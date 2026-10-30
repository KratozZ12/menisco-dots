import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris

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

    // ---- Modo juego: rendimiento maximo, No molestar, sin dock y sin suspender ----
    // Al apagarlo, todo vuelve a como estaba antes de encenderlo.
    property bool modoJuego: false
    property var antesDeJugar: null
    function alternarModoJuego() {
        if (!modoJuego) {
            antesDeJugar = { perfil: perfilActual, dnd: Estilo.noMolestar, cafe: ajustes.cafe };
            Quickshell.execDetached(["powerprofilesctl", "set", "performance"]);
            Estilo.ponerNoMolestar(true);
            ajustes.cafe = true;
            modoJuego = true;
        } else {
            const a = antesDeJugar || { perfil: "balanced", dnd: false, cafe: false };
            Quickshell.execDetached(["powerprofilesctl", "set", a.perfil]);
            Estilo.ponerNoMolestar(a.dnd);
            ajustes.cafe = a.cafe;
            modoJuego = false;
        }
    }
    property string perfilActual: "balanced"
    Process { running: true; command: ["powerprofilesctl", "get"]; stdout: StdioCollector { onStreamFinished: raiz.perfilActual = text.trim() } }

    // ---- Temporizador (se inicia desde el lanzador: "temporizador 5 min") ----
    signal temporizadorTerminado()
    property real temporizadorFin: 0
    property int temporizadorRestante: 0
    function iniciarTemporizador(segundos) { temporizadorFin = Date.now() + segundos * 1000; temporizadorRestante = segundos; }
    function cancelarTemporizador() { temporizadorFin = 0; temporizadorRestante = 0; }
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
    property real origenLanzadorX: 0      // del boton de cuadricula del dock al centro de la pantalla

    function abrirAjustes() { lanzadorAbierto = false; barraAbierta = false; if (!ajustes.abierta) monitorActivo.running = true; }

    // Super+D y el boton del dock llaman a esto.
    IpcHandler {
        target: "lanzador"
        function toggle(): void { raiz.lanzadorAbierto = !raiz.lanzadorAbierto }
    }
    Lanzador { raiz: raiz }

    // Super+A abre y cierra la barra lateral (centro de control).
    IpcHandler {
        target: "barra"
        function toggle(): void { raiz.barraAbierta = !raiz.barraAbierta }
    }
    Barra { raiz: raiz; ajustes: ajustes }
    BotonBarra { raiz: raiz }
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
        Dock { required property var modelData; screen: modelData; shell: raiz; visible: !raiz.modoJuego }
    }

    // Uno solo: sin pantalla fija, niri lo muestra en el monitor que se esta usando.
    VolumenOsd {}

    Variants {
        model: Quickshell.screens
        Isla { required property var modelData; screen: modelData; raiz: raizShell }
    }
}
