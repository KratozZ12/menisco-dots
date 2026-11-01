#!/bin/sh
# Cerebro de la Gota: le pasa un mensaje a OpenCode con el agente de agents/gota.md.
# Uso: gota.sh "mensaje"            -> conversacion nueva
#      GOTA_SESION=ses_... gota.sh "mensaje"  -> sigue la misma conversacion
# Escribe eventos JSON, uno por linea (formato de `opencode run --format json`).
D=$(dirname "$(readlink -f "$0")")
cab=$(python3 -I - "$D/../menisco.json" <<'PY'
import json, sys, time, os
try: d = json.load(open(sys.argv[1]))
except Exception: d = {}
g = (d.get("gotas") or [{}])[min(d.get("gotaActiva", 0), len(d.get("gotas") or [{}]) - 1)]
print(f"[nombre: {g.get('nombre', 'Gota')} · personalidad: {d.get('personalidad', 'normal')} · usuario: {os.environ.get('USER', '')} · casa: {os.path.expanduser('~')} · hora: {time.strftime('%H:%M')}]")
PY
)
# Aislada de la configuracion global: sin plugins (caveman), sin el CLAUDE.md del usuario.
export OPENCODE_CONFIG_DIR="$D" OPENCODE_DISABLE_CLAUDE_CODE=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1
# Caja de solo lectura: todo el sistema montado sin permiso de escritura, salvo las carpetas
# donde OpenCode guarda sus sesiones. Aunque un comando se cuele por los permisos del agente,
# el sistema operativo no lo deja escribir. Los cambios reales los hace gota-plan.py, fuera.
o="$HOME/.local/share/opencode" c="$HOME/.cache/opencode" e="$HOME/.local/state/opencode"
mkdir -p "$o" "$c" "$e"
exec bwrap --ro-bind / / --dev-bind /dev /dev --proc /proc --tmpfs /tmp \
    --bind "$o" "$o" --bind "$c" "$c" --bind "$e" "$e" --die-with-parent -- \
    opencode run --pure --agent gota --format json --dir "$HOME" ${GOTA_SESION:+--session "$GOTA_SESION"} "$cab
$1" </dev/null   # sin esto, lanzado desde la isla espera texto por la entrada y no arranca
