import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../generated/database.js";
import {
  parseFiltroEvaluadores,
  parseFiltroSolicitudes,
  parseFiltroVisitas,
  parseSolicitudFilas,
  parseVisitaFilas,
} from "../frontier/index.js";
import { z } from "zod";
import { evaluadorIdSchema } from "../frontier/http.js";
import { tipoEvaluadorSchema } from "../domain/estados.js";
import { geoFromPostgis, ventanaFromDb } from "../frontier/db.js";

export async function listarSolicitudes(
  client: SupabaseClient<Database>,
  query: unknown,
) {
  const filtro = parseFiltroSolicitudes(query);
  let consulta = client
    .from("solicitudes")
    .select("*")
    .order("id")
    .limit(filtro.limit);
  if (filtro.estado !== undefined) {
    consulta = consulta.eq("estado", filtro.estado);
  }
  if (filtro.talla !== undefined) {
    consulta = consulta.eq("talla", filtro.talla);
  }
  if (filtro.cursor !== undefined) {
    consulta = consulta.gt("id", filtro.cursor);
  }
  const { data, error } = await consulta;
  if (error) {
    throw error;
  }
  return parseSolicitudFilas(data);
}

export async function listarVisitas(
  client: SupabaseClient<Database>,
  query: unknown,
) {
  const filtro = parseFiltroVisitas(query);
  let consulta = client
    .from("visitas_potenciales_api")
    .select("*")
    .order("id")
    .limit(filtro.limit);
  if (filtro.estado !== undefined) {
    consulta = consulta.eq("estado", filtro.estado);
  }
  if (filtro.evaluadorId !== undefined) {
    consulta = consulta.eq("evaluador_id", filtro.evaluadorId);
  }
  if (filtro.solicitudId !== undefined) {
    consulta = consulta.eq("solicitud_id", filtro.solicitudId);
  }
  if (filtro.cursor !== undefined) {
    consulta = consulta.gt("id", filtro.cursor);
  }
  const { data, error } = await consulta;
  if (error) {
    throw error;
  }
  return parseVisitaFilas(data);
}

const evaluadorFilaSchema = z.object({
  id: evaluadorIdSchema,
  tipo: tipoEvaluadorSchema,
  transporte_propio: z.boolean(),
  radio_metros: z.number().int().positive(),
  score_confianza: z.number().min(0.05).max(0.95),
  ubicacion_base: geoFromPostgis,
  ventana: ventanaFromDb,
});

export async function listarEvaluadores(
  client: SupabaseClient<Database>,
  query: unknown,
) {
  const filtro = parseFiltroEvaluadores(query);
  let consulta = client
    .from("evaluadores")
    .select(
      "id, tipo, transporte_propio, radio_metros, score_confianza, ubicacion_base, ventana",
    )
    .order("id")
    .limit(filtro.limit);
  if (filtro.tipo !== undefined) {
    consulta = consulta.eq("tipo", filtro.tipo);
  }
  if (filtro.cursor !== undefined) {
    consulta = consulta.gt("id", filtro.cursor);
  }
  const { data, error } = await consulta;
  if (error) {
    throw error;
  }
  return evaluadorFilaSchema.array().parse(data);
}
