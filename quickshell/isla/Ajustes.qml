// Tipografia: SF Pro Text con los grosores, tamanos y tracking de la guia de Apple (macOS).
// Movimiento: curva de las hojas de iOS (0.32, 0.72, 0, 1) para entrar, InCubic corto para salir.
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
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

    // Muestras del dock (seccion Dock): los iconos de las apps ancladas y el tono de Material You
    // sacado del fondo actual, igual que el dock de verdad.
    property var iconosDock: ["helium", "claude-desktop-unofficial", "org.gnome.Nautilus", "kitty", "steam"]
    FileView {
        path: Estilo.carpeta + "/dock.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const l = JSON.parse(text()).map(a => a.escritorio); if (l.length) ventana.iconosDock = l; } catch (e) {} }
    }
    function iconoApp(id) {
        const e = DesktopEntries.applications.values.find(d => d.id === id);
        return Quickshell.iconPath(e ? e.icon : id, "application-x-executable");
    }
    ColorQuantizer { id: cuantizadorFondo; source: ventana.fondoActual ? "file://" + ventana.fondoActual : ""; depth: 3; rescaleSize: 64 }
    readonly property color tonoMY: Estilo.tonoMaterialYou(cuantizadorFondo.colors)

    // ---- Buscador e ir a un ajuste concreto (Inicio) ----
    // El indice se arma recorriendo las paginas: toda fila con titulo cuenta, asi un ajuste
    // nuevo aparece en el buscador sin registrarlo en ningun lado.
    function sinAcentos(s) { return s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase() }
    function indiceAjustes() {
        const r = [];
        const recorrer = (it, clave) => {
            for (const c of it.children) {
                if (c.clave !== undefined && c.activa !== undefined) { if (c.clave !== "inicio") recorrer(c, c.clave); continue; }
                if (clave && typeof c.titulo === "string" && c.titulo && typeof c.destello === "function")
                    r.push({ titulo: c.titulo, sub: c.sub || "", clave: clave, fila: c });
                recorrer(c, clave);
            }
        };
        recorrer(contenido, "");
        return r;
    }
    function nombreSeccion(clave) { const s = lateral.secciones.find(s => s.id === clave); return s ? s.texto : clave }
    function buscarAjustes(q) {
        q = sinAcentos(q.trim());
        if (!q) return [];
        const secciones = lateral.secciones.filter(s => s.id !== "inicio" && sinAcentos(s.texto).includes(q))
            .map(s => ({ titulo: s.texto, sub: "Sección", clave: s.id, fila: null }));
        const filas = indiceAjustes().filter(f => sinAcentos(f.titulo + " " + f.sub).includes(q));
        return secciones.concat(filas).slice(0, 6);
    }
    // Abre la seccion y, si se da una fila, baja hasta ella y la ilumina.
    function irA(clave, fila) {
        seccion = clave;
        if (!fila) return;
        let f = fila.parent;
        while (f && f.contentY === undefined) f = f.parent;
        if (f) {
            const y = fila.mapToItem(f.contentItem, 0, 0).y;
            f.contentY = Math.max(0, Math.min(y - 60, f.contentHeight - f.height));
        }
        fila.destello();
    }
    function irATitulo(clave, titulo) { irA(clave, indiceAjustes().find(f => f.clave === clave && f.titulo === titulo)?.fila ?? null) }

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
    Entrada { objetivo: buscador; orden: 0 }
    Entrada { objetivo: marcoHero; orden: 1 }
    Entrada { objetivo: filaEquipo; orden: 2 }
    Entrada { objetivo: accesos; orden: 3 }

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
        border.color: Estilo.borde
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
            color: Estilo.hundido
            Rectangle { width: 16; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } color: parent.color }

            readonly property var secciones: [
                { id: "inicio", texto: "Inicio", icono: "home" },
                { id: "apariencia", texto: "Apariencia", icono: "palette" },
                { id: "ventanas", texto: "Ventanas", icono: "select_window" },
                { id: "vidrio", texto: "Liquid glass", icono: "water_drop" },
                { id: "isla", texto: "Isla", icono: "pill" },
                { id: "dock", texto: "Dock", icono: "dock_to_bottom" },
                { id: "esquinas", texto: "Botones", icono: "crop_free" },
                { id: "barra", texto: "Barra lateral", icono: "view_sidebar" },
                { id: "notificaciones", texto: "Notificaciones", icono: "notifications" },
                { id: "asistente", texto: "Asistente", icono: "smart_toy" },
                { id: "pantallas", texto: "Pantallas", icono: "desktop_windows" },
                { id: "atajos", texto: "Atajos", icono: "keyboard" }
            ]
            readonly property int indice: secciones.findIndex(s => s.id === ventana.seccion)

            // Marca: los tres tubos del logo y el nombre en Archivo Expanded Black, como en el banner.
            FontLoader { id: letraMarca; source: Qt.resolvedUrl("fuentes/Archivo-ExpandedBlack.ttf") }
            Row {
                id: tituloLateral
                x: 22; y: 12
                spacing: 6
                bottomPadding: 8
                Shape {
                    id: tubos
                    // Trazos de assets/menisco-logo-white.svg: tubos en x 23.5-76.5, y 28-72.
                    width: 53 * 0.27; height: 44 * 0.27
                    anchors.verticalCenter: marca.verticalCenter
                    preferredRendererType: Shape.CurveRenderer
                    transform: Scale { xScale: 0.27; yScale: 0.27 }
                    ShapePath {
                        strokeWidth: -1
                        fillColor: Qt.alpha(Estilo.texto2, 0.45)
                        startX: 0; startY: 0
                        PathSvg { path: "M0 16Q7.5 21.25 15 16V39A5 5 0 0 1 10 44H5A5 5 0 0 1 0 39ZM38 16Q45.5 21.25 53 16V39A5 5 0 0 1 48 44H43A5 5 0 0 1 38 39Z" }
                    }
                    ShapePath {
                        strokeWidth: -1
                        fillColor: Estilo.texto2
                        PathSvg { path: "M19 0Q26.5 5.25 34 0V39A5 5 0 0 1 29 44H24A5 5 0 0 1 19 39Z" }
                    }
                }
                Text {
                    id: marca
                    text: "MENISCO"; color: Estilo.texto2
                    font { family: letraMarca.name; pixelSize: 11; weight: Font.Black; letterSpacing: 0.4 }
                }
            }

            // Una sola pastilla de seleccion que se desliza entre secciones.
            Rectangle {
                x: 12
                y: listaLateral.y + lateral.indice * 36
                width: lateral.width - 24
                height: 34
                radius: 9
                color: Estilo.hover
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
                        color: !elegida && zona.containsMouse ? Qt.alpha(Estilo.realce, 0.6) : Estilo.nada
                        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }

                        Text {
                            id: iconoLateral
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                            text: modelData.icono
                            color: fila.elegida ? Estilo.acento : Estilo.texto2
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
                            color: fila.elegida ? Estilo.texto : Estilo.texto2
                            Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                            font { family: Estilo.letra; pixelSize: 13; weight: Font.Normal; letterSpacing: -0.08 }
                        }
                        MouseArea { cursorShape: Qt.PointingHandCursor; id: zona; anchors.fill: parent; hoverEnabled: true; onClicked: ventana.seccion = modelData.id }
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
                id: paginaApariencia
                anchors.fill: parent
                clave: "apariencia"; activa: ventana.seccion === clave
                // Perfil en edicion (nombre) y el que muestra sus acciones (clic derecho)
                property int perfilRenombrando: -1
                property int perfilMenu: -1
                readonly property var nombresMaterial: ({ vidrio: "vidrio", solido: "sólido", ahumado: "ahumado", escarcha: "escarcha",
                                                          tinte: "tinte", contorno: "contorno", materialyou: "Material You" })
                Desplazable {
                    Encabezado { text: "Perfiles" }
                    Texto {
                        text: "Un perfil guarda toda la apariencia: tema, dock, isla, botones, marco, ventanas y vidrio. Clic para aplicarlo; clic derecho para renombrarlo, actualizarlo o borrarlo."
                        color: Estilo.texto2; font.pixelSize: 12; width: parent.width; wrapMode: Text.WordWrap
                    }
                    Item { width: 1; height: 10 }
                    Grid {
                        id: rejillaPerfiles
                        width: parent.width; columns: 4; spacing: 10
                        Repeater {
                            model: Estilo.perfiles
                            delegate: Rectangle {
                                id: tarjetaPerfil
                                required property var modelData
                                required property int index
                                readonly property var t: Estilo.temas[modelData.datos.tema] || Estilo.temas.champan
                                readonly property bool enUso: Estilo.perfilActivo === index
                                readonly property bool conMenu: paginaApariencia.perfilMenu === index
                                width: (rejillaPerfiles.width - 30) / 4; height: 150; radius: 14
                                color: Estilo.tarjeta; clip: true
                                border.width: enUso ? 2 : 1
                                border.color: enUso ? Estilo.texto : zonaPerfil.containsMouse ? Estilo.texto2 : Estilo.borde
                                scale: zonaPerfil.pressed ? 0.96 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaPerfil.pressed ? 80 : 340); easing.type: zonaPerfil.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                // Miniatura: pantalla con los colores del tema, isla y dock
                                Rectangle {
                                    x: 1; y: 1; width: parent.width - 2; height: 74
                                    topLeftRadius: 13; topRightRadius: 13
                                    color: tarjetaPerfil.t.fondo
                                    Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: parent.width * 0.42; height: 11; bottomLeftRadius: 6; bottomRightRadius: 6; color: "#000" }
                                    Rectangle {
                                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 9 }
                                        width: parent.width * 0.5; height: 15; radius: 6
                                        color: tarjetaPerfil.t.hover
                                        border.width: 1; border.color: tarjetaPerfil.t.activoBorde !== "#00000000" ? tarjetaPerfil.t.activoBorde : tarjetaPerfil.t.borde
                                    }
                                    Rectangle { x: parent.width - 16; y: 3; width: 9; height: 9; radius: 3; color: tarjetaPerfil.t.activo }
                                }
                                Column {
                                    x: 12; y: 84; width: parent.width - 24; spacing: 5
                                    Item {
                                        width: parent.width; height: 18
                                        Texto {
                                            visible: paginaApariencia.perfilRenombrando !== tarjetaPerfil.index
                                            text: tarjetaPerfil.modelData.nombre; font.pixelSize: 14; font.weight: Font.DemiBold
                                            width: parent.width - (tarjetaPerfil.enUso ? 52 : 0); elide: Text.ElideRight
                                        }
                                        TextInput {
                                            id: campoNombre
                                            visible: paginaApariencia.perfilRenombrando === tarjetaPerfil.index
                                            width: parent.width; text: tarjetaPerfil.modelData.nombre
                                            color: Estilo.texto; selectionColor: Estilo.acento; selectedTextColor: Estilo.sobreAcento
                                            font { family: Estilo.letra; pixelSize: 14; weight: Font.DemiBold }
                                            onVisibleChanged: if (visible) { text = tarjetaPerfil.modelData.nombre; forceActiveFocus(); selectAll(); }
                                            onAccepted: { if (text.trim()) Estilo.renombrarPerfil(tarjetaPerfil.index, text.trim()); paginaApariencia.perfilRenombrando = -1; }
                                            Keys.onEscapePressed: paginaApariencia.perfilRenombrando = -1
                                            Rectangle { anchors { left: parent.left; right: parent.right; top: parent.bottom; topMargin: 1 } height: 1; color: Estilo.acento }
                                        }
                                        Rectangle {
                                            visible: tarjetaPerfil.enUso && paginaApariencia.perfilRenombrando !== tarjetaPerfil.index
                                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                            width: textoUso.implicitWidth + 12; height: 18; radius: 9; color: Estilo.activo
                                            Texto { id: textoUso; anchors.centerIn: parent; text: "En uso"; font.pixelSize: 10; font.weight: Font.DemiBold; color: Estilo.enActivo }
                                        }
                                    }
                                    Row {
                                        spacing: 5
                                        Rectangle { width: 11; height: 11; radius: 6; color: tarjetaPerfil.t.acento }
                                        Rectangle { width: 11; height: 11; radius: 6; color: tarjetaPerfil.t.activoBorde !== "#00000000" ? tarjetaPerfil.t.activoBorde : tarjetaPerfil.t.activo }
                                    }
                                    Texto {
                                        width: parent.width; elide: Text.ElideRight; font.pixelSize: 11; color: Estilo.texto2
                                        text: tarjetaPerfil.t.nombre + " · dock " + (paginaApariencia.nombresMaterial[tarjetaPerfil.modelData.datos.dockMaterial] || "vidrio")
                                    }
                                }
                                MouseArea {
                                    id: zonaPerfil
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    enabled: paginaApariencia.perfilRenombrando !== tarjetaPerfil.index
                                    onClicked: e => {
                                        if (e.button === Qt.RightButton) { paginaApariencia.perfilMenu = tarjetaPerfil.conMenu ? -1 : tarjetaPerfil.index; return; }
                                        paginaApariencia.perfilMenu = -1;
                                        Estilo.aplicarPerfil(tarjetaPerfil.index);
                                    }
                                }
                                // Acciones del clic derecho: encima de la miniatura
                                Row {
                                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 22 }
                                    spacing: 6
                                    opacity: tarjetaPerfil.conMenu ? 1 : 0
                                    visible: opacity > 0.01
                                    scale: tarjetaPerfil.conMenu ? 1 : 0.85
                                    Behavior on opacity { NumberAnimation { duration: Estilo.t(160) } }
                                    Behavior on scale { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                    Repeater {
                                        model: [["edit", "nombre"], ["sync", "actualizar"], ["delete", "borrar"]]
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 32; height: 32; radius: 10
                                            color: zonaAccionPerfil.containsMouse ? (modelData[1] === "borrar" ? Estilo.peligro : Estilo.activo) : Estilo.fondo
                                            border.width: 1; border.color: Estilo.borde
                                            Simbolo {
                                                anchors.centerIn: parent; text: parent.modelData[0]; font.pixelSize: 17
                                                color: zonaAccionPerfil.containsMouse ? (parent.modelData[1] === "borrar" ? "#fff" : Estilo.iconoActivo) : Estilo.texto
                                            }
                                            MouseArea {
                                                id: zonaAccionPerfil; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    const i = tarjetaPerfil.index, a = parent.modelData[1];
                                                    paginaApariencia.perfilMenu = -1;
                                                    if (a === "nombre") paginaApariencia.perfilRenombrando = i;
                                                    else if (a === "actualizar") Estilo.actualizarPerfil(i);
                                                    else Estilo.borrarPerfil(i);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // Guardar lo de ahora como perfil nuevo (y ponerle nombre de una vez)
                        Rectangle {
                            width: (rejillaPerfiles.width - 30) / 4; height: 150; radius: 14
                            color: zonaNuevo.containsMouse ? Estilo.realce : Estilo.nada
                            border.width: 1.5; border.color: zonaNuevo.containsMouse ? Estilo.texto2 : Estilo.borde
                            Column {
                                anchors.centerIn: parent; spacing: 6
                                Simbolo { anchors.horizontalCenter: parent.horizontalCenter; text: "add"; font.pixelSize: 26; color: Estilo.texto2 }
                                Texto { anchors.horizontalCenter: parent.horizontalCenter; text: "Guardar el actual"; color: Estilo.texto2; font.pixelSize: 12 }
                            }
                            MouseArea {
                                id: zonaNuevo; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Estilo.guardarPerfil("Perfil " + (Estilo.perfiles.length + 1));
                                    paginaApariencia.perfilMenu = -1;
                                    paginaApariencia.perfilRenombrando = Estilo.perfiles.length - 1;
                                }
                            }
                        }
                    }
                    Encabezado { text: "Color" }
                    // Una muestra por tema, pintada con sus propios colores; al tocarla cambia todo Menisco.
                    Grid {
                        width: parent.width; columns: 5; spacing: 8
                        Repeater {
                            model: Estilo.ordenTemas
                            delegate: Rectangle {
                                id: muestra
                                required property string modelData
                                readonly property var t: Estilo.temas[modelData]
                                readonly property bool elegido: Estilo.valor("tema") === modelData
                                // Segundo tono: el filo de lo encendido o, si coincide con el acento, el icono encendido
                                readonly property var segundo: {
                                    const c = [];
                                    if (t.activoBorde !== "#00000000") c.push(Qt.alpha(t.activoBorde, 1));
                                    if (!Qt.colorEqual(t.iconoActivo, t.enActivo)) c.push(t.iconoActivo);
                                    return c.find(x => !Qt.colorEqual(x, t.acento)) ?? null;
                                }
                                width: (parent.width - 32) / 5; height: 84; radius: 12
                                color: t.fondo
                                border.width: elegido ? 2 : 1; border.color: elegido ? t.acento : zonaTema.containsMouse ? t.texto2 : t.borde
                                scale: zonaTema.pressed ? 0.95 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaTema.pressed ? 80 : 340); easing.type: zonaTema.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                Rectangle {
                                    x: 10; y: 10; width: parent.width - 20; height: 26; radius: 8
                                    color: muestra.t.tarjeta; border.width: 1; border.color: muestra.t.borde
                                    Rectangle {
                                        visible: muestra.segundo !== null
                                        x: 15; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7
                                        color: muestra.segundo ?? "transparent"
                                        border.width: 2; border.color: muestra.t.tarjeta
                                    }
                                    Rectangle { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7; color: muestra.t.acento }
                                    Rectangle { x: 34; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 44; height: 4; radius: 2; color: muestra.t.texto3 }
                                }
                                Text {
                                    anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
                                    text: muestra.t.nombre; color: muestra.t.texto
                                    font { family: Estilo.letra; pixelSize: 12; weight: Font.DemiBold; letterSpacing: -0.08 }
                                }
                                MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaTema; anchors.fill: parent; hoverEnabled: true; onClicked: Estilo.poner("tema", muestra.modelData) }
                            }
                        }
                    }
                    Encabezado { text: "Texto" }
                    Grupo {
                        Segmentos {
                            titulo: "Letra"; opciones: ["SF Pro", "Inter"]; claves: ["SF Pro", "Inter"]
                            elegida: Estilo.valor("letra"); onElegir: c => Estilo.poner("letra", c)
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
                }
            }

            // ---------------- Ventanas ----------------
            Pagina {
                anchors.fill: parent
                clave: "ventanas"; activa: ventana.seccion === clave
                Desplazable {
                    Encabezado { text: "Bordes y espacio" }
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
                        Interruptor { titulo: "Marco de pantalla"; sub: "Borde alrededor del monitor; la isla sale de él"; encendido: Estilo.valor("marco"); onCambiar: v => Estilo.poner("marco", v) }
                    }
                }
            }

            // ---------------- Dock ----------------
            Pagina {
                anchors.fill: parent
                clave: "dock"; activa: ventana.seccion === clave
                Desplazable {
                    Encabezado { text: "Vista previa" }
                    MuestraDock {
                        width: parent.width; height: 170; radius: 12
                        material: Estilo.valor("dockMaterial"); icono: 34
                    }
                    Encabezado { text: "Con vidrio" }
                    Texto { width: parent.width; wrapMode: Text.Wrap; bottomPadding: 8; color: Estilo.texto2; font.pixelSize: 12
                        text: "niri desenfoca lo que hay detrás; en Lniri, además, lleva el liquid glass." }
                    Grid {
                        width: parent.width; columns: 4; columnSpacing: 10; rowSpacing: 10
                        Repeater {
                            model: [["vidrio", "Vidrio", "De fábrica"], ["ahumado", "Ahumado", "Vidrio oscuro"],
                                    ["escarcha", "Escarcha", "Vidrio claro"], ["tinte", "Tinte", "Color del tema"]]
                            delegate: TarjetaMaterial { width: (parent.width - 30) / 4 }
                        }
                    }
                    Encabezado { text: "Sin vidrio" }
                    Grid {
                        width: parent.width; columns: 3; columnSpacing: 10; rowSpacing: 10
                        Repeater {
                            model: [["solido", "Sólido", "Negro del tema, como la isla"], ["contorno", "Contorno", "Solo el filo"],
                                    ["materialyou", "Material You", "Del color de su fondo"]]
                            delegate: TarjetaMaterial { width: (parent.width - 20) / 3 }
                        }
                    }
                    Encabezado { text: "Posición" }
                    Grupo {
                        Segmentos {
                            readonly property bool posible: Estilo.grosorMarco > 0 && !Estilo.dockConVidrio(Estilo.valor("dockMaterial"))
                            titulo: "Posición del dock"
                            sub: posible ? "Pegado sale del borde de abajo del marco"
                               : Estilo.grosorMarco > 0 ? "Pegado necesita un material sin vidrio" : "Pegado necesita el marco de pantalla (Ventanas)"
                            enabled: posible; opacity: posible ? 1 : 0.45
                            opciones: ["Flotante", "Pegado al borde"]; claves: [false, true]
                            elegida: Estilo.dockPegado
                            onElegir: c => Estilo.poner("dockPegado", c)
                        }
                    }
                    Encabezado { text: "Forma" }
                    Texto {
                        visible: Estilo.dockConVidrio(Estilo.valor("dockMaterial"))
                        width: parent.width; wrapMode: Text.Wrap; bottomPadding: 8; color: Estilo.texto2; font.pixelSize: 12
                        text: "Las formas necesitan un material sin vidrio: el vidrio cubre el dock como un rectángulo."
                    }
                    // Una muestra por forma, dibujada con las mismas cuentas que el dock (pegado o flotante, como esté).
                    Flow {
                        id: formasDock
                        readonly property bool posible: !Estilo.dockConVidrio(Estilo.valor("dockMaterial"))
                        width: parent.width; spacing: 8
                        enabled: posible; opacity: posible ? 1 : 0.45
                        Repeater {
                            model: Estilo.formasDock
                            delegate: Rectangle {
                                id: muestraDock
                                required property var modelData
                                readonly property bool elegida: Estilo.valor("dockForma") === modelData[0]
                                width: (parent.width - 24) / 4; height: 74; radius: 12
                                color: Estilo.tarjeta
                                border.width: elegida ? 2 : 1; border.color: elegida ? Estilo.acento : zonaFormaDock.containsMouse ? Estilo.texto2 : Estilo.borde
                                clip: true
                                scale: zonaFormaDock.pressed ? 0.95 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaFormaDock.pressed ? 80 : 340); easing.type: zonaFormaDock.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                Rectangle {   // franja de "pantalla"; pegado, con el borde del marco abajo
                                    id: pantallaDock
                                    x: 1; y: 1; width: parent.width - 2; height: 40; color: "#3a3f4a"
                                    topLeftRadius: 11; topRightRadius: 11
                                    clip: true
                                    Rectangle { visible: Estilo.dockPegado; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Estilo.fondo }
                                    Shape {   // dock de 160 x 70 reducido (124 a cada lado para la ola)
                                        width: 408; height: 76
                                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Estilo.dockPegado ? 0 : 5 }
                                        scale: 0.3; transformOrigin: Item.Bottom
                                        preferredRendererType: Shape.CurveRenderer
                                        ShapePath {
                                            fillColor: Estilo.fondo; strokeWidth: -1
                                            PathSvg { path: Estilo.trazoDock(Estilo.mitadDock(muestraDock.modelData[0], 124, 70, Estilo.dockPegado, 14), 204, Estilo.dockPegado, 76) }
                                        }
                                    }
                                }
                                Text {
                                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 9 }
                                    text: muestraDock.modelData[1]
                                    color: muestraDock.elegida ? Estilo.texto : Estilo.texto2
                                    font { family: Estilo.letra; pixelSize: 12; weight: muestraDock.elegida ? Font.DemiBold : Font.Normal }
                                }
                                MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaFormaDock; anchors.fill: parent; hoverEnabled: true; onClicked: Estilo.poner("dockForma", muestraDock.modelData[0]) }
                            }
                        }
                    }
                }
            }

            // ---------------- Pantallas ----------------
            Pagina {
                anchors.fill: parent
                clave: "pantallas"; activa: ventana.seccion === clave
                onActivaChanged: if (activa) leerSalidas.running = true
                Desplazable {
                    Encabezado { text: "Disposición" }
                    Rectangle {
                        id: mapa
                        width: parent.width; height: 150; radius: 12; color: Estilo.hundido
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
                                color: modelData.conectada ? Estilo.tarjeta : "transparent"
                                border.color: modelData.nombre === ventana.salidaElegida ? Estilo.acento : Estilo.texto3
                                border.width: modelData.nombre === ventana.salidaElegida ? 2 : 1
                                opacity: modelData.conectada ? 1 : 0.55
                                Behavior on x { enabled: !arrastre.active; NumberAnimation { duration: Estilo.t(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                                Column {
                                    anchors.centerIn: parent
                                    Texto { anchors.horizontalCenter: parent.horizontalCenter; text: caja.modelData.modelo; font.weight: Font.DemiBold }
                                    Texto { anchors.horizontalCenter: parent.horizontalCenter; text: caja.modelData.nombre + (caja.modelData.conectada ? "" : " · desconectado"); color: Estilo.texto2; font.pixelSize: 11 }
                                }
                                TapHandler { cursorShape: Qt.PointingHandCursor; onTapped: if (caja.modelData.conectada) ventana.salidaElegida = caja.modelData.nombre }
                                DragHandler {
                                    id: arrastre
                                    enabled: caja.modelData.conectada
                                    yAxis.enabled: false
                                    onActiveChanged: if (!active) ventana.reacomodar()
                                }
                            }
                        }
                        Texto { x: 12; anchors { bottom: parent.bottom; bottomMargin: 8 } text: "Arrastre los monitores para acomodarlos"; color: Estilo.texto2; font.pixelSize: 11 }
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
                id: paginaIsla
                anchors.fill: parent
                clave: "isla"; activa: ventana.seccion === clave
                property string huecoElegido: "izquierda"
                // [clave, nombre, icono]
                readonly property var catalogo: [["asistente", "Asistente", "face"], ["hora", "Hora", "schedule"], ["fecha", "Fecha y hora", "calendar_today"],
                    ["visualizador", "Visualizador", "graphic_eq"], ["temperatura", "Temperatura", "thermostat"], ["cpu", "Uso de CPU", "memory"],
                    ["volumen", "Volumen", "volume_up"], ["escritorios", "Escritorios", "view_week"], ["caratula", "Carátula", "music_note"], ["nada", "Nada", "block"]]
                Desplazable {

                    Encabezado { text: "Isla pequeña" }
                    Rectangle {
                        id: previaIsla
                        width: parent.width; height: 70; radius: 12; color: "#3a3f4a"
                        clip: true
                        Shape {   // la forma elegida, con las mismas cuentas que la isla de verdad
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                fillColor: Estilo.fondo; strokeWidth: -1
                                PathSvg { path: Estilo.trazoForma(Estilo.mitadForma(Estilo.valor("islaForma"), (previaIsla.width - 300) / 2 - Estilo.ajusteForma(Estilo.valor("islaForma"))[0], 38, 18, 16), previaIsla.width / 2) }
                            }
                        }
                        // Tres huecos: se pulsa uno y abajo se elige que muestra.
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 4; spacing: 4
                            Repeater {
                                model: ["izquierda", "centro", "derecha"]
                                delegate: Rectangle {
                                    id: hueco
                                    required property string modelData
                                    readonly property string tipo: Estilo.huecos[modelData]
                                    readonly property bool elegido: paginaIsla.huecoElegido === modelData
                                    width: modelData === "centro" ? 120 : 82; height: 30; radius: 10
                                    color: zonaHueco.containsMouse && !elegido ? Estilo.realce : Estilo.nada
                                    border.width: elegido ? 1.5 : 1
                                    border.color: elegido ? Estilo.acento : Qt.alpha(Estilo.texto, 0.18)
                                    Behavior on border.color { ColorAnimation { duration: Estilo.t(160) } }
                                    Rectangle {   // asistente: los dos ojos
                                        visible: hueco.tipo === "asistente"
                                        anchors.centerIn: parent
                                        width: 24; height: 24; radius: 12; color: Estilo.tarjeta
                                        Row { anchors.centerIn: parent; spacing: 4; Repeater { model: 2; Rectangle { width: 3; height: 8; radius: 2; color: "#fff" } } }
                                    }
                                    Row {         // visualizador
                                        visible: hueco.tipo === "visualizador"
                                        anchors.centerIn: parent; spacing: 3
                                        Repeater { model: [6, 11, 16, 11, 6]; Rectangle { required property int modelData; width: 3; height: modelData; radius: 1.5; color: "#fff"; anchors.verticalCenter: parent.verticalCenter } }
                                    }
                                    Texto {       // reloj (con fecha solo en el centro)
                                        visible: hueco.tipo === "hora" || hueco.tipo === "fecha"
                                        anchors.centerIn: parent
                                        text: (hueco.tipo === "fecha" ? Qt.locale("es_MX").toString(reloj.date, "ddd d").replace(/\./g, "") + " · " : "")
                                            + Qt.formatTime(reloj.date, Estilo.valor("reloj12") ? "h:mm" : "H:mm")
                                        font.pixelSize: hueco.tipo === "fecha" ? 13 : 15; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                                    }
                                    Simbolo {     // el resto: su icono
                                        visible: !["asistente", "visualizador", "hora", "fecha"].includes(hueco.tipo)
                                        anchors.centerIn: parent
                                        text: (paginaIsla.catalogo.find(c => c[0] === hueco.tipo) || ["", "", "block"])[2]
                                        color: hueco.tipo === "nada" ? Estilo.texto3 : Estilo.texto
                                    }
                                    MouseArea { id: zonaHueco; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: paginaIsla.huecoElegido = hueco.modelData }
                                }
                            }
                        }
                    }
                    Texto {
                        text: "Pulse un hueco y elija qué muestra. Si ya estaba en otro hueco, se cambian de lugar."
                        color: Estilo.texto2; font.pixelSize: 12; width: parent.width; wrapMode: Text.WordWrap
                    }
                    Grid {
                        width: parent.width; columns: 5; spacing: 8
                        Repeater {
                            model: paginaIsla.catalogo
                            delegate: Rectangle {
                                id: pieza
                                required property var modelData
                                readonly property bool puesto: Estilo.huecos[paginaIsla.huecoElegido] === modelData[0]
                                readonly property bool permitido: modelData[0] !== "fecha" || paginaIsla.huecoElegido === "centro"
                                width: (parent.width - 32) / 5; height: 70; radius: 12
                                color: puesto ? Estilo.activo : zonaPieza.containsMouse && permitido ? Estilo.realce : Estilo.tarjeta
                                border.width: 1; border.color: puesto ? Estilo.activoBorde : Estilo.linea
                                opacity: permitido ? 1 : 0.4
                                Behavior on color { ColorAnimation { duration: Estilo.t(160) } }
                                scale: zonaPieza.pressed ? 0.95 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaPieza.pressed ? 80 : 340); easing.type: zonaPieza.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                Simbolo { x: 12; y: 11; text: pieza.modelData[2]; font.pixelSize: 20; color: pieza.puesto ? Estilo.iconoActivo : Estilo.texto }
                                Texto {
                                    x: 12; y: 38; width: parent.width - 20; elide: Text.ElideRight
                                    text: pieza.modelData[1]; font.pixelSize: 12; font.weight: Font.DemiBold
                                    color: pieza.puesto ? Estilo.enActivo : Estilo.texto
                                }
                                Texto {
                                    visible: pieza.modelData[0] === "fecha"
                                    x: 12; y: 53; text: "Solo centro"; font.pixelSize: 10
                                    color: pieza.puesto ? Estilo.enActivo : Estilo.texto2
                                }
                                MouseArea {
                                    id: zonaPieza; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: pieza.permitido ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: if (pieza.permitido) Estilo.ponerHueco(paginaIsla.huecoElegido, pieza.modelData[0])
                                }
                            }
                        }
                    }
                    Encabezado { text: "Forma" }
                    // Una muestra por forma, dibujada con las mismas cuentas que la isla.
                    Flow {
                        width: parent.width; spacing: 8
                        Repeater {
                            model: Estilo.formasIsla
                            delegate: Rectangle {
                                id: muestraForma
                                required property var modelData
                                readonly property bool elegida: Estilo.valor("islaForma") === modelData[0]
                                width: (parent.width - 24) / 4; height: 74; radius: 12
                                color: Estilo.tarjeta
                                border.width: elegida ? 2 : 1; border.color: elegida ? Estilo.acento : zonaForma.containsMouse ? Estilo.texto2 : Estilo.borde
                                clip: true
                                scale: zonaForma.pressed ? 0.95 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaForma.pressed ? 80 : 340); easing.type: zonaForma.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                Rectangle {   // franja de "pantalla" de la que cuelga la isla
                                    x: 1; y: 1; width: parent.width - 2; height: 40; color: "#3a3f4a"
                                    topLeftRadius: 11; topRightRadius: 11
                                    Shape {
                                        anchors.fill: parent
                                        preferredRendererType: Shape.CurveRenderer
                                        ShapePath {
                                            fillColor: Estilo.fondo; strokeWidth: -1
                                            PathSvg { path: Estilo.trazoForma(Estilo.mitadForma(muestraForma.modelData[0], muestraForma.width / 2 - 34 - Estilo.ajusteForma(muestraForma.modelData[0])[0] / 2, 20, 9, 8), muestraForma.width / 2) }
                                        }
                                    }
                                }
                                Text {
                                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 9 }
                                    text: muestraForma.modelData[1]
                                    color: muestraForma.elegida ? Estilo.texto : Estilo.texto2
                                    font { family: Estilo.letra; pixelSize: 12; weight: muestraForma.elegida ? Font.DemiBold : Font.Normal }
                                }
                                MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaForma; anchors.fill: parent; hoverEnabled: true; onClicked: Estilo.poner("islaForma", muestraForma.modelData[0]) }
                            }
                        }
                    }
                    Encabezado { text: "Reloj" }
                    Grupo {
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
                    Encabezado { text: "Pestaña Acciones" }
                    Grupo {
                        Interruptor { titulo: "Botón del asistente"; sub: "La Gota grande a la izquierda de Acciones"; encendido: Estilo.valor("botEnPaginas"); onCambiar: v => Estilo.poner("botEnPaginas", v) }
                    }
                    Encabezado { text: "Imagen de fondo de Acciones" }
                    // "Ninguna" y luego los fondos de pantalla; la elegida va dentro de la isla, desvanecida hacia abajo.
                    Flow {
                        width: parent.width; spacing: 8
                        Rectangle {
                            readonly property bool elegida: !Estilo.valor("islaImagen")
                            width: 96; height: 60; radius: 10
                            color: zonaSinImagen.containsMouse ? Estilo.realce : Estilo.tarjeta
                            border.width: elegida ? 2 : 1; border.color: elegida ? Estilo.acento : Estilo.borde
                            Texto { anchors.centerIn: parent; text: "Ninguna"; font.pixelSize: 12; color: parent.elegida ? Estilo.texto : Estilo.texto2 }
                            MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaSinImagen; anchors.fill: parent; hoverEnabled: true; onClicked: Estilo.poner("islaImagen", "") }
                        }
                        Repeater {
                            model: FolderListModel {
                                folder: "file://" + ventana.carpetaFondos
                                nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
                                showDirs: false
                            }
                            delegate: Item {
                                id: imagenIsla
                                required property string filePath
                                readonly property bool elegida: Estilo.valor("islaImagen") === filePath
                                width: 96; height: 60
                                Rectangle {
                                    anchors.fill: parent; radius: 10; color: "transparent"
                                    border.color: Estilo.acento; border.width: 2
                                    opacity: imagenIsla.elegida ? 1 : 0
                                    scale: imagenIsla.elegida ? 1 : 1.08
                                    Behavior on opacity { NumberAnimation { duration: Estilo.t(220); easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: Estilo.t(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                                }
                                Redondeada {
                                    anchors { fill: parent; margins: 3 }
                                    radio: 7; ruta: imagenIsla.filePath; ancho: 200
                                    scale: zonaImagenIsla.pressed ? 0.94 : (zonaImagenIsla.containsMouse ? 1.04 : 1)
                                    Behavior on scale { NumberAnimation { duration: Estilo.t(zonaImagenIsla.pressed ? 90 : 320); easing.type: zonaImagenIsla.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(1.6) } }
                                }
                                MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaImagenIsla; anchors.fill: parent; hoverEnabled: true; onClicked: Estilo.poner("islaImagen", imagenIsla.filePath) }
                            }
                        }
                    }
                }
            }

            // ---------------- Notificaciones ----------------
            // Los avisos de la isla se guardan en menisco.json; lo de Hokum, en su config.kdl
            // (menisco-hokum.py), que Hokum recarga solo al guardarse.
            Pagina {
                id: paginaNotif
                anchors.fill: parent
                clave: "notificaciones"; activa: ventana.seccion === clave
                onActivaChanged: if (activa) leerHokum.running = true

                property var hokum: ({ posicion: "top-right", dura: "6", maximo: 5, apps: [] })
                readonly property string lado: hokum.posicion.split("-")[1]
                readonly property string alto: hokum.posicion.split("-")[0]
                Process {
                    id: leerHokum
                    command: ["python3", Estilo.carpeta + "/menisco-hokum.py", "leer"]
                    stdout: StdioCollector { onStreamFinished: { try { paginaNotif.hokum = JSON.parse(text); } catch (e) {} } }
                }
                // Se cambia aqui al instante y el archivo se escribe aparte.
                // ponytail: dos clics muy seguidos escriben a la vez; cola si algun dia se pierde uno.
                function hokumCmd(args, cambio) {
                    hokum = Object.assign({}, hokum, cambio);
                    Quickshell.execDetached(["python3", Estilo.carpeta + "/menisco-hokum.py"].concat(args));
                }
                function ponerPosicion(alto, lado) {
                    const pos = alto + "-" + lado;
                    hokumCmd(["comportamiento", "position", pos === "top-right" ? "" : '"' + pos + '"'], { posicion: pos });
                }
                // Apps de "Por aplicacion": las agregadas aqui y las que ya tienen regla en Hokum.
                readonly property var listaApps: {
                    const l = Estilo.valor("hokumApps").slice();
                    for (const a of hokum.apps) if (!l.includes(a.app)) l.push(a.app);
                    return l;
                }
                function regla(app) { return hokum.apps.find(a => a.app === app) || { app: app, modo: "mostrar", interrumpe: false }; }
                function ponerApp(app, modo, interrumpe) {
                    const apps = hokum.apps.filter(a => a.app !== app);
                    if (modo !== "mostrar" || interrumpe) apps.push({ app: app, modo: modo, interrumpe: interrumpe });
                    hokumCmd(["app", app, modo, interrumpe ? "si" : "no"], { apps: apps });
                }
                function quitarApp(app) {
                    Estilo.poner("hokumApps", Estilo.valor("hokumApps").filter(a => a !== app));
                    hokumCmd(["quitar", app], { apps: hokum.apps.filter(a => a.app !== app) });
                }
                function agregarApp(app) {
                    app = app.trim();
                    if (app && !listaApps.includes(app)) Estilo.poner("hokumApps", Estilo.valor("hokumApps").concat([app]));
                    agregando = false;
                }
                property bool agregando: false

                Desplazable {
                    Encabezado { text: "Vista previa" }
                    Rectangle {
                        width: parent.width; height: 96; radius: 12; color: "#3a3f4a"
                        clip: true
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 220; height: 30; color: Estilo.fondo
                            topLeftRadius: 0; topRightRadius: 0; bottomLeftRadius: 15; bottomRightRadius: 15
                            Texto { anchors.centerIn: parent; text: "Ahora suena"; font.pixelSize: 11; color: "#ccc" }
                        }
                        // Tarjeta de Hokum en la posicion elegida
                        Rectangle {
                            width: 150; height: 34; radius: 12; color: Estilo.hundido
                            x: paginaNotif.lado === "left" ? 10 : paginaNotif.lado === "center" ? (parent.width - width) / 2 : parent.width - width - 10
                            y: paginaNotif.alto === "top" ? 38 : parent.height - height - 8
                            Behavior on x { NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                            Behavior on y { NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                            Column {
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                Texto { text: "Discord"; color: Estilo.texto2; font.pixelSize: 10 }
                                Texto { text: "Nuevo mensaje"; font.pixelSize: 11 }
                            }
                        }
                    }

                    Encabezado { text: "No molestar" }
                    Grupo {
                        Interruptor { titulo: "No molestar"; sub: "Calla a Hokum y los avisos de la isla"; encendido: Estilo.noMolestar; onCambiar: v => Estilo.ponerNoMolestar(v) }
                        Interruptor { titulo: "Automático en pantalla completa"; sub: "Juegos y videos: se enciende solo y se apaga al salir"; encendido: Estilo.valor("dndPantallaCompleta"); onCambiar: v => Estilo.poner("dndPantallaCompleta", v) }
                        Interruptor { titulo: "Mientras grabo la pantalla"; sub: "Que no salga nada en el video"; encendido: Estilo.valor("dndGrabando"); onCambiar: v => Estilo.poner("dndGrabando", v) }
                    }

                    Encabezado { text: "Avisos en la isla" }
                    Grupo {
                        Interruptor { icono: "music_note"; titulo: "Ahora suena"; encendido: Estilo.valor("avisoMusica"); onCambiar: v => Estilo.poner("avisoMusica", v) }
                        Interruptor { icono: "headphones"; titulo: "Audífonos y bocinas"; encendido: Estilo.valor("avisoBt"); onCambiar: v => Estilo.poner("avisoBt", v) }
                        Interruptor { icono: "screenshot_region"; titulo: "Capturas de pantalla"; encendido: Estilo.valor("avisoCaptura"); onCambiar: v => Estilo.poner("avisoCaptura", v) }
                        Segmentos {
                            icono: "thermostat"; titulo: "Temperatura alta"
                            opciones: ["No", "70°", "80°", "90°"]; claves: [0, 70, 80, 90]
                            elegida: Estilo.valor("avisoTemp") ? Estilo.valor("avisoGrados") : 0
                            onElegir: c => { Estilo.poner("avisoTemp", c > 0); if (c > 0) Estilo.poner("avisoGrados", c); }
                        }
                        Interruptor { icono: "battery_alert"; titulo: "Batería baja del mando o audífonos"; sub: "Al bajar de 20 %"; encendido: Estilo.valor("avisoBateria"); onCambiar: v => Estilo.poner("avisoBateria", v) }
                        Interruptor { icono: "volume_up"; titulo: "Cambio de salida de audio"; encendido: Estilo.valor("avisoSalida"); onCambiar: v => Estilo.poner("avisoSalida", v) }
                        Interruptor { icono: "build"; titulo: "Fallos del sistema"; sub: "Bluetooth, sonido, gráfica, disco… con botón Arreglar"; encendido: Estilo.valor("avisoFallos"); onCambiar: v => Estilo.poner("avisoFallos", v) }
                        Segmentos { titulo: "Duración"; opciones: ["Corta", "Normal", "Larga"]; claves: ["corta", "normal", "larga"]; elegida: Estilo.valor("avisoDuracion"); onElegir: c => Estilo.poner("avisoDuracion", c) }
                    }

                    Encabezado { text: "Ahora suena" }
                    Grupo {
                        Item {
                            width: parent.width; height: fichas.y + fichas.height + 10
                            Column {
                                id: textoFichas
                                x: 12; y: 9
                                Texto { text: "Apps que avisan" }
                                Texto { text: "Toque una para callarla. Salen las abiertas y las ya calladas"; color: Estilo.texto2; font.pixelSize: 11 }
                            }
                            Flow {
                                id: fichas
                                x: 12; y: textoFichas.y + textoFichas.height + 8
                                width: parent.width - 24; spacing: 6
                                Repeater {
                                    id: repFichas
                                    // ponytail: solo las que tienen reproductor abierto ahora; recordar todas las vistas si hace falta
                                    model: {
                                        const l = Mpris.players.values.map(p => p.identity).filter(x => x);
                                        for (const x of Estilo.valor("musicaIgnorar")) if (!l.includes(x)) l.push(x);
                                        return l.filter((x, i) => l.indexOf(x) === i);
                                    }
                                    delegate: Rectangle {
                                        id: ficha
                                        required property string modelData
                                        readonly property bool callada: Estilo.valor("musicaIgnorar").includes(modelData)
                                        width: filaFicha.width + 16; height: 26; radius: 9; color: zonaFicha.containsMouse ? Estilo.realce : Estilo.hundido
                                        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                                        Row {
                                            id: filaFicha
                                            anchors.centerIn: parent; spacing: 5
                                            Simbolo { text: ficha.callada ? "music_off" : "music_note"; font.pixelSize: 14; color: ficha.callada ? Estilo.texto3 : Estilo.texto; anchors.verticalCenter: parent.verticalCenter }
                                            Texto { text: ficha.modelData; font.pixelSize: 12; font.strikeout: ficha.callada; color: ficha.callada ? Estilo.texto3 : Estilo.texto; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                        MouseArea { cursorShape: Qt.PointingHandCursor
                                            id: zonaFicha; anchors.fill: parent; hoverEnabled: true
                                            onClicked: {
                                                const l = Estilo.valor("musicaIgnorar");
                                                Estilo.poner("musicaIgnorar", ficha.callada ? l.filter(x => x !== ficha.modelData) : l.concat([ficha.modelData]));
                                            }
                                        }
                                    }
                                }
                                Texto { visible: repFichas.count === 0; text: "Ponga algo a sonar y aparecerá aquí"; color: Estilo.texto3; font.pixelSize: 12 }
                            }
                            Rectangle { anchors { left: parent.left; leftMargin: 12; right: parent.right; bottom: parent.bottom } height: 1; color: Estilo.linea }
                        }
                        Interruptor { titulo: "No avisar si la app está al frente"; sub: "Si ya está mirando el reproductor, no hace falta"; encendido: Estilo.valor("musicaNoAlFrente"); onCambiar: v => Estilo.poner("musicaNoAlFrente", v) }
                        Interruptor { titulo: "Solo con carátula"; sub: "Ignora videos y sonidos sueltos sin portada"; encendido: Estilo.valor("musicaConCaratula"); onCambiar: v => Estilo.poner("musicaConCaratula", v) }
                        Segmentos { titulo: "Al reanudar la misma canción"; opciones: ["No avisar", "Avisar"]; claves: [false, true]; elegida: Estilo.valor("musicaReanudar"); onElegir: c => Estilo.poner("musicaReanudar", c) }
                    }

                    Encabezado { text: "Hokum (notificaciones de apps)" }
                    Grupo {
                        Segmentos { titulo: "Posición"; opciones: ["Izquierda", "Centro", "Derecha"]; claves: ["left", "center", "right"]; elegida: paginaNotif.lado; onElegir: c => paginaNotif.ponerPosicion(paginaNotif.alto, c) }
                        Segmentos { titulo: "Arriba o abajo"; opciones: ["Arriba", "Abajo"]; claves: ["top", "bottom"]; elegida: paginaNotif.alto; onElegir: c => paginaNotif.ponerPosicion(c, paginaNotif.lado) }
                        Segmentos {
                            titulo: "Cuánto duran"; sub: "Si la app no dice otra cosa"
                            opciones: ["4 s", "6 s", "10 s", "20 s"]; claves: ["4", "6", "10", "20"]; elegida: paginaNotif.hokum.dura
                            onElegir: c => paginaNotif.hokumCmd(["comportamiento", "stay", c === "6" ? "" : c], { dura: c })
                        }
                        Deslizador {
                            titulo: "Máximo a la vista"; sub: "Las demás esperan en fila"; desde: 1; hasta: 8; valor: paginaNotif.hokum.maximo
                            onSoltado: v => paginaNotif.hokumCmd(["comportamiento", "show-at-most", v === 5 ? "" : String(v)], { maximo: v })
                        }
                    }

                    Encabezado { text: "Por aplicación" }
                    Grupo {
                        Repeater {
                            model: paginaNotif.listaApps
                            delegate: Segmentos {
                                id: filaApp
                                required property string modelData
                                readonly property var r: paginaNotif.regla(modelData)
                                icono: DesktopEntries.applications.values.find(e => e.name.toLowerCase() === modelData.toLowerCase())?.icon ?? ""
                                iconoEsApp: true
                                titulo: modelData
                                sub: r.interrumpe ? "Atraviesa No molestar" : ""
                                opciones: ["Mostrar", "Ocultar"]; claves: ["mostrar", "ocultar"]; elegida: r.modo
                                onElegir: c => paginaNotif.ponerApp(modelData, c, r.interrumpe)
                                // A la derecha de los segmentos: atravesar No molestar y quitar de la lista.
                                margenDerecho: 12 + iconosApp.width + 10
                                Row {
                                    id: iconosApp
                                    parent: filaApp
                                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    spacing: 2
                                    Simbolo {
                                        text: "notifications_active"; font.pixelSize: 17
                                        color: filaApp.r.interrumpe || zCampana.containsMouse ? Estilo.texto : Estilo.texto3
                                        MouseArea { cursorShape: Qt.PointingHandCursor; id: zCampana; hoverEnabled: true; anchors.fill: parent; anchors.margins: -5; onClicked: paginaNotif.ponerApp(filaApp.modelData, filaApp.r.modo, !filaApp.r.interrumpe) }
                                    }
                                    Simbolo {
                                        text: "close"; font.pixelSize: 17; color: zQuitar.containsMouse ? Estilo.peligro : Estilo.texto3
                                        MouseArea { cursorShape: Qt.PointingHandCursor; id: zQuitar; hoverEnabled: true; anchors.fill: parent; anchors.margins: -5; onClicked: paginaNotif.quitarApp(filaApp.modelData) }
                                    }
                                }
                            }
                        }
                        Fila {
                            visible: !paginaNotif.agregando
                            icono: "add"; titulo: "Agregar aplicación"; clicable: true
                            onPulsada: { paginaNotif.agregando = true; buscaApp.text = ""; buscaApp.forceActiveFocus(); }
                            Simbolo { text: "chevron_right"; color: Estilo.texto2 }
                        }
                        Item {
                            visible: paginaNotif.agregando
                            width: parent.width; height: visible ? sugerencias.y + sugerencias.height + 10 : 0
                            Rectangle {
                                x: 12; y: 8; width: parent.width - 24; height: 28; radius: 8; color: Estilo.hundido
                                border.width: 1; border.color: buscaApp.activeFocus ? Estilo.texto3 : "transparent"
                                TextInput {
                                    id: buscaApp
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    color: Estilo.texto; selectionColor: Estilo.texto3
                                    font { family: Estilo.letra; pixelSize: 12 }
                                    onAccepted: paginaNotif.agregarApp(text)
                                    Keys.onEscapePressed: paginaNotif.agregando = false
                                    Texto { visible: !parent.text; text: "Nombre de la app, como sale en la notificación"; color: Estilo.texto3; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                }
                            }
                            Flow {
                                id: sugerencias
                                x: 12; y: 44; width: parent.width - 24; spacing: 6
                                Repeater {
                                    model: !paginaNotif.agregando || !buscaApp.text.trim() ? []
                                        : DesktopEntries.applications.values
                                            .filter(e => !e.noDisplay && e.name.toLowerCase().includes(buscaApp.text.trim().toLowerCase()))
                                            .slice(0, 6).map(e => e.name)
                                    delegate: Rectangle {
                                        required property string modelData
                                        width: tSug.implicitWidth + 18; height: 26; radius: 9; color: zSug.containsMouse ? Estilo.realce : Estilo.hundido
                                        Texto { id: tSug; anchors.centerIn: parent; text: modelData; font.pixelSize: 12 }
                                        MouseArea { cursorShape: Qt.PointingHandCursor; id: zSug; anchors.fill: parent; hoverEnabled: true; onClicked: paginaNotif.agregarApp(modelData) }
                                    }
                                }
                            }
                        }
                    }
                    Texto {
                        topPadding: 10
                        width: parent.width; wrapMode: Text.Wrap
                        text: "La campana deja pasar esa app aunque esté puesto No molestar. Ocultar la calla del todo."
                        color: Estilo.texto2; font.pixelSize: 11
                    }
                }
            }

            // ---------------- Asistente ----------------
            Pagina {
                id: paginaBot
                anchors.fill: parent
                clave: "asistente"; activa: ventana.seccion === clave
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
                                    color: miniGota.elegida ? Estilo.tarjeta : zonaG.containsMouse ? Estilo.realce : Estilo.nada
                                    border.width: 2; border.color: miniGota.elegida ? Estilo.acento : Qt.alpha(Estilo.acento, 0)
                                    Behavior on color { ColorAnimation { duration: Estilo.t(160) } }
                                    Behavior on border.color { ColorAnimation { duration: Estilo.t(200) } }
                                    scale: zonaG.pressed ? 0.92 : 1
                                    Behavior on scale { NumberAnimation { duration: Estilo.t(zonaG.pressed ? 90 : 360); easing.type: zonaG.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(1.8) } }
                                    FormaGota { anchors.centerIn: parent; width: 38; height: 38; forma: miniGota.modelData.forma; color: miniGota.modelData.color }
                                    MouseArea { cursorShape: Qt.PointingHandCursor
                                        id: zonaG; anchors.fill: parent; hoverEnabled: true
                                        onClicked: miniGota.elegida ? dialogoGota.abrir(miniGota.index) : Estilo.poner("gotaActiva", miniGota.index)
                                    }
                                }
                                Texto { anchors.horizontalCenter: parent.horizontalCenter; text: miniGota.modelData.nombre; font.pixelSize: 11; color: miniGota.elegida ? Estilo.texto : Estilo.texto2 }
                            }
                        }
                        Column {
                            spacing: 6
                            Rectangle {
                                width: 56; height: 56; radius: 17
                                color: zonaNueva.containsMouse ? Estilo.realce : Estilo.nada
                                border.width: 1.5; border.color: Estilo.texto3
                                Behavior on color { ColorAnimation { duration: Estilo.t(160) } }
                                scale: zonaNueva.pressed ? 0.92 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaNueva.pressed ? 90 : 360); easing.type: zonaNueva.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(1.8) } }
                                Simbolo { anchors.centerIn: parent; text: "add"; color: Estilo.texto2; font.pixelSize: 24 }
                                MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaNueva; anchors.fill: parent; hoverEnabled: true; onClicked: dialogoGota.abrir(-1) }
                            }
                            Texto { anchors.horizontalCenter: parent.horizontalCenter; text: "Nueva"; font.pixelSize: 11; color: Estilo.texto2 }
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
                            text: Estilo.gota.nombre; font.pixelSize: 15; font.weight: Font.DemiBold; color: Estilo.texto
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
                                    color: elegida ? Estilo.activo : zEmo.containsMouse ? Estilo.realce : Estilo.tarjeta
                                    Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                                    Texto { id: et; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: 12; color: parent.elegida ? Estilo.enActivo : Estilo.texto2 }
                                    MouseArea { cursorShape: Qt.PointingHandCursor; id: zEmo; hoverEnabled: true; anchors.fill: parent; onClicked: paginaBot.prueba = modelData[1] }
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
                    }
                    Encabezado { text: "Animaciones" }
                    Grupo {
                        Interruptor { titulo: "Succionarse al abrir el lanzador"; encendido: Estilo.valor("succion"); onCambiar: v => Estilo.poner("succion", v) }
                    }
                }
            }

            // ---------------- Esquinas ----------------
            // Botones de las esquinas de arriba. Se reordenan arrastrando la fila por el asa;
            // la flecha la pasa al otro lado.
            Pagina {
                id: paginaEsquinas
                anchors.fill: parent
                clave: "esquinas"; activa: ventana.seccion === clave
                function info(c) { return Estilo.botonesCatalogo.find(x => x[0] === c) || [c, c, "help"]; }
                function mover(lado, i, j) {
                    const b = { izquierda: Estilo.botones.izquierda.slice(), derecha: Estilo.botones.derecha.slice() };
                    const [x] = b[lado].splice(i, 1);
                    b[lado].splice(Math.max(0, Math.min(j, b[lado].length)), 0, x);
                    Estilo.ponerBotones(b);
                }
                function cambiarLado(lado, i) {
                    const otro = lado === "izquierda" ? "derecha" : "izquierda";
                    const b = { izquierda: Estilo.botones.izquierda.slice(), derecha: Estilo.botones.derecha.slice() };
                    const [x] = b[lado].splice(i, 1);
                    if (otro === "izquierda") b[otro].push(x); else b[otro].unshift(x);   // entra por el lado de la isla
                    Estilo.ponerBotones(b);
                }
                function quitar(lado, i) {
                    const b = { izquierda: Estilo.botones.izquierda.slice(), derecha: Estilo.botones.derecha.slice() };
                    b[lado].splice(i, 1);
                    Estilo.ponerBotones(b);
                }
                function agregar(c) {
                    const b = { izquierda: Estilo.botones.izquierda.concat([c]), derecha: Estilo.botones.derecha.slice() };
                    Estilo.ponerBotones(b);
                }
                Desplazable {
                    Encabezado { text: "Botones de arriba" }
                    Texto {
                        text: "De izquierda a derecha, como se ven en la pantalla. Arrastre una fila por el asa para cambiar el orden; la flecha la pasa al otro lado."
                        color: Estilo.texto2; font.pixelSize: 12; width: parent.width; wrapMode: Text.WordWrap
                    }
                    Item { width: 1; height: 10 }
                    Row {
                        width: parent.width; spacing: 12
                        Repeater {
                            model: ["izquierda", "derecha"]
                            delegate: Rectangle {
                                id: columnaLado
                                required property string modelData
                                readonly property var lista: Estilo.botones[modelData]
                                readonly property int alto: 44
                                width: (parent.width - 12) / 2
                                height: 40 + Math.max(1, lista.length) * (alto + 6) + 6
                                radius: 12; color: Estilo.tarjeta
                                border.width: 1; border.color: Estilo.borde
                                Texto { x: 14; y: 12; text: columnaLado.modelData === "izquierda" ? "Izquierda" : "Derecha"; color: Estilo.texto2; font.weight: Font.DemiBold }
                                Texto {
                                    visible: columnaLado.lista.length === 0
                                    x: 14; y: 46; text: "Sin botones"; color: Estilo.texto3
                                }
                                Repeater {
                                    model: columnaLado.lista
                                    delegate: Rectangle {
                                        id: filaBoton
                                        required property string modelData
                                        required property int index
                                        readonly property var datos: paginaEsquinas.info(modelData)
                                        x: 8; width: parent.width - 16; height: columnaLado.alto; radius: 10
                                        y: 40 + index * (columnaLado.alto + 6)
                                        z: asa.drag.active ? 2 : 1
                                        color: asa.drag.active ? Estilo.realce : Estilo.hundido
                                        scale: asa.drag.active ? 1.02 : 1
                                        Behavior on scale { NumberAnimation { duration: Estilo.t(160) } }
                                        Simbolo {
                                            id: iconoAsa
                                            x: 8; anchors.verticalCenter: parent.verticalCenter
                                            text: "drag_indicator"; color: Estilo.texto3
                                            MouseArea {
                                                id: asa
                                                anchors.fill: parent; anchors.margins: -6
                                                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                                drag.target: filaBoton; drag.axis: Drag.YAxis
                                                drag.minimumY: 40; drag.maximumY: 40 + (columnaLado.lista.length - 1) * (columnaLado.alto + 6)
                                                onReleased: {
                                                    const j = Math.round((filaBoton.y - 40) / (columnaLado.alto + 6));
                                                    if (j !== filaBoton.index) paginaEsquinas.mover(columnaLado.modelData, filaBoton.index, j);
                                                    else filaBoton.y = Qt.binding(() => 40 + filaBoton.index * (columnaLado.alto + 6));
                                                }
                                            }
                                        }
                                        Simbolo { x: 38; anchors.verticalCenter: parent.verticalCenter; text: filaBoton.datos[2] }
                                        Texto { x: 66; anchors.verticalCenter: parent.verticalCenter; text: filaBoton.datos[1]; width: parent.width - 66 - 70; elide: Text.ElideRight }
                                        Row {
                                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                            spacing: 2
                                            Repeater {
                                                model: [[columnaLado.modelData === "izquierda" ? "arrow_forward" : "arrow_back", "lado"], ["close", "quitar"]]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: 28; height: 28; radius: 8
                                                    color: zonaAccion.containsMouse ? Estilo.realce : Estilo.nada
                                                    Simbolo { anchors.centerIn: parent; text: parent.modelData[0]; font.pixelSize: 16; color: Estilo.texto2 }
                                                    MouseArea {
                                                        id: zonaAccion; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: parent.modelData[1] === "lado" ? paginaEsquinas.cambiarLado(columnaLado.modelData, filaBoton.index)
                                                                                                  : paginaEsquinas.quitar(columnaLado.modelData, filaBoton.index)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Encabezado { text: "Añadir botón" }
                    Texto {
                        text: "Entra a la izquierda; con la flecha se pasa al otro lado."
                        color: Estilo.texto2; font.pixelSize: 12; width: parent.width; wrapMode: Text.WordWrap
                    }
                    Item { width: 1; height: 8 }
                    Flow {
                        width: parent.width; spacing: 8
                        Repeater {
                            model: Estilo.botonesCatalogo.filter(c => !Estilo.botones.izquierda.includes(c[0]) && !Estilo.botones.derecha.includes(c[0]))
                            delegate: Rectangle {
                                required property var modelData
                                width: filaChip.implicitWidth + 26; height: 34; radius: 17
                                color: zonaChip.containsMouse ? Estilo.realce : Estilo.tarjeta
                                border.width: 1; border.color: Estilo.linea
                                scale: zonaChip.pressed ? 0.94 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaChip.pressed ? 80 : 340); easing.type: zonaChip.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                Row {
                                    id: filaChip
                                    anchors.centerIn: parent; spacing: 6
                                    Simbolo { text: "add"; font.pixelSize: 16; color: Estilo.texto2; anchors.verticalCenter: parent.verticalCenter }
                                    Simbolo { text: parent.parent.modelData[2]; font.pixelSize: 17; anchors.verticalCenter: parent.verticalCenter }
                                    Texto { text: parent.parent.modelData[1]; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { id: zonaChip; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: paginaEsquinas.agregar(parent.modelData[0]) }
                            }
                        }
                    }
                    Item { width: 1; height: 12 }
                    Boton {
                        texto: "Volver a como estaba"
                        onPulsado: Estilo.ponerBotones(Estilo.barra.lado === "izquierda"
                            ? { izquierda: ["barra", "bandeja"], derecha: ["menisco"] }
                            : { izquierda: ["menisco"], derecha: ["bandeja", "barra"] })
                    }
                }
            }

            // ---------------- Barra lateral ----------------
            Pagina {
                anchors.fill: parent
                clave: "barra"; activa: ventana.seccion === clave
                Desplazable {
                    Encabezado { text: "Posición" }
                    Grupo {
                        Segmentos { titulo: "Lado"; opciones: ["Izquierda", "Derecha"]; claves: ["izquierda", "derecha"]; elegida: Estilo.barra.lado; onElegir: c => Estilo.ponerBarra("lado", c) }
                        Segmentos { titulo: "Altura"; opciones: ["Arriba", "Centro", "Abajo"]; claves: ["arriba", "centro", "abajo"]; elegida: Estilo.barra.altura; onElegir: c => Estilo.ponerBarra("altura", c) }
                        Deslizador { titulo: "Ancho"; desde: 300; hasta: 420; unidad: " px"; valor: Estilo.barra.ancho; onSoltado: v => Estilo.ponerBarra("ancho", v) }
                    }
                    Encabezado { text: "Cómo se abre" }
                    Grupo {
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
                                color: elegido ? Estilo.activo : zonaChip.containsMouse ? Estilo.realce : Estilo.hundido
                                Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                                scale: zonaChip.pressed ? 0.94 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaChip.pressed ? 80 : 360); easing.type: zonaChip.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                Row {
                                    id: filaChip
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: chip.modelData[1]; color: chip.elegido ? Estilo.enActivo : Estilo.texto2
                                        font { family: "Material Symbols Rounded"; pixelSize: 16 }
                                        font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 20 }
                                        renderType: Text.NativeRendering
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Texto { text: chip.modelData[2]; color: chip.elegido ? Estilo.enActivo : Estilo.texto2; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { cursorShape: Qt.PointingHandCursor
                                    id: zonaChip
                                    anchors.fill: parent; hoverEnabled: true
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
                clave: "vidrio"; activa: ventana.seccion === clave
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
                clave: "atajos"; activa: ventana.seccion === clave
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
                        color: ventana.errorAtajo ? Estilo.peligro : Estilo.texto2; font.pixelSize: 11
                    }
                }
            }

            Pagina {
                anchors.fill: parent
                clave: "inicio"; activa: ventana.seccion === clave

                Column {
                    id: paginaInicio
                    anchors.fill: parent
                    spacing: 0

                    // Buscador: encuentra cualquier fila de cualquier seccion y lleva hasta ella.
                    Item {
                        id: buscador
                        z: 10
                        width: parent.width
                        height: 34
                        property var resultados: []
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: Estilo.tarjeta
                            border.width: 1; border.color: campoBuscar.activeFocus ? Estilo.texto3 : "transparent"
                            Simbolo { x: 11; anchors.verticalCenter: parent.verticalCenter; text: "search"; color: Estilo.texto2; font.pixelSize: 17 }
                            TextInput {
                                id: campoBuscar
                                anchors { fill: parent; leftMargin: 36; rightMargin: 12 }
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                color: Estilo.texto; selectionColor: Estilo.texto3
                                font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
                                onTextChanged: buscador.resultados = ventana.buscarAjustes(text)
                                onAccepted: if (buscador.resultados.length) buscador.ir(buscador.resultados[0])
                                Keys.onEscapePressed: event => { if (text) { text = ""; event.accepted = true } else event.accepted = false }
                                Text {
                                    visible: !campoBuscar.text
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Buscar un ajuste: esquinas, reloj, sonido…"
                                    color: Estilo.texto3; font: campoBuscar.font
                                }
                            }
                        }
                        function ir(r) { campoBuscar.text = ""; campoBuscar.focus = false; ventana.irA(r.clave, r.fila) }

                        // Resultados: flotan sobre el fondo, debajo del campo.
                        Rectangle {
                            visible: campoBuscar.text !== ""
                            y: parent.height + 6
                            width: parent.width
                            height: listaRes.implicitHeight + 8
                            radius: 12
                            color: Estilo.tarjeta
                            border.width: 1; border.color: Estilo.borde
                            Column {
                                id: listaRes
                                x: 4; y: 4
                                width: parent.width - 8
                                Texto {
                                    visible: buscador.resultados.length === 0
                                    leftPadding: 10; topPadding: 9; bottomPadding: 9
                                    text: "Nada con ese nombre."; color: Estilo.texto2
                                }
                                Repeater {
                                    model: buscador.resultados
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: listaRes.width; height: 40; radius: 8
                                        color: zonaRes.containsMouse ? Estilo.realce : "transparent"
                                        Column {
                                            anchors { left: parent.left; leftMargin: 10; right: seccionRes.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                            Texto { text: modelData.titulo; width: parent.width; elide: Text.ElideRight }
                                            Texto { visible: modelData.sub !== "" && modelData.fila; text: modelData.sub; color: Estilo.texto2; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
                                        }
                                        Texto {
                                            id: seccionRes
                                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                            text: ventana.nombreSeccion(modelData.clave); color: Estilo.texto2; font.pixelSize: 11
                                        }
                                        MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaRes; anchors.fill: parent; hoverEnabled: true; onClicked: buscador.ir(modelData) }
                                    }
                                }
                            }
                        }
                    }
                    Item { width: 1; height: 10 }


                    // Hero: fondo actual con la isla en miniatura encima
                    Rectangle {
                        id: marcoHero
                        width: parent.width
                        height: 220
                        radius: 12
                        color: Estilo.tarjeta
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
                                color: Estilo.texto
                                font { family: Estilo.letra; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.06 }
                                renderType: Text.NativeRendering
                            }
                        }

                        Column {
                            anchors { left: parent.left; bottom: fondos.top; leftMargin: 14; bottomMargin: 10 }
                            TextoCambiante {
                                text: ventana.fondoActual ? ventana.fondoActual.split("/").pop().replace(/\.[^.]+$/, "") : "Sin fondo"
                                color: "#fff"
                                font { family: Estilo.letra; pixelSize: 15; weight: Font.DemiBold; letterSpacing: -0.23 }
                            }
                            TextoCambiante {
                                text: ventana.resolucion
                                color: Estilo.texto
                                font { family: Estilo.letra; pixelSize: 11; weight: Font.Normal; letterSpacing: 0.06 }
                            }
                        }

                        Rectangle {
                            id: abrirCarpeta
                            anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
                            width: textoCarpeta.implicitWidth + 20; height: 26; radius: 9
                            color: abrirZona.containsMouse ? "#99000000" : "#66000000"
                            Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                            scale: abrirZona.pressed ? 0.94 : 1
                            Behavior on scale { NumberAnimation { duration: Estilo.t(abrirZona.pressed ? 90 : 320); easing.type: abrirZona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(1.6) } }
                            Text {
                                id: textoCarpeta
                                anchors.centerIn: parent
                                text: "Abrir carpeta"; color: "#fff"
                                font { family: Estilo.letra; pixelSize: 11; weight: Font.Medium; letterSpacing: 0.06 }
                            }
                            MouseArea { cursorShape: Qt.PointingHandCursor; id: abrirZona; anchors.fill: parent; hoverEnabled: true; onClicked: ventana.ejecutar(["xdg-open", ventana.carpetaFondos]) }
                        }

                    ListView {
                            id: fondos
                            anchors { left: parent.left; right: abrirCarpeta.left; bottom: parent.bottom; leftMargin: 10; rightMargin: 8; bottomMargin: 10 }
                            height: 44
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
                                width: 66; height: 44
                                readonly property bool actual: filePath === ventana.fondoActual
    
                                // Anillo de seleccion: aparece cerrandose sobre la miniatura.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 9
                                    color: "transparent"
                                    border.color: Estilo.acento
                                    border.width: 2
                                    opacity: miniatura.actual ? 1 : 0
                                    scale: miniatura.actual ? 1 : 1.08
                                    Behavior on opacity { NumberAnimation { duration: Estilo.t(220); easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: Estilo.t(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                                }
                                Redondeada {
                                    anchors { fill: parent; margins: 3 }
                                    radio: 6
                                    ruta: miniatura.filePath
                                    ancho: 140
                                    scale: zonaMini.pressed ? 0.94 : (zonaMini.containsMouse ? 1.04 : 1)
                                    Behavior on scale { NumberAnimation { duration: Estilo.t(zonaMini.pressed ? 90 : 320); easing.type: zonaMini.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(1.6) } }
                                }
                                MouseArea { cursorShape: Qt.PointingHandCursor
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
    
                        }
                    }

                    // ---- Este equipo: se lee cada 5 s mientras el Inicio esta a la vista ----
                    property var equipo: ({ memoria: "—", grafica: "—", encendido: "—", menisco: "—" })
                    Timer {
                        interval: 5000; repeat: true; triggeredOnStart: true
                        running: ventana.abierta && ventana.seccion === "inicio"
                        onTriggered: leerEquipo.running = true
                    }
                    Process {
                        id: leerEquipo
                        // ponytail: la version sale del repo clonado en ~/menisco-dots; sin el, muestra "—".
                        command: ["sh", "-c", "free -b | awk '/^Mem:/{print $2-$7, $2}'; "
                            + "nvidia-smi --query-gpu=name,temperature.gpu --format=csv,noheader 2>/dev/null | head -1; echo; "
                            + "cut -d. -f1 /proc/uptime; git -C \"$HOME/menisco-dots\" log -1 --format=%h 2>/dev/null"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const l = text.split("\n");
                                const gb = n => (n / 1073741824).toFixed(1).replace(/\.0$/, "");
                                const [usada, total] = (l[0] || "").split(" ").map(Number);
                                const [nombre, temp] = (l[1] || "").split(",").map(s => s.trim());
                                const s = parseInt(l.find((x, i) => i >= 2 && /^\d+$/.test(x)) || "0");
                                const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
                                const ver = l.filter(x => /^[0-9a-f]{7,}$/.test(x)).pop();
                                paginaInicio.equipo = {
                                    memoria: total ? gb(usada) + " / " + Math.round(total / 1073741824) + " GB" : "—",
                                    grafica: nombre ? nombre.replace(/^NVIDIA (GeForce )?/, "") + (temp ? " · " + temp + "°" : "") : "—",
                                    encendido: d ? d + " d " + h + " h" : h ? h + " h " + m + " min" : m + " min",
                                    menisco: ver || "—"
                                };
                            }
                        }
                    }

                    Encabezado { text: "Este equipo" }
                    Row {
                        id: filaEquipo
                        width: parent.width
                        spacing: 8
                        readonly property real ancho: (width - spacing * 3) / 4
                        Repeater {
                            model: [["Memoria", "memoria"], ["Gráfica", "grafica"], ["Encendido", "encendido"], ["Menisco", "menisco"]]
                            delegate: Rectangle {
                                required property var modelData
                                width: filaEquipo.ancho; height: 48; radius: 10
                                color: Estilo.tarjeta
                                Column {
                                    anchors { left: parent.left; right: parent.right; margins: 10; verticalCenter: parent.verticalCenter }
                                    Texto { text: modelData[0]; color: Estilo.texto2; font.pixelSize: 11 }
                                    TextoCambiante {
                                        width: parent.width; elide: Text.ElideRight
                                        text: paginaInicio.equipo[modelData[1]]
                                        color: Estilo.texto; font { family: Estilo.letra; pixelSize: 13; weight: Font.DemiBold; letterSpacing: -0.08 }
                                    }
                                }
                            }
                        }
                    }

                    // Accesos: llevan directo a la fila, no solo a la seccion.
                    Encabezado { text: "Lo que más se cambia" }
                    Grid {
                        id: accesos
                        width: parent.width
                        columns: 2
                        spacing: 8
                        readonly property var lados: ({ left: "izquierda", center: "al centro", right: "derecha" })
                        Acceso {
                            icono: "schedule"; titulo: "Reloj de la isla"
                            detalle: (Estilo.valor("reloj12") ? "12 h" : "24 h") + (Estilo.valor("segundos") ? ", con segundos" : ", sin segundos")
                            onPulsado: ventana.irATitulo("isla", "Reloj")
                        }
                        Acceso {
                            icono: "smart_toy"; titulo: "Asistente"
                            detalle: Estilo.gota.nombre + " · " + Estilo.valor("personalidad")
                            onPulsado: ventana.irATitulo("asistente", "Personalidad")
                        }
                        Acceso {
                            icono: "notifications"; titulo: "Avisos de Hokum"
                            detalle: (paginaNotif.alto === "top" ? "Arriba " : "Abajo ") + accesos.lados[paginaNotif.lado]
                            onPulsado: ventana.irATitulo("notificaciones", "Posición")
                        }
                        Acceso {
                            icono: "keyboard"; titulo: "Atajos"
                            detalle: "Super + D, A, punto…"
                            onPulsado: ventana.irA("atajos", null)
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
                radius: 22; color: Estilo.tarjeta; border.width: 1; border.color: Estilo.linea
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
                            text: "close"; color: zCerrarGota.containsMouse ? Estilo.texto : Estilo.texto2; font.pixelSize: 20
                            MouseArea { cursorShape: Qt.PointingHandCursor; id: zCerrarGota; hoverEnabled: true; anchors.fill: parent; anchors.margins: -6; onClicked: dialogoGota.cerrar() }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Estilo.linea }
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
                        x: 22; width: parent.width - 44; height: 40; radius: 11; color: Estilo.hundido
                        border.width: 1; border.color: nombreGota.activeFocus ? Estilo.texto3 : "transparent"
                        TextInput {
                            id: nombreGota
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                            clip: true; maximumLength: 18
                            color: Estilo.texto; selectionColor: Estilo.texto3
                            font { family: Estilo.letra; pixelSize: 14 }
                            onAccepted: dialogoGota.guardar()
                        }
                        Texto {
                            anchors.centerIn: parent; visible: !nombreGota.text
                            text: "Nombre"; color: Estilo.texto3; font.pixelSize: 14
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
                                color: elegida ? Estilo.hover : zonaF.containsMouse ? Estilo.realce : Estilo.nada
                                Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                                FormaGota { anchors.centerIn: parent; width: 32; height: 32; forma: parent.modelData; color: dialogoGota.color }
                                MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaF; anchors.fill: parent; hoverEnabled: true; onClicked: dialogoGota.forma = parent.modelData }
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
                                    color: "transparent"; border.width: 2; border.color: Estilo.acento
                                    opacity: parent.elegido ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Estilo.t(160) } }
                                }
                                Rectangle {
                                    anchors.fill: parent; radius: 13; color: parent.modelData
                                    scale: zColor.containsMouse ? 1.15 : 1
                                    Behavior on scale { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                    border.width: parent.modelData === "#0b0b0c" ? 1 : 0; border.color: Estilo.texto3
                                }
                                MouseArea { cursorShape: Qt.PointingHandCursor; id: zColor; hoverEnabled: true; anchors.fill: parent; onClicked: dialogoGota.color = parent.modelData }
                            }
                        }
                    }
                    Item { width: 1; height: 10 }
                    Item {
                        width: parent.width; height: 50
                        Column {
                            x: 22; anchors.verticalCenter: parent.verticalCenter
                            Texto { text: "Cambia de forma con las emociones" }
                            Texto { text: "Apagado: solo cambian los ojos"; color: Estilo.texto2; font.pixelSize: 11 }
                        }
                        Rectangle {
                            anchors { right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter }
                            width: 34; height: 20; radius: 10
                            color: zCambia.containsMouse ? Estilo.aclarar(dialogoGota.cambia ? Estilo.acento : Estilo.apagado) : dialogoGota.cambia ? Estilo.acento : Estilo.apagado
                            Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                            Rectangle {
                                y: 2; width: 16; height: 16; radius: 8; color: Estilo.tarjeta
                                x: dialogoGota.cambia ? 16 : 2
                                Behavior on x { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(1.6) } }
                            }
                            MouseArea { cursorShape: Qt.PointingHandCursor; id: zCambia; hoverEnabled: true; anchors.fill: parent; anchors.margins: -6; onClicked: dialogoGota.cambia = !dialogoGota.cambia }
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: Estilo.linea }
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
                            Boton { texto: dialogoGota.indice < 0 ? "Crear" : "Guardar"; fondo: Estilo.acento; colorTexto: Estilo.sobreAcento; onPulsado: dialogoGota.guardar() }
                        }
                    }
                }
            }
        }
    }

    // ---- Piezas de las paginas de ajustes (como las listas agrupadas de iOS) ----
    component Texto: Text {
        color: Estilo.texto
        font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
    }
    component Encabezado: Texto {
        color: Estilo.texto2
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
        color: Estilo.tarjeta
        border.width: 1; border.color: Estilo.borde
        Column { id: lista; width: parent.width }
    }
    component Fila: Item {
        id: filaBase
        property string titulo
        property string sub: ""
        property bool clicable: false       // toda la fila responde al clic (atajos)
        property string icono: ""           // simbolo (o, con iconoEsApp, icono de app) a la izquierda
        property bool iconoEsApp: false
        property real margenDerecho: 12
        signal pulsada()
        default property alias derecha: lado.data
        width: parent ? parent.width : 0
        height: sub ? 50 : 40
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaFila; anchors.fill: parent; enabled: filaBase.clicable; hoverEnabled: true; onClicked: filaBase.pulsada() }
        Rectangle {
            anchors { fill: parent; margins: 3 }
            radius: 9; color: zonaFila.containsMouse ? Estilo.realce : Estilo.nada
            Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        }
        function destello() { brillo.restart() }
        Rectangle {
            id: luz
            anchors { fill: parent; margins: 3 }
            radius: 9; color: "#ffffff"; opacity: 0
            SequentialAnimation {
                id: brillo
                PauseAnimation { duration: Estilo.t(260) }
                NumberAnimation { target: luz; property: "opacity"; to: 0.14; duration: Estilo.t(180); easing.type: Easing.OutCubic }
                NumberAnimation { target: luz; property: "opacity"; to: 0; duration: Estilo.t(900); easing.type: Easing.InOutCubic }
            }
        }
        Rectangle {
            id: cajaIcono
            visible: filaBase.icono !== "" || filaBase.iconoEsApp
            x: 12; anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: 7; color: Estilo.hover
            Simbolo { visible: !filaBase.iconoEsApp || !filaBase.icono; anchors.centerIn: parent; text: filaBase.iconoEsApp ? "notifications" : filaBase.icono; font.pixelSize: 15 }
            IconImage { visible: filaBase.iconoEsApp && filaBase.icono !== ""; anchors.centerIn: parent; implicitSize: 18; source: filaBase.icono ? Quickshell.iconPath(filaBase.icono, true) : "" }
        }
        Column {
            anchors { left: parent.left; leftMargin: cajaIcono.visible ? 46 : 12; verticalCenter: parent.verticalCenter; right: lado.left; rightMargin: 10 }
            Texto { text: titulo; width: parent.width; elide: Text.ElideRight }
            Texto { visible: sub !== ""; text: sub; color: Estilo.texto2; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
        }
        Item {
            id: lado
            anchors { right: parent.right; rightMargin: filaBase.margenDerecho; verticalCenter: parent.verticalCenter }
            width: childrenRect.width; height: childrenRect.height
        }
        Rectangle { anchors { left: parent.left; leftMargin: 12; right: parent.right; bottom: parent.bottom } height: 1; color: Estilo.linea }
    }
    component Interruptor: Fila {
        id: inter
        property bool encendido
        signal cambiar(bool v)
        Rectangle {
            width: 34; height: 20; radius: 10
            color: zInter.containsMouse ? Estilo.aclarar(inter.encendido ? Estilo.acento : Estilo.apagado) : inter.encendido ? Estilo.acento : Estilo.apagado
            Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
            Rectangle {
                y: 2; width: 16; height: 16; radius: 8; color: inter.encendido ? Estilo.sobreAcento : Estilo.texto2
                x: inter.encendido ? 16 : 2
                Behavior on x { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(1.6) } }
            }
            MouseArea { cursorShape: Qt.PointingHandCursor; id: zInter; hoverEnabled: true; anchors.fill: parent; anchors.margins: -6; onClicked: inter.cambiar(!inter.encendido) }
        }
    }
    component Segmentos: Fila {
        id: seg
        property var opciones: []
        property var claves: []
        property var elegida
        signal elegir(var clave)
        Rectangle {
            width: filaSeg.width + 4; height: 26; radius: 9; color: Estilo.hundido
            // pastilla blanca que se desliza a la opcion elegida
            Rectangle {
                readonly property var hijo: repSeg.count, repSeg.itemAt(Math.max(0, seg.claves.indexOf(seg.elegida)))
                visible: seg.claves.indexOf(seg.elegida) >= 0
                x: hijo ? hijo.x + 2 : 2; width: hijo ? hijo.width : 0
                y: 2; height: 22; radius: 7; color: Estilo.activo
                border.width: 1; border.color: Estilo.activoBorde
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
                        color: seg.claves[index] === seg.elegida ? Estilo.enActivo : zSeg.containsMouse ? Estilo.texto : Estilo.texto2
                        Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                        MouseArea { cursorShape: Qt.PointingHandCursor; id: zSeg; hoverEnabled: true; anchors.fill: parent; onClicked: seg.elegir(seg.claves[index]) }
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
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Estilo.apagado }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: perilla.x + 9; height: 4; radius: 2; color: Estilo.acento }
                Rectangle {
                    id: perilla
                    width: 18; height: 18; radius: 9; color: Estilo.texto
                    anchors.verticalCenter: parent.verticalCenter
                    x: (desl.vivo - desl.desde) / (desl.hasta - desl.desde) * (parent.width - width)
                    scale: zonaD.pressed ? 1.15 : 1
                    Behavior on scale { NumberAnimation { duration: Estilo.t(200); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                }
                MouseArea { cursorShape: Qt.PointingHandCursor
                    id: zonaD
                    anchors.fill: parent; anchors.margins: -6
                    function mover(m) { desl.vivo = Math.round(desl.desde + Math.max(0, Math.min(1, (m.x - 6 - 9) / (width - 12 - 18))) * (desl.hasta - desl.desde)); }
                    onPressed: m => mover(m)
                    onPositionChanged: m => mover(m)
                    onReleased: desl.soltado(desl.vivo)
                }
            }
            Texto { width: 42; horizontalAlignment: Text.AlignRight; text: Math.round(desl.vivo) + desl.unidad; color: Estilo.texto2; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
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
                radius: 16; color: Estilo.hundido; border.color: Estilo.borde
                Texto { x: 12; y: 10; text: Qt.formatTime(reloj.date, Estilo.valor("reloj12") ? "h:mm AP" : "H:mm"); font.weight: Font.DemiBold }

                Repeater {
                    model: ["rapidos", "sonido", "musica", "calendario", "energia"]
                    delegate: Rectangle {
                        id: bloque
                        required property string modelData
                        readonly property bool activo: ed.activa(modelData)
                        x: 12; width: mini.width - 24; height: ed.altos[modelData]
                        radius: 12; color: Estilo.tarjeta
                        y: ed.yDe(modelData)
                        Behavior on y { enabled: !arrastre.active; NumberAnimation { duration: Estilo.t(340); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                        opacity: activo ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Estilo.t(220) } }
                        z: arrastre.active ? 5 : 1
                        scale: arrastre.active ? 1.04 : 1
                        Behavior on scale { NumberAnimation { duration: Estilo.t(200); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                        border.color: Estilo.acento; border.width: arrastre.active ? 2 : 0

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
                            Repeater { model: 4; Rectangle { required property int index; width: (parent.width - 4) / 2; height: 19; radius: 7; color: index < 2 ? Estilo.activo : Estilo.hover } }
                        }
                        Column {
                            visible: bloque.modelData === "sonido"
                            anchors { fill: parent; margins: 7 } spacing: 6
                            Repeater { model: [0.4, 0.45]; Rectangle { required property real modelData; width: parent.width; height: 12; radius: 6; color: Estilo.hundido
                                Rectangle { width: parent.width * modelData; height: 12; radius: 6; color: Estilo.acento } } }
                        }
                        Row {
                            visible: bloque.modelData === "musica"
                            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter } spacing: 6
                            Rectangle { width: 28; height: 28; radius: 6; color: "#8a5cf6" }
                            Column { anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                Rectangle { width: 70; height: 6; radius: 3; color: Estilo.texto }
                                Rectangle { width: 44; height: 5; radius: 3; color: Estilo.texto3 } }
                            Rectangle { width: 14; height: 14; radius: 7; color: Estilo.acento; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Grid {
                            visible: bloque.modelData === "calendario"
                            anchors { fill: parent; margins: 8 } columns: 7; spacing: 3
                            Repeater { model: 28; Rectangle { required property int index; width: (parent.width - 18) / 7; height: 7; radius: 2; color: index === 18 ? Estilo.acento : Estilo.texto3 } }
                        }
                        Row {
                            visible: bloque.modelData === "energia"
                            anchors.centerIn: parent; spacing: 14
                            Repeater { model: 4; Rectangle { required property int index; width: 14; height: 14; radius: 7; color: index === 3 ? Estilo.peligro : Estilo.apagado } }
                        }
                    }
                }
            }
        }

        Column {
            width: ed.width - 208 - ed.spacing
            spacing: 8
            Texto { width: parent.width; wrapMode: Text.Wrap; text: "Arrastre los bloques en la vista previa para cambiar su orden."; color: Estilo.texto2; font.pixelSize: 12 }
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
        color: Estilo.texto
    }
    // Boton de pastilla (dialogos)
    component Boton: Rectangle {
        id: bot
        property string texto
        property color fondo: Estilo.hover
        property color colorTexto: Estilo.texto
        signal pulsado()
        width: tb.implicitWidth + 32; height: 34; radius: 17
        color: zb.containsMouse ? Estilo.aclarar(fondo) : fondo
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        scale: zb.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zb.pressed ? 90 : 300); easing.type: zb.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(1.8) } }
        Texto { id: tb; anchors.centerIn: parent; text: bot.texto; color: bot.colorTexto; font.weight: Font.DemiBold }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zb; anchors.fill: parent; hoverEnabled: true; onClicked: bot.pulsado() }
    }

    // Campo de texto que guarda al pulsar Enter o al salir de el.
    component Campo: Fila {
        id: campo
        property string texto
        signal guardar(string t)
        Rectangle {
            width: 160; height: 26; radius: 8; color: Estilo.hundido
            border.width: 1; border.color: entrada.activeFocus ? Estilo.texto3 : "transparent"
            TextInput {
                id: entrada
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                text: campo.texto
                color: Estilo.texto; selectionColor: Estilo.texto3
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
                    width: k.implicitWidth + 12; height: 20; radius: 6; color: Estilo.hundido; border.color: Estilo.apagado
                    Texto { id: k; anchors.centerIn: parent; text: modelData === "Period" ? "." : modelData === "Slash" ? "/" : modelData; font.pixelSize: 11; color: Estilo.texto }
                }
            }
        }
        Texto {
            visible: fa.esperando
            text: "Pulse la combinación…"; color: Estilo.texto; font.pixelSize: 12
            SequentialAnimation on opacity { running: fa.esperando; loops: Animation.Infinite; NumberAnimation { to: 0.4; duration: 500 } NumberAnimation { to: 1; duration: 500 } }
        }
        clicable: true
        onPulsada: { ventana.errorAtajo = ""; ventana.capturando = fa.clave; }
    }

    // Pagina: al cambiar de seccion, la nueva entra con fundido y se desliza 16 px
    // desde la derecha; la vieja se va hacia la izquierda.
    component Pagina: Item {
        id: pagina
        property string clave
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

    // Acceso del Inicio: icono, titulo, valor actual y flecha. Lleva a un ajuste concreto.
    component Acceso: Rectangle {
        id: acceso
        property string icono
        property string titulo
        property string detalle
        signal pulsado()
        width: (accesos.width - accesos.spacing) / 2
        height: 52
        radius: 12
        color: zonaA.containsMouse ? Estilo.realce : Estilo.tarjeta
        Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
        scale: zonaA.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zonaA.pressed ? 90 : 420); easing.type: zonaA.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.2) } }
        Simbolo { x: 13; anchors.verticalCenter: parent.verticalCenter; text: acceso.icono; color: Estilo.texto; font.pixelSize: 20 }
        Column {
            anchors { left: parent.left; leftMargin: 44; right: flecha.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            Texto { text: acceso.titulo; width: parent.width; elide: Text.ElideRight }
            TextoCambiante { text: acceso.detalle; width: parent.width; elide: Text.ElideRight; color: Estilo.texto2; font { family: Estilo.letra; pixelSize: 11; letterSpacing: 0.06 } }
        }
        Simbolo {
            id: flecha
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: "chevron_right"; color: Estilo.texto3; font.pixelSize: 18
            transform: Translate { x: zonaA.containsMouse ? 2 : 0; Behavior on x { NumberAnimation { duration: Estilo.t(200); easing.type: Easing.OutCubic } } }
        }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaA; anchors.fill: parent; hoverEnabled: true; onClicked: acceso.pulsado() }
    }

    // Un dock pequeno sobre el fondo de pantalla real, en el material dado. El vidrio se imita
    // desenfocando el trozo de fondo que queda detras del dock.
    component MuestraDock: ClippingRectangle {
        id: md
        property string material
        property int icono: 18
        color: "#3a3f4a"
        Image {
            id: fondoMd
            anchors.fill: parent
            source: ventana.fondoActual ? "file://" + ventana.fondoActual : ""
            fillMode: Image.PreserveAspectCrop; sourceSize.width: 640; asynchronous: true
        }
        Item {
            id: dk
            readonly property var asp: Estilo.aspectoDock(md.material, ventana.tonoMY, false)
            readonly property real radio: height * (md.material === "materialyou" ? 0.36 : 0.32)
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Math.round(md.icono * 0.45) }
            width: filaIconos.width + md.icono * 0.75; height: Math.round(md.icono * 1.55)
            ClippingRectangle {
                anchors.fill: parent; radius: dk.radio; color: "transparent"
                opacity: Estilo.dockConVidrio(md.material) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Estilo.t(300) } }
                Image {
                    x: -dk.x; y: -dk.y; width: md.width; height: md.height
                    source: fondoMd.source; fillMode: Image.PreserveAspectCrop; sourceSize.width: 640; asynchronous: true
                    layer.enabled: true
                    layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 32 }
                }
            }
            Rectangle {
                anchors.fill: parent; radius: dk.radio
                color: dk.asp[0]; border.color: dk.asp[1]; border.width: dk.asp[2]
                Behavior on color { ColorAnimation { duration: Estilo.t(300) } }
                Behavior on border.color { ColorAnimation { duration: Estilo.t(300) } }
            }
            Rectangle {   // brillo de arriba del Material You
                anchors.fill: parent; radius: dk.radio
                opacity: md.material === "materialyou" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Estilo.t(300) } }
                gradient: Gradient { GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.13) } GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0) } }
            }
            Row {
                id: filaIconos
                anchors.centerIn: parent; spacing: Math.round(md.icono * 0.28)
                Repeater {
                    model: ventana.iconosDock.slice(0, 5)
                    delegate: Image { required property string modelData; width: md.icono; height: md.icono; sourceSize: Qt.size(48, 48); source: ventana.iconoApp(modelData) }
                }
            }
        }
    }
    component TarjetaMaterial: Rectangle {
        id: tm
        required property var modelData          // [clave, nombre, descripcion]
        readonly property bool elegido: Estilo.valor("dockMaterial") === modelData[0]
        height: 88 + 48; radius: 14
        color: Estilo.tarjeta
        border.width: elegido ? 2 : 1; border.color: elegido ? Estilo.acento : zonaTm.containsMouse ? Estilo.texto2 : Estilo.borde
        scale: zonaTm.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zonaTm.pressed ? 80 : 340); easing.type: zonaTm.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
        MuestraDock { x: 3; y: 3; width: parent.width - 6; height: 88; radius: 11; material: tm.modelData[0]; icono: 16 }
        Column {
            x: 11; y: 96; width: parent.width - 22; spacing: 1
            Texto { width: parent.width; text: tm.modelData[1]; font.weight: tm.elegido ? Font.DemiBold : Font.Medium; elide: Text.ElideRight }
            Texto { width: parent.width; text: tm.modelData[2]; color: Estilo.texto2; font.pixelSize: 11; elide: Text.ElideRight }
        }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaTm; anchors.fill: parent; hoverEnabled: true; onClicked: Estilo.poner("dockMaterial", tm.modelData[0]) }
    }
}
