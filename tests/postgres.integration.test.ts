import { afterAll, beforeAll, describe, expect, it } from "vitest";
import postgres from "postgres";
import { parseEstadoFormularioJson } from "../src/frontier/index.js";
import type { EstadoFormulario } from "../src/domain/formulario.js";

const url =
  process.env["FOINIKIS_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const sql = postgres(url, { max: 1, connect_timeout: 2 });

type CampoFila = {
  id: string;
  codigo: string;
  tipo: string;
  opciones: { valor: number; etiqueta: string }[] | null;
};

type EscenarioFormulario = {
  vrId: string;
  authEval: string;
};

async function nucleoDisponible(): Promise<boolean> {
  try {
    const filas = await sql<{ exists: boolean }[]>`
      select exists(
        select 1 from information_schema.schemata where schema_name = 'nucleo'
      ) as exists
    `;
    return filas[0]?.exists === true;
  } catch {
    return false;
  }
}

async function formulariosDisponibles(): Promise<boolean> {
  if (!(await nucleoDisponible())) {
    return false;
  }
  const filas = await sql<{ exists: boolean }[]>`
    select exists(
      select 1 from information_schema.tables
      where table_schema = 'public' and table_name = 'formularios'
    ) as exists
  `;
  return filas[0]?.exists === true;
}

async function insertarUsuario(email: string): Promise<string> {
  const filas = await sql<{ id: string }[]>`
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000',
      gen_random_uuid(),
      'authenticated',
      'authenticated',
      ${email},
      'x',
      now(),
      '{}'::jsonb,
      '{}'::jsonb,
      now(),
      now(),
      '',
      '',
      '',
      ''
    )
    returning id
  `;
  const id = filas[0]?.id;
  if (id === undefined) {
    throw new Error("auth.users no insertó fila");
  }
  return id;
}

async function crearEscenario(): Promise<EscenarioFormulario> {
  const authEval = await insertarUsuario(
    `eval-${crypto.randomUUID()}@foinikis.test`,
  );
  const authSol = await insertarUsuario(
    `sol-${crypto.randomUUID()}@foinikis.test`,
  );
  const personas = await sql<{ id: string }[]>`
    insert into public.personas (auth_user_id, nombre)
    values (${authSol}::uuid, 'Solicitante prueba')
    returning id
  `;
  const personaId = personas[0]?.id;
  const evaluadores = await sql<{ id: string }[]>`
    insert into public.evaluadores (
      auth_user_id, tipo, tarjeta_profesional_path, transporte_propio,
      ubicacion_base, radio_metros, ventana
    ) values (
      ${authEval}::uuid,
      'voluntario',
      'uid/tarjeta.jpg',
      true,
      extensions.st_setsrid(extensions.st_makepoint(-74.0721, 4.7110), 4326)::extensions.geography,
      15000,
      '[2026-08-14 08:00:00+00,2026-08-14 20:00:00+00)'::tstzrange
    )
    returning id
  `;
  const evaluadorId = evaluadores[0]?.id;
  if (personaId === undefined || evaluadorId === undefined) {
    throw new Error("no se creó persona o evaluador");
  }
  const solicitudes = await sql<{ id: string }[]>`
    insert into public.solicitudes (
      solicitante_id, ubicacion, talla, ventana, estado
    ) values (
      ${personaId}::uuid,
      extensions.st_setsrid(extensions.st_makepoint(-74.0721, 4.7110), 4326)::extensions.geography,
      'm',
      '[2026-08-14 08:00:00+00,2026-08-14 20:00:00+00)'::tstzrange,
      'en_evaluacion'
    )
    returning id
  `;
  const solicitudId = solicitudes[0]?.id;
  if (solicitudId === undefined) {
    throw new Error("no se creó solicitud");
  }
  const visitas = await sql<{ id: string }[]>`
    insert into public.visitas_potenciales (
      solicitud_id, evaluador_id, estado, pin_verificado_en, ventana_propuesta
    ) values (
      ${solicitudId}::uuid,
      ${evaluadorId}::uuid,
      'aceptada',
      now(),
      '[2026-08-14 08:00:00+00,2026-08-14 20:00:00+00)'::tstzrange
    )
    returning id
  `;
  const visitaId = visitas[0]?.id;
  if (visitaId === undefined) {
    throw new Error("no se creó visita potencial");
  }
  const realizadas = await sql<{ id: string }[]>`
    insert into public.visitas_realizadas (
      solicitud_id, evaluador_id, visita_potencial_id
    ) values (
      ${solicitudId}::uuid,
      ${evaluadorId}::uuid,
      ${visitaId}::uuid
    )
    returning id
  `;
  const vrId = realizadas[0]?.id;
  if (vrId === undefined) {
    throw new Error("no se creó visita realizada");
  }
  return { vrId, authEval };
}

async function impersonar(authUserId: string): Promise<void> {
  const claims = JSON.stringify({ sub: authUserId });
  await sql`select set_config('request.jwt.claims', ${claims}, false)`;
}

async function iniciar(vrId: string): Promise<EstadoFormulario> {
  const filas = await sql<{ iniciar_formulario: unknown }[]>`
    select nucleo.iniciar_formulario(${vrId}::uuid) as iniciar_formulario
  `;
  const raw = filas[0]?.iniciar_formulario;
  if (raw === undefined) {
    throw new Error("iniciar_formulario sin fila");
  }
  return parseEstadoFormularioJson(raw);
}

async function responder(
  fdId: string,
  campoId: string,
  valor:
    | { texto: string }
    | { valor: number }
    | { storage_path: string }
    | { lat: number; lng: number },
): Promise<EstadoFormulario> {

  const filas = await sql<{ responder_campo: unknown }[]>`
    select nucleo.responder_campo(
      ${fdId}::uuid,
      ${campoId}::uuid,
      ${sql.json(valor)}::jsonb
    ) as responder_campo
  `;
  const raw = filas[0]?.responder_campo;
  if (raw === undefined) {
    throw new Error("responder_campo sin fila");
  }
  return parseEstadoFormularioJson(raw);
}

async function commit(fdId: string): Promise<EstadoFormulario> {
  const filas = await sql<{ commit_formulario: unknown }[]>`
    select nucleo.commit_formulario(${fdId}::uuid) as commit_formulario
  `;
  const raw = filas[0]?.commit_formulario;
  if (raw === undefined) {
    throw new Error("commit_formulario sin fila");
  }
  return parseEstadoFormularioJson(raw);
}

function valorDeCampo(
  campo: CampoFila,
): { texto: string } | { valor: number } | { storage_path: string } | { lat: number; lng: number } {
  if (campo.tipo === "texto") {
    return { texto: "prueba" };
  }
  if (campo.tipo === "imagen") {
    return { storage_path: "uid/foto.jpg" };
  }
  if (campo.tipo === "geolocalizacion") {
    return { lat: 4.711, lng: -74.0721 };
  }
  if (campo.codigo === "cartel_clasificacion") {
    return { valor: 2 };
  }
  if (campo.codigo === "clasificacion_dano") {
    return { valor: 3 };
  }
  const primera = campo.opciones?.[0];
  if (primera === undefined) {
    throw new Error(`campo ${campo.codigo} sin opciones`);
  }
  return { valor: primera.valor };
}

describe("Postgres como verificador de última instancia", () => {
  it("el hash del PIN no es columna pública", async () => {
    if (!(await nucleoDisponible())) {
      return;
    }
    const publicas = await sql<{ column_name: string }[]>`
      select column_name
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'visitas_potenciales'
        and column_name = 'pin_hash'
    `;
    const privadas = await sql<{ table_name: string }[]>`
      select table_name
      from information_schema.tables
      where table_schema = 'nucleo'
        and table_name = 'visita_pines'
    `;
    expect(publicas).toEqual([]);
    expect(privadas).toEqual([{ table_name: "visita_pines" }]);
  });

  it("una transición ilegal levanta transicion_ilegal", async () => {
    if (!(await nucleoDisponible())) {
      return;
    }
    await expect(
      sql`select nucleo.exigir_transicion_visita('cancelada', 'aceptar', 'aceptada')`,
    ).rejects.toThrow(/transicion_ilegal/);
  });

  it("el seed de formulario existe y el mapeo de clasificacion coincide", async () => {
    if (!(await formulariosDisponibles())) {
      return;
    }
    const forms = await sql<{ codigo: string }[]>`
      select codigo from public.formularios where codigo in ('ais_inspeccion_sismo', 'd1171_evaluacion_rapida')
    `;
    expect(forms.length).toBeGreaterThanOrEqual(1);
    const mapped = await sql<{ mapear_cartel_d1171: string }[]>`
      select nucleo.mapear_cartel_d1171(2)
    `;
    expect(mapped[0]?.mapear_cartel_d1171).toBe("restringido");
    await expect(
      sql`select nucleo.mapear_cartel_d1171(9)`,
    ).rejects.toThrow(/cartel_d1171_invalido/);
  });

  it("evidencias es vista y agregar_evidencia ya no existe", async () => {
    if (!(await formulariosDisponibles())) {
      return;
    }
    const vistas = await sql<{ table_type: string }[]>`
      select table_type
      from information_schema.tables
      where table_schema = 'public' and table_name = 'evidencias'
    `;
    expect(vistas).toEqual([{ table_type: "VIEW" }]);
    const procs = await sql<{ proname: string }[]>`
      select p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where p.proname = 'agregar_evidencia'
    `;
    expect(procs).toEqual([]);
  });
});

describe("cursor y commit del formulario", () => {
  let escenario: EscenarioFormulario | undefined;
  let fdId: string | undefined;
  let localidadId: string | undefined;
  let medidasId: string | undefined;
  let esquemaId: string | undefined;
  let actualTrasPrimera: string | null | undefined;

  beforeAll(async () => {
    if (!(await formulariosDisponibles())) {
      return;
    }
    escenario = await crearEscenario();
    await impersonar(escenario.authEval);
  });

  it("el segundo iniciar no duplica el formulario diligenciado", async () => {
    if (escenario === undefined) {
      return;
    }
    const primero = await iniciar(escenario.vrId);
    const segundo = await iniciar(escenario.vrId);
    expect(primero.ok).toBe(true);
    expect(segundo.id).toBe(primero.id);
    const filas = await sql<{ n: number }[]>`
      select count(*)::int as n
      from public.formularios_diligenciados
      where visita_realizada_id = ${escenario.vrId}::uuid
    `;
    expect(filas[0]?.n).toBe(1);
    fdId = primero.id;
    localidadId = primero.campoActual?.id;
  });

  it("overwrite de cardinalidad uno no mueve el cursor", async () => {
    if (fdId === undefined || localidadId === undefined) {
      return;
    }
    const avanzado = await responder(fdId, localidadId, { texto: "uno" });
    expect(avanzado.ok).toBe(true);
    expect(avanzado.campoActual?.id).not.toBe(localidadId);
    actualTrasPrimera = avanzado.campoActual?.id ?? null;
    const overwrite = await responder(fdId, localidadId, { texto: "dos" });
    expect(overwrite.ok).toBe(true);
    expect(overwrite.campoActual?.id ?? null).toBe(actualTrasPrimera);
    const filas = await sql<{ n: number; texto: string }[]>`
      select count(*)::int as n, max(valor ->> 'texto') as texto
      from public.respuestas
      where formulario_diligenciado_id = ${fdId}::uuid
        and campo_id = ${localidadId}::uuid
    `;
    expect(filas[0]?.n).toBe(1);
    expect(filas[0]?.texto).toBe("dos");
  });

  it("append de cardinalidad muchos no mueve el cursor", async () => {
    if (fdId === undefined) {
      return;
    }
    const campos = await sql<CampoFila[]>`
      select c.id, c.codigo, c.tipo, c.opciones
      from public.campos c
      join public.formularios_diligenciados fd on fd.formulario_id = c.formulario_id
      where fd.id = ${fdId}::uuid
        and c.codigo in ('medidas_seguridad', 'medidas_inmediatas', 'esquema', 'foto_1_fachada')
    `;
    for (const campo of campos) {
      if (campo.codigo === "medidas_seguridad" || campo.codigo === "medidas_inmediatas") {
        medidasId = campo.id;
      }
      if (campo.codigo === "esquema" || campo.codigo === "foto_1_fachada") {
        esquemaId = campo.id;
      }
    }
    if (medidasId === undefined) {
      throw new Error("falta medidas_inmediatas o medidas_seguridad en el seed");
    }
    const cursorAntes = actualTrasPrimera;
    const una = await responder(fdId, medidasId, { valor: 1 });
    const dos = await responder(fdId, medidasId, { valor: 3 });
    expect(una.ok).toBe(true);
    expect(dos.ok).toBe(true);
    expect(dos.campoActual?.id ?? null).toBe(cursorAntes);
    const filas = await sql<{ n: number }[]>`
      select count(*)::int as n
      from public.respuestas
      where formulario_diligenciado_id = ${fdId}::uuid
        and campo_id = ${medidasId}::uuid
    `;
    expect(filas[0]?.n).toBe(2);
  });

  it("commit incompleto no congela", async () => {
    if (fdId === undefined) {
      return;
    }
    const estado = await commit(fdId);
    expect(estado.ok).toBe(false);
    expect(estado.error).toBe("campos_obligatorios_pendientes");
    expect(estado.congelado).toBe(false);
  });

  it("commit completo congela, mapea dictamen y cierra la visita", async () => {
    if (fdId === undefined) {
      return;
    }
    const obligatorios = await sql<CampoFila[]>`
      select c.id, c.codigo, c.tipo, c.opciones
      from public.campos c
      join public.formularios_diligenciados fd on fd.formulario_id = c.formulario_id
      where fd.id = ${fdId}::uuid
        and c.obligatorio
      order by c.orden
    `;
    for (const campo of obligatorios) {
      const estado = await responder(fdId, campo.id, valorDeCampo(campo));
      expect(estado.ok).toBe(true);
    }
    if (esquemaId !== undefined) {
      const foto = await responder(fdId, esquemaId, {
        storage_path: "uid/foto.jpg",
      });
      expect(foto.ok).toBe(true);
    }
    const cerrado = await commit(fdId);
    expect(cerrado.ok).toBe(true);
    expect(cerrado.congelado).toBe(true);
    expect(cerrado.resultado).toBe("restringido");
    const evidencias = await sql<{ storage_path: string }[]>`
      select storage_path from public.evidencias
      where visita_realizada_id = (
        select visita_realizada_id from public.formularios_diligenciados
        where id = ${fdId}::uuid
      )
    `;
    expect(evidencias.length).toBeGreaterThanOrEqual(1);
  });

  it("no se responde un formulario congelado", async () => {
    if (fdId === undefined || localidadId === undefined) {
      return;
    }
    const estado = await responder(fdId, localidadId, { texto: "tarde" });
    expect(estado.ok).toBe(false);
    expect(estado.error).toBe("formulario_congelado");
    expect(estado.congelado).toBe(true);
  });
});

afterAll(async () => {
  await sql.end({ timeout: 1 });
});
