import { TransicionIlegal } from "../errors.js";
import { assertNever } from "../never.js";
import type { CausaCancelacion } from "./estados.js";
import type { EventoVisita, VisitaPotencial } from "./visita-potencial.js";

export function transicionarVisita(
  visita: VisitaPotencial,
  evento: EventoVisita,
): VisitaPotencial {
  switch (visita.tag) {
    case "creada":
      return desdeCreada(visita, evento);
    case "aceptada":
      return desdeAceptada(visita, evento);
    case "rechazada":
      throw new TransicionIlegal(visita.tag, evento.tag);
    case "cancelada":
      throw new TransicionIlegal(visita.tag, evento.tag);
    default:
      return assertNever(visita);
  }
}

type Creada = Extract<VisitaPotencial, { tag: "creada" }>;
type Aceptada = Extract<VisitaPotencial, { tag: "aceptada" }>;

function desdeCreada(visita: Creada, evento: EventoVisita): VisitaPotencial {
  switch (evento.tag) {
    case "aceptar":
      return aceptar(visita);
    case "rechazar":
      return rechazar(visita);
    case "tomar_otro":
      return cancelar(visita, "tomada_por_otro");
    default:
      throw new TransicionIlegal(visita.tag, evento.tag);
  }
}

function desdeAceptada(visita: Aceptada, evento: EventoVisita): VisitaPotencial {
  if (visita.verificadaEn !== undefined) {
    throw new TransicionIlegal("aceptada_verificada", evento.tag);
  }
  switch (evento.tag) {
    case "pin_ok":
      return { ...visita, verificadaEn: evento.verificadaEn };
    case "pin_fail":
      return fallarPin(visita);
    case "cancelar":
      return cancelar(visita, evento.causa);
    default:
      throw new TransicionIlegal(visita.tag, evento.tag);
  }
}

function aceptar(visita: Creada): VisitaPotencial {
  return {
    tag: "aceptada",
    id: visita.id,
    solicitudId: visita.solicitudId,
    evaluadorId: visita.evaluadorId,
    ventana: visita.ventana,
    intentosPin: 0,
    verificadaEn: undefined,
  };
}

function rechazar(visita: Creada): VisitaPotencial {
  return {
    tag: "rechazada",
    id: visita.id,
    solicitudId: visita.solicitudId,
    evaluadorId: visita.evaluadorId,
    ventana: visita.ventana,
  };
}

function fallarPin(visita: Aceptada): VisitaPotencial {
  if (visita.intentosPin === 1) {
    return cancelar(visita, "pin_fallido");
  }
  return { ...visita, intentosPin: 1 };
}

function cancelar(
  visita: Creada | Aceptada,
  causa: CausaCancelacion,
): VisitaPotencial {
  return {
    tag: "cancelada",
    id: visita.id,
    solicitudId: visita.solicitudId,
    evaluadorId: visita.evaluadorId,
    ventana: visita.ventana,
    causa,
  };
}
