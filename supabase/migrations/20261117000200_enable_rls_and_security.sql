-- ============================================================================
-- Café Central — Migration 002: Segurança, RLS e Correção de rls_auto_enable()
-- Projeto Supabase: cafe_central (us-west-2 / ref: sjxjlfrquxnpssomjubo)
-- Executar manualmente no SQL Editor do Supabase após a Migration 001.
-- ============================================================================

BEGIN;

-- 1. Habilitar RLS em todas as tabelas públicas
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interest_products ENABLE ROW LEVEL SECURITY;

-- 2. Defesa em profundidade: restringir privilégios SQL diretos de anon/authenticated
REVOKE ALL ON TABLE public.categories FROM anon, authenticated;
REVOKE ALL ON TABLE public.products FROM anon, authenticated;
REVOKE ALL ON TABLE public.customers FROM anon, authenticated;
REVOKE ALL ON TABLE public.contacts FROM anon, authenticated;
REVOKE ALL ON TABLE public.interests FROM anon, authenticated;
REVOKE ALL ON TABLE public.interest_products FROM anon, authenticated;

GRANT SELECT ON TABLE public.categories TO anon, authenticated;
GRANT SELECT ON TABLE public.products TO anon, authenticated;

-- 3. Políticas RLS — categories
-- Visitantes podem consultar todas as categorias; escrita apenas via contexto privilegiado.
DROP POLICY IF EXISTS "Public can read categories" ON public.categories;
CREATE POLICY "Public can read categories"
  ON public.categories
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- 4. Políticas RLS — products
-- Visitantes podem consultar somente produtos disponíveis (available = true).
-- Produtos indisponíveis continuam no banco, mas invisíveis pela API pública.
DROP POLICY IF EXISTS "Public can read available products" ON public.products;
CREATE POLICY "Public can read available products"
  ON public.products
  FOR SELECT
  TO anon, authenticated
  USING (available = true);

-- 5. Políticas RLS — customers, contacts, interests, interest_products
-- Nenhuma policy é concedida para anon/authenticated nesta etapa (sem login):
--   - Leitura pública bloqueada em todas as quatro tabelas.
--   - Inserção/atualização/exclusão públicas bloqueadas.
--   - O envio seguro de contatos e interesses será feito futuramente via Edge Function
--     usando service_role no servidor, nunca no navegador.

-- 6. Correção de segurança em public.rls_auto_enable()
-- Contexto:
--   Funções criadas no schema public recebem EXECUTE para PUBLIC por padrão no PostgreSQL
--   (o que inclui anon e authenticated no Supabase) e, se não tiverem search_path fixo,
--   geram alertas de exposição pública e search_path mutável no Security Advisor.
--
--   Esta rotina preserva integralmente o corpo da função e o event trigger de RLS automático,
--   apenas:
--     (a) revogando EXECUTE de PUBLIC, anon e authenticated; e
--     (b) fixando search_path = '' na função existente (caso ela exista no projeto).
DO $$
DECLARE
  fn_record record;
  trg_record record;
  v_found boolean := false;
BEGIN
  FOR fn_record IN
    SELECT p.oid, p.oid::regprocedure AS fn_sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'rls_auto_enable'
  LOOP
    v_found := true;
    EXECUTE format(
      'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated',
      fn_record.fn_sig
    );
    EXECUTE format(
      'ALTER FUNCTION %s SET search_path = ''''',
      fn_record.fn_sig
    );
    RAISE NOTICE 'Proteção aplicada em % (corpo preservado)', fn_record.fn_sig;

    FOR trg_record IN
      SELECT evtname, evtevent, evtenabled
      FROM pg_event_trigger
      WHERE evtfoid = fn_record.oid
    LOOP
      RAISE NOTICE 'Event trigger preservado: % (evento: %, status: %)',
        trg_record.evtname, trg_record.evtevent, trg_record.evtenabled;
    END LOOP;
  END LOOP;

  IF NOT v_found THEN
    RAISE NOTICE 'Função public.rls_auto_enable() não encontrada neste projeto.';
  END IF;
END
$$;

COMMIT;
