# Foinikis — documento de arquitectura

API REST de evaluación estructural post-sismo. El canal de presentación (app propia o WhatsApp) es un facade: los invariantes viven en Postgres.

---

## Motivacion

Tras un terremoto en Colombia hace falta decidir, en horas, si una casa o un edificio es habitable, de uso restringido o inseguro. Esa decisión no puede depender de un solo testimonio ni de un técnico no identificado: hay ingenieros voluntarios y oficiales, hay riesgo de fraude, y hay que cubrir más predios de los que un equipo institucional alcanza.

Foinikis existe para coordinar esa evaluación de campo:

- Quien habita o administra el predio **solicita** una visita (ubicación, disponibilidad, tamaño estimado).
- El sistema **propone visitas** a evaluadores cuya cobertura, agenda y perfil coinciden.
- El evaluador **acepta o rechaza**. Si acepta, un **PIN de 4 cifras** verifica que quien llega es quien el sistema despachó.
- La visita produce un **formulario diligenciado** (fotos como respuestas `imagen` y un dictamen derivado del cartel oficial según Decreto 1171 de 2026 / Circular Conjunta 73). Una solicitud exige **al menos dos evaluadores distintos**; si discrepan, una tercera visita desempata.
- La confianza del evaluador **sube o baja** según coincida con su par (y según la calificación del solicitante).

El nombre del problema de arranque es explícito: **score de evaluador en frío**. Un ingeniero nuevo no tiene historial; el sistema arranca en un prior (`0.50`) y solo mueve el score con evidencia de pares.

---

## Requisitos funcionales

### RF-1. Registro de evaluadores

- Ingeniero **voluntario** u **oficial** con registro RUPE (P1 a P4).
- Foto de la tarjeta profesional (Storage).
- Transporte propio, área de cobertura (punto + radio), horario disponible (`tstzrange`).
- Score de confianza: lo calcula el núcleo, no el cliente. Prior `0.50`; al cerrar una evaluación con par, \(+0.05\) si coinciden, \(-0.08\) si no (acotado a \([0.05, 0.95]\)).
- El solicitante califica al evaluador (1–5 estrellas) al final de la visita concluida.

### RF-2. Registro de solicitudes

- Persona natural autenticada.
- Ubicación exacta (GPS / mapa → coordenadas).
- Disponibilidad para recibir al evaluador.
- Tamaño estimado de la construcción en tallas de camiseta: `xs | s | m | l | xl`.
- Estados: `creada`, `visita_pendiente`, `en_evaluacion`, `evaluacion_fallida`, `evaluacion_parcial`, `evaluada`.

| Estado | Significado |
|---|---|
| `creada` | Ingresada, aún no publicada al matching |
| `visita_pendiente` | Disponible para asignar visitas potenciales |
| `en_evaluacion` | Un evaluador aceptó y está en camino o en sitio |
| `evaluacion_fallida` | No se encontró el predio, o PIN falló dos veces; el generador puede reagendar |
| `evaluacion_parcial` | Hay al menos una visita realizada; falta par o hay discrepancia |
| `evaluada` | Consenso (2 iguales) o mayoría (3er desempate) |

### RF-3. Generador de visitas potenciales

- Cruza cobertura geográfica (`ST_DWithin`), overlap de agendas, y exclusiones (ya visitó ese predio, ya hay una visita `aceptada`, máximo 3 visitas realizadas, tope de 5 `creada` en mailbox).
- Estados de la visita potencial: `creada`, `aceptada`, `rechazada`, `cancelada`.
- Entrega candidatos al **buzón** de cada evaluador (`buzon_evaluador`).
- El primero que acepta cancela las hermanas (`tomada_por_otro`).

### RF-4. Validación de identidad en sitio (PIN)

- Al aceptar, el sistema genera un PIN de 4 cifras, lo muestra **una vez** al evaluador y guarda solo el hash en `nucleo.visita_pines` (no expuesto por PostgREST).
- El solicitante pregunta el PIN y lo envía al API.
- Correcto → se crea `visita_realizada` (en curso).
- Incorrecto → `alerta` `pin_incorrecto`. El evaluador puede regenerar el PIN. Un segundo fallo cancela la visita (`pin_fallido`) y deja la solicitud en `evaluacion_fallida`.

### RF-5. Visitas realizadas y objetividad

