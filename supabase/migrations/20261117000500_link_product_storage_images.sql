-- ============================================================================
-- Café Central — Migration 005: Vincular image_url após upload no Storage
-- Projeto Supabase: cafe_central (us-west-2 / ref: sjxjlfrquxnpssomjubo)
--
-- ATENÇÃO — PRÉ-REQUISITO EXTERNO OBRIGATÓRIO:
--   Execute esta migration SOMENTE DEPOIS de fazer o upload manual dos 10
--   arquivos .jpg originais (nomes definidos em src/assets/*.asset.json) para
--   a raiz do bucket 'product-images' no painel do Supabase Storage:
--     1. cafe-espresso.jpg
--     2. cafe-cappuccino.jpg
--     3. cafe-iced-latte.jpg
--     4. cafe-cold-brew.jpg
--     5. cafe-chocolate.jpg
--     6. cafe-tea.jpg
--     7. cafe-cake.jpg
--     8. cafe-brownie.jpg
--     9. cafe-croissant.jpg
--    10. cafe-cheese-bread.jpg
-- ============================================================================

BEGIN;

DO $$
DECLARE
  missing_list text;
BEGIN
  SELECT string_agg(m.object_name, ', ')
  INTO missing_list
  FROM (
    VALUES
      ('cafe-espresso.jpg'),
      ('cafe-cappuccino.jpg'),
      ('cafe-iced-latte.jpg'),
      ('cafe-cold-brew.jpg'),
      ('cafe-chocolate.jpg'),
      ('cafe-tea.jpg'),
      ('cafe-cake.jpg'),
      ('cafe-brownie.jpg'),
      ('cafe-croissant.jpg'),
      ('cafe-cheese-bread.jpg')
  ) AS m(object_name)
  LEFT JOIN storage.objects o
    ON o.bucket_id = 'product-images'
   AND o.name = m.object_name
  WHERE o.id IS NULL;

  IF missing_list IS NOT NULL THEN
    RAISE EXCEPTION
      'Upload pendente no bucket product-images. Arquivos ausentes: %',
      missing_list;
  END IF;
END
$$;

WITH image_map (product_name, object_name) AS (
  VALUES
    ('Espresso da casa', 'cafe-espresso.jpg'),
    ('Cappuccino clássico', 'cafe-cappuccino.jpg'),
    ('Latte gelado', 'cafe-iced-latte.jpg'),
    ('Cold brew', 'cafe-cold-brew.jpg'),
    ('Chocolate quente', 'cafe-chocolate.jpg'),
    ('Chá da tarde', 'cafe-tea.jpg'),
    ('Bolo de chocolate', 'cafe-cake.jpg'),
    ('Brownie artesanal', 'cafe-brownie.jpg'),
    ('Croissant de manteiga', 'cafe-croissant.jpg'),
    ('Pão rústico da casa', 'cafe-cheese-bread.jpg')
)
UPDATE public.products p
SET image_url = 'https://sjxjlfrquxnpssomjubo.supabase.co/storage/v1/object/public/product-images/' || m.object_name
FROM image_map m
WHERE p.name = m.product_name;

COMMIT;
