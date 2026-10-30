// Tipografia: SF Pro Text con los grosores, tamanos y tracking de la guia de Apple (macOS).
// Movimiento: curva de las hojas de iOS (0.32, 0.72, 0, 1) para entrar, InCubic corto para salir.
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Widgets

// Ventana de ajustes de los dots. Capa flotante centrada (niri no la acomoda).
// Se abre y cierra con Super+. (IPC "ajustes toggle"); Escape la cierra.
PanelWindow {
    id: ventana

    required property var raiz          // ShellRoot: guarda islaVisible

    readonly property string carpetaFondos: Quickshell.env("HOME") + "/Imágenes/Wallpapers"
    readonly property string configNiri: Quickshell.env("HOME") + "/.config/niri/config.kdl"
    readonly property string dirLniri: Quickshell.env("HOME") + "/.config/lniri"
    readonly property var curvaIos: [0.32, 0.72, 0, 1, 1, 1]
    // Rebote suave: pasa un poco de largo (~12 %) y se asienta, sin oscilar.
    readonly property var curvaRebote: [0.3, 1.55, 0.5, 1, 1, 1]

    property bool abierta: false
    property string fondoActual: ""
    property string resolucion: ""      // "5120 × 2596"; la lee "file" sin cargar la imagen entera
    property bool vidrio: false
    // No molestar lo guarda Hokum (Estilo.noMolestar lo sigue).
    readonly property bool noMolestar: Estilo.noMolestar
    property bool cafe: false
    property int esquinas: 12
    property string seccion: "inicio"

    // Sigue mapeada mientras corre la animacion de cierre.
    visible: abierta || panel.opacity > 0.01
    implicitWidth: 800
    implicitHeight: 596
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ajustes"
    WlrLayershell.keyboardFocus: abierta ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function abrir() {
        leerEstado.running = true;
        abierta = true;
    }
    function cerrar() { abierta = false }

    function ejecutar(cmd) { Quickshell.execDetached(cmd) }

    // Estado que vive fuera del shell: fondo actual, vidrio y esquinas.
    Process {
        id: leerEstado
        command: ["sh", "-c",
            "awww query 2>/dev/null | sed -n 's/.*image: //p' | head -1;" +
            "test -s '" + ventana.dirLniri + "/vidrio.kdl' && echo si || echo no;" +
            "grep -oP '^\\s*geometry-corner-radius \\K[0-9]+(?=.*esquinas-ventanas)' '" + ventana.configNiri + "' || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                ventana.fondoActual = l[0] || "";
                ventana.vidrio = l[1] === "si";
                ventana.esquinas = parseInt(l[2]) || 0;
            }
        }
    }

    // El comando se arma aqui: por enlace llegaba con la ruta anterior (vacia la primera vez).
    onFondoActualChanged: if (fondoActual) { resolucion = ""; medir.command = ["file", "-b", fondoActual]; medir.running = true }
    Process {
        id: medir
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/(\d+)\s*x\s*(\d+)(?!.*\d+\s*x\s*\d+)/);
                ventana.resolucion = m ? m[1] + " × " + m[2] : "";
            }
        }
    }

    SystemClock { id: reloj; precision: SystemClock.Minutes }


    // ---- Pantallas ----
    // salidas: [{ nombre, modelo, conectada, x, ancho, alto, resoluciones, resolucion, frecuencias, frecuencia, escala, principal, modos }]
    property var salidas: []
    property string salidaElegida: ""
    readonly property var salidaActual: salidas.find(s => s.nombre === salidaElegida) ?? null
    Process {
        id: leerSalidas
        command: ["sh", "-c", "niri msg -j outputs; echo '---'; grep -oP '^output \"\\K[^\"]+' '" + ventana.configNiri + "'; echo '---'; awk '/^output /{n=$2} /focus-at-startup/{print n}' '" + ventana.configNiri + "'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const partes = text.split("---\n");
                let json = {};
                try { json = JSON.parse(partes[0]); } catch (e) {}
                const enConfig = (partes[1] || "").trim().split("\n").filter(n => n);
                const principal = (partes[2] || "").trim().replace(/"/g, "");
                const r = [];
                for (const n in json) {
                    const o = json[n], m = o.modes[o.current_mode] || o.modes[0], l = o.logical || { x: 0, width: m.width, height: m.height, scale: 1 };
                    const res = [...new Set(o.modes.map(x => x.width + "x" + x.height))].slice(0, 3);
                    // Una frecuencia por cada Hz redondeado (119.98 y 120.03 son "120 Hz"); se queda la exacta mas alta.
                    const porHz = {};
                    for (const x of o.modes.filter(x => x.width === m.width && x.height === m.height)) {
                        const hz = Math.round(x.refresh_rate / 1000);
                        if (!porHz[hz] || x.refresh_rate > porHz[hz]) porHz[hz] = x.refresh_rate;
                    }
                    if (porHz[Math.round(m.refresh_rate / 1000)]) porHz[Math.round(m.refresh_rate / 1000)] = m.refresh_rate;
                    const frec = Object.values(porHz).sort((a, b) => b - a).slice(0, 3).sort((a, b) => a - b);
                    r.push({ nombre: n, modelo: o.model || n, conectada: true, x: l.x, ancho: l.width, alto: l.height,
                             resoluciones: res, resolucion: m.width + "x" + m.height, frecuencias: frec, frecuencia: m.refresh_rate,
                             escala: l.scale, principal: principal === n, modos: o.modes });
                }
                let fin = r.reduce((s, o) => Math.max(s, o.x + o.ancho), 0);
                for (const n of enConfig) if (!json[n]) { r.push({ nombre: n, modelo: n, conectada: false, x: fin, ancho: 1920, alto: 1080, resoluciones: [], frecuencias: [], escala: 1, principal: false }); fin += 1920; }
                ventana.salidas = r;
                if (!ventana.salidaActual) ventana.salidaElegida = (r.find(s => s.conectada) || {}).nombre || "";
            }
        }
    }
    Timer { id: releerSalidas; interval: 700; onTriggered: leerSalidas.running = true }
    function ponerModo(res, frec) {
        const s = salidaActual;
        if (!s) return;
        res = res || s.resolucion;
        const [w, h] = res.split("x").map(Number);
        const candidatos = s.modos.filter(x => x.width === w && x.height === h);
        const m = candidatos.find(x => x.refresh_rate === frec) ?? candidatos.sort((a, b) => b.refresh_rate - a.refresh_rate)[0];
        if (!m) return;
        Estilo.niri(["salida", s.nombre, "modo", w + "x" + h + "@" + (m.refresh_rate / 1000).toFixed(3)]);
        releerSalidas.restart();
    }
    // Al soltar un monitor en el mapa: se ordenan por donde quedaron y se ponen uno al lado del otro.
    function reacomodar() {
        const cajas = [];
        for (const s of salidas) if (s.conectada) cajas.push(s);
        // la posicion arrastrada vive en el delegado; se aproxima con el orden visual actual
        const conX = cajas.map(s => ({ s: s, x: buscarCaja(s.nombre) }));
        conX.sort((a, b) => a.x - b.x);
        let x = 0;
        for (const c of conX) { Estilo.niri(["salida", c.s.nombre, "posicion", String(x), "0"]); x += c.s.ancho; }
        releerSalidas.restart();
    }
    function buscarCaja(nombre) {
        for (let i = 0; i < mapa.children.length; i++) {
            const h = mapa.children[i];
            if (h.modelData && h.modelData.nombre === nombre) return h.x;
        }
        return 0;
    }

    // ---- Liquid glass ----
    readonly property var vidrioV: Estilo.valor("vidrio")
    function ponerVidrio(clave, v) {
        const d = Object.assign({}, vidrioV);
        d[clave] = v;
        Estilo.poner("vidrio", d);
        Estilo.niri(["vidrio", JSON.stringify(d)]);
    }
    function alternarVidrio(v) {
        vidrio = v;
        ejecutar(["sh", "-c", v
            ? "cp '" + dirLniri + "/vidrio-activo.kdl' '" + dirLniri + "/vidrio.kdl'"
            : ": > '" + dirLniri + "/vidrio.kdl'"]);
    }

    // ---- Atajos ----
    property var atajos: ({})
    property string capturando: ""      // id del atajo que espera una combinacion nueva
    property string errorAtajo: ""
    Process {
        id: leerAtajos
        command: ["python3", Estilo.carpeta + "/menisco-niri.py", "atajos"]
        stdout: StdioCollector { onStreamFinished: { try { ventana.atajos = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: cambiarAtajo
        stdout: StdioCollector {
            onStreamFinished: {
                ventana.errorAtajo = text.trim().startsWith("error") ? text.trim().replace(/^error: /, "No se pudo: ") : "";
                leerAtajos.running = true;
            }
        }
    }
    // Tecla de Qt -> nombre que entiende niri.
    function nombreTecla(e) {
        const especiales = {
            [Qt.Key_Period]: "Period", [Qt.Key_Comma]: "Comma", [Qt.Key_Slash]: "Slash", [Qt.Key_Space]: "Space",
            [Qt.Key_Return]: "Return", [Qt.Key_Tab]: "Tab", [Qt.Key_Minus]: "Minus", [Qt.Key_Equal]: "Equal",
            [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down",
            [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Delete]: "Delete", [Qt.Key_Home]: "Home", [Qt.Key_End]: "End",
            [Qt.Key_Print]: "Print", [Qt.Key_Semicolon]: "Semicolon", [Qt.Key_Apostrophe]: "Apostrophe"
        };
        if (e.key >= Qt.Key_A && e.key <= Qt.Key_Z) return String.fromCharCode(e.key);
        if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9) return String.fromCharCode(e.key);
        if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F12) return "F" + (e.key - Qt.Key_F1 + 1);
        return especiales[e.key] || "";
    }
    function capturar(e) {
        if (e.key === Qt.Key_Escape) { capturando = ""; return; }
        const tecla = nombreTecla(e);
        if (!tecla) return;                   // solo un modificador, todavia
        const mods = [];
        if (e.modifiers & Qt.MetaModifier) mods.push("Mod");
        if (e.modifiers & Qt.ControlModifier) mods.push("Ctrl");
        if (e.modifiers & Qt.AltModifier) mods.push("Alt");
        if (e.modifiers & Qt.ShiftModifier) mods.push("Shift");
        if (!mods.length && !tecla.startsWith("F")) { errorAtajo = "Use al menos una tecla como Super, Ctrl o Alt."; return; }
        cambiarAtajo.command = ["python3", Estilo.carpeta + "/menisco-niri.py", "atajo", capturando, mods.concat([tecla]).join("+")];
        cambiarAtajo.running = true;
        capturando = "";
    }

    // Entrada escalonada de los bloques de Inicio al abrir la ventana.
    Entrada { objetivo: marcoHero; orden: 0 }
    Entrada { objetivo: cabFondos; orden: 1 }
    Entrada { objetivo: fondos; orden: 2 }
    Entrada { objetivo: cabOpciones; orden: 3 }
    Entrada { objetivo: rapidas; orden: 4 }

    // Modo cafe: mientras este proceso viva, el sistema no se suspende.
    Process {
        running: ventana.cafe
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=Dots", "--why=Modo café", "sleep", "infinity"]
    }

    Rectangle {
        id: panel
        width: 760
        height: 556
        anchors.centerIn: parent
        radius: 16
        color: Estilo.fondo
        border.color: "#3a3a3a"
        border.width: 1
        clip: true

        // Entra creciendo desde 0.9 y subiendo 20 px, con rebote; sale encogiendo un poco.
        opacity: ventana.abierta ? 1 : 0
        scale: ventana.abierta ? 1 : 0.9
        transform: Translate { y: ventana.abierta ? 0 : 20; Behavior on y { NumberAnimation { duration: Estilo.t(ventana.abierta ? 560 : 180); easing.type: ventana.abierta ? Easing.BezierSpline : Easing.InCubic; easing.bezierCurve: Estilo.curvaRebote } } }
        Behavior on opacity { NumberAnimation { duration: Estilo.t(ventana.abierta ? 260 : 160); easing.type: ventana.abierta ? Easing.OutCubic : Easing.InCubic } }
        Behavior on scale { NumberAnimation { duration: Estilo.t(ventana.abierta ? 580 : 180); easing.type: ventana.abierta ? Easing.BezierSpline : Easing.InCubic; easing.bezierCurve: Estilo.curvaRebote } }

        focus: ventana.abierta
        Keys.onPressed: e => {
            if (ventana.capturando) { ventana.capturar(e); e.accepted = true; }
            else if (e.key === Qt.Key_Escape) { if (dialogoGota.abierto) dialogoGota.cerrar(); else ventana.cerrar(); e.accepted = true; }
        }

        // Barra lateral
        Rectangle {
            id: lateral
            width: 170
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 1 }
            radius: 15
            color: "#1c1c1c"
            Rectangle { width: 16; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } color: parent.color }

            readonly property var secciones: [
                { id: "inicio", texto: "Inicio", icono: "home" },
                { id: "apariencia", texto: "Apariencia", icono: "palette" },
                { id: "pantallas", texto: "Pantallas", icono: "desktop_windows" },
                { id: "isla", texto: "Isla", icono: "pill" },
                { id: "asistente", texto: "Asistente", icono: "smart_toy" },
                { id: "barra", texto: "Barra lateral", icono: "view_sidebar" },
                { id: "vidrio", texto: "Liquid glass", icono: "water_drop" },
                { id: "atajos", texto: "Atajos", icono: "keyboard" }
            ]
            readonly property int indice: secciones.findIndex(s => s.id === ventana.seccion)

            Text {
                id: tituloLateral
                x: 22; y: 12
                text: "Menisco"; color: "#888"
                font { family: Estilo.letra; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.06 }
                bottomPadding: 8
            }

            // Una sola pastilla de seleccion que se desliza entre secciones.
            Rectangle {
                x: 12
                y: listaLateral.y + lateral.indice * 36
                width: lateral.width - 24
                height: 34
                radius: 9
                color: "#333"
                Behavior on y { NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
            }

            Column {
                id: listaLateral
                x: 12
                y: tituloLateral.y + tituloLateral.height
                width: lateral.width - 24
                spacing: 2

                Repeater {
                    model: lateral.secciones
                    delegate: Rectangle {
                        id: fila
                        required property var modelData
                        readonly property bool elegida: ventana.seccion === modelData.id
                        // De 0 a 1: rellena el icono de forma progresiva.
                        property real relleno: elegida ? 1 : 0
                        Behavior on relleno { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.OutCubic } }

                        width: parent.width
                        height: 34
                        radius: 9
                        color: !elegida && zona.containsMouse ? "#262626" : "#00262626"
                        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }

                        Text {
                            id: iconoLateral
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                            text: modelData.icono
                            color: fila.elegida ? "#fff" : "#bbb"
                            Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                            font { family: "Material Symbols Rounded"; pixelSize: 19 }
                            font.variableAxes: { "FILL": fila.relleno, "wght": 500, "opsz": 20 }
                            renderType: Text.NativeRendering   // sin esto Qt ignora los ejes de la fuente variable
                            scale: zona.pressed ? 0.85 : 1
                            Behavior on scale { NumberAnimation { duration: Estilo.t(zona.pressed ? 80 : 340); easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.5) } }
                        }
                        Text {
                            anchors { verticalCenter: parent.verticalCenter; left: iconoLateral.right; leftMargin: 10 }
                            text: modelData.texto
                            color: fila.elegida ? "#fff" : "#bbb"
                            Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                            font { family: Estilo.letra; pixelSize: 13; weight: Font.Normal; letterSpacing: -0.08 }
                        }
                        MouseArea { id: zona; anchors.fill: parent; hoverEnabled: true; onClicked: ventana.seccion = modelData.id }
                    }
                }
            }
        }

        // Contenido
        Item {
            id: contenido
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right; left: lateral.right; margins: 16 }

            // ---------------- Apariencia ----------------
            Pagina {
                anchors.fill: parent
                activa: ventana.seccion === "apariencia"
                Desplazable {
                    Encabezado { text: "Ventanas" }
                    Grupo {
                        Deslizador {
                            titulo: "Esquinas"; sub: "Radio de las ventanas"; desde: 0; hasta: 24; unidad: " px"
                            valor: ventana.esquinas
                            onSoltado: v => { ventana.esquinas = v; Estilo.poner("esquinas", v); Estilo.niri(["esquinas", v]); }
                        }
                        Deslizador {
                            titulo: "Espacio entre ventanas"; desde: 0; hasta: 32; unidad: " px"
                            valor: Estilo.valor("espacio")
                            onSoltado: v => { Estilo.poner("espacio", v); Estilo.niri(["espacio", v]); }
                        }
                        Deslizador {
                            titulo: "Borde de la ventana activa"; sub: "Opacidad del filo blanco"; desde: 0; hasta: 100; unidad: " %"
                            valor: Estilo.valor("borde")
                            onSoltado: v => { Estilo.poner("borde", v); Estilo.niri(["borde", v]); }
                        }
                    }
                    Encabezado { text: "Movimiento" }
                    Grupo {
                        Segmentos {
                            titulo: "Velocidad de animaciones"; opciones: ["Lenta", "Normal", "Rápida"]; claves: ["lenta", "normal", "rapida"]
                            elegida: Estilo.valor("velocidad"); onElegir: c => Estilo.poner("velocidad", c)
                        }
                        Segmentos {
                            titulo: "Rebote"; opciones: ["Nada", "Suave", "Mucho"]; claves: ["nada", "suave", "mucho"]
                            elegida: Estilo.valor("rebote"); onElegir: c => Estilo.poner("rebote", c)
                        }
                    }
                    Encabezado { text: "Isla y paneles" }
                    Grupo {
                        Segmentos {
                            titulo: "Color de fondo"; sub: "Isla, lanzador, ajustes, volumen"; opciones: ["Gris", "Negro"]; claves: [false, true]
                            elegida: Estilo.valor("fondoNegro"); onElegir: c => Estilo.poner("fondoNegro", c)
                        }
                        Segmentos {
                            titulo: "Letra"; opciones: ["SF Pro", "Inter"]; claves: ["SF Pro", "Inter"]
                            elegida: Estilo.valor("letra"); onElegir: c => Estilo.poner("letra", c)
                        }
                    }
                }
            }

            // ---------------- Pantallas ----------------
            Pagina {
                anchors.fill: parent
                activa: ventana.seccion === "pantallas"
                onActivaChanged: if (activa) leerSalidas.running = true
                Desplazable {
                    Encabezado { text: "Disposición" }
                    Rectangle {
                        id: mapa
                        width: parent.width; height: 150; radius: 12; color: "#1b1b1b"
                        // Escala del mapa: el conjunto de monitores cabe con margen.
                        readonly property real anchoTotal: Math.max(1, ventana.salidas.reduce((s, o) => s + o.ancho, 0))
                        readonly property real k: Math.min((width - 60) / anchoTotal, 84 / 1080)
                        Repeater {
                            model: ventana.salidas
                            delegate: Rectangle {
                                id: caja
                                required property var modelData
                                required property int index
                                width: modelData.ancho * mapa.k; height: modelData.alto * mapa.k
                                y: (mapa.height - height) / 2 - 6
                                x: 30 + modelData.x * mapa.k
                                radius: 8
                                color: modelData.conectada ? "#2e2e2e" : "transparent"
                                border.color: modelData.nombre === ventana.salidaElegida ? "#ffffff" : "#555"
                                border.width: modelData.nombre === ventana.salidaElegida ? 2 : 1
                                opacity: modelData.conectada ? 1 : 0.55
                                Behavior on x { enabled: !arrastre.active; NumberAnimation { duration: Estilo.t(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                                Column {
                                    anchors.centerIn: parent
                                    Texto { anchors.horizontalCenter: parent.horizontalCenter; text: caja.modelData.modelo; font.weight: Font.DemiBold }
                                    Texto { anchors.horizontalCenter: parent.horizontalCenter; text: caja.modelData.nombre + (caja.modelData.conectada ? "" : " · desconectado"); color: "#888"; font.pixelSize: 11 }
                                }
                                TapHandler { onTapped: if (caja.modelData.conectada) ventana.salidaElegida = caja.modelData.nombre }
                                DragHandler {
                                    id: arrastre
                                    enabled: caja.modelData.conectada
                                    yAxis.enabled: false
                                    onActiveChanged: if (!active) ventana.reacomodar()
                                }
                            }
                        }
                        Texto { x: 12; anchors { bottom: parent.bottom; bottomMargin: 8 } text: "Arrastre los monitores para acomodarlos"; color: "#888"; font.pixelSize: 11 }
                    }
                    Encabezado { text: ventana.salidaActual ? ventana.salidaActual.modelo : "" }
                    Grupo {
                        visible: !!ventana.salidaActual
                        Segmentos {
                            titulo: "Resolución"
                            opciones: ventana.salidaActual ? ventana.salidaActual.resoluciones.map(r => r.replace("x", " × ")) : []
                            claves: ventana.salidaActual ? ventana.salidaActual.resoluciones : []
                            elegida: ventana.salidaActual ? ventana.salidaActual.resolucion : ""
                            onElegir: c => ventana.ponerModo(c, null)
                        }
                        Segmentos {
                            titulo: "Frecuencia"
                            opciones: ventana.salidaActual ? ventana.salidaActual.frecuencias.map(f => Math.round(f / 1000) + " Hz") : []
                            claves: ventana.salidaActual ? ventana.salidaActual.frecuencias : []
                            elegida: ventana.salidaActual ? ventana.salidaActual.frecuencia : 0
                            onElegir: c => ventana.ponerModo(null, c)
                        }
                        Segmentos {
                            titulo: "Escala"; opciones: ["100 %", "125 %", "150 %"]; claves: [1, 1.25, 1.5]
                            elegida: ventana.salidaActual ? ventana.salidaActual.escala : 1
                            onElegir: c => { Estilo.niri(["salida", ventana.salidaElegida, "escala", String(c)]); releerSalidas.restart(); }
                        }
                        Interruptor {
                            titulo: "Monitor principal"; sub: "Aquí aparecen la isla y el lanzador primero"
                            encendido: ventana.salidaActual ? ventana.salidaActual.principal : false
                            onCambiar: v => { if (v) { Estilo.niri(["salida", ventana.salidaElegida, "principal"]); releerSalidas.restart(); } }
                        }
                    }
                }
            }

            // ---------------- Isla ----------------
            Pagina {
                anchors.fill: parent
                activa: ventana.seccion === "isla"
                Desplazable {

                    Encabezado { text: "Vista previa" }
                    Rectangle {
                        width: parent.width; height: 70; radius: 12; color: "#3a3f4a"
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 300; height: 38; color: Estilo.fondo
                            topLeftRadius: 0; topRightRadius: 0; bottomLeftRadius: 18; bottomRightRadius: 18
                            Rectangle {
                                visible: Estilo.valor("islaAsistente")
                                x: 14; anchors.verticalCenter: parent.verticalCenter
                                width: 24; height: 24; radius: 12; color: Estilo.valor("fondoNegro") ? "#2c2c2e" : "#0b0b0c"
                                Row { anchors.centerIn: parent; spacing: 4; Repeater { model: 2; Rectangle { width: 3; height: 8; radius: 2; color: "#fff" } } }
                            }
                            Texto {
                                anchors.centerIn: parent
                                text: Qt.formatTime(reloj.date, (Estilo.valor("reloj12") ? "h:mm" : "H:mm") + (Estilo.valor("segundos") ? ":ss" : "") + (Estilo.valor("reloj12") ? " AP" : ""))
                                font.pixelSize: 17; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                            }
                            Row {
                                visible: Estilo.valor("islaVisualizador")
                                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                spacing: 3
                                Repeater { model: [6, 11, 16, 11, 6]; Rectangle { required property int modelData; width: 3; height: modelData; radius: 1.5; color: "#fff"; anchors.verticalCenter: parent.verticalCenter } }
                            }
                        }
                    }
                    Encabezado { text: "Qué muestra" }
                    Grupo {
                        Interruptor { titulo: "Asistente"; sub: "A la izquierda"; encendido: Estilo.valor("islaAsistente"); onCambiar: v => Estilo.poner("islaAsistente", v) }
                        Interruptor { titulo: "Visualizador de audio"; sub: "A la derecha"; encendido: Estilo.valor("islaVisualizador"); onCambiar: v => Estilo.poner("islaVisualizador", v) }
                        Segmentos { titulo: "Reloj"; opciones: ["24 horas", "12 horas"]; claves: [false, true]; elegida: Estilo.valor("reloj12"); onElegir: c => Estilo.poner("reloj12", c) }
                        Interruptor { titulo: "Segundos en el reloj"; encendido: Estilo.valor("segundos"); onCambiar: v => Estilo.poner("segundos", v) }
                    }
                    Encabezado { text: "Al abrirse" }
                    Grupo {
                        Interruptor { titulo: "Abrir al pasar el cursor"; sub: "Si se apaga, solo se abre con un clic"; encendido: Estilo.valor("islaCursor"); onCambiar: v => Estilo.poner("islaCursor", v) }
                        Segmentos { titulo: "Espera antes de abrir"; opciones: ["Corta", "Normal", "Larga"]; claves: ["corta", "normal", "larga"]; elegida: Estilo.valor("islaEspera"); onElegir: c => Estilo.poner("islaEspera", c) }
                        Segmentos { titulo: "Pestaña al abrir"; opciones: ["Música", "Acciones", "Rendimiento", "La última"]; claves: ["musica", "acciones", "rendimiento", "ultima"]; elegida: Estilo.valor("islaPestana"); onElegir: c => Estilo.poner("islaPestana", c) }
                    }
                    Encabezado { text: "Pestaña Música" }
                    Grupo {
                        Interruptor { titulo: "Letra sincronizada"; sub: "Abajo, la línea que suena resaltada"; encendido: Estilo.valor("musicaLetra"); onCambiar: v => Estilo.poner("musicaLetra", v) }
                        Interruptor { titulo: "Buscar también en NetEase"; sub: "Si LRCLIB no tiene la canción (servicio de China)"; encendido: Estilo.valor("letraNetease"); onCambiar: v => Estilo.poner("letraNetease", v) }
                        Interruptor { titulo: "Color de la carátula"; sub: "La isla se tiñe con el disco que suena"; encendido: Estilo.valor("musicaTinte"); onCambiar: v => Estilo.poner("musicaTinte", v) }
                        Interruptor { titulo: "Volumen y salida de audio"; sub: "Abajo a la derecha de los controles"; encendido: Estilo.valor("musicaAudio"); onCambiar: v => Estilo.poner("musicaAudio", v) }
                        Interruptor { titulo: "Esconder el visualizador"; sub: "Las ondas junto al reloj, mientras se ve Música"; encendido: Estilo.valor("ocultarVisualizador"); onCambiar: v => Estilo.poner("ocultarVisualizador", v) }
                    }
                    Encabezado { text: "Avisos" }
                    Grupo {
                        Interruptor { titulo: "Canción nueva"; sub: "Carátula y título unos segundos"; encendido: Estilo.valor("avisoMusica"); onCambiar: v => Estilo.poner("avisoMusica", v) }
                        Interruptor { titulo: "Audífonos y bocinas"; encendido: Estilo.valor("avisoBt"); onCambiar: v => Estilo.poner("avisoBt", v) }
                        Interruptor { titulo: "Capturas de pantalla"; encendido: Estilo.valor("avisoCaptura"); onCambiar: v => Estilo.poner("avisoCaptura", v) }
                        Interruptor { titulo: "Temperatura alta"; encendido: Estilo.valor("avisoTemp"); onCambiar: v => Estilo.poner("avisoTemp", v) }
                        Deslizador { titulo: "Avisar desde"; desde: 60; hasta: 95; unidad: " °C"; valor: Estilo.valor("avisoGrados"); onSoltado: v => Estilo.poner("avisoGrados", v) }
                        Segmentos { titulo: "Duración de los avisos"; opciones: ["Corta", "Normal", "Larga"]; claves: ["corta", "normal", "larga"]; elegida: Estilo.valor("avisoDuracion"); onElegir: c => Estilo.poner("avisoDuracion", c) }
                    }
                }
            }

            // ---------------- Asistente ----------------
            Pagina {
                id: paginaBot
                anchors.fill: parent
                activa: ventana.seccion === "asistente"
                property string prueba: "feliz"     // emocion de la vista previa (solo se ve aqui)
                Desplazable {
                    Encabezado { text: "Tus gotas"; topPadding: 14 }
                    // Gotas guardadas: un clic elige la de la isla; otro clic sobre la elegida la edita.
                    Row {
                        spacing: 14
                        Repeater {
                            model: Estilo.gotas
                            delegate: Column {
                                id: miniGota
                                required property var modelData
                                required property int index
                                readonly property bool elegida: index === Estilo.gotaActiva
                                spacing: 6
                                Rectangle {
                                    width: 56; height: 56; radius: 17
                                    color: miniGota.elegida ? "#2e2e2e" : zonaG.containsMouse ? "#262626" : "#00262626"
                                    border.width: 2; border.color: miniGota.elegida ? "#ffffff" : "#00ffffff"
                                    Behavior on color { ColorAnimation { duration: Estilo.t(160) } }
                                    Behavior on border.color { ColorAnimation { duration: Estilo.t(200) } }
                                    scale: zonaG.pressed ? 0.92 : 1
                                    Behavior on scale { NumberAnimation { duration: Estilo.t(zonaG.pressed ? 90 : 360); easing.type: zonaG.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(1.8) } }
                                    FormaGota { anchors.centerIn: parent; width: 38; height: 38; forma: miniGota.modelData.forma; color: miniGota.modelData.color }
                                    MouseArea {
                                        id: zonaG; anchors.fill: parent; hoverEnabled: true
                                        onClicked: miniGota.elegida ? dialogoGota.abrir(miniGota.index) : Estilo.poner("gotaActiva", miniGota.index)
                                    }
                                }
                                Texto { anchors.horizontalCenter: parent.horizontalCenter; text: miniGota.modelData.nombre; font.pixelSize: 11; color: miniGota.elegida ? "#fff" : "#999" }
                            }
                        }
                        Column {
                            spacing: 6
                            Rectangle {
                                width: 56; height: 56; radius: 17
                                color: zonaNueva.containsMouse ? "#262626" : "#00262626"
                                border.width: 1.5; border.color: "#555"
                                Behavior on color { ColorAnimation { duration: Estilo.t(160) } }
                                scale: zonaNueva.pressed ? 0.92 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaNueva.pressed ? 90 : 360); easing.type: zonaNueva.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(1.8) } }
                                Simbolo { anchors.centerIn: parent; text: "add"; color: "#aaa"; font.pixelSize: 24 }
                                MouseArea { id: zonaNueva; anchors.fill: parent; hoverEnabled: true; onClicked: dialogoGota.abrir(-1) }
                            }
                            Texto { anchors.horizontalCenter: parent.horizontalCenter; text: "Nueva"; font.pixelSize: 11; color: "#999" }
                        }
                    }
                    Item { width: parent.width; height: 16 }
                    Rectangle {
                        width: parent.width; height: 170; radius: 16
                        color: "#070a12"; border.width: 1; border.color: "#2a4a7a"
                        Asistente {
                            width: 90; height: 90
                            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 22 }
                            emocion: paginaBot.prueba
                            ritmo: ({ tranquilo: 1.8, normal: 1, inquieto: 0.5 })[Estilo.valor("personalidad")] ?? 1
                            fondoNegro: true
                        }
                        Texto {
                            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
                            text: Estilo.gota.nombre; font.pixelSize: 15; font.weight: Font.DemiBold; color: "#fff"
                        }
                    }
                    // Probar emociones
                    Item {
                        width: parent.width; height: 40
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Repeater {
                                model: [["Normal", "normal"], ["Feliz", "feliz"], ["Escucha", "escucha"], ["Pensar", "pensar"], ["Emoción", "emocion"], ["Confuso", "confuso"]]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool elegida: paginaBot.prueba === modelData[1]
                                    width: et.implicitWidth + 20; height: 26; radius: 8
                                    color: elegida ? "#ffffff" : "#2e2e2e"
                                    Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                                    Texto { id: et; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: 12; color: parent.elegida ? "#111" : "#ccc" }
                                    MouseArea { anchors.fill: parent; onClicked: paginaBot.prueba = modelData[1] }
                                }
                            }
                        }
                    }
                    Encabezado { text: "Identidad" }
                    Grupo {
                        Campo {
                            titulo: "Nombre"; sub: "Sale en el botón de la isla"; texto: Estilo.gota.nombre
                            onGuardar: t => Estilo.guardarGota(Estilo.gotaActiva, Object.assign({}, Estilo.gota, { nombre: t }))
                        }
                        Campo { titulo: "Subtítulo"; texto: Estilo.valor("botSub"); onGuardar: t => Estilo.poner("botSub", t) }
                    }
                    Encabezado { text: "Carácter" }
                    Grupo {
                        Segmentos {
                            titulo: "Personalidad"; sub: "Qué tan seguido mira y parpadea"
                            opciones: ["Tranquilo", "Normal", "Inquieto"]; claves: ["tranquilo", "normal", "inquieto"]
                            elegida: Estilo.valor("personalidad"); onElegir: c => Estilo.poner("personalidad", c)
                        }
                        Interruptor { titulo: "Reaccionar a la música"; sub: "Se pone feliz cuando suena algo"; encendido: Estilo.valor("reaccionMusica"); onCambiar: v => Estilo.poner("reaccionMusica", v) }
                    }
                    Encabezado { text: "Botón de la isla" }
                    Grupo {
                        Interruptor { titulo: "Luz que gira"; sub: "Apagada, la luz queda quieta"; encendido: Estilo.valor("botLuz"); onCambiar: v => Estilo.poner("botLuz", v) }
                        Interruptor { titulo: "Chispas"; encendido: Estilo.valor("botChispas"); onCambiar: v => Estilo.poner("botChispas", v) }
                        Interruptor { titulo: "Mostrar en Acciones y Rendimiento"; encendido: Estilo.valor("botEnPaginas"); onCambiar: v => Estilo.poner("botEnPaginas", v) }
                    }
                    Encabezado { text: "Animaciones" }
                    Grupo {
                        Interruptor { titulo: "Succionarse al abrir el lanzador"; encendido: Estilo.valor("succion"); onCambiar: v => Estilo.poner("succion", v) }
                    }
                }
            }

            // ---------------- Barra lateral ----------------
            Pagina {
                anchors.fill: parent
                activa: ventana.seccion === "barra"
                Desplazable {
                    Encabezado { text: "Posición" }
                    Grupo {
                        Segmentos { titulo: "Lado"; opciones: ["Izquierda", "Derecha"]; claves: ["izquierda", "derecha"]; elegida: Estilo.barra.lado; onElegir: c => Estilo.ponerBarra("lado", c) }
                        Segmentos { titulo: "Altura"; opciones: ["Arriba", "Centro", "Abajo"]; claves: ["arriba", "centro", "abajo"]; elegida: Estilo.barra.altura; onElegir: c => Estilo.ponerBarra("altura", c) }
                        Deslizador { titulo: "Ancho"; desde: 300; hasta: 420; unidad: " px"; valor: Estilo.barra.ancho; onSoltado: v => Estilo.ponerBarra("ancho", v) }
                    }
                    Encabezado { text: "Cómo se abre" }
                    Grupo {
                        Interruptor { titulo: "Botón de destello"; sub: "Arriba, junto a la isla"; encendido: Estilo.barra.boton; onCambiar: v => Estilo.ponerBarra("boton", v) }
                        Interruptor { titulo: "Borde de la pantalla"; sub: "Al llevar el cursor al borde y esperar un instante"; encendido: Estilo.barra.borde; onCambiar: v => Estilo.ponerBarra("borde", v) }
                        Interruptor { titulo: "Cerrar al hacer clic fuera"; encendido: Estilo.barra.clicFuera; onCambiar: v => Estilo.ponerBarra("clicFuera", v) }
                    }
                    Encabezado { text: "Secciones" }
                    EditorSecciones { width: parent.width }
                    Encabezado { text: "Botones rápidos" }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: [["red", "lan", "Red"], ["bt", "bluetooth", "Bluetooth"], ["dnd", "dark_mode", "No molestar"], ["cafe", "coffee", "Modo café"],
                                    ["captura", "screenshot_region", "Captura"], ["isla", "pill", "Isla"], ["vidrio", "water_drop", "Liquid glass"], ["grabar", "videocam", "Grabar pantalla"]]
                            delegate: Rectangle {
                                id: chip
                                required property var modelData
                                readonly property bool elegido: Estilo.barra.rapidos.includes(modelData[0])
                                width: filaChip.implicitWidth + 20; height: 30; radius: 10
                                color: elegido ? "#ffffff" : "#1b1b1b"
                                Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                                scale: zonaChip.pressed ? 0.94 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaChip.pressed ? 80 : 360); easing.type: zonaChip.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                Row {
                                    id: filaChip
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: chip.modelData[1]; color: chip.elegido ? "#111" : "#aaa"
                                        font { family: "Material Symbols Rounded"; pixelSize: 16 }
                                        font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 20 }
                                        renderType: Text.NativeRendering
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Texto { text: chip.modelData[2]; color: chip.elegido ? "#111" : "#aaa"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea {
                                    id: zonaChip
                                    anchors.fill: parent
                                    // Se respeta el orden de la lista de arriba, no el del clic.
                                    onClicked: {
                                        const orden = ["red", "bt", "dnd", "cafe", "captura", "isla", "vidrio", "grabar"];
                                        const r = chip.elegido ? Estilo.barra.rapidos.filter(x => x !== chip.modelData[0])
                                                               : Estilo.barra.rapidos.concat([chip.modelData[0]]);
                                        Estilo.ponerBarra("rapidos", orden.filter(x => r.includes(x)));
                                    }
                                }
                            }
                        }
                    }
                    Encabezado { text: "Calendario" }
                    Grupo {
                        Segmentos { titulo: "La semana empieza en"; opciones: ["Lunes", "Domingo"]; claves: [true, false]; elegida: Estilo.barra.semanaLunes; onElegir: c => Estilo.ponerBarra("semanaLunes", c) }
                    }
                }
            }

            // ---------------- Liquid glass ----------------
            Pagina {
                anchors.fill: parent
                activa: ventana.seccion === "vidrio"
                Desplazable {
                    Encabezado { text: "Vista previa" }
                    ClippingRectangle {
                        width: parent.width; height: 90; radius: 12; color: "#2b3a4a"
                        Row {
                            rotation: -30; anchors.centerIn: parent
                            Repeater { model: 30; Rectangle { required property int index; width: 14; height: 400; color: index % 2 ? "#3d5468" : "#2b3a4a" } }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 220; height: 50; radius: 22
                            color: Qt.rgba(1, 1, 1, 0.04 + 0.08 * ventana.vidrioV.desenfoque / 100)
                            border.width: 1 + 2 * ventana.vidrioV.brillo / 100
                            border.color: Qt.rgba(1, 1, 1, 0.2 + 0.5 * ventana.vidrioV.brillo / 100)
                            Rectangle {   // filo de color: la aberracion cromatica
                                anchors.fill: parent; anchors.margins: -2; radius: 24; color: "transparent"
                                border.width: 2; border.color: Qt.rgba(0.6, 0.5, 1, 0.45 * ventana.vidrioV.aberracion / 100)
                            }
                        }
                    }
                    Encabezado { text: "Efecto" }
                    Grupo {
                        Interruptor {
                            titulo: "Liquid glass"; sub: "Solo en la sesión Lniri"; encendido: ventana.vidrio
                            onCambiar: v => ventana.alternarVidrio(v)
                        }
                        Deslizador { titulo: "Refracción"; sub: "Cuánto deforma el borde"; desde: 0; hasta: 100; unidad: " %"; valor: ventana.vidrioV.refraccion; onSoltado: v => ventana.ponerVidrio("refraccion", v) }
                        Deslizador { titulo: "Aberración cromática"; sub: "Separación de colores"; desde: 0; hasta: 100; unidad: " %"; valor: ventana.vidrioV.aberracion; onSoltado: v => ventana.ponerVidrio("aberracion", v) }
                        Deslizador { titulo: "Desenfoque"; desde: 0; hasta: 100; unidad: " %"; valor: ventana.vidrioV.desenfoque; onSoltado: v => ventana.ponerVidrio("desenfoque", v) }
                        Deslizador { titulo: "Brillo del canto"; desde: 0; hasta: 100; unidad: " %"; valor: ventana.vidrioV.brillo; onSoltado: v => ventana.ponerVidrio("brillo", v) }
                    }
                    Encabezado { text: "Dónde se aplica" }
                    Grupo {
                        Interruptor { titulo: "Dock"; encendido: ventana.vidrioV.dock; onCambiar: v => ventana.ponerVidrio("dock", v) }
                        Interruptor { titulo: "Ventanas transparentes"; sub: "Terminales con transparencia"; encendido: ventana.vidrioV.ventanas; onCambiar: v => ventana.ponerVidrio("ventanas", v) }
                        Interruptor { titulo: "Notificaciones"; sub: "Hokum reserva una franja alta: el vidrio la cubre entera"; encendido: ventana.vidrioV.notificaciones; onCambiar: v => ventana.ponerVidrio("notificaciones", v) }
                    }
                }
            }

            // ---------------- Atajos ----------------
            Pagina {
                anchors.fill: parent
                activa: ventana.seccion === "atajos"
                onActivaChanged: if (activa) leerAtajos.running = true
                Desplazable {
                    Encabezado { text: "Menisco" }
                    Grupo {
                        Repeater {
                            model: [["lanzador", "Lanzador"], ["ajustes", "Ajustes"], ["captura", "Captura de zona"], ["bloquear", "Bloquear"]]
                            delegate: FilaAtajo { required property var modelData; clave: modelData[0]; titulo: modelData[1] }
                        }
                    }
                    Encabezado { text: "Ventanas" }
                    Grupo {
                        Repeater {
                            model: [["terminal", "Terminal"], ["cerrar", "Cerrar ventana"], ["vista", "Vista general"], ["maximizar", "Maximizar"]]
                            delegate: FilaAtajo { required property var modelData; clave: modelData[0]; titulo: modelData[1] }
                        }
                    }
                    Texto {
                        topPadding: 10
                        width: parent.width; wrapMode: Text.Wrap
                        text: ventana.errorAtajo || "Clic en un atajo y pulse la nueva combinación para cambiarlo. Escape cancela."
                        color: ventana.errorAtajo ? "#ff6b6b" : "#888"; font.pixelSize: 11
                    }
                }
            }

            Pagina {
                anchors.fill: parent
                activa: ventana.seccion === "inicio"

                Column {
                    anchors.fill: parent
                    spacing: 0

                    // Hero: fondo actual con la isla en miniatura encima
                    Rectangle {
                        id: marcoHero
                        width: parent.width
                        height: 220
                        radius: 12
                        color: "#2e2e2e"
                        clip: true

                        // Debajo queda el fondo anterior; el nuevo aparece encima con un fundido
                        // y un leve acercamiento hacia atras (de 1.06 a 1).
                        property string rutaVieja: ""
                        Redondeada {
                            anchors.fill: parent
                            radio: 12
                            ruta: marcoHero.rutaVieja
                            ancho: 1000
                        }
                        Redondeada {
                            id: hero
                            anchors.fill: parent
                            radio: 12
                            ruta: ventana.fondoActual
                            ancho: 1000
                            opacity: 0
                            onListoChanged: if (listo) llegada.restart()
                        }
                        ParallelAnimation {
                            id: llegada
                            NumberAnimation { target: hero; property: "opacity"; from: 0; to: 1; duration: Estilo.t(420); easing.type: Easing.OutCubic }
                            NumberAnimation { target: hero; property: "scale"; from: 1.06; to: 1; duration: Estilo.t(700); easing.type: Easing.BezierSpline; easing.bezierCurve: ventana.curvaIos }
                            onFinished: marcoHero.rutaVieja = ventana.fondoActual
                        }

                        Rectangle {
                            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                            width: 130; height: 18
                            radius: 9
                            color: Estilo.fondo
                            Rectangle { width: parent.width; height: 9; color: parent.color }
                            Text {
                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                                text: Qt.formatTime(reloj.date, "h:mm")
                                color: "#fff"
                                font { family: Estilo.letra; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.06 }
                                renderType: Text.NativeRendering
                            }
                        }

                        Column {
                            anchors { left: parent.left; bottom: parent.bottom; margins: 14 }
                            TextoCambiante {
                                text: ventana.fondoActual ? ventana.fondoActual.split("/").pop().replace(/\.[^.]+$/, "") : "Sin fondo"
                                color: "#fff"
                                font { family: Estilo.letra; pixelSize: 15; weight: Font.DemiBold; letterSpacing: -0.23 }
                            }
                            TextoCambiante {
                                text: ventana.resolucion ? ventana.resolucion + " · actual" : ""
                                color: "#d0d0d0"
                                font { family: Estilo.letra; pixelSize: 11; weight: Font.Normal; letterSpacing: 0.06 }
                            }
                        }
                    }

                    // Selector de fondos
                    Item {
                        id: cabFondos
                        width: parent.width
                        height: 34
                        Text {
                            anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 8 }
                            text: "Fondos"; color: "#888"; font { family: Estilo.letra; pixelSize: 13; weight: Font.Bold; letterSpacing: -0.08 }
                        }
                        Text {
                            anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 8 }
                            text: "Abrir carpeta"; color: abrirZona.containsMouse ? "#fff" : "#888"
                            Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                            font { family: Estilo.letra; pixelSize: 12; weight: Font.Normal; letterSpacing: 0 }
                            MouseArea { id: abrirZona; anchors.fill: parent; hoverEnabled: true; onClicked: ventana.ejecutar(["xdg-open", ventana.carpetaFondos]) }
                        }
                    }

                    ListView {
                        id: fondos
                        width: parent.width
                        height: 66
                        orientation: ListView.Horizontal
                        spacing: 8
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        model: FolderListModel {
                            folder: "file://" + ventana.carpetaFondos
                            nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
                            showDirs: false
                        }

                        delegate: Item {
                            id: miniatura
                            required property string filePath
                            width: 104; height: 66
                            readonly property bool actual: filePath === ventana.fondoActual

                            // Anillo de seleccion: aparece cerrandose sobre la miniatura.
                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: "transparent"
                                border.color: "#fff"
                                border.width: 2
                                opacity: miniatura.actual ? 1 : 0
                                scale: miniatura.actual ? 1 : 1.08
                                Behavior on opacity { NumberAnimation { duration: Estilo.t(220); easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: Estilo.t(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                            }
                            Redondeada {
                                anchors { fill: parent; margins: 4 }
                                radio: 7
                                ruta: miniatura.filePath
                                ancho: 200
                                scale: zonaMini.pressed ? 0.94 : (zonaMini.containsMouse ? 1.04 : 1)
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaMini.pressed ? 90 : 320); easing.type: zonaMini.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(1.6) } }
                            }
                            MouseArea {
                                id: zonaMini
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    // Lo que se ve ahora queda debajo mientras entra el nuevo,
                                    // aunque se pulsen dos miniaturas seguidas.
                                    llegada.stop();
                                    marcoHero.rutaVieja = ventana.fondoActual;
                                    ventana.fondoActual = miniatura.filePath;
                                    ventana.ejecutar(["awww", "img", miniatura.filePath, "--transition-type", "grow", "--transition-fps", "144"]);
                                }
                            }
                        }

                        footer: Item {
                            width: 112; height: 66
                            Rectangle {
                                anchors { fill: parent; leftMargin: 8; topMargin: 4; bottomMargin: 4; rightMargin: 4 }
                                radius: 8
                                color: masZona.containsMouse ? "#262626" : "#1a1a1a"
                                Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                                scale: masZona.pressed ? 0.94 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(masZona.pressed ? 90 : 320); easing.type: masZona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(1.6) } }
                                Text { anchors.centerIn: parent; text: "+"; color: "#888"; font.pixelSize: 22 }
                                MouseArea { id: masZona; anchors.fill: parent; hoverEnabled: true; onClicked: ventana.ejecutar(["xdg-open", ventana.carpetaFondos]) }
                            }
                        }
                    }

                    Item {
                        id: cabOpciones
                        width: parent.width
                        height: 34
                        Text {
                            anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 8 }
                            text: "Opciones rápidas"; color: "#888"; font { family: Estilo.letra; pixelSize: 13; weight: Font.Bold; letterSpacing: -0.08 }
                        }
                    }

                    Grid {
                        id: rapidas
                        width: parent.width
                        columns: 3
                        spacing: 8
                        readonly property real anchoTarjeta: (width - spacing * 2) / 3

                        Tarjeta {
                            icono: "water_drop"; titulo: "Liquid glass"
                            activa: ventana.vidrio
                            detalle: activa ? "Activado" : "Apagado"
                            onPulsada: {
                                ventana.vidrio = !ventana.vidrio;
                                ventana.ejecutar(["sh", "-c", ventana.vidrio
                                    ? "cp '" + ventana.dirLniri + "/vidrio-activo.kdl' '" + ventana.dirLniri + "/vidrio.kdl'"
                                    : ": > '" + ventana.dirLniri + "/vidrio.kdl'"]);
                            }
                        }
                        Tarjeta {
                            icono: "dark_mode"; titulo: "No molestar"
                            activa: ventana.noMolestar
                            detalle: activa ? "Activado" : "Apagado"
                            onPulsada: Estilo.ponerNoMolestar(!ventana.noMolestar)
                        }
                        Tarjeta {
                            icono: "pill"; titulo: "Isla"
                            activa: ventana.raiz.islaVisible
                            detalle: activa ? "Visible" : "Oculta"
                            onPulsada: ventana.raiz.islaVisible = !ventana.raiz.islaVisible
                        }
                        Tarjeta {
                            readonly property var adaptador: Bluetooth.defaultAdapter
                            readonly property var conectado: {
                                const d = Bluetooth.devices.values.find(d => d.connected);
                                return d ? d.name : "";
                            }
                            icono: "bluetooth"; titulo: "Bluetooth"
                            activa: adaptador ? adaptador.enabled : false
                            detalle: !activa ? "Apagado" : (conectado || "Encendido")
                            onPulsada: Estilo.bluetooth(adaptador, !activa)
                        }
                        Tarjeta {
                            icono: "rounded_corner"; titulo: "Esquinas"
                            activa: false
                            detalle: ventana.esquinas + " px"
                            onPulsada: {
                                const pasos = [0, 8, 12, 20];
                                ventana.esquinas = pasos[(pasos.indexOf(ventana.esquinas) + 1) % pasos.length];
                                Estilo.poner("esquinas", ventana.esquinas);
                                Estilo.niri(["esquinas", ventana.esquinas]);
                            }
                        }
                        Tarjeta {
                            icono: "coffee"; titulo: "Modo café"
                            activa: ventana.cafe
                            detalle: activa ? "Activado" : "Apagado"
                            onPulsada: ventana.cafe = !ventana.cafe
                        }
                    }
                }
            }
        }

        // ---------------- Nueva gota / editar gota ----------------
        // Tapa el panel con un velo; la tarjeta entra creciendo con rebote.
        Item {
            id: dialogoGota
            anchors.fill: parent
            property bool abierto: false
            property int indice: -1                  // -1 = nueva
            property string forma: "esfera"
            property string color: "#a26bff"
            property bool cambia: true
            readonly property var colores: ["#0b0b0c", "#94653a", "#ff3b30", "#ff6a00", "#ff9f0a", "#00c96f",
                                             "#14b8a6", "#1186ff", "#a26bff", "#ff2d92", "#8e8e93"]
            function abrir(i) {
                const g = i >= 0 ? Estilo.gotas[i] : { nombre: "", forma: "esfera", color: "#a26bff", cambia: true };
                indice = i; forma = g.forma; color = g.color; cambia = g.cambia;
                nombreGota.text = g.nombre;
                abierto = true;
                nombreGota.forceActiveFocus();
            }
            function cerrar() { abierto = false; panel.forceActiveFocus(); }
            function guardar() {
                Estilo.guardarGota(indice, { nombre: nombreGota.text.trim() || "Gota", forma: forma, color: color, cambia: cambia });
                cerrar();
            }

            visible: velo.opacity > 0.01
            Rectangle {
                id: velo
                anchors.fill: parent; radius: panel.radius
                color: "#99000000"
                opacity: dialogoGota.abierto ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Estilo.t(dialogoGota.abierto ? 220 : 160) } }
                MouseArea { anchors.fill: parent; onClicked: dialogoGota.cerrar() }
            }
            Rectangle {
                id: tarjetaGota
                width: 420; height: columnaGota.implicitHeight
                anchors.centerIn: parent
                radius: 22; color: "#262628"; border.width: 1; border.color: "#353537"
                opacity: dialogoGota.abierto ? 1 : 0
                scale: dialogoGota.abierto ? 1 : 0.9
                Behavior on opacity { NumberAnimation { duration: Estilo.t(dialogoGota.abierto ? 220 : 140) } }
                Behavior on scale { NumberAnimation { duration: Estilo.t(dialogoGota.abierto ? 520 : 160); easing.type: dialogoGota.abierto ? Easing.BezierSpline : Easing.InCubic; easing.bezierCurve: Estilo.curvaRebote } }
                MouseArea { anchors.fill: parent }   // que un clic en la tarjeta no la cierre

                Column {
                    id: columnaGota
                    width: parent.width
                    Item {
                        width: parent.width; height: 50
                        Texto { x: 20; anchors.verticalCenter: parent.verticalCenter; text: dialogoGota.indice < 0 ? "Nueva gota" : "Editar gota"; font.pixelSize: 15; font.weight: Font.DemiBold; color: "#fff" }
                        Simbolo {
                            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            text: "close"; color: "#999"; font.pixelSize: 20
                            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: dialogoGota.cerrar() }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#353537" }
                    }
                    Item {
                        width: parent.width; height: 136
                        FormaGota {
                            id: previaGota
                            anchors.centerIn: parent; width: 112; height: 112
                            forma: dialogoGota.forma; color: dialogoGota.color
                            // Rebota un poco cada vez que cambia la forma o el color.
                            onFormaChanged: rebote.restart()
                            onColorChanged: rebote.restart()
                            SequentialAnimation {
                                id: rebote
                                NumberAnimation { target: previaGota; property: "scale"; to: 0.9; duration: Estilo.t(80); easing.type: Easing.OutQuad }
                                NumberAnimation { target: previaGota; property: "scale"; to: 1; duration: Estilo.t(420); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2.4) }
                            }
                        }
                    }
                    Rectangle {
                        x: 22; width: parent.width - 44; height: 40; radius: 11; color: "#1b1b1d"
                        border.width: 1; border.color: nombreGota.activeFocus ? "#555" : "transparent"
                        TextInput {
                            id: nombreGota
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                            clip: true; maximumLength: 18
                            color: "#fff"; selectionColor: "#555"
                            font { family: Estilo.letra; pixelSize: 14 }
                            onAccepted: dialogoGota.guardar()
                        }
                        Texto {
                            anchors.centerIn: parent; visible: !nombreGota.text
                            text: "Nombre"; color: "#666"; font.pixelSize: 14
                        }
                    }
                    Item { width: 1; height: 14 }
                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 7; spacing: 6
                        Repeater {
                            model: ["esfera", "nube", "cuadro", "estrella", "flor", "corazon", "flor8",
                                    "gota", "capsula", "triangulo", "pentagono", "engrane", "hexagono", "calabaza"]
                            delegate: Rectangle {
                                required property string modelData
                                readonly property bool elegida: dialogoGota.forma === modelData
                                width: 46; height: 46; radius: 12
                                color: elegida ? "#3a3a3c" : zonaF.containsMouse ? "#2f2f31" : "#002f2f31"
                                Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                                FormaGota { anchors.centerIn: parent; width: 32; height: 32; forma: parent.modelData; color: dialogoGota.color }
                                MouseArea { id: zonaF; anchors.fill: parent; hoverEnabled: true; onClicked: dialogoGota.forma = parent.modelData }
                            }
                        }
                    }
                    Item { width: 1; height: 14 }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 9
                        Repeater {
                            model: dialogoGota.colores
                            delegate: Item {
                                required property string modelData
                                readonly property bool elegido: dialogoGota.color === modelData
                                width: 26; height: 26
                                Rectangle {
                                    anchors.centerIn: parent; width: 32; height: 32; radius: 16
                                    color: "transparent"; border.width: 2; border.color: "#ffffff"
                                    opacity: parent.elegido ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Estilo.t(160) } }
                                }
                                Rectangle {
                                    anchors.fill: parent; radius: 13; color: parent.modelData
                                    border.width: parent.modelData === "#0b0b0c" ? 1 : 0; border.color: "#555"
                                }
                                MouseArea { anchors.fill: parent; onClicked: dialogoGota.color = parent.modelData }
                            }
                        }
                    }
                    Item { width: 1; height: 10 }
                    Item {
                        width: parent.width; height: 50
                        Column {
                            x: 22; anchors.verticalCenter: parent.verticalCenter
                            Texto { text: "Cambia de forma con las emociones" }
                            Texto { text: "Apagado: solo cambian los ojos"; color: "#888"; font.pixelSize: 11 }
                        }
                        Rectangle {
                            anchors { right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter }
                            width: 34; height: 20; radius: 10
                            color: dialogoGota.cambia ? "#ffffff" : "#444"
                            Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                            Rectangle {
                                y: 2; width: 16; height: 16; radius: 8; color: "#262628"
                                x: dialogoGota.cambia ? 16 : 2
                                Behavior on x { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(1.6) } }
                            }
                            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: dialogoGota.cambia = !dialogoGota.cambia }
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: "#353537" }
                    Item {
                        width: parent.width; height: 62
                        // Eliminar solo al editar, y nunca la ultima que queda
                        Boton {
                            visible: dialogoGota.indice >= 0 && Estilo.gotas.length > 1
                            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                            texto: "Eliminar"; colorTexto: "#ff453a"; fondo: "#00000000"
                            onPulsado: { Estilo.borrarGota(dialogoGota.indice); dialogoGota.cerrar(); }
                        }
                        Row {
                            anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            Boton { texto: "Cancelar"; onPulsado: dialogoGota.cerrar() }
                            Boton { texto: dialogoGota.indice < 0 ? "Crear" : "Guardar"; fondo: "#ffffff"; colorTexto: "#000"; onPulsado: dialogoGota.guardar() }
                        }
                    }
                }
            }
        }
    }

    // ---- Piezas de las paginas de ajustes (como las listas agrupadas de iOS) ----
    component Texto: Text {
        color: "#eee"
        font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
    }
    component Encabezado: Texto {
        color: "#888"
        font { pixelSize: 13; weight: Font.Bold }
        topPadding: 14; bottomPadding: 8
    }
    component Desplazable: Flickable {
        default property alias contenido: columna.data
        anchors.fill: parent
        contentHeight: columna.implicitHeight + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column { id: columna; width: parent.width; topPadding: -14 }
    }
    component Grupo: Rectangle {
        default property alias filas: lista.data
        width: parent ? parent.width : 0
        height: lista.implicitHeight
        radius: 12
        color: "#2e2e2e"
        Column { id: lista; width: parent.width }
    }
    component Fila: Item {
        id: filaBase
        property string titulo
        property string sub: ""
        property bool clicable: false       // toda la fila responde al clic (atajos)
        signal pulsada()
        default property alias derecha: lado.data
        width: parent ? parent.width : 0
        height: sub ? 50 : 40
        MouseArea { anchors.fill: parent; enabled: filaBase.clicable; onClicked: filaBase.pulsada() }
        Column {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter; right: lado.left; rightMargin: 10 }
            Texto { text: titulo; width: parent.width; elide: Text.ElideRight }
            Texto { visible: sub !== ""; text: sub; color: "#888"; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
        }
        Item {
            id: lado
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: childrenRect.width; height: childrenRect.height
        }
        Rectangle { anchors { left: parent.left; leftMargin: 12; right: parent.right; bottom: parent.bottom } height: 1; color: "#383838" }
    }
    component Interruptor: Fila {
        id: inter
        property bool encendido
        signal cambiar(bool v)
        Rectangle {
            width: 34; height: 20; radius: 10
            color: inter.encendido ? "#ffffff" : "#444"
            Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
            Rectangle {
                y: 2; width: 16; height: 16; radius: 8; color: Estilo.fondo
                x: inter.encendido ? 16 : 2
                Behavior on x { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(1.6) } }
            }
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: inter.cambiar(!inter.encendido) }
        }
    }
    component Segmentos: Fila {
        id: seg
        property var opciones: []
        property var claves: []
        property var elegida
        signal elegir(var clave)
        Rectangle {
            width: filaSeg.width + 4; height: 26; radius: 9; color: "#1b1b1b"
            // pastilla blanca que se desliza a la opcion elegida
            Rectangle {
                readonly property var hijo: repSeg.count, repSeg.itemAt(Math.max(0, seg.claves.indexOf(seg.elegida)))
                visible: seg.claves.indexOf(seg.elegida) >= 0
                x: hijo ? hijo.x + 2 : 2; width: hijo ? hijo.width : 0
                y: 2; height: 22; radius: 7; color: "#ffffff"
                Behavior on x { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                Behavior on width { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
            }
            Row {
                id: filaSeg
                x: 2; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    id: repSeg
                    model: seg.opciones
                    delegate: Texto {
                        required property string modelData
                        required property int index
                        text: modelData
                        leftPadding: 10; rightPadding: 10; topPadding: 4; bottomPadding: 4
                        font.pixelSize: 12
                        color: seg.claves[index] === seg.elegida ? "#111" : "#aaa"
                        Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                        MouseArea { anchors.fill: parent; onClicked: seg.elegir(seg.claves[index]) }
                    }
                }
            }
        }
    }
    component Deslizador: Fila {
        id: desl
        property real desde: 0
        property real hasta: 100
        property real valor: 0
        property string unidad: ""
        property real vivo: valor            // mientras se arrastra
        signal soltado(real v)
        onValorChanged: vivo = valor
        Row {
            spacing: 8
            Item {
                width: 150; height: 20
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: "#444" }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: perilla.x + 9; height: 4; radius: 2; color: "#ffffff" }
                Rectangle {
                    id: perilla
                    width: 18; height: 18; radius: 9; color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                    x: (desl.vivo - desl.desde) / (desl.hasta - desl.desde) * (parent.width - width)
                    scale: zonaD.pressed ? 1.15 : 1
                    Behavior on scale { NumberAnimation { duration: Estilo.t(200); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                }
                MouseArea {
                    id: zonaD
                    anchors.fill: parent; anchors.margins: -6
                    function mover(m) { desl.vivo = Math.round(desl.desde + Math.max(0, Math.min(1, (m.x - 6 - 9) / (width - 12 - 18))) * (desl.hasta - desl.desde)); }
                    onPressed: m => mover(m)
                    onPositionChanged: m => mover(m)
                    onReleased: desl.soltado(desl.vivo)
                }
            }
            Texto { width: 42; horizontalAlignment: Text.AlignRight; text: Math.round(desl.vivo) + desl.unidad; color: "#aaa"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    // Editor de secciones de la barra lateral: a la izquierda una miniatura de la barra con
    // un bloque por seccion, que se reordenan arrastrandolos (los demas le hacen hueco); a la
    // derecha, interruptores para mostrar u ocultar cada una. Se guarda al soltar.
    component EditorSecciones: Row {
        id: ed
        spacing: 14
        readonly property var nombres: ({ rapidos: "Botones rápidos", sonido: "Sonido", musica: "Reproduciendo", calendario: "Calendario", energia: "Energía" })
        readonly property var altos: ({ rapidos: 56, sonido: 44, musica: 40, calendario: 70, energia: 26 })
        readonly property var guardadas: Estilo.barra.secciones
        // Orden en vivo: mientras se arrastra cambia aqui; al soltar se guarda en los ajustes.
        property var orden: guardadas.map(s => s.id)
        onGuardadasChanged: orden = guardadas.map(s => s.id)
        function activa(id) { const s = guardadas.find(x => x.id === id); return s ? s.ver : false; }
        function yDe(id) {
            let y = 34;
            for (const k of orden) { if (k === id) return y; if (activa(k)) y += altos[k] + 6; }
            return y;
        }
        readonly property real altoMini: { let y = 34; for (const k of orden) if (activa(k)) y += altos[k] + 6; return y + 6; }
        function guardar() { Estilo.ponerBarra("secciones", orden.map(id => ({ id: id, ver: activa(id) }))); }

        Rectangle {
            width: 208; height: mini.height + 28; radius: 12; color: "#3a3f4a"
            Rectangle {
                id: mini
                x: 14; y: 14; width: 180
                height: ed.altoMini
                Behavior on height { NumberAnimation { duration: Estilo.t(340); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                radius: 16; color: "#1f1f1f"; border.color: "#3a3a3a"
                Texto { x: 12; y: 10; text: Qt.formatTime(reloj.date, Estilo.valor("reloj12") ? "h:mm AP" : "H:mm"); font.weight: Font.DemiBold }

                Repeater {
                    model: ["rapidos", "sonido", "musica", "calendario", "energia"]
                    delegate: Rectangle {
                        id: bloque
                        required property string modelData
                        readonly property bool activo: ed.activa(modelData)
                        x: 12; width: mini.width - 24; height: ed.altos[modelData]
                        radius: 12; color: "#2e2e2e"
                        y: ed.yDe(modelData)
                        Behavior on y { enabled: !arrastre.active; NumberAnimation { duration: Estilo.t(340); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                        opacity: activo ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Estilo.t(220) } }
                        z: arrastre.active ? 5 : 1
                        scale: arrastre.active ? 1.04 : 1
                        Behavior on scale { NumberAnimation { duration: Estilo.t(200); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                        border.color: "#ffffff"; border.width: arrastre.active ? 2 : 0

                        DragHandler {
                            id: arrastre
                            xAxis.enabled: false
                            yAxis.minimum: 30; yAxis.maximum: ed.altoMini - bloque.height - 4
                            cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            // Mientras se mueve: el bloque va al hueco cuyo centro ya paso.
                            onTranslationChanged: if (active) {
                                const centro = bloque.y + bloque.height / 2;
                                const resto = ed.orden.filter(k => k !== bloque.modelData);
                                let idx = 0, y = 34;
                                for (const k of resto) { if (!ed.activa(k)) continue; if (centro > y + ed.altos[k] / 2) idx++; y += ed.altos[k] + 6; }
                                const vis = resto.filter(k => ed.activa(k)), ocultas = resto.filter(k => !ed.activa(k));
                                vis.splice(idx, 0, bloque.modelData);
                                const nuevo = vis.concat(ocultas);
                                if (nuevo.join() !== ed.orden.join()) ed.orden = nuevo;
                            }
                            onActiveChanged: if (!active) { bloque.y = Qt.binding(() => ed.yDe(bloque.modelData)); ed.guardar(); }
                        }

                        // Dibujos en miniatura de cada seccion
                        Grid {
                            visible: bloque.modelData === "rapidos"
                            anchors { fill: parent; margins: 6 } columns: 2; spacing: 4
                            Repeater { model: 4; Rectangle { required property int index; width: (parent.width - 4) / 2; height: 19; radius: 7; color: index < 2 ? "#ffffff" : "#3a3a3a" } }
                        }
                        Column {
                            visible: bloque.modelData === "sonido"
                            anchors { fill: parent; margins: 7 } spacing: 6
                            Repeater { model: [0.4, 0.45]; Rectangle { required property real modelData; width: parent.width; height: 12; radius: 6; color: "#1b1b1b"
                                Rectangle { width: parent.width * modelData; height: 12; radius: 6; color: "#ffffff" } } }
                        }
                        Row {
                            visible: bloque.modelData === "musica"
                            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter } spacing: 6
                            Rectangle { width: 28; height: 28; radius: 6; color: "#8a5cf6" }
                            Column { anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                Rectangle { width: 70; height: 6; radius: 3; color: "#dddddd" }
                                Rectangle { width: 44; height: 5; radius: 3; color: "#777777" } }
                            Rectangle { width: 14; height: 14; radius: 7; color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Grid {
                            visible: bloque.modelData === "calendario"
                            anchors { fill: parent; margins: 8 } columns: 7; spacing: 3
                            Repeater { model: 28; Rectangle { required property int index; width: (parent.width - 18) / 7; height: 7; radius: 2; color: index === 18 ? "#ffffff" : "#555555" } }
                        }
                        Row {
                            visible: bloque.modelData === "energia"
                            anchors.centerIn: parent; spacing: 14
                            Repeater { model: 4; Rectangle { required property int index; width: 14; height: 14; radius: 7; color: index === 3 ? "#ff6b6b" : "#444444" } }
                        }
                    }
                }
            }
        }

        Column {
            width: ed.width - 208 - ed.spacing
            spacing: 8
            Texto { width: parent.width; wrapMode: Text.Wrap; text: "Arrastre los bloques en la vista previa para cambiar su orden."; color: "#888"; font.pixelSize: 12 }
            Grupo {
                Repeater {
                    model: ["rapidos", "sonido", "musica", "calendario", "energia"]
                    delegate: Interruptor {
                        required property string modelData
                        titulo: ed.nombres[modelData]
                        encendido: ed.activa(modelData)
                        onCambiar: v => Estilo.ponerBarra("secciones", ed.orden.map(id => ({ id: id, ver: id === modelData ? v : ed.activa(id) })))
                    }
                }
            }
        }
    }

    component Simbolo: Text {
        font { family: "Material Symbols Rounded"; pixelSize: 18 }
        font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 24 }
        renderType: Text.NativeRendering
        color: "#ffffff"
    }
    // Boton de pastilla (dialogos)
    component Boton: Rectangle {
        id: bot
        property string texto
        property color fondo: "#3a3a3c"
        property color colorTexto: "#fff"
        signal pulsado()
        width: tb.implicitWidth + 32; height: 34; radius: 17
        color: fondo
        scale: zb.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zb.pressed ? 90 : 300); easing.type: zb.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(1.8) } }
        Texto { id: tb; anchors.centerIn: parent; text: bot.texto; color: bot.colorTexto; font.weight: Font.DemiBold }
        MouseArea { id: zb; anchors.fill: parent; onClicked: bot.pulsado() }
    }

    // Campo de texto que guarda al pulsar Enter o al salir de el.
    component Campo: Fila {
        id: campo
        property string texto
        signal guardar(string t)
        Rectangle {
            width: 160; height: 26; radius: 8; color: "#1b1b1b"
            border.width: 1; border.color: entrada.activeFocus ? "#666" : "transparent"
            TextInput {
                id: entrada
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                text: campo.texto
                color: "#eee"; selectionColor: "#555"
                font { family: Estilo.letra; pixelSize: 12 }
                maximumLength: 18
                onEditingFinished: if (text.trim() && text.trim() !== campo.texto) campo.guardar(text.trim())
            }
        }
    }

    component FilaAtajo: Fila {
        id: fa
        property string clave
        readonly property bool esperando: ventana.capturando === clave
        Row {
            spacing: 3
            visible: !fa.esperando
            Repeater {
                model: (ventana.atajos[fa.clave] || "").replace(/^Mod\b/, "Super").split("+").filter(s => s)
                delegate: Rectangle {
                    required property string modelData
                    width: k.implicitWidth + 12; height: 20; radius: 6; color: "#1b1b1b"; border.color: "#444"
                    Texto { id: k; anchors.centerIn: parent; text: modelData === "Period" ? "." : modelData === "Slash" ? "/" : modelData; font.pixelSize: 11; color: "#ddd" }
                }
            }
        }
        Texto {
            visible: fa.esperando
            text: "Pulse la combinación…"; color: "#fff"; font.pixelSize: 12
            SequentialAnimation on opacity { running: fa.esperando; loops: Animation.Infinite; NumberAnimation { to: 0.4; duration: 500 } NumberAnimation { to: 1; duration: 500 } }
        }
        clicable: true
        onPulsada: { ventana.errorAtajo = ""; ventana.capturando = fa.clave; }
    }

    // Pagina: al cambiar de seccion, la nueva entra con fundido y se desliza 16 px
    // desde la derecha; la vieja se va hacia la izquierda.
    component Pagina: Item {
        id: pagina
        property bool activa
        opacity: activa ? 1 : 0
        visible: opacity > 0.01
        enabled: activa
        transform: Translate { id: desp }
        Behavior on opacity { NumberAnimation { duration: Estilo.t(240); easing.type: Easing.OutCubic } }
        onActivaChanged: { deslizar.from = activa ? 16 : 0; deslizar.to = activa ? 0 : -10; deslizar.restart() }
        NumberAnimation { id: deslizar; target: desp; property: "x"; duration: Estilo.t(520); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote }
    }

    // Entrada escalonada: cada bloque aparece subiendo 10 px, 45 ms despues del anterior,
    // cada vez que se abre la ventana.
    component Entrada: QtObject {
        id: entrada
        property int orden
        required property Item objetivo
        readonly property Translate desplazamiento: Translate { y: 0 }
        Component.onCompleted: objetivo.transform = [desplazamiento]
        property Connections c: Connections {
            target: ventana
            function onAbiertaChanged() {
                if (!ventana.abierta) return;
                anim.restart();
            }
        }
        property SequentialAnimation anim: SequentialAnimation {
            PropertyAction { target: entrada.objetivo; property: "opacity"; value: 0 }
            PropertyAction { target: entrada.desplazamiento; property: "y"; value: 10 }
            PauseAnimation { duration: Estilo.t(60 + entrada.orden * 45) }
            ParallelAnimation {
                NumberAnimation { target: entrada.objetivo; property: "opacity"; to: 1; duration: Estilo.t(320); easing.type: Easing.OutCubic }
                NumberAnimation { target: entrada.desplazamiento; property: "y"; to: 0; duration: Estilo.t(520); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote }
            }
        }
    }

    // Texto que, al cambiar, se desvanece y vuelve a aparecer subiendo 4 px.
    component TextoCambiante: Text {
        id: tc
        transform: Translate { id: tcY }
        onTextChanged: cambioTexto.restart()
        SequentialAnimation {
            id: cambioTexto
            PropertyAction { target: tc; property: "opacity"; value: 0 }
            PropertyAction { target: tcY; property: "y"; value: 4 }
            ParallelAnimation {
                NumberAnimation { target: tc; property: "opacity"; to: 1; duration: Estilo.t(260); easing.type: Easing.OutCubic }
                NumberAnimation { target: tcY; property: "y"; to: 0; duration: Estilo.t(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote }
            }
        }
    }

    // Imagen con esquinas redondeadas.
    component Redondeada: ClippingRectangle {
        id: red
        property string ruta
        property real radio
        property int ancho
        readonly property bool listo: img.status === Image.Ready

        radius: radio
        color: "transparent"
        Image {
            id: img
            anchors.fill: parent
            // Dentro de ClippingRectangle el padre es un contenedor interno: se usa el id.
            source: red.ruta ? "file://" + red.ruta : ""
            sourceSize.width: red.ancho
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    // Tarjeta de opcion rapida: blanca con texto negro cuando esta activa.
    // Al pulsar se hunde (0.95) y rebota al soltar; colores e icono cambian con fundido.
    component Tarjeta: Rectangle {
        id: tarjeta
        property string icono
        property string titulo
        property string detalle
        property bool activa
        signal pulsada()

        property real relleno: activa ? 1 : 0
        Behavior on relleno { NumberAnimation { duration: Estilo.t(280); easing.type: Easing.OutCubic } }

        width: rapidas.anchoTarjeta
        height: 76
        radius: 12
        color: activa ? "#ffffff" : (zonaT.containsMouse ? "#363636" : "#2e2e2e")
        Behavior on color { ColorAnimation { duration: Estilo.t(260); easing.type: Easing.OutCubic } }

        scale: zonaT.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zonaT.pressed ? 90 : 420); easing.type: zonaT.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.2) } }

        Column {
            anchors { left: parent.left; top: parent.top; margins: 11 }
            spacing: 3
            Text {
                text: tarjeta.icono
                color: tarjeta.activa ? "#111" : "#ddd"
                Behavior on color { ColorAnimation { duration: Estilo.t(260) } }
                font { family: "Material Symbols Rounded"; pixelSize: 22 }
                // Encendida: relleno, como el centro de control del iPhone. Apagada: contorno.
                font.variableAxes: { "FILL": tarjeta.relleno, "wght": 500, "opsz": 24 }
                renderType: Text.NativeRendering
            }
            Text {
                text: tarjeta.titulo
                color: tarjeta.activa ? "#111" : "#eee"
                Behavior on color { ColorAnimation { duration: Estilo.t(260) } }
                font { family: Estilo.letra; pixelSize: 13; weight: Font.Normal; letterSpacing: -0.08 }
            }
            TextoCambiante {
                text: tarjeta.detalle
                color: tarjeta.activa ? "#555" : "#888"
                Behavior on color { ColorAnimation { duration: Estilo.t(260) } }
                font { family: Estilo.letra; pixelSize: 11; weight: Font.Normal; letterSpacing: 0.06 }
                elide: Text.ElideRight
                width: rapidas.anchoTarjeta - 22
            }
        }
        MouseArea { id: zonaT; anchors.fill: parent; hoverEnabled: true; onClicked: tarjeta.pulsada() }
    }
}