- Un formulario diligenciado por `visita_realizada`. El cliente pregunta el campo actual y manda una respuesta; el cursor vive en Postgres.
- Fotos: respuesta `imagen` con URI del bucket `evidencias` (no base64). `evidencias` es una vista sobre esas respuestas.
- El dictamen `habitable | restringido | insegura` sale de la asignación del cartel oficial (Decreto 1171/2026: Verde 1 / Amarillo 2 / Rojo 3) en `commit_formulario`, no de un `resultado` suelto.
- Mínimo 2 visitas realizadas, **evaluadores distintos** (`UNIQUE (solicitud_id, evaluador_id)`).
- Máximo 3. Si las dos primeras discrepan, el generador puede despachar una tercera.


### RF-6. Consultas / exportación

- Listar evaluadores, visitas y solicitudes filtrando por estado (y tipo, talla, cursor).
- La API es agnóstica del canal: el mismo REST sirve a un front o a un bot de WhatsApp (facade posterior).

---

## Atributos de Calidad

| Atributo | Escenario | Respuesta del diseño |
|---|---|---|
| **Seguridad / anti-fraude** | Un impostor se presenta en la casa | PIN de un solo uso, 2 intentos, alerta, hash fuera de `public` |
| **Integridad de estado** | Un cliente (o un `as` en TS) fuerza `evaluada` | Escrituras solo por RPC; tabla de transiciones; `transicion_ilegal` |
| **Objetividad** | Un evaluador sesgado o inexperto | Doble visita + desempate; score por acuerdo de pares |
| **Flexibilidad de canal** | Aún no hay front; puede ser WhatsApp | REST + RPCs; facade conversacional después, sin cambiar el núcleo |
| **Auditabilidad** | Hay que reconstruir quién dijo qué | Evidencias, alertas, calificaciones, transiciones explícitas |
| **Disponibilidad de matching** | Pico de solicitudes post-sismo | Matching en SQL (PostGIS + rangos); mailbox por índice parcial |
| **Confidencialidad** | RLS | Cada rol ve lo suyo; coordinación / `service_role` ve el recorte operativo |
| **Correctitud en la frontera** | JSON y filas DB son `any` de facto | Zod en cada borde; IDs branded; `JSON.parse` solo en `src/frontier/json.ts` |
| **Evolución** | Si el sistema se institucionaliza | Postgres sigue siendo el verificador; OCaml queda como opción de núcleo a años |

Prioridad en emergencia: integridad de transiciones y anti-fraude > latencia de matching > lujo de DX.

---

## Decisiones de arquitectura

### ADR-1. TypeScript + Supabase ahora; OCaml como opción de núcleo a largo plazo

TypeScript replica el *estilo* de estados ilegales irrepresentables (uniones discriminadas, `assertNever`, `intentosPin: 0 | 1`), no las *garantías* de OCaml (solidez de Milner, sin erasure). El sistema de tipos de TS es unsound by design (Bierman, Abadi, Torgersen, ECOOP 2014).

La compensación explícita: **los invariantes duros viven en Postgres**. Un `as` deshonesto produce un request que el núcleo rechaza con `transicion_ilegal`, no un estado corrupto.

Por qué TS en esta emergencia: Edge Functions / `supabase gen types`, contratación, un solo lenguaje si el bot o el front también son TS. OCaml paga compuesto cuando el costo de mantenimiento a años domina.

### ADR-2. Postgres es el verificador de última instancia

- Schema privado `nucleo`: funciones `security definer`, tablas de verdad `transicion_solicitud` / `transicion_visita`.
- Wrappers `public.*` `security invoker` para PostgREST. `nucleo` no está en `api.schemas`.
- `GRANT SELECT` a `authenticated`; **cero INSERT/UPDATE/DELETE** de estado desde el cliente.
- PIN en `nucleo.visita_pines`, nunca columna de `public.visitas_potenciales`.

### ADR-3. Régimen TypeScript (no es opcional)

- `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`.
- ESLint: nada de `any`, nada de `as`, `JSON.parse` solo en la frontera.
- *Parse, don't validate* (King, 2019): Zod en HTTP y en filas DB.
- IDs branded: `SolicitudId` ≠ `EvaluadorId`.

### ADR-4. API de facade, no de UI

