import type { Ventana } from "../domain/estados.js";

export function ventanaARango(ventana: Ventana): string {
  return `[${ventana.desde},${ventana.hasta})`;
}
