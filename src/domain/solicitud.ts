import type { PersonaId, SolicitudId, VisitaPotencialId } from "../brands.js";
import type {
  CausaCancelacion,
  GeoPoint,
  ResultadoEvaluacion,
  Talla,
  Ventana,
} from "./estados.js";

export type Solicitud = Readonly<
  | {
      tag: "creada";
      id: SolicitudId;
      solicitanteId: PersonaId;
      ubicacion: GeoPoint;
      talla: Talla;
      ventana: Ventana;
    }
  | {
      tag: "visita_pendiente";
      id: SolicitudId;
      solicitanteId: PersonaId;
      ubicacion: GeoPoint;
      talla: Talla;
      ventana: Ventana;
    }
  | {
      tag: "en_evaluacion";
      id: SolicitudId;
      solicitanteId: PersonaId;
      ubicacion: GeoPoint;
      talla: Talla;
      ventana: Ventana;
      visitaActivaId: VisitaPotencialId | undefined;
    }
  | {
      tag: "evaluacion_fallida";
      id: SolicitudId;
      solicitanteId: PersonaId;
      ubicacion: GeoPoint;
      talla: Talla;
      ventana: Ventana;
      causa: CausaCancelacion | "no_encontrada";
    }
  | {
      tag: "evaluacion_parcial";
      id: SolicitudId;
      solicitanteId: PersonaId;
      ubicacion: GeoPoint;
      talla: Talla;
      ventana: Ventana;
      visitasCompletas: 1 | 2;
    }
  | {
      tag: "evaluada";
      id: SolicitudId;
      solicitanteId: PersonaId;
      ubicacion: GeoPoint;
      talla: Talla;
      ventana: Ventana;
      resultado: ResultadoEvaluacion;
    }
>;
