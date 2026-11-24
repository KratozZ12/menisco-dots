// Tipografia Geist (Estilo.fuenteSans / fuenteMono); iconos Material Symbols Rounded; solo colores de Estilo.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

// Barra lateral (centro de control): entra por un lado con Super+A y se va con Escape.
// Pagina principal: fecha, botones rapidos, niveles, equipo, calendario, energia y reproductor.
// Subpaginas: Bluetooth, Red y Salida de sonido.
PanelWindow {
    id: barra

    required property var raiz
    required property var ajustes       // comparte No molestar y Modo cafe con la ventana de ajustes

    readonly property bool abierta: raiz.barraAbierta
    property string pagina: "inicio"
    property string confirmar: ""        // "reiniciar" o "apagar" esperan un segundo clic
    property bool menuEnergia: false     // el menu pequeno de Energia (estilo "boton")

    // Lado, altura y ancho salen de los ajustes (seccion Barra lateral).
    readonly property var cfg: Estilo.barra
    readonly property bool derecha: cfg.lado !== "izquierda"
    readonly property bool energiaEnBoton: cfg.energia.estilo !== "fila" && cfg.secciones.some(s => s.id === "energia" && s.ver)
    anchors.right: derecha
    anchors.left: !derecha
    // La ventana es mas grande que el panel (holgura a cada lado): cuando el rebote lo agranda
    // un poco, no choca con los bordes de la ventana ni se ve cortado.
    readonly property int holgura: 24
    // Con el marco encendido la barra sale de el: su lado de fuera es el borde del marco, con
    // hombros arriba y abajo, y entra deslizandose desde detras del borde (el recorte la tapa ahi).
    // "tapa" es la parte del panel que queda escondida detras del borde para que el rebote no deje
    // un hueco entre el panel y el marco.
    readonly property real g: Estilo.grosorMarco
    readonly property bool enMarco: g > 0
    readonly property real tapa: enMarco ? 40 : 0
    readonly property real hombro: 14
    implicitWidth: cfg.ancho + holgura * 2
    // Alto fijo (toda la pantalla): si la ventana cambiara de alto con cada pagina, niri tendria
    // que reconfigurarla en cada cuadro de la animacion y se veia a saltos. Solo el panel cambia;
    // la mascara hace que el resto no reciba clics.
    implicitHeight: screen ? screen.height : 1080
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "barra"
    WlrLayershell.keyboardFocus: abierta ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    visible: abierta || panel.mostrar > 0.01
    mask: Region { x: panel.x; y: panel.y; width: panel.width; height: panel.height }

    onAbiertaChanged: {
        if (abierta) {
            pagina = "inicio"; confirmar = ""; menuEnergia = false; cpuHist = []; leerRed.running = true; panel.forceActiveFocus();
            leerBrillo();
            if (!clima.temp || Date.now() - climaHora > 1800000) lecturaClima.running = true;
        }
        else if (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering) Bluetooth.defaultAdapter.discovering = false;
    }
    function cerrar() { raiz.barraAbierta = false }
    function ejecutar(cmd) { Quickshell.execDetached(cmd) }
    function ir(p) {
        pagina = p; menuEnergia = false;
        if (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering !== (p === "bt")) Bluetooth.defaultAdapter.discovering = p === "bt";
        if (p === "red") leerRed.running = true;
    }

    // ---- Red (NetworkManager) ----
    property var cables: []     // [{ dispositivo, conectado, velocidad }]
    property var redesWifi: []  // [{ ssid, senal, segura, activa }]
    property bool hayWifi: false
    Process {
        id: leerRed
        running: true   // al arrancar, para que el boton Red no cambie de color mientras la barra entra
        command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE device; echo ---; " +
            "for d in /sys/class/net/*; do [ -f $d/speed ] && echo \"$(basename $d):$(cat $d/speed 2>/dev/null)\"; done; echo ---; " +
            "nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [dev, vel, wifi] = text.split("---\n").map(s => (s || "").trim().split("\n").filter(l => l));
                const velocidades = {};
                for (const l of vel) { const [d, s] = l.split(":"); velocidades[d] = parseInt(s); }
                barra.cables = dev.map(l => l.split(":")).filter(c => c[1] === "ethernet")
                    .map(c => ({ dispositivo: c[0], conectado: c[2] === "connected", velocidad: velocidades[c[0]] || 0 }));
                barra.hayWifi = dev.some(l => l.split(":")[1] === "wifi");
                const vistas = {};
                barra.redesWifi = wifi.map(l => l.split(":")).filter(w => w[1] && !vistas[w[1]] && (vistas[w[1]] = true))
                    .map(w => ({ activa: w[0] === "yes", ssid: w[1], senal: parseInt(w[2]) || 0, segura: !!w[3] }));
            }
        }
    }
    property string redPidiendo: ""     // SSID que espera contrasena
    function conectarWifi(ssid, clave) {
        ejecutar(clave ? ["nmcli", "device", "wifi", "connect", ssid, "password", clave] : ["nmcli", "device", "wifi", "connect", ssid]);
        redPidiendo = "";
        releerRed.restart();
    }
    Timer { id: releerRed; interval: 2500; onTriggered: leerRed.running = true }

    // ---- Sonido ----
    readonly property var salida: Pipewire.defaultAudioSink
    readonly property var entrada: Pipewire.defaultAudioSource
    readonly property var salidas: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var apps: Pipewire.nodes.values.filter(n => n.isSink && n.isStream && n.audio)
    // Nombre legible de un flujo de audio: "PipeWire ALSA [sonora]" -> "Sonora".
    function nombreApp(n) {
        const s = n.properties["application.name"] || n.name || "";
        const m = s.match(/\[(.+)\]/);
        const r = m ? m[1] : s;
        return r.charAt(0).toUpperCase() + r.slice(1);
    }
    // Una fila por app aunque abra varios flujos (Sonora abre tres): el deslizador mueve todos.
    readonly property var appsAgrupadas: {
        const g = {};
        for (const n of apps) (g[nombreApp(n)] = g[nombreApp(n)] || []).push(n);
        return Object.keys(g).map(k => ({ nombre: k, nodos: g[k] }));
    }
    PwObjectTracker { objects: [barra.salida, barra.entrada].concat(barra.apps) }
    readonly property string nombreSalida: salida ? (salida.nickname || salida.description || salida.name || "") : ""
    function iconoSalida(n) {
        return /blue|buds|head|auric/i.test((n.name || "") + (n.nickname || n.description || "")) ? "headphones"
             : /hdmi|display/i.test((n.name || "") + (n.nickname || n.description || "")) ? "tv" : "speaker";
    }

    readonly property var reproductor: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    SystemClock { id: reloj; precision: SystemClock.Minutes }

    // ---- Datos en vivo: equipo, bajada de red y tiempo encendido, cada 2 s y solo con la barra abierta ----
    // Lo que no se puede leer queda en -1 y se muestra como "—".
    property real cpuUso: -1
    property real ramUsada: -1          // GB
    property real ramTotal: -1          // GB
    property real gpuTemp: -1
    property real gpuUso: -1            // %
    property real cpuTemp: -1           // grados
    property real cpuW: -1              // vatios (RAPL: diferencia de energia entre lecturas)
    property var raplAntes: null
    property var cpuHist: []            // ultimas 30 lecturas de uso de CPU (un minuto)
    property real uptime: -1            // segundos
    property string bajada: ""          // "2.4 MB/s"
    property var cpuAntes: null
    property var redAntes: null
    Process {
        id: leerEquipo
        command: ["sh", "-c", "head -1 /proc/stat; echo ---; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; echo ---; tail -n +3 /proc/net/dev; echo ---; " +
                              "nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>/dev/null; echo ---; cat /proc/uptime; echo ---; " +
                              "for h in /sys/class/hwmon/hwmon*; do case $(cat $h/name) in k10temp|coretemp|zenpower) cat $h/temp1_input;; esac; done | head -1; echo ---; " +
                              "cat /sys/class/powercap/intel-rapl:0/energy_uj 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [stat, mem, net, gpu, up, ctemp, rapl] = text.split("---\n");
                const n = (stat || "").trim().split(/\s+/).slice(1).map(Number);
                if (n.length > 4) {
                    const total = n.reduce((a, b) => a + b, 0), libre = n[3] + (n[4] || 0);
                    if (barra.cpuAntes && total > barra.cpuAntes[0]) {
                        barra.cpuUso = Math.round(100 * (1 - (libre - barra.cpuAntes[1]) / (total - barra.cpuAntes[0])));
                        barra.cpuHist = barra.cpuHist.concat([barra.cpuUso]).slice(-30);
                    }
                    barra.cpuAntes = [total, libre];
                }
                const kb = k => Number(((mem || "").match(new RegExp(k + ":\\s+(\\d+)")) || [0, 0])[1]);
                barra.ramUsada = kb("MemTotal") > 0 ? (kb("MemTotal") - kb("MemAvailable")) / 1048576 : -1;
                barra.ramTotal = kb("MemTotal") > 0 ? kb("MemTotal") / 1048576 : -1;
                let rx = 0;
                for (const l of (net || "").trim().split("\n")) {
                    const [nombre, datos] = l.split(":");
                    if (!datos || /^(lo|veth|docker|br-|virbr)/.test(nombre.trim())) continue;
                    rx += Number(datos.trim().split(/\s+/)[0]);
                }
                const ahora = Date.now();
                if (barra.redAntes) {
                    const bps = Math.max(0, (rx - barra.redAntes[0]) / ((ahora - barra.redAntes[1]) / 1000));
                    barra.bajada = bps >= 1e6 ? (bps / 1e6).toFixed(1) + " MB/s" : Math.round(bps / 1e3) + " KB/s";
                }
                barra.redAntes = [rx, ahora];
                const g = (gpu || "").trim().split(",").map(parseFloat);
                barra.gpuTemp = isNaN(g[0]) ? -1 : g[0];
                barra.gpuUso = isNaN(g[1]) ? -1 : g[1];
                const ct = parseFloat((ctemp || "").trim());
                barra.cpuTemp = isNaN(ct) ? -1 : Math.round(ct / 1000);
                const er = parseFloat((rapl || "").trim());
                if (isNaN(er)) barra.cpuW = -1;
                else {
                    if (barra.raplAntes && er >= barra.raplAntes[0]) barra.cpuW = (er - barra.raplAntes[0]) / 1e6 / ((ahora - barra.raplAntes[1]) / 1000);
                    barra.raplAntes = [er, ahora];
                }
                const u = parseFloat((up || "").trim());
                barra.uptime = isNaN(u) ? -1 : u;
            }
        }
    }
    Timer { interval: 2000; repeat: true; triggeredOnStart: true; running: barra.abierta; onTriggered: leerEquipo.running = true }
    function duracion(s) {
        if (s < 0) return "—";
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return d > 0 ? d + " d " + h + " h" : h > 0 ? h + " h " + m + " min" : m + " min";
    }
    function minutos(s) { return Math.floor(s / 60) + ":" + String(Math.floor(s % 60)).padStart(2, "0"); }

    // ---- Clima de afuera (el mismo servicio que el miniwidget de la isla; wttr.in ubica por la IP) ----
    property var clima: ({ temp: "", icono: "partly_cloudy_day", estado: "" })
    property double climaHora: 0
    Process {
        id: lecturaClima
        command: ["curl", "-sf", "--max-time", "10", "https://wttr.in/?format=%t|%x|%C&m&lang=es"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [t, x, c] = text.trim().split("|");
                if (!t || !/°/.test(t)) return;
                const icono = { "o": "clear_day", "m": "partly_cloudy_day", "mm": "cloud", "mmm": "cloud", "=": "foggy",
                                "/": "rainy", "//": "rainy", "///": "rainy", ".": "rainy", "x": "weather_mix",
                                "*": "weather_snowy", "**": "weather_snowy", "*/*": "weather_snowy", "*/": "weather_snowy", "x/": "weather_mix",
                                "/!/": "thunderstorm", "!/": "thunderstorm", "*!*": "thunderstorm" }[x] || "partly_cloudy_day";
                barra.clima = { temp: t.replace("+", "").replace("C", ""), icono: icono, estado: c || "" };
                barra.climaHora = Date.now();
            }
        }
    }

    // ---- Brillo (DDC con ddcutil: solo lo tienen los monitores que lo permiten; sin el, no hay columna) ----
    property string brilloBus: ""       // numero del bus I2C del primer monitor que responde
    property bool brilloBuscado: false
    property real brillo: -1            // 0..1
    property int brilloMax: 100
    property int brilloPendiente: -1
    function leerBrillo() {
        if (!brilloBuscado) { brilloBuscado = true; buscarBrillo.running = true; }
        else if (brilloBus !== "") leerVcp.running = true;
    }
    Process {
        id: buscarBrillo
        command: ["ddcutil", "detect", "--brief"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/\/dev\/i2c-(\d+)/);
                if (m) { barra.brilloBus = m[1]; leerVcp.running = true; }
            }
        }
    }
    Process {
        id: leerVcp
        command: ["ddcutil", "--bus", barra.brilloBus, "getvcp", "10", "--brief"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/VCP 10 C (\d+) (\d+)/);
                if (m && Number(m[2]) > 0) { barra.brilloMax = Number(m[2]); barra.brillo = Number(m[1]) / Number(m[2]); }
                else barra.brillo = -1;
            }
        }
    }
    // DDC es lento (~0.4 s por orden): mientras se arrastra se manda a lo mas una orden cada 450 ms, y al final la ultima.
    function ponerBrillo(v) { brillo = v; brilloPendiente = Math.round(v * brilloMax); if (!envioBrillo.running) envioBrillo.start(); }
    Timer {
        id: envioBrillo; interval: 450
        onTriggered: if (barra.brilloPendiente >= 0) {
            Quickshell.execDetached(["ddcutil", "--bus", barra.brilloBus, "setvcp", "10", String(barra.brilloPendiente), "--noverify"]);
            barra.brilloPendiente = -1;
            envioBrillo.start();
        }
    }

    // ---- Color de la caratula (mismo calculo que la isla). ColorQuantizer solo lee archivos locales. ----
    readonly property string arte: reproductor ? reproductor.trackArtUrl || "" : ""
    property string arteLocal: ""
    onArteChanged: {
        arteLocal = "";
        if (!arte) return;
        if (arte.startsWith("file://")) arteLocal = arte;
        else {
            const destino = Estilo.tmp + "/menisco-arte-" + Qt.md5(arte);
            bajarArte.command = ["sh", "-c", "[ -s \"$2\" ] || curl -sfL --max-time 8 -o \"$2\" \"$1\"", "sh", arte, destino];
            bajarArte.destino = destino;
            bajarArte.running = true;
        }
    }
    Component.onCompleted: arteChanged()
    // Si la cancion cambio mientras bajaba, se baja la nueva.
    Process {
        id: bajarArte; property string destino
        onExited: code => {
            const quiere = barra.arte && !barra.arte.startsWith("file://") ? Estilo.tmp + "/menisco-arte-" + Qt.md5(barra.arte) : "";
            if (quiere && quiere !== destino) { barra.arteChanged(); return; }
            if (code === 0 && quiere) barra.arteLocal = "file://" + destino;
        }
    }
    ColorQuantizer { id: cuantizador; source: barra.arteLocal; depth: 3; rescaleSize: 64 }
    readonly property color colorCaratula: {
        let mejor = null, puntos = -1;
        for (const c of cuantizador.colors) {
            const p = c.hsvSaturation * Math.min(1, c.hsvValue * 2);
            if (p > puntos) { puntos = p; mejor = c; }
        }
        if (!mejor) return Estilo.acento;
        if (mejor.hsvSaturation < 0.08) return Qt.hsva(0, 0, 0.65, 1);
        return Qt.hsva(mejor.hsvHue, Math.min(mejor.hsvSaturation, 0.85), Math.max(mejor.hsvValue, 0.75), 1);
    }
    // La posicion de MPRIS no avanza sola: se pide una vez por segundo mientras suena y la barra esta abierta.
    Timer { interval: 1000; repeat: true; running: barra.abierta && !!barra.reproductor && barra.reproductor.isPlaying; onTriggered: barra.reproductor.positionChanged() }

    // ---- Acciones de energia (las de siempre; reiniciar y apagar piden un segundo clic) ----
    function accionEnergia(id) {
        if ((id === "reiniciar" || id === "apagar") && confirmar !== id) { confirmar = id; return; }
        menuEnergia = false; confirmar = "";
        cerrar();
        if (id === "bloquear") raiz.bloquear();
        else if (id === "salir") raiz.pedirSalir();
        else if (id === "reiniciar") ejecutar(["systemctl", "reboot"]);
        else ejecutar(["systemctl", "poweroff"]);
    }
    readonly property var accionesEnergia: [
        { id: "bloquear", icono: "lock", texto: "Bloquear" },
        { id: "salir", icono: "logout", texto: "Salir" },
        { id: "reiniciar", icono: "restart_alt", texto: "Reiniciar" },
        { id: "apagar", icono: "power_settings_new", texto: "Apagar" }
    ]

    // ---- Panel ----
    // Hombros del marco: curvas que funden el panel con el borde arriba y abajo.
    Repeater {
        model: barra.enMarco ? [0, 1] : []
        Shape {
            required property int modelData        // 0 arriba, 1 abajo
            readonly property real s: barra.hombro
            width: s; height: s
            x: barra.derecha ? barra.width - barra.g - s : barra.g
            y: modelData === 0 ? panel.y - s : panel.y + panel.height
            opacity: Math.min(1, panel.mostrar * 3)
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { xScale: barra.derecha ? 1 : -1; yScale: modelData === 0 ? 1 : -1; origin.x: s / 2; origin.y: s / 2 }
            ShapePath {
                fillColor: Estilo.fondo; strokeWidth: -1
                PathSvg { path: `M${barra.hombro} 0Q${barra.hombro} ${barra.hombro} 0 ${barra.hombro}H${barra.hombro}Z` }
            }
        }
    }
    Item {
        id: recorte
        anchors { fill: parent; rightMargin: barra.derecha ? barra.g : 0; leftMargin: barra.derecha ? 0 : barra.g }
        clip: barra.enMarco
    Rectangle {
        id: panel
        // Alto = pagina visible; se anima al cambiar de pagina. Si no cabe en la pantalla, la pagina se desplaza.
        readonly property real altoPagina: [pInicio, pBt, pRed, pSonido].find(p => p.activa)?.implicitHeight ?? 0
        property real alto: 28 + altoPagina
        // Solo al cambiar de pagina: al abrir, el alto ya debe ser el final (si no, se ve crecer).
        Behavior on alto { enabled: panel.mostrar > 0.99; NumberAnimation { duration: Estilo.t(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
        // Margenes de arriba y abajo segun la altura elegida (abajo deja sitio al dock).
        readonly property real maxAlto: barra.cfg.altura === "arriba" ? parent.height - (barra.enMarco ? 78 : 56) - 96
                                      : barra.cfg.altura === "abajo" ? parent.height - 96 - barra.holgura
                                      : parent.height - barra.holgura * 2
        width: barra.cfg.ancho + barra.tapa
        height: Math.max(0, Math.min(alto, maxAlto))
        x: barra.enMarco ? (barra.derecha ? parent.width - barra.cfg.ancho : -barra.tapa)
         : barra.derecha ? parent.width - width - (barra.holgura - 14) : barra.holgura - 14
        // Arriba: bajo la isla (con marco, bajo la esquina). Abajo: sobre el dock. Centro: al medio.
        y: barra.cfg.altura === "arriba" ? (barra.enMarco ? 78 : 56)
         : barra.cfg.altura === "abajo" ? parent.height - height - 96
         : (parent.height - height) / 2
        radius: barra.enMarco ? 0 : 22
        // Con marco: solo redondas las esquinas de dentro.
        topLeftRadius: barra.enMarco && !barra.derecha ? 0 : 22
        bottomLeftRadius: barra.enMarco && !barra.derecha ? 0 : 22
        topRightRadius: barra.enMarco && barra.derecha ? 0 : 22
        bottomRightRadius: barra.enMarco && barra.derecha ? 0 : 22
        color: Estilo.fondo
        border.color: Estilo.borde
        border.width: barra.enMarco ? 0 : 1
        clip: true
        // Apertura: llega desde el lado recorriendo solo 48 px, crece desde 0.92 con el
        // borde de fuera como eje, y aparece con fundido; el rebote cabe en la holgura de la ventana.
        // Cierre: corto y sin rebote. "mostrar" va de 0 a 1 y de ella sale todo.
        property real mostrar: 0
        states: State { name: "abierta"; when: barra.abierta; PropertyChanges { target: panel; mostrar: 1 } }
        transitions: [
            Transition { to: "abierta"; NumberAnimation { property: "mostrar"; duration: Estilo.t(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } },
            // Cierre: arranca de inmediato y frena al final; el fundido acompana todo el recorrido.
            Transition { from: "abierta"; NumberAnimation { property: "mostrar"; duration: Estilo.t(300); easing.type: Easing.OutCubic } }
        ]
        opacity: barra.enMarco ? (mostrar > 0.01 ? 1 : 0) : barra.abierta ? Math.min(1, mostrar * 2.2) : mostrar
        transformOrigin: barra.derecha ? Item.Right : Item.Left
        scale: barra.enMarco ? 1 : 0.92 + 0.08 * mostrar
        transform: Translate { x: (1 - panel.mostrar) * (barra.enMarco ? barra.cfg.ancho + 10 : 48) * (barra.derecha ? 1 : -1) }
        focus: barra.abierta
        Keys.onEscapePressed: {
            if (barra.menuEnergia) { barra.menuEnergia = false; barra.confirmar = ""; }
            else barra.pagina === "inicio" ? barra.cerrar() : barra.ir("inicio");
        }

        // Paginas: entran deslizandose desde el lado hacia el que se navega.
        Flickable {
            id: desplaza
            anchors { fill: parent; margins: 14; rightMargin: 14 + (barra.derecha ? barra.tapa : 0); leftMargin: 14 + (barra.derecha ? 0 : barra.tapa) }
            contentWidth: width; contentHeight: cuerpo.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height + 1
            Item {
                id: cuerpo
                width: desplaza.width; height: panel.altoPagina

            Pagina {
                id: pInicio
                activa: barra.pagina === "inicio"
                lado: -1
                spacing: 10

                // Encabezado: el dia en grande, el dia de la semana y el mes, y a la derecha Ajustes (y Energia).
                Item {
                    width: parent.width; height: 66
                    Texto {
                        id: diaGrande
                        anchors.verticalCenter: parent.verticalCenter
                        text: reloj.date.getDate()
                        font { pixelSize: 54; weight: Font.Medium; letterSpacing: -2.16 }
                    }
                    Column {
                        anchors { left: diaGrande.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Texto { text: Qt.locale("es_MX").toString(reloj.date, "dddd"); font { pixelSize: 15; weight: Font.DemiBold } }
                        Texto { text: Qt.locale("es_MX").toString(reloj.date, "MMMM yyyy"); color: Estilo.texto2; font.pixelSize: 13 }
                    }
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        BotonCuadro { icono: "tune"; onPulsado: { barra.cerrar(); barra.raiz.abrirAjustes(); } }
                        BotonCuadro { visible: barra.energiaEnBoton; icono: "power_settings_new"; onPulsado: { barra.confirmar = ""; barra.menuEnergia = true; } }
                    }
                }
                // Clima de afuera y tiempo encendido.
                Item {
                    id: linea
                    width: parent.width; height: 20
                    readonly property real reservado: iconoClima.width + temp.implicitWidth + punto.implicitWidth + encendido.implicitWidth + tiempo.implicitWidth + 7 * 6
                    Row {
                        spacing: 6
                        Simbolo { id: iconoClima; anchors.verticalCenter: parent.verticalCenter; text: barra.clima.icono; relleno: 0; font.pixelSize: 16; color: Estilo.texto2 }
                        Texto { id: temp; anchors.verticalCenter: parent.verticalCenter; text: barra.clima.temp || "—"; font.pixelSize: 13 }
                        Texto {
                            id: estado; anchors.verticalCenter: parent.verticalCenter
                            text: barra.clima.estado; color: Estilo.texto2; font.pixelSize: 13
                            width: Math.min(implicitWidth, Math.max(0, linea.width - linea.reservado)); elide: Text.ElideRight
                            visible: text !== ""
                        }
                        Texto { id: punto; anchors.verticalCenter: parent.verticalCenter; text: "·"; color: Estilo.texto3; font.pixelSize: 13 }
                        Texto { id: encendido; anchors.verticalCenter: parent.verticalCenter; text: "Encendido"; color: Estilo.texto2; font.pixelSize: 13 }
                        Texto { id: tiempo; anchors.verticalCenter: parent.verticalCenter; text: barra.duracion(barra.uptime); font { family: Estilo.fuenteMono; pixelSize: 13 } }
                    }
                }

                // Secciones visibles en el orden elegido en los ajustes.
                Repeater {
                    model: barra.cfg.secciones.filter(s => s.ver)
                    delegate: Loader {
                        required property var modelData
                        width: pInicio.width
                        // Oculto se sale de la columna y no deja hueco (sin musica, la tarjeta no ocupa nada).
                        visible: modelData.id === "musica" ? !!barra.reproductor : modelData.id === "energia" ? barra.cfg.energia.estilo === "fila" : true
                        sourceComponent: ({ rapidos: cRapidos, niveles: cNiveles, equipo: cEquipo, musica: cMusica, calendario: cCalendario, energia: cEnergia })[modelData.id] ?? null
                    }
                }
            }

            Pagina {
                id: pBt
                activa: barra.pagina === "bt"
                Volver { text: "Bluetooth" }
                Rapido {
                    width: parent.width
                    icono: "bluetooth"; titulo: activa ? "Encendido" : "Apagado"; detalle: ""
                    activa: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false
                    onPulsado: Estilo.bluetooth(Bluetooth.defaultAdapter, !activa)
                }
                Encabezado { text: "Mis dispositivos"; visible: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled }
                Repeater {
                    model: Bluetooth.devices.values.filter(d => d.paired && Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled)
                    delegate: FilaBt {
                        required property var modelData
                        dispositivo: modelData
                    }
                }
                Encabezado { text: "Buscando cerca…"; visible: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled }
                Repeater {
                    model: Bluetooth.devices.values.filter(d => !d.paired && d.name && Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled).slice(0, 6)
                    delegate: FilaLista {
                        required property var modelData
                        icono: "devices_other"; titulo: modelData.name
                        detalle: modelData.pairing ? "Emparejando…" : "Toca para emparejar"
                        tenue: true
                        onPulsada: { modelData.trusted = true; modelData.pair(); }
                    }
                }
            }

            Pagina {
                id: pRed
                activa: barra.pagina === "red"
                Volver { text: "Red" }
                Repeater {
                    model: barra.cables
                    delegate: FilaLista {
                        required property var modelData
                        icono: "lan"; titulo: "Cable (" + modelData.dispositivo + ")"
                        detalle: modelData.conectado ? "Conectado" + (modelData.velocidad > 0 ? " · " + (modelData.velocidad >= 1000 ? modelData.velocidad / 1000 + " Gb/s" : modelData.velocidad + " Mb/s") : "") : "Desconectado"
                        marcada: modelData.conectado
                    }
                }
                Encabezado { text: "Wi-Fi" }
                Texto {
                    visible: !barra.hayWifi
                    width: parent.width; wrapMode: Text.Wrap; color: Estilo.texto2; font.pixelSize: 12; leftPadding: 8; rightPadding: 8
                    text: "Este equipo no tiene Wi-Fi."
                }
                Repeater {
                    model: barra.hayWifi ? barra.redesWifi.slice(0, 10) : []
                    delegate: Column {
                        required property var modelData
                        width: parent.width
                        FilaLista {
                            icono: modelData.senal > 66 ? "network_wifi" : modelData.senal > 33 ? "network_wifi_2_bar" : "network_wifi_1_bar"
                            titulo: modelData.ssid
                            detalle: modelData.activa ? "Conectada" : modelData.segura ? "Protegida" : "Abierta"
                            marcada: modelData.activa
                            onPulsada: if (!modelData.activa) { if (modelData.segura) barra.redPidiendo = modelData.ssid; else barra.conectarWifi(modelData.ssid, ""); }
                        }
                        Rectangle {
                            visible: barra.redPidiendo === modelData.ssid
                            width: parent.width; height: visible ? 38 : 0; radius: 12; color: Estilo.hundido
                            TextInput {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                color: Estilo.texto; font { family: Estilo.fuenteSans; pixelSize: 13 }
                                focus: parent.visible
                                onAccepted: barra.conectarWifi(modelData.ssid, text)
                                Texto { visible: !parent.text; text: "Contraseña y Enter"; color: Estilo.texto3; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                }
            }

            Pagina {
                id: pSonido
                activa: barra.pagina === "sonido"
                Volver { text: "Salida de sonido" }
                Repeater {
                    model: barra.salidas
                    delegate: FilaLista {
                        required property var modelData
                        readonly property string nombre: modelData.nickname || modelData.description || modelData.name
                        icono: barra.iconoSalida(modelData)
                        titulo: nombre
                        detalle: ""
                        marcada: barra.salida === modelData
                        onPulsada: Pipewire.preferredDefaultAudioSink = modelData
                    }
                }
                Encabezado { text: "Apps"; visible: barra.appsAgrupadas.length > 0 }
                Column {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: barra.appsAgrupadas
                        delegate: Nivel {
                            required property var modelData
                            etiqueta: modelData.nombre
                            valor: modelData.nodos[0].audio ? Math.min(1, modelData.nodos[0].audio.volume) : 0
                            onCambiar: v => modelData.nodos.forEach(n => { if (n.audio) n.audio.volume = v; })
                        }
                    }
                }
            }
            }
        }

        // Menu de Energia (estilo "boton"): el resto de la barra se oscurece; clic fuera o Escape lo cierra.
        Item {
            id: capaEnergia
            anchors.fill: parent; z: 20
            visible: opacity > 0.01
            opacity: barra.menuEnergia ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Estilo.t(180); easing.type: Easing.OutCubic } }
            Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.55 }
            MouseArea { anchors.fill: parent; enabled: barra.menuEnergia; onClicked: { barra.menuEnergia = false; barra.confirmar = ""; } }
            Rectangle {
                width: 200; height: colMenu.implicitHeight + 16; radius: 16
                color: Estilo.tarjeta; border.width: 1; border.color: Estilo.borde
                x: parent.width - width - 14 - (barra.derecha ? barra.tapa : 0)
                y: 80
                Column {
                    id: colMenu
                    x: 8; y: 8; width: parent.width - 16
                    Repeater {
                        model: barra.accionesEnergia
                        delegate: Rectangle {
                            id: filaMenu
                            required property var modelData
                            readonly property bool peligro: modelData.id === "apagar" || barra.confirmar === modelData.id
                            width: colMenu.width; height: 40; radius: 10
                            color: zonaMenu.containsMouse ? Estilo.realce : Estilo.nada
                            Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                            Simbolo { id: icMenu; x: 10; anchors.verticalCenter: parent.verticalCenter; text: filaMenu.modelData.icono; font.pixelSize: 18; color: filaMenu.peligro ? Estilo.peligro : Estilo.texto }
                            Texto {
                                anchors { left: icMenu.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: barra.confirmar === filaMenu.modelData.id ? "¿Seguro?" : filaMenu.modelData.texto
                                color: filaMenu.peligro ? Estilo.peligro : Estilo.texto; font.pixelSize: 15
                            }
                            MouseArea { id: zonaMenu; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: barra.accionEnergia(filaMenu.modelData.id) }
                        }
                    }
                }
            }
        }
    }
    }

    // ---- Secciones de la pagina principal (se ordenan y ocultan desde los ajustes) ----
    // Que hace cada boton rapido; los ids son los que se eligen en los ajustes.
    function rapido(id) {
        const bt = Bluetooth.defaultAdapter, btOn = bt ? bt.enabled : false;
        const conectado = Bluetooth.devices.values.find(d => d.connected);
        const cable = cables.some(c => c.conectado), wifi = redesWifi.find(w => w.activa);
        const m = (s) => String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
        switch (id) {
        // Red no alterna: apagar la red te dejaria sin conexion; la tarjeta entera abre su subpagina.
        case "red": return { icono: cable ? "lan" : "wifi", titulo: "Red", flecha: true, activa: cable || !!wifi,
                             detalle: cable ? "Cable" + (bajada ? " · ↓ " + bajada : "") : wifi ? wifi.ssid + (bajada ? " · ↓ " + bajada : "") : "Sin conexión",
                             fn: () => ir("red"), abrir: () => ir("red") };
        case "bt": return { icono: "bluetooth", titulo: "Bluetooth", flecha: true, activa: btOn,
                            detalle: !btOn ? "Apagado" : conectado ? conectado.name + (conectado.batteryAvailable ? " · " + Math.round(conectado.battery * 100) + " %" : "") : "Encendido",
                            fn: () => Estilo.bluetooth(bt, !btOn), abrir: () => ir("bt") };
        case "dnd": return { icono: "dark_mode", titulo: "No molestar", activa: ajustes.noMolestar,
                             detalle: ajustes.noMolestar ? "Activado" : "Apagado", fn: () => Estilo.ponerNoMolestar(!ajustes.noMolestar) };
        case "cafe": return { icono: "coffee", titulo: "Modo café", activa: ajustes.cafe,
                              detalle: ajustes.cafe ? "Sin suspender" : "Apagado", fn: () => ajustes.cafe = !ajustes.cafe };
        case "captura": return { icono: "screenshot_region", titulo: "Captura", activa: false, detalle: "Elegir zona",
                                 fn: () => { cerrar(); ejecutar(["sh", "-c", "sleep 0.5; qs -p '" + Estilo.carpeta + "' ipc call captura abrir zona"]); } };
        case "isla": return { icono: "pill", titulo: "Isla", activa: raiz.islaVisible, detalle: raiz.islaVisible ? "Visible" : "Oculta",
                              fn: () => raiz.islaVisible = !raiz.islaVisible };
        case "vidrio": return { icono: "water_drop", titulo: "Liquid glass", activa: ajustes.vidrio, detalle: ajustes.vidrio ? "Activado" : "Apagado",
                                fn: () => ajustes.alternarVidrio(!ajustes.vidrio) };
        case "grabar": return { icono: raiz.grabando ? "stop_circle" : "videocam", titulo: raiz.grabando ? "Grabando" : "Grabar pantalla",
                                activa: raiz.grabando, detalle: raiz.grabando ? m(raiz.segundosGrabando) : "Con sonido",
                                fn: () => { if (!raiz.grabando) cerrar(); raiz.alternarGrabacion(); } };
        }
        return null;
    }

    Component {
        id: cRapidos
        Grid {
            id: botones
            columns: 2; spacing: 8
            readonly property real ancho: (width - 8) / 2
            Repeater {
                model: barra.cfg.rapidos
                delegate: Rapido {
                    required property string modelData
                    readonly property var info: barra.rapido(modelData) || ({})
                    width: botones.ancho
                    icono: info.icono || ""; titulo: info.titulo || ""; detalle: info.detalle || ""
                    activa: !!info.activa; flecha: !!info.flecha
                    onPulsado: if (info.fn) info.fn()
                    onAbrir: if (info.abrir) info.abrir()
                }
            }
        }
    }

    // Niveles: volumen, microfono y brillo (este solo si el monitor lo deja cambiar por DDC) como columnas
    // con menisco, y debajo la salida de sonido.
    Component {
        id: cNiveles
        Rectangle {
            id: niveles
            width: parent.width
            height: contenido.implicitHeight + 24; radius: 16; color: Estilo.tarjeta
            readonly property int columnas: barra.brilloBus !== "" && barra.brillo >= 0 ? 3 : 2
            Column {
                id: contenido
                x: 12; y: 12; width: parent.width - 24
                spacing: 10
                Row {
                    id: filaNiveles
                    width: parent.width; spacing: 8
                    readonly property real ancho: (width - spacing * (niveles.columnas - 1)) / niveles.columnas
                    ColumnaNivel {
                        width: filaNiveles.ancho
                        icono: barra.salida && barra.salida.audio && barra.salida.audio.muted ? "volume_off" : "volume_up"
                        valor: barra.salida && barra.salida.audio ? Math.min(1, barra.salida.audio.volume) : 0
                        pulsable: true
                        onCambiar: v => { if (barra.salida && barra.salida.audio) { barra.salida.audio.muted = false; barra.salida.audio.volume = v; } }
                        onIconoPulsado: if (barra.salida && barra.salida.audio) barra.salida.audio.muted = !barra.salida.audio.muted
                    }
                    ColumnaNivel {
                        width: filaNiveles.ancho
                        icono: barra.entrada && barra.entrada.audio && barra.entrada.audio.muted ? "mic_off" : "mic"
                        valor: barra.entrada && barra.entrada.audio ? Math.min(1, barra.entrada.audio.volume) : 0
                        pulsable: true
                        onCambiar: v => { if (barra.entrada && barra.entrada.audio) { barra.entrada.audio.muted = false; barra.entrada.audio.volume = v; } }
                        onIconoPulsado: if (barra.entrada && barra.entrada.audio) barra.entrada.audio.muted = !barra.entrada.audio.muted
                    }
                    ColumnaNivel {
                        visible: niveles.columnas === 3
                        width: filaNiveles.ancho
                        icono: "light_mode"
                        valor: Math.max(0, barra.brillo)
                        onCambiar: v => barra.ponerBrillo(v)
                    }
                }
                Item {
                    width: parent.width; height: 26
                    Simbolo { id: icSalida; anchors.verticalCenter: parent.verticalCenter; text: barra.salida ? barra.iconoSalida(barra.salida) : "speaker"; font.pixelSize: 18; color: Estilo.texto2 }
                    Texto {
                        anchors { left: icSalida.right; leftMargin: 8; right: flechaSalida.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        textFormat: Text.StyledText; elide: Text.ElideRight; color: Estilo.texto2; font.pixelSize: 14
                        text: "Sale por <font color=\"" + Estilo.texto + "\">" + barra.nombreSalida.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</font>"
                    }
                    Simbolo { id: flechaSalida; anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: "chevron_right"; font.pixelSize: 18; color: Estilo.texto2 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: barra.ir("sonido") }
                }
            }
        }
    }

    // Equipo: CPU, RAM y GPU cada 2 s, en cuatro disenos que se eligen en Ajustes > Barra lateral.
    readonly property real ramPct: ramUsada >= 0 && ramTotal > 0 ? ramUsada / ramTotal : 0
    readonly property bool cpuCaliente: cpuUso >= 90
    readonly property bool gpuCaliente: gpuTemp >= Estilo.valor("avisoGrados")
    readonly property string tCpu: cpuUso >= 0 ? cpuUso + " %" : "—"
    readonly property string tRam: ramUsada >= 0 ? ramUsada.toFixed(1) + " GB" : "—"
    readonly property string tGpu: gpuTemp >= 0 ? Math.round(gpuTemp) + "°" : "—"
    Component {
        id: cEquipo
        Rectangle {
            width: parent.width; color: Estilo.tarjeta; radius: 16
            height: disenoEquipo.item ? disenoEquipo.item.implicitHeight : 0
            Loader {
                id: disenoEquipo
                width: parent.width
                sourceComponent: ({ anillos: cEqAnillos, barras: cEqBarras, historial: cEqHistorial, doble: cEqDoble })[barra.cfg.equipoDiseno] ?? cEqBarras
            }
        }
    }
    // A: tres anillos que se llenan.
    Component {
        id: cEqAnillos
        Item {
            implicitHeight: 100
            Row {
                anchors { fill: parent; topMargin: 14 }
                Repeater {
                    model: [["CPU", barra.cpuUso >= 0 ? barra.cpuUso / 100 : 0, barra.cpuUso >= 0 ? barra.cpuUso + "%" : "—", barra.cpuCaliente],
                            ["RAM · GB", barra.ramPct, barra.ramUsada >= 0 ? barra.ramUsada.toFixed(1) : "—", false],
                            ["GPU", barra.gpuTemp >= 0 ? barra.gpuTemp / 100 : 0, barra.tGpu, barra.gpuCaliente]]
                    delegate: Column {
                        required property var modelData
                        width: parent.width / 3; spacing: 6
                        Anillo { anchors.horizontalCenter: parent.horizontalCenter; p: modelData[1]; texto: modelData[2]; caliente: modelData[3] }
                        Texto { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[0]; color: Estilo.texto3; font.pixelSize: 12 }
                    }
                }
            }
        }
    }
    // B: barras con etiqueta y numero.
    Component {
        id: cEqBarras
        Item {
            implicitHeight: filasMedida.implicitHeight + 20
            Column {
                id: filasMedida
                x: 14; y: 10; width: parent.width - 28
                FilaMedida { etiqueta: "CPU"; p: barra.cpuUso >= 0 ? barra.cpuUso / 100 : 0; texto: barra.tCpu; caliente: barra.cpuCaliente }
                FilaMedida { etiqueta: "RAM"; p: barra.ramPct; texto: barra.ramUsada >= 0 ? barra.ramUsada.toFixed(1) + " / " + barra.ramTotal.toFixed(1) : "—" }
                FilaMedida { etiqueta: "GPU"; p: barra.gpuTemp >= 0 ? barra.gpuTemp / 100 : 0; texto: barra.tGpu; caliente: barra.gpuCaliente }
            }
        }
    }
    // C: CPU grande con su ultimo minuto; RAM y GPU debajo.
    Component {
        id: cEqHistorial
        Item {
            implicitHeight: colHist.implicitHeight + 24
            Column {
                id: colHist
                x: 14; y: 12; width: parent.width - 28
                spacing: 6
                Item {
                    width: parent.width; height: 30
                    Texto { anchors.verticalCenter: parent.verticalCenter; text: "CPU · último minuto"; color: Estilo.texto3; font.pixelSize: 12 }
                    Texto { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: barra.tCpu; color: barra.cpuCaliente ? Estilo.peligro : Estilo.texto; font { family: Estilo.fuenteMono; pixelSize: 22 } }
                }
                Item {
                    id: spark
                    width: parent.width; height: 34
                    readonly property var puntos: {
                        const h = barra.cpuHist, paso = width / 29, m = Math.max(20, ...h);
                        return h.map((v, i) => Qt.point(width - (h.length - 1 - i) * paso, height - 3 - (v / m) * (height - 8)));
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: Estilo.hundido }
                    Shape {
                        anchors.fill: parent; visible: barra.cpuHist.length > 1
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: barra.cpuCaliente ? Estilo.peligro : Estilo.acento; strokeWidth: 1.5; fillColor: "transparent"
                            joinStyle: ShapePath.RoundJoin; capStyle: ShapePath.RoundCap
                            PathPolyline { path: spark.puntos }
                        }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: Estilo.linea }
                Row {
                    width: parent.width
                    Repeater {
                        model: [["RAM", barra.tRam, false], ["GPU", barra.tGpu, barra.gpuCaliente]]
                        delegate: Column {
                            required property var modelData
                            width: parent.width / 2; spacing: 3
                            Texto { text: modelData[0]; color: Estilo.texto3; font.pixelSize: 12 }
                            Texto { text: modelData[1]; color: modelData[2] ? Estilo.peligro : Estilo.texto; font { family: Estilo.fuenteMono; pixelSize: 15 } }
                        }
                    }
                }
            }
        }
    }
    // D: tres columnas con un segundo dato cada una (temperatura y consumo, porcentaje, uso).
    Component {
        id: cEqDoble
        Item {
            implicitHeight: 84
            Row {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                Repeater {
                    model: [["CPU", barra.tCpu, (barra.cpuTemp >= 0 ? barra.cpuTemp + "°" : "—") + (barra.cpuW >= 0 ? " · " + barra.cpuW.toFixed(1) + " W" : ""), barra.cpuCaliente],
                            ["RAM", barra.tRam, barra.ramTotal > 0 ? Math.round(barra.ramPct * 100) + " % de " + barra.ramTotal.toFixed(1) : "—", false],
                            ["GPU", barra.tGpu, barra.gpuUso >= 0 ? Math.round(barra.gpuUso) + " % de uso" : "—", barra.gpuCaliente]]
                    delegate: Column {
                        required property var modelData
                        width: parent.width / 3; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                        Texto { text: modelData[0]; color: Estilo.texto3; font.pixelSize: 12 }
                        Texto { text: modelData[1]; color: modelData[3] ? Estilo.peligro : Estilo.texto; font { family: Estilo.fuenteMono; pixelSize: 15 } }
                        Texto { text: modelData[2]; color: Estilo.texto2; font { family: Estilo.fuenteMono; pixelSize: 11 } }
                    }
                }
            }
        }
    }

    Component {
        id: cMusica
        Rectangle {
            height: 110; radius: 16; color: Estilo.tarjeta
            ClippingRectangle {
                id: caratula
                x: 12; y: 12
                width: 52; height: 52; radius: 11; color: Estilo.hundido
                Image { anchors.fill: parent; source: barra.reproductor ? barra.reproductor.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            }
            Column {
                anchors { left: caratula.right; leftMargin: 12; right: controles.left; rightMargin: 8; verticalCenter: caratula.verticalCenter }
                spacing: 2
                Texto { width: parent.width; text: barra.reproductor ? (barra.reproductor.trackTitle || barra.reproductor.identity) : ""; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Texto { width: parent.width; text: barra.reproductor ? (barra.reproductor.trackTitle ? [barra.reproductor.trackArtist, barra.reproductor.identity].filter(s => s).join(" · ") : "Sin título") : ""; color: Estilo.texto2; font.pixelSize: 12; elide: Text.ElideRight }
            }
            Row {
                id: controles
                anchors { right: parent.right; rightMargin: 12; verticalCenter: caratula.verticalCenter }
                spacing: 4
                BotonReproductor { icono: "skip_previous"; onPulsado: barra.reproductor.previous() }
                BotonReproductor { icono: barra.reproductor && barra.reproductor.isPlaying ? "pause" : "play_arrow"; principal: true; onPulsado: barra.reproductor.togglePlaying() }
                BotonReproductor { icono: "skip_next"; onPulsado: barra.reproductor.next() }
            }
            // Progreso: 3 px, con el color dominante de la caratula. Sin duracion conocida, vacio y "—".
            readonly property bool hayTiempo: !!barra.reproductor && barra.reproductor.lengthSupported && barra.reproductor.length > 0
            Texto { id: tiempoAhora; x: 12; y: 82; text: barra.reproductor && barra.reproductor.positionSupported ? barra.minutos(barra.reproductor.position) : "—"; color: Estilo.texto2; font { family: Estilo.fuenteMono; pixelSize: 12 } }
            Texto { id: tiempoTotal; anchors { right: parent.right; rightMargin: 12 } y: 82; text: parent.hayTiempo ? barra.minutos(barra.reproductor.length) : "—"; color: Estilo.texto2; font { family: Estilo.fuenteMono; pixelSize: 12 } }
            Rectangle {
                anchors { left: tiempoAhora.right; leftMargin: 10; right: tiempoTotal.left; rightMargin: 10; verticalCenter: tiempoAhora.verticalCenter }
                height: 3; radius: 1.5; color: Estilo.hundido
                Rectangle {
                    height: parent.height; radius: 1.5; color: barra.colorCaratula
                    width: parent.parent.hayTiempo ? parent.width * Math.max(0, Math.min(1, barra.reproductor.position / barra.reproductor.length)) : 0
                    Behavior on width { NumberAnimation { duration: Estilo.t(300) } }
                }
            }
        }
    }

    // Calendario: el mes completo, siempre visible. Hoy lleva borde de acento, sin relleno.
    Component {
        id: cCalendario
        Calendario { width: parent.width }
    }

    // Energia en fila (estilo "fila"): cuatro tarjetas.
    Component {
        id: cEnergia
        Row {
            id: filaEnergia
            width: parent.width
            spacing: 8
            readonly property real ancho: (width - 24) / 4
            Repeater {
                model: barra.accionesEnergia
                delegate: Rectangle {
                    id: tarjetaE
                    required property var modelData
                    readonly property bool peligro: modelData.id === "apagar" || barra.confirmar === modelData.id
                    width: filaEnergia.ancho; height: 64; radius: 16
                    color: zonaE.containsMouse ? Estilo.realce : Estilo.tarjeta
                    Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                    Column {
                        anchors.centerIn: parent; spacing: 5
                        Simbolo { anchors.horizontalCenter: parent.horizontalCenter; text: tarjetaE.modelData.icono; font.pixelSize: 18; color: tarjetaE.peligro ? Estilo.peligro : Estilo.texto }
                        Texto {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: barra.confirmar === tarjetaE.modelData.id ? "¿Seguro?" : tarjetaE.modelData.texto
                            color: tarjetaE.peligro ? Estilo.peligro : Estilo.texto2; font.pixelSize: 12
                        }
                    }
                    MouseArea { id: zonaE; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: barra.accionEnergia(tarjetaE.modelData.id) }
                }
            }
        }
    }

    // ---- Piezas ----
    component Texto: Text {
        color: Estilo.texto
        font { family: Estilo.fuenteSans; pixelSize: 13 }
    }
    component Simbolo: Text {
        property real relleno: 1
        font { family: "Material Symbols Rounded"; pixelSize: 20 }
        font.variableAxes: { "FILL": relleno, "wght": 500, "opsz": 24 }
        renderType: Text.NativeRendering
    }
    component Encabezado: Texto {
        color: Estilo.texto2; font.pixelSize: 12; font.weight: Font.DemiBold
        leftPadding: 4; topPadding: 14; bottomPadding: 6
    }
    component Pagina: Column {
        id: pag
        property bool activa
        property int lado: 1                // -1: entra desde la izquierda (volver a inicio)
        width: parent.width
        spacing: 0
        visible: opacity > 0.01
        opacity: activa ? 1 : 0
        enabled: activa
        // La que sale se va rapido (120 ms); la que entra se desliza 18 px en 320 ms, sin rebote largo.
        Behavior on opacity { NumberAnimation { duration: Estilo.t(pag.activa ? 240 : 120); easing.type: Easing.OutCubic } }
        transform: Translate { id: corrimiento }
        onActivaChanged: if (activa) { entrar.from = 18 * pag.lado; entrar.restart(); }
        NumberAnimation { id: entrar; target: corrimiento; property: "x"; to: 0; duration: Estilo.t(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos }
    }
    component Volver: Item {
        property alias text: tituloVolver.text
        width: parent.width; height: 46
        Redondo { id: atras; icono: "chevron_left"; chico: true; anchors.verticalCenter: parent.verticalCenter; onPulsado: barra.ir("inicio") }
        Texto { id: tituloVolver; anchors { left: atras.right; leftMargin: 8; verticalCenter: parent.verticalCenter } font.pixelSize: 17; font.weight: Font.DemiBold }
    }
    component Redondo: Rectangle {
        id: red
        property string icono
        property bool chico: false
        property bool blanco: false
        property bool rojo: false
        signal pulsado()
        width: chico ? 32 : 40; height: width; radius: width / 2
        color: blanco ? Estilo.activo : (zonaR.containsMouse ? Estilo.realce : Estilo.tarjeta)
        border.width: 1; border.color: blanco ? Estilo.activoBorde : Estilo.linea
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        Simbolo { anchors.centerIn: parent; text: red.icono; color: red.blanco ? Estilo.iconoActivo : red.rojo ? Estilo.peligro : Estilo.texto; font.pixelSize: red.chico ? 20 : 19 }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaR; anchors.fill: parent; hoverEnabled: true; onClicked: red.pulsado() }
    }
    // Boton cuadrado del encabezado (Ajustes, Energia): 40x40, radio 12.
    component BotonCuadro: Rectangle {
        id: bc
        property string icono
        signal pulsado()
        width: 40; height: 40; radius: 12
        color: zonaBc.containsMouse ? Estilo.realce : Estilo.tarjeta
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        Simbolo { anchors.centerIn: parent; text: bc.icono; font.pixelSize: 19; color: Estilo.texto }
        MouseArea { id: zonaBc; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bc.pulsado() }
    }
    // Anterior / pausa / siguiente del reproductor. La pausa es un circulo de acento.
    component BotonReproductor: Rectangle {
        id: br
        property string icono
        property bool principal: false
        signal pulsado()
        width: principal ? 36 : 32; height: width; radius: width / 2
        color: principal ? Estilo.acento : zonaBr.containsMouse ? Estilo.realce : Estilo.nada
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        Simbolo { anchors.centerIn: parent; text: br.icono; font.pixelSize: br.principal ? 20 : 19; color: br.principal ? Estilo.sobreAcento : Estilo.texto2 }
        MouseArea { id: zonaBr; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: br.pulsado() }
    }
    // Boton rapido: icono en un cuadro de 32x32; encendido = cuadro de acento y borde de acento de 1.5 px.
    // La flecha (Red, Bluetooth) abre la subpagina; el resto de la tarjeta alterna.
    component Rapido: Rectangle {
        id: rap
        property string icono
        property string titulo
        property string detalle
        property bool activa
        property bool flecha: false
        signal pulsado()
        signal abrir()
        height: 62; radius: 16
        color: zonaQ.containsMouse ? Estilo.realce : Estilo.tarjeta
        border.width: activa ? 1.5 : 0; border.color: Estilo.acento
        Behavior on color { ColorAnimation { duration: Estilo.t(180) } }
        Rectangle {
            id: cuadro
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32; radius: 10
            color: rap.activa ? Estilo.acento : Estilo.hundido
            Behavior on color { ColorAnimation { duration: Estilo.t(180) } }
            Simbolo { anchors.centerIn: parent; text: rap.icono; relleno: rap.activa ? 1 : 0; font.pixelSize: 19; color: rap.activa ? Estilo.sobreAcento : Estilo.texto2
                Behavior on color { ColorAnimation { duration: Estilo.t(180) } } }
        }
        Column {
            anchors { left: cuadro.right; leftMargin: 11; right: parent.right; rightMargin: rap.flecha ? 30 : 10; verticalCenter: parent.verticalCenter }
            spacing: 2
            Texto { text: rap.titulo; font.pixelSize: 14; font.weight: Font.DemiBold; width: parent.width; elide: Text.ElideRight }
            Texto { visible: rap.detalle !== ""; text: rap.detalle; color: Estilo.texto2; font.pixelSize: 12; width: parent.width; elide: Text.ElideRight }
        }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaQ; anchors.fill: parent; hoverEnabled: true; onClicked: rap.pulsado() }
        Item {
            visible: rap.flecha
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 34
            Simbolo { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: "chevron_right"; font.pixelSize: 18; color: zonaF.containsMouse ? Estilo.texto : Estilo.texto2 }
            MouseArea { id: zonaF; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rap.abrir() }
        }
    }
    // Columna de nivel con menisco: el agua (acento) sube desde abajo y su borde es una curva concava,
    // los lados mas altos que el centro. Se controla arrastrando, con la rueda (pasos de 5) y con las
    // flechas arriba y abajo cuando tiene foco. La curva solo se usa aqui.
    component ColumnaNivel: FocusScope {
        id: cn
        property string icono
        property real valor                 // 0..1, lo que dice el sistema
        property bool pulsable: false       // el icono alterna silencio
        signal cambiar(real v)
        signal iconoPulsado()
        property real vivo: valor
        onValorChanged: if (!zonaC.pressed) vivo = valor
        readonly property real alto: 128
        height: alto
        activeFocusOnTab: true
        // ---- Agua ----
        // El nivel dibujado sigue a "vivo" con un resorte (se pasa un poco y se asienta); el agua se bambolea
        // con dos modos de oscilacion amortiguados: la inclinacion (la empuja el arrastre de lado) y el abultado
        // del centro (lo empuja la aceleracion del nivel). Encima, un oleaje muy suave siempre en marcha.
        // Sin movimiento (modo juego o rebote apagado) el nivel va directo a su valor y el agua queda plana.
        readonly property bool conAgua: !Estilo.juego && Estilo.valor("rebote") !== "nada"
        property real nivelPos: 0           // 0..1, lo que se dibuja
        property real nivelVel: 0
        property real inclina: 0            // px en los bordes (mas arriba un lado que el otro)
        property real inclinaVel: 0
        property real abulta: 0             // px entre bordes y centro
        property real abultaVel: 0
        property real fase: 0
        property real ultimoX: -1
        property string ruta: ""
        readonly property real cima: alto * (1 - nivelPos)       // altura del agua desde arriba, sin la curva
        Component.onCompleted: { nivelPos = vivo; ruta = trazar(); }
        onWidthChanged: ruta = trazar()
        // Curva base (menisco): y = alto - valor*alto; c = min(6, valor*0.5, (100-valor)*0.5 + 1.5), valor en 0..100.
        // Es el cubico del diseno, muestreado en 24 puntos para sumarle el oleaje.
        function trazar() {
            const W = width, H = alto;
            if (W <= 0) return "";
            const pct = nivelPos * 100, y = H - nivelPos * H;
            const c = Math.min(6, pct * 0.5, (100 - pct) * 0.5 + 1.5);
            const yE = y - c, yC = y + 0.55 * c;
            // Casi vacia o casi llena, el agua apenas se mueve: no hay donde.
            const f = conAgua ? Math.max(0, Math.min(1, pct / 12, (100 - pct) / 12 + 0.3)) : 0;
            let d = "";
            for (let i = 0; i <= 24; i++) {
                const t = i / 24, m = 1 - t;
                const x = 3 * m * m * t * 0.22 * W + 3 * m * t * t * 0.78 * W + t * t * t * W;
                const u = x / W;
                const ola = f * (inclina * (2 * u - 1) + abulta * Math.cos(2 * Math.PI * u)
                                 + 0.9 * Math.sin(2 * Math.PI * 1.3 * u + fase * 1.7) + 0.5 * Math.sin(2 * Math.PI * 2.1 * u - fase * 2.6));
                d += (i === 0 ? "M " : " L ") + x.toFixed(1) + "," + ((m * m * m + t * t * t) * yE + 3 * m * t * yC + ola).toFixed(1);
            }
            return d + " L " + W + "," + H + " L 0," + H + " Z";
        }
        FrameAnimation {
            running: barra.abierta && cn.visible
            onTriggered: {
                const dt = Math.min(frameTime, 0.033);
                if (dt <= 0) return;
                if (!cn.conAgua) { cn.nivelPos = cn.vivo; cn.ruta = cn.trazar(); return; }
                cn.fase += dt;
                // Nivel: resorte (poco pasado, se asienta en ~0.5 s).
                const acc = 240 * (cn.vivo - cn.nivelPos) - 22 * cn.nivelVel;
                cn.nivelVel += acc * dt;
                cn.nivelPos = Math.max(0, Math.min(1, cn.nivelPos + cn.nivelVel * dt));
                // Velocidad del cursor de lado, solo mientras se arrastra.
                let vx = 0;
                if (zonaC.pressed) { vx = cn.ultimoX >= 0 ? (zonaC.mouseX - cn.ultimoX) / dt : 0; cn.ultimoX = zonaC.mouseX; }
                else cn.ultimoX = -1;
                // Modos: inclinacion (~2 Hz) y abultado (~3.5 Hz), ambos poco amortiguados.
                cn.inclinaVel += (-190 * cn.inclina - 3.4 * cn.inclinaVel + 2.2 * vx) * dt;
                cn.inclina = Math.max(-13, Math.min(13, cn.inclina + cn.inclinaVel * dt));
                cn.abultaVel += (-480 * cn.abulta - 9 * cn.abultaVel - 25 * acc) * dt;
                cn.abulta = Math.max(-8, Math.min(8, cn.abulta + cn.abultaVel * dt));
                cn.ruta = cn.trazar();
            }
        }
        function paso(d) { vivo = Math.max(0, Math.min(1, Math.round((vivo + d) * 20) / 20)); cambiar(vivo); }
        Keys.onUpPressed: paso(0.05)
        Keys.onDownPressed: paso(-0.05)
        ClippingRectangle {
            anchors.fill: parent; radius: 14; color: Estilo.hundido
            Shape {
                width: cn.width; height: cn.alto
                preferredRendererType: Shape.CurveRenderer
                ShapePath { fillColor: Estilo.acento; strokeWidth: -1; PathSvg { path: cn.ruta } }
            }
        }
        Texto {
            x: 12; y: 10
            text: Math.round(cn.vivo * 100)
            color: cn.cima < 26 ? Estilo.sobreAcento : Estilo.texto
            font { family: Estilo.fuenteMono; pixelSize: 15 }
            Behavior on color { ColorAnimation { duration: Estilo.t(180) } }
        }
        Simbolo {
            x: 12; y: cn.alto - height - 10
            text: cn.icono; font.pixelSize: 17
            color: cn.cima < cn.alto - 36 ? Estilo.sobreAcento : Estilo.texto2
            Behavior on color { ColorAnimation { duration: Estilo.t(180) } }
        }
        Rectangle { anchors.fill: parent; radius: 14; color: "transparent"; border.width: 1.5; border.color: Estilo.acento; visible: cn.activeFocus }
        MouseArea {
            id: zonaC
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function mover(m) { cn.vivo = Math.max(0, Math.min(1, 1 - m.y / height)); cn.cambiar(cn.vivo); }
            onPressed: m => { cn.forceActiveFocus(); mover(m); }
            onPositionChanged: m => { if (pressed) mover(m); }
            onWheel: w => cn.paso(w.angleDelta.y > 0 ? 0.05 : -0.05)
        }
        // El icono alterna silencio (volumen y microfono); queda encima del area de arrastre.
        MouseArea {
            enabled: cn.pulsable
            x: 0; y: cn.alto - 40; width: 44; height: 40
            cursorShape: Qt.PointingHandCursor
            onClicked: cn.iconoPulsado()
        }
    }
    // Deslizador horizontal de la pagina de sonido (volumen por app).
    component Nivel: Rectangle {
        id: niv
        property string icono: ""
        property string etiqueta: ""
        property real valor
        property bool flecha: false
        signal cambiar(real v)
        signal icono_pulsado()
        signal flecha_pulsada()
        property real vivo: valor
        onValorChanged: if (!zonaN.pressed) vivo = valor
        width: parent.width; height: 40; radius: 14; color: Estilo.tarjeta
        Simbolo { id: inv; visible: niv.icono !== ""; x: 10; anchors.verticalCenter: parent.verticalCenter; text: niv.icono; font.pixelSize: 19; color: Estilo.texto2
            MouseArea { cursorShape: Qt.PointingHandCursor; id: zIcoN; hoverEnabled: true; anchors.fill: parent; anchors.margins: -6; onClicked: niv.icono_pulsado() } }
        Texto { id: etq; visible: niv.etiqueta !== ""; x: 12; width: 76; anchors.verticalCenter: parent.verticalCenter; text: niv.etiqueta; font.pixelSize: 12; elide: Text.ElideRight }
        Rectangle {
            id: pista
            anchors { left: niv.etiqueta ? etq.right : inv.right; leftMargin: 10; right: valorTxt.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            height: 20; radius: 10; color: Estilo.hundido
            Rectangle { height: parent.height; radius: 10; color: Estilo.acento; width: Math.max(height, parent.width * niv.vivo) }
            MouseArea { cursorShape: Qt.PointingHandCursor
                id: zonaN
                anchors.fill: parent
                function mover(m) { niv.vivo = Math.max(0, Math.min(1, m.x / width)); niv.cambiar(niv.vivo); }
                onPressed: m => mover(m)
                onPositionChanged: m => mover(m)
            }
        }
        Texto { id: valorTxt; anchors { right: niv.flecha ? fl.left : parent.right; rightMargin: niv.flecha ? 2 : 10; verticalCenter: parent.verticalCenter } width: 28; horizontalAlignment: Text.AlignRight; text: Math.round(niv.vivo * 100); color: Estilo.texto2; font { family: Estilo.fuenteMono; pixelSize: 11 } }
        Simbolo { id: fl; visible: niv.flecha; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: "chevron_right"; font.pixelSize: 18; color: zFlechaN.containsMouse ? Estilo.texto : Estilo.texto2
            MouseArea { cursorShape: Qt.PointingHandCursor; id: zFlechaN; hoverEnabled: true; anchors.fill: parent; anchors.margins: -6; onClicked: niv.flecha_pulsada() } }
    }
    // Dispositivo Bluetooth con su estado: conectando y desconectando llevan una ruedita al lado; el
    // conectado lleva tarjeta + borde de acento de 1.5 px + palomita de acento; si falla, borde rojo y
    // "Reintentar". Falla = pasa de Conectando a Desconectado, o 15 s sin conectar.
    component FilaBt: Rectangle {
        id: fb
        property var dispositivo
        readonly property color rojo: Estilo.peligro
        readonly property int st: dispositivo ? dispositivo.state : BluetoothDeviceState.Disconnected
        readonly property bool conectando: st === BluetoothDeviceState.Connecting || (intentando && st !== BluetoothDeviceState.Connected)
        readonly property bool desconectando: st === BluetoothDeviceState.Disconnecting
        readonly property bool conectado: st === BluetoothDeviceState.Connected
        property bool intentando: false
        property bool fallo: false
        property int antes: st
        onStChanged: {
            if (st === BluetoothDeviceState.Connected) { intentando = false; fallo = false; espera.stop(); }
            else if (st === BluetoothDeviceState.Disconnected && antes === BluetoothDeviceState.Connecting) { intentando = false; fallo = true; espera.stop(); }
            antes = st;
        }
        Timer { id: espera; interval: 15000; onTriggered: { if (!fb.conectado) { fb.intentando = false; fb.fallo = true; } } }
        function pulsar() {
            if (conectado) { dispositivo.disconnect(); return; }
            fallo = false; intentando = true; espera.restart(); dispositivo.connect();
        }

        width: parent ? parent.width : 0; height: 52; radius: 14
        color: (conectado || fallo || conectando) ? Estilo.tarjeta : (zonaB.containsMouse ? Estilo.realce : Estilo.nada)
        Behavior on color { ColorAnimation { duration: Estilo.t(180) } }
        border.width: conectado || fallo ? 1.5 : 0; border.color: fallo ? rojo : Estilo.acento
        opacity: desconectando ? 0.6 : 1
        Behavior on opacity { NumberAnimation { duration: Estilo.t(180) } }

        Rectangle {
            id: burbuja
            x: 10; width: 32; height: 32; radius: 10; anchors.verticalCenter: parent.verticalCenter
            color: Estilo.hundido
            Simbolo {
                anchors.centerIn: parent; font.pixelSize: 19
                text: fb.fallo ? "error" : fb.dispositivo && fb.dispositivo.icon && (fb.dispositivo.icon.includes("headset") || fb.dispositivo.icon === "audio-headphones") ? "headphones"
                    : fb.dispositivo && fb.dispositivo.icon && fb.dispositivo.icon.includes("audio") ? "speaker" : "devices_other"
                color: fb.fallo ? fb.rojo : fb.conectado ? Estilo.acento : Estilo.texto2
                Behavior on color { ColorAnimation { duration: Estilo.t(180) } }
            }
        }
        Column {
            anchors { left: burbuja.right; leftMargin: 11; right: lado.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 1
            Texto { text: fb.dispositivo ? fb.dispositivo.name : ""; width: parent.width; elide: Text.ElideRight; font { pixelSize: 14; weight: Font.DemiBold } }
            Texto {
                width: parent.width; elide: Text.ElideRight; font.pixelSize: 12
                text: fb.fallo ? "No se pudo conectar"
                    : fb.dispositivo && fb.dispositivo.pairing ? "Emparejando…"
                    : fb.desconectando ? "Desconectando…"
                    : fb.conectando ? "Conectando…"
                    : fb.conectado ? "Conectado" + (fb.dispositivo.batteryAvailable ? " · " + Math.round(fb.dispositivo.battery * 100) + " %" : "")
                    : "Toca para conectar"
                color: fb.fallo ? fb.rojo : Estilo.texto2
            }
        }
        // Al lado: ruedita mientras conecta o desconecta, la palomita al estar conectado, "Reintentar" si fallo.
        Item {
            id: lado
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: fb.fallo ? reintentar.implicitWidth : 20; height: 20
            Ruedita { anchors.centerIn: parent; visible: fb.conectando || fb.desconectando; tinta: fb.desconectando ? Estilo.texto2 : Estilo.acento }
            Simbolo {
                anchors.centerIn: parent; text: "check"; font.pixelSize: 19; color: Estilo.acento
                opacity: fb.conectado ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Estilo.t(180) } }
            }
            Texto { id: reintentar; anchors.centerIn: parent; visible: fb.fallo; text: "Reintentar"; font.pixelSize: 12; font.weight: Font.DemiBold; color: fb.rojo }
        }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaB; anchors.fill: parent; hoverEnabled: true; onClicked: fb.pulsar() }
    }
    // Ruedita de espera: ocho rayitas que se apagan en circulo.
    component Ruedita: Item {
        id: rd
        property color tinta: Estilo.texto
        width: 18; height: 18
        property int paso: 0
        Timer { running: rd.visible; repeat: true; interval: 90; onTriggered: rd.paso = (rd.paso + 1) % 8 }
        Repeater {
            model: 8
            Rectangle {
                required property int index
                x: rd.width / 2 - 1; y: 0; width: 2; height: 5; radius: 1
                color: rd.tinta
                opacity: 0.25 + 0.75 * (((index - rd.paso + 8) % 8) === 0 ? 1 : Math.max(0, 1 - ((rd.paso - index + 8) % 8) / 7))
                transform: Rotation { origin.x: 1; origin.y: rd.height / 2; angle: index * 45 }
            }
        }
    }
    // Fila de una lista (cables, redes, salidas de sonido): la elegida lleva tarjeta + borde de acento
    // de 1.5 px + palomita de acento, y su icono en acento.
    component FilaLista: Rectangle {
        id: fl2
        property string icono
        property string titulo
        property string detalle
        property bool marcada: false
        property bool tenue: false
        signal pulsada()
        width: parent ? parent.width : 0; height: detalle ? 52 : 44; radius: 14
        color: marcada ? Estilo.tarjeta : (zonaL.containsMouse ? Estilo.realce : Estilo.nada)
        Behavior on color { ColorAnimation { duration: Estilo.t(180) } }
        border.width: marcada ? 1.5 : 0; border.color: Estilo.acento
        opacity: tenue ? 0.75 : 1
        Simbolo { id: il; x: 12; anchors.verticalCenter: parent.verticalCenter; text: fl2.icono; font.pixelSize: 19; color: fl2.marcada ? Estilo.acento : Estilo.texto2 }
        Column {
            anchors { left: il.right; leftMargin: 11; right: parent.right; rightMargin: 38; verticalCenter: parent.verticalCenter }
            Texto { text: fl2.titulo; width: parent.width; elide: Text.ElideRight; font { pixelSize: 14; weight: Font.DemiBold } }
            Texto { visible: fl2.detalle !== ""; text: fl2.detalle; color: Estilo.texto2; font.pixelSize: 12; width: parent.width; elide: Text.ElideRight }
        }
        Simbolo { visible: fl2.marcada; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: "check"; font.pixelSize: 19; color: Estilo.acento }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaL; anchors.fill: parent; hoverEnabled: true; onClicked: fl2.pulsada() }
    }
    // Anillo de medida: el arco se llena con 260 ms; en rojo solo en estado critico.
    component Anillo: Item {
        id: an
        property real p: 0
        property string texto
        property bool caliente: false
        width: 56; height: 56
        property real pm: p
        Behavior on pm { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.OutCubic } }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Estilo.hundido; strokeWidth: 5; fillColor: "transparent"
                PathAngleArc { centerX: 28; centerY: 28; radiusX: 22; radiusY: 22; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: an.caliente ? Estilo.peligro : Estilo.acento; strokeWidth: 5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 28; centerY: 28; radiusX: 22; radiusY: 22; startAngle: -90; sweepAngle: 360 * Math.max(0.001, Math.min(1, an.pm)) }
            }
        }
        Texto { anchors.centerIn: parent; text: an.texto; font { family: Estilo.fuenteMono; pixelSize: 13 } }
    }
    // Fila de medida: etiqueta, barra y numero.
    component FilaMedida: Item {
        id: fm
        property string etiqueta
        property real p: 0
        property string texto
        property bool caliente: false
        width: parent.width; height: 26
        property real pm: p
        Behavior on pm { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.OutCubic } }
        Texto { id: etFm; width: 34; anchors.verticalCenter: parent.verticalCenter; text: fm.etiqueta; color: Estilo.texto3; font.pixelSize: 12 }
        Texto { id: valFm; width: 84; anchors { right: parent.right; verticalCenter: parent.verticalCenter } horizontalAlignment: Text.AlignRight; text: fm.texto; font { family: Estilo.fuenteMono; pixelSize: 13 } }
        Rectangle {
            anchors { left: etFm.right; right: valFm.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            height: 6; radius: 3; color: Estilo.hundido
            Rectangle { height: parent.height; radius: 3; color: fm.caliente ? Estilo.peligro : Estilo.acento; width: parent.width * Math.max(0, Math.min(1, fm.pm)) }
        }
    }
    // Boton pequeno del encabezado del calendario (mes anterior, siguiente, desplegar).
    component BotonNav: Rectangle {
        id: bn
        property string icono
        signal pulsado()
        width: 28; height: 28; radius: 9
        color: zonaNav.containsMouse ? Estilo.realce : "transparent"
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        Simbolo { anchors.centerIn: parent; text: bn.icono; font.pixelSize: 18; color: Estilo.texto2 }
        MouseArea { id: zonaNav; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bn.pulsado() }
    }
    // Calendario, en tres disenos (Ajustes > Barra lateral):
    //   semana: semana de hoy resaltada, numeros de semana, fines de semana atenuados y cambio de mes.
    //   progreso: barra de avance del mes y dias pasados atenuados.
    //   tira: solo la semana de hoy; al desplegar, el mes completo.
    // Hoy lleva borde de acento de 1.5 px, sin relleno, en todos.
    component Calendario: Rectangle {
        id: cal
        readonly property date hoy: reloj.date
        readonly property bool lunes: barra.cfg.semanaLunes
        readonly property string diseno: barra.cfg.calendarioDiseno
        property int desplaz: 0                 // meses respecto al actual (solo en "semana")
        property bool abierto: false            // "tira" desplegada
        readonly property date vista: new Date(hoy.getFullYear(), hoy.getMonth() + desplaz, 1)
        readonly property int anio: vista.getFullYear()
        readonly property int mes: vista.getMonth()
        readonly property bool esActual: desplaz === 0
        readonly property int primerDia: (vista.getDay() + (lunes ? 6 : 0)) % 7
        readonly property int dias: new Date(anio, mes + 1, 0).getDate()
        readonly property int filas: Math.ceil((primerDia + dias) / 7)
        readonly property bool conSemanas: diseno === "semana"
        readonly property bool mostrarMes: diseno !== "tira" || abierto
        readonly property real lead: conSemanas ? 26 : 0
        readonly property var letras: lunes ? ["L", "M", "M", "J", "V", "S", "D"] : ["D", "L", "M", "M", "J", "V", "S"]
        readonly property int diaDelAnio: Math.round((Date.UTC(hoy.getFullYear(), hoy.getMonth(), hoy.getDate()) - Date.UTC(hoy.getFullYear(), 0, 0)) / 86400000)
        // Semana ISO de una fecha (la del jueves de esa semana).
        function semISO(d) {
            const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
            t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
            return Math.ceil(((t - new Date(Date.UTC(t.getUTCFullYear(), 0, 1))) / 86400000 + 1) / 7);
        }
        function numSemana(fila) { return semISO(new Date(anio, mes, 1 - primerDia + fila * 7 + (lunes ? 3 : 4))); }
        Connections { target: barra; function onAbiertaChanged() { if (barra.abierta) { cal.desplaz = 0; cal.abierto = false; } } }
        height: col.y + col.implicitHeight + 10; radius: 16; color: Estilo.tarjeta
        Column {
            id: col
            x: 7; y: 12; width: parent.width - 14
            Item {
                width: parent.width; height: 30
                Texto { x: 7; anchors.verticalCenter: parent.verticalCenter; text: Qt.locale("es_MX").toString(cal.vista, "MMMM yyyy"); font { pixelSize: 15; weight: Font.DemiBold } }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Rectangle {
                        visible: cal.diseno === "semana" && !cal.esActual
                        anchors.verticalCenter: parent.verticalCenter
                        width: textoHoy.implicitWidth + 20; height: 24; radius: 9; color: Estilo.hundido
                        Texto { id: textoHoy; anchors.centerIn: parent; text: "Hoy"; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cal.desplaz = 0 }
                    }
                    BotonNav { visible: cal.diseno === "semana"; icono: "chevron_left"; onPulsado: cal.desplaz--; }
                    BotonNav { visible: cal.diseno === "semana"; icono: "chevron_right"; onPulsado: cal.desplaz++; }
                    Texto { visible: cal.diseno === "progreso"; anchors.verticalCenter: parent.verticalCenter; rightPadding: 7
                            text: "día " + cal.diaDelAnio + " · " + cal.hoy.getDate() + " de " + cal.dias; color: Estilo.texto2; font { family: Estilo.fuenteMono; pixelSize: 12 } }
                    Texto { visible: cal.diseno === "tira"; anchors.verticalCenter: parent.verticalCenter
                            text: "semana " + cal.semISO(cal.hoy); color: Estilo.texto2; font { family: Estilo.fuenteMono; pixelSize: 12 } }
                    BotonNav { visible: cal.diseno === "tira"; icono: cal.abierto ? "expand_less" : "expand_more"; onPulsado: cal.abierto = !cal.abierto; }
                }
            }
            Item { width: 1; height: 6 }
            // Progreso del mes
            Item {
                visible: cal.diseno === "progreso"
                width: parent.width; height: 11
                Rectangle {
                    x: 7; width: parent.width - 14; height: 3; radius: 1.5; color: Estilo.hundido
                    Rectangle { height: parent.height; radius: 1.5; color: Estilo.acento; width: parent.width * cal.hoy.getDate() / cal.dias }
                }
            }
            // Tira: la semana de hoy en grande
            Row {
                visible: cal.diseno === "tira" && !cal.abierto
                x: 7; width: parent.width - 14; spacing: 4
                readonly property real celda: (width - 24) / 7
                Repeater {
                    model: 7
                    delegate: Rectangle {
                        id: chipDia
                        required property int index
                        readonly property date fecha: new Date(cal.hoy.getFullYear(), cal.hoy.getMonth(), cal.hoy.getDate() - ((cal.hoy.getDay() + (cal.lunes ? 6 : 0)) % 7) + index)
                        readonly property bool esHoy: fecha.getDate() === cal.hoy.getDate() && fecha.getMonth() === cal.hoy.getMonth()
                        width: parent.celda; height: 58; radius: 12; color: "transparent"
                        border.width: esHoy ? 1.5 : 0; border.color: Estilo.acento
                        Column {
                            anchors.centerIn: parent; spacing: 5
                            Texto { anchors.horizontalCenter: parent.horizontalCenter; text: cal.letras[chipDia.index]; color: Estilo.texto3; font.pixelSize: 12 }
                            Texto { anchors.horizontalCenter: parent.horizontalCenter; text: chipDia.fecha.getDate(); color: chipDia.esHoy ? Estilo.texto : Estilo.texto2; font { family: Estilo.fuenteMono; pixelSize: 15 } }
                        }
                    }
                }
            }
            Item { visible: cal.diseno === "tira" && !cal.abierto; width: 1; height: 4 }
            // Mes completo
            Column {
                id: mesCol
                visible: cal.mostrarMes
                width: parent.width
                readonly property real celda: (width - cal.lead) / 7
                Row {
                    height: 26
                    Item { width: cal.lead; height: 1 }
                    Repeater {
                        model: cal.letras
                        Texto { required property string modelData; width: mesCol.celda; height: 26; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: modelData; color: Estilo.texto3; font.pixelSize: 12 }
                    }
                }
                Repeater {
                    model: cal.filas
                    delegate: Item {
                        id: fila
                        required property int index
                        width: mesCol.width; height: 33
                        readonly property int inicio: index * 7 - cal.primerDia + 1      // numero del dia en la primera columna
                        Rectangle {
                            visible: cal.diseno === "semana" && cal.esActual && cal.hoy.getDate() >= fila.inicio && cal.hoy.getDate() < fila.inicio + 7
                            anchors.fill: parent; radius: 10; color: Estilo.hundido
                        }
                        Texto { visible: cal.conSemanas; width: cal.lead; height: parent.height; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                text: cal.numSemana(fila.index); color: Estilo.texto3; font { family: Estilo.fuenteMono; pixelSize: 11 } }
                        Repeater {
                            model: 7
                            delegate: Item {
                                id: celda
                                required property int index
                                x: cal.lead + index * mesCol.celda; width: mesCol.celda; height: 33
                                readonly property int dia: fila.inicio + index
                                readonly property bool valido: dia >= 1 && dia <= cal.dias
                                readonly property bool esHoy: valido && cal.esActual && dia === cal.hoy.getDate()
                                readonly property bool finde: cal.lunes ? index >= 5 : (index === 0 || index === 6)
                                Rectangle {
                                    visible: celda.esHoy
                                    anchors.centerIn: parent; width: Math.min(parent.width - 4, 40); height: 30; radius: 10
                                    color: "transparent"; border.width: 1.5; border.color: Estilo.acento
                                }
                                Texto {
                                    anchors.centerIn: parent; visible: celda.valido; text: celda.dia
                                    font { family: Estilo.fuenteMono; pixelSize: 13 }
                                    color: celda.esHoy ? Estilo.texto
                                         : (cal.diseno === "semana" && celda.finde) || (cal.diseno === "progreso" && cal.esActual && celda.dia < cal.hoy.getDate()) ? Estilo.texto3
                                         : Estilo.texto2
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
