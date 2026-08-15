import { z } from "zod";
import {
  campoIdSchema,
  formularioDiligenciadoIdSchema,
  formularioIdSchema,
  respuestaIdSchema,
  visitaRealizadaIdSchema,
} from "../brands.js";
import { geoPointSchema, resultadoEvaluacionSchema } from "../domain/estados.js";
import type { EstadoFormulario } from "../domain/formulario.js";

export const tipoCampoSchema = z.enum([
  "texto",
  "likert",
  "opcion",
  "imagen",
  "geolocalizacion",
]);

export const cardinalidadCampoSchema = z.enum(["uno", "muchos"]);

export const opcionCampoSchema = z.object({
  valor: z.number(),
  etiqueta: z.string(),
});

const campoComun = {
  id: campoIdSchema,
  codigo: z.string(),
  prompt: z.string(),
  orden: z.number().int(),
  obligatorio: z.boolean(),
};

export const campoPublicoSchema = z.discriminatedUnion("tipo", [
  z.object({
    ...campoComun,
    tipo: z.literal("texto"),
    cardinalidad: z.literal("uno"),
    opciones: z.null(),
  }),
  z.object({
    ...campoComun,
    tipo: z.literal("likert"),
    cardinalidad: z.literal("uno"),
    opciones: z.array(opcionCampoSchema).min(1),
  }),
  z.object({
    ...campoComun,
    tipo: z.literal("opcion"),
    cardinalidad: cardinalidadCampoSchema,
    opciones: z.array(opcionCampoSchema).min(1),
  }),
  z.object({
    ...campoComun,
    tipo: z.literal("imagen"),
    cardinalidad: cardinalidadCampoSchema,
    opciones: z.null(),
  }),
  z.object({
    ...campoComun,
    tipo: z.literal("geolocalizacion"),
    cardinalidad: z.literal("uno"),
    opciones: z.null(),
  }),
]);

export const valorTextoSchema = z.object({ texto: z.string().min(1) }).strict();
export const valorCodigoSchema = z.object({ valor: z.number() }).strict();
export const valorImagenSchema = z
  .object({ storage_path: z.string().min(1) })
  .strict();
export const valorGeoSchema = geoPointSchema.strict();
export const valorRespuestaSchema = z.union([
  valorTextoSchema,
  valorCodigoSchema,
  valorImagenSchema,
  valorGeoSchema,
]);
export type ValorRespuesta = z.infer<typeof valorRespuestaSchema>;

export const iniciarFormularioInput = z
  .object({ visitaRealizadaId: visitaRealizadaIdSchema })
  .strict();

export const formularioDiligenciadoIdInput = z
  .object({ formularioDiligenciadoId: formularioDiligenciadoIdSchema })
  .strict();

export const responderCampoInput = z
  .object({
    formularioDiligenciadoId: formularioDiligenciadoIdSchema,
    campoId: campoIdSchema,
    valor: valorRespuestaSchema,
    respuestaId: respuestaIdSchema.optional(),
  })
  .strict();

const estadoBaseSchema = z.object({
  ok: z.boolean(),
  error: z.string().optional(),
  id: formularioDiligenciadoIdSchema,
  visita_realizada_id: visitaRealizadaIdSchema,
  formulario_id: formularioIdSchema,
  campo_actual_id: campoIdSchema.nullable(),
  campo_siguiente_id: campoIdSchema.nullable(),
  campo_actual: campoPublicoSchema.nullable(),
  campo_siguiente: campoPublicoSchema.nullable(),
  campos_diligenciados: z.array(campoIdSchema),
  congelado: z.boolean(),
  completo_obligatorio: z.boolean(),
  resultado: resultadoEvaluacionSchema.optional(),
});

export const estadoFormularioHttpSchema = estadoBaseSchema;

export function estadoFromHttp(
  raw: z.infer<typeof estadoBaseSchema>,
): EstadoFormulario {
  return {
    ok: raw.ok,
    error: raw.error,
    id: raw.id,
    visitaRealizadaId: raw.visita_realizada_id,
    campoActual: raw.campo_actual,
    campoSiguiente: raw.campo_siguiente,
    camposDiligenciados: raw.campos_diligenciados,
    congelado: raw.congelado,
    completoObligatorio: raw.completo_obligatorio,
    resultado: raw.resultado,
  };
}

export const respuestasFormularioHttpSchema = z.object({
  ok: z.literal(true),
  formulario_diligenciado_id: formularioDiligenciadoIdSchema,
  congelado: z.boolean(),
  respuestas: z.array(
    z.object({
      id: respuestaIdSchema,
      campo_id: campoIdSchema,
      codigo: z.string(),
      tipo: tipoCampoSchema,
      valor: z.unknown(),
      created_at: z.string(),
    }),
  ),
});
