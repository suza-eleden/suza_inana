-- Migración: Metamodelo de formularios extensibles, versionamiento y rol de coordinación
-- Fecha: 2026-09-01

-- ---------------------------------------------------------------------------
-- 1. Rol de coordinación y administración de formularios
-- ---------------------------------------------------------------------------

create table if not exists public.coordinadores (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users (id) on delete cascade,
  nombre text not null,
  cargo text,
  created_at timestamptz not null default now()
);

alter table public.coordinadores enable row level security;

create policy coordinadores_select_authenticated on public.coordinadores
  for select to authenticated using (true);

create or replace function nucleo.es_coordinador()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.coordinadores
    where auth_user_id = auth.uid()
  );
$$;

create or replace function nucleo.coordinador_id_actual()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.coordinadores
  where auth_user_id = auth.uid()
  limit 1;
$$;

grant execute on function nucleo.es_coordinador() to authenticated;
grant execute on function nucleo.coordinador_id_actual() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Versionamiento y estados en formularios
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'estado_formulario_def') then
    create type public.estado_formulario_def as enum ('borrador', 'publicado', 'archivado');
  end if;
end;
$$;

alter table public.formularios
  drop constraint if exists formularios_codigo_key;

alter table public.formularios
  add column if not exists estado public.estado_formulario_def not null default 'publicado',
  add column if not exists descripcion text,
  add column if not exists publicado_en timestamptz default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'formularios_codigo_version_key'
  ) then
    alter table public.formularios
      add constraint formularios_codigo_version_key unique (codigo, version);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Desacoplamiento de formularios diligenciados y autoría
-- ---------------------------------------------------------------------------

alter table public.formularios_diligenciados
  alter column visita_realizada_id drop not null;

alter table public.formularios_diligenciados
  add column if not exists autor_id uuid references auth.users (id) on delete set null default auth.uid(),
  add column if not exists solicitud_id uuid references public.solicitudes (id) on delete set null;

alter table public.formularios_diligenciados
  drop constraint if exists formularios_diligenciados_visita_realizada_id_key;

create unique index if not exists formularios_diligenciados_visita_realizada_unique
  on public.formularios_diligenciados (visita_realizada_id)
  where visita_realizada_id is not null;

create index if not exists formularios_diligenciados_autor_id_idx
  on public.formularios_diligenciados (autor_id);

create index if not exists formularios_diligenciados_solicitud_id_idx
  on public.formularios_diligenciados (solicitud_id);

-- ---------------------------------------------------------------------------
-- 4. Helpers de autorización de diligenciamiento
-- ---------------------------------------------------------------------------

create or replace function nucleo.exigir_autor_o_evaluador_del_fd(p_fd_id uuid)
returns public.formularios_diligenciados
language plpgsql
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_eval uuid := nucleo.evaluador_id_actual();
  v_fd public.formularios_diligenciados;
  v_vr public.visitas_realizadas;
begin
  if v_uid is null then
    raise exception 'no_autenticado' using errcode = 'P0001';
  end if;

  select * into v_fd
  from public.formularios_diligenciados
  where id = p_fd_id
  for update;

  if not found then
    raise exception 'formulario_no_existe' using errcode = 'P0001';
  end if;

  -- Si es formulario vinculado a visita, verificar evaluador asignado
  if v_fd.visita_realizada_id is not null then
    select * into v_vr
    from public.visitas_realizadas
    where id = v_fd.visita_realizada_id;

    if v_vr.evaluador_id is distinct from v_eval and not nucleo.es_coordinador() then
      raise exception 'visita_ajena' using errcode = 'P0001';
    end if;
  else
    -- Si es formulario autónomo, verificar autoría
    if v_fd.autor_id is distinct from v_uid and not nucleo.es_coordinador() then
      raise exception 'formulario_ajeno' using errcode = 'P0001';
    end if;
  end if;

  return v_fd;
end;
$$;

