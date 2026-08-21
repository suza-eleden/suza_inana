#!/usr/bin/env bash
# Pruebas HTTP de Foinikis (Supabase local).
# No uses el puerto de Eve: si Eve está en 54321, arrancá Foinikis en otro
# (FOINIKIS_URL) o pará Eve con `supabase stop` desde ese repo.
#
#   chmod +x scripts/pruebas-api.sh
#   FOINIKIS_URL=http://127.0.0.1:54321 ./scripts/pruebas-api.sh
#
# Claves locales por defecto = JWT demo de `supabase start`.
# Para las reales: `cd supabase && supabase status -o env`

set -euo pipefail

BASE="${FOINIKIS_URL:-http://127.0.0.1:54321}"
ANON="${FOINIKIS_ANON_KEY:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0}"
SERVICE="${FOINIKIS_SERVICE_ROLE_KEY:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU}"

VENTANA='[\"2026-08-14T08:00:00+00\",\"2026-08-14T20:00:00+00\")'
STAMP="$(date +%s)"
PASS="Prueba1234"

py() { python3 -c "$1"; }

echo "Base: ${BASE}"
echo

# --- 1. Signup ---------------------------------------------------------------
echo "### 1. Signup solicitante"
SOL_JSON="$(curl -sS "${BASE}/auth/v1/signup" \
  -H "apikey: ${ANON}" -H "Content-Type: application/json" \
  -d "{\"email\":\"solicitante+${STAMP}@example.com\",\"password\":\"${PASS}\"}")"
echo "${SOL_JSON}"
SOL_TOKEN="$(printf '%s' "${SOL_JSON}" | py 'import json,sys; print(json.load(sys.stdin)["access_token"])')"
echo

echo "### 1b. Signup evaluador A"
EA_JSON="$(curl -sS "${BASE}/auth/v1/signup" \
  -H "apikey: ${ANON}" -H "Content-Type: application/json" \
  -d "{\"email\":\"eval-a+${STAMP}@example.com\",\"password\":\"${PASS}\"}")"
echo "${EA_JSON}"
EA_TOKEN="$(printf '%s' "${EA_JSON}" | py 'import json,sys; print(json.load(sys.stdin)["access_token"])')"
EA_UID="$(printf '%s' "${EA_JSON}" | py 'import json,sys; print(json.load(sys.stdin)["user"]["id"])')"
echo

echo "### 1c. Signup evaluador B"
EB_JSON="$(curl -sS "${BASE}/auth/v1/signup" \
  -H "apikey: ${ANON}" -H "Content-Type: application/json" \
  -d "{\"email\":\"eval-b+${STAMP}@example.com\",\"password\":\"${PASS}\"}")"
echo "${EB_JSON}"
EB_TOKEN="$(printf '%s' "${EB_JSON}" | py 'import json,sys; print(json.load(sys.stdin)["access_token"])')"
echo

# --- 2. Persona --------------------------------------------------------------
echo "### 2. registrar_persona"
curl -sS "${BASE}/rest/v1/rpc/registrar_persona" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${SOL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Ana Solicitante","telefono":"+573001112233"}'
echo; echo

# --- 3. Evaluadores ----------------------------------------------------------
echo "### 3. registrar_evaluador A (voluntario, Bogotá, 15km)"
curl -sS "${BASE}/rest/v1/rpc/registrar_evaluador" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"tipo\":\"voluntario\",\"tarjeta_profesional_path\":\"${EA_UID}/tarjeta.jpg\",\"transporte_propio\":true,\"lng\":-74.0721,\"lat\":4.7110,\"radio_metros\":15000,\"ventana\":\"${VENTANA}\"}"
echo; echo

echo "### 3b. registrar_evaluador B (oficial)"
curl -sS "${BASE}/rest/v1/rpc/registrar_evaluador" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"tipo\":\"oficial\",\"tarjeta_profesional_path\":\"placeholder/tarjeta.jpg\",\"transporte_propio\":false,\"lng\":-74.0721,\"lat\":4.7110,\"radio_metros\":20000,\"ventana\":\"${VENTANA}\"}"
echo; echo

# --- 4. Solicitud ------------------------------------------------------------
echo "### 4. crear_solicitud"
SOLICITUD_JSON="$(curl -sS "${BASE}/rest/v1/rpc/crear_solicitud" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${SOL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"lng\":-74.0721,\"lat\":4.7110,\"talla\":\"m\",\"ventana\":\"${VENTANA}\"}")"
echo "${SOLICITUD_JSON}"
SOLICITUD_ID="$(printf '%s' "${SOLICITUD_JSON}" | py 'import json,sys; print(json.load(sys.stdin)["id"])')"
echo

# --- 5. Generador ------------------------------------------------------------
echo "### 5. generar_visitas_potenciales (service_role)"
curl -sS "${BASE}/rest/v1/rpc/generar_visitas_potenciales" \
  -H "apikey: ${SERVICE}" -H "Authorization: Bearer ${SERVICE}" \
  -H "Content-Type: application/json" \
  -d '{}'
