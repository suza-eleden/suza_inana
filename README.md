# Foinikis — régimen TypeScript + Postgres

![logo](./img/logo-provisional.jpg)

API de evaluación post-sismo. El front (app o WhatsApp) es un facade:
los invariantes viven en Postgres; TypeScript solo reduce cuántos errores
llegan hasta ahí.

## Régimen

- `tsconfig.json`: `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`.
- ESLint: nada de `any`, nada de `as`, `JSON.parse` solo en `src/frontier/json.ts`.
- Cada frontera (HTTP, DB) pasa por Zod. Los IDs son branded (`SolicitudId` ≠ `EvaluadorId`).
- Escrituras de estado: RPCs `public.*` → `nucleo.*`. No hay INSERT/UPDATE de solicitudes/visitas desde el cliente.
- El PIN se hashea en `nucleo.visita_pines`. PostgREST no puede leerlo.

## Local

```bash
supabase start
npm install
npm run types:gen    # pisa src/generated/database.ts
npm run typecheck && npm run lint && npm test
```

Variables: `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` (salen de `supabase status`).
Para el test de Postgres: `FOINIKIS_DB_URL` (default `postgresql://postgres:postgres@127.0.0.1:54322/postgres`).

## Máquina de estados

Solicitud: `creada → visita_pendiente → en_evaluacion → {evaluacion_parcial, evaluacion_fallida, evaluada}`.
`evaluacion_fallida` puede `reagendar` a `visita_pendiente`. Dos visitas realizadas distintas; si discrepan, una tercera desempatan.

Visita potencial: `creada → aceptada | rechazada | cancelada`. Aceptar genera un PIN de 4 cifras (una sola vez en la respuesta). Dos fallos de PIN cancelan y dejan la solicitud en `evaluacion_fallida`.
