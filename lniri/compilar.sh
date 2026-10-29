#!/usr/bin/env bash
# Compila Lniri (niri 26.04 + liquid glass de TattvaOrg/Lniri) y lo instala como sesion aparte.
# No toca el niri del sistema. Pide la contrasena solo para copiar a /usr/local y /usr/share.
set -euo pipefail

BASE="${XDG_DATA_HOME:-$HOME/.local/share}/lniri"
AQUI="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$BASE"

# Fedora: herramientas para compilar (en otras distros, los paquetes equivalentes).
if command -v dnf >/dev/null; then
    sudo dnf install -y clang libinput-devel libseat-devel pipewire-devel mesa-libgbm-devel \
        libdisplay-info-devel libxkbcommon-devel pango-devel cairo-devel systemd-devel wayland-devel
fi

[ -d "$BASE/overlay" ] || git clone --depth 1 https://github.com/TattvaOrg/Lniri "$BASE/overlay"
[ -d "$BASE/niri" ]    || git clone --depth 1 --branch v26.04 https://github.com/niri-wm/niri.git "$BASE/niri"

# Los archivos de Lniri estan hechos para niri 26.04: se copian encima de esa version exacta.
cd "$BASE/niri"
for f in src/render_helpers/liquid_glass.rs src/render_helpers/background_effect.rs \
         src/render_helpers/framebuffer_effect.rs src/render_helpers/xray.rs src/render_helpers/mod.rs \
         src/render_helpers/shaders/clipped_surface.frag src/render_helpers/shaders/mod.rs \
         niri-config/src/appearance.rs src/layer/mapped.rs; do
    cp -f "$BASE/overlay/$f" "$f"
done
cargo build --release --bin niri

# Sesion aparte. El servicio de este repo agrega NIRI_CONFIG=~/.config/lniri/config.kdl
# (el oficial lee la config de niri, que no entiende el bloque liquid-glass).
# No se instala lniri-portals.conf: fija gnome-keyring y chocaria con KWallet.
sudo install -Dm755 -s target/release/niri /usr/local/bin/lniri
sudo install -Dm755 "$BASE/overlay/resources/lniri-session" /usr/local/bin/lniri-session
sudo install -Dm644 "$AQUI/lniri.service" /usr/lib/systemd/user/lniri.service
sudo install -Dm644 "$BASE/overlay/resources/lniri-shutdown.target" /usr/lib/systemd/user/lniri-shutdown.target
sudo install -Dm644 "$BASE/overlay/resources/lniri.desktop" /usr/share/wayland-sessions/lniri.desktop
echo "Lniri instalado. Elija \"Lniri (Liquid Glass)\" en la pantalla de inicio de sesion."
