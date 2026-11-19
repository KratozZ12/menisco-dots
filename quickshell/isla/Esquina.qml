import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// Botones de una esquina de arriba, a la altura de la isla (Ajustes > Esquinas).
// La lista va de izquierda a derecha tal como se ve; "bandeja" deja el hueco donde se
// pone la ventana de Bandeja.qml. Con marco dibuja ademas la oreja que los guarda.
PanelWindow {
    id: esq

    required property var raiz
    required property var ajustes
    required property string lado                       // izquierda | derecha
    readonly property bool derecha: lado === "derecha"
    readonly property var lista: Estilo.botones[lado] || []

    visible: lista.some(b => b !== "bandeja" || Estilo.anchoBandeja > 0)
    anchors { top: true; left: !derecha; right: derecha }
    // La ventana empieza en la esquina de la pantalla (sin margenes: niri no aplica un margen
    // que cambia antes de mostrarse) y los botones van dentro, a 10 px del borde.
    readonly property bool conMarco: Estilo.grosorMarco > 0 && !raiz.modoJuego
    implicitWidth: conMarco ? oreja.width : fila.width + 10
    implicitHeight: conMarco ? oreja.height : 38
    mask: Region { item: fila }
    exclusionMode: ExclusionMode.Ignore                 // la isla ya reserva esta franja
    color: "transparent"
    WlrLayershell.namespace: "esquina"
    Gelatina { objetivo: esq.contentItem; origenY: 0 }  // se va con la vista general

    Oreja {
        id: oreja
        visible: esq.conMarco
        espejo: esq.derecha
        ancho: fila.width + 20
    }

    Row {
        id: fila
        x: esq.derecha ? esq.width - 10 - width : 10
        y: 4 + Estilo.grosorMarco
        spacing: 8
        Repeater {
            model: esq.lista
            delegate: Loader {
                required property string modelData
                sourceComponent: modelData === "bandeja" ? hueco : boton
                property string clave: modelData
            }
        }
    }

    // Hueco de la bandeja: la pildora es otra ventana, encima.
    Component { id: hueco; Item { width: Estilo.anchoBandeja; height: 34; visible: width > 0 } }

    Component {
        id: boton
        Rectangle {
            id: b
            readonly property string clave: parent ? parent.clave : ""
            readonly property bool encendido: clave === "menisco" ? esq.ajustes.abierta
                : clave === "barra" ? esq.raiz.barraAbierta
                : clave === "lanzador" ? esq.raiz.lanzadorAbierto
                : clave === "nomolestar" ? Estilo.noMolestar
                : clave === "juego" ? esq.raiz.modoJuego
                : clave === "flotante" ? esq.raiz.flotanteAqui
                : clave === "vista" ? Estilo.vistaGeneral : false
            width: 34; height: 34; radius: 12
            color: encendido ? Estilo.activo : zona.containsMouse ? Estilo.realce : Estilo.fondo
            Behavior on color { ColorAnimation { duration: Estilo.t(220) } }
            scale: zona.pressed ? 0.86 : 1
            Behavior on scale { NumberAnimation { duration: Estilo.t(zona.pressed ? 80 : 420); easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.6) } }
            readonly property color tinta: encendido ? Estilo.iconoActivo : Estilo.texto
            readonly property real crece: zona.containsMouse && !encendido ? 1.12 : 1

            // Menisco: los tres tubos del logo (assets/menisco-logo-white.svg, lienzo de 100x100)
            Shape {
                visible: b.clave === "menisco"
                anchors.centerIn: parent
                width: 100; height: 100
                scale: b.crece * 0.42
                Behavior on scale { NumberAnimation { duration: Estilo.t(300); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillColor: Qt.alpha(b.tinta, 0.45)
                    PathSvg { path: "M23.5 44Q31 49.25 38.5 44V67A5 5 0 0 1 33.5 72H28.5A5 5 0 0 1 23.5 67ZM61.5 44Q69 49.25 76.5 44V67A5 5 0 0 1 71.5 72H66.5A5 5 0 0 1 61.5 67Z" }
                }
                ShapePath {
                    strokeWidth: -1
                    fillColor: b.tinta
                    PathSvg { path: "M42.5 28Q50 33.25 57.5 28V67A5 5 0 0 1 52.5 72H47.5A5 5 0 0 1 42.5 67Z" }
                }
            }
            // Barra lateral: destello de cuatro puntas; gira un cuarto de vuelta al abrir.
            Shape {
                visible: b.clave === "barra"
                anchors.centerIn: parent
                width: 18; height: 18
                preferredRendererType: Shape.CurveRenderer
                rotation: b.encendido ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: Estilo.t(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                scale: b.crece
                Behavior on scale { NumberAnimation { duration: Estilo.t(300); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                ShapePath {
                    fillColor: b.tinta
                    strokeWidth: -1
                    startX: 9; startY: 0
                    PathQuad { x: 18; y: 9; controlX: 10.2; controlY: 7.8 }
                    PathQuad { x: 9; y: 18; controlX: 10.2; controlY: 10.2 }
                    PathQuad { x: 0; y: 9; controlX: 7.8; controlY: 10.2 }
                    PathQuad { x: 9; y: 0; controlX: 7.8; controlY: 7.8 }
                }
            }
            // El resto: icono de Material Symbols
            Text {
                visible: b.clave !== "menisco" && b.clave !== "barra"
                anchors.centerIn: parent
                text: (Estilo.botonesCatalogo.find(c => c[0] === b.clave) || ["", "", "help"])[2]
                font { family: "Material Symbols Rounded"; pixelSize: 19 }
                font.variableAxes: { "FILL": b.encendido ? 1 : 0, "wght": 500, "opsz": 24 }
                renderType: Text.NativeRendering
                color: b.tinta
                scale: b.crece
                Behavior on scale { NumberAnimation { duration: Estilo.t(300); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
            }

            MouseArea {
                id: zona
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: esq.pulsar(b.clave)
            }
        }
    }

    function pulsar(clave) {
        if (clave === "menisco") ajustes.abierta ? ajustes.cerrar() : raiz.abrirAjustes();
        else if (clave === "barra") raiz.barraAbierta = !raiz.barraAbierta;
        else if (clave === "lanzador") raiz.lanzadorAbierto = !raiz.lanzadorAbierto;
        else if (clave === "captura") raiz.abrirCaptura();
        else if (clave === "nomolestar") Estilo.ponerNoMolestar(!Estilo.noMolestar);
        else if (clave === "juego") raiz.alternarModoJuego();
        else if (clave === "vista") Quickshell.execDetached(["niri", "msg", "action", "toggle-overview"]);
        else if (clave === "flotante") raiz.alternarFlotante();
        else if (clave === "bloquear") raiz.bloquear();
        else if (clave === "fondo") Quickshell.execDetached(Estilo.comandoSiguienteFondo);
    }
}
