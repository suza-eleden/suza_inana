import { z } from "zod";

export const solicitudEstadoSchema = z.enum([
  "creada",
  "visita_pendiente",
  "en_evaluacion",
  "evaluacion_fallida",
  "evaluacion_parcial",
  "evaluada",
]);
export type SolicitudEstado = z.infer<typeof solicitudEstadoSchema>;

export const visitaPotencialEstadoSchema = z.enum([
  "creada",
  "aceptada",
  "rechazada",
  "cancelada",
]);
export type VisitaPotencialEstado = z.infer<typeof visitaPotencialEstadoSchema>;

export const tallaSchema = z.enum(["xs", "s", "m", "l", "xl"]);
export type Talla = z.infer<typeof tallaSchema>;

export const tipoEvaluadorSchema = z.enum(["voluntario", "oficial"]);
export type TipoEvaluador = z.infer<typeof tipoEvaluadorSchema>;

export const resultadoEvaluacionSchema = z.enum([
  "habitable",
  "restringido",
  "insegura",
]);
export type ResultadoEvaluacion = z.infer<typeof resultadoEvaluacionSchema>;

export const causaCancelacionSchema = z.enum([
  "pin_fallido",
  "evaluador",
  "solicitante",
  "tomada_por_otro",
]);
export type CausaCancelacion = z.infer<typeof causaCancelacionSchema>;

export const geoPointSchema = z.object({
  lat: z.number().gte(-90).lte(90),
  lng: z.number().gte(-180).lte(180),
});
export type GeoPoint = z.infer<typeof geoPointSchema>;

export const ventanaSchema = z
  .object({
    desde: z.string().datetime({ offset: true }),
    hasta: z.string().datetime({ offset: true }),
  })
  .refine((ventana) => ventana.desde < ventana.hasta, {
    message: "ventana vacía o invertida",
  });
export type Ventana = z.infer<typeof ventanaSchema>;

export const pinPlanoSchema = z.string().regex(/^\d{4}$/);
export type PinPlano = z.infer<typeof pinPlanoSchema>;
