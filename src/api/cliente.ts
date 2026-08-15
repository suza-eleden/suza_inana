import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../generated/database.js";

export function clienteApi(
  url: string,
  publishableKey: string,
): SupabaseClient<Database> {
  return createClient<Database>(url, publishableKey);
}
