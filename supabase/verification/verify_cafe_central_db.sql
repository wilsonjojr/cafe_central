-- ============================================================================
-- Café Central — Script de Verificação Pós-Migration (não altera dados persistidos)
-- Executar no SQL Editor do Supabase após rodar as migrations 001 a 004 (e 005).
-- ============================================================================

-- 1. Conferir RLS habilitado em todas as 6 tabelas públicas (assertivo)
DO $$
DECLARE
  v_disabled_tables text;
BEGIN
  SELECT string_agg(t.expected_table, ', ')
  INTO v_disabled_tables
  FROM (
    VALUES
      ('categories'),
      ('products'),
      ('customers'),
      ('contacts'),
      ('interests'),
      ('interest_products')
  ) AS t(expected_table)
  LEFT JOIN pg_tables pt
    ON pt.schemaname = 'public'
   AND pt.tablename = t.expected_table
  WHERE pt.tablename IS NULL
     OR pt.rowsecurity IS DISTINCT FROM true;

  IF v_disabled_tables IS NOT NULL THEN
    RAISE EXCEPTION 'FALHA DE SEGURANÇA: tabelas ausentes ou sem RLS habilitado: %', v_disabled_tables;
  END IF;

  RAISE NOTICE 'OK: RLS habilitado nas 6 tabelas públicas.';
END
$$;

-- 2. Conferir políticas RLS criadas (consulta informativa)
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd
FROM pg_policies
WHERE (schemaname = 'public')
   OR (schemaname = 'storage' AND tablename = 'objects')
ORDER BY schemaname, tablename, policyname;

-- 3. Conferir proteção de public.rls_auto_enable() (sem EXECUTE para PUBLIC/anon/authenticated e search_path fixo)
SELECT
  p.oid::regprocedure AS function_signature,
  p.proconfig AS function_settings,
  has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'rls_auto_enable';

-- 4. Verificar quantidade exata de categorias e produtos após o seed (assertivo)
DO $$
DECLARE
  v_total_categories integer;
  v_total_products integer;
  v_available_products integer;
BEGIN
  SELECT count(*) INTO v_total_categories FROM public.categories;
  SELECT count(*) INTO v_total_products FROM public.products;
  SELECT count(*) INTO v_available_products FROM public.products WHERE available = true;

  IF v_total_categories <> 5 THEN
    RAISE EXCEPTION 'FALHA NO SEED: esperado exatamente 5 categorias, encontrado %.', v_total_categories;
  END IF;

  IF v_total_products <> 10 THEN
    RAISE EXCEPTION 'FALHA NO SEED: esperado exatamente 10 produtos no total, encontrado %.', v_total_products;
  END IF;

  IF v_available_products <> 10 THEN
    RAISE EXCEPTION 'FALHA NO SEED: esperado exatamente 10 produtos disponíveis após o seed, encontrado %.', v_available_products;
  END IF;

  RAISE NOTICE 'OK: exatamente 5 categorias e 10 produtos disponíveis encontrados após o seed.';
END
$$;

-- 5. Verificar existência do bucket product-images e política de leitura pública restrita a esse bucket (assertivo)
DO $$
DECLARE
  v_bucket_public boolean;
  v_read_policy_count integer;
  v_write_policy_count integer;
BEGIN
  SELECT b.public
  INTO v_bucket_public
  FROM storage.buckets b
  WHERE b.id = 'product-images';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FALHA NO STORAGE: bucket "product-images" não existe.';
  END IF;

  IF v_bucket_public IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FALHA NO STORAGE: bucket "product-images" existe, mas não está marcado como público (public = true).';
  END IF;

  SELECT count(*)
  INTO v_read_policy_count
  FROM pg_policies p
  WHERE p.schemaname = 'storage'
    AND p.tablename = 'objects'
    AND p.cmd = 'SELECT'
    AND p.permissive = 'PERMISSIVE'
    AND (p.roles && ARRAY['anon', 'authenticated', 'public']::name[])
    AND COALESCE(p.qual, '') ILIKE '%product-images%';

  IF v_read_policy_count < 1 THEN
    RAISE EXCEPTION 'FALHA NO STORAGE: nenhuma política SELECT de leitura pública restrita ao bucket "product-images" encontrada em storage.objects.';
  END IF;

  SELECT count(*)
  INTO v_write_policy_count
  FROM pg_policies p
  WHERE p.schemaname = 'storage'
    AND p.tablename = 'objects'
    AND p.cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
    AND (p.roles && ARRAY['anon', 'authenticated', 'public']::name[])
    AND (
      COALESCE(p.qual, '') ILIKE '%product-images%'
      OR COALESCE(p.with_check, '') ILIKE '%product-images%'
    );

  IF v_write_policy_count > 0 THEN
    RAISE EXCEPTION 'FALHA DE SEGURANÇA NO STORAGE: encontrada política pública de escrita (%) em storage.objects para "product-images".', v_write_policy_count;
  END IF;

  RAISE NOTICE 'OK: bucket público "product-images" configurado com leitura pública restrita ao bucket e escrita bloqueada.';
END
$$;

-- 6. Testes funcionais de visibilidade (anon), RLS privado e integridade em transação revertida (ROLLBACK)
BEGIN;

-- Marcar temporariamente 'Espresso da casa' como indisponível (revertido pelo ROLLBACK)
UPDATE public.products
SET available = false
WHERE name = 'Espresso da casa';

-- 6a. Simular usuário anônimo (anon)
SET LOCAL ROLE anon;

