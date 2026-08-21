import { describe, expect, it } from "vitest";
import { ZodError } from "zod";
import {
  mapearCartelD1171,
  mapearClasificacionAis,
} from "../src/domain/formulario.js";
import {
  parseEstadoFormularioJson,
  parseIniciarFormulario,
  parseResponderCampo,
  valorRespuestaSchema,
} from "../src/frontier/index.js";

const FD_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CAMPO_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const VISITA_ID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const FORM_ID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

describe("mapearCartelD1171", () => {
  it("1 es habitable (Cartel Verde)", () => {
    expect(mapearCartelD1171(1)).toBe("habitable");
  });

  it("2 es restringido (Cartel Amarillo)", () => {
    expect(mapearCartelD1171(2)).toBe("restringido");
  });

  it("3 es insegura (Cartel Rojo)", () => {
    expect(mapearCartelD1171(3)).toBe("insegura");
  });

  it("rechaza valores fuera de 1–3", () => {
    expect(() => mapearCartelD1171(0)).toThrow(RangeError);
    expect(() => mapearCartelD1171(4)).toThrow(RangeError);
  });
});

describe("mapearClasificacionAis", () => {

  it("1 y 2 son habitables", () => {
    expect(mapearClasificacionAis(1)).toBe("habitable");
    expect(mapearClasificacionAis(2)).toBe("habitable");
  });

  it("3 es restringido", () => {
    expect(mapearClasificacionAis(3)).toBe("restringido");
  });

  it("4 y 5 son insegura", () => {
    expect(mapearClasificacionAis(4)).toBe("insegura");
    expect(mapearClasificacionAis(5)).toBe("insegura");
  });

  it("rechaza valores fuera de 1–5", () => {
    expect(() => mapearClasificacionAis(0)).toThrow(RangeError);
    expect(() => mapearClasificacionAis(6)).toThrow(RangeError);
  });
});

describe("frontera formulario", () => {
  it("parsea iniciar_formulario", () => {
    const parsed = parseIniciarFormulario(
      JSON.stringify({ visitaRealizadaId: VISITA_ID }),
    );
    expect(parsed.visitaRealizadaId).toBe(VISITA_ID);
  });

  it("acepta valor texto, geo e imagen y rechaza path vacío", () => {
    expect(valorRespuestaSchema.parse({ texto: "Chapinero" })).toEqual({
      texto: "Chapinero",
    });
    expect(
      valorRespuestaSchema.parse({ lat: 4.711, lng: -74.0721 }),
    ).toEqual({ lat: 4.711, lng: -74.0721 });
    expect(
      valorRespuestaSchema.parse({ storage_path: "uid/fachada.jpg" }),
    ).toEqual({ storage_path: "uid/fachada.jpg" });
    expect(() => valorRespuestaSchema.parse({ storage_path: "" })).toThrow(
      ZodError,
    );
  });

  it("parsea responder_campo con overwrite", () => {
    const parsed = parseResponderCampo(
      JSON.stringify({
        formularioDiligenciadoId: FD_ID,
        campoId: CAMPO_ID,
        valor: { valor: 3 },
      }),
    );
    expect(parsed.valor).toEqual({ valor: 3 });
  });

  it("hidrata estado con cursor y campos diligenciados", () => {
    const estado = parseEstadoFormularioJson({
      ok: true,
      id: FD_ID,
      visita_realizada_id: VISITA_ID,
      formulario_id: FORM_ID,
      campo_actual_id: CAMPO_ID,
      campo_siguiente_id: null,
      campo_actual: {
        id: CAMPO_ID,
        codigo: "item_4_fachadas",
        tipo: "likert",
        prompt: "4. Muros de fachadas o antepechos",
        orden: 1,
        obligatorio: true,
        cardinalidad: "uno",
        opciones: [{ valor: 1, etiqueta: "Ninguno" }],
      },
      campo_siguiente: null,
      campos_diligenciados: [CAMPO_ID],
      congelado: false,
      completo_obligatorio: false,
    });
    expect(estado.ok).toBe(true);
    expect(estado.campoActual?.codigo).toBe("item_4_fachadas");
    expect(estado.camposDiligenciados).toHaveLength(1);
    expect(estado.congelado).toBe(false);
  });

  it("parsea error de dominio conservando el estado", () => {
    const estado = parseEstadoFormularioJson({
      ok: false,
      error: "formulario_congelado",
      id: FD_ID,
      visita_realizada_id: VISITA_ID,
      formulario_id: FORM_ID,
      campo_actual_id: CAMPO_ID,
      campo_siguiente_id: null,
      campo_actual: {
        id: CAMPO_ID,
        codigo: "localidad",
        tipo: "texto",
        prompt: "Localidad",
        orden: 1,
        obligatorio: true,
        cardinalidad: "uno",
        opciones: null,
      },
      campo_siguiente: null,
      campos_diligenciados: [],
      congelado: true,
      completo_obligatorio: false,
    });
    expect(estado.ok).toBe(false);
    expect(estado.error).toBe("formulario_congelado");
    expect(estado.congelado).toBe(true);
  });
});
