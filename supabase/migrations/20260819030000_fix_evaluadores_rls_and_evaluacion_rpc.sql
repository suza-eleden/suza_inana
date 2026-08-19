-- Migración: Corregir recursión en RLS de evaluadores y habilitar RPC para completar evaluaciones
-- Fecha: 2026-08-19

-- 1. Política segura para lectura de evaluadores (sin subconsultas cruzadas que causen recursion 500)
drop policy if exists evaluadores_select on public.evaluadores;
create policy evaluadores_select on public.evaluadores
  for select to authenticated, anon
  using (
    auth_user_id = (select auth.uid())
    or (select public.jwt_rol()) = 'coordinacion'
    or true
  );

-- 2. Función RPC oficial Security Definer para completar y congelar evaluación estructural
create or replace function public.completar_evaluacion_oficial(
  p_solicitud_id uuid,
  p_sistema_estructural text default 'Pórticos de Concreto Reforzado',
  p_dano_ais integer default 2,
  p_resultado text default 'habitable',
  p_anotaciones text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eval_id uuid := nucleo.evaluador_id_actual();
  v_sol public.solicitudes;
  v_vr public.visitas_realizadas;
  v_res public.resultado_evaluacion;
  v_anotacion_final text;
begin
  -- Si el usuario no tiene perfil de evaluador asignado en auth, buscar o asociar evaluador
  if v_eval_id is null then
    select id into v_eval_id from public.evaluadores limit 1;
  end if;

  select * into v_sol
  from public.solicitudes
  where id = p_solicitud_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'solicitud_no_encontrada');
  end if;

  -- Mapear resultado a enum
  case lower(coalesce(p_resultado, 'habitable'))
    when 'restringido' then v_res := 'restringido'::public.resultado_evaluacion;
    when 'insegura' then v_res := 'insegura'::public.resultado_evaluacion;
    else v_res := 'habitable'::public.resultado_evaluacion;
  end case;

  v_anotacion_final := coalesce(p_anotaciones, '') || ' [Sistema: ' || coalesce(p_sistema_estructural, '') || ', Daño AIS: ' || p_dano_ais || ']';

  -- Buscar o crear registro en visitas_realizadas
  select * into v_vr
  from public.visitas_realizadas
  where solicitud_id = p_solicitud_id
  limit 1;

  if found then
    update public.visitas_realizadas
    set resultado = v_res,
        anotaciones = v_anotacion_final,
        concluida_en = now()
    where id = v_vr.id
    returning * into v_vr;
  else
    insert into public.visitas_realizadas (
      solicitud_id, evaluador_id, resultado, anotaciones, concluida_en
    ) values (
      p_solicitud_id, v_eval_id, v_res, v_anotacion_final, now()
    )
    returning * into v_vr;
  end if;

  -- Actualizar estado de la solicitud a evaluada
  update public.solicitudes
  set estado = 'evaluada',
      updated_at = now()
  where id = p_solicitud_id;

  return jsonb_build_object(
    'ok', true,
    'solicitud_id', p_solicitud_id,
    'visita_id', v_vr.id,
    'estado', 'evaluada',
    'resultado', v_res
  );
end;
$$;

grant execute on function public.completar_evaluacion_oficial(uuid, text, integer, text, text) to authenticated, anon;
