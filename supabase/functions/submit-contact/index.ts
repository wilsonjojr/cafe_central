/* global Deno */
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function normalizePhone(phone: string): string {
  return phone.replace(/\D/g, "");
}

function validateInput(body: unknown):
  | {
      ok: true;
      data: { name: string; email: string; phone: string; message: string };
    }
  | { ok: false; error: string } {
  if (!body || typeof body !== "object") {
    return { ok: false, error: "Dados do formulário inválidos." };
  }

  const record = body as Record<string, unknown>;
  const name = typeof record.name === "string" ? record.name.trim() : "";
  const email = typeof record.email === "string" ? record.email.trim() : "";
  const rawPhone = typeof record.phone === "string" ? record.phone.trim() : "";
  const phone = normalizePhone(rawPhone);
  const message = typeof record.message === "string" ? record.message.trim() : "";

  if (name.length < 2 || name.length > 120) {
    return { ok: false, error: "Informe seu nome com pelo menos 2 letras." };
  }

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 160) {
    return { ok: false, error: "Informe um endereço de e-mail válido." };
  }

  if (phone.length < 10 || phone.length > 13) {
    return { ok: false, error: "Informe um telefone/WhatsApp válido com DDD." };
  }

  if (message.length < 5 || message.length > 2000) {
    return { ok: false, error: "Escreva uma mensagem com pelo menos 5 caracteres." };
  }

  return { ok: true, data: { name, email, phone, message } };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Método não permitido." });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "Corpo da requisição inválido." });
  }

  const validation = validateInput(body);
  if (!validation.ok) {
    return jsonResponse(400, { error: validation.error });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    console.error(
      "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in Edge Function environment.",
    );
    return jsonResponse(500, {
      error: "Não foi possível enviar sua mensagem no momento. Tente novamente em instantes.",
    });
  }

  const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      storage: undefined,
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const { data, error } = await supabaseAdmin.rpc("submit_contact", {
    p_name: validation.data.name,
    p_email: validation.data.email,
    p_phone: validation.data.phone,
    p_message: validation.data.message,
    p_consent: true,
  });

  if (error || !data || typeof data !== "object") {
    console.error("submit-contact rpc failure:", error?.code ?? "unknown");
    return jsonResponse(500, {
      error: "Não foi possível registrar seu contato agora. Tente novamente em instantes.",
    });
  }

  const result = data as { contact_id?: string; created_at?: string };
  return jsonResponse(201, {
    ok: true,
    contactId: result.contact_id ?? null,
    createdAt: result.created_at ?? null,
  });
});