DO $$
DECLARE
  v_anon_categories integer;
  v_anon_products integer;
  v_espresso_visible integer;
BEGIN
  SELECT count(*) INTO v_anon_categories FROM public.categories;
  SELECT count(*) INTO v_anon_products FROM public.products;
  SELECT count(*) INTO v_espresso_visible
  FROM public.products
  WHERE name = 'Espresso da casa';

  IF v_anon_categories <> 5 THEN
    RAISE EXCEPTION 'FALHA ANON: esperado 5 categorias visíveis para anon, encontrado %.', v_anon_categories;
  END IF;

  IF v_espresso_visible <> 0 THEN
    RAISE EXCEPTION 'FALHA DE RLS: produto "Espresso da casa" continuou visível para anon mesmo com available = false.';
  END IF;

  IF v_anon_products <> 9 THEN
    RAISE EXCEPTION 'FALHA DE RLS: esperado exatamente 9 produtos visíveis para anon com "Espresso da casa" indisponível, encontrado %.', v_anon_products;
  END IF;

  RAISE NOTICE 'OK: anon enxerga 5 categorias, "Espresso da casa" ficou invisível (available = false) e os demais 9 produtos permaneceram visíveis.';

  -- Bloqueio de leitura pública nas quatro tabelas privadas:
  -- customers, contacts, interests e interest_products
  BEGIN
    PERFORM count(*) FROM public.customers;
    RAISE EXCEPTION 'FALHA DE SEGURANÇA: anon conseguiu consultar public.customers';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: leitura pública bloqueada em public.customers';
  END;

  BEGIN
    PERFORM count(*) FROM public.contacts;
    RAISE EXCEPTION 'FALHA DE SEGURANÇA: anon conseguiu consultar public.contacts';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: leitura pública bloqueada em public.contacts';
  END;

  BEGIN
    PERFORM count(*) FROM public.interests;
    RAISE EXCEPTION 'FALHA DE SEGURANÇA: anon conseguiu consultar public.interests';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: leitura pública bloqueada em public.interests';
  END;

  BEGIN
    PERFORM count(*) FROM public.interest_products;
    RAISE EXCEPTION 'FALHA DE SEGURANÇA: anon conseguiu consultar public.interest_products';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: leitura pública bloqueada em public.interest_products';
  END;
END
$$;

RESET ROLE;

-- 6b. Testar integridade referencial, ON DELETE RESTRICT e trigger updated_at (dados fictícios revertidos ao final)
DO $$
DECLARE
  v_customer_id uuid;
  v_category_id uuid;
  v_product_id uuid;
  v_interest_id uuid;
  v_updated_before timestamptz;
  v_updated_after timestamptz;
BEGIN
  SELECT id INTO v_category_id FROM public.categories LIMIT 1;
  SELECT id INTO v_product_id FROM public.products LIMIT 1;

  INSERT INTO public.customers (name, email, phone, updated_at)
  VALUES ('Cliente Teste', 'teste@exemplo.invalid', '(85) 99999-0000', now() - interval '5 minutes')
  RETURNING id, updated_at INTO v_customer_id, v_updated_before;

  UPDATE public.customers
  SET name = 'Cliente Teste Atualizado'
  WHERE id = v_customer_id
  RETURNING updated_at INTO v_updated_after;

  IF v_updated_after <= v_updated_before THEN
    RAISE EXCEPTION 'FALHA: trigger updated_at não atualizou customers.updated_at';
  END IF;
  RAISE NOTICE 'OK: trigger updated_at funcionou corretamente';

  -- Bloquear telefone duplicado com formatação diferente
  BEGIN
    INSERT INTO public.customers (name, phone)
    VALUES ('Duplicado', '85999990000');
    RAISE EXCEPTION 'FALHA: telefone duplicado não foi bloqueado';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: telefone duplicado bloqueado mesmo com formatação diferente';
  END;

  -- Criar contato e interesse ligados ao cliente e produto
  INSERT INTO public.contacts (customer_id, message, consent, consent_at)
  VALUES (v_customer_id, 'Mensagem de teste automatizado.', true, now());

  INSERT INTO public.interests (customer_id, status)
  VALUES (v_customer_id, 'Pendente')
  RETURNING id INTO v_interest_id;

  INSERT INTO public.interest_products (interest_id, product_id)
  VALUES (v_interest_id, v_product_id);

  -- Bloquear duplicação do mesmo produto no mesmo interesse
  BEGIN
    INSERT INTO public.interest_products (interest_id, product_id)
    VALUES (v_interest_id, v_product_id);
    RAISE EXCEPTION 'FALHA: duplicação em interest_products não foi bloqueada';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: duplicação em interest_products bloqueada';
  END;

  -- Bloquear exclusão de categoria com produtos
  BEGIN
    DELETE FROM public.categories WHERE id = v_category_id;
    RAISE EXCEPTION 'FALHA: categoria com produtos foi excluída';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK: exclusão de categoria com produtos bloqueada';
  END;

  -- Bloquear exclusão de produto com interesses
  BEGIN
    DELETE FROM public.products WHERE id = v_product_id;
    RAISE EXCEPTION 'FALHA: produto com interesses foi excluído';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK: exclusão de produto com interesses bloqueada';
  END;

  -- Bloquear exclusão de cliente com contatos/interesses
  BEGIN
    DELETE FROM public.customers WHERE id = v_customer_id;
    RAISE EXCEPTION 'FALHA: cliente com histórico foi excluído';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK: exclusão de cliente com histórico bloqueada';
  END;
END
$$;

ROLLBACK;