Los comandos son RPCs (`aceptar_visita`, `verificar_pin`, …). Un canal WhatsApp o una SPA llaman lo mismo. No se modela el diálogo en el dominio.

### ADR-5. Matching geográfico + agenda en SQL

Cobertura = `geography(Point)` + `radio_metros`. Ventana = `tstzrange`. El generador es una función, no un worker aparte en v1 (se puede colgar de cron / coordinación).

### ADR-6. Identidad en sitio con PIN, no con KYC pesado

Cuatro dígitos, bcrypt, dos intentos, alerta. Suficiente para el riesgo “se hace pasar por el ingeniero” sin onboarding biométrico en emergencia.

### ADR-7. Score en frío con prior, no con “cero visitas = cero confianza”

`0.50` de arranque. Sin eso, nadie nuevo entra al matching de calidad. El par es la señal; la estrella del solicitante es otra señal, no sustituye el acuerdo técnico.

### ADR-8. El backend posee el cursor del formulario

Clientes delgados (web o WhatsApp) no recorren un wizard propio: preguntan `estado_formulario` y mandan `responder_campo`. Un `formularios_diligenciados` por `visita_realizada`. Responder el campo actual avanza el cursor; responder otro campo solo sobreescribe (`uno`) o agrega (`muchos`). `commit_formulario` exige obligatorios, congela el FD y llama `nucleo.concluir_visita` con el mapeo AIS. `public.concluir_visita` deja de ser el write path del cliente.

---

## Entidades Principales

```mermaid
erDiagram
  personas ||--o{ solicitudes : pone
  evaluadores ||--o{ visitas_potenciales : recibe
  solicitudes ||--o{ visitas_potenciales : genera
  solicitudes ||--o{ visitas_realizadas : acumula
  evaluadores ||--o{ visitas_realizadas : dictamina
  visitas_potenciales ||--o| visitas_realizadas : origina
  visitas_realizadas ||--|| formularios_diligenciados : uno_a_uno
  formularios ||--o{ campos : contiene
  formularios ||--o{ formularios_diligenciados : instancia
  campos ||--o{ respuestas : recibe
  formularios_diligenciados ||--o{ respuestas : acumula
  respuestas ||--o| evidencias : si_imagen
  visitas_potenciales ||--o{ alertas : dispara
  solicitudes ||--o{ calificaciones : recibe
  evaluadores ||--o{ calificaciones : es_calificado

  personas {
    uuid id PK
    uuid auth_user_id
    text nombre
    text telefono
  }
  evaluadores {
    uuid id PK
    uuid auth_user_id
    tipo_evaluador tipo
    text tarjeta_profesional_path
    boolean transporte_propio
    geography ubicacion_base
    int radio_metros
    tstzrange ventana
    numeric score_confianza
  }
  solicitudes {
    uuid id PK
    uuid solicitante_id FK
    geography ubicacion
    talla_construccion talla
    tstzrange ventana
    solicitud_estado estado
  }
  visitas_potenciales {
    uuid id PK
    uuid solicitud_id FK
    uuid evaluador_id FK
    visita_potencial_estado estado
    causa_cancelacion causa_cancelacion
    smallint pin_intentos
    timestamptz pin_verificado_en
    tstzrange ventana_propuesta
  }
  visitas_realizadas {
    uuid id PK
    uuid solicitud_id FK
    uuid evaluador_id FK
    uuid visita_potencial_id FK
    resultado_evaluacion resultado
    text anotaciones
    timestamptz concluida_en
  }
  formularios {
    uuid id PK
    text codigo UK
    text nombre
    int version
  }
  campos {
    uuid id PK
    uuid formulario_id FK
    text codigo
    tipo_campo tipo
    cardinalidad_campo cardinalidad
    int orden
    boolean obligatorio
    jsonb opciones
  }
  formularios_diligenciados {
    uuid id PK
    uuid visita_realizada_id UK
    uuid formulario_id FK
    uuid campo_actual_id FK
    uuid campo_siguiente_id FK
    timestamptz congelado_en
  }
  respuestas {
    uuid id PK
    uuid formulario_diligenciado_id FK
    uuid campo_id FK
    jsonb valor
  }
  evidencias {
    uuid id PK
    uuid visita_realizada_id FK
    text campo_formulario
    text storage_path
  }
  alertas {
    uuid id PK
    uuid visita_potencial_id FK
    tipo_alerta tipo
  }
  calificaciones {
    uuid id PK
    uuid solicitud_id FK
    uuid evaluador_id FK
    smallint estrellas
  }
```

