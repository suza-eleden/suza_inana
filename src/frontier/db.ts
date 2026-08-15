import { z } from "zod";
import {
  evaluadorIdSchema,
  personaIdSchema,
  solicitudIdSchema,
  visitaPotencialIdSchema,
} from "../brands.js";
import type { Solicitud } from "../domain/solicitud.js";
import type { VisitaPotencial } from "../domain/visita-potencial.js";
import {
  causaCancelacionSchema,
  geoPointSchema,
  solicitudEstadoSchema,
  tallaSchema,
  ventanaSchema,
  visitaPotencialEstadoSchema,
} from "../domain/estados.js";
import { FronteraInvalida } from "../errors.js";
import { assertNever } from "../never.js";

const geoJsonPoint = z
  .object({
    type: z.literal("Point"),
    coordinates: z.tuple([z.number(), z.number()]),
  })
  .transform((point) =>
    geoPointSchema.parse({
      lng: point.coordinates[0],
      lat: point.coordinates[1],
    }),
  );

export const geoFromPostgis = z.union([geoJsonPoint, geoPointSchema]);

const rangeText = z.string().transform((raw, ctx) => {
  const match = /^\[([^,]+),([^)]+)\)/.exec(raw);
  const desdeRaw = match?.[1];
  const hastaRaw = match?.[2];
  if (desdeRaw === undefined || hastaRaw === undefined) {
    ctx.addIssue({ code: "custom", message: "tstzrange irreconocible" });
    return z.NEVER;
  }
  return ventanaSchema.parse({
    desde: toOffsetIso(desdeRaw.trim()),
    hasta: toOffsetIso(hastaRaw.trim()),
  });
});

export const ventanaFromDb = z.union([rangeText, ventanaSchema]);

export const solicitudFilaSchema = z.object({
  id: solicitudIdSchema,
  solicitante_id: personaIdSchema,
  ubicacion: geoFromPostgis,
  talla: tallaSchema,
  ventana: ventanaFromDb,
  estado: solicitudEstadoSchema,
});
export type SolicitudFila = z.infer<typeof solicitudFilaSchema>;

export const visitaFilaSchema = z.object({
  id: visitaPotencialIdSchema,
  solicitud_id: solicitudIdSchema,
  evaluador_id: evaluadorIdSchema,
  estado: visitaPotencialEstadoSchema,
  causa_cancelacion: causaCancelacionSchema.nullable(),
  pin_intentos: z.union([z.literal(0), z.literal(1)]),
  pin_verificado_en: z.string().datetime({ offset: true }).nullable(),
  ventana_propuesta: ventanaFromDb,
});
export type VisitaFila = z.infer<typeof visitaFilaSchema>;

export function solicitudFromFila(fila: SolicitudFila): Solicitud {
  const base = {
    id: fila.id,
    solicitanteId: fila.solicitante_id,
    ubicacion: fila.ubicacion,
    talla: fila.talla,
    ventana: fila.ventana,
  };
  switch (fila.estado) {
    case "creada":
      return { tag: "creada", ...base };
    case "visita_pendiente":
      return { tag: "visita_pendiente", ...base };
    case "en_evaluacion":
      return { tag: "en_evaluacion", ...base, visitaActivaId: undefined };
    case "evaluacion_fallida":
      return { tag: "evaluacion_fallida", ...base, causa: "no_encontrada" };
    case "evaluacion_parcial":
      return { tag: "evaluacion_parcial", ...base, visitasCompletas: 1 };
    case "evaluada":
      throw new FronteraInvalida(
        "evaluada requiere join con visitas_realizadas; no hidratar desde la fila sola",
      );
    default:
      return assertNever(fila.estado);
  }
}

export function visitaFromFila(fila: VisitaFila): VisitaPotencial {
  const base = {
    id: fila.id,
    solicitudId: fila.solicitud_id,
    evaluadorId: fila.evaluador_id,
    ventana: fila.ventana_propuesta,
  };
  switch (fila.estado) {
    case "creada":
      return { tag: "creada", ...base };
    case "aceptada":
      return {
        tag: "aceptada",
        ...base,
        intentosPin: fila.pin_intentos,
        verificadaEn:
          fila.pin_verificado_en === null
            ? undefined
            : new Date(fila.pin_verificado_en),
      };
    case "rechazada":
      return { tag: "rechazada", ...base };
    case "cancelada":
      return canceladaFromFila(fila, base);
    default:
      return assertNever(fila.estado);
  }
}

function canceladaFromFila(
  fila: VisitaFila,
  base: Pick<VisitaPotencial, "id" | "solicitudId" | "evaluadorId" | "ventana">,
): VisitaPotencial {
  if (fila.causa_cancelacion === null) {
    throw new FronteraInvalida("cancelada sin causa_cancelacion");
  }
  return { tag: "cancelada", ...base, causa: fila.causa_cancelacion };
}

function toOffsetIso(value: string): string {
  const withT = value.includes("T") ? value : value.replace(" ", "T");
  return withT.replace(/([+-]\d{2})$/, "$1:00");
}
