# Menisco

> El *menisco* es la curva que forma un líquido en el borde de su recipiente: lo mismo que dibuja el liquid glass en el borde del vidrio.

Un escritorio para **niri** hecho a mano con **Quickshell**: una isla dinámica con avisos, música con letra, acciones rápidas y rendimiento; un asistente animado y personalizable; un dock de vidrio; un lanzador que brota del dock; una barra lateral; una ventana de ajustes completa; y un aviso de volumen de líquido. Todo en grises, blanco y vidrio, con tipografía SF Pro y animaciones con rebote suave.

Funciona en niri normal (con desenfoque) y en **Lniri**, un niri modificado que agrega *liquid glass*, es decir, refracción real en los bordes del vidrio.

---

## Qué trae

### La isla
Muesca pegada al borde de arriba, con curvas continuas tipo *squircle*.

- **Reloj** al centro, en SF Pro Semibold con cifras de ancho fijo (12 o 24 horas, con o sin segundos).
- **Asistente** a la izquierda (ver más abajo).
- **Visualizador de audio** a la derecha: 5 barras redondeadas que siguen el sonido real (con [cava](https://github.com/karlstav/cava)). En silencio se convierten en una línea ondulada suave. Si hay una grabación o un temporizador en marcha, ahí sale su tiempo.

**Avisos.** La isla crece unos segundos y vuelve sola cuando:
- empieza una canción nueva (carátula y título);
- se conectan audífonos o bocinas Bluetooth (con su batería);
- se guarda una captura (miniatura, con botones Abrir y Carpeta);
- la CPU o la GPU pasan de cierta temperatura;
- termina el temporizador o se copia un color.

Si la isla está abierta, los avisos esperan en fila y salen al cerrarla. Las notificaciones de las apps no pasan por la isla: las muestra [Hokum](https://hokum.app).

**Vista expandida.** Al pasar el cursor (o fija con un clic) crece hacia abajo con tres pestañas:
- **Música:** carátula grande (un clic lleva a la app), la isla teñida con el color del disco, barra de progreso que se arrastra, pastillas para elegir reproductor si suena más de uno, volumen de esa app, salida de audio (audífonos, bocinas, HDMI) y **letra sincronizada** abajo, que sube línea por línea con una ola, al estilo de Apple Music. La letra se busca en [LRCLIB](https://lrclib.net) y, si no está, en NetEase (`letra.sh`).
- **Acciones:** captura de zona o de pantalla completa, grabar pantalla (`wf-recorder`), tomar un color de la pantalla, temporizador (1, 5, 10 o 25 min), historial del portapapeles, modo juego (esconde el dock, silencia avisos, perfil de rendimiento), micrófono, bloquear, siguiente fondo y una nota rápida.
- **Rendimiento:** consumo en vatios, uso y temperatura de la CPU y la GPU NVIDIA, perfil de energía y los programas que más gastan (`rendimiento.py`, solo corre mientras se ve).

### Asistente
Una carita con ojos proyectados en 3D sobre una esfera. Mira a su alrededor, parpadea y se duerme entre gestos para no gastar CPU. Todavía no responde; es el diseño.

- Seis emociones, cada una con su forma y su color. Cambiar de una a otra transforma la cabeza con un rebote:

  | Emoción | Forma | Color |
  |---|---|---|
  | `normal` | la de su gota | el de su gota |
  | `feliz` | cápsula | verde |
  | `escucha` | triángulo | azul |
  | `pensar` | gota | gris |
  | `emocion` | nube | naranja |
  | `confuso` | trébol | café |

  Para probarlas: `qs -p ~/.config/quickshell/isla ipc call asistente emocion feliz`
- **Gotas:** en Ajustes > Asistente se crean asistentes propios con nombre, una de 14 formas y uno de 11 colores. Se puede elegir que cambie de forma con las emociones o que solo cambien los ojos.
- En la isla abierta tiene un botón vertical con luz azul que gira y chispas (se puede apagar).

### Dock
- Vidrio esmerilado en niri; *liquid glass* en Lniri.
- Lupa al pasar el cursor, con rebote, y un punto debajo de las apps abiertas.
- Las apps abiertas que no están ancladas aparecen solas y el dock crece con animación.
- **Clic derecho:** Anclar al dock / Quitar del dock / Abrir / Cerrar. Las ancladas se guardan en `~/.config/quickshell/isla/dock.json`.
- Botón de cuadrícula que abre el lanzador (se aclara al pasar el cursor; no usa la lupa).

### Lanzador (`Super+D` o el botón del dock)
Brota del botón de cuadrícula del dock con un rebote y regresa a él al cerrar. Al abrirlo, el asistente es "succionado" de la isla y reaparece en la barra de búsqueda, que está abajo, cerca del dock.

- **Sin escribir:** lo que está sonando (con controles), apps frecuentes (aprende de las que abre), ventanas abiertas y archivos recientes.
- **Al escribir:**
  - **Apps:** por nombre, y también por descripción y palabras clave (`minecraft` encuentra Prism Launcher).
  - **Calculadora:** `12*8+4`; `Enter` copia el resultado.
  - **Acciones:** apagar y reiniciar (piden un segundo `Enter`), bloquear, cerrar sesión, captura, Bluetooth y No molestar con interruptor, y los ajustes de Menisco.
  - **Archivos** de la carpeta personal (con `plocate`).
  - **Emojis**, en español o en inglés y sin importar acentos (`fuego`, `fire`). Con `:` delante se muestran solo emojis.
  - **Web:** buscar en el navegador.
- El asistente reacciona a la búsqueda: piensa con varios resultados, se alegra con uno, se confunde si no hay nada.
- Flechas para moverse, `Enter` para abrir, `Escape` para cerrar.

### Barra lateral (`Super+A`)
Centro de control que entra por un lado de la pantalla: botones rápidos (Wi-Fi, Bluetooth, No molestar, Modo café y más), volumen, música, calendario y energía, con páginas propias para Bluetooth, Wi-Fi y sonido. También se abre con el botón de estrella de la esquina o acercando el cursor al borde.

### Ajustes (`Super+.`)
Ventana flotante centrada con una sombra suave detrás. Se guardan en `~/.config/quickshell/isla/menisco.json`; lo que vive en niri lo escribe `menisco-niri.py` (y lo valida antes de guardar).
- **Inicio:** fondo de pantalla actual y selector (lee `~/Imágenes/Wallpapers`; se cambia en `Ajustes.qml`), y opciones rápidas.
- **Apariencia:** velocidad y rebote de las animaciones, color de la isla, tipografía, esquinas, espacio entre ventanas.
- **Pantallas**, **Liquid glass** y **Atajos** (se graban pulsando la combinación).
- **Isla:** qué muestra, cómo se abre y en qué pestaña, opciones de la pestaña Música y qué avisos salen.
- **Asistente:** sus gotas, carácter y el botón de luz.
- **Barra lateral:** lado, alto, ancho, y una miniatura donde se reordenan las secciones arrastrándolas.

### Aviso de volumen
Cápsula pequeña sobre el dock que se llena de líquido con el borde ondulado. Aparece al cambiar el volumen y se va sola.

---

## Requisitos

| Qué | Para qué |
|---|---|
| [niri](https://github.com/niri-wm/niri) 26.04 o más nuevo | el compositor |
| [Quickshell](https://quickshell.org) 0.3 | la isla, el dock, los ajustes y el aviso de volumen |
| [awww](https://codeberg.org/LGFae/awww) | el fondo de pantalla |
| [Hokum](https://hokum.app) | las notificaciones (y su No molestar) |
| [cava](https://github.com/karlstav/cava) | el visualizador de audio |
| `plocate`, `wl-clipboard`, `python3` | archivos, copiar resultados y emojis, archivos recientes |
| `curl`, `jq` | letras de canciones |
| `wf-recorder`, `cliphist`, `swaylock` | grabar pantalla, historial del portapapeles, bloquear |
| PipeWire, BlueZ, NetworkManager, `power-profiles-daemon` | volumen, Bluetooth, Wi-Fi y perfil de energía |
| `nvidia-smi` (opcional) | datos de la GPU en Rendimiento |
| Tipografía **SF Pro** | textos (ver la nota de abajo) |
| [Material Symbols Rounded](https://github.com/google/material-design-icons) (fuente variable) | iconos |
| Tema de iconos [WhiteSur](https://github.com/vinceliuice/WhiteSur-icon-theme) | iconos del dock (opcional) |

> **Sobre SF Pro:** es de Apple, se descarga gratis en [developer.apple.com/fonts](https://developer.apple.com/fonts/), pero su licencia solo permite usarla para diseñar apps para dispositivos de Apple. Este repo **no** la incluye. Si no la instala, Qt usará otra fuente; Inter Display es un buen sustituto (cambie `"SF Pro Text"` en los `.qml`).

---

## Instalación

```bash
git clone https://github.com/KratozZ12/menisco-dots
cd menisco-dots
./instalar.sh
```

`instalar.sh` copia todo a `~/.config`. Si ya tenía una configuración de niri, Hokum o `quickshell/isla`, la renombra a `*.antes-de-menisco` y se lo dice.

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
| `Super+D` | lanzador |
| `Super+A` | barra lateral |
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
- **No molestar** lo guarda Hokum; los interruptores de Menisco (ajustes, barra, lanzador, modo juego) lo cambian con `hokum dnd`.
- **Letras:** para buscar la letra, la isla manda el título y el artista de la canción a LRCLIB y, si no la encuentra, a NetEase (un servicio de China). Las dos se pueden apagar en Ajustes > Isla.
- **Quickshell a la frecuencia del monitor:** niri lo lanza con `QSG_RENDER_LOOP=threaded`; sin eso, Qt anima a 60 fps aunque el monitor vaya a 144.
- **El fondo de awww vive en el *backdrop* de niri:** por eso el fondo de los espacios de trabajo es transparente en la configuración.

---

## Créditos

- [niri](https://github.com/niri-wm/niri) y [Lniri](https://github.com/TattvaOrg/Lniri) por el compositor y el *liquid glass*.
- [Quickshell](https://quickshell.org).
- [Hokum](https://hokum.app), [cava](https://github.com/karlstav/cava), [awww](https://codeberg.org/LGFae/awww), [LRCLIB](https://lrclib.net).
- Iconos: Material Symbols (Google) y WhiteSur.

---

## Licencia

[MIT](LICENSE). Lniri (que `lniri/compilar.sh` descarga y compila) tiene su propia licencia, GPL-3.0.
