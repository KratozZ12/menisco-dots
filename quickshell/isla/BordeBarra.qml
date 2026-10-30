import QtQuick
import Quickshell
import Quickshell.Wayland

// Dos ventanas invisibles al servicio de la barra lateral (segun sus ajustes):
// - el borde: una franja de 2 px en el lado de la barra; con el cursor ahi 250 ms, se abre.
// - el clic fuera: con la barra abierta, cubre la pantalla por debajo de ella y la cierra.
Scope {
    id: borde
    required property var raiz
    readonly property var cfg: Estilo.barra

    PanelWindow {
        visible: borde.cfg.borde && !borde.raiz.barraAbierta
        anchors { top: true; bottom: true; right: borde.cfg.lado !== "izquierda"; left: borde.cfg.lado === "izquierda" }
        implicitWidth: 2
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "barra-borde"

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: espera.restart()
            onExited: espera.stop()
            Timer { id: espera; interval: 250; onTriggered: borde.raiz.barraAbierta = true }
        }
    }

    PanelWindow {
        visible: borde.cfg.clicFuera && borde.raiz.barraAbierta
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top     // la barra va en Overlay, por encima de esta
        WlrLayershell.namespace: "barra-fuera"
        MouseArea { anchors.fill: parent; onPressed: borde.raiz.barraAbierta = false }
    }
}
