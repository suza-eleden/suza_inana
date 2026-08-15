import { decodeJson } from "./json.js";
import {
  crearSolicitudInput,
  filtroListaEvaluadores,
  filtroListaSolicitudes,
  filtroListaVisitas,
  verificarPinInput,
  type CrearSolicitudInput,
  type FiltroListaSolicitudes,
  type FiltroListaVisitas,
} from "./http.js";
import { solicitudFilaSchema, visitaFilaSchema } from "./db.js";
import {
  estadoFormularioHttpSchema,
  estadoFromHttp,
  formularioDiligenciadoIdInput,
  iniciarFormularioInput,
  responderCampoInput,
  respuestasFormularioHttpSchema,
} from "./formulario.js";

export function parseCrearSolicitud(raw: string): CrearSolicitudInput {
  return crearSolicitudInput.parse(decodeJson(raw));
}

export function parseFiltroSolicitudes(raw: unknown): FiltroListaSolicitudes {
  return filtroListaSolicitudes.parse(raw);
}

export function parseFiltroVisitas(raw: unknown): FiltroListaVisitas {
  return filtroListaVisitas.parse(raw);
}

export function parseFiltroEvaluadores(raw: unknown) {
  return filtroListaEvaluadores.parse(raw);
}

export function parseVerificarPin(raw: string) {
  return verificarPinInput.parse(decodeJson(raw));
}

export function parseSolicitudFilas(raw: unknown) {
  return solicitudFilaSchema.array().parse(raw);
}

export function parseVisitaFilas(raw: unknown) {
  return visitaFilaSchema.array().parse(raw);
}

export function parseIniciarFormulario(raw: string) {
  return iniciarFormularioInput.parse(decodeJson(raw));
}

export function parseEstadoFormularioId(raw: string) {
  return formularioDiligenciadoIdInput.parse(decodeJson(raw));
}

export function parseResponderCampo(raw: string) {
  return responderCampoInput.parse(decodeJson(raw));
}

export function parseEstadoFormularioJson(raw: unknown) {
  return estadoFromHttp(estadoFormularioHttpSchema.parse(raw));
}

export function parseRespuestasFormularioJson(raw: unknown) {
  return respuestasFormularioHttpSchema.parse(raw);
}

export {
  solicitudFromFila,
  visitaFromFila,
  solicitudFilaSchema,
  visitaFilaSchema,
} from "./db.js";
export {
  aceptacionHttpSchema,
  calificarInput,
  concluirVisitaInput,
  crearSolicitudInput,
  filtroListaEvaluadores,
  filtroListaSolicitudes,
  filtroListaVisitas,
  registrarEvaluadorInput,
  registrarPersonaInput,
  verificacionPinHttpSchema,
  verificarPinInput,
  visitaIdInput,
} from "./http.js";
export {
  estadoFormularioHttpSchema,
  iniciarFormularioInput,
  responderCampoInput,
  valorRespuestaSchema,
} from "./formulario.js";
