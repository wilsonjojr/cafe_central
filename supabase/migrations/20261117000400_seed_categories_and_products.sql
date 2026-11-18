-- ============================================================================
-- Café Central — Migration 004: Seed das 5 categorias e 10 produtos iniciais
-- Fonte dos dados: src/lib/cafe-data.ts
-- Executar manualmente no SQL Editor do Supabase após a Migration 003.
--
-- Nota sobre image_url:
--   As imagens são mantidas inicialmente como NULL até que os 10 arquivos .jpg
--   originais sejam enviados para o bucket 'product-images'. Em seguida, execute
--   a Migration 005 para vincular as URLs públicas do Storage sem deixar
--   referências antigas (/ __l5e/...) nem inventar URLs.
-- ============================================================================

BEGIN;

-- 1. Inserir as 5 categorias iniciais
INSERT INTO public.categories (name, sort_order)
VALUES
  ('Cafés quentes', 1),
  ('Cafés gelados', 2),
  ('Outras bebidas', 3),
  ('Doces e sobremesas', 4),
  ('Salgados', 5)
ON CONFLICT (name) DO UPDATE SET
  sort_order = EXCLUDED.sort_order;

-- 2. Inserir os 10 produtos iniciais preservando nomes, descrições, preços e categorias
WITH seed_products (category_name, name, description, price, sort_order) AS (
  VALUES
    ('Cafés quentes', 'Espresso da casa', 'Intenso, aromático e com uma crema perfeita.', 7.50::numeric(10, 2), 1),
    ('Cafés quentes', 'Cappuccino clássico', 'Espresso, leite cremoso e um toque de carinho.', 12.00::numeric(10, 2), 2),
    ('Cafés gelados', 'Latte gelado', 'Café, leite e gelo. Leve e refrescante.', 14.00::numeric(10, 2), 3),
    ('Cafés gelados', 'Cold brew', 'Extraído a frio, suave e naturalmente adocicado.', 13.00::numeric(10, 2), 4),
    ('Outras bebidas', 'Chocolate quente', 'Chocolate de verdade, cremoso e aconchegante.', 14.00::numeric(10, 2), 5),
    ('Outras bebidas', 'Chá da tarde', 'Uma infusão delicada para desacelerar o dia.', 9.00::numeric(10, 2), 6),
    ('Doces e sobremesas', 'Bolo de chocolate', 'Massa fofinha e uma generosa cobertura.', 16.00::numeric(10, 2), 7),
    ('Doces e sobremesas', 'Brownie artesanal', 'Casquinha crocante e chocolate a cada pedaço.', 12.00::numeric(10, 2), 8),
    ('Salgados', 'Croissant de manteiga', 'Dourado, delicado e feito para acompanhar seu café.', 11.00::numeric(10, 2), 9),
    ('Salgados', 'Pão rústico da casa', 'Fermentação lenta, casca crocante e miolo macio.', 10.00::numeric(10, 2), 10)
)
INSERT INTO public.products (category_id, name, description, price, image_url, available, sort_order)
SELECT
  c.id,
  s.name,
  s.description,
  s.price,
  NULL,
  true,
  s.sort_order
FROM seed_products s
JOIN public.categories c ON c.name = s.category_name
ON CONFLICT (category_id, name) DO UPDATE SET
  description = EXCLUDED.description,
  price = EXCLUDED.price,
  available = EXCLUDED.available,
  sort_order = EXCLUDED.sort_order;

COMMIT;
