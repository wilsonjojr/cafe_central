import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  ALL_CATEGORY,
  TELEGRAM_BOT_URL,
  fetchCatalog,
  filterProductsByCategory,
  normalizePhone,
  socialLinks,
  submitContactForm,
  validateContact,
  type CatalogCategory,
  type CatalogProduct,
} from "@/lib/cafe-data";

const mockOrderMock = vi.fn();
const mockEqMock = vi.fn();
const mockSelectMock = vi.fn();
const mockFromMock = vi.fn();
const mockInvokeMock = vi.fn();

vi.mock("@/integrations/supabase/client", () => ({
  supabase: {
    from: (...args: unknown[]) => mockFromMock(...args),
    functions: {
      invoke: (...args: unknown[]) => mockInvokeMock(...args),
    },
  },
}));

describe("Café Central catalog", () => {
  const sampleCategories: CatalogCategory[] = [
    { id: "cat-1", name: "Cafés quentes", sort_order: 1 },
    { id: "cat-2", name: "Salgados", sort_order: 2 },
  ];

  const sampleProducts: CatalogProduct[] = [
    {
      id: "prod-1",
      category_id: "cat-1",
      name: "Espresso da casa",
      description: "Intenso, aromático e com uma crema perfeita.",
      price: 7.5,
      image_url:
        "https://sjxjlfrquxnpssomjubo.supabase.co/storage/v1/object/public/product-images/cafe-espresso.jpg",
      available: true,
      sort_order: 1,
    },
    {
      id: "prod-2",
      category_id: "cat-2",
      name: "Croissant de manteiga",
      description: "Dourado, delicado e feito para acompanhar seu café.",
      price: 11,
      image_url:
        "https://sjxjlfrquxnpssomjubo.supabase.co/storage/v1/object/public/product-images/cafe-croissant.jpg",
      available: true,
      sort_order: 2,
    },
  ];

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("shows all products when Todos is selected", () => {
    expect(filterProductsByCategory(sampleProducts, sampleCategories, ALL_CATEGORY)).toHaveLength(
      2,
    );
  });

  it("filters products by selected category name", () => {
    const filtered = filterProductsByCategory(sampleProducts, sampleCategories, "Cafés quentes");
    expect(filtered).toHaveLength(1);
    expect(filtered[0]?.name).toBe("Espresso da casa");
  });

  it("returns empty array for unknown category", () => {
    expect(filterProductsByCategory(sampleProducts, sampleCategories, "Inexistente")).toEqual([]);
  });

  it("fetches categories and available products ordered by sort_order from Supabase", async () => {
    mockFromMock.mockImplementation((table: string) => {
      if (table === "categories") {
        return {
          select: mockSelectMock.mockReturnValue({
            order: mockOrderMock.mockReturnValueOnce({
              order: vi.fn().mockResolvedValue({ data: sampleCategories, error: null }),
            }),
          }),
        };
      }
      return {
        select: vi.fn().mockReturnValue({
          eq: mockEqMock.mockReturnValue({
            order: vi.fn().mockReturnValue({
              order: vi.fn().mockResolvedValue({ data: sampleProducts, error: null }),
            }),
          }),
        }),
      };
    });

    const data = await fetchCatalog();
    expect(mockFromMock).toHaveBeenCalledWith("categories");
    expect(mockFromMock).toHaveBeenCalledWith("products");
    expect(mockEqMock).toHaveBeenCalledWith("available", true);
    expect(data.categories).toEqual(sampleCategories);
    expect(data.products).toEqual(sampleProducts);
  });

  it("throws when Supabase returns an error", async () => {
    mockFromMock.mockImplementation((table: string) => {
      if (table === "categories") {
        return {
          select: vi.fn().mockReturnValue({
            order: vi.fn().mockReturnValue({
              order: vi.fn().mockResolvedValue({
                data: null,
                error: { message: "permission denied" },
              }),
            }),
          }),
        };
      }
      return {
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            order: vi.fn().mockReturnValue({
              order: vi.fn().mockResolvedValue({ data: [], error: null }),
            }),
          }),
        }),
      };
    });

    await expect(fetchCatalog()).rejects.toThrow("Erro ao carregar categorias: permission denied");
  });
});

describe("Contact validation and submission", () => {
  const valid = {
    name: "Maria Silva",
    email: "maria@example.com",
    phone: "(85) 99999-1234",
    message: "Gostaria de conhecer a cafeteria.",
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("normalizes phone numbers by stripping non-digit characters", () => {
    expect(normalizePhone("(85) 99999-1234")).toBe("85999991234");
    expect(normalizePhone("+55 85 9 9999-1234")).toBe("5585999991234");
  });

  it("accepts valid contact details", () => {
    expect(validateContact(valid)).toBe(true);
  });

  it.each(["name", "email", "phone", "message"] as const)("rejects empty %s", (field) => {
    expect(validateContact({ ...valid, [field]: "" })).toBe(false);
  });

  it("rejects malformed email", () => {
    expect(validateContact({ ...valid, email: "sem-arroba" })).toBe(false);
  });

  it("rejects incomplete phone", () => {
    expect(validateContact({ ...valid, phone: "123" })).toBe(false);
  });

  it("rejects whitespace-only message", () => {
    expect(validateContact({ ...valid, message: "     " })).toBe(false);
  });

  it("submits normalized contact payload via submit-contact Edge Function", async () => {
    mockInvokeMock.mockResolvedValue({
      data: { ok: true, contactId: "cnt-1", createdAt: "2026-11-17T12:00:00Z" },
      error: null,
    });

    const result = await submitContactForm({
      name: "  Maria Silva  ",
      email: "  maria@example.com  ",
      phone: "(85) 99999-1234",
      message: "  Olá, gostaria de informações!  ",
    });

    expect(mockInvokeMock).toHaveBeenCalledWith("submit-contact", {
      body: {
        name: "Maria Silva",
        email: "maria@example.com",
        phone: "85999991234",
        message: "Olá, gostaria de informações!",
      },
    });
    expect(result.ok).toBe(true);
    expect(result.contactId).toBe("cnt-1");
  });

  it("throws without calling Edge Function when phone or message is invalid", async () => {
    await expect(submitContactForm({ ...valid, phone: "123" })).rejects.toThrow();
    await expect(submitContactForm({ ...valid, message: "   " })).rejects.toThrow();
    expect(mockInvokeMock).not.toHaveBeenCalled();
  });

  it("surfaces a safe error message when Edge Function invocation fails", async () => {
    mockInvokeMock.mockResolvedValue({
      data: null,
      error: new Error("Network failure"),
    });

    await expect(submitContactForm(valid)).rejects.toThrow(
      "Não foi possível enviar sua mensagem no momento. Tente novamente.",
    );
  });
});

describe("Telegram support links", () => {
  it("uses the centralized official Café Central Telegram bot URL", () => {
    expect(TELEGRAM_BOT_URL).toBe("https://t.me/botWillTestN8N_bot");
    expect(socialLinks.telegram).toBe(TELEGRAM_BOT_URL);
  });
});
