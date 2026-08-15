-- Régimen: los invariantes duros viven aquí. TypeScript solo reduce cuántos
-- errores llegan. Las escrituras de estado pasan por nucleo.*; public.* son
-- wrappers invoker para PostgREST. nucleo no está en api.schemas.

create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;

create schema if not exists nucleo;
revoke all on schema nucleo from public;
grant usage on schema nucleo to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.solicitud_estado as enum (
  'creada',
  'visita_pendiente',
  'en_evaluacion',
  'evaluacion_fallida',
  'evaluacion_parcial',
  'evaluada'
);

create type public.visita_potencial_estado as enum (
  'creada',
  'aceptada',
  'rechazada',
  'cancelada'
);

create type public.talla_construccion as enum ('xs', 's', 'm', 'l', 'xl');

create type public.tipo_evaluador as enum ('voluntario', 'oficial');

create type public.resultado_evaluacion as enum (
  'habitable',
  'restringido',
  'insegura'
);

create type public.causa_cancelacion as enum (
  'pin_fallido',
  'evaluador',
  'solicitante',
  'tomada_por_otro'
);

create type public.tipo_alerta as enum ('pin_incorrecto');

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------

create table public.personas (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users (id) on delete cascade,
  nombre text not null,
  telefono text,
  created_at timestamptz not null default now()
);

