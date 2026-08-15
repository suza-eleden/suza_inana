import { describe, expect, expectTypeOf, it } from "vitest";
import {
  evaluadorIdSchema,
  solicitudIdSchema,
  visitaPotencialIdSchema,
} from "../src/brands.js";
import { transicionarVisita } from "../src/domain/transiciones.js";
import type { VisitaPotencial } from "../src/domain/visita-potencial.js";
import { TransicionIlegal } from "../src/errors.js";

const ID_VISITA = visitaPotencialIdSchema.parse(
  "11111111-1111-4111-8111-111111111111",
);
const ID_SOLICITUD = solicitudIdSchema.parse(
  "22222222-2222-4222-8222-222222222222",
);
const ID_EVALUADOR = evaluadorIdSchema.parse(
  "33333333-3333-4333-8333-333333333333",
);

const VENTANA = {
  desde: "2026-08-13T10:00:00.000Z",
  hasta: "2026-08-13T18:00:00.000Z",
};

function creada(): VisitaPotencial {
  return {
    tag: "creada",
    id: ID_VISITA,
    solicitudId: ID_SOLICITUD,
    evaluadorId: ID_EVALUADOR,
    ventana: VENTANA,
  };
}

describe("transicionarVisita", () => {
  it("aceptar produce aceptada con cero intentos", () => {
    const siguiente = transicionarVisita(creada(), { tag: "aceptar" });
    expect(siguiente).toMatchObject({ tag: "aceptada", intentosPin: 0 });
  });

  it("el primer pin_fail incrementa intentos y no cancela", () => {
    const aceptada = transicionarVisita(creada(), { tag: "aceptar" });
    const siguiente = transicionarVisita(aceptada, { tag: "pin_fail" });
    expect(siguiente).toMatchObject({ tag: "aceptada", intentosPin: 1 });
  });

  it("el segundo pin_fail cancela con causa pin_fallido", () => {
    const aceptada = transicionarVisita(creada(), { tag: "aceptar" });
    const primerFallo = transicionarVisita(aceptada, { tag: "pin_fail" });
    const siguiente = transicionarVisita(primerFallo, { tag: "pin_fail" });
    expect(siguiente).toMatchObject({
      tag: "cancelada",
      causa: "pin_fallido",
    });
  });

  it("rechazar desde creada", () => {
    const siguiente = transicionarVisita(creada(), { tag: "rechazar" });
    expect(siguiente.tag).toBe("rechazada");
  });

  it("pin_ok desde creada es ilegal", () => {
    expect(() =>
      transicionarVisita(creada(), {
        tag: "pin_ok",
        verificadaEn: new Date("2026-08-13T12:00:00.000Z"),
      }),
    ).toThrow(TransicionIlegal);
  });

  it("SolicitudId y EvaluadorId no unifican", () => {
    expectTypeOf<typeof ID_SOLICITUD>().not.toEqualTypeOf<typeof ID_EVALUADOR>();
  });
});
