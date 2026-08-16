# Plan de Pruebas de Aseguramiento de Calidad (QA) — API Foinikis

Este documento define el protocolo de pruebas de QA para la API de **Foinikis** (evaluación post-sismo). Cubre la verificación del flujo completo de inspección, la seguridad a nivel de filas (RLS), la máquina de estados de PostgreSQL y las funciones RPC expuestas a través de Supabase.

---

## 📋 Información del Proyecto

- **Nombre del Proyecto:** Foinikis — Régimen TypeScript + Postgres
- **Entorno de Pruebas:** Local (`http://127.0.0.1:54321`) / Supabase Cloud (`https://<PROJECT_REF>.supabase.co`)
- **Herramientas de QA:** Insomnia / Postman / `scripts/pruebas-api.sh` / cURL
- **Colección de Insomnia:** [`foinikis-insomnia-collection.json`](file:///Users/alejandromorales/ws/foinikis/foinikis-insomnia-collection.json)

---

## 🛠️ Requisitos Previos y Variables de Entorno

Antes de iniciar la ejecución de los casos de prueba en Insomnia, asegúrate de tener configurado el entorno con las siguientes variables:

| Variable | Descripción | Ejemplo / Formato |
| :--- | :--- | :--- |
| `base_url` | URL de la API de Supabase | `http://127.0.0.1:54321` o `https://<PROJECT_REF>.supabase.co` |
| `anon_key` | Clave pública anónima de API | `eyJhbGciOi...` |
| `service_role_key` | Clave con privilegios administrativos | `eyJhbGciOi...` |
| `sol_token` | Token JWT del usuario Solicitante | `Bearer eyJhbGciOi...` |
| `ea_token` | Token JWT del Evaluador A (Voluntario) | `Bearer eyJhbGciOi...` |
| `eb_token` | Token JWT del Evaluador B (Oficial) | `Bearer eyJhbGciOi...` |
| `solicitud_id` | UUID de la solicitud de evaluación creada | `UUID v4` |
| `visita_id` | UUID de la visita potencial asignada | `UUID v4` |
| `visita_realizada_id` | UUID de la visita presencial verificada | `UUID v4` |
| `formulario_diligenciado_id` | UUID del borrador de formulario activo | `UUID v4` |
| `pin` | Código de 4 dígitos generado al aceptar la visita | `String(4)` (ej. `"4829"`) |

---

## 🧪 Matriz de Casos de Prueba (Paso a Paso)

### Módulo 1: Autenticación y Registro de Usuarios (Auth)

#### `QA-AUTH-01`: Registro de Usuario Solicitante
- **Petición:** `POST /auth/v1/signup` (ó `POST /auth/v1/admin/users`)
- **Headers:** `apikey: {{ _.anon_key }}` / `Authorization: Bearer {{ _.service_role_key }}`
- **Body:**
  ```json
  {
    "email": "solicitante@example.com",
    "password": "Prueba1234",
    "email_confirm": true
  }
  ```
- **Resultado Esperado:** Código HTTP `200 OK`. Devuelve objeto de usuario con `id` y `access_token`.
- **Acción QA:** Copiar `access_token` en la variable `sol_token`.

#### `QA-AUTH-02`: Registro de Evaluadores (A y B)
- **Petición:** `POST /auth/v1/admin/users`
- **Body Evaluador A:** `{"email": "eval-a@example.com", "password": "Prueba1234", "email_confirm": true}`
- **Body Evaluador B:** `{"email": "eval-b@example.com", "password": "Prueba1234", "email_confirm": true}`
- **Resultado Esperado:** HTTP `200 OK` en ambas respuestas.
- **Acción QA:** Copiar tokens en `ea_token` y `eb_token` respectivamente.

---

### Módulo 2: Registro de Perfiles de Dominio

#### `QA-PER-01`: Registrar Persona (Solicitante)
- **Petición:** `POST /rest/v1/rpc/registrar_persona`
- **Headers:** `Authorization: Bearer {{ _.sol_token }}`
- **Body:**
  ```json
  {
    "nombre": "Ana Solicitante",
    "telefono": "+573001112233"
  }
  ```
- **Resultado Esperado:** HTTP `200 OK` (o `204 No Content`). Persona vinculada correctamente al UID autenticado.

#### `QA-PER-02`: Registrar Evaluador A (Voluntario)
- **Petición:** `POST /rest/v1/rpc/registrar_evaluador`
- **Headers:** `Authorization: Bearer {{ _.ea_token }}`
- **Body:**
  ```json
  {
    "tipo": "voluntario",
    "tarjeta_profesional_path": "placeholder/tarjeta.jpg",
    "transporte_propio": true,
    "lng": -74.0721,
    "lat": 4.7110,
    "radio_metros": 15000,
    "ventana": "[\"2026-08-14T08:00:00+00\",\"2026-08-14T20:00:00+00\")"
  }
  ```
- **Resultado Esperado:** HTTP `200 OK`. Evaluador registrado con ubicación geográfica y ventana horaria.

#### `QA-PER-03`: Registrar Evaluador B (Oficial)
- **Petición:** `POST /rest/v1/rpc/registrar_evaluador`
- **Headers:** `Authorization: Bearer {{ _.eb_token }}`
- **Body:**
  ```json
  {
    "tipo": "oficial",
    "tarjeta_profesional_path": "placeholder/tarjeta.jpg",
    "transporte_propio": false,
    "lng": -74.0721,
    "lat": 4.7110,
    "radio_metros": 20000,
    "ventana": "[\"2026-08-14T08:00:00+00\",\"2026-08-14T20:00:00+00\")"
  }
  ```
- **Resultado Esperado:** HTTP `200 OK`.

---

### Módulo 3: Gestión de Solicitudes Post-Sismo

#### `QA-SOL-01`: Crear Solicitud de Evaluación
- **Petición:** `POST /rest/v1/rpc/crear_solicitud`
- **Headers:** `Authorization: Bearer {{ _.sol_token }}`
- **Body:**
  ```json
  {
    "lng": -74.0721,
    "lat": 4.7110,
    "talla": "m",
    "ventana": "[\"2026-08-14T08:00:00+00\",\"2026-08-14T20:00:00+00\")"
  }
  ```
- **Resultado Esperado:** HTTP `200 OK`. Retorna JSON con `id` de la solicitud y estado inicial `"creada"`.
- **Acción QA:** Guardar el `id` en la variable `solicitud_id`.

#### `QA-SOL-02`: Filtrar Solicitudes por Estado
- **Petición:** `GET /rest/v1/solicitudes?estado=eq.visita_pendiente&select=id,estado,talla`
- **Headers:** `Authorization: Bearer {{ _.sol_token }}`
- **Resultado Esperado:** HTTP `200 OK`. Retorna arreglo JSON con la solicitud recién creada.

---

### Módulo 4: Algoritmo de Emparejamiento y Proceso de Sistema

#### `QA-SYS-01`: Ejecutar Generador de Visitas Potenciales
- **Petición:** `POST /rest/v1/rpc/generar_visitas_potenciales`
- **Headers:** `Authorization: Bearer {{ _.service_role_key }}` (Solo clave de servicio)
- **Body:** `{}`
- **Resultado Esperado:** HTTP `200 OK`. Cruza las solicitudes pendientes con los evaluadores disponibles dentro del radio de alcance y genera los registros en el buzón.

---

### Módulo 5: Buzón y Transición de Visitas

#### `QA-VIS-01`: Consultar Buzón del Evaluador A
- **Petición:** `GET /rest/v1/buzon_evaluador?select=*`
- **Headers:** `Authorization: Bearer {{ _.ea_token }}`
- **Resultado Esperado:** HTTP `200 OK`. Devuelve al menos un elemento en el buzón.
- **Acción QA:** Copiar el `id` de la visita recibida en la variable `visita_id`.

#### `QA-VIS-02`: Rechazar Visita (Evaluador B - Opcional)
- **Petición:** `POST /rest/v1/rpc/rechazar_visita`
- **Headers:** `Authorization: Bearer {{ _.eb_token }}`
- **Body:** `{"visita_id": "{{ _.visita_id }}"}`
- **Resultado Esperado:** HTTP `200 OK`. La visita cambia a estado `"rechazada"` para el Evaluador B.

#### `QA-VIS-03`: Aceptar Visita (Evaluador A - Generación de PIN)
- **Petición:** `POST /rest/v1/rpc/aceptar_visita`
- **Headers:** `Authorization: Bearer {{ _.ea_token }}`
- **Body:** `{"visita_id": "{{ _.visita_id }}"}`
- **Resultado Esperado:** HTTP `200 OK`. Retorna objeto conteniendo el código PIN de 4 cifras: `{"pin": "XXXX"}`.
- **Acción QA:** Copiar el PIN retornado en la variable `pin`.

#### `QA-VIS-04`: Probar Transición Ilegal (Re-aceptar Visita)
- **Petición:** `POST /rest/v1/rpc/aceptar_visita`
- **Headers:** `Authorization: Bearer {{ _.ea_token }}`
- **Body:** `{"visita_id": "{{ _.visita_id }}"}`
- **Resultado Esperado:** HTTP `400 Bad Request` / Error de Postgres por transición de estado inválida.

---

### Módulo 6: Seguridad Presencial y Validación de PIN

#### `QA-PIN-01`: Verificar PIN Incorrecto (Intento Fallido)
- **Petición:** `POST /rest/v1/rpc/verificar_pin`
- **Headers:** `Authorization: Bearer {{ _.sol_token }}`
- **Body:** `{"visita_id": "{{ _.visita_id }}", "pin": "0000"}`
- **Resultado Esperado:** HTTP `200 OK` con indicador de error de PIN / Alerta registrada. Incrementa contador de fallos.

#### `QA-PIN-02`: Regenerar PIN (En caso de pérdida o error)
- **Petición:** `POST /rest/v1/rpc/regenerar_pin`
- **Headers:** `Authorization: Bearer {{ _.ea_token }}`
- **Body:** `{"visita_id": "{{ _.visita_id }}"}`
- **Resultado Esperado:** HTTP `200 OK`. Devuelve un nuevo PIN de 4 cifras.
- **Acción QA:** Actualizar la variable `pin` con el nuevo valor.

#### `QA-PIN-03`: Verificar PIN Correcto
- **Petición:** `POST /rest/v1/rpc/verificar_pin`
- **Headers:** `Authorization: Bearer {{ _.sol_token }}`
- **Body:** `{"visita_id": "{{ _.visita_id }}", "pin": "{{ _.pin }}"}`
- **Resultado Esperado:** HTTP `200 OK`. La visita se marca como verificada y crea la `visita_realizada`.

---

### Módulo 7: Inspección y Diligenciamiento de Formulario

#### `QA-FRM-01`: Obtener Visitas Realizadas
- **Petición:** `GET /rest/v1/visitas_realizadas?select=id,solicitud_id,evaluador_id,concluida_en`
- **Headers:** `Authorization: Bearer {{ _.ea_token }}`
- **Resultado Esperado:** HTTP `200 OK`.
- **Acción QA:** Guardar el `id` en la variable `visita_realizada_id`.

#### `QA-FRM-02`: Iniciar Formulario (Prueba de Idempotencia)
- **Petición:** `POST /rest/v1/rpc/iniciar_formulario`
- **Headers:** `Authorization: Bearer {{ _.ea_token }}`
- **Body:** `{"visita_realizada_id": "{{ _.visita_realizada_id }}"}`
- **Resultado Esperado:** HTTP `200 OK`. Retorna `id` del borrador de formulario.
- **Acción QA:** Guardar el `id` en `formulario_diligenciado_id`.
- **Nota:** Ejecutar por segunda vez debe devolver exactamente el mismo borrador sin duplicarlo.

#### `QA-FRM-03`: Responder Campos del Formulario
- **Petición:** `POST /rest/v1/rpc/responder_campo`
- **Headers:** `Authorization: Bearer {{ _.ea_token }}`
- **Body (Ejemplo Campo Texto):**
  ```json
  {
    "formulario_diligenciado_id": "{{ _.formulario_diligenciado_id }}",
    "campo_id": "<UUID_CAMPO>",
    "valor": { "texto": "Fisuras diagonales en muros de mampostería" }
  }
  ```
- **Resultado Esperado:** HTTP `200 OK` con `{"ok": true}`.

#### `QA-FRM-04`: Intentar Commit de Formulario Incompleto
- **Petición:** `POST /rest/v1/rpc/commit_formulario`
- **Headers:** `Authorization: Bearer {{ _.ea_token }}`
- **Body:** `{"formulario_diligenciado_id": "{{ _.formulario_diligenciado_id }}"}`
- **Resultado Esperado:** Retorna error indicando `campos_obligatorios_pendientes` si falta responder algún campo marcado como obligatorio.

#### `QA-FRM-05`: Finalizar y Confirmar Formulario (Commit Exitoso)
- **Petición:** `POST /rest/v1/rpc/commit_formulario` (Una vez respondidos los obligatorios)
- **Headers:** `Authorization: Bearer {{ _.ea_token }}`
- **Body:** `{"formulario_diligenciado_id": "{{ _.formulario_diligenciado_id }}"}`
- **Resultado Esperado:** HTTP `200 OK` con `{"ok": true}`. La solicitud pasa a estado `evaluada` o `evaluacion_parcial`.

---

### Módulo 8: Calificación y Manejo de Excepciones

#### `QA-CAL-01`: Calificar Evaluador
- **Petición:** `POST /rest/v1/rpc/calificar_evaluador`
- **Headers:** `Authorization: Bearer {{ _.sol_token }}`
- **Body:**
  ```json
  {
    "solicitud_id": "{{ _.solicitud_id }}",
    "evaluador_id": "<UUID_EVALUADOR>",
    "estrellas": 5
  }
  ```
- **Resultado Esperado:** HTTP `200 OK`. Actualiza el `score_confianza` del evaluador.

#### `QA-EXC-01`: Marcar Predio No Encontrado
- **Petición:** `POST /rest/v1/rpc/marcar_no_encontrada`
- **Headers:** `Authorization: Bearer {{ _.ea_token }}`
- **Body:** `{"visita_realizada_id": "{{ _.visita_realizada_id }}"}`
- **Resultado Esperado:** HTTP `200 OK`. Cancela la visita en curso y re-programa la solicitud si aplica.

---

## 🔒 Matriz de Seguridad y Políticas RLS

| ID Prueba | Descripción de Seguridad | Acción Realizada | Resultado Esperado |
| :--- | :--- | :--- | :--- |
| **RLS-01** | Privacidad de buzones entre evaluadores | Evaluador B intenta leer `buzon_evaluador` del Evaluador A. | Retorna solo los registros propios o arreglo vacío. |
| **RLS-02** | Modificación no autorizada de solicitudes | Evaluador A intenta crear una solicitud a nombre de Solicitante. | Error RLS / `403 Forbidden` / Violación de política Postgres. |
| **RLS-03** | Inviolabilidad de PINs | Consultar tabla `nucleo.visita_pines` por PostgREST / REST. | Acceso denegado (Tabla no expuesta en esquema `public`). |

---

## ✅ Criterios de Aceptación (Checklist de QA)

- [ ] Todos los endpoints Auth retornan tokens JWT válidos.
- [ ] No es posible escribir directamente en `solicitudes` o `visitas` mediante `INSERT`/`UPDATE` directo (debe ser a través de RPCs).
- [ ] La aceptación de una visita entrega el PIN de 4 dígitos **únicamente una vez**.
- [ ] La verificación de 2 PINs fallidos invalida la visita y genera una alerta de sistema.
- [ ] `iniciar_formulario` funciona de manera strictly idempotente.
- [ ] `commit_formulario` bloquea el cierre si faltan campos obligatorios o el croquis.
- [ ] Los tests automatizados (`npm test`) y la verificación de tipos (`npm run typecheck`) pasan con **0 errores**.