create table public.evaluadores (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users (id) on delete cascade,
  tipo public.tipo_evaluador not null,
  tarjeta_profesional_path text not null,
  transporte_propio boolean not null,
  ubicacion_base extensions.geography(point, 4326) not null,
  radio_metros integer not null check (radio_metros > 0 and radio_metros <= 200000),
  ventana tstzrange not null,
  score_confianza numeric(5, 4) not null default 0.5000
    check (score_confianza >= 0.0500 and score_confianza <= 0.9500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.solicitudes (
  id uuid primary key default gen_random_uuid(),
  solicitante_id uuid not null references public.personas (id) on delete restrict,
  ubicacion extensions.geography(point, 4326) not null,
  talla public.talla_construccion not null,
  ventana tstzrange not null,
  estado public.solicitud_estado not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint solicitudes_ventana_no_vacia check (not isempty(ventana))
);

create table public.visitas_potenciales (
  id uuid primary key default gen_random_uuid(),
  solicitud_id uuid not null references public.solicitudes (id) on delete restrict,
  evaluador_id uuid not null references public.evaluadores (id) on delete restrict,
  estado public.visita_potencial_estado not null,
  causa_cancelacion public.causa_cancelacion,
  pin_intentos smallint not null default 0 check (pin_intentos in (0, 1)),
  pin_verificado_en timestamptz,
  ventana_propuesta tstzrange not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint visitas_pin_solo_aceptada check (
    estado = 'aceptada'
    or (pin_verificado_en is null and pin_intentos = 0)
  ),
  constraint visitas_cancelada_con_causa check (
    (estado = 'cancelada' and causa_cancelacion is not null)
    or (estado <> 'cancelada' and causa_cancelacion is null)
  ),
  constraint visitas_verificada_solo_aceptada check (
    pin_verificado_en is null or estado = 'aceptada'
  )
);

-- El hash del PIN no vive en public: PostgREST no debe poder SELECT-arlo.
create table nucleo.visita_pines (
  visita_id uuid primary key references public.visitas_potenciales (id) on delete cascade,
  pin_hash text not null
);

create table public.visitas_realizadas (
  id uuid primary key default gen_random_uuid(),
  solicitud_id uuid not null references public.solicitudes (id) on delete restrict,
  evaluador_id uuid not null references public.evaluadores (id) on delete restrict,
  visita_potencial_id uuid not null unique references public.visitas_potenciales (id) on delete restrict,
  resultado public.resultado_evaluacion,
  anotaciones text,
  concluida_en timestamptz,
  created_at timestamptz not null default now(),
  constraint visitas_realizadas_par unique (solicitud_id, evaluador_id),
  constraint visitas_realizadas_resultado_coherente check (
    (concluida_en is null and resultado is null)
    or (concluida_en is not null and resultado is not null)
  )
);

create table public.evidencias (
  id uuid primary key default gen_random_uuid(),
  visita_realizada_id uuid not null references public.visitas_realizadas (id) on delete cascade,
  campo_formulario text not null,
  storage_path text not null,
  anotacion text,
  captured_at timestamptz not null default now()
);

create table public.alertas (
  id uuid primary key default gen_random_uuid(),
  visita_potencial_id uuid not null references public.visitas_potenciales (id) on delete restrict,
  tipo public.tipo_alerta not null,
  created_at timestamptz not null default now()
);

create table public.calificaciones (
  id uuid primary key default gen_random_uuid(),
  solicitud_id uuid not null references public.solicitudes (id) on delete restrict,
  evaluador_id uuid not null references public.evaluadores (id) on delete restrict,
  estrellas smallint not null check (estrellas between 1 and 5),
  created_at timestamptz not null default now(),
  constraint calificaciones_unicas unique (solicitud_id, evaluador_id)
);

-- ---------------------------------------------------------------------------
-- Índices (FKs, RLS, mailbox, matching geo)
-- ---------------------------------------------------------------------------

create index personas_auth_user_id_idx on public.personas (auth_user_id);
create index evaluadores_auth_user_id_idx on public.evaluadores (auth_user_id);
create index evaluadores_ubicacion_base_idx on public.evaluadores using gist (ubicacion_base);
create index solicitudes_solicitante_id_idx on public.solicitudes (solicitante_id);
create index solicitudes_ubicacion_idx on public.solicitudes using gist (ubicacion);
create index solicitudes_estado_idx on public.solicitudes (estado);
create index visitas_potenciales_solicitud_id_idx on public.visitas_potenciales (solicitud_id);
create index visitas_potenciales_evaluador_id_idx on public.visitas_potenciales (evaluador_id);
create index visitas_potenciales_buzon_idx
  on public.visitas_potenciales (evaluador_id, created_at)
  where estado = 'creada';
create index visitas_realizadas_solicitud_id_idx on public.visitas_realizadas (solicitud_id);
create index visitas_realizadas_evaluador_id_idx on public.visitas_realizadas (evaluador_id);
create index evidencias_visita_realizada_id_idx on public.evidencias (visita_realizada_id);
create index alertas_visita_potencial_id_idx on public.alertas (visita_potencial_id);
create index calificaciones_evaluador_id_idx on public.calificaciones (evaluador_id);

-- ---------------------------------------------------------------------------
-- Transiciones permitidas (tabla de verdad; las funciones consultan esto)
-- ---------------------------------------------------------------------------

create table nucleo.transicion_solicitud (
  desde public.solicitud_estado not null,
  hacia public.solicitud_estado not null,
  evento text not null,
  primary key (desde, evento, hacia)
);

insert into nucleo.transicion_solicitud (desde, hacia, evento) values
  ('creada', 'visita_pendiente', 'publicar'),
  ('visita_pendiente', 'en_evaluacion', 'aceptar'),
  ('en_evaluacion', 'evaluacion_fallida', 'pin_fallido'),
  ('en_evaluacion', 'evaluacion_parcial', 'cerrar_primera'),
  ('en_evaluacion', 'evaluacion_parcial', 'cerrar_discrepancia'),
  ('en_evaluacion', 'evaluada', 'cerrar_consenso'),
  ('en_evaluacion', 'evaluacion_fallida', 'no_encontrada'),
  ('en_evaluacion', 'visita_pendiente', 'visita_abortada'),
  ('evaluacion_parcial', 'en_evaluacion', 'aceptar'),
  ('evaluacion_fallida', 'visita_pendiente', 'reagendar');

create table nucleo.transicion_visita (
  desde public.visita_potencial_estado not null,
  hacia public.visita_potencial_estado not null,
  evento text not null,
  primary key (desde, evento, hacia)
);

insert into nucleo.transicion_visita (desde, hacia, evento) values
  ('creada', 'aceptada', 'aceptar'),
  ('creada', 'rechazada', 'rechazar'),
  ('creada', 'cancelada', 'tomar_otro'),
  ('aceptada', 'cancelada', 'pin_fallido'),
  ('aceptada', 'cancelada', 'evaluador'),
  ('aceptada', 'cancelada', 'solicitante');

-- ---------------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------------

create function nucleo.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger evaluadores_touch
  before update on public.evaluadores
  for each row execute function nucleo.touch_updated_at();

create trigger solicitudes_touch
  before update on public.solicitudes
  for each row execute function nucleo.touch_updated_at();

create trigger visitas_potenciales_touch
  before update on public.visitas_potenciales
  for each row execute function nucleo.touch_updated_at();

create function public.jwt_rol()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select (select auth.jwt()) -> 'app_metadata' ->> 'rol';
$$;

create function nucleo.persona_id_actual()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id
  from public.personas p
  where p.auth_user_id = (select auth.uid());
$$;

create function nucleo.evaluador_id_actual()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select e.id
  from public.evaluadores e
  where e.auth_user_id = (select auth.uid());
$$;

create function nucleo.exigir_transicion_solicitud(
  p_desde public.solicitud_estado,
  p_evento text,
  p_hacia public.solicitud_estado
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from nucleo.transicion_solicitud t
    where t.desde = p_desde
      and t.evento = p_evento
      and t.hacia = p_hacia
  ) then
    raise exception 'transicion_ilegal'
      using errcode = 'P0001',
            detail = format('%s -[%s]-> %s', p_desde, p_evento, p_hacia);
  end if;
end;
$$;

create function nucleo.exigir_transicion_visita(
  p_desde public.visita_potencial_estado,
  p_evento text,
  p_hacia public.visita_potencial_estado
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from nucleo.transicion_visita t
    where t.desde = p_desde
      and t.evento = p_evento
      and t.hacia = p_hacia
  ) then
    raise exception 'transicion_ilegal'
      using errcode = 'P0001',
            detail = format('%s -[%s]-> %s', p_desde, p_evento, p_hacia);
  end if;
end;
$$;

create function nucleo.punto(p_lng double precision, p_lat double precision)
returns extensions.geography
language sql
immutable
set search_path = ''
as $$
  select extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography;
$$;

create function nucleo.generar_pin()
returns text
language sql
volatile
set search_path = ''
as $$
  select lpad(floor(random() * 10000)::integer::text, 4, '0');
$$;

create function nucleo.hash_pin(p_pin text)
returns text
language sql
volatile
set search_path = ''
as $$
  select extensions.crypt(p_pin, extensions.gen_salt('bf'));
$$;

create function nucleo.pin_coincide(p_pin text, p_hash text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select extensions.crypt(p_pin, p_hash) = p_hash;
$$;

create function nucleo.clamp_score(p numeric)
returns numeric
language sql
immutable
as $$
  select least(0.9500, greatest(0.0500, p));
$$;

create function nucleo.limite_visitas_realizadas()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (
    select count(*)
    from public.visitas_realizadas vr
    where vr.solicitud_id = new.solicitud_id
  ) >= 3 then
    raise exception 'max_visitas_realizadas'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger visitas_realizadas_limite
  before insert on public.visitas_realizadas
  for each row execute function nucleo.limite_visitas_realizadas();

-- ---------------------------------------------------------------------------
-- Escrituras (security definer; cheques de identidad adentro)
-- ---------------------------------------------------------------------------

create function nucleo.registrar_persona(p_nombre text, p_telefono text)
returns public.personas
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_row public.personas;
begin
  if v_uid is null then
    raise exception 'no_autenticado' using errcode = 'P0001';
  end if;
  insert into public.personas (auth_user_id, nombre, telefono)
  values (v_uid, p_nombre, p_telefono)
  returning * into v_row;
  return v_row;
end;
$$;

create function nucleo.registrar_evaluador(
  p_tipo public.tipo_evaluador,
  p_tarjeta_profesional_path text,
  p_transporte_propio boolean,
  p_lng double precision,
  p_lat double precision,
  p_radio_metros integer,
  p_ventana tstzrange
)
returns public.evaluadores
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_row public.evaluadores;
begin
  if v_uid is null then
    raise exception 'no_autenticado' using errcode = 'P0001';
  end if;
  insert into public.evaluadores (
    auth_user_id, tipo, tarjeta_profesional_path, transporte_propio,
    ubicacion_base, radio_metros, ventana
  ) values (
    v_uid, p_tipo, p_tarjeta_profesional_path, p_transporte_propio,
    nucleo.punto(p_lng, p_lat), p_radio_metros, p_ventana
  )
  returning * into v_row;
  return v_row;
end;
$$;

create function nucleo.crear_solicitud(
  p_lng double precision,
  p_lat double precision,
  p_talla public.talla_construccion,
  p_ventana tstzrange
)
returns public.solicitudes
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_persona uuid := nucleo.persona_id_actual();
  v_row public.solicitudes;
begin
  if v_persona is null then
    raise exception 'no_es_solicitante' using errcode = 'P0001';
  end if;
  insert into public.solicitudes (
    solicitante_id, ubicacion, talla, ventana, estado
  ) values (
    v_persona, nucleo.punto(p_lng, p_lat), p_talla, p_ventana, 'visita_pendiente'
  )
  returning * into v_row;
  return v_row;
end;
$$;

create function nucleo.aceptar_visita(p_visita_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eval uuid := nucleo.evaluador_id_actual();
  v_row public.visitas_potenciales;
  v_sol public.solicitudes;
  v_pin text;
begin
  if v_eval is null then
    raise exception 'no_es_evaluador' using errcode = 'P0001';
  end if;

  select * into v_row
  from public.visitas_potenciales
  where id = p_visita_id
  for update;

  if not found then
    raise exception 'visita_no_existe' using errcode = 'P0001';
  end if;
  if v_row.evaluador_id is distinct from v_eval then
    raise exception 'visita_ajena' using errcode = 'P0001';
  end if;

  perform nucleo.exigir_transicion_visita(v_row.estado, 'aceptar', 'aceptada');

  select * into v_sol
  from public.solicitudes
  where id = v_row.solicitud_id
  for update;

  perform nucleo.exigir_transicion_solicitud(v_sol.estado, 'aceptar', 'en_evaluacion');

  v_pin := nucleo.generar_pin();

  update public.visitas_potenciales
  set estado = 'aceptada',
      pin_intentos = 0
  where id = v_row.id;

  insert into nucleo.visita_pines (visita_id, pin_hash)
  values (v_row.id, nucleo.hash_pin(v_pin));

  update public.solicitudes
  set estado = 'en_evaluacion'
  where id = v_sol.id;

  update public.visitas_potenciales
  set estado = 'cancelada',
      causa_cancelacion = 'tomada_por_otro'
  where solicitud_id = v_row.solicitud_id
    and id <> v_row.id
    and estado = 'creada';

  return jsonb_build_object(
    'visita_id', v_row.id,
    'solicitud_id', v_row.solicitud_id,
    'estado', 'aceptada',
    'pin', v_pin
  );
end;
$$;

create function nucleo.rechazar_visita(p_visita_id uuid)
returns public.visitas_potenciales
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eval uuid := nucleo.evaluador_id_actual();
  v_row public.visitas_potenciales;
begin
  if v_eval is null then
    raise exception 'no_es_evaluador' using errcode = 'P0001';
  end if;

  select * into v_row
  from public.visitas_potenciales
  where id = p_visita_id
  for update;

  if not found then
    raise exception 'visita_no_existe' using errcode = 'P0001';
  end if;
  if v_row.evaluador_id is distinct from v_eval then
    raise exception 'visita_ajena' using errcode = 'P0001';
  end if;

  perform nucleo.exigir_transicion_visita(v_row.estado, 'rechazar', 'rechazada');

  update public.visitas_potenciales
  set estado = 'rechazada'
  where id = v_row.id
  returning * into v_row;

  return v_row;
end;
$$;

create function nucleo.regenerar_pin(p_visita_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eval uuid := nucleo.evaluador_id_actual();
  v_row public.visitas_potenciales;
  v_pin text;
begin
  if v_eval is null then
    raise exception 'no_es_evaluador' using errcode = 'P0001';
  end if;

  select * into v_row
  from public.visitas_potenciales
  where id = p_visita_id
  for update;

  if not found or v_row.evaluador_id is distinct from v_eval then
    raise exception 'visita_ajena' using errcode = 'P0001';
  end if;
  if v_row.estado is distinct from 'aceptada' or v_row.pin_verificado_en is not null then
    raise exception 'transicion_ilegal' using errcode = 'P0001';
  end if;

  v_pin := nucleo.generar_pin();

  update nucleo.visita_pines
  set pin_hash = nucleo.hash_pin(v_pin)
  where visita_id = v_row.id;

  return jsonb_build_object(
    'visita_id', v_row.id,
    'estado', 'aceptada',
    'pin', v_pin
  );
end;
$$;

create function nucleo.verificar_pin(p_visita_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_persona uuid := nucleo.persona_id_actual();
  v_row public.visitas_potenciales;
  v_sol public.solicitudes;
  v_hash text;
  v_ok boolean;
begin
  if v_persona is null then
    raise exception 'no_es_solicitante' using errcode = 'P0001';
  end if;
  if p_pin is null or p_pin !~ '^\d{4}$' then
    raise exception 'pin_invalido' using errcode = 'P0001';
  end if;

  select * into v_row
  from public.visitas_potenciales
  where id = p_visita_id
  for update;

  if not found then
    raise exception 'visita_no_existe' using errcode = 'P0001';
  end if;

  select * into v_sol
  from public.solicitudes
  where id = v_row.solicitud_id
  for update;

  if v_sol.solicitante_id is distinct from v_persona then
    raise exception 'solicitud_ajena' using errcode = 'P0001';
  end if;
  if v_row.estado is distinct from 'aceptada' or v_row.pin_verificado_en is not null then
    raise exception 'transicion_ilegal' using errcode = 'P0001';
  end if;

  select pin_hash into v_hash
  from nucleo.visita_pines
  where visita_id = v_row.id;

  v_ok := nucleo.pin_coincide(p_pin, v_hash);

  if v_ok then
    update public.visitas_potenciales
    set pin_verificado_en = now()
    where id = v_row.id;

    delete from nucleo.visita_pines where visita_id = v_row.id;

    insert into public.visitas_realizadas (
      solicitud_id, evaluador_id, visita_potencial_id
    ) values (
      v_sol.id, v_row.evaluador_id, v_row.id
    );

    return jsonb_build_object('ok', true, 'solicitud_estado', v_sol.estado);
  end if;

  insert into public.alertas (visita_potencial_id, tipo)
  values (v_row.id, 'pin_incorrecto');

  if v_row.pin_intentos = 0 then
    update public.visitas_potenciales
    set pin_intentos = 1
    where id = v_row.id;
    return jsonb_build_object('ok', false, 'intentos', 1, 'alerta', true);
  end if;

  perform nucleo.exigir_transicion_visita(v_row.estado, 'pin_fallido', 'cancelada');
  perform nucleo.exigir_transicion_solicitud(v_sol.estado, 'pin_fallido', 'evaluacion_fallida');

  update public.visitas_potenciales
  set estado = 'cancelada',
      causa_cancelacion = 'pin_fallido'
  where id = v_row.id;

  delete from nucleo.visita_pines where visita_id = v_row.id;

  update public.solicitudes
  set estado = 'evaluacion_fallida'
  where id = v_sol.id;

  return jsonb_build_object(
    'ok', false,
    'cancelada', true,
    'solicitud_estado', 'evaluacion_fallida'
  );
end;
$$;

create function nucleo.concluir_visita(
  p_visita_realizada_id uuid,
  p_resultado public.resultado_evaluacion,
  p_anotaciones text
)
returns public.visitas_realizadas
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eval uuid := nucleo.evaluador_id_actual();
  v_vr public.visitas_realizadas;
  v_sol public.solicitudes;
  v_pares integer;
  v_distintos integer;
  v_hacia public.solicitud_estado;
  v_evento text;
begin
  if v_eval is null then
    raise exception 'no_es_evaluador' using errcode = 'P0001';
  end if;

  select * into v_vr
  from public.visitas_realizadas
  where id = p_visita_realizada_id
  for update;

  if not found or v_vr.evaluador_id is distinct from v_eval then
    raise exception 'visita_ajena' using errcode = 'P0001';
  end if;
  if v_vr.concluida_en is not null then
    raise exception 'transicion_ilegal' using errcode = 'P0001';
  end if;

  select * into v_sol
  from public.solicitudes
  where id = v_vr.solicitud_id
  for update;

  update public.visitas_realizadas
  set resultado = p_resultado,
      anotaciones = p_anotaciones,
      concluida_en = now()
  where id = v_vr.id
  returning * into v_vr;

  select count(*) filter (where concluida_en is not null),
         count(distinct resultado) filter (where concluida_en is not null)
    into v_pares, v_distintos
  from public.visitas_realizadas
  where solicitud_id = v_sol.id;

  if v_pares = 1 then
    v_evento := 'cerrar_primera';
    v_hacia := 'evaluacion_parcial';
  elsif v_distintos = 1 or v_pares >= 3 then
    v_evento := 'cerrar_consenso';
    v_hacia := 'evaluada';
  else
    v_evento := 'cerrar_discrepancia';
    v_hacia := 'evaluacion_parcial';
  end if;

  perform nucleo.exigir_transicion_solicitud(v_sol.estado, v_evento, v_hacia);

  update public.solicitudes
  set estado = v_hacia
  where id = v_sol.id;

  if v_hacia = 'evaluada' then
    perform nucleo.actualizar_scores(v_sol.id);
  end if;

  return v_vr;
end;
$$;

create function nucleo.marcar_no_encontrada(p_visita_realizada_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eval uuid := nucleo.evaluador_id_actual();
  v_vr public.visitas_realizadas;
  v_sol public.solicitudes;
begin
  select * into v_vr
  from public.visitas_realizadas
  where id = p_visita_realizada_id
  for update;

  if not found or v_vr.evaluador_id is distinct from v_eval then
    raise exception 'visita_ajena' using errcode = 'P0001';
  end if;

  select * into v_sol
  from public.solicitudes
  where id = v_vr.solicitud_id
  for update;

  perform nucleo.exigir_transicion_solicitud(v_sol.estado, 'no_encontrada', 'evaluacion_fallida');

  delete from public.visitas_realizadas where id = v_vr.id;

  update public.visitas_potenciales
  set estado = 'cancelada',
      causa_cancelacion = 'evaluador'
  where id = v_vr.visita_potencial_id;

  delete from nucleo.visita_pines where visita_id = v_vr.visita_potencial_id;

  update public.solicitudes
  set estado = 'evaluacion_fallida'
  where id = v_sol.id;
end;
$$;

create function nucleo.actualizar_scores(p_solicitud_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r1 public.resultado_evaluacion;
  v_r2 public.resultado_evaluacion;
  v_e1 uuid;
  v_e2 uuid;
  v_delta numeric;
begin
  select vr.resultado, vr.evaluador_id
    into v_r1, v_e1
  from public.visitas_realizadas vr
  where vr.solicitud_id = p_solicitud_id
    and vr.concluida_en is not null
  order by vr.concluida_en
  limit 1;

  select vr.resultado, vr.evaluador_id
    into v_r2, v_e2
  from public.visitas_realizadas vr
  where vr.solicitud_id = p_solicitud_id
    and vr.concluida_en is not null
    and vr.evaluador_id <> v_e1
  order by vr.concluida_en
  limit 1;

  if v_e2 is null then
    return;
  end if;

  v_delta := case when v_r1 = v_r2 then 0.0500 else -0.0800 end;

  update public.evaluadores
  set score_confianza = nucleo.clamp_score(score_confianza + v_delta)
  where id in (v_e1, v_e2);
end;
$$;

create function nucleo.calificar_evaluador(
  p_solicitud_id uuid,
  p_evaluador_id uuid,
  p_estrellas integer
)
returns public.calificaciones
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_persona uuid := nucleo.persona_id_actual();
  v_sol public.solicitudes;
  v_row public.calificaciones;
begin
  select * into v_sol
  from public.solicitudes
  where id = p_solicitud_id;

  if not found or v_sol.solicitante_id is distinct from v_persona then
    raise exception 'solicitud_ajena' using errcode = 'P0001';
  end if;
  if v_sol.estado not in ('evaluacion_parcial', 'evaluada') then
    raise exception 'transicion_ilegal' using errcode = 'P0001';
  end if;
  if not exists (
    select 1
    from public.visitas_realizadas vr
    where vr.solicitud_id = p_solicitud_id
      and vr.evaluador_id = p_evaluador_id
      and vr.concluida_en is not null
  ) then
    raise exception 'evaluador_no_visito' using errcode = 'P0001';
  end if;

  insert into public.calificaciones (solicitud_id, evaluador_id, estrellas)
  values (p_solicitud_id, p_evaluador_id, p_estrellas)
  returning * into v_row;
  return v_row;
end;
$$;

create function nucleo.agregar_evidencia(
  p_visita_realizada_id uuid,
  p_campo_formulario text,
  p_storage_path text,
  p_anotacion text
)
returns public.evidencias
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eval uuid := nucleo.evaluador_id_actual();
  v_vr public.visitas_realizadas;
  v_row public.evidencias;
begin
  select * into v_vr
  from public.visitas_realizadas
  where id = p_visita_realizada_id;

  if not found or v_vr.evaluador_id is distinct from v_eval then
    raise exception 'visita_ajena' using errcode = 'P0001';
  end if;
  if v_vr.concluida_en is not null then
    raise exception 'transicion_ilegal' using errcode = 'P0001';
  end if;

  insert into public.evidencias (
    visita_realizada_id, campo_formulario, storage_path, anotacion
  ) values (
    p_visita_realizada_id, p_campo_formulario, p_storage_path, p_anotacion
  )
  returning * into v_row;
  return v_row;
end;
$$;

create function nucleo.generar_visitas_potenciales()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  if (select public.jwt_rol()) is distinct from 'coordinacion'
     and (select auth.role()) is distinct from 'service_role' then
    raise exception 'no_autorizado' using errcode = 'P0001';
  end if;

  update public.solicitudes s
  set estado = 'visita_pendiente'
  where s.estado = 'evaluacion_fallida'
    and exists (
      select 1 from nucleo.transicion_solicitud t
      where t.desde = 'evaluacion_fallida'
        and t.evento = 'reagendar'
        and t.hacia = 'visita_pendiente'
    );

  insert into public.visitas_potenciales (
    solicitud_id, evaluador_id, estado, ventana_propuesta
  )
  select s.id, e.id, 'creada', s.ventana
  from public.solicitudes s
  join public.evaluadores e
    on extensions.st_dwithin(s.ubicacion, e.ubicacion_base, e.radio_metros)
   and e.ventana && s.ventana
  where s.estado in ('visita_pendiente', 'evaluacion_parcial')
    and not exists (
      select 1
      from public.visitas_potenciales vp
      where vp.solicitud_id = s.id
        and vp.estado = 'aceptada'
    )
    and not exists (
      select 1
      from public.visitas_potenciales vp
      where vp.solicitud_id = s.id
        and vp.evaluador_id = e.id
        and vp.estado in ('creada', 'aceptada', 'rechazada')
    )
    and not exists (
      select 1
      from public.visitas_realizadas vr
      where vr.solicitud_id = s.id
        and vr.evaluador_id = e.id
    )
    and (
      select count(*)
      from public.visitas_realizadas vr
      where vr.solicitud_id = s.id
    ) < 3
    and (
      select count(*)
      from public.visitas_potenciales vp
      where vp.solicitud_id = s.id
        and vp.estado = 'creada'
    ) < 5;

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------
-- Wrappers públicos (invoker). PostgREST solo ve public.
-- ---------------------------------------------------------------------------

create function public.registrar_persona(nombre text, telefono text)
returns public.personas
language sql
security invoker
set search_path = ''
as $$
  select * from nucleo.registrar_persona(nombre, telefono);
$$;

create function public.registrar_evaluador(
  tipo public.tipo_evaluador,
  tarjeta_profesional_path text,
  transporte_propio boolean,
  lng double precision,
  lat double precision,
  radio_metros integer,
  ventana tstzrange
)
returns public.evaluadores
language sql
security invoker
set search_path = ''
as $$
  select * from nucleo.registrar_evaluador(
    tipo, tarjeta_profesional_path, transporte_propio, lng, lat, radio_metros, ventana
  );
$$;

create function public.crear_solicitud(
  lng double precision,
  lat double precision,
  talla public.talla_construccion,
  ventana tstzrange
)
returns public.solicitudes
language sql
security invoker
set search_path = ''
as $$
  select * from nucleo.crear_solicitud(lng, lat, talla, ventana);
$$;

create function public.aceptar_visita(visita_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.aceptar_visita(visita_id);
$$;

create function public.rechazar_visita(visita_id uuid)
returns public.visitas_potenciales
language sql
security invoker
set search_path = ''
as $$
  select * from nucleo.rechazar_visita(visita_id);
$$;

create function public.regenerar_pin(visita_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.regenerar_pin(visita_id);
$$;

create function public.verificar_pin(visita_id uuid, pin text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.verificar_pin(visita_id, pin);
$$;

create function public.concluir_visita(
  visita_realizada_id uuid,
  resultado public.resultado_evaluacion,
  anotaciones text
)
returns public.visitas_realizadas
language sql
security invoker
set search_path = ''
as $$
  select * from nucleo.concluir_visita(visita_realizada_id, resultado, anotaciones);
$$;

create function public.marcar_no_encontrada(visita_realizada_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
  select nucleo.marcar_no_encontrada(visita_realizada_id);
$$;

create function public.calificar_evaluador(
  solicitud_id uuid,
  evaluador_id uuid,
  estrellas integer
)
returns public.calificaciones
language sql
security invoker
set search_path = ''
as $$
  select * from nucleo.calificar_evaluador(solicitud_id, evaluador_id, estrellas);
$$;

create function public.agregar_evidencia(
  visita_realizada_id uuid,
  campo_formulario text,
  storage_path text,
  anotacion text
)
returns public.evidencias
language sql
security invoker
set search_path = ''
as $$
  select * from nucleo.agregar_evidencia(
    visita_realizada_id, campo_formulario, storage_path, anotacion
  );
$$;

create function public.generar_visitas_potenciales()
returns integer
language sql
security invoker
set search_path = ''
as $$
  select nucleo.generar_visitas_potenciales();
$$;

-- Vista API: nunca expone pin_hash. security_invoker respeta RLS de la tabla.
create view public.visitas_potenciales_api
with (security_invoker = true) as
select
  id,
  solicitud_id,
  evaluador_id,
  estado,
  causa_cancelacion,
  pin_intentos,
  pin_verificado_en,
  ventana_propuesta,
  created_at,
  updated_at
from public.visitas_potenciales;

create view public.buzon_evaluador
with (security_invoker = true) as
select
  vp.id,
  vp.solicitud_id,
  vp.ventana_propuesta,
  vp.created_at,
  s.talla,
  s.ubicacion
from public.visitas_potenciales vp
join public.solicitudes s on s.id = vp.solicitud_id
where vp.estado = 'creada'
  and vp.evaluador_id = nucleo.evaluador_id_actual();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.personas enable row level security;
alter table public.evaluadores enable row level security;
alter table public.solicitudes enable row level security;
alter table public.visitas_potenciales enable row level security;
alter table public.visitas_realizadas enable row level security;
alter table public.evidencias enable row level security;
alter table public.alertas enable row level security;
alter table public.calificaciones enable row level security;

create policy personas_select on public.personas
  for select to authenticated
  using (
    auth_user_id = (select auth.uid())
    or (select public.jwt_rol()) = 'coordinacion'
  );

create policy evaluadores_select on public.evaluadores
  for select to authenticated
  using (
    auth_user_id = (select auth.uid())
    or (select public.jwt_rol()) = 'coordinacion'
    or exists (
      select 1
      from public.visitas_potenciales vp
      join public.solicitudes s on s.id = vp.solicitud_id
      join public.personas p on p.id = s.solicitante_id
      where vp.evaluador_id = evaluadores.id
        and p.auth_user_id = (select auth.uid())
        and vp.estado = 'aceptada'
    )
  );

create policy solicitudes_select on public.solicitudes
  for select to authenticated
  using (
    solicitante_id = nucleo.persona_id_actual()
    or (select public.jwt_rol()) = 'coordinacion'
    or exists (
      select 1
      from public.visitas_potenciales vp
      where vp.solicitud_id = solicitudes.id
        and vp.evaluador_id = nucleo.evaluador_id_actual()
    )
  );

create policy visitas_potenciales_select on public.visitas_potenciales
  for select to authenticated
  using (
    evaluador_id = nucleo.evaluador_id_actual()
    or (select public.jwt_rol()) = 'coordinacion'
    or exists (
      select 1
      from public.solicitudes s
      where s.id = visitas_potenciales.solicitud_id
        and s.solicitante_id = nucleo.persona_id_actual()
    )
  );

create policy visitas_realizadas_select on public.visitas_realizadas
  for select to authenticated
  using (
    evaluador_id = nucleo.evaluador_id_actual()
    or (select public.jwt_rol()) = 'coordinacion'
    or exists (
      select 1
      from public.solicitudes s
      where s.id = visitas_realizadas.solicitud_id
        and s.solicitante_id = nucleo.persona_id_actual()
    )
  );

create policy evidencias_select on public.evidencias
  for select to authenticated
  using (
    exists (
      select 1
      from public.visitas_realizadas vr
      where vr.id = evidencias.visita_realizada_id
        and (
          vr.evaluador_id = nucleo.evaluador_id_actual()
          or (select public.jwt_rol()) = 'coordinacion'
          or exists (
            select 1 from public.solicitudes s
            where s.id = vr.solicitud_id
              and s.solicitante_id = nucleo.persona_id_actual()
          )
        )
    )
  );

create policy alertas_select on public.alertas
  for select to authenticated
  using ((select public.jwt_rol()) = 'coordinacion');

create policy calificaciones_select on public.calificaciones
  for select to authenticated
  using (
    evaluador_id = nucleo.evaluador_id_actual()
    or (select public.jwt_rol()) = 'coordinacion'
    or exists (
      select 1 from public.solicitudes s
      where s.id = calificaciones.solicitud_id
        and s.solicitante_id = nucleo.persona_id_actual()
    )
  );

-- ---------------------------------------------------------------------------
-- Privileges: lecturas vía SELECT; escrituras solo RPC
-- ---------------------------------------------------------------------------

revoke all on all tables in schema public from anon, authenticated, public;
revoke all on all routines in schema public from anon, authenticated, public;
revoke all on all routines in schema nucleo from anon, authenticated, public;

grant select on public.personas to authenticated;
grant select on public.evaluadores to authenticated;
grant select on public.solicitudes to authenticated;
grant select on public.visitas_potenciales to authenticated;
grant select on public.visitas_realizadas to authenticated;
grant select on public.evidencias to authenticated;
grant select on public.alertas to authenticated;
grant select on public.calificaciones to authenticated;
grant select on public.visitas_potenciales_api to authenticated;
grant select on public.buzon_evaluador to authenticated;

grant execute on function public.jwt_rol() to authenticated;
grant execute on function public.registrar_persona(text, text) to authenticated;
grant execute on function public.registrar_evaluador(
  public.tipo_evaluador, text, boolean, double precision, double precision, integer, tstzrange
) to authenticated;
grant execute on function public.crear_solicitud(
  double precision, double precision, public.talla_construccion, tstzrange
) to authenticated;
grant execute on function public.aceptar_visita(uuid) to authenticated;
grant execute on function public.rechazar_visita(uuid) to authenticated;
grant execute on function public.regenerar_pin(uuid) to authenticated;
grant execute on function public.verificar_pin(uuid, text) to authenticated;
grant execute on function public.concluir_visita(
  uuid, public.resultado_evaluacion, text
) to authenticated;
grant execute on function public.marcar_no_encontrada(uuid) to authenticated;
grant execute on function public.calificar_evaluador(uuid, uuid, integer) to authenticated;
grant execute on function public.agregar_evidencia(uuid, text, text, text) to authenticated;
grant execute on function public.generar_visitas_potenciales() to authenticated;

grant execute on function nucleo.registrar_persona(text, text) to authenticated;
grant execute on function nucleo.registrar_evaluador(
  public.tipo_evaluador, text, boolean, double precision, double precision, integer, tstzrange
) to authenticated;
grant execute on function nucleo.crear_solicitud(
  double precision, double precision, public.talla_construccion, tstzrange
) to authenticated;
grant execute on function nucleo.aceptar_visita(uuid) to authenticated;
grant execute on function nucleo.rechazar_visita(uuid) to authenticated;
grant execute on function nucleo.regenerar_pin(uuid) to authenticated;
grant execute on function nucleo.verificar_pin(uuid, text) to authenticated;
grant execute on function nucleo.concluir_visita(
  uuid, public.resultado_evaluacion, text
) to authenticated;
grant execute on function nucleo.marcar_no_encontrada(uuid) to authenticated;
grant execute on function nucleo.calificar_evaluador(uuid, uuid, integer) to authenticated;
grant execute on function nucleo.agregar_evidencia(uuid, text, text, text) to authenticated;
grant execute on function nucleo.generar_visitas_potenciales() to authenticated;
grant execute on function nucleo.persona_id_actual() to authenticated;
grant execute on function nucleo.evaluador_id_actual() to authenticated;

revoke all on table nucleo.visita_pines from public, anon, authenticated;
revoke all on table nucleo.transicion_solicitud from public, anon, authenticated;
revoke all on table nucleo.transicion_visita from public, anon, authenticated;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  (
    'tarjetas-profesionales',
    'tarjetas-profesionales',
    false,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
  ),
  (
    'evidencias',
    'evidencias',
    false,
    10485760,
    array['image/jpeg', 'image/png', 'image/webp']
  )
on conflict (id) do nothing;

create policy tarjetas_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'tarjetas-profesionales'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy tarjetas_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'tarjetas-profesionales'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or (select public.jwt_rol()) = 'coordinacion'
    )
  );

create policy evidencias_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'evidencias'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy evidencias_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'evidencias'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or (select public.jwt_rol()) = 'coordinacion'
    )
  );
