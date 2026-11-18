-- ============================================================================
-- Café Central — Migration 006: Função transacional submit_contact()
-- Projeto Supabase: cafe_central (us-west-2 / ref: sjxjlfrquxnpssomjubo)
--
-- Objetivo:
--   Executar em uma única transação atômica do PostgreSQL:
--     1. Normalização do telefone (apenas dígitos) e busca com lock (FOR UPDATE).
--     2. Criação do cliente em public.customers se não existir, ou atualização
--        de nome e e-mail com os dados mais recentes se já existir.
--     3. Inserção de um novo registro em public.contacts com consentimento.
--   Caso ocorra falha ao gravar em contacts, toda a operação em customers
--   é revertida automaticamente pela transação.
--
-- Segurança:
--   - RLS permanece inalterado em customers e contacts.
--   - EXECUTE revogado de PUBLIC, anon e authenticated.
--   - EXECUTE concedido exclusivamente para service_role (Edge Function).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.submit_contact(
  p_name text,
  p_email text,
  p_phone text,
  p_message text,
  p_consent boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_name text;
  v_email text;
  v_phone_digits text;
  v_message text;
  v_consent boolean;
  v_customer_id uuid;
  v_contact_id uuid;
  v_created_at timestamptz;
  v_customer_created boolean := false;
BEGIN
  v_name := btrim(COALESCE(p_name, ''));
  v_email := NULLIF(btrim(COALESCE(p_email, '')), '');
  v_phone_digits := regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g');
  v_message := btrim(COALESCE(p_message, ''));
  v_consent := COALESCE(p_consent, true);

  IF char_length(v_name) < 2 THEN
    RAISE EXCEPTION 'Nome deve ter pelo menos 2 caracteres.' USING ERRCODE = '22023';
  END IF;

  IF v_email IS NOT NULL AND v_email !~* '^[^\s@]+@[^\s@]+\.[^\s@]+$' THEN
    RAISE EXCEPTION 'E-mail inválido.' USING ERRCODE = '22023';
  END IF;

  IF char_length(v_phone_digits) < 10 OR char_length(v_phone_digits) > 13 THEN
    RAISE EXCEPTION 'Telefone deve conter entre 10 e 13 dígitos com DDD.' USING ERRCODE = '22023';
  END IF;

  IF char_length(v_message) < 5 THEN
    RAISE EXCEPTION 'Mensagem deve ter pelo menos 5 caracteres.' USING ERRCODE = '22023';
  END IF;

  -- Serializa concorrência pelo mesmo telefone normalizado
  PERFORM pg_advisory_xact_lock(hashtext(v_phone_digits));

  SELECT c.id
  INTO v_customer_id
  FROM public.customers c
  WHERE regexp_replace(c.phone, '\D', '', 'g') = v_phone_digits
  LIMIT 1
  FOR UPDATE;

  IF v_customer_id IS NULL THEN
    INSERT INTO public.customers (name, email, phone)
    VALUES (v_name, v_email, v_phone_digits)
    RETURNING id INTO v_customer_id;

    v_customer_created := true;
  ELSE
    UPDATE public.customers
    SET
      name = v_name,
      email = COALESCE(v_email, email)
    WHERE id = v_customer_id;

    v_customer_created := false;
  END IF;

  INSERT INTO public.contacts (customer_id, message, consent, consent_at)
  VALUES (
    v_customer_id,
    v_message,
    v_consent,
    CASE WHEN v_consent THEN now() ELSE NULL END
  )
  RETURNING id, created_at INTO v_contact_id, v_created_at;

  RETURN jsonb_build_object(
    'customer_id', v_customer_id,
    'contact_id', v_contact_id,
    'created_at', v_created_at,
    'customer_created', v_customer_created
  );
END;
$$;

REVOKE ALL ON FUNCTION public.submit_contact(text, text, text, text, boolean)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.submit_contact(text, text, text, text, boolean)
  TO service_role;

COMMIT;
