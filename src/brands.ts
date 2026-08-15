import { z } from "zod";

export const solicitudIdSchema = z.string().uuid().brand<"SolicitudId">();
export type SolicitudId = z.infer<typeof solicitudIdSchema>;

export const evaluadorIdSchema = z.string().uuid().brand<"EvaluadorId">();
export type EvaluadorId = z.infer<typeof evaluadorIdSchema>;

export const visitaPotencialIdSchema = z
  .string()
  .uuid()
  .brand<"VisitaPotencialId">();
export type VisitaPotencialId = z.infer<typeof visitaPotencialIdSchema>;

export const visitaRealizadaIdSchema = z
  .string()
  .uuid()
  .brand<"VisitaRealizadaId">();
export type VisitaRealizadaId = z.infer<typeof visitaRealizadaIdSchema>;

export const personaIdSchema = z.string().uuid().brand<"PersonaId">();
export type PersonaId = z.infer<typeof personaIdSchema>;

export const pinHashSchema = z.string().min(1).brand<"PinHash">();
export type PinHash = z.infer<typeof pinHashSchema>;

export const formularioIdSchema = z.string().uuid().brand<"FormularioId">();
export type FormularioId = z.infer<typeof formularioIdSchema>;

export const campoIdSchema = z.string().uuid().brand<"CampoId">();
export type CampoId = z.infer<typeof campoIdSchema>;

export const formularioDiligenciadoIdSchema = z
  .string()
  .uuid()
  .brand<"FormularioDiligenciadoId">();
export type FormularioDiligenciadoId = z.infer<
  typeof formularioDiligenciadoIdSchema
>;

export const respuestaIdSchema = z.string().uuid().brand<"RespuestaId">();
export type RespuestaId = z.infer<typeof respuestaIdSchema>;