-- Mantener exigencia de evaluador para retrocompatibilidad interna
create or replace function nucleo.exigir_evaluador_del_fd(p_fd_id uuid)
returns public.formularios_diligenciados
language plpgsql
set search_path = ''
as $$
begin
  return nucleo.exigir_autor_o_evaluador_del_fd(p_fd_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Estado JSON extendido
-- ---------------------------------------------------------------------------

create or replace function nucleo.estado_formulario_json(p_fd_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_fd public.formularios_diligenciados;
  v_form public.formularios;
  v_actual public.campos;
  v_siguiente public.campos;
begin
  select * into v_fd
  from public.formularios_diligenciados
  where id = p_fd_id;

  if not found then
    raise exception 'formulario_no_existe' using errcode = 'P0001';
  end if;

  select * into v_form
  from public.formularios
  where id = v_fd.formulario_id;

  if v_fd.campo_actual_id is not null then
    select * into v_actual from public.campos where id = v_fd.campo_actual_id;
  end if;
  if v_fd.campo_siguiente_id is not null then
    select * into v_siguiente from public.campos where id = v_fd.campo_siguiente_id;
  end if;

  return jsonb_build_object(
    'id', v_fd.id,
    'formulario_id', v_fd.formulario_id,
    'formulario_codigo', v_form.codigo,
    'formulario_version', v_form.version,
    'visita_realizada_id', v_fd.visita_realizada_id,
    'solicitud_id', v_fd.solicitud_id,
    'autor_id', v_fd.autor_id,
    'campo_actual_id', v_fd.campo_actual_id,
    'campo_siguiente_id', v_fd.campo_siguiente_id,
    'campo_actual', nucleo.campo_publico(v_actual),
    'campo_siguiente', nucleo.campo_publico(v_siguiente),
    'campos_diligenciados', nucleo.campos_diligenciados(p_fd_id),
    'congelado', v_fd.congelado_en is not null,
    'completo_obligatorio', nucleo.completo_obligatorio(p_fd_id)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. RPCs de Gestión de Formularios (Coordinación)
-- ---------------------------------------------------------------------------

create or replace function nucleo.crear_formulario(
  p_codigo text,
  p_nombre text,
  p_descripcion text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form public.formularios;
begin
  if not nucleo.es_coordinador() then
    raise exception 'no_es_coordinador' using errcode = 'P0001';
  end if;

  if coalesce(p_codigo, '') = '' or coalesce(p_nombre, '') = '' then
    raise exception 'parametros_invalidos' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.formularios where codigo = p_codigo and version = 1) then
    raise exception 'formulario_ya_existe' using errcode = 'P0001';
  end if;

  insert into public.formularios (
    codigo, nombre, version, estado, descripcion, publicado_en
  ) values (
    p_codigo, p_nombre, 1, 'borrador', p_descripcion, null
  )
  returning * into v_form;

  return jsonb_build_object(
    'ok', true,
    'formulario_id', v_form.id,
    'codigo', v_form.codigo,
    'version', v_form.version,
    'estado', v_form.estado
  );
end;
$$;

create or replace function nucleo.publicar_formulario(p_formulario_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form public.formularios;
begin
  if not nucleo.es_coordinador() then
    raise exception 'no_es_coordinador' using errcode = 'P0001';
  end if;

  select * into v_form
  from public.formularios
  where id = p_formulario_id
  for update;

  if not found then
    raise exception 'formulario_no_existe' using errcode = 'P0001';
  end if;

  -- Al publicar, archivar versiones anteriores del mismo código
  update public.formularios
  set estado = 'archivado'
  where codigo = v_form.codigo
    and id <> v_form.id
    and estado = 'publicado';

  update public.formularios
  set estado = 'publicado',
      publicado_en = now()
  where id = p_formulario_id
  returning * into v_form;

  return jsonb_build_object(
    'ok', true,
    'formulario_id', v_form.id,
    'codigo', v_form.codigo,
    'version', v_form.version,
    'estado', v_form.estado,
    'publicado_en', v_form.publicado_en
  );
end;
$$;

create or replace function nucleo.archivar_formulario(p_formulario_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form public.formularios;
begin
  if not nucleo.es_coordinador() then
    raise exception 'no_es_coordinador' using errcode = 'P0001';
  end if;

  update public.formularios
  set estado = 'archivado'
  where id = p_formulario_id
  returning * into v_form;

  if not found then
    raise exception 'formulario_no_existe' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'ok', true,
    'formulario_id', v_form.id,
    'codigo', v_form.codigo,
    'version', v_form.version,
    'estado', v_form.estado
  );
end;
$$;

create or replace function nucleo.crear_nueva_version_formulario(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max_version integer;
  v_ultima_form public.formularios;
  v_nueva_form public.formularios;
begin
  if not nucleo.es_coordinador() then
    raise exception 'no_es_coordinador' using errcode = 'P0001';
  end if;

  select max(version) into v_max_version
  from public.formularios
  where codigo = p_codigo;

  if v_max_version is null then
    raise exception 'formulario_no_existe' using errcode = 'P0001';
  end if;

  select * into v_ultima_form
  from public.formularios
  where codigo = p_codigo and version = v_max_version;

  insert into public.formularios (
    codigo, nombre, version, estado, descripcion, publicado_en
  ) values (
    p_codigo, v_ultima_form.nombre, v_max_version + 1, 'borrador', v_ultima_form.descripcion, null
  )
  returning * into v_nueva_form;

  -- Clonar campos de la versión previa
  insert into public.campos (
    formulario_id, codigo, tipo, prompt, orden, obligatorio, cardinalidad, opciones
  )
  select
    v_nueva_form.id, c.codigo, c.tipo, c.prompt, c.orden, c.obligatorio, c.cardinalidad, c.opciones
  from public.campos c
  where c.formulario_id = v_ultima_form.id
  order by c.orden;

  return jsonb_build_object(
    'ok', true,
    'formulario_id', v_nueva_form.id,
    'codigo', v_nueva_form.codigo,
    'version', v_nueva_form.version,
    'estado', v_nueva_form.estado
  );
end;
$$;

create or replace function nucleo.agregar_campo(
  p_formulario_id uuid,
  p_codigo text,
  p_tipo public.tipo_campo,
  p_prompt text,
  p_orden integer,
  p_obligatorio boolean default true,
  p_cardinalidad public.cardinalidad_campo default 'uno',
  p_opciones jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form public.formularios;
  v_campo public.campos;
begin
  if not nucleo.es_coordinador() then
    raise exception 'no_es_coordinador' using errcode = 'P0001';
  end if;

  select * into v_form
  from public.formularios
  where id = p_formulario_id
  for update;

  if not found then
    raise exception 'formulario_no_existe' using errcode = 'P0001';
  end if;

  if v_form.estado <> 'borrador' then
    raise exception 'formulario_no_es_borrador' using errcode = 'P0001';
  end if;

  insert into public.campos (
    formulario_id, codigo, tipo, prompt, orden, obligatorio, cardinalidad, opciones
  ) values (
    p_formulario_id, p_codigo, p_tipo, p_prompt, p_orden, p_obligatorio, p_cardinalidad, p_opciones
  )
  returning * into v_campo;

  return jsonb_build_object(
    'ok', true,
    'campo_id', v_campo.id,
    'codigo', v_campo.codigo,
    'orden', v_campo.orden
  );
end;
$$;

create or replace function nucleo.registrar_coordinador(
  p_nombre text,
  p_cargo text default null
)
returns public.coordinadores
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_coord public.coordinadores;
begin
  if v_uid is null then
    raise exception 'no_autenticado' using errcode = 'P0001';
  end if;
  if coalesce(p_nombre, '') = '' then
    raise exception 'nombre_requerido' using errcode = 'P0001';
  end if;

  insert into public.coordinadores (auth_user_id, nombre, cargo)
  values (v_uid, p_nombre, p_cargo)
  on conflict (auth_user_id) do update
    set nombre = excluded.nombre, cargo = excluded.cargo
  returning * into v_coord;

  return v_coord;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Iniciar Formulario (Generalizado y Retrocompatible)
-- ---------------------------------------------------------------------------

create or replace function nucleo.iniciar_formulario(
  p_visita_realizada_id uuid default null,
  p_codigo text default null,
  p_solicitud_id uuid default null,
  p_version integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_eval uuid := nucleo.evaluador_id_actual();
  v_vr public.visitas_realizadas;
  v_fd public.formularios_diligenciados;
  v_form_id uuid;
  v_actual uuid;
  v_siguiente uuid;
  v_orden integer;
begin
  if v_uid is null then
    raise exception 'no_autenticado' using errcode = 'P0001';
  end if;

  -- Caso 1: Formulario ligado a visita realizada
  if p_visita_realizada_id is not null then
    if v_eval is null and not nucleo.es_coordinador() then
      raise exception 'no_es_evaluador' using errcode = 'P0001';
    end if;

    select * into v_vr
    from public.visitas_realizadas
    where id = p_visita_realizada_id
    for update;

    if not found then
      raise exception 'visita_ajena' using errcode = 'P0001';
    end if;
    if v_vr.evaluador_id is distinct from v_eval and not nucleo.es_coordinador() then
      raise exception 'visita_ajena' using errcode = 'P0001';
    end if;
    if v_vr.concluida_en is not null then
      raise exception 'transicion_ilegal' using errcode = 'P0001';
    end if;

    select * into v_fd
    from public.formularios_diligenciados
    where visita_realizada_id = p_visita_realizada_id;

    if found then
      return jsonb_build_object('ok', true) || nucleo.estado_formulario_json(v_fd.id);
    end if;
  end if;

  -- Resolver definición de formulario
  if p_codigo is not null then
    if p_version is not null then
      select id into v_form_id
      from public.formularios
      where codigo = p_codigo and version = p_version and estado = 'publicado';
    else
      select id into v_form_id
      from public.formularios
      where codigo = p_codigo and estado = 'publicado'
      order by version desc
      limit 1;
    end if;
  elsif p_visita_realizada_id is not null then
    -- Fallback estándar para evaluación post-sismo
    select id into v_form_id
    from public.formularios
    where codigo = 'd1171_evaluacion_rapida' and estado = 'publicado'
    order by version desc
    limit 1;

    if v_form_id is null then
      select id into v_form_id
      from public.formularios
      where codigo = 'ais_inspeccion_sismo' and estado = 'publicado'
      order by version desc
      limit 1;
    end if;
  end if;

  if v_form_id is null then
    -- Fallback final a cualquier formulario publicado
    select id into v_form_id
    from public.formularios
    where estado = 'publicado'
    order by version desc, created_at desc
    limit 1;
  end if;

  if v_form_id is null then
    raise exception 'formulario_no_existe' using errcode = 'P0001';
  end if;

  select c.id, c.orden into v_actual, v_orden
  from public.campos c
  where c.formulario_id = v_form_id
  order by c.orden
  limit 1;

  v_siguiente := nucleo.siguiente_campo(v_form_id, v_orden);

  insert into public.formularios_diligenciados (
    visita_realizada_id, formulario_id, autor_id, solicitud_id, campo_actual_id, campo_siguiente_id
  ) values (
    p_visita_realizada_id, v_form_id, v_uid, p_solicitud_id, v_actual, v_siguiente
  )
  returning * into v_fd;

  return jsonb_build_object('ok', true) || nucleo.estado_formulario_json(v_fd.id);
end;
$$;

-- Sobrecarga para mantener firma previa con 1 argumento en PL/pgSQL
create or replace function nucleo.iniciar_formulario(p_visita_realizada_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return nucleo.iniciar_formulario(p_visita_realizada_id, null, null, null);
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Commit Formulario (Genérico y Declarativo)
-- ---------------------------------------------------------------------------

create or replace function nucleo.commit_formulario(p_fd_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fd public.formularios_diligenciados;
  v_form public.formularios;
  v_clasificacion integer;
  v_codigo_campo text;
  v_resultado public.resultado_evaluacion;
  v_anotaciones text;
  v_vr public.visitas_realizadas;
begin
  v_fd := nucleo.exigir_autor_o_evaluador_del_fd(p_fd_id);

  if v_fd.congelado_en is not null then
    return jsonb_build_object('ok', false, 'error', 'formulario_congelado')
      || nucleo.estado_formulario_json(v_fd.id);
  end if;

  if not nucleo.completo_obligatorio(v_fd.id) then
    return jsonb_build_object('ok', false, 'error', 'campos_obligatorios_pendientes')
      || nucleo.estado_formulario_json(v_fd.id);
  end if;

  select * into v_form
  from public.formularios
  where id = v_fd.formulario_id;

  -- Si está ligado a una visita técnica con resultado estructural
  if v_fd.visita_realizada_id is not null then
    select (r.valor ->> 'valor')::integer, c.codigo
      into v_clasificacion, v_codigo_campo
    from public.respuestas r
    join public.campos c on c.id = r.campo_id
    where r.formulario_diligenciado_id = v_fd.id
      and c.codigo in ('cartel_clasificacion', 'clasificacion_dano')
    order by (case when c.codigo = 'cartel_clasificacion' then 0 else 1 end), r.created_at desc
    limit 1;

    if v_clasificacion is not null then
      if v_codigo_campo = 'cartel_clasificacion' then
        v_resultado := nucleo.mapear_cartel_d1171(v_clasificacion);
      else
        v_resultado := nucleo.mapear_clasificacion_ais(v_clasificacion);
      end if;

      select r.valor ->> 'texto'
        into v_anotaciones
      from public.respuestas r
      join public.campos c on c.id = r.campo_id
      where r.formulario_diligenciado_id = v_fd.id
        and c.codigo in ('observaciones_tecnicas', 'comentarios')
      order by (case when c.codigo = 'observaciones_tecnicas' then 0 else 1 end), r.created_at desc
      limit 1;

      update public.formularios_diligenciados
      set congelado_en = now()
      where id = v_fd.id;

      v_vr := nucleo.concluir_visita(
        v_fd.visita_realizada_id,
        v_resultado,
        coalesce(v_anotaciones, '')
      );

      return jsonb_build_object(
        'ok', true,
        'resultado', v_vr.resultado,
        'visita_realizada_id', v_vr.id
      ) || nucleo.estado_formulario_json(v_fd.id);
    end if;
  end if;

  -- Diligenciamiento genérico / autónomo
  update public.formularios_diligenciados
  set congelado_en = now()
  where id = v_fd.id;

  return jsonb_build_object('ok', true) || nucleo.estado_formulario_json(v_fd.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Wrappers public invoker
-- ---------------------------------------------------------------------------

create or replace function public.iniciar_formulario(
  visita_realizada_id uuid default null,
  codigo_formulario text default null,
  solicitud_id uuid default null,
  version integer default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.iniciar_formulario(
    visita_realizada_id, codigo_formulario, solicitud_id, version
  );
$$;

create or replace function public.crear_formulario(
  codigo text,
  nombre text,
  descripcion text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.crear_formulario(codigo, nombre, descripcion);
$$;

create or replace function public.publicar_formulario(formulario_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.publicar_formulario(formulario_id);
$$;

create or replace function public.archivar_formulario(formulario_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.archivar_formulario(formulario_id);
$$;

create or replace function public.crear_nueva_version_formulario(codigo text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.crear_nueva_version_formulario(codigo);
$$;

create or replace function public.agregar_campo(
  formulario_id uuid,
  codigo text,
  tipo public.tipo_campo,
  prompt text,
  orden integer,
  obligatorio boolean default true,
  cardinalidad public.cardinalidad_campo default 'uno',
  opciones jsonb default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.agregar_campo(
    formulario_id, codigo, tipo, prompt, orden, obligatorio, cardinalidad, opciones
  );
$$;

create or replace function public.registrar_coordinador(
  nombre text,
  cargo text default null
)
returns public.coordinadores
language sql
security invoker
set search_path = ''
as $$
  select nucleo.registrar_coordinador(nombre, cargo);
$$;
