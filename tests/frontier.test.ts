import { describe, expect, it } from "vitest";
import { ZodError } from "zod";
import {
  parseCrearSolicitud,
  parseFiltroSolicitudes,
  parseVerificarPin,
  solicitudFromFila,
  visitaFromFila,
} from "../src/frontier/index.js";
import { solicitudFilaSchema, visitaFilaSchema } from "../src/frontier/db.js";

describe("frontera HTTP", () => {
  it("acepta una solicitud bien formada", () => {
    const raw = JSON.stringify({
      lng: -74.0721,
      lat: 4.71099,
      talla: "m",
      ventana: {
        desde: "2026-08-13T10:00:00.000Z",
        hasta: "2026-08-13T18:00:00.000Z",
      },
    });
    const parsed = parseCrearSolicitud(raw);
    expect(parsed.talla).toBe("m");
  });

  it("rechaza JSON con campos de más (strict)", () => {
    const raw = JSON.stringify({
      lng: -74.0721,
      lat: 4.71099,
      talla: "m",
      ventana: {
        desde: "2026-08-13T10:00:00.000Z",
        hasta: "2026-08-13T18:00:00.000Z",
      },
      estado: "evaluada",
    });
    expect(() => parseCrearSolicitud(raw)).toThrow(ZodError);
  });

  it("no deja entrar un PIN que no sea de 4 cifras", () => {
    expect(() =>
      parseVerificarPin(
        JSON.stringify({
          visitaId: "11111111-1111-4111-8111-111111111111",
          pin: "12",
        }),
      ),
    ).toThrow(ZodError);
  });

  it("filtra listas por estado", () => {
    const filtro = parseFiltroSolicitudes({ estado: "visita_pendiente" });
    expect(filtro.estado).toBe("visita_pendiente");
    expect(filtro.limit).toBe(50);
  });
});

describe("frontera DB", () => {
  it("hidrata una visita aceptada sin pin_hash", () => {
    const fila = visitaFilaSchema.parse({
      id: "11111111-1111-4111-8111-111111111111",
      solicitud_id: "22222222-2222-4222-8222-222222222222",
      evaluador_id: "33333333-3333-4333-8333-333333333333",
      estado: "aceptada",
      causa_cancelacion: null,
      pin_intentos: 0,
      pin_verificado_en: null,
      ventana_propuesta: "[2026-08-13 10:00:00+00,2026-08-13 18:00:00+00)",
    });
    const visita = visitaFromFila(fila);
    expect(visita.tag).toBe("aceptada");
    expect("pinHash" in visita).toBe(false);
  });

  it("hidrata solicitud visita_pendiente desde GeoJSON", () => {
    const fila = solicitudFilaSchema.parse({
      id: "22222222-2222-4222-8222-222222222222",
      solicitante_id: "44444444-4444-4444-8444-444444444444",
      ubicacion: { type: "Point", coordinates: [-74.0721, 4.71099] },
      talla: "l",
      ventana: {
        desde: "2026-08-13T10:00:00.000Z",
        hasta: "2026-08-13T18:00:00.000Z",
      },
      estado: "visita_pendiente",
    });
    const solicitud = solicitudFromFila(fila);
    expect(solicitud.tag).toBe("visita_pendiente");
    if (solicitud.tag === "visita_pendiente") {
      expect(solicitud.ubicacion.lat).toBeCloseTo(4.71099);
    }
  });

  it("rechaza un estado que no existe en el enum", () => {
    expect(() =>
      solicitudFilaSchema.parse({
        id: "22222222-2222-4222-8222-222222222222",
        solicitante_id: "44444444-4444-4444-8444-444444444444",
        ubicacion: { type: "Point", coordinates: [-74.0721, 4.71099] },
        talla: "l",
        ventana: {
          desde: "2026-08-13T10:00:00.000Z",
          hasta: "2026-08-13T18:00:00.000Z",
        },
        estado: "hackeada",
      }),
    ).toThrow(ZodError);
  });
});
