import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// Boton de la barra lateral: arriba a la derecha, a la altura de la isla.
// Icono: destello de cuatro puntas con lados curvos hacia adentro.
PanelWindow {
    id: boton

    required property var raiz
    readonly property bool abierta: raiz.barraAbierta

    // En el mismo lado que la barra; se oculta si asi se elige en los ajustes.
    visible: Estilo.barra.boton
    anchors { top: true; right: Estilo.barra.lado !== "izquierda"; left: Estilo.barra.lado === "izquierda" }
    margins { top: 4; right: 10; left: 10 }
    implicitWidth: 34
    implicitHeight: 34
    exclusionMode: ExclusionMode.Ignore   // la isla ya reserva esta franja
    color: "transparent"
    WlrLayershell.namespace: "boton-barra"

    Rectangle {
        id: fondo
        anchors.fill: parent
        radius: 12
        // Abierta: blanco con el destello oscuro, como los botones encendidos de Menisco.
        color: boton.abierta ? "#ffffff" : zona.containsMouse ? Qt.lighter(Estilo.fondo, 1.45) : Estilo.fondo
        Behavior on color { ColorAnimation { duration: Estilo.t(220) } }
        scale: zona.pressed ? 0.86 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zona.pressed ? 80 : 420); easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.6) } }

        Shape {
            id: destello
            anchors.centerIn: parent
            width: 18; height: 18
            preferredRendererType: Shape.CurveRenderer
            // Gira un cuarto de vuelta al abrir y regresa al cerrar; al pasar el cursor crece un poco.
            rotation: boton.abierta ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: Estilo.t(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
            scale: zona.containsMouse && !boton.abierta ? 1.12 : 1
            Behavior on scale { NumberAnimation { duration: Estilo.t(300); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }

            ShapePath {
                fillColor: boton.abierta ? "#111111" : "#ffffff"
                Behavior on fillColor { ColorAnimation { duration: Estilo.t(220) } }
                strokeWidth: -1
                // Cuatro puntas (arriba, derecha, abajo, izquierda) unidas por curvas que
                // pasan cerca del centro: eso hace los lados concavos.
                startX: 9; startY: 0
                PathQuad { x: 18; y: 9; controlX: 10.2; controlY: 7.8 }
                PathQuad { x: 9; y: 18; controlX: 10.2; controlY: 10.2 }
                PathQuad { x: 0; y: 9; controlX: 7.8; controlY: 10.2 }
                PathQuad { x: 9; y: 0; controlX: 7.8; controlY: 7.8 }
            }
        }

        MouseArea {
            id: zona
            anchors.fill: parent
            hoverEnabled: true
            onClicked: boton.raiz.barraAbierta = !boton.raiz.barraAbierta
        }
    }
}
