import type { CampoId, FormularioDiligenciadoId, VisitaRealizadaId } from "../brands.js";
import type { GeoPoint, ResultadoEvaluacion } from "./estados.js";

export type TipoCampo =
  | "texto"
  | "likert"
  | "opcion"
  | "imagen"
  | "geolocalizacion";

export type CardinalidadCampo = "uno" | "muchos";

export type OpcionCampo = Readonly<{
  valor: number;
  etiqueta: string;
}>;

type CampoComun = Readonly<{
  id: CampoId;
  codigo: string;
  prompt: string;
  orden: number;
  obligatorio: boolean;
}>;

export type CampoTexto = CampoComun &
  Readonly<{ tipo: "texto"; cardinalidad: "uno"; opciones: null }>;

export type CampoLikert = CampoComun &
  Readonly<{
    tipo: "likert";
    cardinalidad: "uno";
    opciones: readonly OpcionCampo[];
  }>;

export type CampoOpcion = CampoComun &
  Readonly<{
    tipo: "opcion";
    cardinalidad: CardinalidadCampo;
    opciones: readonly OpcionCampo[];
  }>;

export type CampoImagen = CampoComun &
  Readonly<{
    tipo: "imagen";
    cardinalidad: CardinalidadCampo;
    opciones: null;
  }>;

export type CampoGeo = CampoComun &
  Readonly<{
    tipo: "geolocalizacion";
    cardinalidad: "uno";
    opciones: null;
  }>;

export type Campo =
  | CampoTexto
  | CampoLikert
  | CampoOpcion
  | CampoImagen
  | CampoGeo;

export type ValorTexto = Readonly<{ texto: string }>;
export type ValorCodigo = Readonly<{ valor: number }>;
export type ValorImagen = Readonly<{ storage_path: string }>;
export type ValorGeo = GeoPoint;
export type ValorRespuesta = ValorTexto | ValorCodigo | ValorImagen | ValorGeo;

export type EstadoFormulario = Readonly<{
  ok: boolean;
  error: string | undefined;
  id: FormularioDiligenciadoId;
  visitaRealizadaId: VisitaRealizadaId;
  campoActual: Campo | null;
  campoSiguiente: Campo | null;
  camposDiligenciados: readonly CampoId[];
  congelado: boolean;
  completoObligatorio: boolean;
  resultado: ResultadoEvaluacion | undefined;
}>;

export function mapearClasificacionAis(valor: number): ResultadoEvaluacion {
  if (valor === 1 || valor === 2) {
    return "habitable";
  }
  if (valor === 3) {
    return "restringido";
  }
  if (valor === 4 || valor === 5) {
    return "insegura";
  }
  throw new RangeError(`clasificacion AIS fuera de 1–5: ${String(valor)}`);
}
