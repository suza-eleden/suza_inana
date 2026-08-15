import { z } from "zod";
import {
  evaluadorIdSchema,
  personaIdSchema,
  solicitudIdSchema,
  visitaPotencialIdSchema,
  visitaRealizadaIdSchema,
} from "../brands.js";
import {
  causaCancelacionSchema,
  geoPointSchema,
  pinPlanoSchema,
  resultadoEvaluacionSchema,
  tallaSchema,
  tipoEvaluadorSchema,
  ventanaSchema,
  visitaPotencialEstadoSchema,
  solicitudEstadoSchema,
} from "../domain/estados.js";

export const crearSolicitudInput = z
  .object({
    lng: z.number().gte(-180).lte(180),
    lat: z.number().gte(-90).lte(90),
    talla: tallaSchema,
    ventana: ventanaSchema,
  })
  .strict();
export type CrearSolicitudInput = z.infer<typeof crearSolicitudInput>;

export const registrarEvaluadorInput = z
  .object({
    tipo: tipoEvaluadorSchema,
    tarjetaProfesionalPath: z.string().min(1),
    transportePropio: z.boolean(),
    lng: z.number().gte(-180).lte(180),
    lat: z.number().gte(-90).lte(90),
    radioMetros: z.number().int().positive().max(200000),
    ventana: ventanaSchema,
  })
  .strict();
export type RegistrarEvaluadorInput = z.infer<typeof registrarEvaluadorInput>;

export const registrarPersonaInput = z.object({
  nombre: z.string().min(1),
  telefono: z.string().min(1).optional(),
});

export const visitaIdInput = z.object({
  visitaId: visitaPotencialIdSchema,
});

export const verificarPinInput = z.object({
  visitaId: visitaPotencialIdSchema,
  pin: pinPlanoSchema,
});

export const concluirVisitaInput = z.object({
  visitaRealizadaId: visitaRealizadaIdSchema,
  resultado: resultadoEvaluacionSchema,
  anotaciones: z.string(),
});

export const calificarInput = z.object({
  solicitudId: solicitudIdSchema,
  evaluadorId: evaluadorIdSchema,
  estrellas: z.number().int().min(1).max(5),
});

export const filtroListaSolicitudes = z.object({
  estado: solicitudEstadoSchema.optional(),
  talla: tallaSchema.optional(),
  limit: z.number().int().min(1).max(1000).default(50),
  cursor: solicitudIdSchema.optional(),
});
export type FiltroListaSolicitudes = z.infer<typeof filtroListaSolicitudes>;

export const filtroListaVisitas = z.object({
  estado: visitaPotencialEstadoSchema.optional(),
  evaluadorId: evaluadorIdSchema.optional(),
  solicitudId: solicitudIdSchema.optional(),
  limit: z.number().int().min(1).max(1000).default(50),
  cursor: visitaPotencialIdSchema.optional(),
});
export type FiltroListaVisitas = z.infer<typeof filtroListaVisitas>;

export const filtroListaEvaluadores = z.object({
  tipo: tipoEvaluadorSchema.optional(),
  limit: z.number().int().min(1).max(1000).default(50),
  cursor: evaluadorIdSchema.optional(),
});

export const aceptacionHttpSchema = z.object({
  visita_id: visitaPotencialIdSchema,
  solicitud_id: solicitudIdSchema,
  estado: z.literal("aceptada"),
  pin: pinPlanoSchema,
});

export const verificacionPinHttpSchema = z.union([
  z.object({
    ok: z.literal(true),
    solicitud_estado: z.literal("en_evaluacion"),
  }),
  z.object({
    ok: z.literal(false),
    intentos: z.literal(1),
    alerta: z.literal(true),
  }),
  z.object({
    ok: z.literal(false),
    cancelada: z.literal(true),
    solicitud_estado: z.literal("evaluacion_fallida"),
  }),
]);

export {
  causaCancelacionSchema,
  evaluadorIdSchema,
  geoPointSchema,
  personaIdSchema,
  solicitudIdSchema,
  visitaPotencialIdSchema,
};
