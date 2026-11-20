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
    // Ocupa el monitor entero pero solo el panel recibe clics (mask): fuera de el, el clic
    // llega a la capa de sombra de shell.qml, que cierra Ajustes. El panel se mide con la
    // pantalla y se centra en el espacio util, entre la isla y el dock.
    anchors { top: true; bottom: true; left: true; right: true }
    // La zona de clics sale de este rectangulo quieto y no del panel: el panel entra escalado
    // (0.9 -> 1) y la region se quedaba con el tamaño de ese momento, dejando los bordes sin clic.
    mask: Region { item: zonaClics }
    Item { id: zonaClics; x: ventana.xPanel; y: ventana.yPanel; width: ventana.anchoPanel; height: ventana.altoPanel }
    readonly property int topReserve: 44
    readonly property int bottomReserve: 96
    readonly property int anchoPanel: Math.round(Math.min(1280, Math.max(900, (screen ? screen.width : 1920) * 0.62)))
    readonly property int altoPanel: Math.round(Math.min(860, Math.max(640, ((screen ? screen.height : 1080) - topReserve - bottomReserve) * 0.88)))
    readonly property real xPanel: Math.round((width - anchoPanel) / 2)
    readonly property real yPanel: Math.round(topReserve + (height - topReserve - bottomReserve - altoPanel) / 2)
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
    // Abre la seccion y, si se da una fila, baja hasta ella y la ilumina. Si estaba guardada en
    // una tarjeta plegada o detras de "Mostrar mas", primero la abre y baja cuando termina de abrirse.
    property var destino: null
    function irA(clave, fila) {
        seccion = clave;
        if (!fila) return;
        let abrio = false;
        for (let p = fila; p; p = p.parent) {
            if (p.esPlegable && !p.abierto) { p.abierto = true; abrio = true; }
            if (p.visibles > 0 && !p.mas && p.filasReales.indexOf(fila) >= p.visibles) { p.mas = true; abrio = true; }
            if (p.esRevelar && !p.abierto && fila.mapToItem(p, 0, 0).y >= p.alturaCerrada) { p.pedirAbrir(); abrio = true; }
        }
        destino = fila;
        if (abrio) bajar.restart(); else bajarADestino();
    }
    Timer { id: bajar; interval: Estilo.t(440) + 30; onTriggered: ventana.bajarADestino() }
    function bajarADestino() {
        const fila = destino;
        if (!fila) return;
        let f = fila.parent;
        while (f && f.contentY === undefined) f = f.parent;
        if (f && f.conPestanas) f.parent.parte = f.parte;
        if (f) {
            const y = fila.mapToItem(f.contentItem, 0, 0).y;
            f.contentY = Math.max(0, Math.min(y - 60, f.contentHeight - f.height));
        }
        if (fila.destello) fila.destello();
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
                    // Todas las resoluciones que da el monitor (de mayor a menor) y la nativa, la que el
                    // monitor prefiere.
                    const res = [...new Set(o.modes.slice().sort((p, q) => q.width * q.height - p.width * p.height).map(x => x.width + "x" + x.height))];
                    const pref = o.modes.find(x => x.is_preferred) || m;
                    // Una frecuencia por cada Hz redondeado (119.98 y 120.03 son "120 Hz"); se queda la exacta mas alta.
                    const porHz = {};
                    for (const x of o.modes.filter(x => x.width === m.width && x.height === m.height)) {
                        const hz = Math.round(x.refresh_rate / 1000);
                        if (!porHz[hz] || x.refresh_rate > porHz[hz]) porHz[hz] = x.refresh_rate;
                    }
                    if (porHz[Math.round(m.refresh_rate / 1000)]) porHz[Math.round(m.refresh_rate / 1000)] = m.refresh_rate;
                    const frec = Object.values(porHz).sort((a, b) => a - b);
                    r.push({ nombre: n, modelo: o.model || n, conectada: true, x: l.x, ancho: l.width, alto: l.height,
                             resoluciones: res, nativa: pref.width + "x" + pref.height, resolucion: m.width + "x" + m.height, frecuencias: frec, frecuencia: m.refresh_rate,
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
    property var conflicto: null         // { id, otro, tecla }: la combinacion nueva ya la usa "otro"
    readonly property var nombresAtajo: ({ lanzador: "Lanzador", ajustes: "Ajustes", captura: "Captura de zona", bloquear: "Bloquear",
                                           terminal: "Terminal", cerrar: "Cerrar", vista: "Vista general", maximizar: "Maximizar" })
    function nombreTeclaVista(k) {
        return ({ Mod: "Super", Period: ".", Slash: "/", Comma: ",", Space: "Espacio", Return: "Enter", Minus: "-", Equal: "=",
                  BackSpace: "Retroceso", Semicolon: ";", Apostrophe: "'" })[k] || k;
    }
    // Choque: el otro atajo se queda con la combinacion vieja de este (pasando por una tecla
    // provisional, porque niri no admite dos atajos iguales ni un momento).
    function intercambiar() {
        const c = conflicto;
        conflicto = null;
        if (!c) return;
        const vieja = atajos[c.id];
        if (!vieja) { errorAtajo = nombresAtajo[c.id] + " no tenía combinación: no hay nada que darle a " + nombresAtajo[c.otro] + "."; return; }
        cambiarAtajo.command = ["sh", "-c", 'p="$1"; shift; python3 "$p" atajo "$1" Mod+Ctrl+Alt+Shift+F12 && python3 "$p" atajo "$2" "$3" && python3 "$p" atajo "$1" "$4"',
                                "sh", Estilo.carpeta + "/menisco-niri.py", c.otro, c.id, c.tecla, vieja];
        cambiarAtajo.running = true;
    }
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
        if (!mods.length && !tecla.startsWith("F")) { errorAtajo = "Usa al menos una tecla como Super, Ctrl o Alt."; return; }
        const combo = mods.concat([tecla]).join("+");
        const igual = (x, y) => x.replace(/^(Mod|Super)\b/, "Super").toLowerCase() === y.replace(/^(Mod|Super)\b/, "Super").toLowerCase();
        const otro = Object.keys(atajos).find(k => k !== capturando && igual(atajos[k] || "", combo));
        if (otro) { conflicto = { id: capturando, otro: otro, tecla: combo }; capturando = ""; return; }
        cambiarAtajo.command = ["python3", Estilo.carpeta + "/menisco-niri.py", "atajo", capturando, combo];
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
        x: ventana.xPanel; y: ventana.yPanel
        width: ventana.anchoPanel
        height: ventana.altoPanel
        radius: 16
        color: Estilo.fondo
        border.color: Estilo.borde
        border.width: 1
        clip: true

        // Entra creciendo desde 0.9 y subiendo 20 px, con rebote; sale encogiendo un poco.
        opacity: ventana.abierta ? 1 : 0
        scale: ventana.abierta ? 1 : 0.9
        transform: Translate { y: ventana.abierta ? 0 : 20; Behavior on y { NumberAnimation { duration: Estilo.t(ventana.abierta ? 420 : 180); easing.type: ventana.abierta ? Easing.BezierSpline : Easing.InCubic; easing.bezierCurve: Estilo.curvaIos } } }
        Behavior on opacity { NumberAnimation { duration: Estilo.t(ventana.abierta ? 260 : 160); easing.type: ventana.abierta ? Easing.OutCubic : Easing.InCubic } }
        Behavior on scale { NumberAnimation { duration: Estilo.t(ventana.abierta ? 420 : 180); easing.type: ventana.abierta ? Easing.BezierSpline : Easing.InCubic; easing.bezierCurve: Estilo.curvaIos } }

        focus: ventana.abierta
        Keys.onPressed: e => {
            if (ventana.capturando) { ventana.capturar(e); e.accepted = true; }
            else if (e.key === Qt.Key_Escape && ventana.conflicto) { ventana.conflicto = null; e.accepted = true; }
            else if (e.key === Qt.Key_Escape) { if (dialogoGota.abierto) dialogoGota.cerrar(); else ventana.cerrar(); e.accepted = true; }
        }

        // Luz de arriba: muy tenue (blanco al 7 % en Ónix, el color del tema en los demas). Quieta.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: lateral.width + (panel.width - lateral.width) / 2; centerY: -40
                    centerRadius: panel.width * 0.55; focalX: centerX; focalY: centerY
                    GradientStop { position: 0; color: Qt.alpha(Estilo.luz, 0.07) }
                    GradientStop { position: 1; color: Qt.alpha(Estilo.luz, 0) }
                }
                PathRectangle { width: panel.width; height: panel.height }
            }
        }

        // Barra lateral
        Rectangle {
            id: lateral
            width: 240
            z: 2    // los resultados del buscador se salen por encima del contenido
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 1 }
            radius: 15
            color: Estilo.lateral
            Rectangle { width: 16; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } color: parent.color }
            Rectangle { width: 1; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } color: Estilo.linea }

            // Menu en tres grupos; las entradas con "cab" son los titulos de grupo. "tono": el color
            // apagado del cuadro de cada icono (el mismo en todos los temas; la elegida va en el acento).
            readonly property var menu: [
                { id: "inicio", texto: "Inicio", icono: "home", tono: "#55595f", archivo: "inicio" },
                { cab: "Aspecto" },
                { id: "apariencia", texto: "Color y estilo", icono: "palette", tono: "#6f5a96", archivo: "color" },
                { id: "vidrio", texto: "Liquid glass", icono: "water_drop", tono: "#3d6890", archivo: "glass" },
                { id: "ventanas", texto: "Ventanas y marco", icono: "select_window", tono: "#525e76", archivo: "ventanas" },
                { cab: "Partes de Menisco" },
                { id: "isla", texto: "Isla", icono: "pill", tono: "#3b3e45", archivo: "isla" },
                { id: "esquinas", texto: "Botones de arriba", icono: "grid_view", tono: "#625890", archivo: "botones" },
                { id: "dock", texto: "Dock", icono: "dock_to_bottom", tono: "#3a7564", archivo: "dock" },
                { id: "barra", texto: "Barra lateral", icono: "view_sidebar", tono: "#806a3e", archivo: "barra" },
                { cab: "Sistema" },
                { id: "notificaciones", texto: "Notificaciones", icono: "notifications", tono: "#94504c", archivo: "notif" },
                { id: "asistente", texto: "Gota", icono: "water_drop", tono: "#467f52", archivo: "gota" },
                { id: "pantallas", texto: "Pantallas", icono: "desktop_windows", tono: "#3d6399", archivo: "pantallas" },
                { id: "atajos", texto: "Atajos", icono: "keyboard", tono: "#5a5e66", archivo: "atajos" }
            ]
            readonly property var secciones: menu.filter(m => m.id)
            readonly property int indice: menu.findIndex(s => s.id === ventana.seccion)

            // Marca: el logo y la palabra oficiales (assets/menisco-logo-white.svg y la version recta
            // de assets/readme/readme-encabezado-oscuro.svg).
            Row {
                id: marcaLateral
                x: 20; y: 20
                spacing: 9
                LogoMenisco { marco: false; tam: 16; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -1.5 }
                PalabraMenisco { alto: 13; anchors.verticalCenter: parent.verticalCenter }
            }

            // Buscador: encuentra cualquier fila de cualquier seccion y lleva hasta ella.
            Item {
                id: buscador
                z: 10
                x: 14; y: marcaLateral.y + marcaLateral.height + 16
                width: lateral.width - 28
                height: 36
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
                            text: "Buscar un ajuste…"
                            color: Estilo.texto3; font: campoBuscar.font
                        }
                    }
                }
                function ir(r) { campoBuscar.text = ""; campoBuscar.focus = false; ventana.irA(r.clave, r.fila) }

                // Resultados: flotan sobre el fondo, debajo del campo.
                Rectangle {
                    visible: campoBuscar.text !== ""
                    y: parent.height + 6
                    width: 380
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

            // Una sola pastilla de seleccion que se desliza entre secciones, sin rebote.
            Rectangle {
                x: 14
                y: listaLateral.y + (repMenu.count > lateral.indice && lateral.indice >= 0 ? repMenu.itemAt(lateral.indice).y : 0)
                width: lateral.width - 28
                height: 38
                radius: 10
                color: Qt.alpha(Estilo.acento, 0.1)
                Behavior on y { NumberAnimation { duration: Estilo.t(360); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
            }

            Column {
                id: listaLateral
                x: 14
                y: buscador.y + buscador.height + 4
                width: lateral.width - 28
                spacing: 1

                Repeater {
                    id: repMenu
                    model: lateral.menu
                    delegate: Rectangle {
                        id: fila
                        required property var modelData
                        readonly property bool cab: !!modelData.cab
                        readonly property bool elegida: !cab && ventana.seccion === modelData.id

                        width: parent.width
                        height: cab ? 34 : 38
                        radius: 10
                        color: !cab && !elegida && zona.containsMouse ? Qt.alpha(Estilo.realce, 0.6) : Estilo.nada
                        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }

                        Text {   // titulo de grupo
                            visible: fila.cab
                            anchors { left: parent.left; leftMargin: 10; bottom: parent.bottom; bottomMargin: 6 }
                            text: (fila.modelData.cab || "").toUpperCase(); color: Estilo.texto2
                            font { family: Estilo.letra; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.8 }
                        }
                        // Icono de la seccion (assets/iconos-ajustes): la version "normal" y, en la
                        // elegida, la "activo" encima, con un fundido corto entre las dos.
                        Item {
                            id: cuadroIcono
                            visible: !fila.cab
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 9 }
                            width: 24; height: 24
                            readonly property string base: Qt.resolvedUrl("assets/iconos-ajustes/")
                            Image {
                                anchors.fill: parent
                                source: fila.modelData.archivo ? cuadroIcono.base + "normal/" + fila.modelData.archivo + ".svg" : ""
                                sourceSize: Qt.size(48, 48); smooth: true; mipmap: true
                            }
                            Image {
                                anchors.fill: parent
                                source: fila.modelData.archivo ? cuadroIcono.base + "activo/" + fila.modelData.archivo + ".svg" : ""
                                sourceSize: Qt.size(48, 48); smooth: true; mipmap: true
                                opacity: fila.elegida ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Estilo.t(180); easing.type: Easing.OutCubic } }
                            }
                        }
                        Text {
                            visible: !fila.cab
                            anchors { verticalCenter: parent.verticalCenter; left: cuadroIcono.right; leftMargin: 11 }
                            text: modelData.texto || ""
                            color: Estilo.texto
                            font { family: Estilo.letra; pixelSize: 14; weight: fila.elegida ? Font.DemiBold : Font.Normal; letterSpacing: -0.1 }
                        }
                        MouseArea { cursorShape: Qt.PointingHandCursor; id: zona; enabled: !fila.cab; anchors.fill: parent; hoverEnabled: true; onClicked: ventana.seccion = modelData.id }
                    }
                }
            }
        }

        // Contenido
        Item {
            id: contenido
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right; left: lateral.right; margins: 16 }

            // ---------------- Color y estilo ----------------
            Pagina {
                id: paginaApariencia
                anchors.fill: parent
                clave: "apariencia"; activa: ventana.seccion === clave
                // Perfil en edicion (nombre) y el que muestra sus acciones (clic derecho)
                property int perfilRenombrando: -1
                property int perfilMenu: -1
                readonly property var nombresMaterial: ({ vidrio: "vidrio", solido: "sólido", ahumado: "ahumado", escarcha: "escarcha",
                                                          tinte: "tinte", contorno: "contorno", materialyou: "Material You" })
                // Si el tema elegido es de los de "Mostrar más", la lista se abre sola al entrar.
                property bool masTemas: false
                onActivaChanged: if (activa && Estilo.ordenTemas.indexOf(Estilo.valor("tema")) >= 6) masTemas = true
                Desplazable {
                    EncabezadoParte { grupo: "Aspecto"; titulo: "Color y estilo" }
                    Item { width: 1; height: 18 }

                    // Cabecera: logo y nombre, la Gota (la unica luz) con su rayo y su halo, y la ficha del tema.
                    Rectangle {
                        id: tarjetaMarca
                        width: parent.width; height: 210; radius: 18
                        color: Estilo.fondo; border.width: 1; border.color: Estilo.borde
                        clip: true
                        readonly property real xGota: width * 0.66
                        readonly property real yGota: height / 2
                        // Halo: luz suave alrededor de la Gota. Quieto.
                        Halo { anchors.fill: parent; cx: tarjetaMarca.xGota; cy: tarjetaMarca.yGota; radio: 130 }
                        // Rayo: una linea fina que llega a la Gota desde abajo a la izquierda. Quieto.
                        Rectangle {
                            readonly property real x1: tarjetaMarca.width * 0.04
                            readonly property real y1: tarjetaMarca.height
                            readonly property real x2: tarjetaMarca.xGota - 50
                            readonly property real y2: tarjetaMarca.yGota + 8
                            x: x1; y: y1 - height / 2
                            width: Math.hypot(x2 - x1, y2 - y1); height: 1.6; radius: 0.8
                            transformOrigin: Item.Left
                            rotation: Math.atan2(y2 - y1, x2 - x1) * 180 / Math.PI
                            antialiasing: true
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Qt.alpha(Estilo.acento2, 0) }
                                GradientStop { position: 0.4; color: Qt.alpha(Estilo.acento2, 0.55) }
                                GradientStop { position: 1; color: Qt.alpha(Estilo.acento, 0.75) }
                            }
                        }
                        Column {
                            x: 40; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -6
                            spacing: 16
                            Row {
                                spacing: 18
                                LogoMenisco { tam: 56; anchors.verticalCenter: parent.verticalCenter }
                                PalabraMenisco { alto: 38; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Texto { text: "Lo justo, en su sitio."; color: Estilo.texto2; font.pixelSize: 17 }
                        }
                        // La Gota de verdad: solo su dibujo, con el color del tema (oscura en Ónix).
                        Asistente {
                            width: 110; height: 110
                            x: tarjetaMarca.xGota - width / 2; y: tarjetaMarca.yGota - height / 2
                            emocion: "normal"; fondoNegro: true
                            mirada: ({ y: 0.6, p: -0.3 })   // siempre hacia arriba a la derecha
                            gota: ({ forma: Estilo.gota.forma, cambia: false,
                                     color: Estilo.valor("tema") === "onix" ? "#2c2c2e" : String(Estilo.acento) })
                        }
                        // Ficha del tema, como una etiqueta de especificaciones.
                        Rectangle {
                            id: ficha
                            anchors { right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter }
                            width: 176; height: 162; radius: 12; color: "#ececec"
                            readonly property int numero: Math.max(0, Estilo.ordenTemas.indexOf(Estilo.valor("tema"))) + 1
                            Column {
                                x: 16; y: 16; spacing: 2
                                Repeater {
                                    model: ["MENISCO", "APARIENCIA"]
                                    Text { required property string modelData; text: modelData; color: "#1c1c1e"; font { family: "JetBrains Mono"; pixelSize: 11; letterSpacing: 0.6 } }
                                }
                                // El nombre del tema entra por abajo y el anterior se va por arriba.
                                Rodillo {
                                    valor: (Estilo.temas[Estilo.valor("tema")] || Estilo.temas.onix).nombre.toUpperCase()
                                    color: "#1c1c1e"; fuente.family: "JetBrains Mono"; fuente.pixelSize: 11; fuente.letterSpacing: 0.6
                                }
                            }
                            Rectangle {
                                x: 16; anchors { bottom: parent.bottom; bottomMargin: 18 }
                                width: 18; height: 18; radius: 9
                                color: Estilo.valor("tema") === "onix" ? "#2c2c2e" : Estilo.acento
                            }
                            // El numero, cifra por cifra: la primera rueda hacia arriba y la segunda hacia abajo.
                            Row {
                                anchors { right: parent.right; rightMargin: 16; bottom: parent.bottom; bottomMargin: 8 }
                                spacing: -1.5
                                Repeater {
                                    model: 2
                                    Rodillo {
                                        required property int index
                                        valor: String(ficha.numero).padStart(2, "0")[index]
                                        sentido: index === 0 ? 1 : -1; centrar: true
                                        color: "#111113"; fuente.family: Estilo.letra; fuente.pixelSize: 58; fuente.weight: Font.Bold
                                    }
                                }
                            }
                        }
                    }

                    // Color: seis temas a la vista y el resto con "Mostrar más".
                    Item {
                        width: parent.width; height: 52
                        Texto { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 10 } text: "Color"; font { pixelSize: 17; weight: Font.DemiBold } }
                        Texto { anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 11 } text: "Un toque y cambia todo"; color: Estilo.texto2 }
                    }
                    Revelar {
                    abierto: paginaApariencia.masTemas; visibles: 6
                    Grid {
                        id: rejillaTemas
                        width: parent.width; columns: 6; spacing: 12
                        readonly property real ancho: (width - spacing * 5) / 6
                        Repeater {
                            model: Estilo.ordenTemas
                            delegate: Rectangle {
                                id: muestra
                                required property string modelData
                                readonly property var t: Estilo.temas[modelData]
                                readonly property bool elegido: Estilo.valor("tema") === modelData
                                readonly property bool esOnix: modelData === "onix"
                                function mezcla(a, b, k) { const x = Qt.color(a), y = Qt.color(b); return Qt.rgba(x.r + (y.r - x.r) * k, x.g + (y.g - x.g) * k, x.b + (y.b - x.b) * k, 1); }
                                // Franja de cuatro tonos: acento, acento2, un intermedio oscuro y uno claro.
                                readonly property var tonos: esOnix ? ["#f2f2f3", "#8e8e93", "#3a3a3c", "#000000"]
                                    : [t.acento, t.acento2, mezcla(mezcla(t.acento, t.acento2, 0.5), t.fondo, 0.7), mezcla(t.acento, "#ffffff", 0.45)]
                                width: rejillaTemas.ancho; height: 152; radius: 14
                                color: zonaTema.containsMouse && !elegido ? Estilo.realce : Estilo.tarjeta
                                border.width: elegido ? 2 : 1
                                border.color: elegido ? (esOnix ? "#f2f2f3" : t.acento) : Estilo.borde
                                Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                                Text {
                                    x: 16; y: 12
                                    text: "Aa"; color: muestra.esOnix ? "#f2f2f3" : muestra.t.acento
                                    font { family: Estilo.letra; pixelSize: 34; weight: Font.DemiBold; letterSpacing: -0.5 }
                                }
                                Row {
                                    x: 16; y: 66; spacing: 5
                                    Repeater {
                                        model: muestra.tonos
                                        Rectangle {
                                            required property var modelData
                                            width: (muestra.width - 32 - 15) / 4; height: 5; radius: 2.5
                                            color: modelData
                                            border.width: Qt.colorEqual(modelData, "#000000") ? 1 : 0; border.color: Estilo.borde
                                        }
                                    }
                                }
                                Column {
                                    x: 16; anchors { bottom: parent.bottom; bottomMargin: 16 }
                                    width: parent.width - 32; spacing: 2
                                    Texto { text: muestra.t.nombre; font { pixelSize: 15; weight: Font.DemiBold }
                                    width: parent.width; elide: Text.ElideRight }
                                    Texto { text: muestra.t.desc || ""; color: Estilo.texto2; font.pixelSize: 12; width: parent.width; elide: Text.ElideRight }
                                }
                                MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaTema; anchors.fill: parent; hoverEnabled: true; onClicked: Estilo.poner("tema", muestra.modelData) }
                            }
                        }
                    }
                    }
                    MostrarMas {
                        linea: false; abierto: paginaApariencia.masTemas; cuantas: Estilo.ordenTemas.length - 6
                        onPulsado: paginaApariencia.masTemas = !paginaApariencia.masTemas
                    }

                    // Ajuste fino, en tabla: numero, ajuste, que hace y como esta ahora.
                    Texto { text: "Ajuste fino"; topPadding: 10; bottomPadding: 10; font { pixelSize: 17; weight: Font.DemiBold } }
                    TablaAjustes {
                    FilaTabla {
                        numero: 1; titulo: "Superficies"; que: "Qué tan negro es el fondo de ventanas y tarjetas"
                        Desplegable {
                            readonly property bool esOnix: Estilo.valor("tema") === "onix"
                            enabled: !esOnix; opacity: esOnix ? 0.55 : 1
                            opciones: [["negro", "Negro puro"], ["suave", "Suave"]]
                            elegida: esOnix ? "negro" : Estilo.valor("superficies")
                            onElegir: c => Estilo.poner("superficies", c)
                        }
                    }
                    FilaTabla {
                        numero: 2; titulo: "Letra"; que: "La misma letra en todo el shell"
                        Desplegable {
                            opciones: [["SF Pro", "SF Pro"], ["Inter", "Inter"]]
                            elegida: Estilo.valor("letra"); onElegir: c => Estilo.poner("letra", c)
                        }
                    }
                    FilaTabla {
                        numero: 3; titulo: "Movimiento"
                        // Tres maneras de moverse; cada una pone la velocidad y el rebote de siempre.
                        readonly property var modos: ({ calmado: ["normal", "nada"], normal: ["normal", "suave"], vivo: ["rapida", "mucho"] })
                        readonly property string modo: Object.keys(modos).find(k => modos[k][0] === Estilo.valor("velocidad") && modos[k][1] === Estilo.valor("rebote")) ?? "personalizado"
                        que: ({ calmado: "Tranquilo: una sola cosa se mueve a la vez", normal: "Con un rebote suave al llegar", vivo: "Rápido y con más rebote" })[modo]
                            ?? "Velocidad y rebote elegidos a mano"
                        Desplegable {
                            opciones: [["calmado", "Calmado"], ["normal", "Normal"], ["vivo", "Vivo"]]
                            elegida: parent.parent.modo
                            textoOtro: "Personalizado"
                            onElegir: c => { const m = parent.parent.modos[c]; Estilo.poner("velocidad", m[0]); Estilo.poner("rebote", m[1]); }
                        }
                    }
                    FilaTabla {
                        numero: 4; titulo: "Seguir al fondo"
                        readonly property bool conFondo: Estilo.valor("tema") === "delfondo"
                        que: conFondo ? "Si cambias de fondo, el color cambia con él" : "Solo con el color Del fondo"
                        Llave {
                            enabled: parent.parent.conFondo; opacity: enabled ? 1 : 0.4
                            encendido: Estilo.valor("seguirFondo")
                            // Al apagarlo se guarda el color de ahora, para que no cambie mas.
                            onCambiar: v => { if (!v) { Estilo.poner("fondoAcento", String(Estilo.acentoFondo)); Estilo.poner("fondoAcento2", String(Estilo.acento2Fondo)); } Estilo.poner("seguirFondo", v); }
                        }
                    }
                    }

                    Encabezado { text: "Perfiles"; topPadding: 22 }
                    Plegable {
                        icono: "bookmarks"; titulo: "Perfiles guardados"; relleno: 12
                        resumen: Estilo.perfiles.length + (Estilo.perfiles.length === 1 ? " perfil" : " perfiles") + " · guardan color, dock, isla, botones y marco"
                        Texto {
                            text: "Un perfil guarda toda la apariencia: tema, dock, isla, botones, marco, ventanas y vidrio. Haz clic para aplicarlo; clic derecho para renombrarlo, actualizarlo o borrarlo."
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
                    }
                }
            }

            // ---------------- Ventanas y marco ----------------
            Pagina {
                anchors.fill: parent
                clave: "ventanas"; activa: ventana.seccion === clave
                Desplazable {
                    EncabezadoParte { grupo: "Aspecto"; titulo: "Ventanas y marco"; descripcion: "Bordes, espacio entre ventanas y el marco alrededor de la pantalla." }
                    Item { width: 1; height: 18 }
                    // Vista previa en vivo: una pantalla en miniatura con la isla y tres ventanas en mosaico.
                    Escenario {
                        height: 300
                        Item {
                            id: miniPantalla
                            // Escala de la pantalla real (1920) a la miniatura; espacio y esquinas se exageran
                            // un poco para que se vean al cambiar.
                            readonly property real k: width / 1920
                            readonly property real e: 1.8
                            readonly property bool marco: Estilo.valor("marco")
                            readonly property real m: marco ? 4 : 0
                            readonly property real g: ctlEspacio.vivo * k * e
                            readonly property real r: ctlEsquinas.vivo * k * e
                            readonly property real filo: ctlBorde.vivo / 100
                            width: 480; height: 270
                            x: (parent.width - width - 190) / 2; anchors.verticalCenter: parent.verticalCenter
                            ClippingRectangle {
                                anchors.fill: parent; radius: 12; color: "#000000"
                                Image {
                                    anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                                    source: ventana.fondoActual ? "file://" + ventana.fondoActual : ""; sourceSize.width: 960
                                }
                                Rectangle { anchors.fill: parent; color: "#80000000" }
                                // Tres ventanas: una grande a la izquierda (la activa) y dos apiladas.
                                Item {
                                    id: zonaVentanas
                                    x: miniPantalla.m + miniPantalla.g
                                    y: miniPantalla.m + 13 + miniPantalla.g
                                    width: parent.width - 2 * (miniPantalla.m + miniPantalla.g)
                                    height: parent.height - y - miniPantalla.m - miniPantalla.g
                                    Repeater {
                                        model: 3
                                        delegate: Rectangle {
                                            required property int index
                                            readonly property real anchoIzq: (zonaVentanas.width - miniPantalla.g) * 0.56
                                            readonly property real altoDer: (zonaVentanas.height - miniPantalla.g) / 2
                                            x: index === 0 ? 0 : anchoIzq + miniPantalla.g
                                            y: index === 2 ? altoDer + miniPantalla.g : 0
                                            width: index === 0 ? anchoIzq : zonaVentanas.width - anchoIzq - miniPantalla.g
                                            height: index === 0 ? zonaVentanas.height : altoDer
                                            radius: miniPantalla.r
                                            color: "#0e0e10"
                                            border.width: index === 0 ? 1.5 : 1
                                            border.color: index === 0 ? Qt.rgba(1, 1, 1, Math.max(0.08, miniPantalla.filo)) : "#14ffffff"
                                            Row { visible: index === 0; x: 10; y: 9; spacing: 4; Repeater { model: 2; Rectangle { width: 5; height: 5; radius: 2.5; color: "#55ffffff" } } }
                                            Column {
                                                x: 12; y: index === 0 ? 22 : 12; spacing: 6
                                                Repeater {
                                                    model: index === 0 ? [0.55, 0.75, 0.4] : [0.45]
                                                    Rectangle { required property real modelData; width: (parent.parent.width - 24) * modelData; height: 3; radius: 1.5; color: "#3dffffff" }
                                                }
                                            }
                                        }
                                    }
                                }
                                // Marco de pantalla: borde negro alrededor; la isla sale de el.
                                Rectangle {
                                    visible: miniPantalla.marco
                                    anchors.fill: parent; color: "transparent"; radius: 12
                                    border.width: miniPantalla.m; border.color: Estilo.fondo
                                }
                                IslaMini {
                                    anchors.horizontalCenter: parent.horizontalCenter; y: miniPantalla.m
                                    ancho: 74; alto: 13; esquina: 6; hombro: 6
                                }
                            }
                            Behavior on x { NumberAnimation { duration: Estilo.t(200) } }
                        }
                        // Resumen en vivo
                        Column {
                            anchors { left: miniPantalla.right; leftMargin: 34; verticalCenter: parent.verticalCenter }
                            spacing: 9
                            Texto { text: "EN VIVO"; color: Estilo.texto2; font { pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.8 } }
                            Repeater {
                                model: [["Esquinas", Math.round(ctlEsquinas.vivo) + " px"], ["Espacio", Math.round(ctlEspacio.vivo) + " px"],
                                        ["Filo activo", Math.round(ctlBorde.vivo) + " %"], ["Marco", Estilo.valor("marco") ? "Sí" : "No"]]
                                Row {
                                    required property var modelData
                                    spacing: 6
                                    Texto { text: modelData[0]; color: Estilo.texto2; font.pixelSize: 14 }
                                    Texto { text: modelData[1]; font { pixelSize: 14; weight: Font.DemiBold } }
                                }
                            }
                        }
                    }
                    Item { width: 1; height: 8 }
                    TablaAjustes {
                        FilaTabla {
                            numero: 1; titulo: "Marco de pantalla"; que: "Borde alrededor del monitor; la isla sale de él"
                            Llave { encendido: Estilo.valor("marco"); onCambiar: v => Estilo.poner("marco", v) }
                        }
                        FilaTabla {
                            numero: 2; titulo: "Esquinas"; que: "Qué tan redondas son las ventanas"
                            ControlDeslizador {
                                id: ctlEsquinas; desde: 0; hasta: 24; unidad: " px"; valor: ventana.esquinas
                                onSoltado: v => { ventana.esquinas = v; Estilo.poner("esquinas", v); Estilo.niri(["esquinas", v]); }
                            }
                        }
                        FilaTabla {
                            numero: 3; titulo: "Espacio entre ventanas"; que: "El aire entre una ventana y otra"
                            ControlDeslizador {
                                id: ctlEspacio; desde: 0; hasta: 32; unidad: " px"; valor: Estilo.valor("espacio")
                                onSoltado: v => { Estilo.poner("espacio", v); Estilo.niri(["espacio", v]); }
                            }
                        }
                        FilaTabla {
                            numero: 4; titulo: "Borde de la ventana activa"; que: "Qué tan visible es el filo blanco"
                            ControlDeslizador {
                                id: ctlBorde; desde: 0; hasta: 100; unidad: " %"; valor: Estilo.valor("borde")
                                onSoltado: v => { Estilo.poner("borde", v); Estilo.niri(["borde", v]); }
                            }
                        }
                    }
                    Item { width: 1; height: 12 }
                }
            }

            // ---------------- Dock ----------------
            Pagina {
                anchors.fill: parent
                id: paginaDock
                clave: "dock"; activa: ventana.seccion === clave
                readonly property string material: Estilo.valor("dockMaterial")
                readonly property bool conVidrio: Estilo.dockConVidrio(material)
                readonly property var materiales: [["vidrio", "Vidrio", "De fábrica"], ["ahumado", "Ahumado", "Vidrio oscuro"],
                    ["escarcha", "Escarcha", "Vidrio claro"], ["tinte", "Tinte", "Color del tema"],
                    ["solido", "Sólido", "Negro, como la isla"], ["contorno", "Contorno", "Solo el filo"], ["materialyou", "Material You", "Del color de tu fondo"]]
                Desplazable {
                    EncabezadoParte { grupo: "Partes de Menisco"; titulo: "Dock"; descripcion: "La pieza de vidrio de Menisco: qué material lleva, dónde va y cómo se comporta." }
                    Item { width: 1; height: 18 }
                    // Vista previa: el fondo real con el dock encima, en el material, tamaño e indicadores elegidos.
                    Escenario {
                        height: 240
                        MuestraDock {
                            anchors { fill: parent; margins: 1 } radius: 17
                            material: paginaDock.material; icono: Estilo.valor("dockIcono"); indicadores: true
                        }
                        Rectangle {
                            x: 16; y: 16
                            width: textoMaterial.implicitWidth + 26; height: 32; radius: 16
                            color: "#cc000000"; border.width: 1; border.color: "#26ffffff"
                            Text {
                                id: textoMaterial
                                anchors.centerIn: parent
                                text: (paginaDock.materiales.find(m => m[0] === paginaDock.material) || ["", "Vidrio"])[1]
                                    + " · " + Estilo.valor("dockIcono") + " px · aumento " + (Estilo.valor("dockAumento") ? "activado" : "apagado")
                                color: "#ffffff"; font { family: Estilo.letra; pixelSize: 13; weight: Font.DemiBold }
                            }
                        }
                    }
                    Item {
                        width: parent.width; height: 52
                        Texto { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 10 } text: "Material"; font { pixelSize: 17; weight: Font.DemiBold } }
                        Texto { anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 11 } text: "El vidrio es la firma de Menisco"; color: Estilo.texto2 }
                    }
                    // Siete materiales en una fila: cuatro con vidrio y tres sin vidrio.
                    Item {
                        id: filaMateriales
                        width: parent.width; height: 32
                        readonly property real ancho: (width - 6 * 10) / 7
                        Repeater {
                            model: [["CON VIDRIO", 0, 4], ["SIN VIDRIO", 4, 3]]
                            Item {
                                required property var modelData
                                x: modelData[1] * (filaMateriales.ancho + 10); width: modelData[2] * (filaMateriales.ancho + 10) - 10; height: 32
                                Texto { anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; color: Estilo.texto2; font { pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.8 } }
                                Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: 4; width: parent.width; height: 1; color: Estilo.linea }
                            }
                        }
                    }
                    Row {
                        spacing: 10
                        Repeater {
                            model: paginaDock.materiales
                            delegate: TarjetaMaterial { width: filaMateriales.ancho }
                        }
                    }
                    Texto { text: "Ajuste fino"; topPadding: 20; bottomPadding: 6; font { pixelSize: 17; weight: Font.DemiBold } }
                    TablaAjustes {
                        FilaTabla {
                            id: filaPosicion
                            numero: 1; titulo: "Posición"
                            que: "Flota sobre el escritorio o se pega al borde de la pantalla"
                            readonly property bool posible: Estilo.grosorMarco > 0 && !paginaDock.conVidrio
                            height: posible ? 62 : 82
                            Column {
                                spacing: 6
                                ControlSegmentos {
                                    anchors.right: parent.right
                                    grande: true
                                    opciones: ["Flotante", "Pegado al borde"]; claves: [false, true]
                                    apagadas: filaPosicion.posible ? [] : [true]
                                    elegida: Estilo.dockPegado
                                    onElegir: c => Estilo.poner("dockPegado", c)
                                }
                                Texto {
                                    visible: !filaPosicion.posible
                                    anchors.right: parent.right
                                    text: Estilo.grosorMarco > 0 ? "Pegado necesita un material sin vidrio" : "Pegado necesita el marco de pantalla"
                                    color: Estilo.texto2; font.pixelSize: 12
                                }
                            }
                        }
                        FilaTabla {
                            numero: 2; titulo: "Forma"
                            atenuada: paginaDock.conVidrio
                            que: paginaDock.conVidrio ? "Solo sin vidrio: el vidrio va redondeado" : "El contorno del dock"
                            Desplegable {
                                opciones: Estilo.formasDock
                                elegida: Estilo.valor("dockForma"); onElegir: c => Estilo.poner("dockForma", c)
                            }
                        }
                        FilaTabla {
                            numero: 3; titulo: "Tamaño de íconos"; que: "De 40 a 64 px; el dock crece con ellos"
                            ControlDeslizador { desde: 40; hasta: 64; valor: Estilo.valor("dockIcono"); unidad: " px"; onSoltado: v => Estilo.poner("dockIcono", Math.round(v)) }
                        }
                        FilaTabla {
                            numero: 4; titulo: "Aumento"; que: "Agranda un poco el ícono que tiene el cursor"
                            Llave { encendido: Estilo.valor("dockAumento"); onCambiar: v => Estilo.poner("dockAumento", v) }
                        }
                        FilaTabla {
                            numero: 5; titulo: "Ocultar"; que: "Cuándo se esconde el dock"
                            Desplegable {
                                opciones: [["nunca", "Nunca"], ["siempre", "Siempre"], ["ventana", "Si una ventana lo toca"]]
                                elegida: Estilo.valor("dockOcultar"); onElegir: c => Estilo.poner("dockOcultar", c)
                            }
                        }
                        FilaTabla {
                            numero: 6; titulo: "Indicadores"; que: "Cómo se marcan las apps abiertas"
                            ControlSegmentos {
                                grande: true
                                opciones: ["Punto", "Píldora en la enfocada"]; claves: ["punto", "pildora"]
                                elegida: Estilo.valor("dockIndicador"); onElegir: c => Estilo.poner("dockIndicador", c)
                            }
                        }
                        FilaTabla {
                            numero: 7; titulo: "Apps sin fijar"; que: "Muestra las apps abiertas que no están fijadas, tras un separador"
                            Llave { encendido: Estilo.valor("dockSinFijar"); onCambiar: v => Estilo.poner("dockSinFijar", v) }
                        }
                    }
                    Item {
                        width: parent.width; height: 56
                        Texto { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 10 } text: "Avanzado"; font { pixelSize: 17; weight: Font.DemiBold } }
                        Texto { anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 11 } text: "Para cuando quieras afinar más"; color: Estilo.texto2 }
                    }
                    Avanzado {
                        FilaTabla {
                            sinNumero: true; titulo: "Retraso al ocultar"; que: "Cuánto espera antes de esconderse"
                            atenuada: Estilo.valor("dockOcultar") === "nunca"
                            Desplegable {
                                opciones: [[0, "Al instante"], [150, "150 ms"], [300, "300 ms"], [600, "600 ms"], [1000, "1 s"]]
                                textoOtro: Estilo.valor("dockRetraso") + " ms"
                                elegida: Estilo.valor("dockRetraso"); onElegir: c => Estilo.poner("dockRetraso", c)
                            }
                        }
                        FilaTabla {
                            sinNumero: true; titulo: "Clic en app abierta"; que: "Qué pasa al pulsar una app que ya está en pantalla"
                            Desplegable {
                                opciones: [["enfocar", "Enfocar"], ["siguiente", "Siguiente ventana"]]
                                elegida: Estilo.valor("dockClic"); onElegir: c => Estilo.poner("dockClic", c)
                            }
                        }
                        FilaTabla {
                            sinNumero: true; titulo: "Nombre al pasar el cursor"; que: "Etiqueta encima del ícono"
                            Llave { encendido: Estilo.valor("dockNombre"); onCambiar: v => Estilo.poner("dockNombre", v) }
                        }
                        FilaTabla {
                            sinNumero: true; titulo: "Monitor"; que: "En qué pantalla aparece"
                            Desplegable {
                                opciones: [["", "Todas"], ["principal", "Principal"]].concat(Array.from(Quickshell.screens).map(p => [p.name, p.name]))
                                textoOtro: Estilo.valor("dockMonitor")
                                elegida: Estilo.valor("dockMonitor"); onElegir: c => Estilo.poner("dockMonitor", c)
                            }
                        }
                    }
                    Item { width: 1; height: 16 }
                }
            }

            // ---------------- Pantallas ----------------
            Pagina {
                anchors.fill: parent
                clave: "pantallas"; activa: ventana.seccion === clave
                onActivaChanged: if (activa) leerSalidas.running = true
                Desplazable {
                    EncabezadoParte { grupo: "Sistema"; titulo: "Pantallas"; descripcion: "Resolución, frecuencia y dónde va cada monitor." }
                    Item { width: 1; height: 18 }
                    // Vista previa: los monitores dibujados como pantallas, del tamaño de su resolucion.
                    Escenario {
                        height: 320
                        Item {
                            id: mapa
                            anchors { fill: parent; margins: 24; bottomMargin: 44 }
                            readonly property int separacion: 26
                            readonly property real anchoTotal: Math.max(1, ventana.salidas.reduce((s, o) => s + o.ancho, 0))
                            readonly property real altoMax: Math.max(1, ...ventana.salidas.map(o => o.alto))
                            readonly property real k: Math.min((width - separacion * Math.max(0, ventana.salidas.length - 1)) / anchoTotal, (height - 62) / altoMax)
                            readonly property real x0: (width - anchoTotal * k - separacion * Math.max(0, ventana.salidas.length - 1)) / 2
                            readonly property var conectadas: ventana.salidas.filter(o => o.conectada)
                            Repeater {
                                model: ventana.salidas
                                delegate: Item {
                                    id: caja
                                    required property var modelData
                                    required property int index
                                    readonly property bool elegida: modelData.nombre === ventana.salidaElegida
                                    readonly property bool principal: modelData.principal || (mapa.conectadas.length === 1 && modelData.conectada)
                                    width: modelData.ancho * mapa.k; height: modelData.alto * mapa.k + 62
                                    x: mapa.x0 + modelData.x * mapa.k + index * mapa.separacion
                                    y: (mapa.altoMax - modelData.alto) * mapa.k
                                    opacity: modelData.conectada ? 1 : 0.55
                                    Behavior on x { enabled: !arrastre.active; NumberAnimation { duration: Estilo.t(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                                    ClippingRectangle {
                                        id: pantallaMon
                                        width: parent.width; height: caja.modelData.alto * mapa.k; radius: 10
                                        color: caja.modelData.conectada ? "#000000" : "transparent"
                                        border.width: caja.elegida ? 2 : caja.modelData.conectada ? 1 : 0
                                        border.color: caja.elegida ? Estilo.acento : Estilo.borde
                                        Image {
                                            visible: caja.modelData.conectada
                                            anchors { fill: parent; margins: caja.elegida ? 2 : 1 }
                                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                                            source: ventana.fondoActual ? "file://" + ventana.fondoActual : ""; sourceSize.width: 640
                                        }
                                        Shape {   // la muesca de la isla
                                            visible: caja.modelData.conectada
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 60; height: 11
                                            preferredRendererType: Shape.CurveRenderer
                                            ShapePath { strokeWidth: -1; fillColor: "#000000"; PathSvg { path: "M0 0 H60 L52 11 H8 Z" } }
                                        }
                                        Shape {   // desconectado: borde punteado
                                            visible: !caja.modelData.conectada
                                            anchors.fill: parent
                                            preferredRendererType: Shape.CurveRenderer
                                            ShapePath {
                                                fillColor: "transparent"; strokeColor: Qt.alpha(Estilo.texto, 0.4); strokeWidth: 1.5
                                                strokeStyle: ShapePath.DashLine; dashPattern: [3, 3]
                                                PathRectangle { x: 0.75; y: 0.75; width: pantallaMon.width - 1.5; height: pantallaMon.height - 1.5; radius: 9 }
                                            }
                                        }
                                        Texto { visible: !caja.modelData.conectada; anchors.centerIn: parent; text: "Sin señal"; color: Estilo.texto2 }
                                        Rectangle {
                                            visible: caja.principal
                                            anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
                                            width: filaPrincipal.width + 18; height: 24; radius: 12
                                            color: "#cc000000"; border.width: 1; border.color: "#33ffffff"
                                            Row {
                                                id: filaPrincipal
                                                anchors.centerIn: parent; spacing: 4
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: "★"; color: "#ffffff"; font.pixelSize: 11 }
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: "Principal"; color: "#ffffff"; font { family: Estilo.letra; pixelSize: 12; weight: Font.DemiBold } }
                                            }
                                        }
                                    }
                                    // Pie del monitor
                                    Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: pantallaMon.height + 8; width: Math.min(70, parent.width * 0.3); height: 5; radius: 2.5; color: Estilo.hover }
                                    Column {
                                        anchors.horizontalCenter: parent.horizontalCenter; y: pantallaMon.height + 20
                                        spacing: 1
                                        Texto { anchors.horizontalCenter: parent.horizontalCenter; text: caja.modelData.modelo; font { pixelSize: 14; weight: Font.DemiBold } }
                                        Texto {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: caja.modelData.conectada
                                                ? caja.modelData.nombre + " · " + caja.modelData.resolucion.replace("x", " × ") + " · " + Math.round(caja.modelData.frecuencia / 1000) + " Hz"
                                                : "Desconectado"
                                            color: Estilo.texto2; font.pixelSize: 12
                                        }
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
                        }
                        Texto { anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 } text: "Arrastra los monitores para acomodarlos."; color: Estilo.texto2; font.pixelSize: 13 }
                    }
                    Item {
                        visible: !!ventana.salidaActual
                        width: parent.width; height: 56
                        Texto { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 10 } text: ventana.salidaActual ? ventana.salidaActual.modelo : ""; font { pixelSize: 17; weight: Font.DemiBold } }
                        Texto { anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 11 } text: ventana.salidaActual ? ventana.salidaActual.nombre : ""; color: Estilo.texto2 }
                    }
                    TablaAjustes {
                        visible: !!ventana.salidaActual
                        FilaTabla {
                            numero: 1; titulo: "Resolución"; que: "Los píxeles de la pantalla"
                            Desplegable {
                                opciones: ventana.salidaActual ? ventana.salidaActual.resoluciones.map(r => [r, r.replace("x", " × ") + (r === ventana.salidaActual.nativa ? " (nativa)" : "")]) : []
                                elegida: ventana.salidaActual ? ventana.salidaActual.resolucion : ""
                                onElegir: c => ventana.ponerModo(c, null)
                            }
                        }
                        FilaTabla {
                            numero: 2; titulo: "Frecuencia"; que: "Cuántas veces por segundo se dibuja"
                            ControlSegmentos {
                                grande: true
                                opciones: ventana.salidaActual ? ventana.salidaActual.frecuencias.map(f => Math.round(f / 1000) + " Hz") : []
                                claves: ventana.salidaActual ? ventana.salidaActual.frecuencias : []
                                elegida: ventana.salidaActual ? ventana.salidaActual.frecuencia : 0
                                onElegir: c => ventana.ponerModo(null, c)
                            }
                        }
                        FilaTabla {
                            numero: 3; titulo: "Escala"; que: "El tamaño de todo lo que ves"
                            ControlSegmentos {
                                grande: true
                                opciones: ["100 %", "125 %", "150 %"]; claves: [1, 1.25, 1.5]
                                elegida: ventana.salidaActual ? ventana.salidaActual.escala : 1
                                onElegir: c => { Estilo.niri(["salida", ventana.salidaElegida, "escala", String(c)]); releerSalidas.restart(); }
                            }
                        }
                        FilaTabla {
                            numero: 4; titulo: "Monitor principal"; que: "Donde salen la isla y el dock"
                            // Con un solo monitor conectado, ese es el principal.
                            readonly property var conectadas: ventana.salidas.filter(o => o.conectada)
                            Desplegable {
                                opciones: parent.parent.conectadas.map(o => [o.nombre, o.modelo])
                                elegida: (ventana.salidas.find(o => o.principal && o.conectada) || (parent.parent.conectadas.length === 1 ? parent.parent.conectadas[0] : {})).nombre || ""
                                textoOtro: "Sin elegir"
                                onElegir: c => { Estilo.niri(["salida", c, "principal"]); releerSalidas.restart(); }
                            }
                        }
                    }
                    Item { width: 1; height: 16 }
                }
            }

            // ---------------- Isla ----------------
            Pagina {
                id: paginaIsla
                anchors.fill: parent
                clave: "isla"; activa: ventana.seccion === clave
                property string huecoElegido: "izquierda"
                property bool masPiezas: false
                // [clave, nombre, icono]
                // Las cinco primeras se ven siempre; las demas, con "Mostrar más".
                readonly property var catalogo: [["hora", "Hora", "schedule"], ["fecha", "Fecha y hora", "calendar_today"], ["volumen", "Volumen", "volume_up"],
                    ["visualizador", "Visualizador", "graphic_eq"], ["caratula", "Reproductor", "play_circle"],
                    ["asistente", "Gota", "face"], ["temperatura", "Temperatura", "thermostat"], ["cpu", "Uso de CPU", "memory"],
                    ["escritorios", "Escritorios", "view_week"], ["clima", "Clima", "partly_cloudy_day"], ["red", "Red", "arrow_downward"], ["ram", "RAM", "memory_alt"],
                    ["micro", "Micrófono", "mic_off"], ["bateria", "Batería", "headphones"], ["nada", "Nada", "block"]]
                function nombreForma(k) { return ((Estilo.formasIsla.find(f => f[0] === k) || ["", k])[1] || "").toLowerCase() }
                // Cuando aparece cada contenido en la isla pequeña.
                readonly property var cuando: ({ hora: "Siempre", fecha: "Solo en el centro", volumen: "Siempre", visualizador: "Con música",
                    caratula: "Con música", asistente: "Siempre", temperatura: "Siempre", cpu: "Siempre", escritorios: "Siempre",
                    clima: "Con conexión", red: "Con conexión", ram: "Siempre", micro: "Si está silenciado", bateria: "Con algo conectado", nada: "Hueco vacío" })
                Desplazable {
                    EncabezadoParte { grupo: "Partes de Menisco"; titulo: "Isla"; descripcion: "La píldora de arriba: qué enseña y cómo se abre." }
                    Item { width: 1; height: 18 }
                    Escenario {
                        height: 186
                    Rectangle {
                        id: previaIsla
                        // La muestra es la isla misma, en grande y a todo el ancho (sin el recuadro gris).
                        // Con Ajustar contenido se encoge con los huecos, como la de verdad.
                        width: parent.width; height: 110; color: "transparent"
                        readonly property string forma: Estilo.valor("islaForma")
                        // Se dibuja con las medidas de la isla real (42 px de alto) y se agranda entera,
                        // asi cada forma conserva sus proporciones (la pildora sigue siendo pildora).
                        readonly property real k: height / 42
                        // Lo que la forma se sale a los lados por arriba (hombros, diagonales): se deja de margen.
                        readonly property real hombros: -Math.min(...Estilo.mitadForma(forma, 0, 42, 20, 16).map(q => q[0])) * k
                        readonly property real anchoForma: Math.min(width - 2 * hombros, filaHuecos.width + 52)
                        Shape {   // la forma elegida, con las mismas cuentas que la isla de verdad
                            anchors.fill: parent
                            transform: Scale { origin.x: previaIsla.width / 2; xScale: previaIsla.k; yScale: previaIsla.k }
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                // la pagina es del mismo color que la isla: un poco mas oscura y con filo
                                fillColor: Qt.darker(Estilo.fondo, 1.6); strokeColor: Estilo.borde; strokeWidth: 1 / previaIsla.k
                                PathSvg { path: Estilo.trazoForma(Estilo.mitadForma(previaIsla.forma, (previaIsla.width - previaIsla.anchoForma / previaIsla.k) / 2, 42, 20, 16), previaIsla.width / 2) }
                            }
                        }
                        // Tres huecos: se pulsa uno y abajo se elige que muestra.
                        Row {
                            id: filaHuecos
                            anchors.horizontalCenter: parent.horizontalCenter
                            // centrada en el cuerpo de la forma (la pildora deja 5 px libres arriba)
                            y: ((previaIsla.forma === "pildora" ? 5 * previaIsla.k : 0) + previaIsla.height) / 2 - 32 - (previaIsla.forma === "pildora" ? 0 : 3); spacing: 8
                            // Las formas con hombros anchos (biselada, ola) dejan menos cuerpo: los huecos se reparten lo que quede.
                            readonly property real cuerpo: previaIsla.width - 2 * previaIsla.hombros - 52
                            readonly property real anchoLado: Math.max(64, Math.min(100, cuerpo * 0.2))
                            readonly property real anchoCentro: Math.max(100, cuerpo - 2 * anchoLado - 2 * spacing)
                            Repeater {
                                model: ["izquierda", "centro", "derecha"]
                                delegate: Rectangle {
                                    id: hueco
                                    required property string modelData
                                    readonly property string tipo: Estilo.huecos[modelData]
                                    readonly property bool elegido: paginaIsla.huecoElegido === modelData
                                    // Con Ajustar contenido los vacios se achican (siguen ahi para poder elegirlos)
                                    // y la forma de atras se encoge con ellos, como la isla de verdad.
                                    width: tipo === "nada" && Estilo.valor("islaAjustar") ? 64 : modelData === "centro" ? filaHuecos.anchoCentro : filaHuecos.anchoLado
                                    height: 64; radius: 32
                                    Behavior on width { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                                    readonly property bool vacio: tipo === "nada"
                                    color: elegido ? Qt.alpha(Estilo.texto, 0.06) : zonaHueco.containsMouse ? Estilo.realce : Estilo.nada
                                    border.width: vacio && !elegido ? 0 : elegido ? 1.5 : 1
                                    border.color: elegido ? Estilo.acento : Qt.alpha(Estilo.texto, 0.18)
                                    // Hueco vacio: borde punteado
                                    Shape {
                                        visible: hueco.vacio && !hueco.elegido
                                        anchors.fill: parent
                                        preferredRendererType: Shape.CurveRenderer
                                        ShapePath {
                                            fillColor: "transparent"; strokeColor: Qt.alpha(Estilo.texto, 0.35); strokeWidth: 1.5
                                            strokeStyle: ShapePath.DashLine; dashPattern: [3, 3]
                                            PathRectangle { x: 0.75; y: 0.75; width: hueco.width - 1.5; height: hueco.height - 1.5; radius: hueco.radius - 0.75 }
                                        }
                                    }
                                    Texto {   // reloj: la hora real con el formato elegido
                                        visible: hueco.tipo === "hora" || hueco.tipo === "fecha"
                                        anchors.centerIn: parent
                                        text: Qt.formatTime(reloj.date, Estilo.valor("reloj12") ? "h:mm AP" : "H:mm")
                                            + (hueco.tipo === "fecha" ? "  " + Qt.locale("es_MX").toString(reloj.date, "ddd d").replace(/\./g, "") : "")
                                        font { pixelSize: 24; weight: Font.DemiBold; letterSpacing: -0.4 }
                                        font.features: { "tnum": 1 }
                                    }
                                    Behavior on border.color { ColorAnimation { duration: Estilo.t(160) } }
                                    Rectangle {   // asistente: los dos ojos
                                        visible: hueco.tipo === "asistente"
                                        scale: 1.7
                                        anchors.centerIn: parent
                                        width: 24; height: 24; radius: 12; color: Estilo.tarjeta
                                        Row { anchors.centerIn: parent; spacing: 4; Repeater { model: 2; Rectangle { width: 3; height: 8; radius: 2; color: "#fff" } } }
                                    }
                                    Row {         // visualizador
                                        visible: hueco.tipo === "visualizador"
                                        scale: 1.7
                                        anchors.centerIn: parent; spacing: 3
                                        Repeater { model: [6, 11, 16, 11, 6]; Rectangle { required property int modelData; width: 3; height: modelData; radius: 1.5; color: "#fff"; anchors.verticalCenter: parent.verticalCenter } }
                                    }
                                    Simbolo {     // el resto: su icono; vacio, un "+"
                                        visible: !["asistente", "visualizador", "hora", "fecha"].includes(hueco.tipo)
                                        font.pixelSize: hueco.vacio ? 26 : 34
                                        anchors.centerIn: parent
                                        text: hueco.vacio ? "add" : (paginaIsla.catalogo.find(c => c[0] === hueco.tipo) || ["", "", "help"])[2]
                                        color: hueco.vacio ? Estilo.texto2 : Estilo.texto
                                    }
                                    MouseArea { id: zonaHueco; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: paginaIsla.huecoElegido = hueco.modelData }
                                }
                            }
                        }
                    }
                    Texto {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
                        text: "Pulsa un hueco y elige qué muestra. Si ya estaba en otro hueco, se cambian."
                        color: Estilo.texto2; font.pixelSize: 13
                    }
                    }
                    Item { width: 1; height: 14 }
                    Revelar {
                    abierto: paginaIsla.masPiezas; visibles: 5
                    Grid {
                        width: parent.width; columns: 5; spacing: 8
                        Repeater {
                            model: paginaIsla.catalogo
                            delegate: Rectangle {
                                id: pieza
                                required property var modelData
                                readonly property bool puesto: Estilo.huecos[paginaIsla.huecoElegido] === modelData[0]
                                readonly property bool permitido: modelData[0] !== "fecha" || paginaIsla.huecoElegido === "centro"
                                width: (parent.width - 32) / 5; height: 64; radius: 12
                                // Elegida: borde fino del acento, sin relleno.
                                color: puesto ? Qt.tint(Estilo.tarjeta, Qt.alpha(Estilo.texto, 0.05)) : zonaPieza.containsMouse && permitido ? Estilo.realce : Estilo.tarjeta
                                border.width: puesto ? 1.5 : 1; border.color: puesto ? Estilo.acento : Estilo.borde
                                opacity: permitido ? 1 : 0.4
                                Behavior on color { ColorAnimation { duration: Estilo.t(160) } }
                                scale: zonaPieza.pressed ? 0.96 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaPieza.pressed ? 80 : 340); easing.type: zonaPieza.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                Simbolo { visible: pieza.modelData[0] !== "asistente"; x: 14; anchors.verticalCenter: parent.verticalCenter; text: pieza.modelData[2]; font.pixelSize: 20 }
                                Rectangle {   // la Gota: circulo oscuro con dos ojos
                                    visible: pieza.modelData[0] === "asistente"
                                    x: 13; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; radius: 11; color: Estilo.hover
                                    Row { anchors.centerIn: parent; spacing: 4; Repeater { model: 2; Rectangle { width: 3; height: 8; radius: 2; color: "#fff" } } }
                                }
                                Column {
                                    x: 46; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 54; spacing: 1
                                    Texto { width: parent.width; elide: Text.ElideRight; text: pieza.modelData[1]; font { pixelSize: 14; weight: Font.DemiBold } }
                                    Texto { width: parent.width; elide: Text.ElideRight; text: paginaIsla.cuando[pieza.modelData[0]] || ""; color: Estilo.texto2; font.pixelSize: 12 }
                                }
                                MouseArea {
                                    id: zonaPieza; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: pieza.permitido ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: if (pieza.permitido) Estilo.ponerHueco(paginaIsla.huecoElegido, pieza.modelData[0])
                                }
                            }
                        }
                    }
                    }
                    MostrarMas {
                        linea: false; abierto: paginaIsla.masPiezas; cuantas: paginaIsla.catalogo.length - 5
                        onPulsado: paginaIsla.masPiezas = !paginaIsla.masPiezas
                    }
                    Texto { text: "Ajuste fino"; topPadding: 22; bottomPadding: 6; font { pixelSize: 17; weight: Font.DemiBold } }
                    TablaAjustes {
                        FilaTabla {
                            numero: 1; titulo: "Reloj"; que: "Formato de la hora"
                            ControlSegmentos { grande: true; opciones: ["12 horas", "24 horas"]; claves: [true, false]; elegida: Estilo.valor("reloj12"); onElegir: c => Estilo.poner("reloj12", c) }
                        }
                        FilaTabla {
                            numero: 2; titulo: "Segundos"; que: "Mostrar los segundos en el reloj"
                            Llave { encendido: Estilo.valor("segundos"); onCambiar: v => Estilo.poner("segundos", v) }
                        }
                        FilaTabla {
                            numero: 3; titulo: "Tamaño"; que: "Ancho de la isla pequeña"
                            Desplegable {
                                opciones: [[true, "Se ajusta a lo que muestra"], [false, "Ancho fijo"]]
                                elegida: !!Estilo.valor("islaAjustar"); onElegir: c => Estilo.poner("islaAjustar", c)
                            }
                        }
                        FilaTabla {
                            numero: 4; titulo: "Abrir al pasar el cursor"; que: "Si se apaga, solo se abre con un clic"
                            Llave { encendido: Estilo.valor("islaCursor"); onCambiar: v => Estilo.poner("islaCursor", v) }
                        }
                    }
                    Item {
                        width: parent.width; height: 56
                        Texto { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 10 } text: "Avanzado"; font { pixelSize: 17; weight: Font.DemiBold } }
                        Texto { anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 11 } text: "Lo que se cambia poco"; color: Estilo.texto2 }
                    }
                    Avanzado {
                        FilaAvanzada {
                            titulo: "Forma"; relleno: 16
                            resumen: "Pequeña: " + paginaIsla.nombreForma(Estilo.valor("islaForma")) + " · abierta: " + paginaIsla.nombreForma(Estilo.valor("islaFormaAbierta"))
                            Texto { text: "Isla pequeña"; color: Estilo.texto2; font.pixelSize: 12; bottomPadding: 6 }
                            FormasIsla { clave: "islaForma" }
                            Texto { text: "Isla abierta"; color: Estilo.texto2; font.pixelSize: 12; topPadding: 12; bottomPadding: 6 }
                            FormasIsla { clave: "islaFormaAbierta" }
                        }
                        FilaAvanzada {
                            titulo: "Al abrirla"
                            resumen: "Espera " + (({ corta: "corta", normal: "normal", larga: "larga" })[Estilo.valor("islaEspera")] ?? "")
                                + " · abre en " + (({ musica: "Música", acciones: "Acciones", rendimiento: "Rendimiento", ultima: "la última pestaña" })[Estilo.valor("islaPestana")] ?? "")
                            FilaTabla {
                                numero: 1; titulo: "Espera antes de abrir"; que: "Cuánto esperar con el cursor encima"
                                ControlSegmentos { grande: true; opciones: ["Corta", "Normal", "Larga"]; claves: ["corta", "normal", "larga"]; elegida: Estilo.valor("islaEspera"); onElegir: c => Estilo.poner("islaEspera", c) }
                            }
                            FilaTabla {
                                numero: 2; titulo: "Pestaña al abrir"; que: "Con cuál empieza"
                                Desplegable {
                                    opciones: [["musica", "Música"], ["acciones", "Acciones"], ["rendimiento", "Rendimiento"], ["ultima", "La última"]]
                                    elegida: Estilo.valor("islaPestana"); onElegir: c => Estilo.poner("islaPestana", c)
                                }
                            }
                        }
                        FilaAvanzada {
                            titulo: "Pestaña Música"
                            resumen: [["musicaLetra", "letra sincronizada"], ["musicaTinte", "color de la carátula"], ["musicaAudio", "volumen y salida"]]
                                .filter(c => Estilo.valor(c[0])).map(c => c[1]).join(", ").replace(/^./, c => c.toUpperCase()) || "Sin extras"
                            FilaTabla { numero: 1; titulo: "Letra sincronizada"; que: "Abajo, la línea que suena resaltada"; Llave { encendido: Estilo.valor("musicaLetra"); onCambiar: v => Estilo.poner("musicaLetra", v) } }
                            FilaTabla { numero: 2; titulo: "Buscar también en NetEase"; que: "Si LRCLIB no tiene la canción (servicio de China)"; Llave { encendido: Estilo.valor("letraNetease"); onCambiar: v => Estilo.poner("letraNetease", v) } }
                            FilaTabla { numero: 3; titulo: "Color de la carátula"; que: "La isla se tiñe con el disco que suena"; Llave { encendido: Estilo.valor("musicaTinte"); onCambiar: v => Estilo.poner("musicaTinte", v) } }
                            FilaTabla { numero: 4; titulo: "Volumen y salida de audio"; que: "Abajo a la derecha de los controles"; Llave { encendido: Estilo.valor("musicaAudio"); onCambiar: v => Estilo.poner("musicaAudio", v) } }
                            FilaTabla { numero: 5; titulo: "Esconder el visualizador"; que: "Las ondas junto al reloj, mientras ves Música"; Llave { encendido: Estilo.valor("ocultarVisualizador"); onCambiar: v => Estilo.poner("ocultarVisualizador", v) } }
                        }
                        FilaAvanzada {
                            titulo: "Pestaña Acciones"
                            resumen: (Estilo.valor("botEnPaginas") ? "Con botón de la Gota" : "Sin botón de la Gota") + " · " + (Estilo.valor("islaImagen") ? "con imagen de fondo" : "sin imagen de fondo")
                            FilaTabla { numero: 1; titulo: "Botón de la Gota"; que: "La Gota grande a la izquierda de Acciones"; Llave { encendido: Estilo.valor("botEnPaginas"); onCambiar: v => Estilo.poner("botEnPaginas", v) } }
                        Texto { x: 12; text: "Imagen de fondo"; color: Estilo.texto2; font.pixelSize: 12; topPadding: 10; bottomPadding: 6 }
                        Item {
                            width: parent.width; height: fondosAcciones.height + 12
                        // "Ninguna" y luego los fondos de pantalla; la elegida va dentro de la isla, desvanecida hacia abajo.
                        Flow {
                            id: fondosAcciones
                            x: 12; width: parent.width - 24; spacing: 8
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
                    }
                    Item { width: 1; height: 16 }
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

                property bool masAvisos: false
                Desplazable {
                    EncabezadoParte { grupo: "Sistema"; titulo: "Notificaciones"; descripcion: "Los avisos de la isla y las notificaciones de las apps." }
                    Item { width: 1; height: 18 }
                    // Vista previa: el fondo real con el aviso "Ahora suena" en la isla y uno de Hokum en su sitio.
                    // Con No molestar todo se apaga.
                    Escenario {
                        height: 250
                        Item {
                            anchors.fill: parent
                            opacity: Estilo.noMolestar ? 0.25 : 1
                            Behavior on opacity { NumberAnimation { duration: Estilo.t(300) } }
                            layer.enabled: Estilo.noMolestar
                            layer.effect: MultiEffect { saturation: -1 }
                            Image {
                                anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                                source: ventana.fondoActual ? "file://" + ventana.fondoActual : ""; sourceSize.width: 1200
                            }
                            Rectangle { anchors.fill: parent; color: "#73000000" }
                            IslaMini {
                                id: islaAviso
                                readonly property var musica: Mpris.players.values.find(pl => pl.isPlaying) ?? Mpris.players.values[0] ?? null
                                anchors.horizontalCenter: parent.horizontalCenter
                                ancho: 300; alto: 60; esquina: 24; hombro: 16
                                Row {
                                    anchors.centerIn: parent; spacing: 12
                                    ClippingRectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 38; height: 38; radius: 9
                                        color: Qt.tint(Estilo.hover, Qt.alpha(Estilo.acento, 0.5))
                                        Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; source: islaAviso.musica ? islaAviso.musica.trackArtUrl || "" : ""; sourceSize: Qt.size(76, 76) }
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        Texto { text: "Ahora suena"; color: Estilo.texto2; font.pixelSize: 11 }
                                        Texto {
                                            width: Math.min(implicitWidth, 200); elide: Text.ElideRight
                                            text: islaAviso.musica && islaAviso.musica.trackTitle ? islaAviso.musica.trackTitle + (islaAviso.musica.trackArtist ? " · " + islaAviso.musica.trackArtist : "") : "Tu canción · su artista"
                                            font { pixelSize: 15; weight: Font.DemiBold }
                                        }
                                    }
                                }
                            }
                            AvisoMini {
                                x: paginaNotif.lado === "left" ? 18 : paginaNotif.lado === "center" ? (parent.width - width) / 2 : parent.width - width - 18
                                y: paginaNotif.alto === "top" ? (paginaNotif.lado === "center" ? 86 : 18) : parent.height - height - 18
                                Behavior on x { NumberAnimation { duration: Estilo.t(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                                Behavior on y { NumberAnimation { duration: Estilo.t(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                            }
                        }
                        Rectangle {
                            visible: Estilo.noMolestar
                            anchors.centerIn: parent
                            width: filaDnd.width + 32; height: 40; radius: 20
                            color: Estilo.tarjeta; border.width: 1; border.color: Estilo.borde
                            Row {
                                id: filaDnd
                                anchors.centerIn: parent; spacing: 8
                                Simbolo { anchors.verticalCenter: parent.verticalCenter; text: "do_not_disturb_on"; font.pixelSize: 17 }
                                Texto { anchors.verticalCenter: parent.verticalCenter; text: "No molestar: nada te interrumpe"; font { pixelSize: 14; weight: Font.DemiBold } }
                            }
                        }
                    }
                    Texto { text: "Lo básico"; topPadding: 22; bottomPadding: 6; font { pixelSize: 17; weight: Font.DemiBold } }
                    TablaAjustes {
                        FilaTabla { numero: 1; titulo: "No molestar"; que: "Calla a Hokum y los avisos de la isla"; Llave { encendido: Estilo.noMolestar; onCambiar: v => Estilo.ponerNoMolestar(v) } }
                        FilaTabla { numero: 2; titulo: "Automático en pantalla completa"; que: "En juegos y videos se enciende solo"; Llave { encendido: Estilo.valor("dndPantallaCompleta"); onCambiar: v => Estilo.poner("dndPantallaCompleta", v) } }
                        FilaTabla { numero: 3; titulo: "Mientras grabas la pantalla"; que: "Que no salga nada en el video"; Llave { encendido: Estilo.valor("dndGrabando"); onCambiar: v => Estilo.poner("dndGrabando", v) } }
                    }
                    Item {
                        width: parent.width; height: 56
                        Texto { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 10 } text: "Avisos en la isla"; font { pixelSize: 17; weight: Font.DemiBold } }
                        Texto { anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 11 } text: "Qué puede asomarse por la isla"; color: Estilo.texto2 }
                    }
                    Revelar {
                    abierto: paginaNotif.masAvisos
                    alturaCerrada: filaAviso3.parent.y + filaAviso3.y + filaAviso3.height
                    onPedirAbrir: paginaNotif.masAvisos = true
                    TablaAjustes {
                        FilaTabla { numero: 1; titulo: "Ahora suena"; que: "La canción que empieza"; Llave { encendido: Estilo.valor("avisoMusica"); onCambiar: v => Estilo.poner("avisoMusica", v) } }
                        FilaTabla { numero: 2; titulo: "Audífonos y bocinas"; que: "Al conectar o cambiar de salida"; Llave { encendido: Estilo.valor("avisoBt"); onCambiar: v => Estilo.poner("avisoBt", v) } }
                        FilaTabla { id: filaAviso3; numero: 3; titulo: "Capturas de pantalla"; que: "Una miniatura al tomarla"; Llave { encendido: Estilo.valor("avisoCaptura"); onCambiar: v => Estilo.poner("avisoCaptura", v) } }
                        FilaTabla {
                            numero: 4; titulo: "Temperatura alta"; que: "Si el equipo se calienta de más"
                            ControlSegmentos {
                                grande: true
                                opciones: ["No", "70°", "80°", "90°"]; claves: [0, 70, 80, 90]
                                elegida: Estilo.valor("avisoTemp") ? Estilo.valor("avisoGrados") : 0
                                onElegir: c => { Estilo.poner("avisoTemp", c > 0); if (c > 0) Estilo.poner("avisoGrados", c); }
                            }
                        }
                        FilaTabla { numero: 5; titulo: "Batería baja"; que: "Del mando o los audífonos, al bajar de 20 %"; Llave { encendido: Estilo.valor("avisoBateria"); onCambiar: v => Estilo.poner("avisoBateria", v) } }
                        FilaTabla { numero: 6; titulo: "Cambio de salida de audio"; que: "Cuando el sonido pasa a otro aparato"; Llave { encendido: Estilo.valor("avisoSalida"); onCambiar: v => Estilo.poner("avisoSalida", v) } }
                        FilaTabla { numero: 7; titulo: "Fallos del sistema"; que: "Bluetooth, sonido, gráfica o disco, con botón Arreglar"; Llave { encendido: Estilo.valor("avisoFallos"); onCambiar: v => Estilo.poner("avisoFallos", v) } }
                        FilaTabla {
                            numero: 8; titulo: "Duración"; que: "Cuánto se queda cada aviso"
                            ControlSegmentos { grande: true; opciones: ["Corta", "Normal", "Larga"]; claves: ["corta", "normal", "larga"]; elegida: Estilo.valor("avisoDuracion"); onElegir: c => Estilo.poner("avisoDuracion", c) }
                        }
                    }
                    }
                    MostrarMas { linea: false; abierto: paginaNotif.masAvisos; cuantas: 5; onPulsado: paginaNotif.masAvisos = !paginaNotif.masAvisos }
                    Item {
                        width: parent.width; height: 48
                        Texto { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 10 } text: "Avanzado"; font { pixelSize: 17; weight: Font.DemiBold } }
                        Texto { anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 11 } text: "Lo que se cambia poco"; color: Estilo.texto2 }
                    }
                    Avanzado {
                        FilaAvanzada {
                            titulo: "Notificaciones de apps"
                            resumen: (({ left: "Izquierda", center: "Centro", right: "Derecha" })[paginaNotif.lado] ?? "") + ", " + (paginaNotif.alto === "top" ? "arriba" : "abajo")
                                + " · " + paginaNotif.hokum.dura + " s · máximo " + paginaNotif.hokum.maximo
                            FilaTabla {
                                numero: 1; titulo: "Posición"; que: "De qué lado salen"
                                ControlSegmentos { grande: true; opciones: ["Izquierda", "Centro", "Derecha"]; claves: ["left", "center", "right"]; elegida: paginaNotif.lado; onElegir: c => paginaNotif.ponerPosicion(paginaNotif.alto, c) }
                            }
                            FilaTabla {
                                numero: 2; titulo: "Arriba o abajo"; que: "En qué borde de la pantalla"
                                ControlSegmentos { grande: true; opciones: ["Arriba", "Abajo"]; claves: ["top", "bottom"]; elegida: paginaNotif.alto; onElegir: c => paginaNotif.ponerPosicion(c, paginaNotif.lado) }
                            }
                            FilaTabla {
                                numero: 3; titulo: "Cuánto duran"; que: "Si la app no dice otra cosa"
                                ControlSegmentos {
                                    grande: true
                                    opciones: ["4 s", "6 s", "10 s", "20 s"]; claves: ["4", "6", "10", "20"]; elegida: paginaNotif.hokum.dura
                                    onElegir: c => paginaNotif.hokumCmd(["comportamiento", "stay", c === "6" ? "" : c], { dura: c })
                                }
                            }
                            FilaTabla {
                                numero: 4; titulo: "Máximo a la vista"; que: "Las demás esperan en fila"
                                ControlDeslizador {
                                    desde: 1; hasta: 8; valor: paginaNotif.hokum.maximo
                                    onSoltado: v => paginaNotif.hokumCmd(["comportamiento", "show-at-most", v === 5 ? "" : String(v)], { maximo: v })
                                }
                            }
                        }
                        FilaAvanzada {
                            titulo: "Detalles de «Ahora suena»"
                            resumen: (Estilo.valor("musicaConCaratula") ? "Solo con carátula" : "Con o sin carátula") + " · " + (Estilo.valor("musicaReanudar") ? "avisa al reanudar" : "no repite al reanudar")
                            Item {
                                width: parent.width; height: fichas.y + fichas.height + 10
                                Column {
                                    id: textoFichas
                                    x: 12; y: 9
                                    Texto { text: "Apps que avisan" }
                                    Texto { text: "Toca una para callarla. Salen las abiertas y las ya calladas"; color: Estilo.texto2; font.pixelSize: 11 }
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
                                    Texto { visible: repFichas.count === 0; text: "Pon algo a sonar y aparecerá aquí"; color: Estilo.texto3; font.pixelSize: 12 }
                                }
                                Rectangle { anchors { left: parent.left; leftMargin: 12; right: parent.right; bottom: parent.bottom } height: 1; color: Estilo.linea }
                            }
                            FilaTabla { numero: 1; titulo: "No avisar si la app está al frente"; que: "Si ya estás mirando el reproductor"; Llave { encendido: Estilo.valor("musicaNoAlFrente"); onCambiar: v => Estilo.poner("musicaNoAlFrente", v) } }
                            FilaTabla { numero: 2; titulo: "Solo con carátula"; que: "Ignora videos y sonidos sin portada"; Llave { encendido: Estilo.valor("musicaConCaratula"); onCambiar: v => Estilo.poner("musicaConCaratula", v) } }
                            FilaTabla {
                                numero: 3; titulo: "Al reanudar la misma canción"; que: "Si vuelve a sonar tras una pausa"
                                ControlSegmentos { grande: true; opciones: ["No avisar", "Avisar"]; claves: [false, true]; elegida: Estilo.valor("musicaReanudar"); onElegir: c => Estilo.poner("musicaReanudar", c) }
                            }
                        }
                        FilaAvanzada {
                            titulo: "Por aplicación"
                            resumen: paginaNotif.listaApps.length === 0 ? "Ninguna todavía"
                                : paginaNotif.listaApps.slice(0, 2).join(", ") + (paginaNotif.listaApps.length > 2 ? " y " + (paginaNotif.listaApps.length - 2) + " más" : "")
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
                            Texto {
                                x: 12; topPadding: 10; bottomPadding: 10
                                width: parent.width - 24; wrapMode: Text.Wrap
                                text: "La campana deja pasar esa app aunque esté puesto No molestar. Ocultar la calla del todo."
                                color: Estilo.texto2; font.pixelSize: 11
                            }
                        }
                    }
                    Item { width: 1; height: 16 }
                }
            }

            // ---------------- Asistente ----------------
            Pagina {
                id: paginaBot
                anchors.fill: parent
                clave: "asistente"; activa: ventana.seccion === clave
                property string prueba: "feliz"     // emocion de la vista previa (solo se ve aqui)
                Desplazable {
                    EncabezadoParte { grupo: "Sistema"; titulo: "Gota"; descripcion: "Tu mascota: su nombre, su carácter y su botón en la isla." }
                    Item { width: 1; height: 18 }
                    // La casa de la Gota: ella grande, con su halo y su rayo en su color, y sus caras para probar.
                    Escenario {
                        id: casaGota
                        height: 400
                        // Una gota casi negra no daria luz: entonces usa la del tema.
                        readonly property color tono: { const c = Qt.color(Estilo.gota.color); return c.hslLightness < 0.2 ? Estilo.luz : c; }
                        readonly property real cx: width / 2 - 60
                        readonly property real cy: 165
                        readonly property var caras: [["Normal", "normal"], ["Feliz", "feliz"], ["Escucha", "escucha"], ["Pensar", "pensar"], ["Emoción", "emocion"], ["Confuso", "confuso"]]
                        Halo { anchors.fill: parent; cx: casaGota.cx; cy: casaGota.cy; radio: 190; tono: casaGota.tono }
                        Rectangle {   // rayo fino desde abajo a la izquierda
                            readonly property real x1: 22
                            readonly property real y1: casaGota.height - 10
                            readonly property real x2: casaGota.cx - 88
                            readonly property real y2: casaGota.cy + 30
                            x: x1; y: y1 - height / 2
                            width: Math.hypot(x2 - x1, y2 - y1); height: 1.6; radius: 0.8
                            transformOrigin: Item.Left
                            rotation: Math.atan2(y2 - y1, x2 - x1) * 180 / Math.PI
                            antialiasing: true
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Qt.alpha(Estilo.acento2, 0) }
                                GradientStop { position: 0.4; color: Qt.alpha(Estilo.acento2, 0.55) }
                                GradientStop { position: 1; color: Qt.alpha(casaGota.tono, 0.75) }
                            }
                        }
                        Texto { x: 22; y: 20; text: "PRUEBA SUS CARAS →"; color: Estilo.texto2; font { pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.8 } }
                        Asistente {
                            width: 200; height: 200
                            x: casaGota.cx - width / 2; y: casaGota.cy - height / 2
                            emocion: paginaBot.prueba
                            ritmo: ({ tranquilo: 1.8, normal: 1, inquieto: 0.5 })[Estilo.valor("personalidad")] ?? 1
                            fondoNegro: true
                        }
                        Column {
                            anchors.horizontalCenter: undefined
                            x: casaGota.cx - width / 2; y: casaGota.cy + 112
                            spacing: 3
                            Texto { anchors.horizontalCenter: parent.horizontalCenter; text: Estilo.gota.nombre; font { pixelSize: 22; weight: Font.Bold } }
                            Texto {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: ((casaGota.caras.find(c => c[1] === paginaBot.prueba) || ["Normal"])[0]) + " · personalidad " + (Estilo.valor("personalidad") || "normal")
                                color: Estilo.texto2; font.pixelSize: 14
                            }
                        }
                        Column {
                            anchors { right: parent.right; rightMargin: 22; top: parent.top; topMargin: 20 }
                            spacing: 8
                            Repeater {
                                model: casaGota.caras
                                Rectangle {
                                    required property var modelData
                                    readonly property bool elegida: paginaBot.prueba === modelData[1]
                                    width: 124; height: 38; radius: 19
                                    color: elegida ? Qt.alpha(Estilo.texto, 0.06) : zCara.containsMouse ? Estilo.realce : Estilo.nada
                                    border.width: elegida ? 1.5 : 1; border.color: elegida ? Estilo.acento : Estilo.borde
                                    Texto { x: 16; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0]; font { pixelSize: 14; weight: parent.elegida ? Font.DemiBold : Font.Normal } }
                                    MouseArea { id: zCara; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: paginaBot.prueba = parent.modelData[1] }
                                }
                            }
                        }
                    }
                    Texto { text: "Ajuste fino"; topPadding: 22; bottomPadding: 6; font { pixelSize: 17; weight: Font.DemiBold } }
                    TablaAjustes {
                        FilaTabla {
                            numero: 1; titulo: "Tu nombre"; que: "Para el saludo de Inicio"
                            ControlCampo { texto: Estilo.valor("nombre") || ""; marcador: "Cómo te llamas"; onGuardar: t => Estilo.poner("nombre", t.trim()) }
                        }
                        FilaTabla {
                            numero: 2; titulo: "Nombre de la Gota"; que: "Sale en el botón de la isla"
                            ControlCampo { texto: Estilo.gota.nombre; marcador: "Gota"; onGuardar: t => Estilo.guardarGota(Estilo.gotaActiva, Object.assign({}, Estilo.gota, { nombre: t.trim() || "Gota" })) }
                        }
                        FilaTabla {
                            numero: 3; titulo: "Personalidad"; que: "Qué tan seguido mira y parpadea"
                            ControlSegmentos { grande: true; opciones: ["Tranquilo", "Normal", "Inquieto"]; claves: ["tranquilo", "normal", "inquieto"]; elegida: Estilo.valor("personalidad"); onElegir: c => Estilo.poner("personalidad", c) }
                        }
                        FilaTabla {
                            numero: 4; titulo: "Reaccionar a la música"; que: "Se pone feliz cuando suena algo"
                            Llave { encendido: Estilo.valor("reaccionMusica"); onCambiar: v => Estilo.poner("reaccionMusica", v) }
                        }
                    }
                    Item {
                        width: parent.width; height: 56
                        Texto { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 10 } text: "Tus gotas"; font { pixelSize: 17; weight: Font.DemiBold } }
                        Texto { anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 11 } text: "La que está en uso aparece en la isla"; color: Estilo.texto2 }
                    }
                    // Un clic elige la gota de la isla; otro clic sobre la que esta en uso la edita.
                    Flow {
                        width: parent.width; spacing: 12
                        Repeater {
                            model: Estilo.gotas
                            delegate: Rectangle {
                                id: tarjetaGota
                                required property var modelData
                                required property int index
                                readonly property bool enUso: index === Estilo.gotaActiva
                                width: 190; height: 140; radius: 16
                                color: enUso ? Qt.tint(Estilo.tarjeta, Qt.alpha(Estilo.texto, 0.05)) : zGota.containsMouse ? Estilo.realce : Estilo.tarjeta
                                border.width: enUso ? 1.5 : 1; border.color: enUso ? Estilo.acento : Estilo.borde
                                scale: zGota.pressed ? 0.96 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zGota.pressed ? 80 : 300); easing.type: Easing.OutCubic } }
                                Asistente {
                                    anchors.horizontalCenter: parent.horizontalCenter; y: 10
                                    width: 70; height: 70
                                    emocion: "normal"; fondoNegro: true
                                    gota: tarjetaGota.modelData || Estilo.gota
                                }
                                Column {
                                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                                    spacing: 1
                                    Texto { anchors.horizontalCenter: parent.horizontalCenter; text: tarjetaGota.modelData.nombre; font { pixelSize: 15; weight: Font.DemiBold } }
                                    Texto { anchors.horizontalCenter: parent.horizontalCenter; text: tarjetaGota.enUso ? "En uso · toca para editar" : "Toca para usarla"; color: Estilo.texto2; font.pixelSize: 12 }
                                }
                                MouseArea {
                                    id: zGota; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: tarjetaGota.enUso ? dialogoGota.abrir(tarjetaGota.index) : Estilo.poner("gotaActiva", tarjetaGota.index)
                                }
                            }
                        }
                        Item {
                            id: nuevaGota
                            width: 190; height: 140
                            Rectangle { anchors.fill: parent; radius: 16; color: zNueva.containsMouse ? Estilo.realce : Estilo.nada }
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    fillColor: "transparent"; strokeColor: zNueva.containsMouse ? Estilo.texto2 : Qt.alpha(Estilo.texto, 0.3); strokeWidth: 1.2
                                    strokeStyle: ShapePath.DashLine; dashPattern: [3, 3]
                                    PathRectangle { x: 0.6; y: 0.6; width: nuevaGota.width - 1.2; height: nuevaGota.height - 1.2; radius: 15.4 }
                                }
                            }
                            Column {
                                anchors.centerIn: parent; spacing: 6
                                Simbolo { anchors.horizontalCenter: parent.horizontalCenter; text: "add"; font.pixelSize: 24; color: Estilo.texto2 }
                                Texto { anchors.horizontalCenter: parent.horizontalCenter; text: "Nueva gota"; font.pixelSize: 15 }
                            }
                            MouseArea { id: zNueva; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dialogoGota.abrir(-1) }
                        }
                    }
                    Item {
                        width: parent.width; height: 56
                        Texto { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 10 } text: "Avanzado"; font { pixelSize: 17; weight: Font.DemiBold } }
                        Texto { anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 11 } text: "Lo que se cambia poco"; color: Estilo.texto2 }
                    }
                    Avanzado {
                        FilaAvanzada {
                            titulo: "Botón de la isla y animaciones"
                            resumen: [["botLuz", "luz que gira"], ["botChispas", "chispas"], ["succion", "se succiona al abrir el lanzador"]]
                                .filter(c => Estilo.valor(c[0])).map(c => c[1]).join(" · ").replace(/^./, c => c.toUpperCase()) || "Todo apagado"
                            FilaTabla { numero: 1; titulo: "Subtítulo"; que: "Debajo del nombre, en el botón"; ControlCampo { texto: Estilo.valor("botSub") || ""; marcador: "Sin subtítulo"; onGuardar: t => Estilo.poner("botSub", t) } }
                            FilaTabla { numero: 2; titulo: "Luz que gira"; que: "Apagada, la luz queda quieta"; Llave { encendido: Estilo.valor("botLuz"); onCambiar: v => Estilo.poner("botLuz", v) } }
                            FilaTabla { numero: 3; titulo: "Chispas"; que: "Destellos alrededor del botón"; Llave { encendido: Estilo.valor("botChispas"); onCambiar: v => Estilo.poner("botChispas", v) } }
                            FilaTabla { numero: 4; titulo: "Succionarse al abrir el lanzador"; que: "La Gota se mete en el lanzador"; Llave { encendido: Estilo.valor("succion"); onCambiar: v => Estilo.poner("succion", v) } }
                        }
                    }
                    Item { width: 1; height: 16 }
                }
            }

            // ---------------- Botones de arriba ----------------
            // Cuatro sitios por boton (las esquinas y los lados de la isla), con vista previa.
            Pagina {
                id: paginaEsquinas
                anchors.fill: parent
                clave: "esquinas"; activa: ventana.seccion === clave
                property bool agregandoApp: false
                property bool masBotones: false
                readonly property var appsDock: Estilo.valor("miniDockApps") || []
                function entradaDe(id) { return DesktopEntries.applications.values.find(e => e.id === id) ?? null }
                function moverApp(i, j) {
                    const l = appsDock.slice();
                    if (j < 0 || j >= l.length) return;
                    const [x] = l.splice(i, 1); l.splice(j, 0, x);
                    Estilo.poner("miniDockApps", l);
                }
                function info(c) { return Estilo.botonesCatalogo.find(x => x[0] === c) || [c, c, "help"]; }
                property string resaltado: ""      // boton resaltado en la lista y en la vista previa
                readonly property var nombresZona: ({ izquierda: "Esquina izquierda", izquierdaIsla: "Junto a la isla · izquierda",
                                                      derechaIsla: "Junto a la isla · derecha", derecha: "Esquina derecha" })
                function copia() { const b = {}; for (const z of Estilo.zonasBotones) b[z] = Estilo.botones[z].slice(); return b; }
                // Todos los botones puestos, de izquierda a derecha como se ven: [clave, sitio].
                readonly property var puestos: Estilo.zonasBotones.reduce((r, z) => r.concat(Estilo.botones[z].map(c => [c, z])), [])
                // Pasa un boton a otro sitio. Entra por el lado de la isla.
                function moverA(c, zona) {
                    const b = copia();
                    for (const z of Estilo.zonasBotones) b[z] = b[z].filter(x => x !== c);
                    if (zona === "izquierda" || zona === "izquierdaIsla") b[zona].push(c); else b[zona].unshift(c);
                    Estilo.ponerBotones(b);
                }
                // Arrastrar en la lista: cambia el orden; cada boton sigue en su sitio.
                function reordenar(i, j) {
                    const l = puestos.slice();
                    const [x] = l.splice(i, 1);
                    l.splice(Math.max(0, Math.min(j, l.length)), 0, x);
                    const b = {};
                    for (const z of Estilo.zonasBotones) b[z] = l.filter(q => q[1] === z).map(q => q[0]);
                    Estilo.ponerBotones(b);
                }
                function quitar(c) {
                    const b = copia();
                    for (const z of Estilo.zonasBotones) b[z] = b[z].filter(x => x !== c);
                    Estilo.ponerBotones(b);
                }
                function agregar(c) { const b = copia(); b.izquierdaIsla.push(c); Estilo.ponerBotones(b); }
                // Cambia el orden dentro de un sitio (arrastrando el asa).
                function reordenarZona(z, i, j) {
                    const b = copia();
                    const [x] = b[z].splice(i, 1);
                    b[z].splice(Math.max(0, Math.min(j, b[z].length)), 0, x);
                    Estilo.ponerBotones(b);
                }
                property string opcionesDe: ""     // boton con sus opciones abiertas (reproductor o minidock)
                Desplazable {
                    EncabezadoParte {
                        grupo: "Partes de Menisco"; titulo: "Botones de arriba"
                        descripcion: "Los botones a la altura de la isla. Cada uno elige su sitio: en una esquina o junto a la isla."
                        // lo mismo que Estilo.botones sin guardar: la estrella solo si la barra tiene boton
                        textoBoton: "Restablecer"
                        onBoton: Estilo.ponerBotones(Estilo.barra.lado === "izquierda"
                            ? { izquierda: (Estilo.barra.boton ? ["barra"] : []).concat(["bandeja"]), derecha: ["menisco"] }
                            : { izquierda: ["menisco"], derecha: ["bandeja"].concat(Estilo.barra.boton ? ["barra"] : []) })
                    }
                    Item { width: 1; height: 18 }
                    // Vista previa: la franja de arriba en pequeño, con la isla y los cuatro sitios.
                    Escenario {
                        height: 178
                        PreviaBotones {
                            id: previaArriba
                            x: 16; width: parent.width - 32; height: 64
                            resaltado: paginaEsquinas.resaltado
                            onTocado: c => paginaEsquinas.resaltado = paginaEsquinas.resaltado === c ? "" : c
                        }
                        // Las tres zonas, con una linea fina encima.
                        Row {
                            x: 16; y: 76; width: parent.width - 32; spacing: 16
                            readonly property real tercio: (width - 32) / 3
                            Repeater {
                                model: [["ESQUINA IZQUIERDA", Text.AlignLeft], ["JUNTO A LA ISLA", Text.AlignHCenter], ["ESQUINA DERECHA", Text.AlignRight]]
                                Column {
                                    required property var modelData
                                    width: parent.tercio; spacing: 10
                                    Rectangle { width: parent.width; height: 1; color: Estilo.linea }
                                    Texto { width: parent.width; horizontalAlignment: modelData[1]; text: modelData[0]; color: Estilo.texto2; font { pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.8 } }
                                }
                            }
                        }
                        Texto {
                            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
                            text: "Toca un botón de la lista para encontrarlo aquí."; color: Estilo.texto2; font.pixelSize: 13
                        }
                    }
                    Item {
                        width: parent.width; height: 54
                        Texto { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 12 } text: "Botones puestos"; font { pixelSize: 17; weight: Font.DemiBold } }
                        Texto {
                            anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 13 }
                            text: { const n = paginaEsquinas.puestos.length; return n + (n === 1 ? " botón" : " botones") + " · arrastra el asa para cambiar el orden"; }
                            color: Estilo.texto2
                        }
                    }
                    Rectangle {
                        width: parent.width; height: listaZonas.implicitHeight; radius: 14
                        color: Estilo.tarjeta; border.width: 1; border.color: Estilo.borde
                        Column {
                            id: listaZonas
                            width: parent.width
                            Repeater {
                                model: Estilo.zonasBotones
                                delegate: Column {
                                    id: grupoZona
                                    required property string modelData
                                    required property int index
                                    readonly property var lista: Estilo.botones[modelData]
                                    width: listaZonas.width
                                    visible: lista.length > 0
                                    Item {
                                        width: parent.width; height: 44
                                        Row {
                                            x: 20; anchors { bottom: parent.bottom; bottomMargin: 10 }
                                            spacing: 8
                                            Texto { text: paginaEsquinas.nombresZona[grupoZona.modelData].toUpperCase(); color: Estilo.texto2; font { pixelSize: 12; weight: Font.DemiBold; letterSpacing: 0.8 } }
                                            Texto { text: grupoZona.lista.length; color: Estilo.texto2; font.pixelSize: 12 }
                                        }
                                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Estilo.linea }
                                    }
                                    Repeater {
                                        model: grupoZona.lista
                                        delegate: Item {
                                            id: filaBoton
                                            required property string modelData
                                            required property int index
                                            readonly property string clave: modelData
                                            readonly property string zona: grupoZona.modelData
                                            readonly property var datos: paginaEsquinas.info(clave)
                                            readonly property bool conOpciones: clave === "reproductor" || clave === "minidock"
                                            readonly property bool abierta: paginaEsquinas.opcionesDe === clave
                                            property real despliegue: abierta ? 1 : 0
                                            Behavior on despliegue { NumberAnimation { duration: Estilo.t(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                                            width: parent.width
                                            readonly property bool resaltada: paginaEsquinas.resaltado === clave
                                            height: 58 + (panelOpciones.implicitHeight + 10) * despliegue
                                            clip: despliegue > 0.001     // sin recorte, la ayuda del selector puede salir por arriba
                                            z: asa.pressed || sitios.ayuda ? 3 : 1
                                            transform: Translate { y: asa.dy }
                                            // Un clic en la fila la resalta aqui y en la vista previa.
                                            MouseArea { anchors.fill: parent; onClicked: paginaEsquinas.resaltado = filaBoton.resaltada ? "" : filaBoton.clave }
                                            Rectangle {
                                                width: parent.width; height: 58
                                                color: asa.pressed || filaBoton.resaltada ? Qt.alpha(Estilo.texto, 0.05) : Estilo.nada
                                                Behavior on color { ColorAnimation { duration: Estilo.t(160) } }
                                            }
                                            Rectangle { visible: filaBoton.index > 0; width: parent.width; height: 1; color: Estilo.linea }
                                            Simbolo {
                                                x: 14; y: 29 - height / 2
                                                text: "drag_indicator"; color: Estilo.texto3
                                                MouseArea {
                                                    id: asa
                                                    // Arrastre dentro de su sitio: la fila sigue al dedo y al soltar cambia el orden.
                                                    property real inicio: 0
                                                    property real dy: 0
                                                    anchors.fill: parent; anchors.margins: -6
                                                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                                    onPressed: m => { inicio = mapToItem(null, m.x, m.y).y; dy = 0; }
                                                    onPositionChanged: m => dy = mapToItem(null, m.x, m.y).y - inicio
                                                    onReleased: {
                                                        const j = filaBoton.index + Math.round(dy / 52);
                                                        dy = 0;
                                                        if (j !== filaBoton.index) paginaEsquinas.reordenarZona(filaBoton.zona, filaBoton.index, j);
                                                    }
                                                }
                                            }
                                            // Icono en un circulo negro con borde fino, como en la barra de verdad.
                                            Rectangle {
                                                x: 42; y: 12
                                                width: 34; height: 34; radius: 17; color: Estilo.fondo
                                                border.width: filaBoton.resaltada ? 1.5 : 1; border.color: filaBoton.resaltada ? Estilo.acento : Estilo.borde
                                                LogoMenisco { visible: filaBoton.clave === "menisco"; anchors.centerIn: parent; tam: 18 }
                                                Simbolo { visible: filaBoton.clave !== "menisco"; anchors.centerIn: parent; text: filaBoton.datos[2]; font.pixelSize: 16 }
                                            }
                                            Texto { x: 90; y: 29 - height / 2; width: engrane.x - 100; elide: Text.ElideRight; text: filaBoton.datos[1]; font.pixelSize: 15 }
                                            // Opciones del boton (mini reproductor y mini dock), aqui mismo.
                                            Rectangle {
                                                id: engrane
                                                anchors { right: sitios.left; rightMargin: 10 }
                                                y: 13; width: 32; height: 32; radius: 9
                                                border.width: 1; border.color: Estilo.borde
                                                opacity: filaBoton.conOpciones ? 1 : 0
                                                enabled: filaBoton.conOpciones
                                                color: zEngrane.containsMouse || filaBoton.abierta ? Estilo.realce : Estilo.nada
                                                Simbolo { anchors.centerIn: parent; text: "settings"; font.pixelSize: 16; color: filaBoton.abierta ? Estilo.texto : Estilo.texto2; rotation: 60 * filaBoton.despliegue }
                                                MouseArea { id: zEngrane; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: paginaEsquinas.opcionesDe = filaBoton.abierta ? "" : filaBoton.clave }
                                            }
                                            // Selector dibujado como la barra: cuatro casillas con la muesca de la isla en medio.
                                            SelectorSitio {
                                                id: sitios
                                                anchors { right: quitarBoton.left; rightMargin: 12 }
                                                y: 29 - height / 2
                                                zona: filaBoton.zona
                                                onElegir: z => paginaEsquinas.moverA(filaBoton.clave, z)
                                            }
                                            Rectangle {
                                                id: quitarBoton
                                                anchors { right: parent.right; rightMargin: 12 }
                                                y: 15; width: 28; height: 28; radius: 8
                                                color: zQuitarB.containsMouse ? Estilo.realce : Estilo.nada
                                                Simbolo { anchors.centerIn: parent; text: "close"; font.pixelSize: 16; color: zQuitarB.containsMouse ? Estilo.peligro : Estilo.texto2 }
                                                MouseArea { id: zQuitarB; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: paginaEsquinas.quitar(filaBoton.clave) }
                                            }
                                            Column {
                                                id: panelOpciones
                                                x: 42; y: 60; width: parent.width - 58
                                                visible: filaBoton.despliegue > 0
                                                Column {
                                                    visible: filaBoton.clave === "reproductor"
                                                    width: parent.width
                                                    FilaTabla {
                                                        numero: 1; titulo: "Forma"; que: "También la usa el mini dock"
                                                        ControlSegmentos { grande: true; opciones: ["Redondeado", "Píldora"]; claves: ["redondeada", "pildora"]; elegida: Estilo.valor("reproductorForma"); onElegir: c => Estilo.poner("reproductorForma", c) }
                                                    }
                                                    FilaTabla {
                                                        numero: 2; titulo: "Color de la carátula"; que: "Tiñe el reproductor con el color del disco"
                                                        ControlSegmentos { grande: true; opciones: ["Ninguno", "Al lado", "Abajo"]; claves: ["nada", "lado", "abajo"]; elegida: Estilo.valor("reproductorTinte"); onElegir: c => Estilo.poner("reproductorTinte", c) }
                                                    }
                                                }
                                                Column {
                                                    visible: filaBoton.clave === "minidock"
                                                    width: parent.width
                                                    Fila {
                                                        visible: paginaEsquinas.appsDock.length === 0
                                                        titulo: "Sin apps todavía"; sub: "Agrega las que quieras tener a mano arriba"
                                                    }
                                                    Repeater {
                                                        model: paginaEsquinas.appsDock
                                                        delegate: Fila {
                                                            id: filaApp
                                                            required property string modelData
                                                            required property int index
                                                            readonly property var entrada: paginaEsquinas.entradaDe(modelData)
                                                            titulo: entrada ? entrada.name : modelData
                                                            icono: entrada ? entrada.icon : ""; iconoEsApp: true
                                                            Row {
                                                                spacing: 2
                                                                Repeater {
                                                                    model: [["arrow_upward", -1], ["arrow_downward", 1], ["close", 0]]
                                                                    delegate: Rectangle {
                                                                        required property var modelData
                                                                        width: 28; height: 28; radius: 8
                                                                        color: zApp.containsMouse ? Estilo.realce : Estilo.nada
                                                                        Simbolo { anchors.centerIn: parent; text: parent.modelData[0]; font.pixelSize: 16; color: Estilo.texto2 }
                                                                        MouseArea {
                                                                            id: zApp; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                                            onClicked: parent.modelData[1] === 0
                                                                                ? Estilo.poner("miniDockApps", paginaEsquinas.appsDock.filter((a, k) => k !== filaApp.index))
                                                                                : paginaEsquinas.moverApp(filaApp.index, filaApp.index + parent.modelData[1])
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                    Fila {
                                                        visible: !paginaEsquinas.agregandoApp
                                                        icono: "add"; titulo: "Agregar app"; clicable: true
                                                        onPulsada: { paginaEsquinas.agregandoApp = true; buscaDock.text = ""; buscaDock.forceActiveFocus(); }
                                                        Simbolo { text: "chevron_right"; color: Estilo.texto2 }
                                                    }
                                                    Item {
                                                        visible: paginaEsquinas.agregandoApp
                                                        width: parent.width; height: visible ? sugDock.y + sugDock.height + 10 : 0
                                                        Rectangle {
                                                            x: 12; y: 8; width: parent.width - 24; height: 28; radius: 8; color: Estilo.hundido
                                                            border.width: 1; border.color: buscaDock.activeFocus ? Estilo.texto3 : "transparent"
                                                            TextInput {
                                                                id: buscaDock
                                                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                                                verticalAlignment: TextInput.AlignVCenter
                                                                clip: true
                                                                color: Estilo.texto; selectionColor: Estilo.texto3
                                                                font { family: Estilo.letra; pixelSize: 12 }
                                                                Keys.onEscapePressed: paginaEsquinas.agregandoApp = false
                                                                Texto { visible: !parent.text; text: "Busca una app instalada"; color: Estilo.texto3; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                                            }
                                                        }
                                                        Flow {
                                                            id: sugDock
                                                            x: 12; y: 44; width: parent.width - 24; spacing: 6
                                                            Repeater {
                                                                model: !paginaEsquinas.agregandoApp || !buscaDock.text.trim() ? []
                                                                    : DesktopEntries.applications.values
                                                                        .filter(e => !e.noDisplay && !paginaEsquinas.appsDock.includes(e.id) && e.name.toLowerCase().includes(buscaDock.text.trim().toLowerCase()))
                                                                        .slice(0, 8)
                                                                delegate: Rectangle {
                                                                    required property var modelData
                                                                    width: filaSug.implicitWidth + 18; height: 28; radius: 9; color: zSugD.containsMouse ? Estilo.realce : Estilo.hundido
                                                                    Row {
                                                                        id: filaSug
                                                                        anchors.centerIn: parent; spacing: 6
                                                                        IconImage { implicitSize: 16; anchors.verticalCenter: parent.verticalCenter; source: Quickshell.iconPath(parent.parent.modelData.icon, "application-x-executable") }
                                                                        Texto { text: parent.parent.modelData.name; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                                                    }
                                                                    MouseArea {
                                                                        cursorShape: Qt.PointingHandCursor; id: zSugD; anchors.fill: parent; hoverEnabled: true
                                                                        // al guardar, esta sugerencia desaparece (ya esta agregada) y su contexto con ella: todo antes
                                                                        onClicked: { const id = parent.modelData.id, pag = paginaEsquinas; pag.agregandoApp = false; Estilo.poner("miniDockApps", pag.appsDock.concat([id])); }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Item {
                        id: grupoLibres
                        readonly property var libres: Estilo.botonesCatalogo.filter(c => !Estilo.zonaDe(c[0]))
                        width: parent.width; height: 56
                        Texto { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 12 } text: "Añadir botón"; font { pixelSize: 17; weight: Font.DemiBold } }
                        Texto { anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 13 } text: "Los nuevos entran junto a la isla, a la izquierda"; color: Estilo.texto2 }
                    }
                    Revelar {
                    abierto: paginaEsquinas.masBotones; visibles: 5
                    Flow {
                        width: parent.width; spacing: 10
                        Repeater {
                            model: grupoLibres.libres
                            delegate: Item {
                                id: fichaNueva
                                required property var modelData
                                width: filaChip.implicitWidth + 36; height: 44
                                scale: zonaChip.pressed ? 0.95 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaChip.pressed ? 80 : 340); easing.type: zonaChip.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                Rectangle { anchors.fill: parent; radius: 22; color: zonaChip.containsMouse ? Estilo.realce : Estilo.nada }
                                Shape {   // borde punteado
                                    anchors.fill: parent
                                    preferredRendererType: Shape.CurveRenderer
                                    ShapePath {
                                        fillColor: "transparent"; strokeColor: zonaChip.containsMouse ? Estilo.texto2 : Qt.alpha(Estilo.texto, 0.3); strokeWidth: 1.2
                                        strokeStyle: ShapePath.DashLine; dashPattern: [3, 3]
                                        PathRectangle { x: 0.6; y: 0.6; width: fichaNueva.width - 1.2; height: fichaNueva.height - 1.2; radius: 21.4 }
                                    }
                                }
                                Row {
                                    id: filaChip
                                    anchors.centerIn: parent; spacing: 8
                                    Simbolo { text: "add"; font.pixelSize: 17; color: Estilo.texto2; anchors.verticalCenter: parent.verticalCenter }
                                    Simbolo { text: fichaNueva.modelData[2]; font.pixelSize: 17; anchors.verticalCenter: parent.verticalCenter }
                                    Texto { text: fichaNueva.modelData[1]; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { id: zonaChip; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: paginaEsquinas.agregar(fichaNueva.modelData[0]) }
                            }
                        }
                        Texto { visible: grupoLibres.libres.length === 0; text: "Ya están todos puestos"; color: Estilo.texto2 }
                    }
                    }
                    MostrarMas {
                        visible: grupoLibres.libres.length > 5
                        linea: false
                        abierto: paginaEsquinas.masBotones; cuantas: grupoLibres.libres.length - 5
                        onPulsado: paginaEsquinas.masBotones = !paginaEsquinas.masBotones
                    }
                    Item { width: 1; height: 16 }
                }
            }

            // ---------------- Barra lateral ----------------
            Pagina {
                id: paginaBarra
                anchors.fill: parent
                clave: "barra"; activa: ventana.seccion === clave
                Desplazable {
                    EncabezadoParte { grupo: "Partes de Menisco"; titulo: "Barra lateral"; descripcion: "El panel que sale de un lado, con botones rápidos, sonido y calendario." }
                    Item { width: 1; height: 18 }
                    // Vista previa: el panel en miniatura (lado, altura y ancho reales) con sus bloques
                    // arrastrables, y a la derecha que secciones se ven.
                    Escenario {
                        height: editorBarra.height + 48
                        EditorSecciones { id: editorBarra; anchors.centerIn: parent }
                    }
                    Item { width: 1; height: 8 }
                    TablaAjustes {
                        FilaTabla {
                            numero: 1; titulo: "Lado"; que: "De qué lado de la pantalla sale"
                            ControlSegmentos { grande: true; opciones: ["Izquierda", "Derecha"]; claves: ["izquierda", "derecha"]; elegida: Estilo.barra.lado; onElegir: c => Estilo.ponerBarra("lado", c) }
                        }
                        FilaTabla {
                            numero: 2; titulo: "Borde de la pantalla"; que: "Ábrela llevando el cursor al borde"
                            Llave { encendido: Estilo.barra.borde; onCambiar: v => Estilo.ponerBarra("borde", v) }
                        }
                        FilaTabla {
                            numero: 3; titulo: "Cerrar al hacer clic fuera"; que: "Un clic fuera del panel lo cierra"
                            Llave { encendido: Estilo.barra.clicFuera; onCambiar: v => Estilo.ponerBarra("clicFuera", v) }
                        }
                        FilaTabla {
                            numero: 4; titulo: "Altura"; que: "Dónde se queda a lo alto"
                            ControlSegmentos { grande: true; opciones: ["Arriba", "Centro", "Abajo"]; claves: ["arriba", "centro", "abajo"]; elegida: Estilo.barra.altura; onElegir: c => Estilo.ponerBarra("altura", c) }
                        }
                        FilaTabla {
                            numero: 5; titulo: "Ancho"; que: "Qué tan ancho es el panel"
                            ControlDeslizador { id: ctlAnchoBarra; desde: 300; hasta: 420; unidad: " px"; valor: Estilo.barra.ancho; onSoltado: v => Estilo.ponerBarra("ancho", v) }
                        }
                        FilaTabla {
                            numero: 6; titulo: "La semana empieza en"; que: "Primer día del calendario"
                            ControlSegmentos { grande: true; opciones: ["Lunes", "Domingo"]; claves: [true, false]; elegida: Estilo.barra.semanaLunes; onElegir: c => Estilo.ponerBarra("semanaLunes", c) }
                        }
                    }
                    Texto { text: "Botones rápidos"; topPadding: 22; bottomPadding: 10; font { pixelSize: 17; weight: Font.DemiBold } }
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
                                    color: elegido ? Qt.tint(Estilo.tarjeta, Qt.alpha(Estilo.texto, 0.05)) : zonaChip.containsMouse ? Estilo.realce : Estilo.tarjeta
                                    border.width: elegido ? 1.5 : 1; border.color: elegido ? Estilo.acento : Estilo.borde
                                    Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                                    scale: zonaChip.pressed ? 0.94 : 1
                                    Behavior on scale { NumberAnimation { duration: Estilo.t(zonaChip.pressed ? 80 : 360); easing.type: zonaChip.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                    Row {
                                        id: filaChip
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text {
                                            text: chip.modelData[1]; color: chip.elegido ? Estilo.texto : Estilo.texto2
                                            font { family: "Material Symbols Rounded"; pixelSize: 16 }
                                            font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 20 }
                                            renderType: Text.NativeRendering
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Texto { text: chip.modelData[2]; color: chip.elegido ? Estilo.texto : Estilo.texto2; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
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
                    Item { width: 1; height: 16 }
                }
            }

            // ---------------- Liquid glass ----------------
            Pagina {
                anchors.fill: parent
                id: paginaVidrio
                clave: "vidrio"; activa: ventana.seccion === clave
                // Lniri se reconoce por el nombre de la sesion (XDG_SESSION_DESKTOP lleva "lniri").
                readonly property bool enLniri: (Quickshell.env("XDG_SESSION_DESKTOP") || "").toLowerCase().includes("lniri")
                readonly property bool conVidrio: ventana.vidrio && enLniri
                Desplazable {
                    EncabezadoParte { grupo: "Aspecto"; titulo: "Liquid glass"; descripcion: "Vidrio que deforma lo que hay detrás. Solo en la sesión Lniri (niri con liquid glass)." }
                    Item { width: 1; height: 18 }
                    // Vista previa: el fondo real con un dock, una terminal y un aviso; cada uno con
                    // vidrio o solido segun su interruptor, y el efecto sigue a los deslizadores.
                    Escenario {
                        id: escVidrio
                        height: 300
                        Image {
                            id: fondoVidrio
                            anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                            source: ventana.fondoActual ? "file://" + ventana.fondoActual : ""; sourceSize.width: 1400
                        }
                        PiezaVidrio {
                            fondo: fondoVidrio
                            x: 40; y: 66; width: 330; height: 124; radio: 14
                            vidrio: paginaVidrio.conVidrio && ventana.vidrioV.ventanas
                            refraccion: ctlRefraccion.vivo / 100; desenfoque: ctlDesenfoque.vivo / 100
                            aberracion: ctlAberracion.vivo / 100; brillo: ctlBrillo.vivo / 100
                            Row { x: 14; y: 12; spacing: 5; Repeater { model: 3; Rectangle { width: 8; height: 8; radius: 4; color: "#66ffffff" } } }
                            Column {
                                x: 16; y: 34; spacing: 4
                                Text { text: "~ $ ls"; color: "#ffffff"; font { family: "JetBrains Mono"; pixelSize: 13 } }
                                Text { text: "Descargas  Imágenes  Música"; color: "#d9ffffff"; font { family: "JetBrains Mono"; pixelSize: 13 } }
                                Text { text: "~ $ _"; color: "#ffffff"; font { family: "JetBrains Mono"; pixelSize: 13 } }
                            }
                        }
                        PiezaVidrio {
                            fondo: fondoVidrio
                            anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - height - 22
                            width: filaDockVidrio.width + 20; height: 66; radio: 20
                            vidrio: paginaVidrio.conVidrio && ventana.vidrioV.dock
                            refraccion: ctlRefraccion.vivo / 100; desenfoque: ctlDesenfoque.vivo / 100
                            aberracion: ctlAberracion.vivo / 100; brillo: ctlBrillo.vivo / 100
                            Row {
                                id: filaDockVidrio
                                anchors.centerIn: parent; spacing: 8
                                Repeater {
                                    model: ventana.iconosDock
                                    IconImage { required property string modelData; implicitSize: 44; source: ventana.iconoApp(modelData) }
                                }
                            }
                        }
                        PiezaVidrio {
                            fondo: fondoVidrio
                            anchors { right: parent.right; rightMargin: 24 }
                            y: 22
                            width: 236; height: 58; radio: 29
                            vidrio: paginaVidrio.conVidrio && ventana.vidrioV.notificaciones
                            refraccion: ctlRefraccion.vivo / 100; desenfoque: ctlDesenfoque.vivo / 100
                            aberracion: ctlAberracion.vivo / 100; brillo: ctlBrillo.vivo / 100
                            AvisoMini { anchors.fill: parent; color: "transparent"; border.width: 0 }
                        }
                        // Estado de la sesion
                        Rectangle {
                            x: 16; y: 16
                            width: filaEstado.width + 26; height: 32; radius: 16
                            color: "#cc000000"; border.width: 1; border.color: "#26ffffff"
                            Row {
                                id: filaEstado
                                anchors.centerIn: parent; spacing: 8
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: paginaVidrio.enLniri ? "#30d158" : "#e5a54b" }
                                Text {
                                    text: paginaVidrio.enLniri ? "Sesión Lniri activa" : "No estás en la sesión Lniri: elígela al iniciar sesión"
                                    color: paginaVidrio.enLniri ? "#ffffff" : "#f2c27a"
                                    font { family: Estilo.letra; pixelSize: 13; weight: Font.DemiBold }
                                }
                            }
                        }
                    }
                    Item { width: 1; height: 8 }
                    TablaAjustes {
                        FilaTabla {
                            numero: 1; titulo: "Liquid glass"; que: "Vidrio que deforma lo que hay detrás"
                            atenuada: !paginaVidrio.enLniri
                            Llave { encendido: ventana.vidrio; onCambiar: v => ventana.alternarVidrio(v) }
                        }
                        SubtituloTabla { texto: "Dónde se aplica"; atenuada: !paginaVidrio.conVidrio }
                        FilaTabla {
                            numero: 2; titulo: "Dock"; que: "La pieza que brilla"; atenuada: !paginaVidrio.conVidrio
                            Llave { encendido: ventana.vidrioV.dock; onCambiar: v => ventana.ponerVidrio("dock", v) }
                        }
                        FilaTabla {
                            numero: 3; titulo: "Ventanas transparentes"; que: "Terminales con transparencia"; atenuada: !paginaVidrio.conVidrio
                            Llave { encendido: ventana.vidrioV.ventanas; onCambiar: v => ventana.ponerVidrio("ventanas", v) }
                        }
                        FilaTabla {
                            numero: 4; titulo: "Notificaciones"; que: "Hokum: el vidrio cubre toda su franja"; atenuada: !paginaVidrio.conVidrio
                            Llave { encendido: ventana.vidrioV.notificaciones; onCambiar: v => ventana.ponerVidrio("notificaciones", v) }
                        }
                        SubtituloTabla { texto: "Efecto"; atenuada: !paginaVidrio.conVidrio }
                        FilaTabla {
                            numero: 5; titulo: "Refracción"; que: "Cuánto se curva lo de atrás en el borde"; atenuada: !paginaVidrio.conVidrio
                            ControlDeslizador { id: ctlRefraccion; unidad: " %"; valor: ventana.vidrioV.refraccion; onSoltado: v => ventana.ponerVidrio("refraccion", v) }
                        }
                        FilaTabla {
                            numero: 6; titulo: "Desenfoque"; que: "Cuánto se difumina lo de atrás"; atenuada: !paginaVidrio.conVidrio
                            ControlDeslizador { id: ctlDesenfoque; unidad: " %"; valor: ventana.vidrioV.desenfoque; onSoltado: v => ventana.ponerVidrio("desenfoque", v) }
                        }
                        FilaTabla {
                            numero: 7; titulo: "Aberración cromática"; que: "Cuánto se separan los colores en el borde"; atenuada: !paginaVidrio.conVidrio
                            ControlDeslizador { id: ctlAberracion; unidad: " %"; valor: ventana.vidrioV.aberracion; onSoltado: v => ventana.ponerVidrio("aberracion", v) }
                        }
                        FilaTabla {
                            numero: 8; titulo: "Brillo del canto"; que: "Qué tan claro se ve el filo"; atenuada: !paginaVidrio.conVidrio
                            ControlDeslizador { id: ctlBrillo; unidad: " %"; valor: ventana.vidrioV.brillo; onSoltado: v => ventana.ponerVidrio("brillo", v) }
                        }
                    }
                    Item { width: 1; height: 12 }
                }
            }

            // ---------------- Atajos ----------------
            Pagina {
                anchors.fill: parent
                clave: "atajos"; activa: ventana.seccion === clave
                onActivaChanged: if (activa) leerAtajos.running = true
                Desplazable {
                    EncabezadoParte { grupo: "Sistema"; titulo: "Atajos"; descripcion: "Las combinaciones de teclas de Menisco y de las ventanas." }
                    Item { width: 1; height: 14 }
                    TablaAjustes {
                        colAjuste: "ATAJO"; colAhora: "TECLAS"
                        SubtituloTabla { texto: "MENISCO" }
                        Repeater {
                            model: [["lanzador", "Abre el buscador de apps"], ["ajustes", "Abre esta ventana"], ["captura", "Elige un trozo de la pantalla"], ["bloquear", "Bloquea la sesión"]]
                            delegate: FilaTabla {
                                required property var modelData
                                required property int index
                                numero: index + 1; titulo: ventana.nombresAtajo[modelData[0]]; que: modelData[1]
                                resaltada: ventana.capturando === modelData[0] || (!!ventana.conflicto && ventana.conflicto.id === modelData[0])
                                TeclasAtajo { clave: parent.parent.modelData[0] }
                            }
                        }
                        SubtituloTabla { texto: "VENTANAS" }
                        Repeater {
                            model: [["terminal", "Abre una terminal"], ["cerrar", "Cierra la ventana activa"], ["vista", "Todas las ventanas de un vistazo"], ["maximizar", "La ventana activa ocupa todo"]]
                            delegate: FilaTabla {
                                required property var modelData
                                required property int index
                                numero: index + 5; titulo: ventana.nombresAtajo[modelData[0]]; que: modelData[1]
                                resaltada: ventana.capturando === modelData[0] || (!!ventana.conflicto && ventana.conflicto.id === modelData[0])
                                TeclasAtajo { clave: parent.parent.modelData[0] }
                            }
                        }
                    }
                    Texto {
                        topPadding: 14
                        width: parent.width; wrapMode: Text.Wrap
                        text: ventana.errorAtajo || "Pulsa un atajo y luego la nueva combinación. Escape cancela."
                        color: ventana.errorAtajo ? Estilo.peligro : Estilo.texto2; font.pixelSize: 13
                    }
                    Item { width: 1; height: 16 }
                }
            }

            Pagina {
                anchors.fill: parent
                clave: "inicio"; activa: ventana.seccion === clave
                // La tarjeta de Atajos enseña el atajo real del lanzador.
                onActivaChanged: if (activa) leerAtajos.running = true
                Connections { target: ventana; function onAbiertaChanged() { if (ventana.abierta) leerAtajos.running = true } }

                Desplazable {
                    id: paginaInicio
                    // Nombre de quien usa el equipo (campo de nombre del usuario); sin nombre, solo el saludo.
                    // Primero el que se escribe en Ajustes > Gota ("Tu nombre"); si no, el nombre completo del usuario.
                    property string nombreSistema: ""
                    readonly property string nombre: (Estilo.valor("nombre") || "").trim() || nombreSistema
                    Process {
                        running: true
                        command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1"]
                        stdout: StdioCollector { onStreamFinished: paginaInicio.nombreSistema = text.trim() }
                    }
                    readonly property int horaDia: reloj.date.getHours()
                    readonly property string saludo: horaDia >= 6 && horaDia < 12 ? "Buenos días" : horaDia >= 12 && horaDia < 20 ? "Buenas tardes" : "Buenas noches"

                    // ---- Encabezado: la Gota con su halo, el saludo y el reloj ----
                    Item {
                        width: parent.width; height: 80
                        // Cabe entera arriba (el desplazable corta) y se sale hacia abajo sin borde.
                        Halo { width: 180; height: 200; cx: 34; cy: 50; radio: 42; fuerza: 0.26 }
                        Asistente {
                            x: 4; y: 20; width: 60; height: 60
                            emocion: "normal"; fondoNegro: true
                            gota: ({ forma: Estilo.gota.forma, cambia: false, color: Estilo.valor("tema") === "onix" ? "#2c2c2e" : String(Estilo.acento) })
                        }
                        Column {
                            x: 82; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 4
                            spacing: 2
                            Texto { text: paginaInicio.saludo + (paginaInicio.nombre ? ", " + paginaInicio.nombre : ""); font { pixelSize: 30; weight: Font.Bold; letterSpacing: -0.6 } }
                            Texto { text: "Todo está en su sitio."; color: Estilo.texto2; font.pixelSize: 15 }
                        }
                        Column {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: 4 }
                            spacing: 0
                            Texto {
                                anchors.right: parent.right
                                text: Qt.formatTime(reloj.date, Estilo.valor("reloj12") ? "h:mm AP" : "H:mm")
                                font { pixelSize: 40; weight: Font.Bold; letterSpacing: -1 }
                                font.features: { "tnum": 1 }
                            }
                            Texto {
                                anchors.right: parent.right
                                text: Qt.locale("es_MX").toString(reloj.date, "dddd d 'de' MMMM").replace(/^./, c => c.toUpperCase())
                                color: Estilo.texto2; font.pixelSize: 14
                            }
                        }
                    }
                    Item { width: 1; height: 12 }

                    // ---- Fila principal: el fondo de pantalla y el equipo en vivo ----
                    Row {
                        width: parent.width; spacing: 12
                        readonly property real alto: 280
                        Rectangle {
                            id: marcoHero
                            width: (parent.width - 12) * 0.6; height: parent.alto; radius: 16
                            color: Estilo.tarjeta; border.width: 1; border.color: Estilo.borde
                            clip: true
                            // Debajo queda el fondo anterior; el nuevo aparece encima con un fundido
                            // y un leve acercamiento hacia atras (de 1.06 a 1).
                            property string rutaVieja: ""
                            Item {
                                id: marcoImagen
                                x: 1; y: 1; width: parent.width - 2; height: parent.height - 68
                                Redondeada { anchors.fill: parent; radio: 15; ruta: marcoHero.rutaVieja; ancho: 1000 }
                                Redondeada {
                                    id: hero
                                    anchors.fill: parent; radio: 15; ruta: ventana.fondoActual; ancho: 1000
                                    opacity: 0
                                    onListoChanged: if (listo) llegada.restart()
                                }
                                // Sombra abajo para que se lea el texto sobre cualquier fondo.
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: 90; radius: 15
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: "#00000000" }
                                        GradientStop { position: 1; color: "#b3000000" }
                                    }
                                }
                                Column {
                                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 18; bottomMargin: 14 }
                                    spacing: 1
                                    Text { text: "Fondo actual"; color: "#ffffff"; font { family: Estilo.letra; pixelSize: 16; weight: Font.DemiBold } }
                                    TextoCambiante {
                                        text: ventana.fondoActual ? ventana.fondoActual.split("/").pop().replace(/\.[^.]+$/, "") : "Sin fondo"
                                        color: "#e6e6e6"; font { family: "JetBrains Mono"; pixelSize: 12 }
                                    }
                                }
                                Rectangle {
                                    id: abrirCarpeta
                                    anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
                                    width: textoCarpeta.implicitWidth + 28; height: 32; radius: 16
                                    color: abrirZona.containsMouse ? "#e6000000" : "#b3000000"
                                    border.width: 1; border.color: "#33ffffff"
                                    Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                                    Text {
                                        id: textoCarpeta
                                        anchors.centerIn: parent
                                        text: "Abrir carpeta"; color: "#ffffff"
                                        font { family: Estilo.letra; pixelSize: 13; weight: Font.DemiBold }
                                    }
                                    MouseArea { cursorShape: Qt.PointingHandCursor; id: abrirZona; anchors.fill: parent; hoverEnabled: true; onClicked: ventana.ejecutar(["xdg-open", ventana.carpetaFondos]) }
                                }
                            }
                            ParallelAnimation {
                                id: llegada
                                NumberAnimation { target: hero; property: "opacity"; from: 0; to: 1; duration: Estilo.t(420); easing.type: Easing.OutCubic }
                                NumberAnimation { target: hero; property: "scale"; from: 1.06; to: 1; duration: Estilo.t(700); easing.type: Easing.BezierSpline; easing.bezierCurve: ventana.curvaIos }
                                onFinished: marcoHero.rutaVieja = ventana.fondoActual
                            }
                    ListView {
                            id: fondos
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 14; rightMargin: 14; bottomMargin: 10 }
                            height: 46
                            orientation: ListView.Horizontal
                            spacing: 8
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            // La actual siempre a la vista.
                            function irActual() { const k = model.indexOf("file://" + ventana.fondoActual); if (k >= 0) positionViewAtIndex(k, ListView.Contain); }
                            onCountChanged: irActual()
                            Connections { target: ventana; function onFondoActualChanged() { fondos.irActual() } }
    
                            model: FolderListModel {
                                folder: "file://" + ventana.carpetaFondos
                                nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
                                showDirs: false
                            }
    
                            delegate: Item {
                                id: miniatura
                                required property string filePath
                                width: 70; height: 46
                                readonly property bool actual: filePath === ventana.fondoActual
    
                                // Anillo de seleccion: aparece cerrandose sobre la miniatura.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 9
                                    color: "transparent"
                                    border.color: Estilo.acento
                                    border.width: 2.5
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
                                                // Desvanecido al final de la tira: hay mas fondos hacia la derecha.
                            Rectangle {
                                anchors { right: parent.right; rightMargin: 1 }
                                y: fondos.y; width: 56; height: fondos.height
                                visible: !fondos.atXEnd
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: Qt.alpha(Estilo.tarjeta, 0) }
                                    GradientStop { position: 1; color: Estilo.tarjeta }
                                }
                            }
                        }

                        // Este equipo: abierto y en vivo.
                        Rectangle {
                            id: filaEquipo
                            width: (parent.width - 12) * 0.4; height: parent.alto; radius: 16
                            color: Estilo.tarjeta; border.width: 1; border.color: Estilo.borde
                            Column {
                                x: 20; y: 12; width: parent.width - 40
                                Item {
                                    width: parent.width; height: 32
                                    Texto { anchors.verticalCenter: parent.verticalCenter; text: "Este equipo"; font { pixelSize: 17; weight: Font.DemiBold } }
                                    Row {
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        spacing: 6
                                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: "#30d158" }
                                        Texto { text: "En vivo"; color: Estilo.texto2; font.pixelSize: 13 }
                                    }
                                }
                                Repeater {
                                    model: [["Procesador", "cpu"], ["Memoria", "mem"], ["Disco", "disco"]]
                                    delegate: Item {
                                        required property var modelData
                                        width: parent.width; height: 42
                                        Texto { y: 6; text: modelData[0]; color: Estilo.texto2; font.pixelSize: 14 }
                                        // Por encima del 80 %: ambar suave, la barra y el valor.
                                        readonly property bool alto: (paginaInicio.equipo[modelData[1] + "F"] || 0) > 0.8
                                        readonly property color tono: alto ? "#e5a54b" : Estilo.acento
                                        TextoCambiante {
                                            anchors.right: parent.right; y: 6
                                            text: paginaInicio.equipo[modelData[1]]
                                            color: parent.alto ? "#e5a54b" : Estilo.texto; font { family: Estilo.letra; pixelSize: 14; weight: Font.DemiBold }
                                        }
                                        Rectangle {
                                            y: 31; width: parent.width; height: 4; radius: 2; color: Estilo.apagado
                                            Rectangle {
                                                width: parent.width * Math.max(0, Math.min(1, paginaInicio.equipo[modelData[1] + "F"] || 0))
                                                height: parent.height; radius: 2; color: parent.parent.tono
                                                Behavior on color { ColorAnimation { duration: Estilo.t(300) } }
                                                Behavior on width { NumberAnimation { duration: Estilo.t(600); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                                            }
                                        }
                                    }
                                }
                                Item { width: 1; height: 8 }
                                Rectangle { width: parent.width; height: 1; color: Estilo.linea }
                                Item { width: 1; height: 10 }
                                Grid {
                                    width: parent.width; columns: 2; rowSpacing: 8
                                    Repeater {
                                        model: [["Gráfica", "grafica"], ["Encendido", "encendido"], ["Red", "red"], ["Versión", "version"]]
                                        delegate: Column {
                                            required property var modelData
                                            width: parent.width / 2; spacing: 1
                                            Texto { text: modelData[0]; color: Estilo.texto2; font.pixelSize: 12 }
                                            TextoCambiante {
                                                width: parent.width - 8; elide: Text.ElideRight
                                                text: paginaInicio.equipo[modelData[1]]
                                                color: Estilo.texto
                                                font { family: modelData[1] === "version" ? "JetBrains Mono" : Estilo.letra; pixelSize: 14; weight: Font.DemiBold }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- Este equipo: se lee cada 4 s mientras el Inicio esta a la vista ----
                    // Procesador: /proc/stat (dos lecturas) y k10temp/coretemp; disco: df de /; red: la interfaz
                    // de la ruta por defecto (wifi si tiene carpeta wireless). La version, del repo en ~/menisco-dots.
                    property var equipo: ({ cpu: "—", cpuF: 0, mem: "—", memF: 0, disco: "—", discoF: 0, grafica: "—", encendido: "—", red: "—", version: "—" })
                    property var cpuAntes: null
                    Timer {
                        id: relojEquipo
                        interval: 4000; repeat: true; triggeredOnStart: true
                        running: ventana.abierta && ventana.seccion === "inicio"
                        onTriggered: leerEquipo.running = true
                    }
                    Timer { id: segundaLectura; interval: 900; onTriggered: leerEquipo.running = true }
                    Process {
                        id: leerEquipo
                        command: ["sh", "-c", `echo "mem $(free -b | awk '/^Mem:/{print $2-$7, $2}')"
echo "cpu $(head -1 /proc/stat | cut -d' ' -f2-)"
for h in /sys/class/hwmon/hwmon*; do case "$(cat $h/name 2>/dev/null)" in k10temp|coretemp|zenpower) echo "ctemp $(cat $h/temp1_input)"; break;; esac; done
echo "disco $(df -B1 --output=used,size / | tail -1)"
d=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \\([^ ]*\\).*/\\1/p')
if [ -z "$d" ]; then echo "red nada"; elif [ -d "/sys/class/net/$d/wireless" ]; then echo "red wifi"; else echo "red eth"; fi
echo "gpu $(nvidia-smi --query-gpu=name,temperature.gpu --format=csv,noheader 2>/dev/null | head -1)"
echo "up $(cut -d. -f1 /proc/uptime)"
echo "ver $(git -C "$HOME/menisco-dots" log -1 --format=%h 2>/dev/null)"`]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const v = {};
                                for (const l of text.split("\n")) { const k = l.indexOf(" "); if (k > 0) v[l.slice(0, k)] = l.slice(k + 1).trim(); }
                                const gb = n => (n / 1073741824).toFixed(1).replace(/\.0$/, "");
                                const e = Object.assign({}, paginaInicio.equipo);
                                const [usada, total] = (v.mem || "").split(" ").map(Number);
                                if (total) { e.mem = gb(usada) + " / " + Math.round(total / 1073741824) + " GB"; e.memF = usada / total; }
                                // Uso del procesador: diferencia entre dos lecturas de /proc/stat.
                                const n = (v.cpu || "").split(/\s+/).map(Number);
                                const cpuTotal = n.reduce((a, b) => a + (b || 0), 0), cpuLibre = (n[3] || 0) + (n[4] || 0);
                                const temp = v.ctemp ? Math.round(Number(v.ctemp) / 1000) + "°" : "";
                                if (paginaInicio.cpuAntes && cpuTotal > paginaInicio.cpuAntes[0]) {
                                    const uso = Math.round(100 * (1 - (cpuLibre - paginaInicio.cpuAntes[1]) / (cpuTotal - paginaInicio.cpuAntes[0])));
                                    e.cpu = uso + " %" + (temp ? " · " + temp : ""); e.cpuF = uso / 100;
                                } else {
                                    e.cpu = temp ? "— · " + temp : "—";
                                    segundaLectura.restart();
                                }
                                if (cpuTotal) paginaInicio.cpuAntes = [cpuTotal, cpuLibre];
                                const [dUsado, dTotal] = (v.disco || "").split(/\s+/).map(Number);
                                if (dTotal) { e.disco = Math.round(dUsado / 1073741824) + " / " + Math.round(dTotal / 1073741824) + " GB"; e.discoF = dUsado / dTotal; }
                                e.red = ({ eth: "Ethernet", wifi: "Wi-Fi", nada: "Sin conexión" })[v.red] || "—";
                                const [nombre, gtemp] = (v.gpu || "").split(",").map(x => x.trim());
                                e.grafica = nombre ? nombre.replace(/^NVIDIA (GeForce )?/, "") + (gtemp ? " · " + gtemp + "°" : "") : "—";
                                const sg = parseInt(v.up || "0"), dd = Math.floor(sg / 86400), hh = Math.floor(sg % 86400 / 3600), mm = Math.floor(sg % 3600 / 60);
                                e.encendido = sg ? (dd ? dd + " d " + hh + " h" : hh ? hh + " h " + mm + " min" : mm + " min") : "—";
                                e.version = /^[0-9a-f]{7,}$/.test(v.ver || "") ? v.ver : "—";
                                paginaInicio.equipo = e;
                            }
                        }
                    }

                    // ---- Lo que mas se cambia: cada tarjeta enseña la pieza que configura ----
                    Item {
                        width: parent.width; height: 46
                        Texto { anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 10 } text: "Lo que más se cambia"; font { pixelSize: 17; weight: Font.DemiBold } }
                        Texto { anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 11 } text: "Pasa el cursor para verlo en acción"; color: Estilo.texto2 }
                    }
                    Grid {
                        id: accesos
                        width: parent.width; columns: 3; spacing: 12
                        readonly property real ancho: (width - spacing * 2) / 3
                        readonly property var lados: ({ left: "a la izquierda", center: "al centro", right: "a la derecha" })
                        // Reloj de la isla: la isla con la hora; con el cursor, se abre.
                        TarjetaPieza {
                            id: tReloj
                            width: accesos.ancho
                            titulo: "Reloj de la isla"
                            valor: (Estilo.valor("reloj12") ? "12 h" : "24 h") + (Estilo.valor("segundos") ? ", con segundos" : ", sin segundos")
                            onPulsado: ventana.irATitulo("isla", "Reloj")
                            IslaMini {
                                anchors.horizontalCenter: parent.horizontalCenter
                                ancho: 160 + 80 * tReloj.fase; alto: 46 + 30 * tReloj.fase; esquina: 22 + 6 * tReloj.fase; hombro: 18
                                Column {
                                    anchors.centerIn: parent
                                    Texto {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Qt.formatTime(reloj.date, Estilo.valor("reloj12") ? "h:mm AP" : "H:mm")
                                        font { pixelSize: 22; weight: Font.DemiBold; letterSpacing: -0.4 }
                                        font.features: { "tnum": 1 }
                                    }
                                    Texto {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        visible: tReloj.fase > 0.05; opacity: tReloj.fase
                                        text: Qt.locale("es_MX").toString(reloj.date, "ddd d MMM").replace(/\./g, "")
                                        color: Estilo.texto2; font.pixelSize: 13
                                    }
                                }
                            }
                        }
                        // Gota: la de verdad, asomandose desde abajo; con el cursor, parpadea.
                        TarjetaPieza {
                            id: tGota
                            width: accesos.ancho
                            titulo: "Gota"
                            valor: ({ tranquilo: "Tranquila", normal: "Normal", inquieto: "Inquieta" })[Estilo.valor("personalidad")] ?? ""
                            onPulsado: ventana.irATitulo("asistente", "Personalidad")
                            Halo { anchors.fill: parent; cx: width / 2; cy: height - 6; radio: 110 }
                            Asistente {
                                id: gotaTarjeta
                                width: 110; height: 110
                                anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 62
                                emocion: "normal"; fondoNegro: true
                                gota: ({ forma: Estilo.gota.forma, cambia: false, color: Estilo.valor("tema") === "onix" ? "#2c2c2e" : String(Estilo.acento) })
                            }
                            Timer { running: tGota.activo; repeat: true; interval: 1400; triggeredOnStart: true; onTriggered: gotaTarjeta.parpadear() }
                        }
                        // Avisos de Hokum: un aviso con su forma de capsula; con el cursor, entra y sale.
                        TarjetaPieza {
                            id: tAviso
                            width: accesos.ancho
                            titulo: "Avisos de Hokum"
                            valor: (paginaNotif.alto === "top" ? "Arriba " : "Abajo ") + accesos.lados[paginaNotif.lado]
                            onPulsado: ventana.irATitulo("notificaciones", "Posición")
                            AvisoMini {
                                anchors.verticalCenter: parent.verticalCenter
                                x: (parent.width - width) / 2 + 40 * tAviso.fase
                                opacity: 1 - tAviso.fase
                            }
                        }
                        // Atajos: la tira de teclas con las del lanzador encendidas; con el cursor, se pulsan.
                        TarjetaPieza {
                            id: tAtajos
                            width: accesos.ancho
                            readonly property var combo: (ventana.atajos.lanzador || "Mod+D").replace(/^Mod\b/, "Super").split("+")
                            titulo: "Atajos"
                            valor: combo.join(" + ") + " abre el lanzador"
                            onPulsado: ventana.irA("atajos", null)
                            Row {
                                anchors.centerIn: parent; spacing: 6
                                Repeater {
                                    model: ["Esc"].concat(tAtajos.combo).concat(["A", "."])
                                    delegate: Rectangle {
                                        required property string modelData
                                        required property int index
                                        readonly property bool encendida: index > 0 && index <= tAtajos.combo.length
                                        readonly property real pulsada: encendida ? Math.max(0, Math.min(1, (tAtajos.fase - 0.25) * 3)) : 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(36, teclaTexto.implicitWidth + 22); height: 38; radius: 9
                                        color: encendida ? Qt.tint(Estilo.tarjeta, Qt.alpha(Estilo.texto, 0.06 + 0.06 * pulsada)) : Estilo.hundido
                                        border.width: 1; border.color: encendida ? Qt.alpha(Estilo.texto, 0.45) : Estilo.borde
                                        scale: 1 - 0.07 * pulsada
                                        transform: Translate { y: 2 * pulsada }
                                        Texto {
                                            id: teclaTexto
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: parent.encendida ? Estilo.texto : Estilo.texto3
                                            font { pixelSize: 14; weight: parent.encendida ? Font.DemiBold : Font.Normal }
                                        }
                                    }
                                }
                            }
                        }
                        // Color: los temas en abanico, el actual al frente; con el cursor, el abanico se abre.
                        TarjetaPieza {
                            id: tColor
                            width: accesos.ancho
                            readonly property string actual: Estilo.valor("tema")
                            readonly property var abanico: [actual].concat(Estilo.ordenTemas.filter(k => k !== actual)).slice(0, 6)
                            titulo: "Color"
                            valor: (Estilo.temas[actual] || Estilo.temas.onix).nombre
                            onPulsado: ventana.irA("apariencia", null)
                            Item {
                                anchors.centerIn: parent
                                readonly property real paso: 30 + 12 * tColor.fase
                                width: 60 + paso * 5; height: 60
                                Repeater {
                                    model: tColor.abanico
                                    delegate: Rectangle {
                                        required property string modelData
                                        required property int index
                                        readonly property bool frente: index === 0
                                        z: 10 - index
                                        width: frente ? 60 : 44; height: width; radius: width / 2
                                        x: frente ? 0 : 60 + parent.paso * (index - 1) - 22 + 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: modelData === "onix" ? "#f2f2f3" : (Estilo.temas[modelData] || {}).acento || "#888888"
                                        border.width: frente ? 3 : 2; border.color: frente ? Estilo.texto : Estilo.hundido
                                    }
                                }
                            }
                        }
                        // Botones de arriba: la franja de arriba con la isla y los botones puestos;
                        // con el cursor, los botones se separan de la isla.
                        TarjetaPieza {
                            id: tBotones
                            width: accesos.ancho
                            titulo: "Botones de arriba"
                            valor: { const n = Estilo.zonasBotones.reduce((k, z) => k + Estilo.botones[z].length, 0); return n + (n === 1 ? " botón puesto" : " botones puestos"); }
                            onPulsado: ventana.irA("esquinas", null)
                            // Solo los botones, en sus cuatro grupos y sin la isla (queda un hueco mayor en
                            // medio). Si no caben, todo se reduce por igual. Con el cursor, se elevan uno tras
                            // otro de izquierda a derecha.
                            property real ola: 0
                            NumberAnimation on ola {
                                running: tBotones.activo; loops: Animation.Infinite
                                from: 0; to: 1; duration: 1600; easing.type: Easing.Linear
                                onRunningChanged: if (!running) tBotones.ola = 0
                            }
                            Row {
                                id: gruposArriba
                                readonly property var zonas: Estilo.zonasBotones
                                readonly property int total: zonas.reduce((k, z) => k + Estilo.botones[z].length, 0)
                                // posicion de cada boton contando de izquierda a derecha, para la ola
                                function orden(zona, i) { let k = 0; for (const z of zonas) { if (z === zona) return k + i; k += Estilo.botones[z].length; } return k; }
                                anchors.centerIn: parent
                                spacing: 18
                                scale: Math.min(1, (parent.width - 24) / Math.max(1, implicitWidth))
                                Repeater {
                                    model: [0, 1, -1, 2, 3]       // -1: el hueco de la isla, sin dibujarla
                                    delegate: Item {
                                        id: grupo
                                        required property int modelData
                                        readonly property string zona: modelData < 0 ? "" : gruposArriba.zonas[modelData]
                                        readonly property var lista: zona ? Estilo.botones[zona] : []
                                        readonly property bool junto: zona.endsWith("Isla")
                                        visible: modelData < 0 || lista.length > 0
                                        width: modelData < 0 ? 18 : filaGrupo.width + (junto ? 10 : 0)
                                        height: 40
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle {   // pastilla oscura de los grupos junto a la isla
                                            visible: grupo.junto
                                            anchors.fill: parent; radius: height / 2
                                            color: Estilo.fondo; border.width: 1; border.color: Estilo.borde
                                        }
                                        Row {
                                            id: filaGrupo
                                            anchors.centerIn: parent
                                            spacing: grupo.junto ? 2 : 6
                                            Repeater {
                                                model: grupo.lista
                                                delegate: Rectangle {
                                                    required property string modelData
                                                    required property int index
                                                    readonly property int n: gruposArriba.orden(grupo.zona, index)
                                                    // ola: sube cuando la cresta pasa por su sitio
                                                    readonly property real alto: Math.max(0, 1 - Math.abs(tBotones.ola * (gruposArriba.total + 3) - n - 1.5) / 1.5)
                                                    width: 30; height: 30; radius: 15
                                                    color: Estilo.fondo
                                                    border.width: grupo.junto ? 0 : 1; border.color: Estilo.borde
                                                    transform: Translate { y: -7 * alto }
                                                    LogoMenisco { visible: parent.modelData === "menisco"; anchors.centerIn: parent; tam: 17 }
                                                    Simbolo {
                                                        visible: parent.modelData !== "menisco"
                                                        anchors.centerIn: parent; font.pixelSize: 16
                                                        text: (Estilo.botonesCatalogo.find(c => c[0] === parent.modelData) || ["", "", "help"])[2]
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Item { width: 1; height: 12 }
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

    // Logo oficial (assets/menisco-logo-white.svg, lienzo de 100x100): el marco y los tres tubos.
    component LogoMenisco: Item {
        id: logo
        property real tam: 22
        property color color: Estilo.texto
        // Sin marco: solo los tres tubos (x 23.5-76.5, y 28-72 en el lienzo), y "tam" es su alto.
        property bool marco: true
        readonly property real k: marco ? tam / 100 : tam / 44
        width: marco ? tam : tam * 53 / 44; height: tam
        Shape {
            width: 100; height: 100
            x: logo.marco ? 0 : -23.5 * logo.k; y: logo.marco ? 0 : -28 * logo.k
            scale: logo.k; transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1; fillColor: logo.marco ? logo.color : "transparent"; fillRule: ShapePath.OddEvenFill
                PathSvg { path: "M34 10H66A24 24 0 0 1 90 34V66A24 24 0 0 1 66 90H34A24 24 0 0 1 10 66V34A24 24 0 0 1 34 10ZM34 15.5H66A18.5 18.5 0 0 1 84.5 34V66A18.5 18.5 0 0 1 66 84.5H34A18.5 18.5 0 0 1 15.5 66V34A18.5 18.5 0 0 1 34 15.5Z" }
            }
            ShapePath {
                strokeWidth: -1; fillColor: Qt.alpha(logo.color, 0.45)
                PathSvg { path: "M23.5 44Q31 49.25 38.5 44V67A5 5 0 0 1 33.5 72H28.5A5 5 0 0 1 23.5 67ZM61.5 44Q69 49.25 76.5 44V67A5 5 0 0 1 71.5 72H66.5A5 5 0 0 1 61.5 67Z" }
            }
            ShapePath {
                strokeWidth: -1; fillColor: logo.color
                PathSvg { path: "M42.5 28Q50 33.25 57.5 28V67A5 5 0 0 1 52.5 72H47.5A5 5 0 0 1 42.5 67Z" }
            }
        }
    }
    // La palabra MENISCO, version recta (los siete glifos de assets/readme/readme-encabezado-oscuro.svg,
    // sin la curva del banner). Mide 590.4 x 68.35 en su lienzo; alto = altura de la letra.
    component PalabraMenisco: Item {
        id: palabra
        property real alto: 13
        property color color: Estilo.texto
        width: alto * 590.4 / 68.35; height: alto
        Shape {
            width: 590.4; height: 68.35
            scale: palabra.alto / 68.35; transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer
            ShapePath { strokeWidth: -1; fillColor: palabra.color; PathSvg { path: "M0.00 67.20L0.00 1.15L37.25 1.15L45.41 25.34Q46.18 27.36 46.95 30.00Q47.72 32.64 48.44 35.28Q49.16 37.92 49.64 39.84L50.31 39.84Q50.79 38.02 51.51 35.52Q52.23 33.02 53.04 30.29Q53.86 27.55 54.63 25.34L62.79 1.15L98.88 1.15L98.88 67.20L75.17 67.20L75.17 38.40Q75.17 36.00 75.22 33.12Q75.27 30.24 75.36 27.46Q75.46 24.67 75.46 22.66L74.69 22.66Q74.02 24.86 73.11 27.79Q72.20 30.72 71.28 33.55Q70.37 36.38 69.60 38.40L59.24 67.20L38.21 67.20L27.84 38.40Q26.79 35.33 25.78 32.30Q24.77 29.28 24.00 26.74Q23.24 24.19 22.76 22.66L21.99 22.66Q22.08 24.19 22.13 26.74Q22.18 29.28 22.23 32.30Q22.28 35.33 22.28 38.40L22.28 67.20ZM113.09 67.20L113.09 1.15L183.65 1.15L183.65 17.57L136.90 17.57L136.90 26.11L177.22 26.11L177.22 41.66L136.90 41.66L136.90 50.78L184.42 50.78L184.42 67.20ZM195.65 67.20L195.65 1.15L216.29 1.15L248.93 28.70Q249.51 29.18 250.57 30.14Q251.62 31.10 252.77 32.16Q253.93 33.22 254.89 34.08L255.85 34.08Q255.85 32.74 255.85 30.48Q255.85 28.22 255.85 26.11L255.85 1.15L278.12 1.15L278.12 67.20L257.67 67.20L226.66 41.18Q224.65 39.55 222.39 37.54Q220.13 35.52 218.79 34.27L217.93 34.27Q217.93 35.62 217.93 38.06Q217.93 40.51 217.93 43.01L217.93 67.20ZM292.32 67.20L292.32 1.15L316.04 1.15L316.04 67.20ZM368.07 68.35Q359.52 68.35 352.13 67.34Q344.74 66.34 339.17 63.89Q333.60 61.44 330.44 57.07Q327.27 52.70 327.27 46.08Q327.27 45.89 327.27 45.55Q327.27 45.22 327.36 44.83L350.50 44.83Q350.40 45.22 350.40 45.55Q350.40 45.89 350.40 46.18Q350.40 49.06 352.32 50.59Q354.24 52.13 357.70 52.66Q361.16 53.18 365.67 53.18Q367.49 53.18 369.46 53.14Q371.43 53.09 373.30 52.85Q375.17 52.61 376.66 52.13Q378.15 51.65 379.06 50.83Q379.97 50.02 379.97 48.77Q379.97 47.04 377.81 46.08Q375.65 45.12 371.96 44.59Q368.26 44.06 363.70 43.58Q359.14 43.10 354.24 42.34Q349.35 41.57 344.79 40.18Q340.23 38.78 336.53 36.38Q332.84 33.98 330.68 30.24Q328.52 26.50 328.52 21.12Q328.52 15.36 331.54 11.33Q334.56 7.30 339.75 4.80Q344.93 2.30 351.65 1.15Q358.37 0.00 365.67 0.00Q373.16 0.00 379.73 1.10Q386.31 2.21 391.35 4.61Q396.39 7.01 399.27 10.90Q402.15 14.78 402.15 20.35L402.15 21.50L379.20 21.50L379.20 21.12Q379.20 19.20 377.96 17.71Q376.71 16.22 373.92 15.31Q371.14 14.40 366.63 14.40Q362.02 14.40 358.95 14.98Q355.88 15.55 354.39 16.56Q352.90 17.57 352.90 18.72Q352.90 20.45 355.06 21.41Q357.22 22.37 360.92 22.90Q364.61 23.42 369.17 23.90Q373.73 24.38 378.63 25.10Q383.52 25.82 388.08 27.12Q392.64 28.42 396.34 30.72Q400.04 33.02 402.20 36.58Q404.36 40.13 404.36 45.31Q404.36 53.47 399.60 58.56Q394.85 63.65 386.64 66.00Q378.44 68.35 368.07 68.35ZM454.56 68.35Q440.26 68.35 430.85 64.46Q421.44 60.58 416.79 52.99Q412.13 45.41 412.13 34.18Q412.13 17.76 422.98 8.88Q433.83 0.00 454.75 0.00Q466.27 0.00 475.01 3.60Q483.75 7.20 488.69 13.58Q493.63 19.97 493.63 28.32L470.59 28.32Q470.59 24.86 468.58 22.18Q466.56 19.49 462.91 17.95Q459.27 16.42 454.37 16.42Q448.23 16.42 444.24 18.62Q440.26 20.83 438.39 24.58Q436.51 28.32 436.51 32.93L436.51 35.33Q436.51 39.74 438.39 43.54Q440.26 47.33 444.10 49.63Q447.94 51.94 453.89 51.94Q459.36 51.94 463.25 50.50Q467.14 49.06 469.20 46.46Q471.27 43.87 471.27 40.42L493.63 40.42Q493.63 48.48 488.98 54.82Q484.32 61.15 475.59 64.75Q466.85 68.35 454.56 68.35ZM546.30 68.35Q532.84 68.35 522.93 64.22Q513.02 60.10 507.65 52.46Q502.27 44.83 502.27 34.22Q502.27 23.52 507.65 15.84Q513.02 8.16 522.93 4.08Q532.84 0.00 546.30 0.00Q559.97 0.00 569.81 4.08Q579.65 8.16 585.02 15.84Q590.40 23.52 590.40 34.22Q590.40 44.83 585.02 52.46Q579.65 60.10 569.81 64.22Q559.97 68.35 546.30 68.35ZM546.33 51.94Q550.85 51.94 554.49 50.74Q558.14 49.54 560.73 47.28Q563.33 45.02 564.67 41.94Q566.01 38.86 566.01 35.23L566.01 32.93Q566.01 29.32 564.67 26.27Q563.33 23.23 560.73 21.02Q558.14 18.82 554.49 17.62Q550.85 16.42 546.33 16.42Q541.82 16.42 538.17 17.62Q534.53 18.82 531.93 21.02Q529.34 23.23 528.00 26.27Q526.65 29.32 526.65 32.93L526.65 35.23Q526.65 38.86 528.00 41.94Q529.34 45.02 531.93 47.28Q534.53 49.54 538.17 50.74Q541.82 51.94 546.33 51.94Z" } }
        }
    }
    // Fila de la tabla de "Ajuste fino": numero, ajuste, que hace y el control a la derecha.
    // Tiene titulo y destello, asi el buscador la encuentra.
    component FilaTabla: Item {
        id: ft
        property int numero
        property string titulo
        property string que
        property string sub: ""
        // Depende de un ajuste apagado: se ve al 40 % y no responde.
        property bool atenuada: false
        property bool resaltada: false      // fondo apenas mas claro (p. ej. un atajo que se esta grabando)
        property bool sinNumero: false      // sin la columna "#" (filas del bloque Avanzado)
        Rectangle { anchors.fill: parent; color: Qt.alpha(Estilo.texto, 0.05); visible: ft.resaltada }
        opacity: atenuada ? 0.4 : 1
        enabled: !atenuada
        Behavior on opacity { NumberAnimation { duration: Estilo.t(200) } }
        default property alias control: ladoFt.data
        function destello() { brilloFt.restart() }
        width: parent ? parent.width : 0; height: 62
        Rectangle {
            id: luzFt
            anchors { fill: parent; topMargin: 4; bottomMargin: 4 }
            radius: 10; color: Estilo.texto; opacity: 0
            SequentialAnimation {
                id: brilloFt
                PauseAnimation { duration: Estilo.t(260) }
                NumberAnimation { target: luzFt; property: "opacity"; to: 0.1; duration: Estilo.t(180) }
                NumberAnimation { target: luzFt; property: "opacity"; to: 0; duration: Estilo.t(900) }
            }
        }
        Text {
            visible: !ft.sinNumero
            x: 8; anchors.verticalCenter: parent.verticalCenter
            text: String(ft.numero).padStart(2, "0"); color: Estilo.texto2
            font { family: "JetBrains Mono"; pixelSize: 13 }
        }
        // Los titulos largos pasan a dos lineas en vez de montarse sobre "Que hace".
        Texto { x: ft.sinNumero ? 18 : 62; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.3 - x - 10; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; text: ft.titulo; font { pixelSize: 15; weight: Font.DemiBold } }
        Texto {
            x: parent.width * 0.3; anchors.verticalCenter: parent.verticalCenter
            width: ladoFt.x - x - 16; elide: Text.ElideRight
            text: ft.que; color: Estilo.texto2; font.pixelSize: 14
        }
        Item {
            id: ladoFt
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            width: childrenRect.width; height: childrenRect.height
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Estilo.linea }
    }
    // Boton con flecha que abre una lista pequeña debajo (ventana emergente: no la corta el desplazable).
    // opciones: [[clave, texto], ...]; si "elegida" no esta en la lista se muestra textoOtro.
    component Desplegable: Rectangle {
        id: desp
        property var opciones: []
        property var elegida
        property string textoOtro: ""
        signal elegir(var clave)
        readonly property var actual: opciones.find(o => o[0] === elegida) ?? null
        width: filaDesp.implicitWidth + 28; height: 40; radius: 10
        color: zDesp.containsMouse || lista.visible ? Estilo.hover : Estilo.tarjeta
        border.width: 1; border.color: Estilo.borde
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        Row {
            id: filaDesp
            anchors.centerIn: parent; spacing: 8
            Texto { anchors.verticalCenter: parent.verticalCenter; text: desp.actual ? desp.actual[1] : desp.textoOtro; font.pixelSize: 15 }
            Simbolo {
                anchors.verticalCenter: parent.verticalCenter
                text: "expand_more"; font.pixelSize: 18; color: Estilo.texto2
                rotation: lista.visible ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
            }
        }
        MouseArea { id: zDesp; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lista.visible = !lista.visible }
        PopupWindow {
            id: lista
            anchor.item: desp
            anchor.rect: Qt.rect(0, desp.height + 6, desp.width, 0)
            anchor.edges: Edges.Top | Edges.Right
            anchor.gravity: Edges.Bottom | Edges.Left
            grabFocus: true                 // un clic fuera la cierra
            implicitWidth: Math.max(desp.width, 170)
            implicitHeight: columnaLista.implicitHeight + 10
            color: "transparent"
            Rectangle {
                anchors.fill: parent; radius: 12
                color: Estilo.tarjeta; border.width: 1; border.color: Estilo.borde
                Column {
                    id: columnaLista
                    x: 5; y: 5; width: parent.width - 10
                    Repeater {
                        model: desp.opciones
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool esta: modelData[0] === desp.elegida
                            width: columnaLista.width; height: 36; radius: 8
                            color: zOp.containsMouse ? Estilo.realce : Estilo.nada
                            Texto { x: 12; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1]; font.pixelSize: 14 }
                            Simbolo { visible: parent.esta; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: "check"; font.pixelSize: 17 }
                            MouseArea {
                                id: zOp; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { const c = parent.modelData[0]; lista.visible = false; desp.elegir(c); }
                            }
                        }
                    }
                }
            }
        }
    }
    // Texto que rueda al cambiar: el valor nuevo entra por un lado y el viejo sale por el otro.
    // sentido 1: sube (el nuevo entra por abajo); -1: baja (entra por arriba).
    component Rodillo: Item {
        id: ro
        property string valor
        property int sentido: 1
        property bool centrar: false      // cifras: centradas en su hueco mientras cambia el ancho
        property color color
        property font fuente
        // Sin enlace a "valor": si fuera un enlace, a veces se actualiza antes que onValorChanged
        // y el viejo ya traeria el valor nuevo (el numero "saltaba" sin animar).
        property string mostrado
        property string viejo: ""
        property real paso: 1
        onValorChanged: {
            if (valor === mostrado) return;
            if (!mostrado) { mostrado = valor; return; }            // al aparecer: sin rodar
            // Cambio encima de otro a medio rodar: si el anterior apenas empezaba, solo se cambia el que
            // entra y sigue el mismo giro; si ya casi llegaba, pasa a ser el que sale. Asi nada brinca.
            if (rodar.running && paso < 0.5) { mostrado = valor; return; }
            viejo = mostrado; mostrado = valor; rodar.restart();
        }
        NumberAnimation on paso { id: rodar; running: false; from: 0; to: 1; duration: Estilo.t(520); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos }
        // El ancho pasa del viejo al nuevo con el mismo paso: las cifras de al lado no brincan.
        implicitWidth: tViejo.implicitWidth + (tNuevo.implicitWidth - tViejo.implicitWidth) * paso
        implicitHeight: tNuevo.implicitHeight
        clip: true
        Text { id: tViejo; x: ro.centrar ? (ro.width - implicitWidth) / 2 : 0; visible: ro.paso < 1; text: ro.viejo; color: ro.color; font: ro.fuente
               y: -ro.sentido * ro.paso * ro.height; opacity: 1 - ro.paso }
        Text { id: tNuevo; x: ro.centrar ? (ro.width - implicitWidth) / 2 : 0; text: ro.mostrado; color: ro.color; font: ro.fuente
               y: ro.sentido * (1 - ro.paso) * ro.height; opacity: ro.paso }
    }
    // Lo que va detras de "Mostrar mas": todo se dibuja siempre y se recorta; cerrado se ve hasta el
    // final de los primeros `visibles` hijos del contenido (o hasta alturaCerrada, si se da).
    // Se abre y se cierra con la misma curva que las tarjetas plegables.
    component Revelar: Item {
        id: rv
        default property alias contenido: interiorRv.data
        property bool abierto
        property int visibles
        readonly property bool esRevelar: true
        signal pedirAbrir()           // el buscador encontro algo escondido aqui
        property real alturaCerrada: {
            const capa = interiorRv.children[0];
            if (!capa) return 0;
            let m = 0, n = 0;
            for (const c of capa.children) {
                if (!c.visible || c.height === 0) continue;     // el Repeater y lo oculto no cuentan
                if (n++ >= visibles) break;
                m = Math.max(m, c.y + c.height);
            }
            return m;
        }
        property real despliegue: abierto ? 1 : 0
        Behavior on despliegue { NumberAnimation { duration: Estilo.t(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
        width: parent ? parent.width : 0
        height: alturaCerrada + Math.max(0, interiorRv.height - alturaCerrada) * despliegue
        clip: true
        Item { id: interiorRv; width: parent.width; height: children.length ? children[0].height : 0 }
    }
    // Luz suave y quieta alrededor de la Gota: "luz" del tema en el centro, se funde en acento2.
    component Halo: Shape {
        id: halo
        property real cx
        property real cy
        property real radio: 100
        property real fuerza: 0.22
        property color tono: Estilo.luz
        property color tono2: Estilo.acento2
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: halo.cx; centerY: halo.cy; centerRadius: halo.radio
                focalX: halo.cx; focalY: halo.cy
                GradientStop { position: 0; color: Qt.alpha(halo.tono, halo.fuerza) }
                GradientStop { position: 0.45; color: Qt.alpha(halo.tono2, halo.fuerza * 0.32) }
                GradientStop { position: 1; color: Qt.alpha(halo.tono2, 0) }
            }
            PathRectangle { width: halo.width; height: halo.height }
        }
    }
    // La isla en pequeño, con la forma elegida y las mismas cuentas que Isla.qml (cuelga del borde
    // de arriba con sus hombros). La isla de verdad es una ventana propia: aqui va su dibujo.
    component IslaMini: Item {
        id: im
        property real ancho: 150
        property real alto: 42
        property real esquina: 20
        property real hombro: 18
        readonly property string forma: Estilo.valor("islaForma")
        readonly property var ajuste: Estilo.ajusteForma(forma)
        default property alias contenido: cuerpoIsla.data
        width: ancho + 4 * hombro; height: alto
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 1; strokeColor: Estilo.borde; fillColor: Estilo.fondo
                PathSvg { path: Estilo.trazoForma(Estilo.mitadForma(im.forma, (im.width - im.ancho) / 2 - im.ajuste[0], im.alto, im.esquina, Math.min(im.hombro, im.esquina * 0.9)), im.width / 2) }
            }
        }
        Item { id: cuerpoIsla; x: (im.width - im.ancho) / 2; y: im.ajuste[1]; width: im.ancho; height: im.alto - im.ajuste[1] }
    }
    // Franja de arriba en pequeño: la isla y los botones puestos en sus cuatro sitios (Esquina.qml).
    // separacion: aire entre la isla y las pildoras de su lado.
    component PreviaBotones: Rectangle {
        id: pb
        property real separacion: 8
        property bool soloCentro: false      // solo la isla y los botones pegados a ella
        property string resaltado: ""        // boton con anillo
        signal tocado(string clave)
        color: "transparent"
        clip: true
        function icono(c) { return (Estilo.botonesCatalogo.find(x => x[0] === c) || ["", "", "help"])[2] }
        IslaMini {
            id: islaPB
            anchors.horizontalCenter: parent.horizontalCenter
            ancho: 92; alto: 36; esquina: 16; hombro: 12
            Texto { anchors.centerIn: parent; text: Qt.formatTime(reloj.date, Estilo.valor("reloj12") ? "h:mm AP" : "H:mm"); font { pixelSize: 13; weight: Font.DemiBold } }
        }
        Repeater {
            model: Estilo.zonasBotones
            delegate: Rectangle {
                id: sitioPB
                required property string modelData
                required property int index
                readonly property bool junto: modelData.endsWith("Isla")
                readonly property var lista: Estilo.botones[modelData]
                visible: lista.length > 0 && (junto || !pb.soloCentro)
                width: filaPB.width + (junto ? 8 : 0); height: 30; radius: 15; y: 3
                color: junto ? Estilo.fondo : "transparent"
                border.width: junto ? 1 : 0; border.color: Estilo.borde
                x: index === 0 ? 8 : index === 3 ? pb.width - 8 - width
                    : index === 1 ? islaPB.x - pb.separacion - width : islaPB.x + islaPB.width + pb.separacion
                Behavior on x { enabled: pb.separacion === 8; NumberAnimation { duration: Estilo.t(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                Row {
                    id: filaPB
                    anchors.centerIn: parent; spacing: sitioPB.junto ? 0 : 4
                    Repeater {
                        model: sitioPB.lista
                        delegate: Rectangle {
                            required property string modelData
                            width: 26; height: 26; radius: 9
                            color: sitioPB.junto ? "transparent" : Estilo.fondo
                            border.width: sitioPB.junto ? 0 : 1; border.color: Estilo.borde
                            LogoMenisco { visible: parent.modelData === "menisco"; anchors.centerIn: parent; tam: 17 }
                            Simbolo { visible: parent.modelData !== "menisco"; anchors.centerIn: parent; text: pb.icono(parent.modelData); font.pixelSize: 15 }
                            // Anillo del boton resaltado (desde la lista o tocandolo aqui).
                            Rectangle {
                                anchors { fill: parent; margins: -3 }
                                radius: width / 2; color: "transparent"
                                border.width: 2; border.color: Estilo.acento
                                opacity: pb.resaltado === parent.modelData ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Estilo.t(200) } }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pb.tocado(parent.modelData) }
                        }
                    }
                }
            }
        }
    }
    // Un aviso de Hokum de ejemplo, con su tema "capsule" y los colores que Menisco le escribe.
    // Hokum es otro programa: aqui va su dibujo.
    component AvisoMini: Rectangle {
        width: 236; height: 58; radius: 29
        color: Estilo.tarjeta; border.width: 1; border.color: Estilo.borde
        Rectangle {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            width: 34; height: 34; radius: 17; color: Estilo.acento
            Simbolo { anchors.centerIn: parent; text: "chat_bubble"; font.pixelSize: 17; color: Estilo.sobreAcento }
        }
        Column {
            x: 56; anchors.verticalCenter: parent.verticalCenter; spacing: 1
            Texto { text: "Discord"; font { pixelSize: 13; weight: Font.DemiBold } }
            Texto { text: "Nuevo mensaje"; color: Estilo.texto2; font.pixelSize: 12 }
        }
        Texto { anchors { right: parent.right; rightMargin: 18; top: parent.top; topMargin: 11 } text: "ahora"; color: Estilo.texto2; font.pixelSize: 11 }
    }
    // Tarjeta de Inicio: arriba la pieza que configura, abajo su nombre y su valor; un clic lleva a
    // su pagina. Con el cursor encima, "fase" va y viene (0 a 1) y la pieza se anima; sin cursor y en
    // modo juego, todo quieto.
    component TarjetaPieza: Rectangle {
        id: tp
        property string titulo
        property string valor
        property real fase: 0
        readonly property bool activo: zTp.containsMouse && !Estilo.juego
        default property alias vista: cajaVista.data
        signal pulsado()
        height: 172; radius: 16
        color: Estilo.tarjeta
        border.width: 1; border.color: zTp.containsMouse ? Qt.alpha(Estilo.texto, 0.22) : Estilo.borde
        Behavior on border.color { ColorAnimation { duration: Estilo.t(160) } }
        SequentialAnimation {
            running: tp.activo; loops: Animation.Infinite
            NumberAnimation { target: tp; property: "fase"; to: 1; duration: 900; easing.type: Easing.InOutSine }
            PauseAnimation { duration: 700 }
            NumberAnimation { target: tp; property: "fase"; to: 0; duration: 900; easing.type: Easing.InOutSine }
            PauseAnimation { duration: 500 }
        }
        NumberAnimation { id: volverTp; target: tp; property: "fase"; to: 0; duration: 300; easing.type: Easing.OutCubic }
        onActivoChanged: if (!activo) volverTp.restart()
        ClippingRectangle {
            id: cajaVista
            x: 10; y: 10; width: parent.width - 20; height: 92; radius: 12
            color: Estilo.hundido
        }
        Column {
            x: 18; anchors { bottom: parent.bottom; bottomMargin: 14 }
            width: parent.width - 36; spacing: 2
            Texto { text: tp.titulo; width: parent.width; elide: Text.ElideRight; font { pixelSize: 15; weight: Font.DemiBold } }
            TextoCambiante { text: tp.valor; width: parent.width; elide: Text.ElideRight; color: Estilo.texto2; font { family: Estilo.letra; pixelSize: 13 } }
        }
        MouseArea { id: zTp; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tp.pulsado() }
    }
    // Encabezado de las paginas: el grupo en pequeño, el titulo grande y una linea que lo explica.
    component EncabezadoParte: Column {
        id: ep
        property string grupo
        property string titulo
        property string descripcion: ""
        property string textoBoton: ""        // boton pequeño a la derecha del titulo (opcional)
        signal boton()
        width: parent ? parent.width : 0
        topPadding: 14; spacing: 2
        Texto { text: ep.grupo; color: Estilo.texto2; font.pixelSize: 13 }
        Item {
            width: parent.width; height: tituloEp.height
            Texto { id: tituloEp; text: ep.titulo; font { pixelSize: 30; weight: Font.Bold; letterSpacing: -0.6 } }
            Rectangle {
                visible: ep.textoBoton !== ""
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: filaBotonEp.width + 28; height: 32; radius: 10
                color: zBotonEp.containsMouse ? Estilo.realce : Estilo.tarjeta
                border.width: 1; border.color: Estilo.borde
                Row {
                    id: filaBotonEp
                    anchors.centerIn: parent; spacing: 6
                    Simbolo { anchors.verticalCenter: parent.verticalCenter; text: "restart_alt"; font.pixelSize: 16; color: Estilo.texto2 }
                    Texto { anchors.verticalCenter: parent.verticalCenter; text: ep.textoBoton; font.pixelSize: 13 }
                }
                MouseArea { id: zBotonEp; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ep.boton() }
            }
        }
        Texto { visible: ep.descripcion !== ""; text: ep.descripcion; color: Estilo.texto2; font.pixelSize: 15; width: parent.width; wrapMode: Text.WordWrap; topPadding: 4 }
    }
    // Escenario de las vistas previas: oscuro, con borde fino y una luz muy tenue arriba (sin rayo ni halo).
    component Escenario: Rectangle {
        default property alias contenido: interiorEsc.data
        width: parent ? parent.width : 0
        radius: 18; color: Estilo.lateral
        border.width: 1; border.color: Estilo.borde
        clip: true
        Rectangle {
            width: parent.width; height: 110; radius: 18
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(Estilo.luz, 0.05) }
                GradientStop { position: 1; color: Qt.alpha(Estilo.luz, 0) }
            }
        }
        Item { id: interiorEsc; anchors.fill: parent }
    }
    // Tabla de ajustes: # · Ajuste · Que hace · Ahora. Dentro van FilaTabla y SubtituloTabla.
    component TablaAjustes: Column {
        id: tablaAj
        default property alias filas: cuerpoTabla.data
        property string colAjuste: "AJUSTE"
        property string colAhora: "AHORA"
        width: parent ? parent.width : 0
        Item {
            width: parent.width; height: 34
            Repeater {
                model: [["#", 8], [tablaAj.colAjuste, 62], ["QUÉ HACE", 0.3]]
                Texto {
                    required property var modelData
                    x: modelData[1] < 1 ? parent.width * modelData[1] : modelData[1]
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData[0]; color: Estilo.texto2; font { pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.8 }
                }
            }
            Texto { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: tablaAj.colAhora; color: Estilo.texto2; font { pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.8 } }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Estilo.linea }
        }
        Column { id: cuerpoTabla; width: parent.width }
    }
    // Fila de titulo de grupo dentro de la tabla (sin numero).
    component SubtituloTabla: Item {
        property string texto
        property bool atenuada: false
        opacity: atenuada ? 0.4 : 1
        Behavior on opacity { NumberAnimation { duration: Estilo.t(200) } }
        width: parent ? parent.width : 0; height: 42
        Texto { x: 8; anchors { bottom: parent.bottom; bottomMargin: 9 } text: parent.texto; color: Estilo.texto2; font { pixelSize: 13; weight: Font.DemiBold } }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Estilo.linea }
    }
    // Interruptor suelto (para la columna "Ahora" de las tablas).
    component Llave: Rectangle {
        id: llave
        property bool encendido
        signal cambiar(bool v)
        width: 46; height: 26; radius: 13
        color: zLlave.containsMouse ? Estilo.aclarar(encendido ? Estilo.acento : Estilo.apagado) : encendido ? Estilo.acento : Estilo.apagado
        Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
        Rectangle {
            y: 3; width: 20; height: 20; radius: 10
            color: llave.encendido ? Estilo.sobreAcento : Estilo.texto2
            x: llave.encendido ? 23 : 3
            Behavior on x { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
        }
        MouseArea { id: zLlave; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: llave.cambiar(!llave.encendido) }
    }
    // Pieza en miniatura sobre el fondo real, con vidrio (el fondo de detras desenfocado, un poco
    // agrandado por la refraccion, con canto brillante y filo de color) o solida.
    component PiezaVidrio: Item {
        id: pv
        property Item fondo
        property bool vidrio: true
        property real refraccion: 1
        property real desenfoque: 0.15
        property real aberracion: 0.7
        property real brillo: 0.3
        property real radio: 18
        default property alias contenido: capaPieza.data
        ClippingRectangle {
            anchors.fill: parent; radius: pv.radio
            color: Estilo.tarjeta
            Item {
                visible: pv.vidrio
                x: -pv.x; y: -pv.y
                width: pv.fondo ? pv.fondo.width : 0; height: pv.fondo ? pv.fondo.height : 0
                transform: Scale {
                    origin.x: pv.x + pv.width / 2; origin.y: pv.y + pv.height / 2
                    xScale: 1 + 0.08 * pv.refraccion; yScale: 1 + 0.08 * pv.refraccion
                }
                Image {
                    anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                    source: pv.fondo ? pv.fondo.source : ""; sourceSize.width: 1400
                    layer.enabled: pv.vidrio
                    layer.effect: MultiEffect { blurEnabled: true; blur: pv.desenfoque; blurMax: 48 }
                }
            }
            Rectangle { anchors.fill: parent; color: pv.vidrio ? Qt.rgba(1, 1, 1, 0.05) : "transparent" }
            Item { id: capaPieza; anchors.fill: parent }
        }
        Rectangle {
            anchors.fill: parent; radius: pv.radio; color: "transparent"
            border.width: pv.vidrio ? 1 + 1.5 * pv.brillo : 1
            border.color: pv.vidrio ? Qt.rgba(1, 1, 1, 0.16 + 0.5 * pv.brillo) : Estilo.borde
        }
        Rectangle {
            visible: pv.vidrio && pv.aberracion > 0
            anchors { fill: parent; margins: -1.5 }
            radius: pv.radio + 1.5; color: "transparent"
            border.width: 1.5; border.color: Qt.rgba(0.55, 0.45, 1, 0.5 * pv.aberracion)
        }
    }
    // Rayas diagonales neutras, como el fondo de transparencia de un editor de imagenes.
    component Rayas: Item {
        clip: true
        Row {
            anchors.centerIn: parent
            rotation: -45
            Repeater {
                model: 40
                Rectangle { required property int index; width: 9; height: 400; color: index % 2 ? Qt.tint(Estilo.hundido, Qt.alpha(Estilo.texto, 0.07)) : Estilo.hundido }
            }
        }
    }
    // Bloque "Avanzado": un solo contenedor con filas que se abren (FilaAvanzada).
    component Avanzado: Rectangle {
        default property alias filas: listaAv.data
        width: parent ? parent.width : 0
        height: listaAv.implicitHeight
        radius: 14; color: Estilo.tarjeta
        border.width: 1; border.color: Estilo.borde
        clip: true
        Column { id: listaAv; width: parent.width }
    }
    // Fila de "Avanzado": titulo y resumen; al abrirla muestra sus ajustes (en tabla) debajo.
    component FilaAvanzada: Item {
        id: fav
        property string titulo
        property string resumen: ""
        property real relleno: 0
        property bool abierto: false
        readonly property bool esPlegable: true
        default property alias contenido: cuerpoAv.data
        function destello() { abierto = true }
        property real despliegue: abierto ? 1 : 0
        Behavior on despliegue { NumberAnimation { duration: Estilo.t(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
        width: parent ? parent.width : 0
        height: 62 + (cuerpoAv.implicitHeight + 2 * relleno + 8) * despliegue
        clip: true
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Estilo.linea; visible: fav.parent && fav.parent.children[0] !== fav }
        Item {
            width: parent.width; height: 62
            Rectangle { anchors { fill: parent; margins: 3 } radius: 10; color: zFav.containsMouse ? Estilo.realce : Estilo.nada; Behavior on color { ColorAnimation { duration: Estilo.t(140) } } }
            Column {
                x: 18; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 70; spacing: 2
                Texto { text: fav.titulo; font { pixelSize: 15; weight: Font.DemiBold } }
                Texto { visible: fav.resumen !== ""; text: fav.resumen; color: Estilo.texto2; font.pixelSize: 13; width: parent.width; elide: Text.ElideRight }
            }
            Simbolo {
                anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                text: "chevron_right"; color: Estilo.texto2; font.pixelSize: 20
                rotation: 90 * fav.despliegue
            }
            MouseArea { id: zFav; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: fav.abierto = !fav.abierto }
        }
        Column {
            id: cuerpoAv
            x: 12 + fav.relleno; y: 62 + fav.relleno
            width: parent.width - 24 - 2 * fav.relleno
            visible: fav.despliegue > 0
        }
    }
    // Selector de sitio de un boton, dibujado como la barra: dos casillas, la muesca de la isla
    // (no se elige) y otras dos. La elegida va rellena del acento; cada casilla dice su nombre.
    component SelectorSitio: Rectangle {
        id: sel
        property string zona
        readonly property bool ayuda: repSel.count > 0 && [0, 1, 2, 3].some(k => repSel.itemAt(k) && repSel.itemAt(k).encima)
        signal elegir(string zona)
        readonly property var nombres: ["Esquina izquierda", "Junto a la isla, a la izquierda", "Junto a la isla, a la derecha", "Esquina derecha"]
        width: filaSel.width + 10; height: 32; radius: 10
        color: Estilo.hundido; border.width: 1; border.color: Estilo.borde
        Row {
            id: filaSel
            anchors.centerIn: parent; spacing: 5
            Repeater {
                id: repSel
                model: 4
                delegate: Item {
                    id: casilla
                    required property int index
                    readonly property string clave: Estilo.zonasBotones[index]
                    readonly property bool elegida: sel.zona === clave
                    readonly property bool encima: zCasilla.containsMouse
                    width: 26 + (index === 1 ? 32 : 0); height: 20
                    Rectangle {
                        width: 26; height: 20; radius: 6
                        color: casilla.elegida ? Estilo.acento : zCasilla.containsMouse ? Estilo.realce : Estilo.nada
                        border.width: casilla.elegida ? 0 : 1; border.color: zCasilla.containsMouse ? Estilo.texto2 : Estilo.borde
                        Behavior on color { ColorAnimation { duration: Estilo.t(180) } }
                        MouseArea {
                            id: zCasilla
                            anchors.fill: parent; anchors.margins: -2
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: if (!casilla.elegida) sel.elegir(casilla.clave)
                        }
                        // Ayuda: el nombre de la casilla, arriba.
                        Rectangle {
                            visible: zCasilla.containsMouse
                            anchors { bottom: parent.top; bottomMargin: 8; horizontalCenter: parent.horizontalCenter }
                            width: textoAyuda.implicitWidth + 16; height: 26; radius: 8
                            color: Estilo.tarjeta; border.width: 1; border.color: Estilo.borde
                            Texto { id: textoAyuda; anchors.centerIn: parent; text: sel.nombres[casilla.index]; font.pixelSize: 12 }
                        }
                    }
                    // La muesca de la isla, entre la segunda y la tercera casilla.
                    Shape {
                        visible: casilla.index === 1
                        x: 31; width: 26; height: 20
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: -1; fillColor: Qt.alpha(Estilo.texto, 0.22)
                            PathSvg { path: "M0 2 H26 L21 18 H5 Z" }
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
    // Una muestra por forma, dibujada con las mismas cuentas que la isla. clave: islaForma (pequena)
    // o islaFormaAbierta (vista grande, dibujada mas alta).
    component FormasIsla: Flow {
        id: formas
        property string clave
        readonly property real altoIsla: clave === "islaFormaAbierta" ? 30 : 20
    // La vista grande solo admite estas tres (las demas no le quedaban a un panel tan alto).
    readonly property var lista: clave === "islaFormaAbierta" ? Estilo.formasIsla.filter(f => ["clasica", "recta", "octagono"].includes(f[0])) : Estilo.formasIsla
        width: parent.width; spacing: 8
        Repeater {
            model: formas.lista
            delegate: Rectangle {
                id: muestraForma
                required property var modelData
                readonly property bool elegida: Estilo.valor(formas.clave) === modelData[0]
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
                            PathSvg { path: Estilo.trazoForma(Estilo.mitadForma(muestraForma.modelData[0], muestraForma.width / 2 - 34 - Estilo.ajusteForma(muestraForma.modelData[0])[0] / 2, formas.altoIsla, formas.altoIsla === 20 ? 9 : 12, 8), muestraForma.width / 2) }
                        }
                    }
                }
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 9 }
                    text: muestraForma.modelData[1]
                    color: muestraForma.elegida ? Estilo.texto : Estilo.texto2
                    font { family: Estilo.letra; pixelSize: 12; weight: muestraForma.elegida ? Font.DemiBold : Font.Normal }
                }
                MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaForma; anchors.fill: parent; hoverEnabled: true; onClicked: Estilo.poner(formas.clave, muestraForma.modelData[0]) }
            }
        }
    }
    component Encabezado: Texto {
        color: Estilo.texto2
        font { pixelSize: 13; weight: Font.Bold }
        topPadding: 14; bottomPadding: 8
    }
    component Desplazable: Flickable {
        default property alias contenido: columna.data
        // En paginas con pestanas (Pagina.partes) cada Desplazable es una subpagina.
        property int parte: 0
        readonly property bool conPestanas: !!parent && !!parent.partes && parent.partes.length > 0
        anchors.fill: parent
        anchors.topMargin: conPestanas ? 50 : 0
        opacity: !conPestanas || parent.parte === parte ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Estilo.t(200); easing.type: Easing.OutCubic } }
        contentHeight: columna.implicitHeight + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column { id: columna; width: parent.width; topPadding: -14 }
    }
    component Grupo: Rectangle {
        id: grupo
        default property alias filas: lista.data
        // visibles > 0: solo esas primeras filas a la vista y "Mostrar N más" debajo para el resto.
        // (No usarlo con filas que tengan su propio "visible": se lo pisa.)
        property int visibles: 0
        property bool mas: false
        readonly property var filasReales: { const r = []; for (const c of lista.children) if (c.titulo !== undefined) r.push(c); return r; }
        readonly property int ocultas: visibles > 0 ? Math.max(0, filasReales.length - visibles) : 0
        function aplicar() { if (visibles > 0) filasReales.forEach((f, i) => f.visible = mas || i < visibles); }
        onMasChanged: aplicar()
        onFilasRealesChanged: aplicar()
        width: parent ? parent.width : 0
        height: lista.implicitHeight + (ocultas > 0 ? 40 : 0)
        Behavior on height { enabled: grupo.ocultas > 0; NumberAnimation { duration: Estilo.t(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
        clip: ocultas > 0
        radius: 12
        color: Estilo.tarjeta
        border.width: 1; border.color: Estilo.borde
        Column { id: lista; width: parent.width }
        MostrarMas { visible: grupo.ocultas > 0; y: lista.implicitHeight; abierto: grupo.mas; cuantas: grupo.ocultas; onPulsado: grupo.mas = !grupo.mas }
    }
    // Fila "Mostrar N más" / "Mostrar menos", con la flecha que gira.
    component MostrarMas: Item {
        id: mm
        property bool abierto
        property int cuantas
        property bool linea: true
        signal pulsado()
        width: parent ? parent.width : 0; height: 40
        Rectangle { visible: mm.linea; width: parent.width; height: 1; color: Estilo.linea }
        Rectangle {
            anchors { fill: parent; margins: 3 }
            radius: 9; color: zMm.containsMouse ? Estilo.realce : Estilo.nada
            Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        }
        Row {
            anchors.centerIn: parent; spacing: 4
            Simbolo {
                anchors.verticalCenter: parent.verticalCenter
                text: "expand_more"; font.pixelSize: 19; color: zMm.containsMouse ? Estilo.texto : Estilo.texto2
                rotation: mm.abierto ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Estilo.t(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
            }
            Texto {
                anchors.verticalCenter: parent.verticalCenter
                text: mm.abierto ? "Mostrar menos" : "Mostrar " + mm.cuantas + " más"
                font.weight: Font.DemiBold; color: zMm.containsMouse ? Estilo.texto : Estilo.texto2
            }
        }
        MouseArea { id: zMm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mm.pulsado() }
    }
    // Tarjeta que se pliega: cabecera con icono, titulo y un resumen de lo que guarda.
    // relleno: margen alrededor del contenido cuando no son filas (muestras, rejillas).
    component Plegable: Item {
        id: pleg
        property string icono
        property string titulo
        property string resumen: ""
        property real relleno: 0
        property bool abierto: false
        readonly property bool esPlegable: true
        default property alias contenido: cuerpo.data
        function destello() { abierto = true }      // el buscador la encuentra por su titulo
        property real despliegue: abierto ? 1 : 0
        Behavior on despliegue { NumberAnimation { duration: Estilo.t(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
        width: parent ? parent.width : 0
        height: 8 + tarjetaPleg.height
        Rectangle {
            id: tarjetaPleg
            y: 8; width: parent.width
            height: 54 + (cuerpo.implicitHeight + 1 + 2 * pleg.relleno) * pleg.despliegue
            radius: 12; color: Estilo.tarjeta
            border.width: 1; border.color: Estilo.borde
            clip: true
            Item {
                width: parent.width; height: 54
                Rectangle {
                    anchors { fill: parent; margins: 3 }
                    radius: 9; color: zPleg.containsMouse ? Estilo.realce : Estilo.nada
                    Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                }
                Rectangle {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30; radius: 8; color: Estilo.hover
                    Simbolo { anchors.centerIn: parent; text: pleg.icono; font.pixelSize: 17 }
                }
                Column {
                    anchors { left: parent.left; leftMargin: 54; right: flechaPleg.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    Texto { text: pleg.titulo; width: parent.width; elide: Text.ElideRight }
                    Texto { visible: pleg.resumen !== ""; text: pleg.resumen; color: Estilo.texto2; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
                }
                Simbolo {
                    id: flechaPleg
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "expand_more"; color: Estilo.texto2; font.pixelSize: 20
                    rotation: 180 * pleg.despliegue
                }
                MouseArea { id: zPleg; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pleg.abierto = !pleg.abierto }
            }
            Rectangle { y: 54; width: parent.width; height: 1; color: Estilo.linea; visible: pleg.despliegue > 0 }
            Column {
                id: cuerpo
                x: pleg.relleno; y: 55 + pleg.relleno
                width: parent.width - 2 * pleg.relleno
                visible: pleg.despliegue > 0
            }
        }
    }
    // Titulo grande de la seccion y una frase que dice para que sirve.
    component Cabecera: Column {
        id: cabecera
        property string titulo
        property string descripcion
        width: parent ? parent.width : 0
        topPadding: 14; bottomPadding: 2; spacing: 3
        Texto { text: cabecera.titulo; font { pixelSize: 20; weight: Font.Bold; letterSpacing: -0.3 } }
        Texto { text: cabecera.descripcion; color: Estilo.texto2; width: parent.width; wrapMode: Text.WordWrap }
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
        ControlSegmentos { opciones: seg.opciones; claves: seg.claves; elegida: seg.elegida; onElegir: c => seg.elegir(c) }
    }
    // Segmentos sueltos (con pastilla que se desliza). grande: el tamaño de las tablas.
    // apagadas: claves que no se pueden elegir ahora (se ven al 40 %).
    component ControlSegmentos: Rectangle {
        id: cs
        property var opciones: []
        property var claves: []
        property var elegida
        property var apagadas: []
        property bool grande: false
        signal elegir(var clave)
        width: filaSeg.width + 6; height: grande ? 38 : 26; radius: grande ? 11 : 9; color: Estilo.hundido
        border.width: grande ? 1 : 0; border.color: Estilo.borde
        // pastilla que se desliza a la opcion elegida
        Rectangle {
            readonly property var hijo: repSeg.count, repSeg.itemAt(Math.max(0, cs.claves.indexOf(cs.elegida)))
            visible: cs.claves.indexOf(cs.elegida) >= 0
            x: hijo ? hijo.x + 3 : 3; width: hijo ? hijo.width : 0
            y: 3; height: parent.height - 6; radius: cs.grande ? 8 : 7; color: Estilo.activo
            border.width: 1; border.color: Estilo.activoBorde
            Behavior on x { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
            Behavior on width { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
        }
        Row {
            id: filaSeg
            x: 3; anchors.verticalCenter: parent.verticalCenter
            Repeater {
                id: repSeg
                model: cs.opciones
                delegate: Texto {
                    required property string modelData
                    required property int index
                    readonly property bool apagada: cs.apagadas.some(a => a === cs.claves[index])
                    text: modelData
                    leftPadding: cs.grande ? 14 : 10; rightPadding: cs.grande ? 14 : 10; topPadding: 4; bottomPadding: 4
                    font.pixelSize: cs.grande ? 14 : 12
                    font.weight: cs.claves[index] === cs.elegida ? Font.DemiBold : Font.Normal
                    opacity: apagada ? 0.4 : 1
                    color: cs.claves[index] === cs.elegida ? Estilo.enActivo : zSeg.containsMouse && !apagada ? Estilo.texto : Estilo.texto2
                    Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                    MouseArea { cursorShape: apagada ? Qt.ArrowCursor : Qt.PointingHandCursor; id: zSeg; hoverEnabled: true; anchors.fill: parent; onClicked: if (!parent.apagada) cs.elegir(cs.claves[index]) }
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
        readonly property real vivo: cdDesl.vivo    // mientras se arrastra
        signal soltado(real v)
        ControlDeslizador { id: cdDesl; desde: desl.desde; hasta: desl.hasta; valor: desl.valor; unidad: desl.unidad; onSoltado: v => desl.soltado(v) }
    }
    // Deslizador con su valor a la derecha; "vivo" sigue al dedo mientras se arrastra (las vistas
    // previas lo leen) y "soltado" avisa al soltar, que es cuando se guarda.
    component ControlDeslizador: Row {
        id: cd
        property real desde: 0
        property real hasta: 100
        property real valor: 0
        property string unidad: ""
        property real largo: 170
        property real vivo: valor
        onValorChanged: vivo = valor
        signal soltado(real v)
        spacing: 10
        Item {
            width: cd.largo; height: 20
            anchors.verticalCenter: parent.verticalCenter
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Estilo.apagado }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: perillaCd.x + 9; height: 4; radius: 2; color: Estilo.acento }
            Rectangle {
                id: perillaCd
                width: 18; height: 18; radius: 9; color: Estilo.texto
                anchors.verticalCenter: parent.verticalCenter
                x: (cd.vivo - cd.desde) / (cd.hasta - cd.desde) * (parent.width - width)
                scale: zonaCd.pressed ? 1.15 : 1
                Behavior on scale { NumberAnimation { duration: Estilo.t(200); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
            }
            MouseArea {
                id: zonaCd
                cursorShape: Qt.PointingHandCursor
                anchors.fill: parent; anchors.margins: -6
                function mover(m) { cd.vivo = Math.round(cd.desde + Math.max(0, Math.min(1, (m.x - 6 - 9) / (width - 12 - 18))) * (cd.hasta - cd.desde)); }
                onPressed: m => mover(m)
                onPositionChanged: m => mover(m)
                onReleased: cd.soltado(cd.vivo)
            }
        }
        Texto { width: 48; horizontalAlignment: Text.AlignRight; text: Math.round(cd.vivo) + cd.unidad; color: Estilo.texto2; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
    }
    // Editor de secciones de la barra lateral: a la izquierda una miniatura de la barra con
    // un bloque por seccion, que se reordenan arrastrandolos (los demas le hacen hueco); a la
    // derecha, interruptores para mostrar u ocultar cada una. Se guarda al soltar.
    // Vista previa de la barra lateral: una pantalla en miniatura con el panel en su lado, su altura
    // y su ancho, y bloques con su contenido real en pequeño. Se reordenan como en el iPhone:
    // mantener pulsado levanta el bloque, los demas tiemblan y se apartan, y al soltar se guarda.
    // A la derecha, que secciones se ven.
    component EditorSecciones: Row {
        id: ed
        spacing: 32
        readonly property var ids: ["rapidos", "sonido", "musica", "calendario", "energia"]
        readonly property var nombres: ({ rapidos: "Botones rápidos", sonido: "Sonido", musica: "Reproduciendo", calendario: "Calendario", energia: "Energía" })
        readonly property var iconos: ({ rapidos: "grid_view", sonido: "volume_up", musica: "music_note", calendario: "calendar_today", energia: "power_settings_new" })
        readonly property var altos: ({ rapidos: 72, sonido: 50, musica: 48, calendario: 122, energia: 44 })
        readonly property var guardadas: Estilo.barra.secciones
        // Orden en vivo: mientras se arrastra cambia aqui; al soltar se guarda en los ajustes.
        property var orden: guardadas.map(s => s.id)
        onGuardadasChanged: orden = guardadas.map(s => s.id)
        property string levantado: ""          // bloque que se esta moviendo
        readonly property bool tiembla: levantado !== "" && !Estilo.juego && Estilo.valor("rebote") !== "nada"
        function activa(id) { const s = guardadas.find(x => x.id === id); return s ? s.ver : false; }
        readonly property int arriba: 34        // alto del encabezado del panel
        function yDe(id) {
            let y = arriba;
            for (const k of orden) { if (k === id) return y; if (activa(k)) y += altos[k] + 6; }
            return y;
        }
        readonly property real altoMini: { let y = arriba; for (const k of orden) if (activa(k)) y += altos[k] + 6; return y + 4; }
        function guardar() { Estilo.ponerBarra("secciones", orden.map(id => ({ id: id, ver: activa(id) }))); }
        // Estado de los botones rapidos (los encendidos van en blanco).
        function rapidoEncendido(c) {
            return ({ red: true, bt: !!(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled), dnd: Estilo.noMolestar,
                      cafe: ventana.cafe, isla: !!(ventana.raiz && ventana.raiz.islaVisible), vidrio: ventana.vidrio })[c] || false;
        }
        readonly property var rapidosInfo: ({ red: ["lan", "Red"], bt: ["bluetooth", "Bluetooth"], dnd: ["dark_mode", "No molestar"], cafe: ["coffee", "Modo café"],
            captura: ["screenshot_region", "Captura"], isla: ["pill", "Isla"], vidrio: ["water_drop", "Liquid glass"], grabar: ["videocam", "Grabar"] })
        readonly property var musica: Mpris.players.values.find(pl => pl.isPlaying) ?? Mpris.players.values[0] ?? null

        // ---- Pantalla en miniatura ----
        ClippingRectangle {
            id: pantallaMini
            width: 400; height: 440; radius: 14
            color: "#000000"
            border.width: 1; border.color: Estilo.linea
            Image {
                anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                source: ventana.fondoActual ? "file://" + ventana.fondoActual : ""; sourceSize.width: 800
            }
            Rectangle { anchors.fill: parent; color: "#8c000000" }
            IslaMini { anchors.horizontalCenter: parent.horizontalCenter; ancho: 96; alto: 16; esquina: 8; hombro: 8 }

            Rectangle {
                id: mini
                readonly property real anchoVivo: typeof ctlAnchoBarra !== "undefined" ? ctlAnchoBarra.vivo : Estilo.barra.ancho
                width: 186 + (anchoVivo - 300) / 120 * 50
                height: Math.min(ed.altoMini, pantallaMini.height - 36)
                x: Estilo.barra.lado === "izquierda" ? 12 : pantallaMini.width - width - 12
                y: Estilo.barra.altura === "arriba" ? 26 : Estilo.barra.altura === "abajo" ? pantallaMini.height - height - 12 : (pantallaMini.height - height) / 2 + 6
                Behavior on x { NumberAnimation { duration: Estilo.t(340); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                Behavior on y { NumberAnimation { duration: Estilo.t(340); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                Behavior on width { NumberAnimation { duration: Estilo.t(200) } }
                Behavior on height { NumberAnimation { duration: Estilo.t(340); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                radius: 16; color: Estilo.fondo; border.width: 1; border.color: Estilo.borde
                // Encabezado: hora y fecha
                Texto { x: 12; y: 9; text: Qt.formatTime(reloj.date, Estilo.valor("reloj12") ? "h:mm AP" : "H:mm"); font { pixelSize: 14; weight: Font.Bold } }
                Texto { anchors { right: parent.right; rightMargin: 12 } y: 12; text: Qt.locale("es_MX").toString(reloj.date, "ddd d MMM").replace(/\./g, ""); color: Estilo.texto2; font.pixelSize: 10 }

                Repeater {
                    model: ed.ids
                    delegate: Rectangle {
                        id: bloque
                        required property string modelData
                        required property int index
                        readonly property bool activo: ed.activa(modelData)
                        readonly property bool alzado: ed.levantado === modelData
                        x: 8; width: mini.width - 16; height: ed.altos[modelData]
                        radius: 11; color: Estilo.tarjeta
                        border.width: alzado ? 1.5 : 1; border.color: alzado ? Estilo.acento : Estilo.linea
                        y: ed.yDe(modelData)
                        Behavior on y { enabled: !bloque.alzado; NumberAnimation { duration: Estilo.t(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                        opacity: activo ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Estilo.t(240) } }
                        z: alzado ? 5 : 1
                        scale: alzado ? 1.04 : 1
                        Behavior on scale { NumberAnimation { duration: Estilo.t(200); easing.type: Easing.OutCubic } }
                        // Temblor de los que no estan levantados (como al editar la pantalla de inicio del iPhone).
                        SequentialAnimation on rotation {
                            running: ed.tiembla && !bloque.alzado
                            loops: Animation.Infinite
                            PauseAnimation { duration: bloque.index * 37 }
                            NumberAnimation { to: 0.6; duration: 110; easing.type: Easing.InOutSine }
                            NumberAnimation { to: -0.6; duration: 220; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0; duration: 110; easing.type: Easing.InOutSine }
                            onRunningChanged: if (!running) bloque.rotation = 0
                        }
                        RectangularShadow {
                            z: -1
                            anchors.fill: parent; radius: parent.radius
                            blur: 18; offset.y: 6; color: "#a0000000"
                            opacity: bloque.alzado ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Estilo.t(200) } }
                        }

                        // Botones rapidos: los cuatro primeros elegidos, encendidos en blanco
                        Grid {
                            visible: bloque.modelData === "rapidos"
                            anchors { fill: parent; margins: 6 } columns: 2; spacing: 5
                            Repeater {
                                model: Estilo.barra.rapidos.slice(0, 4)
                                Rectangle {
                                    required property string modelData
                                    readonly property bool encendido: ed.rapidoEncendido(modelData)
                                    width: (parent.width - 5) / 2; height: (parent.height - 5) / 2; radius: 8
                                    color: encendido ? "#f2f2f3" : Estilo.hover
                                    Row {
                                        x: 7; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                        Simbolo { anchors.verticalCenter: parent.verticalCenter; text: (ed.rapidosInfo[parent.parent.modelData] || ["help"])[0]; font.pixelSize: 11; color: parent.parent.encendido ? "#000000" : Estilo.texto }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: (ed.rapidosInfo[parent.parent.modelData] || ["", ""])[1]; color: parent.parent.encendido ? "#000000" : Estilo.texto; font { family: Estilo.letra; pixelSize: 9; weight: Font.DemiBold } }
                                    }
                                }
                            }
                        }
                        // Sonido: volumen y microfono
                        Column {
                            visible: bloque.modelData === "sonido"
                            anchors { fill: parent; margins: 9 } spacing: 10
                            Repeater {
                                model: [["volume_up", 0.55], ["mic", 0.75]]
                                Row {
                                    required property var modelData
                                    spacing: 6
                                    Simbolo { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0]; font.pixelSize: 11; color: Estilo.texto2 }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: bloque.width - 40; height: 5; radius: 2.5; color: Estilo.apagado
                                        Rectangle { width: parent.width * parent.parent.modelData[1]; height: parent.height; radius: 2.5; color: Estilo.texto }
                                    }
                                }
                            }
                        }
                        // Reproduciendo: caratula, titulo, artista y play
                        Item {
                            visible: bloque.modelData === "musica"
                            anchors { fill: parent; margins: 7 }
                            ClippingRectangle {
                                id: caratulaMini
                                width: 34; height: 34; radius: 7; color: Estilo.hover
                                anchors.verticalCenter: parent.verticalCenter
                                Simbolo { anchors.centerIn: parent; visible: !imagenCaratula.source.toString(); text: "music_note"; font.pixelSize: 15; color: Estilo.texto2 }
                                Image { id: imagenCaratula; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; source: ed.musica ? ed.musica.trackArtUrl || "" : ""; sourceSize: Qt.size(64, 64) }
                            }
                            Column {
                                anchors { left: caratulaMini.right; leftMargin: 8; right: playMini.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                Text { width: parent.width; elide: Text.ElideRight; text: ed.musica && ed.musica.trackTitle ? ed.musica.trackTitle : "Nada sonando"; color: Estilo.texto; font { family: Estilo.letra; pixelSize: 10; weight: Font.DemiBold } }
                                Text { width: parent.width; elide: Text.ElideRight; text: ed.musica ? ed.musica.trackArtist || "" : ""; color: Estilo.texto2; font { family: Estilo.letra; pixelSize: 9 } }
                            }
                            Rectangle {
                                id: playMini
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: 22; height: 22; radius: 11; color: "#f2f2f3"
                                Simbolo { anchors.centerIn: parent; text: ed.musica && ed.musica.isPlaying ? "pause" : "play_arrow"; font.pixelSize: 13; color: "#000000" }
                            }
                        }
                        // Calendario: el mes de hoy, con la semana como en los ajustes
                        Item {
                            visible: bloque.modelData === "calendario"
                            anchors { fill: parent; margins: 8 }
                            readonly property date hoy: reloj.date
                            readonly property bool lunes: Estilo.barra.semanaLunes
                            readonly property int desfase: { const d = new Date(hoy.getFullYear(), hoy.getMonth(), 1).getDay(); return lunes ? (d + 6) % 7 : d; }
                            readonly property int dias: new Date(hoy.getFullYear(), hoy.getMonth() + 1, 0).getDate()
                            Text { text: Qt.locale("es_MX").toString(parent.hoy, "MMMM").replace(/^./, c => c.toUpperCase()); color: Estilo.texto; font { family: Estilo.letra; pixelSize: 10; weight: Font.DemiBold } }
                            Grid {
                                y: 16; width: parent.width; columns: 7
                                readonly property real celda: width / 7
                                Repeater {
                                    model: parent.parent.lunes ? ["L", "M", "M", "J", "V", "S", "D"] : ["D", "L", "M", "M", "J", "V", "S"]
                                    Text { required property string modelData; width: parent.celda; horizontalAlignment: Text.AlignHCenter; text: modelData; color: Estilo.texto2; font { family: Estilo.letra; pixelSize: 7 } }
                                }
                                Repeater {
                                    model: 42
                                    Item {
                                        required property int index
                                        readonly property int dia: index - parent.parent.desfase + 1
                                        readonly property bool hoy: dia === parent.parent.hoy.getDate()
                                        width: parent.celda; height: 13
                                        visible: dia >= 1 && dia <= parent.parent.dias || index < 35
                                        Rectangle { anchors.centerIn: parent; width: 16; height: 11; radius: 5.5; color: "#f2f2f3"; visible: parent.hoy }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: parent.dia >= 1 && parent.dia <= parent.parent.parent.dias
                                            text: parent.dia; color: parent.hoy ? "#000000" : Estilo.texto2
                                            font { family: Estilo.letra; pixelSize: 7; weight: parent.hoy ? Font.Bold : Font.Normal }
                                        }
                                    }
                                }
                            }
                        }
                        // Energia: bloquear, suspender, reiniciar y apagar
                        Row {
                            visible: bloque.modelData === "energia"
                            anchors.centerIn: parent; spacing: 14
                            Repeater {
                                model: ["lock", "bedtime", "restart_alt", "power_settings_new"]
                                Rectangle {
                                    required property string modelData
                                    required property int index
                                    width: 26; height: 26; radius: 13; color: index === 3 ? Estilo.peligro : Estilo.hover
                                    Simbolo { anchors.centerIn: parent; text: parent.modelData; font.pixelSize: 13; color: parent.index === 3 ? "#ffffff" : Estilo.texto }
                                }
                            }
                        }

                        // Mantener pulsado lo levanta; arrastrando, los demas le hacen hueco; al soltar se guarda.
                        MouseArea {
                            anchors.fill: parent
                            pressAndHoldInterval: 320
                            cursorShape: bloque.alzado ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            drag.target: bloque.alzado ? bloque : null
                            drag.axis: Drag.YAxis
                            drag.minimumY: ed.arriba - 4; drag.maximumY: ed.altoMini - bloque.height - 4
                            onPressAndHold: ed.levantado = bloque.modelData
                            // Sin esto el desplazable de la pagina se queda con el movimiento vertical.
                            preventStealing: true
                            // Hueco nuevo, mirando a cada vecino TAL COMO SE VE: al subir, el borde de arriba
                            // del bloque tiene que pasar el centro del de encima; al bajar, el borde de abajo
                            // pasa el centro del de debajo (que esta corrido el alto del bloque). Asi un bloque
                            // alto llega a cualquier puesto y, al cruzarse, no se vuelven a cambiar enseguida.
                            onPositionChanged: if (bloque.alzado) {
                                const arribaB = bloque.y, abajoB = bloque.y + bloque.height;
                                const vis = ed.orden.filter(k => ed.activa(k));
                                const ocultas = ed.orden.filter(k => !ed.activa(k));
                                const actual = vis.indexOf(bloque.modelData);
                                const resto = vis.filter(k => k !== bloque.modelData);
                                let idx = actual, y = ed.arriba;
                                resto.forEach((k, r) => {
                                    if (r < actual) { if (arribaB < y + ed.altos[k] / 2) idx = Math.min(idx, r); }
                                    else if (abajoB > y + bloque.height + 6 + ed.altos[k] / 2) idx = Math.max(idx, r + 1);
                                    y += ed.altos[k] + 6;
                                });
                                resto.splice(idx, 0, bloque.modelData);
                                const nuevo = resto.concat(ocultas);
                                if (nuevo.join() !== ed.orden.join()) ed.orden = nuevo;
                            }
                            onReleased: if (bloque.alzado) {
                                ed.levantado = "";
                                bloque.y = Qt.binding(() => ed.yDe(bloque.modelData));
                                ed.guardar();
                            }
                            onCanceled: if (bloque.alzado) { ed.levantado = ""; bloque.y = Qt.binding(() => ed.yDe(bloque.modelData)); }
                        }
                    }
                }
            }
        }

        // ---- Lista de secciones ----
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: 360
            spacing: 12
            Texto { width: parent.width; wrapMode: Text.Wrap; text: "Mantén pulsado un bloque y arrástralo."; color: Estilo.texto2; font.pixelSize: 13 }
            Rectangle {
                width: parent.width; height: listaSecciones.height; radius: 14
                color: Estilo.tarjeta; border.width: 1; border.color: Estilo.borde
                Column {
                    id: listaSecciones
                    width: parent.width
                    Repeater {
                        model: ed.orden
                        delegate: Item {
                            required property string modelData
                            required property int index
                            width: listaSecciones.width; height: 56
                            Rectangle { visible: parent.index > 0; width: parent.width; height: 1; color: Estilo.linea }
                            Simbolo { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "drag_indicator"; color: Estilo.texto3; font.pixelSize: 16 }
                            Rectangle {
                                x: 40; anchors.verticalCenter: parent.verticalCenter
                                width: 30; height: 30; radius: 8; color: Estilo.hover
                                Simbolo { anchors.centerIn: parent; text: ed.iconos[parent.parent.modelData]; font.pixelSize: 16 }
                            }
                            Texto { x: 84; anchors.verticalCenter: parent.verticalCenter; text: ed.nombres[parent.modelData]; font.pixelSize: 15 }
                            Llave {
                                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                encendido: ed.activa(parent.modelData)
                                onCambiar: v => Estilo.ponerBarra("secciones", ed.orden.map(id => ({ id: id, ver: id === parent.modelData ? v : ed.activa(id) })))
                            }
                        }
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

    // Una tecla como un keycap: fondo oscuro, borde fino y el borde de abajo mas grueso.
    component Tecla: Rectangle {
        id: tecla
        property string texto
        width: Math.max(34, textoTecla.implicitWidth + 22); height: 34; radius: 8
        color: Qt.alpha(Estilo.texto, 0.2)
        Rectangle {
            anchors { fill: parent; margins: 1; bottomMargin: 3 }
            radius: 7; color: Qt.tint(Estilo.fondo, Qt.alpha(Estilo.texto, 0.09))
            Texto { id: textoTecla; anchors.centerIn: parent; text: tecla.texto; font { pixelSize: 14; weight: Font.DemiBold } }
        }
    }
    // Las teclas de un atajo. Pulsar las teclas (o "Sin asignar") lo pone a grabar; si la nueva
    // combinacion ya la usa otro atajo, avisa antes de guardar.
    component TeclasAtajo: Item {
        id: ta
        property string clave
        readonly property bool esperando: ventana.capturando === clave
        readonly property bool choca: !!ventana.conflicto && ventana.conflicto.id === clave
        readonly property var partes: (ventana.atajos[clave] || "").split("+").filter(x => x)
        width: esperando ? grabando.width : choca ? avisoChoque.width : partes.length ? filaTeclas.width : sinAsignar.width
        height: 40
        function grabar() { ventana.errorAtajo = ""; ventana.conflicto = null; ventana.capturando = ta.clave; }
        Row {
            id: filaTeclas
            visible: !ta.esperando && !ta.choca && ta.partes.length > 0
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 6
            Repeater { model: ta.partes; Tecla { required property string modelData; texto: ventana.nombreTeclaVista(modelData) } }
        }
        Item {
            id: sinAsignar
            visible: !ta.esperando && !ta.choca && ta.partes.length === 0
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: textoSin.implicitWidth + 30; height: 36
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"; strokeColor: Qt.alpha(Estilo.texto, 0.35); strokeWidth: 1.2
                    strokeStyle: ShapePath.DashLine; dashPattern: [3, 3]
                    PathRectangle { x: 0.6; y: 0.6; width: sinAsignar.width - 1.2; height: sinAsignar.height - 1.2; radius: 9 }
                }
            }
            Texto { id: textoSin; anchors.centerIn: parent; text: "Sin asignar · Asignar"; color: Estilo.texto2; font.pixelSize: 14 }
        }
        MouseArea {
            visible: filaTeclas.visible || sinAsignar.visible
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: ta.grabar()
        }
        // Grabando: punto rojo que late y la nota.
        Rectangle {
            id: grabando
            visible: ta.esperando
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: filaGrab.width + 30; height: 38; radius: 10
            color: Estilo.tarjeta; border.width: 1.5; border.color: Estilo.acento
            Row {
                id: filaGrab
                anchors.centerIn: parent; spacing: 9
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: 4; color: Estilo.peligro
                    SequentialAnimation on opacity {
                        running: ta.esperando && !Estilo.juego; loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                    }
                }
                Texto { anchors.verticalCenter: parent.verticalCenter; text: "Pulsa la nueva combinación…"; font { pixelSize: 14; weight: Font.DemiBold } }
            }
        }
        // Choque con otro atajo
        Row {
            id: avisoChoque
            visible: ta.choca
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8
            Texto {
                anchors.verticalCenter: parent.verticalCenter
                text: ventana.conflicto ? "Ya la usa " + ventana.nombresAtajo[ventana.conflicto.otro] + ". ¿Intercambiarlas?" : ""
                color: Estilo.texto; font.pixelSize: 13
            }
            Repeater {
                model: [["Intercambiar", true], ["Cancelar", false]]
                Rectangle {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: textoOp.implicitWidth + 24; height: 32; radius: 9
                    color: modelData[1] ? Estilo.acento : zOp.containsMouse ? Estilo.realce : Estilo.tarjeta
                    border.width: modelData[1] ? 0 : 1; border.color: Estilo.borde
                    Texto { id: textoOp; anchors.centerIn: parent; text: parent.modelData[0]; color: parent.modelData[1] ? Estilo.sobreAcento : Estilo.texto; font { pixelSize: 13; weight: Font.DemiBold } }
                    MouseArea { id: zOp; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.modelData[1] ? ventana.intercambiar() : (ventana.conflicto = null) }
                }
            }
        }
    }
    // Campo de texto suelto (para la columna "Ahora"); guarda al terminar de escribir.
    component ControlCampo: Rectangle {
        id: cc
        property string texto
        property string marcador: ""
        signal guardar(string t)
        width: 260; height: 40; radius: 10
        color: Estilo.tarjeta; border.width: 1; border.color: entradaCc.activeFocus ? Estilo.acento : Estilo.borde
        onTextoChanged: if (!entradaCc.activeFocus) entradaCc.text = texto
        TextInput {
            id: entradaCc
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            text: cc.texto
            color: Estilo.texto; selectionColor: Estilo.texto3
            font { family: Estilo.letra; pixelSize: 15 }
            onEditingFinished: if (text !== cc.texto) cc.guardar(text)
            Texto { visible: !entradaCc.text; anchors.verticalCenter: parent.verticalCenter; text: cc.marcador; color: Estilo.texto3; font.pixelSize: 15 }
        }
    }
    // Pagina: al cambiar de seccion, la nueva entra con fundido y se desliza 16 px
    // desde la derecha; la vieja se va hacia la izquierda.
    component Pagina: Item {
        id: pagina
        property string clave
        property bool activa
        property var partes: []     // nombres de las subpaginas; vacio = sin pestanas
        property int parte: 0
        // Pestanas arriba: misma pastilla que Segmentos, pero a todo el ancho.
        Rectangle {
            visible: pagina.partes.length > 0
            width: parent.width; height: 36; radius: 11; color: Estilo.hundido
            z: 2
            Rectangle {
                readonly property real ancho: (parent.width - 6) / Math.max(1, pagina.partes.length)
                x: 3 + pagina.parte * ancho; y: 3; width: ancho; height: 30; radius: 8
                color: Estilo.activo; border.width: 1; border.color: Estilo.activoBorde
                Behavior on x { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
            }
            Row {
                x: 3; y: 3
                Repeater {
                    model: pagina.partes
                    delegate: Item {
                        required property string modelData
                        required property int index
                        width: (pagina.width - 6) / pagina.partes.length; height: 30
                        Texto {
                            anchors.centerIn: parent
                            text: modelData; font.pixelSize: 13
                            font.weight: pagina.parte === index ? Font.DemiBold : Font.Normal
                            color: pagina.parte === index ? Estilo.enActivo : zPestana.containsMouse ? Estilo.texto : Estilo.texto2
                            Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                        }
                        MouseArea { id: zPestana; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pagina.parte = index }
                    }
                }
            }
        }
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
    // Un dock pequeno sobre el fondo de pantalla real, con el mismo dibujo que Dock.qml: relleno,
    // reflejo, filo degradado y radio concentrico. El vidrio se imita desenfocando lo que queda
    // detras. Con "manchas", un patron de prueba de colores en vez del fondo (las tarjetas de
    // material: asi se nota la diferencia entre materiales). Con "indicadores", punto en las
    // abiertas y pildora en la enfocada, como el ajuste elegido.
    component MuestraDock: ClippingRectangle {
        id: md
        property string material
        property int icono: 18
        property bool manchas: false
        property bool indicadores: false
        color: manchas ? Estilo.hundido : "#3a3f4a"
        Manchas { id: manchasMd; visible: md.manchas; anchors.fill: parent }
        Image {
            id: fondoMd
            visible: !md.manchas
            anchors.fill: parent
            source: ventana.fondoActual ? "file://" + ventana.fondoActual : ""
            fillMode: Image.PreserveAspectCrop; sourceSize.width: 640; asynchronous: true
        }
        Item {
            id: dk
            readonly property var asp: Estilo.aspectoDock(md.material, ventana.tonoMY)
            readonly property bool vidrio: Estilo.dockConVidrio(md.material)
            readonly property int relleno: Math.round(md.icono * 0.19)
            readonly property int radio: Math.round(md.icono * 0.225) + relleno
            readonly property int pie: Math.max(2, Math.round(md.icono * 0.125))
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Math.round(md.icono * 0.45) }
            width: filaIconos.width + relleno * 2 + 4; height: md.icono + relleno * 2 + pie
            ClippingRectangle {
                anchors.fill: parent; radius: dk.radio; color: "transparent"
                visible: dk.vidrio
                Image {
                    visible: !md.manchas
                    x: -dk.x; y: -dk.y; width: md.width; height: md.height
                    source: fondoMd.source; fillMode: Image.PreserveAspectCrop; sourceSize.width: 640; asynchronous: true
                    layer.enabled: true
                    layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 32; saturation: 0.05 }
                }
                Manchas {
                    visible: md.manchas
                    x: -dk.x; y: -dk.y; width: md.width; height: md.height
                    layer.enabled: true
                    layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 24; saturation: 0.05 }
                }
            }
            Rectangle {
                anchors.fill: parent; radius: dk.radio
                color: dk.asp.relleno
                Behavior on color { ColorAnimation { duration: Estilo.t(180) } }
                gradient: dk.asp.reflejo > 0 ? reflejoMd : null
                Gradient {
                    id: reflejoMd
                    GradientStop { position: 0; color: Qt.tint(dk.asp.relleno, Qt.rgba(1, 1, 1, dk.asp.reflejo)) }
                    GradientStop { position: 0.4; color: dk.asp.relleno }
                }
            }
            Shape {
                id: filoMd
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                function rect(x, y, w, h, r) {
                    return `M${x + r} ${y} H${x + w - r} A${r} ${r} 0 0 1 ${x + w} ${y + r} V${y + h - r} A${r} ${r} 0 0 1 ${x + w - r} ${y + h} `
                         + `H${x + r} A${r} ${r} 0 0 1 ${x} ${y + h - r} V${y + r} A${r} ${r} 0 0 1 ${x + r} ${y} Z`;
                }
                readonly property var f: dk.asp.filo || [0, 0, 0]
                function tono(k) { return dk.asp.color !== undefined ? dk.asp.color : Qt.rgba(1, 1, 1, f[k]); }
                ShapePath {
                    strokeWidth: -1
                    fillRule: ShapePath.OddEvenFill
                    fillGradient: LinearGradient {
                        y1: 0; y2: dk.height
                        GradientStop { position: 0; color: filoMd.tono(0) }
                        GradientStop { position: 0.35; color: filoMd.tono(1) }
                        GradientStop { position: 0.7; color: filoMd.tono(1) }
                        GradientStop { position: 1; color: filoMd.tono(2) }
                    }
                    PathSvg {
                        readonly property real a: dk.asp.ancho
                        path: filoMd.rect(0, 0, dk.width, dk.height, dk.radio)
                            + " " + filoMd.rect(a, a, dk.width - 2 * a, dk.height - 2 * a, Math.max(0, dk.radio - a))
                    }
                }
            }
            Row {
                id: filaIconos
                x: dk.relleno + 2; y: dk.relleno
                spacing: Math.round(md.icono * 0.22)
                Repeater {
                    model: ventana.iconosDock.slice(0, 5)
                    delegate: Image {
                        required property string modelData
                        required property int index
                        width: md.icono; height: md.icono; sourceSize: Qt.size(64, 64); source: ventana.iconoApp(modelData)
                        // Abiertas: la 1.ª (enfocada), la 2.ª y la ultima.
                        Rectangle {
                            readonly property bool pildora: index === 0 && Estilo.valor("dockIndicador") === "pildora"
                            visible: md.indicadores && (index === 0 || index === 1 || index === 4)
                            anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: Math.max(1, dk.pie / 2) }
                            width: pildora ? 14 : 4; height: 4; radius: 2
                            color: pildora ? Estilo.acento : Qt.rgba(1, 1, 1, 0.6)
                            Behavior on width { NumberAnimation { duration: Estilo.t(180); easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }
    }
    // Patron de prueba para las tarjetas de material: manchas de color sobre oscuro (no el fondo de
    // pantalla, que se repetiria en todas las tarjetas).
    component Manchas: Item {
        clip: true
        Rectangle { anchors.fill: parent; color: "#14151a" }
        Repeater {
            // Tres manchas que se juntan justo donde va el dock: asi cada material deja ver otra cosa.
            model: [[0.18, 0.5, "#ff7a3d"], [0.82, 0.45, "#3d7bff"], [0.5, 1.0, "#5fcf5a"]]
            Rectangle {
                required property var modelData
                width: parent.width * 0.5; height: width; radius: width / 2
                x: parent.width * modelData[0] - width / 2; y: parent.height * modelData[1] - height / 2
                color: modelData[2]
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 40 }
            }
        }
    }
    component TarjetaMaterial: Rectangle {
        id: tm
        required property var modelData          // [clave, nombre, descripcion]
        readonly property bool elegido: Estilo.valor("dockMaterial") === modelData[0]
        height: 154; radius: 14
        // Elegida: solo el borde del acento (1.5 px), sin relleno.
        color: zonaTm.containsMouse && !elegido ? Estilo.realce : Estilo.tarjeta
        border.width: elegido ? 1.5 : 1; border.color: elegido ? Estilo.acento : Estilo.borde
        Behavior on color { ColorAnimation { duration: Estilo.t(160) } }
        scale: zonaTm.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(120); easing.type: Easing.OutCubic } }
        MuestraDock { x: 6; y: 6; width: parent.width - 12; height: 72; radius: 10; material: tm.modelData[0]; icono: 14; manchas: true }
        Column {
            x: 11; y: 88; width: parent.width - 22; spacing: 2
            Texto { width: parent.width; text: tm.modelData[1]; font { pixelSize: 14; weight: Font.DemiBold } elide: Text.ElideRight }
            Texto { width: parent.width; text: tm.modelData[2]; color: Estilo.texto2; font.pixelSize: 12; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
        }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaTm; anchors.fill: parent; hoverEnabled: true; onClicked: Estilo.poner("dockMaterial", tm.modelData[0]) }
    }
}
