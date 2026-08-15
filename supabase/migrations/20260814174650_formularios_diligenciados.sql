-- Formularios diligenciados: el backend posee el cursor.
-- evidencias deja de ser tabla de escritura y pasa a vista sobre respuestas imagen.

create type public.tipo_campo as enum (
  'texto',
  'likert',
  'opcion',
  'imagen',
  'geolocalizacion'
);

create type public.cardinalidad_campo as enum ('uno', 'muchos');

-- ---------------------------------------------------------------------------
-- Quitar el canal paralelo de evidencias
-- ---------------------------------------------------------------------------

drop policy if exists evidencias_select on public.evidencias;
drop function if exists public.agregar_evidencia(uuid, text, text, text);
drop function if exists nucleo.agregar_evidencia(uuid, text, text, text);
drop table if exists public.evidencias;

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------

create table public.formularios (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  version integer not null default 1,
  created_at timestamptz not null default now()
);

create table public.campos (
  id uuid primary key default gen_random_uuid(),
  formulario_id uuid not null references public.formularios (id) on delete restrict,
  codigo text not null,
  tipo public.tipo_campo not null,
  prompt text not null,
  orden integer not null,
  obligatorio boolean not null default true,
  cardinalidad public.cardinalidad_campo not null default 'uno',
  opciones jsonb,
  created_at timestamptz not null default now(),
  constraint campos_codigo_unico unique (formulario_id, codigo),
  constraint campos_orden_unico unique (formulario_id, orden),
  constraint campos_opciones_coherentes check (
    (
      tipo in ('likert', 'opcion')
      and jsonb_typeof(opciones) = 'array'
      and jsonb_array_length(opciones) > 0
    )
    or (tipo in ('texto', 'imagen', 'geolocalizacion') and opciones is null)
  )
);

