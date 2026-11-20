import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Bluetooth

// Isla dinamica de adorno, pegada al borde de arriba como una muesca del monitor.
// Abajo esquinas redondeadas; arriba, curvas hacia afuera que la funden con el borde.
// Muestra la hora.
ShellRoot {
    id: raiz
    property bool islaVisible: true
    property string emocion: "normal"   // normal, feliz, escucha, pensar, emocion, confuso
    property bool lanzadorAbierto: false
    property bool barraAbierta: false
    // Para piezas creadas dentro de Variants: ahi "raiz: raiz" se enlaza consigo misma.
    readonly property var raizShell: raiz
    // ---- Notificaciones: las recibe Hokum (niri lo arranca). La isla solo muestra sus propios
    // avisos (cancion, audifonos, capturas, temperatura, temporizador, color). ----

    // ---- Modo juego: rendimiento maximo, No molestar, sin suspender, sin animaciones ni efectos ----
    // (Menisco con duraciones en cero via Estilo.juego; niri sin animaciones, sombras ni vidrio via juego.kdl)
    // Al apagarlo, todo vuelve a como estaba antes de encenderlo.
    property bool modoJuego: false
    property var antesDeJugar: null
    onModoJuegoChanged: Estilo.juego = modoJuego
    // Si la sesion se cerro en modo juego, niri seguiria sin animaciones: al arrancar se limpia.
    Component.onCompleted: Estilo.niri(["juego", "off"])
    function alternarModoJuego() {
        if (!modoJuego) {
            antesDeJugar = { perfil: perfilActual, dnd: Estilo.noMolestar, cafe: ajustes.cafe };
            Quickshell.execDetached(["powerprofilesctl", "set", "performance"]);
            Estilo.ponerNoMolestar(true);
            ajustes.cafe = true;
            Estilo.niri(["juego", "on"]);
            modoJuego = true;
        } else {
            const a = antesDeJugar || { perfil: "balanced", dnd: false, cafe: false };
            Quickshell.execDetached(["powerprofilesctl", "set", a.perfil]);
            Estilo.ponerNoMolestar(a.dnd);
            ajustes.cafe = a.cafe;
            Estilo.niri(["juego", "off"]);
            modoJuego = false;
        }
    }
    // ---- No molestar automatico (Ajustes > Notificaciones): en pantalla completa y al grabar ----
    // Solo apaga lo que encendio el; si usted lo apaga mientras tanto, se queda apagado.
    property bool pantallaCompleta: false
    readonly property bool dndAutoPide: (Estilo.valor("dndPantallaCompleta") && pantallaCompleta) || (Estilo.valor("dndGrabando") && grabando)
    property bool dndAuto: false
    onDndAutoPideChanged: {
        if (dndAutoPide && !Estilo.noMolestar) { dndAuto = true; Estilo.ponerNoMolestar(true); }
        else if (!dndAutoPide && dndAuto) { dndAuto = false; Estilo.ponerNoMolestar(false); }
    }
    Connections { target: Estilo; function onNoMolestarChanged() { if (!Estilo.noMolestar) raiz.dndAuto = false; } }

    // ---- Bluetooth que se queda en "apagado" ----
    // El receptor USB (Realtek) se cuelga al iniciar sesion y el kernel lo reinicia: el adaptador
    // vuelve como uno nuevo. Si eso pasa con el shell ya abierto, a Quickshell se le escapa el aviso
    // de que se encendio y lo muestra apagado aunque funcione. Apagar y encender de verdad lo pone
    // al dia; solo se hace si BlueZ dice que esta encendido, para no prender uno que usted apago.
    Connections { target: Bluetooth; function onDefaultAdapterChanged() { revisarBt.restart() } }
    Timer {
        id: revisarBt; interval: 4000
        onTriggered: if (Bluetooth.defaultAdapter && !Bluetooth.defaultAdapter.enabled)
            Quickshell.execDetached(["sh", "-c", "bluetoothctl show | grep -q 'Powered: yes' && bluetoothctl power off && bluetoothctl power on"])
    }
    // niri no dice si una ventana esta en pantalla completa: se compara su tamano con el del monitor.
    Process {
        running: Estilo.valor("dndPantallaCompleta")
        command: ["niri", "msg", "-j", "event-stream"]
        stdout: SplitParser { onRead: revisarCompleta.restart() }
        onRunningChanged: if (!running) raiz.pantallaCompleta = false
    }
    Timer { id: revisarCompleta; interval: 300; onTriggered: pantallaCompletaProc.running = true }
    Process {
        id: pantallaCompletaProc
        command: ["sh", "-c", "niri msg -j focused-window; niri msg -j focused-output"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const [v, s] = text.trim().split("\n").filter(l => l).map(l => JSON.parse(l));
                    raiz.pantallaCompleta = !!v && !!s && v.layout.window_size[0] >= s.logical.width && v.layout.window_size[1] >= s.logical.height;
                } catch (e) { raiz.pantallaCompleta = false; }
            }
        }
    }

    // ---- Modo flotante por escritorio (Super+Alt+F, IPC "ventanas modo") ----
    // niri solo sabe soltar ventanas de una en una. Menisco recuerda que escritorios van flotantes
    // y suelta ahi cada ventana nueva; las que usted vuelva a encajar con Super+V se quedan asi.
    // Se olvida al cerrar sesion.
    property var flotantes: []          // ids de escritorio de niri
    property int escritorioActivo: -1
    property var escritorios: []        // los de niri, para saber numero y monitor del activo
    readonly property bool flotanteAqui: flotantes.includes(escritorioActivo)
    property var ventanas: ({})         // id de ventana -> ventana de niri (la del minimapa tambien)
    signal modoCambiado(bool flotante, string salida, int numero)
    function alternarFlotante() {
        const ws = escritorioActivo;
        if (ws < 0) return;
        const flota = !flotantes.includes(ws);
        flotantes = flota ? flotantes.concat([ws]) : flotantes.filter(f => f !== ws);
        for (const id in ventanas)
            if (ventanas[id].workspace_id === ws && ventanas[id].is_floating !== flota)
                Quickshell.execDetached(["niri", "msg", "action", flota ? "move-window-to-floating" : "move-window-to-tiling", "--id", id]);
        const w = escritorios.find(e => e.id === ws);
        modoCambiado(flota, w?.output ?? "", w?.idx ?? 0);
    }
    Process {
        running: true
        command: ["niri", "msg", "-j", "event-stream"]
        stdout: SplitParser {
            onRead: linea => {
                let e;
                try { e = JSON.parse(linea); } catch (x) { return; }
                if (e.WorkspacesChanged) {
                    const lista = e.WorkspacesChanged.workspaces;
                    raiz.escritorios = lista;
                    raiz.escritorioActivo = lista.find(w => w.is_focused)?.id ?? -1;
                    raiz.flotantes = raiz.flotantes.filter(f => lista.some(w => w.id === f));
                } else if (e.WorkspaceActivated) {
                    // is_active por monitor, para los puntos de escritorios de la isla
                    const id = e.WorkspaceActivated.id, w0 = raiz.escritorios.find(w => w.id === id);
                    if (w0) raiz.escritorios = raiz.escritorios.map(w => w.output === w0.output ? Object.assign({}, w, { is_active: w.id === id }) : w);
                    if (e.WorkspaceActivated.focused) raiz.escritorioActivo = id;
                } else if (e.WindowsChanged) {
                    const v = {};
                    for (const w of e.WindowsChanged.windows) v[w.id] = w;
                    raiz.ventanas = v;
                } else if (e.WindowOpenedOrChanged) {
                    // Se reasigna una copia para que el minimapa se entere del cambio.
                    const w = e.WindowOpenedOrChanged.window;
                    if (!(w.id in raiz.ventanas) && !w.is_floating && raiz.flotantes.includes(w.workspace_id))
                        Quickshell.execDetached(["niri", "msg", "action", "move-window-to-floating", "--id", String(w.id)]);
                    const v = Object.assign({}, raiz.ventanas, { [w.id]: w });
                    if (w.is_focused) for (const id in v) if (+id !== w.id && v[id].is_focused) v[id] = Object.assign({}, v[id], { is_focused: false });
                    raiz.ventanas = v;
                } else if (e.WindowClosed) {
                    const v = Object.assign({}, raiz.ventanas);
                    delete v[e.WindowClosed.id];
                    raiz.ventanas = v;
                } else if (e.WindowLayoutsChanged) {
                    const v = Object.assign({}, raiz.ventanas);
                    for (const [id, l] of e.WindowLayoutsChanged.changes) if (v[id]) v[id] = Object.assign({}, v[id], { layout: l });
                    raiz.ventanas = v;
                } else if ("WindowFocusChanged" in e) {
                    const f = e.WindowFocusChanged.id;
                    if (f === null) return;   // la vista general quita el foco: el minimapa marca la ultima
                    const v = {};
                    for (const id in raiz.ventanas) v[id] = Object.assign({}, raiz.ventanas[id], { is_focused: +id === f });
                    raiz.ventanas = v;
                } else if (e.OverviewOpenedOrClosed) {
                    Estilo.vistaGeneral = e.OverviewOpenedOrClosed.is_open;
                    if (Estilo.vistaGeneral) raiz.barraAbierta = false;
                }
            }
        }
    }
    // qs -p ~/.config/quickshell/isla ipc call juego alternar
    IpcHandler {
        target: "juego"
        function alternar(): void { raiz.alternarModoJuego() }
    }
    IpcHandler {
        target: "ventanas"
        function modo(): void { raiz.alternarFlotante() }
    }

    property string perfilActual: "balanced"
    Process { running: true; command: ["powerprofilesctl", "get"]; stdout: StdioCollector { onStreamFinished: raiz.perfilActual = text.trim() } }

    // ---- Temporizador (se inicia desde el lanzador: "temporizador 5 min") ----
    signal temporizadorTerminado()
    property real temporizadorFin: 0
    property int temporizadorRestante: 0
    function iniciarTemporizador(segundos) { temporizadorFin = Date.now() + segundos * 1000; temporizadorRestante = segundos; }
    function cancelarTemporizador() { temporizadorFin = 0; temporizadorRestante = 0; }
    // ---- Cronometro (lanzador: "cronometro"); corre en la isla donde va el temporizador ----
    property real cronometroInicio: 0
    property int cronometroSegundos: 0
    function alternarCronometro() { cronometroInicio = cronometroInicio > 0 ? 0 : Date.now(); cronometroSegundos = 0; }
    Timer { interval: 250; repeat: true; running: raiz.cronometroInicio > 0; onTriggered: raiz.cronometroSegundos = Math.floor((Date.now() - raiz.cronometroInicio) / 1000) }
    // Modo cafe vive en Ajustes; el lanzador lo lee y lo cambia por aqui.
    readonly property bool cafe: ajustes.cafe
    function alternarCafe() { ajustes.cafe = !ajustes.cafe }
    Timer {
        interval: 250; repeat: true; running: raiz.temporizadorFin > 0
        onTriggered: {
            raiz.temporizadorRestante = Math.max(0, Math.ceil((raiz.temporizadorFin - Date.now()) / 1000));
            if (raiz.temporizadorRestante === 0) {
                raiz.temporizadorFin = 0;
                raiz.temporizadorTerminado();
                Quickshell.execDetached(["paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga"]);
            }
        }
    }

    property bool grabando: false
    property int segundosGrabando: 0
    property string archivoGrabacion: ""

    // Grabar pantalla con wf-recorder, con sonido. Con dos monitores hay que decirle cual
    // (si no, se queda esperando): se graba el que tiene el foco.
    function alternarGrabacion() {
        if (grabando) { grabador.signal(2); return; }   // SIGINT: wf-recorder cierra el archivo bien
        monitorGrabar.running = true;
    }
    Process {
        id: monitorGrabar
        command: ["niri", "msg", "-j", "focused-output"]
        stdout: StdioCollector {
            onStreamFinished: {
                let salida = "";
                try { salida = JSON.parse(text)?.name ?? ""; } catch (e) {}
                const ahora = new Date();
                raiz.archivoGrabacion = Quickshell.env("HOME") + "/Vídeos/Grabación " + Qt.formatDateTime(ahora, "yyyy-MM-dd HH-mm-ss") + ".mp4";
                grabador.command = ["wf-recorder", "-a"].concat(salida ? ["-o", salida] : []).concat(["-f", raiz.archivoGrabacion]);
                raiz.segundosGrabando = 0;
                grabador.running = true;
            }
        }
    }
    Process {
        id: grabador
        onRunningChanged: {
            raiz.grabando = running;
            if (!running && raiz.archivoGrabacion)
                Quickshell.execDetached(["notify-send", "-a", "Menisco", "Grabación guardada", raiz.archivoGrabacion]);
        }
    }
    Timer { interval: 1000; repeat: true; running: raiz.grabando; onTriggered: raiz.segundosGrabando++ }

    // ---- Clic fuera: cierra la isla fijada y la barra lateral ----
    // Capa transparente en Top, siempre puesta pero sin recibir nada (mascara vacia) hasta que algo
    // esta abierto: asi queda debajo de la isla y los botones, que se crean despues. El clic que
    // cierra no llega a la ventana de abajo.
    // ponytail: el dock se recrea al cambiar de material y queda encima: un clic en el dock no cierra.
    property int islasFijadas: 0
    signal clicFuera()
    readonly property bool hayAlgoAbierto: islasFijadas > 0 || barraAbierta
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: fuera
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "menisco-fuera"
            property Region lleno: Region { item: zonaFuera }
            property Region vacio: Region {}
            mask: raiz.hayAlgoAbierto ? lleno : vacio
            MouseArea {
                id: zonaFuera
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: { raiz.barraAbierta = false; raiz.clicFuera(); }
            }
        }
    }

    function abrirAjustes() { lanzadorAbierto = false; barraAbierta = false; if (!ajustes.abierta) monitorActivo.running = true; }
    function abrirAjustesEn(seccion) { ajustes.seccion = seccion; abrirAjustes(); }

    // Super+D y el boton del dock llaman a esto.
    IpcHandler {
        target: "lanzador"
        function toggle(): void { raiz.lanzadorAbierto = !raiz.lanzadorAbierto }
        // Para probar sin teclado: ... ipc call lanzador escribir "kit"
        function escribir(texto: string): void { raiz.lanzadorAbierto = true; lanzador.escribir(texto) }
    }
    Lanzador { id: lanzador; raiz: raiz }

    // Super+A abre y cierra la barra lateral (centro de control).
    IpcHandler {
        target: "barra"
        function toggle(): void { raiz.barraAbierta = !raiz.barraAbierta }
        function abrirEn(pagina: string): void { raiz.abrirBarraEn(pagina) }
    }
    // Abre la barra lateral ya en una pagina (bt, red, sonido); la usa "Opciones avanzadas" del lanzador.
    function abrirBarraEn(p) { lanzadorAbierto = false; barraAbierta = true; barra.ir(p); }
    Barra { id: barra; raiz: raiz; ajustes: ajustes }
    // Esquinas de arriba (Ajustes > Esquinas). Bandeja va despues: queda encima de su hueco.
    Esquina { raiz: raiz; ajustes: ajustes; lado: "izquierda" }
    Esquina { raiz: raiz; ajustes: ajustes; lado: "izquierdaIsla" }
    Esquina { raiz: raiz; ajustes: ajustes; lado: "derechaIsla" }
    Esquina { raiz: raiz; ajustes: ajustes; lado: "derecha" }
    // La isla de una pantalla (los botones de junto a la isla siguen su ancho).
    function islaEn(pantalla) { return islas.instances.find(i => i.screen === pantalla) ?? null }
    Bandeja {}
    BordeBarra { raiz: raiz }

    // Para probar: qs -p ~/.config/quickshell/isla ipc call asistente emocion feliz
    IpcHandler {
        target: "asistente"
        function emocion(nombre: string): void { raiz.emocion = nombre }
    }

    // Super+. llama a esto (ver config.kdl de niri).
    IpcHandler {
        target: "ajustes"
        function toggle(): void {
            if (ajustes.abierta) ajustes.cerrar();
            else monitorActivo.running = true;
        }
        // Abre en una seccion: qs -p ~/.config/quickshell/isla ipc call ajustes abrirEn notificaciones
        function abrirEn(seccion: string): void {
            ajustes.seccion = seccion;
            if (!ajustes.abierta) monitorActivo.running = true;
        }
    }

    // Abre los ajustes en el monitor que tiene el foco.
    Process {
        id: monitorActivo
        command: ["niri", "msg", "-j", "focused-output"]
        stdout: StdioCollector {
            onStreamFinished: {
                let nombre = "";
                try { nombre = JSON.parse(text)?.name ?? ""; } catch (e) {}
                ajustes.screen = Quickshell.screens.find(s => s.name === nombre) ?? Quickshell.screens[0];
                ajustes.abrir();
            }
        }
    }

    Ajustes { id: ajustes; raiz: raiz }

    // Super+Shift+/ abre y cierra la tabla de atajos.
    IpcHandler {
        target: "atajos"
        function toggle(): void { atajos.alternar() }
    }
    Atajos { id: atajos }

    // Super+Shift+E abre el cuadro para salir de niri.
    IpcHandler {
        target: "salir"
        function toggle(): void { salir.alternar() }
    }
    Salir { id: salir }

    // Novedades tras cada actualizacion (novedades.json); a mano: ipc call novedades abrir
    IpcHandler {
        target: "novedades"
        function abrir(): void { novedades.abrir() }
    }
    Novedades { id: novedades; raiz: raiz }
    // Clic derecho en el fondo. Para probar: ... ipc call escritorio menu 400 300 | cerrar
    MenuEscritorio { id: menuEscritorio; raiz: raiz }
    VistaGeneral { raiz: raizShell }   // acompana a la vista general de niri
    IpcHandler {
        target: "escritorio"
        function menu(x: real, y: real): void { menuEscritorio.abrir(Quickshell.screens[0], x, y) }
        function cerrar(): void { menuEscritorio.abierto = false }
    }
    // Pantalla de bloqueo propia (Bloqueo.qml). "ensayo" la muestra sin bloquear, para probarla.
    Bloqueo { id: bloqueo }
    function abrirCaptura() { lanzadorAbierto = false; barraAbierta = false; captura.abrir("zona"); }
    function bloquear() { lanzadorAbierto = false; barraAbierta = false; bloqueo.bloquear(); }
    IpcHandler {
        target: "bloqueo"
        function bloquear(): void { raiz.bloquear() }
        function ensayo(): void { bloqueo.ensayar() }
        function ensayoSalida(): void { bloqueo.ensayarSalida() }
    }
    // La barra y el lanzador piden salir con la ventana de Menisco, no con el aviso de niri.
    function pedirSalir() { lanzadorAbierto = false; barraAbierta = false; if (!salir.abierta) salir.alternar(); }

    // Super+Shift+S, la isla, la barra y el lanzador abren el modo captura.
    // qs -p ~/.config/quickshell/isla ipc call captura abrir zona|ventana|pantalla
    IpcHandler {
        target: "captura"
        function abrir(modo: string): void { captura.abrir(modo) }
        function cerrar(): void { captura.cerrar() }
        function capturar(): void { captura.capturar() }
        function modo(m: string): void { captura.ponerModo(m) }
        function forma(f: string): void { captura.ponerForma(f) }
        function menu(): void { captura.menuFormas = !captura.menuFormas }
        // Para probar sin raton: ... ipc call captura zona 400 200 800 450
        function zona(x: real, y: real, w: real, h: real): void { captura.sx = x; captura.sy = y; captura.sw = w; captura.sh = h; }
    }
    Captura { id: captura }

    // Sombra detras de los ajustes: grande y suave, sin desenfoque, para que la ventana se
    // despegue de lo de atras. Sigue la misma entrada que el panel (crece y sube con rebote).
    // La capa cubre cada monitor: un clic fuera de la ventana la cierra.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: capaSombra
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "ajustes-sombra"
            visible: ajustes.visible
            color: "transparent"
            RectangularShadow {
                visible: capaSombra.modelData === ajustes.screen
                anchors.centerIn: parent
                width: 760; height: 556                 // el panel de Ajustes.qml
                radius: 16
                offset.y: 20
                blur: 70; spread: 20
                color: "#cc000000"
                opacity: ajustes.abierta ? 1 : 0
                scale: ajustes.abierta ? 1 : 0.9
                transform: Translate { y: ajustes.abierta ? 0 : 20; Behavior on y { NumberAnimation { duration: Estilo.t(ajustes.abierta ? 560 : 180); easing.type: ajustes.abierta ? Easing.BezierSpline : Easing.InCubic; easing.bezierCurve: Estilo.curvaRebote } } }
                Behavior on opacity { NumberAnimation { duration: Estilo.t(ajustes.abierta ? 260 : 160); easing.type: ajustes.abierta ? Easing.OutCubic : Easing.InCubic } }
                Behavior on scale { NumberAnimation { duration: Estilo.t(ajustes.abierta ? 580 : 180); easing.type: ajustes.abierta ? Easing.BezierSpline : Easing.InCubic; easing.bezierCurve: Estilo.curvaRebote } }
            }
            MouseArea { anchors.fill: parent; onClicked: ajustes.cerrar() }
        }
    }

    Variants {
        model: Quickshell.screens
        Marco { required property var modelData; screen: modelData; encendido: Estilo.valor("marco") && !raiz.modoJuego }
    }

    Variants {
        model: Quickshell.screens
        Dock { required property var modelData; screen: modelData; shell: raiz; visible: !oculto }
    }

    // Uno solo: sin pantalla fija, niri lo muestra en el monitor que se esta usando.
    VolumenOsd {}

    Variants {
        id: islas
        model: Quickshell.screens
        Isla { required property var modelData; screen: modelData; raiz: raizShell }
    }
}