El hash del PIN **no** es atributo de `visitas_potenciales`: vive en `nucleo.visita_pines`.
`evidencias` es una **vista** sobre respuestas `imagen` (`storage_path` en el bucket, no base64).

### Máquinas de estado

```mermaid
stateDiagram-v2
  [*] --> creada
  creada --> visita_pendiente: publicar
  visita_pendiente --> en_evaluacion: aceptar
  en_evaluacion --> evaluacion_parcial: cerrar_primera / cerrar_discrepancia
  en_evaluacion --> evaluada: cerrar_consenso
  en_evaluacion --> evaluacion_fallida: pin_fallido / no_encontrada
  en_evaluacion --> visita_pendiente: visita_abortada
  evaluacion_parcial --> en_evaluacion: aceptar
  evaluacion_fallida --> visita_pendiente: reagendar
  evaluada --> [*]
```

```mermaid
stateDiagram-v2
  [*] --> creada
  creada --> aceptada: aceptar
  creada --> rechazada: rechazar
  creada --> cancelada: tomar_otro
  aceptada --> cancelada: pin_fallido / evaluador / solicitante
  rechazada --> [*]
  cancelada --> [*]
```

---

## Casos de Uso

Actores: **Solicitante**, **Evaluador**, **Coordinación** (o `service_role` en v1), **Sistema** (generador).

```mermaid
flowchart LR
  subgraph actores
    S[Solicitante]
    E[Evaluador]
    C[Coordinación]
  end
  S --> UC1[Poner solicitud]
  S --> UC5[Verificar PIN]
  S --> UC8[Calificar evaluador]
  E --> UC2[Registrarse]
  E --> UC4[Aceptar o rechazar visita]
  E --> UC6[Diligenciar formulario y commit]
  E --> UC7[Marcar predio no encontrado]
  C --> UC3[Generar visitas potenciales]
  C --> UC9[Exportar listas]
```

| ID | Actor | Caso | Resultado |
|---|---|---|---|
| UC-1 | Solicitante | Registrar persona y crear solicitud con GPS, talla y ventana | Solicitud en `visita_pendiente` |
| UC-2 | Evaluador | Subir tarjeta profesional, cobertura, agenda, tipo | Evaluador con score `0.50` |
| UC-3 | Coordinación | Correr el generador | Visitas `creada` en buzones que matchean |
| UC-4a | Evaluador | Aceptar visita del buzón | PIN de 4 cifras; solicitud `en_evaluacion`; hermanas `cancelada` |
| UC-4b | Evaluador | Rechazar visita | Visita `rechazada`; la solicitud sigue asignable |
| UC-5a | Solicitante | Enviar PIN correcto | `visita_realizada` en curso |
| UC-5b | Solicitante | PIN incorrecto | Alerta; 2º fallo → visita `cancelada`, solicitud `evaluacion_fallida` |
| UC-6 | Evaluador | `iniciar_formulario` → `responder_campo` → `commit_formulario` | `evaluacion_parcial` (1ª) o `evaluada` (consenso / 3ª) |
| UC-7 | Evaluador | `marcar_no_encontrada` | Solicitud `evaluacion_fallida` |
| UC-8 | Solicitante | 1–5 estrellas | `calificaciones` única por par solicitud/evaluador |
| UC-9 | Coordinación | GET filtrado de solicitudes, visitas, evaluadores | Export operativo |
| UC-10 | Sistema | Segunda visita de **otro** evaluador; si discrepa, tercera | Objetividad |

---

## Diagrama de componentes

```mermaid
flowchart TB
  subgraph canales["Canales — facade, aún no elegido"]
    WA[WhatsApp / bot]
    APP[App o web]
    CURL[Cliente HTTP / curls]
  end

  subgraph api["API REST — un contrato"]
    AUTH[GoTrue / Auth]
    REST[PostgREST]
    ST[Storage]
    TS[Capa TS: frontier Zod + comandos]
  end

  subgraph nucleo_box["Núcleo — verificador"]
    PUB["public.* wrappers invoker"]
    NUC["nucleo.* definer + transiciones"]
    PG[(Postgres + PostGIS)]
    PIN[(nucleo.visita_pines)]
  end

  WA --> TS
  APP --> TS
  CURL --> REST
  TS --> REST
  TS --> AUTH
  REST --> PUB
  PUB --> NUC
  NUC --> PG
  NUC --> PIN
  AUTH --> PG
  ST --> PG
  REST --> PG
```

