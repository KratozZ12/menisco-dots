# Vino Dots

> El nombre es provisional.

Un escritorio para **niri** hecho a mano con **Quickshell**: una isla con reloj, un asistente animado y un visualizador de audio; un dock de vidrio; una ventana de ajustes; y un aviso de volumen de líquido. Todo en grises, blanco y vidrio, con tipografía SF Pro y animaciones con rebote suave.

Funciona en niri normal (con desenfoque) y en **Lniri**, un niri modificado que agrega *liquid glass*, es decir, refracción real en los bordes del vidrio.

---

## Qué trae

### La isla
Muesca pegada al borde de arriba, con curvas continuas tipo *squircle*.

- **Reloj** al centro, en SF Pro Semibold con cifras de ancho fijo.
- **Asistente** a la izquierda: una carita con ojos proyectados en 3D sobre una esfera. Mira a su alrededor, parpadea (a veces dos veces seguidas) y se duerme entre gestos para no gastar CPU. Todavía no hace nada; es el diseño.
  - Seis emociones, cada una con su forma y su color. Cambiar de una a otra transforma la cabeza con un rebote:

    | Emoción | Forma | Color |
    |---|---|---|
    | `normal` | esfera | negro |
    | `feliz` | cápsula | verde |
    | `escucha` | triángulo | azul |
    | `pensar` | gota | gris |
    | `emocion` | nube | naranja |
    | `confuso` | trébol | café |

    Para probarlas: `qs -p ~/.config/quickshell/isla ipc call asistente emocion feliz`
- **Visualizador de audio** a la derecha: 5 barras redondeadas que siguen el sonido real (con [cava](https://github.com/karlstav/cava)). En silencio se convierten en una línea ondulada suave.

### Dock
- Vidrio esmerilado en niri; *liquid glass* en Lniri.
- Lupa al pasar el cursor, con rebote, y un punto debajo de las apps abiertas.
- Las apps abiertas que no están ancladas aparecen solas y el dock crece con animación.
- **Clic derecho:** Anclar al dock / Quitar del dock / Abrir / Cerrar. Las ancladas se guardan en `~/.config/quickshell/isla/dock.json`.
- Botón para abrir el menú de apps (fuzzel).

### Ajustes (`Super+.`)
Ventana flotante centrada. La página **Inicio** tiene:
- El fondo de pantalla actual en grande y un selector de fondos (lee `~/Imágenes/Wallpapers`; se cambia en `Ajustes.qml`).
- Opciones rápidas: Liquid glass, No molestar (Hokum), Isla visible, Bluetooth, radio de las esquinas de las ventanas y Modo café (evita la suspensión).

Las demás secciones están por hacer.

### Aviso de volumen
Cápsula pequeña sobre el dock que se llena de líquido con el borde ondulado. Aparece al cambiar el volumen y se va sola.

---

## Requisitos

| Qué | Para qué |
|---|---|
| [niri](https://github.com/niri-wm/niri) 26.04 o más nuevo | el compositor |
| [Quickshell](https://quickshell.org) 0.3 | la isla, el dock, los ajustes y el aviso de volumen |
| [awww](https://codeberg.org/LGFae/awww) | el fondo de pantalla |
| [Hokum](https://hokum.app) | las notificaciones |
| [cava](https://github.com/karlstav/cava) | el visualizador de audio |
| [fuzzel](https://codeberg.org/dnkl/fuzzel) | el menú de apps |
| PipeWire, BlueZ | volumen y Bluetooth |
| Tipografía **SF Pro** | textos (ver la nota de abajo) |
| [Material Symbols Rounded](https://github.com/google/material-design-icons) (fuente variable) | iconos |
| Tema de iconos [WhiteSur](https://github.com/vinceliuice/WhiteSur-icon-theme) | iconos del dock (opcional) |

> **Sobre SF Pro:** es de Apple, se descarga gratis en [developer.apple.com/fonts](https://developer.apple.com/fonts/), pero su licencia solo permite usarla para diseñar apps para dispositivos de Apple. Este repo **no** la incluye. Si no la instala, Qt usará otra fuente; Inter Display es un buen sustituto (cambie `"SF Pro Text"` en los `.qml`).

---

## Instalación

```bash
git clone https://github.com/KratozZ12/Vino-Dots
cd Vino-Dots
./instalar.sh
```

`instalar.sh` copia todo a `~/.config`. Si ya tenía una configuración de niri, Hokum o `quickshell/isla`, la renombra a `*.antes-de-vino-dots` y se lo dice.

Después, revise en `~/.config/niri/config.kdl`:
- los bloques `output` (nombres y posición de **sus** monitores);
- las líneas de **KWallet** y del agente de polkit de KDE: si no usa KDE, bórrelas o cámbielas por las de su escritorio.

### Lniri (opcional, para el liquid glass)

```bash
./lniri/compilar.sh
```

Compila niri 26.04 con los archivos de [TattvaOrg/Lniri](https://github.com/TattvaOrg/Lniri) y lo instala como una sesión aparte, **"Lniri (Liquid Glass)"**. El niri normal no se toca. Lniri lee `~/.config/lniri/config.kdl`, que incluye la configuración de niri y le suma `vidrio.kdl` (el botón *Liquid glass* de los ajustes copia o vacía ese archivo).

> El *liquid glass* solo se ve detrás de lo que es transparente: el dock, terminales con transparencia y otras piezas de Quickshell. Las ventanas opacas lo tapan.

---

## Atajos

| Atajo | Qué hace |
|---|---|
| `Super+.` | abrir/cerrar los ajustes |
| `Super+D` | menú de apps |
| `Super+T` | terminal |
| `Super+Q` | cerrar ventana |
| `Super+O` | vista general |
| `Super+Shift+S` | captura de una zona |
| `Super+Shift+/` | lista de todos los atajos |

El resto son los atajos de fábrica de niri.

---

## Cosas que conviene saber

- **Si usa también Plasma u otro escritorio en la misma máquina:** Hokum (y mako, si lo tiene) pueden quitarle las notificaciones al otro escritorio, porque arrancan solos cuando llega una notificación. Aquí niri lo arranca a mano; para bloquear el arranque automático:
  ```bash
  systemctl --user mask hokum.service
  ```
  y cree `~/.local/share/dbus-1/services/app.hokum.Notifications.service` con el `Exec=` del servicio de notificaciones de su otro escritorio.
- **Sin un programa de notificaciones**, algunas apps (como la de escritorio de Claude) se congelan esperando respuesta. No quite Hokum sin poner otro.
- **Quickshell a la frecuencia del monitor:** niri lo lanza con `QSG_RENDER_LOOP=threaded`; sin eso, Qt anima a 60 fps aunque el monitor vaya a 144.
- **El fondo de awww vive en el *backdrop* de niri:** por eso el fondo de los espacios de trabajo es transparente en la configuración.

---

## Créditos

- [niri](https://github.com/niri-wm/niri) y [Lniri](https://github.com/TattvaOrg/Lniri) por el compositor y el *liquid glass*.
- [Quickshell](https://quickshell.org).
- [Hokum](https://hokum.app), [cava](https://github.com/karlstav/cava), [awww](https://codeberg.org/LGFae/awww), [fuzzel](https://codeberg.org/dnkl/fuzzel).
- Iconos: Material Symbols (Google) y WhiteSur.
