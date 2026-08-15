export class TransicionIlegal extends Error {
  readonly estado: string;
  readonly evento: string;

  constructor(estado: string, evento: string) {
    super(`transicion_ilegal: ${estado} -[ ${evento} ]->`);
    this.name = "TransicionIlegal";
    this.estado = estado;
    this.evento = evento;
  }
}

export class FronteraInvalida extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FronteraInvalida";
  }
}