echo; echo

# --- 6. Listas ---------------------------------------------------------------
echo "### 6. GET buzon_evaluador"
BUZON="$(curl -sS "${BASE}/rest/v1/buzon_evaluador?select=*" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}")"
echo "${BUZON}"
VISITA_ID="$(printf '%s' "${BUZON}" | py 'import json,sys; d=json.load(sys.stdin); print(d[0]["id"] if d else "")')"
echo

echo "### 6b. GET solicitudes filtradas"
curl -sS "${BASE}/rest/v1/solicitudes?estado=eq.visita_pendiente&select=id,estado,talla" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${SOL_TOKEN}"
echo; echo

echo "### 6c. GET visitas_potenciales_api filtradas"
curl -sS "${BASE}/rest/v1/visitas_potenciales_api?estado=eq.creada&select=id,solicitud_id,evaluador_id,estado" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}"
echo; echo

echo "### 6d. GET evaluadores filtrados"
curl -sS "${BASE}/rest/v1/evaluadores?tipo=eq.voluntario&select=id,tipo,radio_metros,score_confianza" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}"
echo; echo

# --- 7. Rechazar / aceptar ---------------------------------------------------
echo "### 7. rechazar_visita (evaluador B, si tiene buzón)"
BUZON_B="$(curl -sS "${BASE}/rest/v1/buzon_evaluador?select=id" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EB_TOKEN}")"
VISITA_B="$(printf '%s' "${BUZON_B}" | py 'import json,sys; d=json.load(sys.stdin); print(d[0]["id"] if d else "")')"
if [[ -n "${VISITA_B}" ]]; then
  curl -sS "${BASE}/rest/v1/rpc/rechazar_visita" \
    -H "apikey: ${ANON}" -H "Authorization: Bearer ${EB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"visita_id\":\"${VISITA_B}\"}"
  echo; echo
fi

echo "### 7b. aceptar_visita (devuelve pin UNA vez)"
ACEPTACION="$(curl -sS "${BASE}/rest/v1/rpc/aceptar_visita" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"visita_id\":\"${VISITA_ID}\"}")"
echo "${ACEPTACION}"
PIN="$(printf '%s' "${ACEPTACION}" | py 'import json,sys; print(json.load(sys.stdin).get("pin",""))')"
echo

# --- 8. PIN ------------------------------------------------------------------
echo "### 8. verificar_pin incorrecto → alerta"
curl -sS "${BASE}/rest/v1/rpc/verificar_pin" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${SOL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"visita_id\":\"${VISITA_ID}\",\"pin\":\"0000\"}"
echo; echo

echo "### 8b. regenerar_pin"
NUEVO="$(curl -sS "${BASE}/rest/v1/rpc/regenerar_pin" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"visita_id\":\"${VISITA_ID}\"}")"
echo "${NUEVO}"
PIN="$(printf '%s' "${NUEVO}" | py 'import json,sys; print(json.load(sys.stdin).get("pin",""))')"
echo

echo "### 8c. verificar_pin correcto"
curl -sS "${BASE}/rest/v1/rpc/verificar_pin" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${SOL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"visita_id\":\"${VISITA_ID}\",\"pin\":\"${PIN}\"}"
echo; echo

# --- 9. Visita realizada -----------------------------------------------------
echo "### 9. GET visitas_realizadas"
VR="$(curl -sS "${BASE}/rest/v1/visitas_realizadas?select=id,solicitud_id,evaluador_id,concluida_en" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}")"
echo "${VR}"
VR_ID="$(printf '%s' "${VR}" | py 'import json,sys; d=json.load(sys.stdin); print(d[0]["id"] if d else "")')"
EVAL_ID="$(printf '%s' "${VR}" | py 'import json,sys; d=json.load(sys.stdin); print(d[0]["evaluador_id"] if d else "")')"
echo

echo "### 9b. iniciar_formulario"
FD_JSON="$(curl -sS "${BASE}/rest/v1/rpc/iniciar_formulario" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"visita_realizada_id\":\"${VR_ID}\"}")"
echo "${FD_JSON}"
FD_ID="$(printf '%s' "${FD_JSON}" | py 'import json,sys; print(json.load(sys.stdin)["id"])')"
FORM_ID="$(printf '%s' "${FD_JSON}" | py 'import json,sys; print(json.load(sys.stdin)["formulario_id"])')"
echo

echo "### 9c. segundo iniciar_formulario (idempotente)"
curl -sS "${BASE}/rest/v1/rpc/iniciar_formulario" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"visita_realizada_id\":\"${VR_ID}\"}"
echo; echo

echo "### 9d. responder campos obligatorios + evidencias"
CAMPOS="$(curl -sS "${BASE}/rest/v1/campos?formulario_id=eq.${FORM_ID}&select=id,codigo,tipo,opciones,obligatorio" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}")"
python3 - "${BASE}" "${ANON}" "${EA_TOKEN}" "${FD_ID}" "${CAMPOS}" <<'PY'
import json, sys, urllib.request

