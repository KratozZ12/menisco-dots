#!/bin/sh
# Vigilante de fallos conocidos (lo corre Cerebro.qml cada minuto). Solo mira, no cambia nada.
# Una linea por problema:  clave|titulo corto para la isla|detalle para la Gota
# Lista corta a proposito: los registros del sistema tienen errores inofensivos todo el rato,
# y avisar de todos haria que nadie le hiciera caso. Se amplia cuando aparezca un fallo nuevo.

# Bluetooth: el servicio cayo, o no hay adaptador
if systemctl is-failed -q bluetooth.service; then
    echo "bt|El Bluetooth se cayó|bluetooth.service está en estado failed"
elif systemctl is-active -q bluetooth.service && [ -z "$(timeout 5 bluetoothctl list 2>/dev/null)" ]; then
    echo "bt|No encuentro el Bluetooth|bluetooth.service activo pero bluetoothctl list no muestra adaptador"
fi

# Sonido: PipeWire y compania
for s in pipewire wireplumber pipewire-pulse; do
    systemctl --user is-active -q "$s.service" || { echo "sonido|El sonido se cayó|$s.service (de usuario) no está activo: $(systemctl --user is-active "$s.service")"; break; }
done

# Portal del escritorio (dialogos de abrir/guardar, capturas en apps)
systemctl --user is-failed -q xdg-desktop-portal.service && echo "portal|El portal del escritorio falló|xdg-desktop-portal.service de usuario en estado failed"

# Grafica: tras actualizar NVIDIA sin reiniciar, el driver y el modulo no coinciden
if command -v nvidia-smi >/dev/null && ! timeout 10 nvidia-smi -L >/dev/null 2>&1; then
    echo "grafica|La gráfica perdió el driver|nvidia-smi falla: $(timeout 10 nvidia-smi -L 2>&1 | head -1)"
fi

# Disco casi lleno (carpeta personal al 95 % o mas)
uso=$(df --output=pcent "$HOME" | tail -1 | tr -dc 0-9)
[ "${uso:-0}" -ge 95 ] && echo "disco|Te queda poco disco|la carpeta personal está al $uso %: $(df -h --output=avail "$HOME" | tail -1 | tr -d ' ') libres"

# Cualquier servicio de usuario fallado (los del sistema traen ruido, como drkonqi)
systemctl --user --failed --no-legend --plain 2>/dev/null | while read -r u _; do
    case "$u" in pipewire*|wireplumber*|xdg-desktop-portal.service) continue ;; esac
    echo "u:$u|${u%.service} dejó de funcionar|el servicio de usuario $u está en estado failed"
done
exit 0
