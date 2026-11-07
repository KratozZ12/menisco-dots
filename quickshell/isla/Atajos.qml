import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Tabla de atajos (Super+Shift+/): reemplaza la de niri, que no deja cambiar sus colores.
// Las teclas se leen de la config de niri cada vez que se abre (menisco-niri.py tabla), asi que
// un atajo cambiado desde Ajustes sale bien sin tocar nada aqui. Esc o un clic fuera la cierran.
PanelWindow {
    id: tabla

    property bool abierta: false
    property var filas: []
    readonly property var grupos: ["Menisco", "Ventanas", "Moverse", "Sistema"]

    function alternar() { if (abierta) abierta = false; else monitor.running = true; }

    visible: abierta || caja.opacity > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "atajos"
    WlrLayershell.keyboardFocus: abierta ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Se abre en el monitor con el foco, con las teclas ya leidas (asi no cambia de alto al aparecer).
    Process {
        id: monitor
        command: ["niri", "msg", "-j", "focused-output"]
        stdout: StdioCollector {
            onStreamFinished: {
                let nombre = "";
                try { nombre = JSON.parse(text)?.name ?? ""; } catch (e) {}
                tabla.screen = Quickshell.screens.find(s => s.name === nombre) ?? Quickshell.screens[0];
                leer.running = true;
            }
        }
    }
    Process {
        id: leer
        command: ["python3", Estilo.carpeta + "/menisco-niri.py", "tabla"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { tabla.filas = JSON.parse(text); } catch (e) {}
                tabla.abierta = true;
                foco.forceActiveFocus();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: tabla.abierta ? 0.35 : 0
        Behavior on opacity { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; onClicked: tabla.abierta = false }

    Item {
        id: foco
        focus: true
        Keys.onEscapePressed: tabla.abierta = false
    }

    Rectangle {
        id: caja
        anchors.centerIn: parent
        width: 780
        height: columna.implicitHeight + 44
        radius: 22
        color: Estilo.fondo
        border.width: 1; border.color: Estilo.borde
        opacity: tabla.abierta ? 1 : 0
        scale: tabla.abierta ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Estilo.t(tabla.abierta ? 260 : 180); easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Estilo.t(tabla.abierta ? 420 : 180); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
        MouseArea { anchors.fill: parent }   // que un clic dentro no la cierre

        Column {
            id: columna
            x: 24; y: 22; width: parent.width - 48
            spacing: 16

            Item {
                width: parent.width; height: 24
                Texto { text: "Atajos"; font.pixelSize: 18; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                Texto { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: "Esc para cerrar"; color: Estilo.texto2; font.pixelSize: 12 }
            }

            Grid {
                width: parent.width
                columns: 2; columnSpacing: 14; rowSpacing: 14
                Repeater {
                    model: tabla.grupos
                    delegate: Rectangle {
                        id: tarjeta
                        required property string modelData
                        required property int index
                        readonly property var suyas: tabla.filas.filter(f => f.grupo === modelData)
                        // Las dos tarjetas de una fila miden lo mismo: manda la que tiene mas atajos.
                        readonly property int filasPar: Math.max(suyas.length, tabla.filas.filter(f => f.grupo === tabla.grupos[index ^ 1]).length)
                        width: (columna.width - 14) / 2
                        height: 12 + 23 + filasPar * 30 + 12
                        radius: 14
                        color: Estilo.tarjeta
                        border.width: 1; border.color: Estilo.borde
                        Column {
                            id: lista
                            x: 14; y: 12; width: parent.width - 28
                            Texto {
                                text: tarjeta.modelData.toUpperCase(); color: Estilo.acento
                                font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.8
                                bottomPadding: 6
                            }
                            Repeater {
                                model: tarjeta.suyas
                                delegate: Item {
                                    required property var modelData
                                    width: lista.width; height: 30
                                    Texto { anchors.verticalCenter: parent.verticalCenter; width: parent.width - teclas.width - 8; elide: Text.ElideRight; text: modelData.titulo }
                                    Row {
                                        id: teclas
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        spacing: 4
                                        Repeater {
                                            model: modelData.teclas
                                            delegate: Tecla { required property string modelData; texto: modelData }
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

    // Tecla con un poco de relieve: el borde de abajo es mas grueso, como una tecla real.
    component Tecla: Rectangle {
        property string texto
        width: Math.max(22, t.implicitWidth + 12); height: 22; radius: 6
        color: Estilo.borde
        Rectangle {
            anchors { fill: parent; bottomMargin: 2 }
            radius: 6
            color: Estilo.hundido
            border.width: 1; border.color: Estilo.borde
            Texto { id: t; anchors.centerIn: parent; text: parent.parent.texto; font.pixelSize: 11; color: Estilo.texto }
        }
    }
    component Texto: Text {
        color: Estilo.texto
        font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
    }
}
