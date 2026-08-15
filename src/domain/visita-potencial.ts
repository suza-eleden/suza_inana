import type { EvaluadorId, SolicitudId, VisitaPotencialId } from "../brands.js";
import type { CausaCancelacion, Ventana } from "./estados.js";

export type VisitaPotencial = Readonly<
  | {
      tag: "creada";
      id: VisitaPotencialId;
      solicitudId: SolicitudId;
      evaluadorId: EvaluadorId;
      ventana: Ventana;
    }
  | {
      tag: "aceptada";
      id: VisitaPotencialId;
      solicitudId: SolicitudId;
      evaluadorId: EvaluadorId;
      ventana: Ventana;
      intentosPin: 0 | 1;
      verificadaEn: Date | undefined;
    }
  | {
      tag: "rechazada";
      id: VisitaPotencialId;
      solicitudId: SolicitudId;
      evaluadorId: EvaluadorId;
      ventana: Ventana;
    }
  | {
      tag: "cancelada";
      id: VisitaPotencialId;
      solicitudId: SolicitudId;
      evaluadorId: EvaluadorId;
      ventana: Ventana;
      causa: CausaCancelacion;
    }
>;

export type EventoVisita = Readonly<
  | { tag: "aceptar" }
  | { tag: "rechazar" }
  | { tag: "pin_ok"; verificadaEn: Date }
  | { tag: "pin_fail" }
  | { tag: "tomar_otro" }
  | { tag: "cancelar"; causa: Exclude<CausaCancelacion, "tomada_por_otro"> }
>;
