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
  agregarCampoInput,
  archivarFormularioInput,
  coordinadorFilaSchema,
  crearFormularioInput,
  crearNuevaVersionFormularioInput,
  estadoFormularioHttpSchema,
  estadoFromHttp,
  formularioDiligenciadoIdInput,
  iniciarFormularioInput,
  publicarFormularioInput,
  registrarCoordinadorInput,
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

export function parseCrearFormulario(raw: string) {
  return crearFormularioInput.parse(decodeJson(raw));
}

export function parsePublicarFormulario(raw: string) {
  return publicarFormularioInput.parse(decodeJson(raw));
}

export function parseArchivarFormulario(raw: string) {
  return archivarFormularioInput.parse(decodeJson(raw));
}

export function parseCrearNuevaVersionFormulario(raw: string) {
  return crearNuevaVersionFormularioInput.parse(decodeJson(raw));
}

export function parseAgregarCampo(raw: string) {
  return agregarCampoInput.parse(decodeJson(raw));
}

export function parseRegistrarCoordinador(raw: string) {
  return registrarCoordinadorInput.parse(decodeJson(raw));
}

export function parseCoordinadorFila(raw: unknown) {
  return coordinadorFilaSchema.parse(raw);
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
  agregarCampoInput,
  archivarFormularioInput,
  coordinadorFilaSchema,
  crearFormularioInput,
  crearNuevaVersionFormularioInput,
  estadoFormularioDefSchema,
  estadoFormularioHttpSchema,
  iniciarFormularioInput,
  publicarFormularioInput,
  registrarCoordinadorInput,
  responderCampoInput,
  valorRespuestaSchema,
} from "./formulario.js";
