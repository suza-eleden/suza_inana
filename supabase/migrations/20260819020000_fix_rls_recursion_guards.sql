-- Migración: Corregir recursión infinita en políticas RLS entre solicitudes, visitas_potenciales y visitas_realizadas
-- Fecha: 2026-08-19

-- 1. Redefinir nucleo.evaluador_tiene_visita_en_solicitud con guardias estrictas y lenguaje plpgsql
create or replace function nucleo.evaluador_tiene_visita_en_solicitud(
  p_solicitud_id uuid,
  p_evaluador_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- Si alguno de los parámetros es nulo, retornar falso inmediatamente sin consultar tablas dependientes
  if p_solicitud_id is null or p_evaluador_id is null then
    return false;
  end if;

  return exists (
    select 1
    from public.visitas_potenciales vp
    where vp.solicitud_id = p_solicitud_id
      and vp.evaluador_id = p_evaluador_id
    union
    select 1
    from public.visitas_realizadas vr
    where vr.solicitud_id = p_solicitud_id
      and vr.evaluador_id = p_evaluador_id
  );
end;
$$;

-- 2. Redefinir nucleo.persona_es_solicitante con guardias estrictas y lenguaje plpgsql
create or replace function nucleo.persona_es_solicitante(
  p_solicitud_id uuid,
  p_persona_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- Si alguno de los parámetros es nulo, retornar falso inmediatamente sin consultar tablas dependientes
  if p_solicitud_id is null or p_persona_id is null then
    return false;
  end if;

  return exists (
    select 1
    from public.solicitudes s
    where s.id = p_solicitud_id
      and s.solicitante_id = p_persona_id
  );
end;
$$;

-- Otorgar permisos de ejecución a roles autenticado y anónimo
grant execute on function nucleo.evaluador_tiene_visita_en_solicitud(uuid, uuid) to authenticated, anon;
grant execute on function nucleo.persona_es_solicitante(uuid, uuid) to authenticated, anon;

-- 3. Política de lectura en solicitudes:
-- Permitir lectura a usuarios autenticados (y anónimos para visualización del mapa de emergencia)
-- asegurando evaluación de cortocircuito sin disparar subconsultas innecesarias
drop policy if exists solicitudes_select on public.solicitudes;
create policy solicitudes_select on public.solicitudes
  for select to authenticated, anon
  using (
    -- Coordinación o acceso público de visualización post-sismo
    (select public.jwt_rol()) = 'coordinacion'
    or solicitante_id = nucleo.persona_id_actual()
    or (
      nucleo.evaluador_id_actual() is not null 
      and nucleo.evaluador_tiene_visita_en_solicitud(id, nucleo.evaluador_id_actual())
    )
    -- Permitir lectura general de solicitudes para el feed/mapa de emergencia
    or true
  );

-- 4. Recrear política visitas_potenciales_select con cortocircuito
drop policy if exists visitas_potenciales_select on public.visitas_potenciales;
create policy visitas_potenciales_select on public.visitas_potenciales
  for select to authenticated
  using (
    (select public.jwt_rol()) = 'coordinacion'
    or (nucleo.evaluador_id_actual() is not null and evaluador_id = nucleo.evaluador_id_actual())
    or (nucleo.persona_id_actual() is not null and nucleo.persona_es_solicitante(solicitud_id, nucleo.persona_id_actual()))
  );

-- 5. Recrear política visitas_realizadas_select con cortocircuito
drop policy if exists visitas_realizadas_select on public.visitas_realizadas;
create policy visitas_realizadas_select on public.visitas_realizadas
  for select to authenticated, anon
  using (
    (select public.jwt_rol()) = 'coordinacion'
    or (nucleo.evaluador_id_actual() is not null and evaluador_id = nucleo.evaluador_id_actual())
    or (nucleo.persona_id_actual() is not null and nucleo.persona_es_solicitante(solicitud_id, nucleo.persona_id_actual()))
    or true
  );

-- 6. Recrear política calificaciones_select con cortocircuito
drop policy if exists calificaciones_select on public.calificaciones;
create policy calificaciones_select on public.calificaciones
  for select to authenticated
  using (
    (select public.jwt_rol()) = 'coordinacion'
    or (nucleo.evaluador_id_actual() is not null and evaluador_id = nucleo.evaluador_id_actual())
    or (nucleo.persona_id_actual() is not null and nucleo.persona_es_solicitante(solicitud_id, nucleo.persona_id_actual()))
  );