create table public.formularios_diligenciados (
  id uuid primary key default gen_random_uuid(),
  visita_realizada_id uuid not null unique
    references public.visitas_realizadas (id) on delete restrict,
  formulario_id uuid not null references public.formularios (id) on delete restrict,
  campo_actual_id uuid references public.campos (id) on delete restrict,
  campo_siguiente_id uuid references public.campos (id) on delete restrict,
  congelado_en timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.respuestas (
  id uuid primary key default gen_random_uuid(),
  formulario_diligenciado_id uuid not null
    references public.formularios_diligenciados (id) on delete cascade,
  campo_id uuid not null references public.campos (id) on delete restrict,
  valor jsonb not null,
  created_at timestamptz not null default now()
);

create index campos_formulario_id_idx on public.campos (formulario_id, orden);
create index formularios_diligenciados_formulario_id_idx
  on public.formularios_diligenciados (formulario_id);
create index respuestas_fd_campo_idx
  on public.respuestas (formulario_diligenciado_id, campo_id);

create trigger formularios_diligenciados_touch
  before update on public.formularios_diligenciados
  for each row execute function nucleo.touch_updated_at();

create view public.evidencias
with (security_invoker = true) as
select
  r.id,
  fd.visita_realizada_id,
  c.codigo as campo_formulario,
  r.valor ->> 'storage_path' as storage_path,
  r.created_at as captured_at
from public.respuestas r
join public.campos c on c.id = r.campo_id
join public.formularios_diligenciados fd on fd.id = r.formulario_diligenciado_id
where c.tipo = 'imagen';

-- ---------------------------------------------------------------------------
-- Helpers de estado
-- ---------------------------------------------------------------------------

create function nucleo.campo_publico(p_campo public.campos)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select case
    when p_campo.id is null then null
    else jsonb_build_object(
      'id', p_campo.id,
      'codigo', p_campo.codigo,
      'tipo', p_campo.tipo,
      'prompt', p_campo.prompt,
      'orden', p_campo.orden,
      'obligatorio', p_campo.obligatorio,
      'cardinalidad', p_campo.cardinalidad,
      'opciones', p_campo.opciones
    )
  end;
$$;

create function nucleo.campos_diligenciados(p_fd_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (
      select jsonb_agg(q.campo_id order by q.campo_id)
      from (
        select distinct r.campo_id
        from public.respuestas r
        where r.formulario_diligenciado_id = p_fd_id
      ) q
    ),
    '[]'::jsonb
  );
$$;

create function nucleo.completo_obligatorio(p_fd_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select not exists (
    select 1
    from public.formularios_diligenciados fd
    join public.campos c on c.formulario_id = fd.formulario_id
    where fd.id = p_fd_id
      and c.obligatorio
      and not exists (
        select 1
        from public.respuestas r
        where r.formulario_diligenciado_id = fd.id
          and r.campo_id = c.id
      )
  );
$$;

create function nucleo.estado_formulario_json(p_fd_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_fd public.formularios_diligenciados;
  v_actual public.campos;
  v_siguiente public.campos;
begin
  select * into v_fd
  from public.formularios_diligenciados
  where id = p_fd_id;

  if not found then
    raise exception 'formulario_no_existe' using errcode = 'P0001';
  end if;

  if v_fd.campo_actual_id is not null then
    select * into v_actual from public.campos where id = v_fd.campo_actual_id;
  end if;
  if v_fd.campo_siguiente_id is not null then
    select * into v_siguiente from public.campos where id = v_fd.campo_siguiente_id;
  end if;

  return jsonb_build_object(
    'id', v_fd.id,
    'visita_realizada_id', v_fd.visita_realizada_id,
    'formulario_id', v_fd.formulario_id,
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

create function nucleo.siguiente_campo(p_formulario_id uuid, p_orden integer)
returns uuid
language sql
stable
set search_path = ''
as $$
  select c.id
  from public.campos c
  where c.formulario_id = p_formulario_id
    and c.orden > p_orden
  order by c.orden
  limit 1;
$$;

create function nucleo.exigir_evaluador_del_fd(p_fd_id uuid)
returns public.formularios_diligenciados
language plpgsql
set search_path = ''
as $$
declare
  v_eval uuid := nucleo.evaluador_id_actual();
  v_fd public.formularios_diligenciados;
  v_vr public.visitas_realizadas;
begin
  if v_eval is null then
    raise exception 'no_es_evaluador' using errcode = 'P0001';
  end if;
  select * into v_fd
  from public.formularios_diligenciados
  where id = p_fd_id
  for update;
  if not found then
    raise exception 'formulario_no_existe' using errcode = 'P0001';
  end if;
  select * into v_vr
  from public.visitas_realizadas
  where id = v_fd.visita_realizada_id;
  if v_vr.evaluador_id is distinct from v_eval then
    raise exception 'visita_ajena' using errcode = 'P0001';
  end if;
  return v_fd;
end;
$$;

create function nucleo.validar_valor_campo(
  p_campo public.campos,
  p_valor jsonb
)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_num numeric;
  v_path text;
begin
  if p_valor is null or jsonb_typeof(p_valor) <> 'object' then
    return 'valor_invalido';
  end if;

  case p_campo.tipo
    when 'texto' then
      if coalesce(p_valor ->> 'texto', '') = '' then
        return 'valor_invalido';
      end if;
    when 'likert', 'opcion' then
      if jsonb_typeof(p_valor -> 'valor') <> 'number' then
        return 'valor_invalido';
      end if;
      v_num := (p_valor ->> 'valor')::numeric;
      if not exists (
        select 1
        from jsonb_array_elements(p_campo.opciones) o
        where (o ->> 'valor')::numeric = v_num
      ) then
        return 'opcion_desconocida';
      end if;
    when 'imagen' then
      v_path := p_valor ->> 'storage_path';
      if v_path is null or v_path = '' then
        return 'valor_invalido';
      end if;
    when 'geolocalizacion' then
      if jsonb_typeof(p_valor -> 'lat') <> 'number'
         or jsonb_typeof(p_valor -> 'lng') <> 'number' then
        return 'valor_invalido';
      end if;
      if (p_valor ->> 'lat')::numeric < -90
         or (p_valor ->> 'lat')::numeric > 90
         or (p_valor ->> 'lng')::numeric < -180
         or (p_valor ->> 'lng')::numeric > 180 then
        return 'valor_invalido';
      end if;
  end case;
  return null;
end;
$$;

create function nucleo.mapear_clasificacion_ais(p_valor integer)
returns public.resultado_evaluacion
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_valor in (1, 2) then
    return 'habitable'::public.resultado_evaluacion;
  end if;
  if p_valor = 3 then
    return 'restringido'::public.resultado_evaluacion;
  end if;
  if p_valor in (4, 5) then
    return 'insegura'::public.resultado_evaluacion;
  end if;
  raise exception 'clasificacion_ais_invalida' using errcode = 'P0001';
end;
$$;

-- ---------------------------------------------------------------------------
-- RPCs nucleo
-- ---------------------------------------------------------------------------

create function nucleo.iniciar_formulario(p_visita_realizada_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eval uuid := nucleo.evaluador_id_actual();
  v_vr public.visitas_realizadas;
  v_fd public.formularios_diligenciados;
  v_form_id uuid;
  v_actual uuid;
  v_siguiente uuid;
  v_orden integer;
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

  select * into v_fd
  from public.formularios_diligenciados
  where visita_realizada_id = p_visita_realizada_id;

  if found then
    return jsonb_build_object('ok', true) || nucleo.estado_formulario_json(v_fd.id);
  end if;

  select id into v_form_id
  from public.formularios
  where codigo = 'ais_inspeccion_sismo'
  order by version desc
  limit 1;

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
    visita_realizada_id, formulario_id, campo_actual_id, campo_siguiente_id
  ) values (
    p_visita_realizada_id, v_form_id, v_actual, v_siguiente
  )
  returning * into v_fd;

  return jsonb_build_object('ok', true) || nucleo.estado_formulario_json(v_fd.id);
end;
$$;

create function nucleo.estado_formulario(p_fd_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fd public.formularios_diligenciados;
begin
  v_fd := nucleo.exigir_evaluador_del_fd(p_fd_id);
  return jsonb_build_object('ok', true) || nucleo.estado_formulario_json(v_fd.id);
end;
$$;

create function nucleo.responder_campo(
  p_fd_id uuid,
  p_campo_id uuid,
  p_valor jsonb,
  p_respuesta_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fd public.formularios_diligenciados;
  v_campo public.campos;
  v_error text;
  v_orden integer;
begin
  v_fd := nucleo.exigir_evaluador_del_fd(p_fd_id);

  if v_fd.congelado_en is not null then
    return jsonb_build_object('ok', false, 'error', 'formulario_congelado')
      || nucleo.estado_formulario_json(v_fd.id);
  end if;

  select * into v_campo
  from public.campos
  where id = p_campo_id
    and formulario_id = v_fd.formulario_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'campo_ajeno')
      || nucleo.estado_formulario_json(v_fd.id);
  end if;

  v_error := nucleo.validar_valor_campo(v_campo, p_valor);
  if v_error is not null then
    return jsonb_build_object('ok', false, 'error', v_error)
      || nucleo.estado_formulario_json(v_fd.id);
  end if;

  if v_campo.cardinalidad = 'uno' then
    delete from public.respuestas
    where formulario_diligenciado_id = v_fd.id
      and campo_id = v_campo.id;
    insert into public.respuestas (formulario_diligenciado_id, campo_id, valor)
    values (v_fd.id, v_campo.id, p_valor);
  elsif p_respuesta_id is not null then
    update public.respuestas
    set valor = p_valor
    where id = p_respuesta_id
      and formulario_diligenciado_id = v_fd.id
      and campo_id = v_campo.id;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'respuesta_ajena')
        || nucleo.estado_formulario_json(v_fd.id);
    end if;
  else
    insert into public.respuestas (formulario_diligenciado_id, campo_id, valor)
    values (v_fd.id, v_campo.id, p_valor);
  end if;

  if p_campo_id = v_fd.campo_actual_id and v_fd.campo_siguiente_id is not null then
    select c.orden into v_orden
    from public.campos c
    where c.id = v_fd.campo_siguiente_id;
    update public.formularios_diligenciados
    set campo_actual_id = v_fd.campo_siguiente_id,
        campo_siguiente_id = nucleo.siguiente_campo(v_fd.formulario_id, v_orden)
    where id = v_fd.id;
  end if;

  return jsonb_build_object('ok', true) || nucleo.estado_formulario_json(v_fd.id);
end;
$$;

create function nucleo.respuestas_formulario(p_fd_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fd public.formularios_diligenciados;
begin
  v_fd := nucleo.exigir_evaluador_del_fd(p_fd_id);
  return jsonb_build_object(
    'ok', true,
    'formulario_diligenciado_id', v_fd.id,
    'congelado', v_fd.congelado_en is not null,
    'respuestas', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'campo_id', r.campo_id,
            'codigo', c.codigo,
            'tipo', c.tipo,
            'valor', r.valor,
            'created_at', r.created_at
          )
          order by c.orden, r.created_at
        )
        from public.respuestas r
        join public.campos c on c.id = r.campo_id
        where r.formulario_diligenciado_id = v_fd.id
      ),
      '[]'::jsonb
    )
  );
end;
$$;

create function nucleo.commit_formulario(p_fd_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fd public.formularios_diligenciados;
  v_clasificacion integer;
  v_resultado public.resultado_evaluacion;
  v_anotaciones text;
  v_vr public.visitas_realizadas;
begin
  v_fd := nucleo.exigir_evaluador_del_fd(p_fd_id);

  if v_fd.congelado_en is not null then
    return jsonb_build_object('ok', false, 'error', 'formulario_congelado')
      || nucleo.estado_formulario_json(v_fd.id);
  end if;

  if not nucleo.completo_obligatorio(v_fd.id) then
    return jsonb_build_object('ok', false, 'error', 'campos_obligatorios_pendientes')
      || nucleo.estado_formulario_json(v_fd.id);
  end if;

  select (r.valor ->> 'valor')::integer
    into v_clasificacion
  from public.respuestas r
  join public.campos c on c.id = r.campo_id
  where r.formulario_diligenciado_id = v_fd.id
    and c.codigo = 'clasificacion_dano'
  order by r.created_at desc
  limit 1;

  if v_clasificacion is null then
    return jsonb_build_object('ok', false, 'error', 'clasificacion_faltante')
      || nucleo.estado_formulario_json(v_fd.id);
  end if;

  v_resultado := nucleo.mapear_clasificacion_ais(v_clasificacion);

  select r.valor ->> 'texto'
    into v_anotaciones
  from public.respuestas r
  join public.campos c on c.id = r.campo_id
  where r.formulario_diligenciado_id = v_fd.id
    and c.codigo = 'comentarios'
  order by r.created_at desc
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
end;
$$;

-- ---------------------------------------------------------------------------
-- Wrappers public
-- ---------------------------------------------------------------------------

create function public.iniciar_formulario(visita_realizada_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.iniciar_formulario(visita_realizada_id);
$$;

create function public.estado_formulario(formulario_diligenciado_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.estado_formulario(formulario_diligenciado_id);
$$;

create function public.responder_campo(
  formulario_diligenciado_id uuid,
  campo_id uuid,
  valor jsonb,
  respuesta_id uuid default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.responder_campo(
    formulario_diligenciado_id, campo_id, valor, respuesta_id
  );
$$;

create function public.respuestas_formulario(formulario_diligenciado_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.respuestas_formulario(formulario_diligenciado_id);
$$;

create function public.commit_formulario(formulario_diligenciado_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select nucleo.commit_formulario(formulario_diligenciado_id);
$$;

-- ---------------------------------------------------------------------------
-- Seed AIS
-- ---------------------------------------------------------------------------

create function nucleo.sembrar_campo(
  p_formulario_id uuid,
  p_codigo text,
  p_tipo public.tipo_campo,
  p_prompt text,
  p_orden integer,
  p_obligatorio boolean,
  p_cardinalidad public.cardinalidad_campo,
  p_opciones jsonb
)
returns void
language sql
set search_path = ''
as $$
  insert into public.campos (
    formulario_id, codigo, tipo, prompt, orden, obligatorio, cardinalidad, opciones
  ) values (
    p_formulario_id, p_codigo, p_tipo, p_prompt, p_orden,
    p_obligatorio, p_cardinalidad, p_opciones
  );
$$;

do $$
declare
  v_form uuid;
  v_dano jsonb := '[
    {"valor":1,"etiqueta":"Ninguno"},
    {"valor":2,"etiqueta":"Leve"},
    {"valor":3,"etiqueta":"Moderado"},
    {"valor":4,"etiqueta":"Fuerte"},
    {"valor":5,"etiqueta":"Severo"}
  ]'::jsonb;
  v_si_no_nd jsonb := '[
    {"valor":1,"etiqueta":"Sí"},
    {"valor":2,"etiqueta":"No"},
    {"valor":3,"etiqueta":"No se pudo determinar"}
  ]'::jsonb;
  v_uso jsonb := '[
    {"valor":1,"etiqueta":"Residencial"},
    {"valor":2,"etiqueta":"Comercial"},
    {"valor":3,"etiqueta":"Educacional"},
    {"valor":4,"etiqueta":"Salud"},
    {"valor":5,"etiqueta":"Hotelero"},
    {"valor":6,"etiqueta":"Oficinas"},
    {"valor":7,"etiqueta":"Industrial"},
    {"valor":8,"etiqueta":"Institucional"},
    {"valor":9,"etiqueta":"Bodegas"},
    {"valor":10,"etiqueta":"Estacionamientos"},
    {"valor":11,"etiqueta":"Otros"}
  ]'::jsonb;
  v_n integer := 0;
begin
  insert into public.formularios (codigo, nombre, version)
  values (
    'ais_inspeccion_sismo',
    'Formulario único AIS inspección post-sismo',
    1
  )
  returning id into v_form;

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'localidad', 'texto',
    'Localidad', v_n, true, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'barrio', 'texto',
    'Nombre del barrio', v_n, true, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'catastro_barrio', 'texto',
    'Identificación catastral — Barrio', v_n, false, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'catastro_manzana', 'texto',
    'Identificación catastral — Manzana', v_n, false, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'catastro_predio', 'texto',
    'Identificación catastral — Predio', v_n, false, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'inspeccion_acceso', 'opcion',
    'Inspección de la edificación', v_n, true, 'uno',
    '[{"valor":1,"etiqueta":"Exterior e interior"},{"valor":2,"etiqueta":"No se pudo entrar"}]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'direccion', 'texto',
    'Dirección', v_n, true, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'nombre_edificacion', 'texto',
    'Nombre de la edificación', v_n, false, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'uso_edificacion', 'opcion',
    'Uso predominante de la edificación', v_n, true, 'uno', v_uso);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'uso_planta_baja', 'opcion',
    'Uso predominante de la planta baja', v_n, false, 'uno', v_uso);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'pisos_sobre_terreno', 'texto',
    'Número de pisos — niveles sobre el terreno', v_n, true, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'sotanos', 'texto',
    'Número de sótanos', v_n, false, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'frente_m', 'texto',
    'Dimensiones aproximadas — Frente (m)', v_n, false, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'fondo_m', 'texto',
    'Dimensiones aproximadas — Fondo (m)', v_n, false, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'ubicacion_inspector', 'geolocalizacion',
    'Geolocalización del inspector en sitio', v_n, false, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'sistema_estructural', 'opcion',
    'Sistema estructural', v_n, true, 'uno',
    '[
      {"valor":11,"etiqueta":"Pórtico de concreto"},
      {"valor":12,"etiqueta":"Muros estructurales"},
      {"valor":13,"etiqueta":"Sistemas duales"},
      {"valor":14,"etiqueta":"Prefabricados"},
      {"valor":21,"etiqueta":"Mampostería confinada"},
      {"valor":22,"etiqueta":"Mampostería reforzada"},
      {"valor":23,"etiqueta":"Mampostería no reforzada"},
      {"valor":31,"etiqueta":"Pórticos arriostrados"},
      {"valor":32,"etiqueta":"Pórticos no arriostrados"},
      {"valor":41,"etiqueta":"Pórticos y paneles en madera"},
      {"valor":42,"etiqueta":"Pórticos en madera y paneles en otros materiales"},
      {"valor":50,"etiqueta":"Mixta"},
      {"valor":51,"etiqueta":"Muros en bahareque"},
      {"valor":52,"etiqueta":"Muros en tapia"},
      {"valor":60,"etiqueta":"Otros"}
    ]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'tipo_entrepiso', 'opcion',
    'Tipo de entrepiso', v_n, true, 'uno',
    '[
      {"valor":11,"etiqueta":"Placa maciza"},
      {"valor":12,"etiqueta":"Placa aligerada"},
      {"valor":13,"etiqueta":"Reticular celulado"},
      {"valor":21,"etiqueta":"Lámina colaborante"},
      {"valor":22,"etiqueta":"Vigas de acero"},
      {"valor":23,"etiqueta":"Cerchas"},
      {"valor":31,"etiqueta":"Vigas de madera"},
      {"valor":32,"etiqueta":"Mixta"},
      {"valor":40,"etiqueta":"Otros"}
    ]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'anio_construccion', 'opcion',
    'Año de construcción', v_n, true, 'uno',
    '[
      {"valor":1,"etiqueta":"Antes de 1930"},
      {"valor":2,"etiqueta":"1930 a 1984"},
      {"valor":3,"etiqueta":"1985 a 1997"},
      {"valor":4,"etiqueta":"A partir de 1998"}
    ]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_1_colapso', 'opcion',
    '1. ¿Existe colapso?', v_n, true, 'uno',
    '[{"valor":1,"etiqueta":"No"},{"valor":2,"etiqueta":"Parcial"},{"valor":3,"etiqueta":"Total"}]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_2_inclinacion', 'opcion',
    '2. Desviación o inclinación de la edificación o de algún entrepiso',
    v_n, true, 'uno', v_si_no_nd);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_3_cimentacion', 'opcion',
    '3. Falla o asentamiento de la cimentación', v_n, true, 'uno', v_si_no_nd);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_4_fachadas', 'likert',
    '4. Muros de fachadas o antepechos', v_n, true, 'uno', v_dano);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_5_particiones', 'likert',
    '5. Muros divisorios o particiones', v_n, true, 'uno', v_dano);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_6_cielo_rasos', 'likert',
    '6. Cielo rasos y luminarias', v_n, true, 'uno', v_dano);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_7_cubierta', 'likert',
    '7. Cubierta', v_n, true, 'uno', v_dano);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_8_escaleras', 'likert',
    '8. Escaleras', v_n, true, 'uno', v_dano);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_9_instalaciones_grado', 'likert',
    '9. Instalaciones — grado de daño', v_n, true, 'uno', v_dano);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_9_instalaciones_servicios', 'opcion',
    '9. Instalaciones afectadas', v_n, false, 'muchos',
    '[
      {"valor":1,"etiqueta":"Acueducto"},
      {"valor":2,"etiqueta":"Alcantarillado"},
      {"valor":3,"etiqueta":"Energía"},
      {"valor":4,"etiqueta":"Gas"}
    ]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_10_tanques', 'likert',
    '10. Tanques elevados', v_n, true, 'uno', v_dano);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_11_talud', 'opcion',
    '11. Falla en talud o movimientos en masa', v_n, true, 'uno',
    '[{"valor":1,"etiqueta":"No"},{"valor":2,"etiqueta":"Puntual"},{"valor":3,"etiqueta":"General"}]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_12_asentamiento', 'opcion',
    '12. Asentamiento, subsidencia o licuación', v_n, true, 'uno',
    '[{"valor":1,"etiqueta":"No"},{"valor":2,"etiqueta":"Puntual"},{"valor":3,"etiqueta":"General"}]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'piso_mayor_dano', 'texto',
    'Nivel de entrepiso con el mayor daño', v_n, true, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_13_columnas', 'likert',
    '13. Columnas o muros portantes', v_n, true, 'uno', v_dano);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_14_vigas', 'likert',
    '14. Vigas', v_n, true, 'uno', v_dano);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_15_nudos', 'likert',
    '15. Nudos o puntos de conexión', v_n, true, 'uno', v_dano);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'item_16_entrepisos', 'likert',
    '16. Entrepisos', v_n, true, 'uno', v_dano);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'porcentaje_dano_global', 'opcion',
    'Porcentaje de daños global de la edificación', v_n, true, 'uno',
    '[
      {"valor":0,"etiqueta":"0% Ninguno"},
      {"valor":1,"etiqueta":"0-10% Leve"},
      {"valor":2,"etiqueta":"10-30% Moderado"},
      {"valor":3,"etiqueta":"30-60% Fuerte"},
      {"valor":4,"etiqueta":"60-100% Severo"},
      {"valor":5,"etiqueta":"100% Colapso total"}
    ]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'clasificacion_dano', 'likert',
    'Indique la clasificación del daño según la presente evaluación',
    v_n, true, 'uno',
    '[
      {"valor":1,"etiqueta":"Ninguno — Habitable (verde)"},
      {"valor":2,"etiqueta":"Leve — Habitable (verde)"},
      {"valor":3,"etiqueta":"Moderado — Uso restringido (amarillo)"},
      {"valor":4,"etiqueta":"Fuerte — No habitable (naranja)"},
      {"valor":5,"etiqueta":"Severo — Peligro de colapso (rojo)"}
    ]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'clasificacion_previa', 'opcion',
    '¿Existe una clasificación previa?', v_n, true, 'uno',
    '[{"valor":1,"etiqueta":"Sí"},{"valor":2,"etiqueta":"No"}]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'clasificacion_previa_cual', 'texto',
    '¿Cuál fue la clasificación previa?', v_n, false, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'visita_especializada', 'opcion',
    'Se necesita visita especializada por aspectos', v_n, false, 'muchos',
    '[
      {"valor":1,"etiqueta":"Estructurales"},
      {"valor":2,"etiqueta":"Geotécnicos"},
      {"valor":3,"etiqueta":"Servicios públicos"}
    ]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'intervencion', 'opcion',
    'Se recomienda intervención de', v_n, false, 'muchos',
    '[
      {"valor":1,"etiqueta":"Planeación — Control físico"},
      {"valor":2,"etiqueta":"Policía — Ejército"},
      {"valor":3,"etiqueta":"Tránsito"},
      {"valor":4,"etiqueta":"Bomberos / entidades de rescate"}
    ]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'medidas_seguridad', 'opcion',
    'Medidas de seguridad', v_n, false, 'muchos',
    '[
      {"valor":1,"etiqueta":"Restringir paso de peatones"},
      {"valor":2,"etiqueta":"Restringir tráfico vehicular"},
      {"valor":3,"etiqueta":"Apuntalar"},
      {"valor":4,"etiqueta":"Demoler elementos en peligro de caer"},
      {"valor":5,"etiqueta":"Evacuar parcialmente la edificación"},
      {"valor":6,"etiqueta":"Evacuar totalmente la edificación"},
      {"valor":7,"etiqueta":"Evacuar edificaciones vecinas"},
      {"valor":8,"etiqueta":"Manejo de sustancias peligrosas"}
    ]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'desconectar_servicios', 'opcion',
    'Desconectar servicios', v_n, false, 'muchos',
    '[
      {"valor":1,"etiqueta":"Energía"},
      {"valor":2,"etiqueta":"Gas"},
      {"valor":3,"etiqueta":"Agua"}
    ]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'lugares_medidas', 'texto',
    'Especifique lugares de la edificación que requieran las medidas de seguridad',
    v_n, false, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'esquema', 'imagen',
    'Esquema / croquis de la edificación', v_n, false, 'muchos', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'calidad_construccion', 'opcion',
    'Calidad de la construcción', v_n, false, 'uno',
    '[{"valor":1,"etiqueta":"Buena"},{"valor":2,"etiqueta":"Regular"},{"valor":3,"etiqueta":"Mala"}]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'posicion_manzana', 'opcion',
    'Posición de la edificación en la manzana', v_n, false, 'uno',
    '[
      {"valor":1,"etiqueta":"Esquina"},
      {"valor":2,"etiqueta":"Intermedia"},
      {"valor":3,"etiqueta":"Libre por un costado"},
      {"valor":4,"etiqueta":"Libre por dos costados"}
    ]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'hubo_muertos_heridos', 'opcion',
    'Hubo muertos o heridos', v_n, true, 'uno',
    '[{"valor":1,"etiqueta":"No"},{"valor":2,"etiqueta":"Sí"},{"valor":3,"etiqueta":"No se sabe"}]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'numero_fallecidos', 'texto',
    'Número de personas fallecidas', v_n, false, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'numero_heridos', 'texto',
    'Número de heridos', v_n, false, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'edificacion_habitada', 'opcion',
    'En el momento de esta evaluación la edificación está habitada',
    v_n, true, 'uno',
    '[{"valor":1,"etiqueta":"Sí"},{"valor":2,"etiqueta":"No"}]'::jsonb);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'contacto_nombre', 'texto',
    'Persona para contacto — nombres y apellidos', v_n, true, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'contacto_telefono', 'texto',
    'Persona para contacto — teléfono', v_n, true, 'uno', null);
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'comentarios', 'texto',
    'Comentarios: ampliar la evaluación e indicar los daños más importantes',
    v_n, false, 'uno', null);
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.formularios enable row level security;
alter table public.campos enable row level security;
alter table public.formularios_diligenciados enable row level security;
alter table public.respuestas enable row level security;

