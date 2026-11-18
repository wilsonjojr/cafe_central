import { FunctionsHttpError } from "@supabase/supabase-js";
import { supabase } from "@/integrations/supabase/client";
import type { Tables } from "@/integrations/supabase/types";

export const ALL_CATEGORY = "Todos";

export type CatalogCategory = Pick<Tables<"categories">, "id" | "name" | "sort_order">;
export type CatalogProduct = Pick<
  Tables<"products">,
  "id" | "category_id" | "name" | "description" | "price" | "image_url" | "available" | "sort_order"
>;

export interface CatalogData {
  categories: CatalogCategory[];
  products: CatalogProduct[];
}

export interface ContactInput {
  name: string;
  email: string;
  phone: string;
  message: string;
}

export interface SubmitContactResult {
  ok: true;
  contactId: string | null;
  createdAt: string | null;
}

export const TELEGRAM_BOT_URL = "https://t.me/botWillTestN8N_bot";

export const socialLinks = {
  // Provisional Instagram link: replace with the café's real profile when available.
  instagram: "https://www.instagram.com/cafecentral.exemplo/",
  telegram: TELEGRAM_BOT_URL,
};

export async function fetchCatalog(): Promise<CatalogData> {
  const [categoriesResult, productsResult] = await Promise.all([
    supabase
      .from("categories")
      .select("id, name, sort_order")
      .order("sort_order", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("products")
      .select("id, category_id, name, description, price, image_url, available, sort_order")
      .eq("available", true)
      .order("sort_order", { ascending: true })
      .order("name", { ascending: true }),
  ]);

  if (categoriesResult.error) {
    throw new Error(`Erro ao carregar categorias: ${categoriesResult.error.message}`);
  }

  if (productsResult.error) {
    throw new Error(`Erro ao carregar produtos: ${productsResult.error.message}`);
  }

  const categories = categoriesResult.data ?? [];
  const products = (productsResult.data ?? []).map((product) => ({
    ...product,
    price: Number(product.price),
  }));

  return { categories, products };
}

export function filterProductsByCategory(
  products: readonly CatalogProduct[],
  categories: readonly CatalogCategory[],
  selectedCategory: string,
): CatalogProduct[] {
  if (selectedCategory === ALL_CATEGORY) {
    return [...products];
  }

  const matchedCategory = categories.find((category) => category.name === selectedCategory);
  if (!matchedCategory) {
    return [];
  }

  return products.filter((product) => product.category_id === matchedCategory.id);
}

export function normalizePhone(phone: string): string {
  return phone.replace(/\D/g, "");
}

export function validateContact(values: ContactInput) {
  const digits = normalizePhone(values.phone);
  return (
    values.name.trim().length >= 2 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(values.email.trim()) &&
    digits.length >= 10 &&
    digits.length <= 13 &&
    values.message.trim().length >= 5
  );
}

export async function submitContactForm(values: ContactInput): Promise<SubmitContactResult> {
  if (!validateContact(values)) {
    throw new Error(
      "Confira seus dados: nome com pelo menos 2 letras, e-mail válido, telefone com DDD e mensagem com pelo menos 5 caracteres.",
    );
  }

  const { data, error } = await supabase.functions.invoke<SubmitContactResult | { error?: string }>(
    "submit-contact",
    {
      body: {
        name: values.name.trim(),
        email: values.email.trim(),
        phone: normalizePhone(values.phone),
        message: values.message.trim(),
      },
    },
  );

  if (error) {
    if (error instanceof FunctionsHttpError) {
      try {
        const body = (await error.context.json()) as { error?: unknown };
        if (typeof body?.error === "string" && body.error.trim().length > 0) {
          throw new Error(body.error);
        }
      } catch (parseErr) {
        if (parseErr instanceof Error && parseErr.message !== "Unexpected end of JSON input") {
          throw parseErr;
        }
      }
    }
    throw new Error("Não foi possível enviar sua mensagem no momento. Tente novamente.");
  }

  if (!data || !("ok" in data) || !data.ok) {
    const fallbackError =
      data && "error" in data && typeof data.error === "string"
        ? data.error
        : "Não foi possível confirmar o envio da mensagem. Tente novamente.";
    throw new Error(fallbackError);
  }

  return data;
}
