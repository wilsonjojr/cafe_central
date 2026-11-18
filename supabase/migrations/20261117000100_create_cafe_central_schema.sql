-- ============================================================================
-- Café Central — Migration 001: Schema, Relacionamentos, Índices e Triggers
-- Projeto Supabase: cafe_central (us-west-2 / ref: sjxjlfrquxnpssomjubo)
-- Executar manualmente no SQL Editor do Supabase.
-- ============================================================================

BEGIN;

-- 1. Tipo enumerado para status de interesses
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'interest_status'
      AND n.nspname = 'public'
  ) THEN
    CREATE TYPE public.interest_status AS ENUM (
      'Pendente',
      'Em atendimento',
      'Concluído'
    );
  END IF;
END
$$;

-- 2. Tabela: categories
CREATE TABLE IF NOT EXISTS public.categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT categories_name_not_blank CHECK (char_length(btrim(name)) > 0),
  CONSTRAINT categories_name_unique UNIQUE (name),
  CONSTRAINT categories_sort_order_non_negative CHECK (sort_order >= 0)
);

-- 3. Tabela: products
CREATE TABLE IF NOT EXISTS public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL,
  name text NOT NULL,
  description text,
  price numeric(10, 2) NOT NULL,
  image_url text,
  available boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT products_category_fkey
    FOREIGN KEY (category_id)
    REFERENCES public.categories (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  CONSTRAINT products_name_not_blank CHECK (char_length(btrim(name)) > 0),
  CONSTRAINT products_price_positive CHECK (price > 0),
  CONSTRAINT products_sort_order_non_negative CHECK (sort_order >= 0),
  CONSTRAINT products_category_name_unique UNIQUE (category_id, name)
);

-- 4. Tabela: customers
CREATE TABLE IF NOT EXISTS public.customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text,
  phone text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT customers_name_min_length CHECK (char_length(btrim(name)) >= 2),
  CONSTRAINT customers_email_format CHECK (
    email IS NULL OR email ~* '^[^\s@]+@[^\s@]+\.[^\s@]+$'
  ),
  CONSTRAINT customers_phone_digits_length CHECK (
    char_length(regexp_replace(phone, '\D', '', 'g')) BETWEEN 10 AND 15
  ),
  CONSTRAINT customers_phone_unique UNIQUE (phone)
);

-- Impede dois clientes com o mesmo número de telefone mesmo com formatação diferente
CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_phone_digits_unique
  ON public.customers ((regexp_replace(phone, '\D', '', 'g')));

-- 5. Tabela: contacts
CREATE TABLE IF NOT EXISTS public.contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL,
  message text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  consent boolean NOT NULL DEFAULT false,
  consent_at timestamptz,
  CONSTRAINT contacts_customer_fkey
    FOREIGN KEY (customer_id)
    REFERENCES public.customers (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  CONSTRAINT contacts_message_not_blank CHECK (char_length(btrim(message)) > 0),
  CONSTRAINT contacts_consent_timestamp_chk CHECK (
    (consent = false AND consent_at IS NULL)
    OR (consent = true AND consent_at IS NOT NULL)
  )
);

-- 6. Tabela: interests
CREATE TABLE IF NOT EXISTS public.interests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL,
  status public.interest_status NOT NULL DEFAULT 'Pendente',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT interests_customer_fkey
    FOREIGN KEY (customer_id)
    REFERENCES public.customers (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
);

-- 7. Tabela intermediária: interest_products
CREATE TABLE IF NOT EXISTS public.interest_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  interest_id uuid NOT NULL,
  product_id uuid NOT NULL,
  CONSTRAINT interest_products_interest_fkey
    FOREIGN KEY (interest_id)
    REFERENCES public.interests (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  CONSTRAINT interest_products_product_fkey
    FOREIGN KEY (product_id)
    REFERENCES public.products (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  CONSTRAINT interest_products_unique_pair UNIQUE (interest_id, product_id)
);

-- 8. Índices para chaves estrangeiras e consultas frequentes
CREATE INDEX IF NOT EXISTS idx_categories_sort_order
  ON public.categories (sort_order, name);

CREATE INDEX IF NOT EXISTS idx_products_category_id
  ON public.products (category_id);

CREATE INDEX IF NOT EXISTS idx_products_available_sort_order
  ON public.products (available, sort_order, name);

CREATE INDEX IF NOT EXISTS idx_contacts_customer_id
  ON public.contacts (customer_id);

CREATE INDEX IF NOT EXISTS idx_contacts_created_at
  ON public.contacts (created_at);

CREATE INDEX IF NOT EXISTS idx_interests_customer_id
  ON public.interests (customer_id);

CREATE INDEX IF NOT EXISTS idx_interests_status_created_at
  ON public.interests (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_interest_products_interest_id
  ON public.interest_products (interest_id);

CREATE INDEX IF NOT EXISTS idx_interest_products_product_id
  ON public.interest_products (product_id);

-- 9. Função e trigger para atualização automática de updated_at em customers
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_customers_set_updated_at ON public.customers;
CREATE TRIGGER trg_customers_set_updated_at
  BEFORE UPDATE ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

COMMIT;
