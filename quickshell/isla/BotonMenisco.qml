import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// Boton de Menisco: a la altura de la isla, en la esquina contraria al de la barra lateral.
// Icono: los tres tubos del logo (el boton hace de recuadro). Abre y cierra los ajustes.
PanelWindow {
    id: boton

    required property var raiz
    required property var ajustes
    readonly property bool abierta: ajustes.abierta

    anchors { top: true; left: Estilo.barra.lado !== "izquierda"; right: Estilo.barra.lado === "izquierda" }
    margins { top: 4; right: 10; left: 10 }
    implicitWidth: 34
    implicitHeight: 34
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "boton-menisco"

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: boton.abierta ? Estilo.activo : zona.containsMouse ? Estilo.hover : Estilo.fondo
        Behavior on color { ColorAnimation { duration: Estilo.t(220) } }
        scale: zona.pressed ? 0.86 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zona.pressed ? 80 : 420); easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.6) } }

        // Trazos copiados de assets/menisco-logo-white.svg (lienzo de 100x100, tubos al centro).
        Shape {
            id: logo
            anchors.centerIn: parent
            width: 100; height: 100
            scale: (zona.containsMouse && !boton.abierta ? 1.12 : 1) * 0.42
            Behavior on scale { NumberAnimation { duration: Estilo.t(300); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
            preferredRendererType: Shape.CurveRenderer
            readonly property color tinta: boton.abierta ? Estilo.iconoActivo : Estilo.texto
            ShapePath {
                strokeWidth: -1
                fillColor: Qt.alpha(logo.tinta, 0.45)
                PathSvg { path: "M23.5 44Q31 49.25 38.5 44V67A5 5 0 0 1 33.5 72H28.5A5 5 0 0 1 23.5 67ZM61.5 44Q69 49.25 76.5 44V67A5 5 0 0 1 71.5 72H66.5A5 5 0 0 1 61.5 67Z" }
            }
            ShapePath {
                strokeWidth: -1
                fillColor: logo.tinta
                PathSvg { path: "M42.5 28Q50 33.25 57.5 28V67A5 5 0 0 1 52.5 72H47.5A5 5 0 0 1 42.5 67Z" }
            }
        }

        MouseArea {
            id: zona
            anchors.fill: parent
            hoverEnabled: true
            onClicked: boton.ajustes.abierta ? boton.ajustes.cerrar() : boton.raiz.abrirAjustes()
        }
    }
}