base, anon, token, fd_id, campos_raw = sys.argv[1:]
campos = json.loads(campos_raw)

def valor(campo):
    if campo["tipo"] == "texto":
        return {"texto": "prueba"}
    if campo["tipo"] == "imagen":
        return {"storage_path": "uid/evidencia.jpg"}
    if campo["tipo"] == "geolocalizacion":
        return {"lat": 4.711, "lng": -74.0721}
    if campo["codigo"] == "cartel_clasificacion":
        return {"valor": 2} # Amarillo (Uso Restringido)
    if campo["codigo"] == "clasificacion_dano":
        return {"valor": 3}
    opciones = campo.get("opciones") or []
    return {"valor": opciones[0]["valor"]}

def rpc(nombre, payload):
    req = urllib.request.Request(
        f"{base}/rest/v1/rpc/{nombre}",
        data=json.dumps(payload).encode(),
        headers={
            "apikey": anon,
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())

for campo in campos:
    if not campo["obligatorio"] and campo["codigo"] not in ("esquema", "foto_3_dano_critico"):
        continue
    estado = rpc("responder_campo", {
        "formulario_diligenciado_id": fd_id,
        "campo_id": campo["id"],
        "valor": valor(campo),
    })
    if not estado.get("ok"):
        raise SystemExit(f"responder_campo falló en {campo['codigo']}: {estado}")
print("obligatorios + evidencias ok")
PY

echo

echo "### 9e. respuestas_formulario"
curl -sS "${BASE}/rest/v1/rpc/respuestas_formulario" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"formulario_diligenciado_id\":\"${FD_ID}\"}"
echo; echo

echo "### 9f. commit_formulario"
curl -sS "${BASE}/rest/v1/rpc/commit_formulario" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"formulario_diligenciado_id\":\"${FD_ID}\"}"
echo; echo

echo "### 9g. GET evidencias (vista sobre respuestas imagen)"
curl -sS "${BASE}/rest/v1/evidencias?select=campo_formulario,storage_path" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}"
echo; echo

# --- 10. Calificar + export --------------------------------------------------
echo "### 10. calificar_evaluador"
curl -sS "${BASE}/rest/v1/rpc/calificar_evaluador" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${SOL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"solicitud_id\":\"${SOLICITUD_ID}\",\"evaluador_id\":\"${EVAL_ID}\",\"estrellas\":5}"
echo; echo

echo "### 10b. GET solicitudes?estado=eq.evaluacion_parcial"
curl -sS "${BASE}/rest/v1/solicitudes?estado=eq.evaluacion_parcial&select=id,estado,talla" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${SOL_TOKEN}"
echo; echo

echo "### 10c. GET alertas (service_role)"
curl -sS "${BASE}/rest/v1/alertas?select=*" \
  -H "apikey: ${SERVICE}" -H "Authorization: Bearer ${SERVICE}"
echo; echo

# --- 11. Ilegal --------------------------------------------------------------
echo "### 11. aceptar_visita de nuevo (transicion_ilegal)"
curl -sS "${BASE}/rest/v1/rpc/aceptar_visita" \
  -H "apikey: ${ANON}" -H "Authorization: Bearer ${EA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"visita_id\":\"${VISITA_ID}\"}"
echo; echo

echo "### extras útiles (no ejecutados)"
echo "# login:"
echo "curl -sS ${BASE}/auth/v1/token?grant_type=password \\"
echo "  -H 'apikey: \$ANON' -H 'Content-Type: application/json' \\"
echo "  -d '{\"email\":\"...\",\"password\":\"${PASS}\"}'"
echo
echo "# commit incompleto (campos_obligatorios_pendientes):"
echo "curl -sS ${BASE}/rest/v1/rpc/commit_formulario \\"
echo "  -H 'Authorization: Bearer \$EA_TOKEN' -H 'apikey: \$ANON' -H 'Content-Type: application/json' \\"
echo "  -d '{\"formulario_diligenciado_id\":\"\$FD_ID\"}'"
echo
echo "# marcar_no_encontrada:"
echo "curl -sS ${BASE}/rest/v1/rpc/marcar_no_encontrada \\"
echo "  -H 'Authorization: Bearer \$EA_TOKEN' -H 'apikey: \$ANON' -H 'Content-Type: application/json' \\"
echo "  -d '{\"visita_realizada_id\":\"\$VR_ID\"}'"
echo
echo "# segundo fallo de PIN (cancela visita + solicitud evaluacion_fallida):"
echo "curl -sS ${BASE}/rest/v1/rpc/verificar_pin \\"
echo "  -H 'Authorization: Bearer \$SOL_TOKEN' -H 'apikey: \$ANON' -H 'Content-Type: application/json' \\"
echo "  -d '{\"visita_id\":\"\$VISITA_ID\",\"pin\":\"1111\"}'"
echo
echo "Listo. solicitud=${SOLICITUD_ID} visita=${VISITA_ID}"
