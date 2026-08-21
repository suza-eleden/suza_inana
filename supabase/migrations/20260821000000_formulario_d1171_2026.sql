-- Migración: Actualización del formulario de evaluación rápida post-sismo a la norma Decreto 1171 de 2026 / Circular Conjunta 73 de 2026 (SNGRD - UNGRD / IDIGER)
-- Fecha: 2026-08-21

-- 1. Ampliar tabla de evaluadores con atributos de registro RUPE
alter table public.evaluadores
  add column if not exists identificador_rupe text,
  add column if not exists perfil_rupe text default 'P1',
  add column if not exists matricula_profesional text,
  add column if not exists entidad_organizacion text;

-- 2. Función para mapear el cartel oficial D1171 a resultado_evaluacion
create or replace function nucleo.mapear_cartel_d1171(p_valor integer)
returns public.resultado_evaluacion
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_valor = 1 then
    return 'habitable'::public.resultado_evaluacion; -- Verde (Inspeccionada)
  elsif p_valor = 2 then
    return 'restringido'::public.resultado_evaluacion; -- Amarillo (Uso Restringido)
  elsif p_valor = 3 then
    return 'insegura'::public.resultado_evaluacion; -- Rojo (Inseguro / Peligro de Colapso)
  end if;
  raise exception 'cartel_d1171_invalido' using errcode = 'P0001';
end;
$$;

grant execute on function nucleo.mapear_cartel_d1171(integer) to authenticated;

-- 3. Actualizar iniciar_formulario para dar prioridad al formulario oficial D1171
create or replace function nucleo.iniciar_formulario(p_visita_realizada_id uuid)
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

  -- Priorizar formulario D1171; fallback al más reciente
  select id into v_form_id
  from public.formularios
  where codigo = 'd1171_evaluacion_rapida'
  order by version desc
  limit 1;

  if v_form_id is null then
    select id into v_form_id
    from public.formularios
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
    visita_realizada_id, formulario_id, campo_actual_id, campo_siguiente_id
  ) values (
    p_visita_realizada_id, v_form_id, v_actual, v_siguiente
  )
  returning * into v_fd;

  return jsonb_build_object('ok', true) || nucleo.estado_formulario_json(v_fd.id);
end;
$$;

-- 4. Actualizar commit_formulario para soportar cartel D1171 y clasificacion previa AIS
create or replace function nucleo.commit_formulario(p_fd_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fd public.formularios_diligenciados;
  v_clasificacion integer;
  v_codigo_campo text;
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

  -- Buscar clasificación en cartel D1171 o clasificacion AIS tradicional
  select (r.valor ->> 'valor')::integer, c.codigo
    into v_clasificacion, v_codigo_campo
  from public.respuestas r
  join public.campos c on c.id = r.campo_id
  where r.formulario_diligenciado_id = v_fd.id
    and c.codigo in ('cartel_clasificacion', 'clasificacion_dano')
  order by (case when c.codigo = 'cartel_clasificacion' then 0 else 1 end), r.created_at desc
  limit 1;

  if v_clasificacion is null then
    return jsonb_build_object('ok', false, 'error', 'clasificacion_faltante')
      || nucleo.estado_formulario_json(v_fd.id);
  end if;

  if v_codigo_campo = 'cartel_clasificacion' then
    v_resultado := nucleo.mapear_cartel_d1171(v_clasificacion);
  else
    v_resultado := nucleo.mapear_clasificacion_ais(v_clasificacion);
  end if;

  -- Obtener comentarios u observaciones
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
end;
$$;

-- 5. Sembrar formulario oficial Decreto 1171 de 2026
do $$
declare
  v_form uuid;
  v_n integer := 0;
  v_severidad_d1171 jsonb := '[
    {"valor":1,"etiqueta":"N (Ninguno/Leve)"},
    {"valor":2,"etiqueta":"M (Moderado)"},
    {"valor":3,"etiqueta":"S (Severo)"},
    {"valor":4,"etiqueta":"NA (No Aplica)"}
  ]'::jsonb;