Flujo de un comando: JSON → Zod (HTTP) → RPC `public.foo` → `nucleo.foo` → fila → Zod (DB) → unión discriminada. Nunca `JSON.parse` fuera de `src/frontier/json.ts`.

---

## Diagrama de secuencia

Camino feliz de una visita (PIN + formulario). El segundo evaluador replica UC-4…UC-6 sobre la misma solicitud.

```mermaid
sequenceDiagram
  autonumber
  actor Sol as Solicitante
  actor Ev as Evaluador
  participant API as PostgREST
  participant N as nucleo
  participant DB as Postgres

  Sol->>API: crear_solicitud(lng, lat, talla, ventana)
  API->>N: nucleo.crear_solicitud
  N->>DB: INSERT solicitudes estado=visita_pendiente
  DB-->>Sol: solicitud

  Note over API,N: Coordinación o service_role
  API->>N: generar_visitas_potenciales()
  N->>DB: INSERT visitas_potenciales estado=creada<br/>si cobertura ∩ agenda

  Ev->>API: GET buzon_evaluador
  DB-->>Ev: lista de visitas creada

  Ev->>API: aceptar_visita(visita_id)
  API->>N: nucleo.aceptar_visita
  N->>DB: visita=aceptada, solicitud=en_evaluacion<br/>hermanas cancelada/tomada_por_otro
  N->>DB: INSERT nucleo.visita_pines hash
  N-->>Ev: { pin: "1234" } una sola vez

  Sol->>Ev: "¿cuál es el PIN?"
  Ev-->>Sol: 1234

  Sol->>API: verificar_pin(visita_id, "0000")
  N->>DB: INSERT alertas pin_incorrecto<br/>pin_intentos=1
  N-->>Sol: { ok: false, intentos: 1, alerta: true }

  Ev->>API: regenerar_pin(visita_id)
  N-->>Ev: { pin: "9876" }

  Sol->>API: verificar_pin(visita_id, "9876")
  N->>DB: pin_verificado_en, DELETE visita_pines<br/>INSERT visitas_realizadas
  N-->>Sol: { ok: true, solicitud_estado: en_evaluacion }

  Ev->>API: iniciar_formulario(visita_realizada_id)
  N-->>Ev: estado id actual siguiente
  Ev->>API: responder_campo(fd_id, campo_id, valor)
  N->>DB: guarda respuesta; avanza cursor si era el actual
  N-->>Ev: nuevo estado
  Ev->>API: commit_formulario(fd_id)
  N->>DB: congela FD; concluir_visita con mapeo AIS<br/>solicitud=evaluacion_parcial o evaluada
  Sol->>API: calificar_evaluador(estrellas)
```

Segundo fallo de PIN (sin ir a evidencias):

```mermaid
sequenceDiagram
  actor Sol as Solicitante
  participant N as nucleo
  participant DB as Postgres
  Sol->>N: verificar_pin (2º fallo)
  N->>DB: visita cancelada/pin_fallido
  N->>DB: solicitud evaluacion_fallida
  N-->>Sol: { ok: false, cancelada: true }
  Note over N: El generador puede reagendar
```

---

## CURL pruebas básicas

Requisitos: stack **Foinikis** arriba (no el de Eve si Eve ya ocupa `54321`). Claves demo de `supabase start`, o `supabase status -o env`.

```bash
BASE=http://127.0.0.1:54321
ANON=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0
SERVICE=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU
VENTANA='[\"2026-08-14T08:00:00+00\",\"2026-08-14T20:00:00+00\")'
```

Siempre `apikey` y `Authorization`. Flujo encadenado (IDs y PIN extraídos solos): `./scripts/pruebas-api.sh`.

### Auth

```bash
curl -sS "$BASE/auth/v1/signup" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d '{"email":"solicitante@foinikis.test","password":"Prueba1234"}'

curl -sS "$BASE/auth/v1/signup" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d '{"email":"eval-a@foinikis.test","password":"Prueba1234"}'

curl -sS "$BASE/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d '{"email":"solicitante@foinikis.test","password":"Prueba1234"}'
```

