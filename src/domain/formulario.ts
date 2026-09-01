import type {
  CampoId,
  FormularioDiligenciadoId,
  FormularioId,
  SolicitudId,
  VisitaRealizadaId,
} from "../brands.js";
import type { GeoPoint, ResultadoEvaluacion } from "./estados.js";

export type EstadoFormularioDef = "borrador" | "publicado" | "archivado";

export type Formulario = Readonly<{
  id: FormularioId;
  codigo: string;
  nombre: string;
  version: number;
  estado: EstadoFormularioDef;
  descripcion?: string | null;
  publicadoEn?: string | null;
}>;

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
  formularioId: FormularioId;
  formularioCodigo?: string | undefined;
  formularioVersion?: number | undefined;
  visitaRealizadaId: VisitaRealizadaId | null;
  solicitudId?: SolicitudId | null | undefined;
  autorId?: string | null | undefined;
  campoActual: Campo | null;
  campoSiguiente: Campo | null;
  camposDiligenciados: readonly CampoId[];
  congelado: boolean;
  completoObligatorio: boolean;
  resultado: ResultadoEvaluacion | undefined;
}>;

export type PerfilRupe = "P1" | "P2" | "P3" | "P4" | "otro";

export type SeveridadD1171 = "N" | "M" | "S" | "NA";

export type CartelOficialD1171 = 1 | 2 | 3;

export function mapearCartelD1171(valor: number): ResultadoEvaluacion {
  if (valor === 1) {
    return "habitable"; // Verde (Inspeccionada)
  }
  if (valor === 2) {
    return "restringido"; // Amarillo (Uso Restringido)
  }
  if (valor === 3) {
    return "insegura"; // Rojo (Inseguro / Peligro de Colapso)
  }
  throw new RangeError(`cartel D1171 fuera de 1–3: ${String(valor)}`);
}

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

