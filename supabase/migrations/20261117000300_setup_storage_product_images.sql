-- ============================================================================
-- Café Central — Migration 003: Supabase Storage (bucket product-images)
-- Projeto Supabase: cafe_central (us-west-2 / ref: sjxjlfrquxnpssomjubo)
-- Executar manualmente no SQL Editor do Supabase após a Migration 002.
--
-- COMO CRIAR A POLÍTICA DE LEITURA PELO PAINEL DO SUPABASE (SE NECESSÁRIO):
--   Caso o SQL Editor não tenha permissão de proprietário em storage.objects
--   ("must be owner of table objects"), o bucket abaixo ainda será criado/atualizado
--   normalmente, e você deverá criar a política pelo painel:
--     1. Acesse Storage -> Policies no painel do Supabase.
--     2. Em "storage.objects" (ou no bucket "product-images"), clique em "New policy".
--     3. Escolha "For full customization" (Create a policy from scratch).
--     4. Configure:
--        - Policy name: Public read access for product-images
--        - Allowed operation: SELECT (marque SOMENTE SELECT; não marque INSERT/UPDATE/DELETE)
--        - Target roles: anon, authenticated (ou public)
--        - USING expression: bucket_id = 'product-images'
--     5. Salve a política e execute o verify_cafe_central_db.sql para confirmar.
-- ============================================================================

BEGIN;

-- 1. Criar/atualizar o bucket público product-images
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'product-images',
  'product-images',
  true,
  5242880, -- 5 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. Permitir leitura pública apenas dos objetos do bucket product-images
-- Operações de escrita (INSERT, UPDATE, DELETE) não recebem policy para anon/authenticated,
-- ficando restritas ao painel do Supabase ou contexto administrativo (service_role).
-- O bloco trata insufficient_privilege para não reverter a criação do bucket caso
-- o executor do SQL Editor não seja proprietário de storage.objects.
DO $$
BEGIN
  EXECUTE 'DROP POLICY IF EXISTS "Public read access for product-images" ON storage.objects';
  EXECUTE '
    CREATE POLICY "Public read access for product-images"
      ON storage.objects
      FOR SELECT
      TO anon, authenticated
      USING (bucket_id = ''product-images'')
  ';
  RAISE NOTICE 'Política de leitura pública criada em storage.objects para product-images.';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'Sem permissão de proprietário para alterar storage.objects via SQL Editor. Bucket product-images preservado; crie a política SELECT (bucket_id = ''product-images'') manualmente em Storage -> Policies conforme instruções no cabeçalho deste arquivo.';
END
$$;

COMMIT;