### Altas

```bash
curl -sS "$BASE/rest/v1/rpc/registrar_persona" \
  -H "apikey: $ANON" -H "Authorization: Bearer $SOL_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Ana Solicitante","telefono":"+573001112233"}'

curl -sS "$BASE/rest/v1/rpc/registrar_evaluador" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"tipo\":\"voluntario\",\"tarjeta_profesional_path\":\"uid/tarjeta.jpg\",\"transporte_propio\":true,\"lng\":-74.0721,\"lat\":4.7110,\"radio_metros\":15000,\"ventana\":\"$VENTANA\"}"

curl -sS "$BASE/rest/v1/rpc/crear_solicitud" \
  -H "apikey: $ANON" -H "Authorization: Bearer $SOL_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"lng\":-74.0721,\"lat\":4.7110,\"talla\":\"m\",\"ventana\":\"$VENTANA\"}"
```

### Matching y listados

```bash
curl -sS "$BASE/rest/v1/rpc/generar_visitas_potenciales" \
  -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" \
  -H "Content-Type: application/json" -d '{}'

curl -sS "$BASE/rest/v1/buzon_evaluador?select=*" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN"

curl -sS "$BASE/rest/v1/solicitudes?estado=eq.visita_pendiente&select=id,estado,talla" \
  -H "apikey: $ANON" -H "Authorization: Bearer $SOL_TOKEN"

curl -sS "$BASE/rest/v1/visitas_potenciales_api?estado=eq.creada&select=id,solicitud_id,estado" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN"

curl -sS "$BASE/rest/v1/evaluadores?tipo=eq.voluntario&select=id,tipo,score_confianza" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN"
```

### Visita y PIN

```bash
curl -sS "$BASE/rest/v1/rpc/rechazar_visita" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EB_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"visita_id":"<UUID>"}'

curl -sS "$BASE/rest/v1/rpc/aceptar_visita" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"visita_id":"<UUID>"}'

curl -sS "$BASE/rest/v1/rpc/verificar_pin" \
  -H "apikey: $ANON" -H "Authorization: Bearer $SOL_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"visita_id":"<UUID>","pin":"0000"}'

curl -sS "$BASE/rest/v1/rpc/regenerar_pin" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"visita_id":"<UUID>"}'

curl -sS "$BASE/rest/v1/rpc/verificar_pin" \
  -H "apikey: $ANON" -H "Authorization: Bearer $SOL_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"visita_id":"<UUID>","pin":"<PIN>"}'
```

### Formulario y cierre

```bash
curl -sS "$BASE/rest/v1/visitas_realizadas?select=id,evaluador_id,concluida_en" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN"

curl -sS "$BASE/rest/v1/rpc/iniciar_formulario" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"visita_realizada_id":"<UUID>"}'

curl -sS "$BASE/rest/v1/rpc/estado_formulario" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"formulario_diligenciado_id":"<UUID>"}'

curl -sS "$BASE/rest/v1/rpc/responder_campo" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"formulario_diligenciado_id":"<UUID>","campo_id":"<UUID>","valor":{"texto":"Chapinero"}}'

curl -sS "$BASE/rest/v1/rpc/respuestas_formulario" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"formulario_diligenciado_id":"<UUID>"}'

curl -sS "$BASE/rest/v1/rpc/commit_formulario" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"formulario_diligenciado_id":"<UUID>"}'

curl -sS "$BASE/rest/v1/rpc/calificar_evaluador" \
  -H "apikey: $ANON" -H "Authorization: Bearer $SOL_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"solicitud_id":"<UUID>","evaluador_id":"<UUID>","estrellas":5}'

curl -sS "$BASE/rest/v1/rpc/marcar_no_encontrada" \
  -H "apikey: $ANON" -H "Authorization: Bearer $EA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"visita_realizada_id":"<UUID>"}'

curl -sS "$BASE/rest/v1/alertas?select=*" \
  -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE"
```

Una `aceptar_visita` sobre una visita ya `aceptada` debe responder `transicion_ilegal`. El commit incompleto devuelve `campos_obligatorios_pendientes` y el mismo estado.
