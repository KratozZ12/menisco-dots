import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Isla dinamica de adorno, pegada al borde de arriba como una muesca del monitor.
// Abajo esquinas redondeadas; arriba, curvas hacia afuera que la funden con el borde.
// Muestra la hora.
ShellRoot {
    id: raiz
    property bool islaVisible: true
    property string emocion: "normal"   // normal, feliz, escucha, pensar, emocion, confuso

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

    Variants {
        model: Quickshell.screens
        Dock { required property var modelData; screen: modelData }
    }

    // Uno solo: sin pantalla fija, niri lo muestra en el monitor que se esta usando.
    VolumenOsd {}

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: raiz.islaVisible

            readonly property real ancho: 360
            readonly property real alto: 42
            readonly property real esquina: 20               // radio de las esquinas de abajo
            readonly property real hombro: esquina * 0.9      // curva que la funde con el borde de arriba

            anchors.top: true
            implicitWidth: ancho + hombro * 2
            implicitHeight: alto
            color: "transparent"
            WlrLayershell.namespace: "isla"

            // Forma "squircle": curvas continuas (Bezier) en vez de arcos de circulo,
            // como las esquinas del hardware de Apple. k = 0.62 da la tension de la curva.
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    id: p
                    readonly property real r: win.esquina
                    readonly property real x0: win.hombro
                    readonly property real x1: win.hombro + win.ancho
                    readonly property real h: win.alto
                    readonly property real k: 0.62

                    fillColor: "#242424"   // mismo gris que las tarjetas de Hokum (tema capsule)
                    strokeWidth: -1
                    startX: 0; startY: 0

                    PathCubic { control1X: p.x0 - p.r * 0.25; control1Y: 0; control2X: p.x0; control2Y: p.r * 0.15; x: p.x0; y: p.r * 0.9 }
                    PathLine { x: p.x0; y: p.h - p.r }
                    PathCubic { control1X: p.x0; control1Y: p.h - p.r * (1 - p.k); control2X: p.x0 + p.r * (1 - p.k); control2Y: p.h; x: p.x0 + p.r; y: p.h }
                    PathLine { x: p.x1 - p.r; y: p.h }
                    PathCubic { control1X: p.x1 - p.r * (1 - p.k); control1Y: p.h; control2X: p.x1; control2Y: p.h - p.r * (1 - p.k); x: p.x1; y: p.h - p.r }
                    PathLine { x: p.x1; y: p.r * 0.9 }
                    PathCubic { control1X: p.x1; control1Y: p.r * 0.15; control2X: p.x1 + p.r * 0.25; control2Y: 0; x: p.x1 + win.hombro; y: 0 }
                }
            }
            // Reloj en SF Pro Text Semibold, como el de la barra de estado del iPhone.
            SystemClock {
                id: reloj
                precision: SystemClock.Minutes
            }

            // Asistente a la izquierda, donde antes estaba el reloj.
            Asistente {
                width: 40
                height: 40
                anchors.left: parent.left
                anchors.leftMargin: win.hombro + 6
                anchors.verticalCenter: parent.verticalCenter
                emocion: raiz.emocion
            }

            // Visualizador de audio a la derecha, a la misma distancia del borde que el asistente.
            Visualizador {
                anchors.right: parent.right
                anchors.rightMargin: win.hombro + 18
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                text: Qt.formatTime(reloj.date, "h:mm")
                color: "#ffffff"
                font.family: "SF Pro Text"
                font.weight: Font.DemiBold
                font.pixelSize: 19
                font.letterSpacing: -0.45
                font.features: { "tnum": 1 }   // cifras de ancho fijo: no baila al cambiar
            }
        }
    }
}
