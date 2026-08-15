/**
 * Única puerta donde JSON.parse existe. El resto del programa recibe `unknown`
 * y lo pasa por Zod. Ver King, "Parse, don't validate" (2019).
 */
import type { Json } from "../generated/database.js";

export function decodeJson(raw: string): unknown {
  return JSON.parse(raw);
}

export function encodeJson(value: unknown): Json {
  return JSON.parse(JSON.stringify(value)) as Json;
}
