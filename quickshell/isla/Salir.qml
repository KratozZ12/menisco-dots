import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Cuadro de "salir de niri" (Super+Shift+E): reemplaza el de niri, que no deja cambiar sus colores.
// Enter sale, Esc o un clic fuera cancelan. Sale con `niri msg action quit --skip-confirmation`.
PanelWindow {
    id: salir

    property bool abierta: false

    function alternar() { if (abierta) abierta = false; else monitor.running = true; }
    function confirmar() { abierta = false; Quickshell.execDetached(["niri", "msg", "action", "quit", "--skip-confirmation"]); }

    visible: abierta || caja.opacity > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "salir"
    WlrLayershell.keyboardFocus: abierta ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Process {
        id: monitor
        command: ["niri", "msg", "-j", "focused-output"]
        stdout: StdioCollector {
            onStreamFinished: {
                let nombre = "";
                try { nombre = JSON.parse(text)?.name ?? ""; } catch (e) {}
                salir.screen = Quickshell.screens.find(s => s.name === nombre) ?? Quickshell.screens[0];
                salir.abierta = true;
                foco.forceActiveFocus();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: salir.abierta ? 0.45 : 0
        Behavior on opacity { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; onClicked: salir.abierta = false }

    Item {
        id: foco
        focus: true
        Keys.onEscapePressed: salir.abierta = false
        Keys.onReturnPressed: salir.confirmar()
        Keys.onEnterPressed: salir.confirmar()
    }

    Rectangle {
        id: caja
        anchors.centerIn: parent
        width: 340; height: columna.implicitHeight + 48
        radius: 22
        color: Estilo.fondo
        border.width: 1; border.color: Estilo.borde
        opacity: salir.abierta ? 1 : 0
        scale: salir.abierta ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: Estilo.t(salir.abierta ? 240 : 160); easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Estilo.t(salir.abierta ? 420 : 160); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
        MouseArea { anchors.fill: parent }   // que un clic dentro no lo cierre

        Column {
            id: columna
            x: 24; y: 24; width: parent.width - 48
            spacing: 6

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 48; height: 48; radius: 24
                color: Estilo.tarjeta; border.width: 1; border.color: Estilo.borde
                Text {
                    anchors.centerIn: parent
                    text: "logout"; color: Estilo.acento
                    font { family: "Material Symbols Rounded"; pixelSize: 24 }
                    font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 24 }
                    renderType: Text.NativeRendering
                }
            }
            Item { width: 1; height: 6 }
            Texto { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "¿Salir de niri?"; font.pixelSize: 17; font.weight: Font.DemiBold }
            Texto { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: "Se cerrarán todas las ventanas y volverá a la pantalla de inicio de sesión."; color: Estilo.texto2; font.pixelSize: 12 }
            Item { width: 1; height: 12 }
            Row {
                width: parent.width; spacing: 10
                Boton { texto: "Cancelar"; tecla: "Esc"; onPulsado: salir.abierta = false }
                Boton { texto: "Salir"; tecla: "Enter"; principal: true; onPulsado: salir.confirmar() }
            }
        }
    }

    component Boton: Rectangle {
        id: boton
        property string texto
        property string tecla
        property bool principal: false
        signal pulsado()
        width: (columna.width - 10) / 2; height: 40; radius: 12
        color: principal ? Estilo.acento : zona.containsMouse ? Estilo.hover : Estilo.tarjeta
        border.width: principal ? 0 : 1; border.color: Estilo.borde
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        scale: zona.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zona.pressed ? 80 : 340); easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.2) } }
        Row {
            anchors.centerIn: parent; spacing: 8
            Texto { anchors.verticalCenter: parent.verticalCenter; text: boton.texto; font.weight: Font.DemiBold; color: boton.principal ? Estilo.sobreAcento : Estilo.texto }
            Texto { anchors.verticalCenter: parent.verticalCenter; text: boton.tecla; font.pixelSize: 11; color: boton.principal ? Qt.alpha(Estilo.sobreAcento, 0.6) : Estilo.texto3 }
        }
        MouseArea { id: zona; anchors.fill: parent; hoverEnabled: true; onClicked: boton.pulsado() }
    }
    component Texto: Text {
        color: Estilo.texto
        font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
    }
}
