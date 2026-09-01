import { z } from "zod";
import {
  campoIdSchema,
  coordinadorIdSchema,
  formularioDiligenciadoIdSchema,
  formularioIdSchema,
  respuestaIdSchema,
  solicitudIdSchema,
  visitaRealizadaIdSchema,
} from "../brands.js";
import { geoPointSchema, resultadoEvaluacionSchema } from "../domain/estados.js";
import type { EstadoFormulario } from "../domain/formulario.js";

export const estadoFormularioDefSchema = z.enum([
  "borrador",
  "publicado",
  "archivado",
]);

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
  .object({
    visitaRealizadaId: visitaRealizadaIdSchema.optional(),
    codigoFormulario: z.string().min(1).optional(),
    solicitudId: solicitudIdSchema.optional(),
    version: z.number().int().positive().optional(),
  })
  .strict()
  .refine(
    (val) =>
      val.visitaRealizadaId !== undefined || val.codigoFormulario !== undefined,
    { message: "debe especificar visitaRealizadaId o codigoFormulario" },
  );

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

export const crearFormularioInput = z
  .object({
    codigo: z.string().min(1),
    nombre: z.string().min(1),
    descripcion: z.string().optional(),
  })
  .strict();

export const publicarFormularioInput = z
  .object({ formularioId: formularioIdSchema })
  .strict();

export const archivarFormularioInput = z
  .object({ formularioId: formularioIdSchema })
  .strict();

export const crearNuevaVersionFormularioInput = z
  .object({ codigo: z.string().min(1) })
  .strict();

export const agregarCampoInput = z
  .object({
    formularioId: formularioIdSchema,
    codigo: z.string().min(1),
    tipo: tipoCampoSchema,
    prompt: z.string().min(1),
    orden: z.number().int(),
    obligatorio: z.boolean().default(true),
    cardinalidad: cardinalidadCampoSchema.default("uno"),
    opciones: z.array(opcionCampoSchema).optional(),
  })
  .strict();

export const registrarCoordinadorInput = z
  .object({
    nombre: z.string().min(1),
    cargo: z.string().optional(),
  })
  .strict();

export const coordinadorFilaSchema = z.object({
  id: coordinadorIdSchema,
  auth_user_id: z.string().uuid(),
  nombre: z.string(),
  cargo: z.string().nullable().optional(),
  created_at: z.string(),
});

const estadoBaseSchema = z.object({
  ok: z.boolean(),
  error: z.string().optional(),
  id: formularioDiligenciadoIdSchema,
  visita_realizada_id: visitaRealizadaIdSchema.nullable().optional(),
  formulario_id: formularioIdSchema,
  formulario_codigo: z.string().optional(),
  formulario_version: z.number().int().optional(),
  solicitud_id: solicitudIdSchema.nullable().optional(),
  autor_id: z.string().uuid().nullable().optional(),
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
    formularioId: raw.formulario_id,
    formularioCodigo: raw.formulario_codigo,
    formularioVersion: raw.formulario_version,
    visitaRealizadaId: raw.visita_realizada_id ?? null,
    solicitudId: raw.solicitud_id ?? null,
    autorId: raw.autor_id ?? null,
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
