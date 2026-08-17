-- Fix infinite recursion in RLS policies for solicitudes, visitas_potenciales and visitas_realizadas

-- 1. Helper SECURITY DEFINER para verificar si un evaluador tiene asignada una visita para una solicitud
create or replace function nucleo.evaluador_tiene_visita_en_solicitud(
  p_solicitud_id uuid,
  p_evaluador_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.visitas_potenciales vp
    where vp.solicitud_id = p_solicitud_id
      and vp.evaluador_id = p_evaluador_id
  );
$$;

-- 2. Helper SECURITY DEFINER para verificar si una persona es la solicitante del predio
create or replace function nucleo.persona_es_solicitante(
  p_solicitud_id uuid,
  p_persona_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.solicitudes s
    where s.id = p_solicitud_id
      and s.solicitante_id = p_persona_id
  );
$$;

grant execute on function nucleo.evaluador_tiene_visita_en_solicitud(uuid, uuid) to authenticated;
grant execute on function nucleo.persona_es_solicitante(uuid, uuid) to authenticated;

-- 3. Recrear política solicitudes_select
drop policy if exists solicitudes_select on public.solicitudes;
create policy solicitudes_select on public.solicitudes
  for select to authenticated
  using (
    solicitante_id = nucleo.persona_id_actual()
    or (select public.jwt_rol()) = 'coordinacion'
    or nucleo.evaluador_tiene_visita_en_solicitud(id, nucleo.evaluador_id_actual())
  );

-- 4. Recrear política visitas_potenciales_select
drop policy if exists visitas_potenciales_select on public.visitas_potenciales;
create policy visitas_potenciales_select on public.visitas_potenciales
  for select to authenticated
  using (
    evaluador_id = nucleo.evaluador_id_actual()
    or (select public.jwt_rol()) = 'coordinacion'
    or nucleo.persona_es_solicitante(solicitud_id, nucleo.persona_id_actual())
  );

-- 5. Recrear política visitas_realizadas_select
drop policy if exists visitas_realizadas_select on public.visitas_realizadas;
create policy visitas_realizadas_select on public.visitas_realizadas
  for select to authenticated
  using (
    evaluador_id = nucleo.evaluador_id_actual()
    or (select public.jwt_rol()) = 'coordinacion'
    or nucleo.persona_es_solicitante(solicitud_id, nucleo.persona_id_actual())
  );

-- 6. Recrear política calificaciones_select
drop policy if exists calificaciones_select on public.calificaciones;
create policy calificaciones_select on public.calificaciones
  for select to authenticated
  using (
    evaluador_id = nucleo.evaluador_id_actual()
    or (select public.jwt_rol()) = 'coordinacion'
    or nucleo.persona_es_solicitante(solicitud_id, nucleo.persona_id_actual())
  );
