import QtQuick

// Se va con la vista general de niri: la pieza se encoge un poco hacia su orilla y se desvanece,
// rapido. Al cerrar la vista vuelve igual, al reves. Se pone dentro de la ventana:
// Gelatina { objetivo: contentItem }
// origenY: 0 se encoge hacia arriba (isla, botones), 1 hacia abajo (dock).
Item {
    id: g
    required property Item objetivo
    property real origenY: 0
    // Ventana dueña de la pieza: su mascara de clics se recalcula al volver, porque Quickshell la
    // mide una vez y, si eso pasa con la pieza encogida, queda chica para siempre.
    property var ventana: null
    readonly property bool oculto: Estilo.vistaGeneral

    Scale {
        id: escala
        origin.x: g.objetivo ? g.objetivo.width / 2 : 0
        origin.y: g.objetivo ? g.objetivo.height * g.origenY : 0
        xScale: g.oculto ? 0.8 : 1
        yScale: xScale
        Behavior on xScale { NumberAnimation { duration: Estilo.t(g.oculto ? 200 : 320); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
    }
    Component.onCompleted: objetivo.transform = [escala]

    NumberAnimation { id: fundido; target: g.objetivo; property: "opacity"; duration: Estilo.t(g.oculto ? 160 : 260); easing.type: Easing.OutCubic }
    onOcultoChanged: { fundido.to = oculto ? 0 : 1; fundido.restart(); if (!oculto) refresco.restart(); }
    Timer {
        id: refresco
        interval: 400   // un poco mas que la animacion de vuelta (320 ms)
        onTriggered: {
            const v = g.ventana;
            if (!v || g.oculto) return;
            const m = v.mask; v.mask = null; v.mask = m;
        }
    }
}
