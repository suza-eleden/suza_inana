import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../generated/database.js";
import { decodeJson, encodeJson } from "../frontier/json.js";
import {
  aceptacionHttpSchema,
  parseAgregarCampo,
  parseArchivarFormulario,
  parseCoordinadorFila,
  parseCrearFormulario,
  parseCrearNuevaVersionFormulario,
  parseCrearSolicitud,
  parseEstadoFormularioId,
  parseEstadoFormularioJson,
  parseIniciarFormulario,
  parsePublicarFormulario,
  parseRegistrarCoordinador,
  parseResponderCampo,
  parseRespuestasFormularioJson,
  parseVerificarPin,
  registrarEvaluadorInput,
  registrarPersonaInput,
  verificacionPinHttpSchema,
  visitaIdInput,
} from "../frontier/index.js";
import { solicitudFilaSchema, visitaFilaSchema } from "../frontier/db.js";
import { ventanaARango } from "./rango.js";

export async function crearSolicitud(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parseCrearSolicitud(raw);
  const { data, error } = await client.rpc("crear_solicitud", {
    lng: input.lng,
    lat: input.lat,
    talla: input.talla,
    ventana: ventanaARango(input.ventana),
  });
  if (error) {
    throw error;
  }
  return solicitudFilaSchema.parse(data);
}

export async function registrarPersona(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = registrarPersonaInput.parse(decodeJson(raw));
  const { data, error } = await client.rpc("registrar_persona", {
    nombre: input.nombre,
    telefono: input.telefono ?? "",
  });
  if (error) {
    throw error;
  }
  return data;
}

export async function registrarEvaluador(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = registrarEvaluadorInput.parse(decodeJson(raw));
  const { data, error } = await client.rpc("registrar_evaluador", {
    tipo: input.tipo,
    tarjeta_profesional_path: input.tarjetaProfesionalPath,
    transporte_propio: input.transportePropio,
    lng: input.lng,
    lat: input.lat,
    radio_metros: input.radioMetros,
    ventana: ventanaARango(input.ventana),
  });
  if (error) {
    throw error;
  }
  return data;
}

export async function aceptarVisita(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = visitaIdInput.parse(decodeJson(raw));
  const { data, error } = await client.rpc("aceptar_visita", {
    visita_id: input.visitaId,
  });
  if (error) {
    throw error;
  }
  return aceptacionHttpSchema.parse(data);
}

export async function rechazarVisita(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = visitaIdInput.parse(decodeJson(raw));
  const { data, error } = await client.rpc("rechazar_visita", {
    visita_id: input.visitaId,
  });
  if (error) {
    throw error;
  }
  return visitaFilaSchema.parse(data);
}

export async function verificarPin(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parseVerificarPin(raw);
  const { data, error } = await client.rpc("verificar_pin", {
    visita_id: input.visitaId,
    pin: input.pin,
  });
  if (error) {
    throw error;
  }
  return verificacionPinHttpSchema.parse(data);
}

export async function iniciarFormulario(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parseIniciarFormulario(raw);
  const { data, error } = await client.rpc("iniciar_formulario", {
    visita_realizada_id: input.visitaRealizadaId,
    codigo_formulario: input.codigoFormulario,
    solicitud_id: input.solicitudId,
    version: input.version,
  });
  if (error) {
    throw error;
  }
  return parseEstadoFormularioJson(data);
}

export async function estadoFormulario(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parseEstadoFormularioId(raw);
  const { data, error } = await client.rpc("estado_formulario", {
    formulario_diligenciado_id: input.formularioDiligenciadoId,
  });
  if (error) {
    throw error;
  }
  return parseEstadoFormularioJson(data);
}

export async function responderCampo(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parseResponderCampo(raw);
  const valor = encodeJson(input.valor);
  const args =
    input.respuestaId === undefined
      ? {
          formulario_diligenciado_id: input.formularioDiligenciadoId,
          campo_id: input.campoId,
          valor,
        }
      : {
          formulario_diligenciado_id: input.formularioDiligenciadoId,
          campo_id: input.campoId,
          valor,
          respuesta_id: input.respuestaId,
        };
  const { data, error } = await client.rpc("responder_campo", args);
  if (error) {
    throw error;
  }
  return parseEstadoFormularioJson(data);
}

export async function respuestasFormulario(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parseEstadoFormularioId(raw);
  const { data, error } = await client.rpc("respuestas_formulario", {
    formulario_diligenciado_id: input.formularioDiligenciadoId,
  });
  if (error) {
    throw error;
  }
  return parseRespuestasFormularioJson(data);
}

export async function commitFormulario(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parseEstadoFormularioId(raw);
  const { data, error } = await client.rpc("commit_formulario", {
    formulario_diligenciado_id: input.formularioDiligenciadoId,
  });
  if (error) {
    throw error;
  }
  return parseEstadoFormularioJson(data);
}

export async function crearFormulario(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parseCrearFormulario(raw);
  const { data, error } = await client.rpc("crear_formulario", {
    codigo: input.codigo,
    nombre: input.nombre,
    descripcion: input.descripcion,
  });
  if (error) {
    throw error;
  }
  return data;
}

export async function publicarFormulario(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parsePublicarFormulario(raw);
  const { data, error } = await client.rpc("publicar_formulario", {
    formulario_id: input.formularioId,
  });
  if (error) {
    throw error;
  }
  return data;
}

export async function archivarFormulario(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parseArchivarFormulario(raw);
  const { data, error } = await client.rpc("archivar_formulario", {
    formulario_id: input.formularioId,
  });
  if (error) {
    throw error;
  }
  return data;
}

export async function crearNuevaVersionFormulario(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parseCrearNuevaVersionFormulario(raw);
  const { data, error } = await client.rpc("crear_nueva_version_formulario", {
    codigo: input.codigo,
  });
  if (error) {
    throw error;
  }
  return data;
}

export async function agregarCampo(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parseAgregarCampo(raw);
  const opciones = input.opciones !== undefined ? encodeJson(input.opciones) : null;
  const { data, error } = await client.rpc("agregar_campo", {
    formulario_id: input.formularioId,
    codigo: input.codigo,
    tipo: input.tipo,
    prompt: input.prompt,
    orden: input.orden,
    obligatorio: input.obligatorio,
    cardinalidad: input.cardinalidad,
    opciones,
  });
  if (error) {
    throw error;
  }
  return data;
}

export async function registrarCoordinador(
  client: SupabaseClient<Database>,
  raw: string,
) {
  const input = parseRegistrarCoordinador(raw);
  const { data, error } = await client.rpc("registrar_coordinador", {
    nombre: input.nombre,
    cargo: input.cargo,
  });
  if (error) {
    throw error;
  }
  return parseCoordinadorFila(data);
}
