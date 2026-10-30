#!/usr/bin/env bash
# Copia los dots a ~/.config. Si ya hay una config de niri, lniri o la carpeta
# quickshell/isla, la mueve a <nombre>.antes-de-menisco y avisa.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"

poner() {   # poner <origen> <destino>
    if [ -e "$2" ]; then
        mv "$2" "$2.antes-de-menisco"
        echo "Respaldo: $2 -> $2.antes-de-menisco"
    fi
    mkdir -p "$(dirname "$2")"
    cp -r "$1" "$2"
}

poner "$AQUI/niri/config.kdl"     "$CFG/niri/config.kdl"
poner "$AQUI/quickshell/isla"     "$CFG/quickshell/isla"
mkdir -p "$CFG/lniri"
cp "$AQUI/lniri/config.kdl" "$AQUI/lniri/vidrio-activo.kdl" "$CFG/lniri/"
cp "$AQUI/lniri/vidrio-activo.kdl" "$CFG/lniri/vidrio.kdl"     # liquid glass encendido

echo "Listo. Cierre sesion y entre a niri (o a Lniri si lo compilo)."