begin
  -- Si ya existe por re-ejecución, reutilizar o recrear campos
  select id into v_form
  from public.formularios
  where codigo = 'd1171_evaluacion_rapida';

  if v_form is not null then
    delete from public.campos where formulario_id = v_form;
  else
    insert into public.formularios (codigo, nombre, version)
    values (
      'd1171_evaluacion_rapida',
      'Formulario Oficial D1171/2026 Evaluación Rápida Post-Sismo (Fase 1)',
      2
    )
    returning id into v_form;
  end if;

  -- -------------------------------------------------------------------------
  -- METADATOS Y CONTROL DE REGISTRO
  -- -------------------------------------------------------------------------
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'codigo_snigrd', 'texto',
    'Código Único de la Edificación (SNIGRD): [DANE (5)]-[DIVIPOLA (1)]-[RUPE (3)][Consecutivo (4)]',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'identificador_predial_chip', 'texto',
    'Identificador Predial / Chip / Cédula Catastral',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'fecha_evaluacion', 'texto',
    'Fecha de Evaluación (DD/MM/AAAA)',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'hora_inicio', 'texto',
    'Hora de Inicio (HH:MM)',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'hora_fin', 'texto',
    'Hora de Finalización (HH:MM)',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'tipo_inspeccion', 'opcion',
    'Tipo de Inspección Realizada',
    v_n, true, 'uno',
    '[
      {"valor":1,"etiqueta":"Inspección solo del exterior"},
      {"valor":2,"etiqueta":"Inspección exterior y del interior"}
    ]'::jsonb);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'evaluador_nombre', 'texto',
    'Nombre del Evaluador Responsable',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'evaluador_cedula', 'texto',
    'Cédula de Ciudadanía del Evaluador',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'evaluador_rupe', 'texto',
    'Identificador Único RUPE',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'evaluador_matricula', 'texto',
    'Matrícula / Tarjeta Profesional (COPNIA / CPNAA)',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'evaluador_perfil_rupe', 'opcion',
    'Perfil Habilitado RUPE',
    v_n, true, 'uno',
    '[
      {"valor":1,"etiqueta":"P1 (Evaluador Rápido)"},
      {"valor":2,"etiqueta":"P2 (Evaluador Verificador)"},
      {"valor":3,"etiqueta":"P3"},
      {"valor":4,"etiqueta":"Otro"}
    ]'::jsonb);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'evaluador_entidad', 'texto',
    'Entidad / Organización / Universidad',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'evaluador_telefono', 'texto',
    'Teléfono de Contacto del Evaluador',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'evaluador_email', 'texto',
    'Correo Electrónico del Evaluador',
    v_n, false, 'uno', null);

  -- -------------------------------------------------------------------------
  -- BLOQUE 1: LOCALIZACIÓN Y EVALUACIÓN GENERAL
  -- -------------------------------------------------------------------------
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'ubicacion_departamento', 'texto',
    'Departamento',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'ubicacion_municipio', 'texto',
    'Municipio / Distrito',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'ubicacion_localidad', 'texto',
    'Localidad / Comuna',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'ubicacion_barrio', 'texto',
    'Barrio / Vereda',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'direccion_oficial', 'texto',
    'Dirección Oficial',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'direccion_referencia', 'texto',
    'Dirección Anterior / Referencia de Llegada',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'coordenadas_gps', 'geolocalizacion',
    'Coordenadas GPS (WGS84)',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'gps_precision_m', 'texto',
    'Precisión GPS (metros)',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'contacto_sitio_nombre', 'texto',
    'Contacto en Sitio: Nombre de la Persona Atendida',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'contacto_sitio_calidad', 'opcion',
    'Contacto en Sitio: Calidad de la Persona Atendida',
    v_n, false, 'uno',
    '[
      {"valor":1,"etiqueta":"Propietario"},
      {"valor":2,"etiqueta":"Arrendatario"},
      {"valor":3,"etiqueta":"Administrador"},
      {"valor":4,"etiqueta":"Vecino / Testigo"},
      {"valor":5,"etiqueta":"No hubo contacto"}
    ]'::jsonb);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'contacto_sitio_telefono', 'texto',
    'Contacto en Sitio: Teléfono',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'contacto_sitio_documento', 'texto',
    'Contacto en Sitio: Documento de Identidad',
    v_n, false, 'uno', null);

  -- -------------------------------------------------------------------------
  -- BLOQUE 2: DESCRIPCIÓN DE LA EDIFICACIÓN
  -- -------------------------------------------------------------------------
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'uso_principal', 'opcion',
    'Uso Principal del Inmueble',
    v_n, true, 'uno',
    '[
      {"valor":1,"etiqueta":"Residencial Unifamiliar"},
      {"valor":2,"etiqueta":"Residencial Multifamiliar"},
      {"valor":3,"etiqueta":"Comercial / Servicios"},
      {"valor":4,"etiqueta":"Uso Mixto (Residencial + Comercial)"},
      {"valor":5,"etiqueta":"Infraestructura Vital: Salud (Hospital / IPS)"},
      {"valor":6,"etiqueta":"Infraestructura Vital: Educación (Colegio / Jardín)"},
      {"valor":7,"etiqueta":"Infraestructura Vital: Seguridad / Emergencias (Bomberos / Policía)"},
      {"valor":8,"etiqueta":"Infraestructura Vital: Sede Administrativa Pública"},
      {"valor":9,"etiqueta":"Asamblea / Concentración de Público"},
      {"valor":10,"etiqueta":"Industrial / Almacenamiento"},
      {"valor":11,"etiqueta":"Otro"}
    ]'::jsonb);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'unidades_multifamiliar', 'texto',
    'No. de Unidades / Aptos (si aplica)',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'codigo_reps_salud', 'texto',
    'Código REPS (si es Salud)',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'codigo_due_educacion', 'texto',
    'Código DUE (si es Educación)',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'pisos_sobre_terreno', 'texto',
    'Número de Pisos Sobre Terreno',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'pisos_sotanos', 'texto',
    'Número de Sótanos / Semisótanos',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'anio_construccion_estimado', 'texto',
    'Año Estimado de Construcción',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'cumplimiento_normativo', 'opcion',
    'Cumplimiento Normativo Estimado',
    v_n, true, 'uno',
    '[
      {"valor":1,"etiqueta":"Pre-NSR98"},
      {"valor":2,"etiqueta":"NSR-98"},
      {"valor":3,"etiqueta":"NSR-10"},
      {"valor":4,"etiqueta":"Desconocido"}
    ]'::jsonb);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'sistema_estructural', 'opcion',
    'Sistema Estructural Dominante',
    v_n, true, 'uno',
    '[
      {"valor":1,"etiqueta":"Pórticos de Concreto Reforzado (Vigas y Columnas)"},
      {"valor":2,"etiqueta":"Muros de Carga de Concreto Reforzado"},
      {"valor":3,"etiqueta":"Mampostería Estructural (Confinada / Reforzada)"},
      {"valor":4,"etiqueta":"Mampostería No Reforzada (sin vigas/columnas de amarre)"},
      {"valor":5,"etiqueta":"Estructura Metálica / Acero Estructural"},
      {"valor":6,"etiqueta":"Madera / Guadua / Materiales Vegetales"},
      {"valor":7,"etiqueta":"Tapia Pisada / Adobe / Bahareque"},
      {"valor":8,"etiqueta":"Sistema Mixto / Combinación de Sistemas"}
    ]'::jsonb);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'sistema_estructural_mixto_detalle', 'texto',
    'Sistema Mixto: Detalle de Combinación',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'tipo_entrepiso', 'opcion',
    'Tipo de Entrepiso',
    v_n, true, 'uno',
    '[
      {"valor":1,"etiqueta":"Placa Concreto"},
      {"valor":2,"etiqueta":"Vigueta y Bovedilla"},
      {"valor":3,"etiqueta":"Madera / Metal"},
      {"valor":4,"etiqueta":"Otro"}
    ]'::jsonb);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'tipo_cubierta', 'opcion',
    'Tipo de Cubierta',
    v_n, true, 'uno',
    '[
      {"valor":1,"etiqueta":"Placa Concreto"},
      {"valor":2,"etiqueta":"Teja Termoacústica / Zinc"},
      {"valor":3,"etiqueta":"Teja de Barro / Asbesto-Cemento"},
      {"valor":4,"etiqueta":"Madera"}
    ]'::jsonb);

  -- -------------------------------------------------------------------------
  -- BLOQUE 3: CONDICIONES OBSERVADAS (EVALUACIÓN DE DAÑOS)
  -- -------------------------------------------------------------------------
  -- 3.1 Geotécnicas
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_geo_desplazamiento_suelo', 'likert',
    '3.1.1 Desplazamiento del terreno / Agrietamiento del suelo',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_geo_desplazamiento_suelo_desc', 'texto',
    '3.1.1 Desplazamiento de suelo: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_geo_remocion_masa', 'likert',
    '3.1.2 Evidencia de Fenómenos de Remoción en Masa / Deslizamiento',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_geo_remocion_masa_desc', 'texto',
    '3.1.2 Remoción en masa: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_geo_licuacion_asentamiento', 'likert',
    '3.1.3 Evidencia de Licuación de Suelos / Asentamiento Diferencial',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_geo_licuacion_asentamiento_desc', 'texto',
    '3.1.3 Licuación / asentamiento: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_geo_muros_taludes_vecinos', 'likert',
    '3.1.4 Falla o inestabilidad en muros de contención / taludes vecinos',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_geo_muros_taludes_vecinos_desc', 'texto',
    '3.1.4 Muros / taludes vecinos: Descripción específica',
    v_n, false, 'uno', null);

  -- 3.2 Globales y Estructurales
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_colapso', 'likert',
    '3.2.1 Colapso Total o Parcial de la Estructura',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_colapso_desc', 'texto',
    '3.2.1 Colapso: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_inclinacion_piso_blando', 'likert',
    '3.2.2 Inclinación Apreciable o Desplome / Piso Blando',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_inclinacion_piso_blando_desc', 'texto',
    '3.2.2 Inclinación / piso blando: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_cimentacion', 'likert',
    '3.2.3 Desplazamiento / Pérdida de Apoyo de la Cimentación',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_cimentacion_desc', 'texto',
    '3.2.3 Cimentación: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_columnas', 'likert',
    '3.2.4 Daño en Columnas (Grietas en X, pandeo de barras, aplastamiento)',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_columnas_desc', 'texto',
    '3.2.4 Columnas: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_muros_estructurales', 'likert',
    '3.2.5 Daño en Muros Estructurales / Confinados (Grietas diagonales severas)',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_muros_estructurales_desc', 'texto',
    '3.2.5 Muros estructurales: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_vigas_conexiones', 'likert',
    '3.2.6 Daño en Vigas / Conexiones Viga-Columna',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_vigas_conexiones_desc', 'texto',
    '3.2.6 Vigas y conexiones: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_entrepisos_placas', 'likert',
    '3.2.7 Daño en Sistemas de Entrepiso / Placas de Concreto',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_est_entrepisos_placas_desc', 'texto',
    '3.2.7 Entrepisos: Descripción específica',
    v_n, false, 'uno', null);

  -- 3.3 No Estructurales y Amenazas Externas
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_no_est_fachadas_parapetos', 'likert',
    '3.3.1 Muros de Fachada / Antepechos / Parapetos Inestables',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_no_est_fachadas_parapetos_desc', 'texto',
    '3.3.1 Fachadas y antepechos: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_no_est_particiones', 'likert',
    '3.3.2 Muros Divisorios / Tabiques Interiores Agrietados o Desplomados',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_no_est_particiones_desc', 'texto',
    '3.3.2 Muros divisorios: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_no_est_cubiertas_cielorrasos', 'likert',
    '3.3.3 Cubiertas, Cielorrasos, Plafones o Aleros en Peligro de Caída',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_no_est_cubiertas_cielorrasos_desc', 'texto',
    '3.3.3 Cubiertas y cielorrasos: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_no_est_vidrios_ventaneria', 'likert',
    '3.3.4 Vidrios / Ventanerías Rotos con Riesgo de Desprendimiento',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_no_est_vidrios_ventaneria_desc', 'texto',
    '3.3.4 Vidrios y ventanería: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_no_est_escaleras', 'likert',
    '3.3.5 Escaleras / Vías de Evacuación Obstruidas o Inestables',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_no_est_escaleras_desc', 'texto',
    '3.3.5 Escaleras: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_amenaza_externa_vecinos', 'likert',
    '3.3.6 Amenaza Externa por Colapso de Edificación Vecina / Líneas Eléctricas',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_amenaza_externa_vecinos_desc', 'texto',
    '3.3.6 Amenaza externa: Descripción específica',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_servicios_fugas_gas', 'likert',
    '3.3.7 Fugas de Gas / Daño en Acometidas de Servicios Públicos',
    v_n, true, 'uno', v_severidad_d1171);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'dano_servicios_fugas_gas_desc', 'texto',
    '3.3.7 Fugas / acometidas: Descripción específica',
    v_n, false, 'uno', null);

  -- -------------------------------------------------------------------------
  -- BLOQUE 4: CLASIFICACIÓN DE LA EDIFICACIÓN (ASIGNACIÓN DE CARTEL)
  -- -------------------------------------------------------------------------
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'cartel_clasificacion', 'opcion',
    'Clasificación de la Edificación (Asignación de Cartel)',
    v_n, true, 'uno',
    '[
      {"valor":1,"etiqueta":"1. INSPECCIONADA: INGRESO Y USOS PERMITIDOS (CARTEL VERDE)"},
      {"valor":2,"etiqueta":"2. USO RESTRINGIDO: ENTRADA, OCUPACIÓN Y USO RESTRINGIDOS (CARTEL AMARILLO)"},
      {"valor":3,"etiqueta":"3. INSEGURO: PELIGRO DE COLAPSO - NO ENTRAR NI OCUPAR (CARTEL ROJO)"}
    ]'::jsonb);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'cartel_sectores_restringidos', 'texto',
    'Sectores Restringidos Específicos (requerido si Cartel Amarillo)',
    v_n, false, 'uno', null);

  -- -------------------------------------------------------------------------
  -- BLOQUE 5: ACCIONES POSTERIORES Y MEDIDAS RECOMENDADAS
  -- -------------------------------------------------------------------------
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'medidas_inmediatas', 'opcion',
    '5.1 Medidas Inmediatas en Terreno',
    v_n, false, 'muchos',
    '[
      {"valor":1,"etiqueta":"Instalación de Cartel Oficial en acceso principal visible al público"},
      {"valor":2,"etiqueta":"Instalación requerida de cinta de acordonamiento perimetral / aislamiento"},
      {"valor":3,"etiqueta":"Evacuación preventiva inmediata recomendada"},
      {"valor":4,"etiqueta":"Apuntalamiento preventivo de emergencia"},
      {"valor":5,"etiqueta":"Notificación inmediata de riesgo inminente al CMGRD / Bomberos / Policía"}
    ]'::jsonb);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'cartel_ubicacion_exacta', 'texto',
    'Ubicación exacta del cartel instalado',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'evacuacion_personas_estimadas', 'texto',
    'No. estimado de personas para evacuación preventiva',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'apuntalamiento_sitios', 'texto',
    'Lugares específicos para apuntalamiento preventivo',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'remisiones_institucionales', 'opcion',
    '5.2 Remisiones Institucionales',
    v_n, false, 'muchos',
    '[
      {"valor":1,"etiqueta":"Remisión Obligatoria a FASE 2: Prioridad Alta (Cartel Rojo / Amarillo)"},
      {"valor":2,"etiqueta":"Remisión Obligatoria a FASE 2: Prioridad Geotécnica (Perfil P4 requerido)"},
      {"valor":3,"etiqueta":"Remisión Obligatoria a FASE 2: Prioridad Infraestructura Vital"},
      {"valor":4,"etiqueta":"Remisión al Componente Social (RUD / EDAN - Atención a Damnificados)"},
      {"valor":5,"etiqueta":"Remisión a Empresas Prestadoras de Servicios Públicos (Gas / Energía / Acueducto)"}
    ]'::jsonb);

  -- -------------------------------------------------------------------------
  -- BLOQUE 6: COMENTARIOS, REGISTRO FOTOGRÁFICO Y FIRMAS
  -- -------------------------------------------------------------------------
  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'foto_1_fachada', 'imagen',
    'Foto 1 (Obligatoria): Fachada completa con nomenclatura / entorno',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'foto_2_cartel', 'imagen',
    'Foto 2 (Obligatoria): Cartel oficial instalado en el acceso principal',
    v_n, true, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'foto_3_dano_critico', 'imagen',
    'Foto 3 (Detalle): Daño estructural o no estructural más crítico',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'foto_4_contexto_geotecnico', 'imagen',
    'Foto 4 (Contexto): Condición geotécnica / amenaza circundante',
    v_n, false, 'uno', null);

  v_n := v_n + 1;
  perform nucleo.sembrar_campo(v_form, 'observaciones_tecnicas', 'texto',
    'Observaciones y Comentarios Técnicos del Evaluador',
    v_n, false, 'uno', null);

end;
$$;