create policy formularios_select on public.formularios
  for select to authenticated
  using (true);

create policy campos_select on public.campos
  for select to authenticated
  using (true);

create policy formularios_diligenciados_select on public.formularios_diligenciados
  for select to authenticated
  using (
    exists (
      select 1
      from public.visitas_realizadas vr
      where vr.id = formularios_diligenciados.visita_realizada_id
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

create policy respuestas_select on public.respuestas
  for select to authenticated
  using (
    exists (
      select 1
      from public.formularios_diligenciados fd
      join public.visitas_realizadas vr on vr.id = fd.visita_realizada_id
      where fd.id = respuestas.formulario_diligenciado_id
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

grant select on public.formularios to authenticated;
grant select on public.campos to authenticated;
grant select on public.formularios_diligenciados to authenticated;
grant select on public.respuestas to authenticated;
grant select on public.evidencias to authenticated;

grant execute on function public.iniciar_formulario(uuid) to authenticated;
grant execute on function public.estado_formulario(uuid) to authenticated;
grant execute on function public.responder_campo(uuid, uuid, jsonb, uuid) to authenticated;
grant execute on function public.respuestas_formulario(uuid) to authenticated;
grant execute on function public.commit_formulario(uuid) to authenticated;

grant execute on function nucleo.iniciar_formulario(uuid) to authenticated;
grant execute on function nucleo.estado_formulario(uuid) to authenticated;
grant execute on function nucleo.responder_campo(uuid, uuid, jsonb, uuid) to authenticated;
grant execute on function nucleo.respuestas_formulario(uuid) to authenticated;
grant execute on function nucleo.commit_formulario(uuid) to authenticated;
grant execute on function nucleo.estado_formulario_json(uuid) to authenticated;
grant execute on function nucleo.campo_publico(public.campos) to authenticated;
grant execute on function nucleo.campos_diligenciados(uuid) to authenticated;
grant execute on function nucleo.completo_obligatorio(uuid) to authenticated;
grant execute on function nucleo.exigir_evaluador_del_fd(uuid) to authenticated;
grant execute on function nucleo.validar_valor_campo(public.campos, jsonb) to authenticated;
grant execute on function nucleo.mapear_clasificacion_ais(integer) to authenticated;
grant execute on function nucleo.siguiente_campo(uuid, integer) to authenticated;

-- El dictamen sale del commit del formulario, no de un resultado suelto.
revoke execute on function public.concluir_visita(
  uuid,
  public.resultado_evaluacion,
  text
) from authenticated, public;
