import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Ventana de novedades: sale una vez despues de cada actualizacion (novedades.json cambia de
// "version"), centrada en el monitor con foco y encima de todo, asi que las reglas de ventana
// de niri no la tocan. Siempre en Onix, sea cual sea el tema. IPC: novedades abrir.
PanelWindow {
    id: nov

    required property var raiz
    property bool abierta: false
    property var info: ({ lista: [] })
    // 0 = solo el logo, 1 = mas el titulo, 2 = todo
    property int etapa: 0
    signal olaLetras()
    signal entraResto()
    readonly property var c: Estilo.temas.onix

    function abrir() { monitor.running = true; }
    function reiniciar() { torres.hI = 44; torres.oI = 0.35; torres.hD = 44; torres.oD = 0.35; torres.hC = 40; torres.oC = 0.6; etiquetaFecha.opacity = 0; etapa = 0; }
    function cerrar() { abierta = false; Estilo.poner("novedadesVista", info.version); }

    visible: abierta || caja.opacity > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "novedades"
    WlrLayershell.keyboardFocus: abierta ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    FileView {
        path: Qt.resolvedUrl("novedades.json")
        onLoaded: { try { nov.info = JSON.parse(text()); } catch (e) {} }
    }
    // Da tiempo a que Estilo lea menisco.json antes de comparar.
    Timer {
        running: true; interval: 3000
        onTriggered: if (nov.info.version && Estilo.valor("novedadesVista") !== nov.info.version) nov.abrir()
    }

    Process {
        id: monitor
        command: ["niri", "msg", "-j", "focused-output"]
        stdout: StdioCollector {
            onStreamFinished: {
                let nombre = "";
                try { nombre = JSON.parse(text)?.name ?? ""; } catch (e) {}
                nov.screen = Quickshell.screens.find(s => s.name === nombre) ?? Quickshell.screens[0];
                nov.abierta = true;
                foco.forceActiveFocus();
                logo.restart();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: nov.abierta ? 0.45 : 0
        Behavior on opacity { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; onClicked: nov.cerrar() }

    Item {
        id: foco
        focus: true
        Keys.onEscapePressed: nov.cerrar()
        Keys.onReturnPressed: nov.cerrar()
        Keys.onEnterPressed: nov.cerrar()
    }

    Rectangle {
        id: caja
        anchors.centerIn: parent
        width: nov.etapa === 0 ? 200 : 360
        height: nov.etapa === 0 ? torres.y + torres.height + 26 + columna.y
              : nov.etapa === 1 ? textos.y + textos.height + 26 + columna.y
              : columna.y + columna.implicitHeight + 24
        Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
        Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
        clip: true
        radius: 22
        color: nov.c.fondo
        border.width: 1; border.color: nov.c.borde
        opacity: nov.abierta ? 1 : 0
        scale: nov.abierta ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: Estilo.t(nov.abierta ? 240 : 160); easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Estilo.t(nov.abierta ? 420 : 160); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
        MouseArea { anchors.fill: parent }

        // Marca de Menisco arriba a la izquierda, como en la barra lateral de Ajustes
        FontLoader { id: letraMarca; source: Qt.resolvedUrl("fuentes/Archivo-ExpandedBlack.ttf") }
        Row {
            x: 18; y: 16; spacing: 6
            Shape {
                width: 53 * 0.27; height: 44 * 0.27
                anchors.verticalCenter: marca.verticalCenter
                preferredRendererType: Shape.CurveRenderer
                transform: Scale { xScale: 0.27; yScale: 0.27 }
                ShapePath {
                    strokeWidth: -1; fillColor: Qt.alpha(nov.c.texto2, 0.45)
                    PathSvg { path: "M0 16Q7.5 21.25 15 16V39A5 5 0 0 1 10 44H5A5 5 0 0 1 0 39ZM38 16Q45.5 21.25 53 16V39A5 5 0 0 1 48 44H43A5 5 0 0 1 38 39Z" }
                }
                ShapePath {
                    strokeWidth: -1; fillColor: nov.c.texto2
                    PathSvg { path: "M19 0Q26.5 5.25 34 0V39A5 5 0 0 1 29 44H24A5 5 0 0 1 19 39Z" }
                }
            }
            Text {
                id: marca
                text: "MENISCO"; color: nov.c.texto2
                font { family: letraMarca.name; pixelSize: 11; weight: Font.Black; letterSpacing: 0.4 }
            }
        }

        // Ancho fijo y centrado: con la caja angosta, lo de los lados queda recortado.
        Column {
            id: columna
            width: 312; x: (parent.width - width) / 2; y: 44
            spacing: 6

            // Las tres torres del logo (lienzo de 100x100 de assets/menisco-logo-white.svg,
            // ventana de x 15..85, y 10..78). La del centro espera su turno y sale con rebote.
            Item {
                id: torres
                anchors.horizontalCenter: parent.horizontalCenter
                width: 76; height: 74
                readonly property real k: width / 70
                property real hI: 44; property real oI: 0.35
                property real hD: 44; property real oD: 0.35
                property real hC: 40; property real oC: 0.6
                function camino(x, top) {
                    const w = 15, f = 72;
                    return `M${x} ${top}Q${x + w / 2} ${top + 5.25} ${x + w} ${top}V${f - 5}A5 5 0 0 1 ${x + w - 5} ${f}H${x + 5}A5 5 0 0 1 ${x} ${f - 5}Z`;
                }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    transform: [Translate { x: -15; y: -10 }, Scale { xScale: torres.k; yScale: torres.k }]
                    ShapePath { strokeWidth: -1; fillColor: Qt.alpha(nov.c.texto, torres.oI); PathSvg { path: torres.camino(23.5, torres.hI) } }
                    ShapePath { strokeWidth: -1; fillColor: Qt.alpha(nov.c.texto, torres.oD); PathSvg { path: torres.camino(61.5, torres.hD) } }
                    ShapePath { strokeWidth: -1; fillColor: Qt.alpha(nov.c.texto, torres.oC); PathSvg { path: torres.camino(42.5, torres.hC) } }
                }
            }

            Item { width: 1; height: 6 }
            Column {
                id: textos
                width: parent.width; spacing: 6
                // Letra por letra: cada una sube, se pasa un poco y vuelve a su sitio.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    Repeater {
                        model: "Menisco se actualizó".split("")
                        delegate: Texto {
                            id: letra
                            required property string modelData
                            required property int index
                            text: modelData; font.pixelSize: 17; font.weight: Font.DemiBold
                            opacity: 0
                            transform: Translate { id: alza; y: 0 }
                            Connections { target: nov; function onOlaLetras() { ola.restart(); } }
                            Connections { target: nov; function onEtapaChanged() { if (nov.etapa === 0) { ola.stop(); letra.opacity = 0; alza.y = 0; } } }
                            SequentialAnimation {
                                id: ola
                                PauseAnimation { duration: letra.index * 35 }
                                ParallelAnimation {
                                    NumberAnimation { target: alza; property: "y"; to: -9; duration: 170; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: letra; property: "opacity"; to: 1; duration: 140 }
                                }
                                NumberAnimation { target: alza; property: "y"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                            }
                        }
                    }
                }
                Rectangle {
                    id: etiquetaFecha
                    opacity: 0
                    Behavior on opacity { NumberAnimation { duration: 260 } }
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: etiqueta.implicitWidth + 20; height: 20; radius: 10
                    color: nov.c.tarjeta; border.width: 1; border.color: nov.c.borde
                    Texto { id: etiqueta; anchors.centerIn: parent; text: nov.info.fecha || ""; font.pixelSize: 11; color: nov.c.texto2 }
                }
            }
            Item { width: 1; height: 12 }
            Repeater {
                model: nov.info.lista
                delegate: Rectangle {
                    id: fila
                    required property var modelData
                    required property int index
                    width: columna.width; height: 52; radius: 14
                    color: nov.c.tarjeta
                    Entrada { objetivo: fila; retraso: fila.index * 80 }
                    Rectangle {
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 32; radius: 10
                        color: nov.c.activo
                        Text {
                            anchors.centerIn: parent
                            text: modelData.icono; color: nov.c.iconoActivo
                            font { family: "Material Symbols Rounded"; pixelSize: 19 }
                            font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 20 }
                            renderType: Text.NativeRendering
                        }
                    }
                    Column {
                        x: 56; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                        Texto { text: modelData.titulo; font.weight: Font.DemiBold }
                        Texto { text: modelData.texto; font.pixelSize: 12; color: nov.c.texto2 }
                    }
                }
            }
            Item { width: 1; height: 12 }
            Row {
                id: botones
                width: parent.width; spacing: 10
                Entrada { objetivo: botones; retraso: nov.info.lista.length * 80 + 60 }
                Boton { texto: "Ver en Ajustes"; onPulsado: { nov.cerrar(); nov.raiz.abrirAjustesEn(nov.info.seccion || "inicio"); } }
                Boton { texto: "Entendido"; tecla: "Enter"; principal: true; onPulsado: nov.cerrar() }
            }
        }
    }

    // Tiempos del mockup aprobado (x0.8). Fijos: no siguen la velocidad de Ajustes.
    SequentialAnimation {
        id: logo
        ScriptAction { script: nov.reiniciar() }
        PauseAnimation { duration: 200 }
        // izquierda, luego derecha
        Sube { blanco: "I"; h: 32; o: 0.9; duracion: 192 }
        Baja { blanco: "I"; duracion: 208 }
        Sube { blanco: "D"; h: 32; o: 0.9; duracion: 160 }
        Baja { blanco: "D"; duracion: 184 }
        // redoble de las dos
        ParallelAnimation { Sube { blanco: "I"; h: 38; o: 0.7; duracion: 112 } Sube { blanco: "D"; h: 38; o: 0.7; duracion: 112 } }
        ParallelAnimation { Baja { blanco: "I"; duracion: 136 } Baja { blanco: "D"; duracion: 136 } }
        ParallelAnimation { Sube { blanco: "I"; h: 39; o: 0.7; duracion: 88 } Sube { blanco: "D"; h: 39; o: 0.7; duracion: 88 } }
        ParallelAnimation { Baja { blanco: "I"; duracion: 112 } Baja { blanco: "D"; duracion: 112 } }
        // la del centro toma impulso y espera
        ParallelAnimation {
            NumberAnimation { target: torres; property: "hC"; to: 53; duration: 336; easing.type: Easing.InOutQuad }
            NumberAnimation { target: torres; property: "oC"; to: 0.45; duration: 336 }
        }
        PauseAnimation { duration: 224 }
        // el golpe: sale con resorte, los lados se hunden y rebotan, entra el texto
        ParallelAnimation {
            NumberAnimation { target: torres; property: "hC"; to: 28; duration: 1040; easing.type: Easing.OutElastic; easing.amplitude: 1; easing.period: 0.37 }
            NumberAnimation { target: torres; property: "oC"; to: 1; duration: 200 }
            SequentialAnimation { PauseAnimation { duration: 600 } ScriptAction { script: nov.etapa = 1 } }
            SequentialAnimation {
                ParallelAnimation { Sube { blanco: "I"; h: 49; o: 0.4; duracion: 120 } Sube { blanco: "D"; h: 49; o: 0.4; duracion: 120 } }
                ParallelAnimation {
                    NumberAnimation { target: torres; property: "hI"; to: 44; duration: 960; easing.type: Easing.OutElastic; easing.amplitude: 1; easing.period: 0.37 }
                    NumberAnimation { target: torres; property: "hD"; to: 44; duration: 960; easing.type: Easing.OutElastic; easing.amplitude: 1; easing.period: 0.37 }
                    NumberAnimation { target: torres; property: "oI"; to: 0.45; duration: 300 }
                    NumberAnimation { target: torres; property: "oD"; to: 0.45; duration: 300 }
                }
            }
        }
        // el titulo letra por letra, despues la fecha, y al final se abre todo lo de abajo
        ScriptAction { script: nov.olaLetras() }
        PauseAnimation { duration: 19 * 35 + 380 }
        ScriptAction { script: etiquetaFecha.opacity = 1 }
        PauseAnimation { duration: 180 }
        ScriptAction { script: nov.etapa = 2 }
        PauseAnimation { duration: 160 }
        ScriptAction { script: nov.entraResto() }
    }

    // Aparece subiendo un poco, con retraso para que entren en cascada. Escondido en las etapas 0 y 1.
    component Entrada: Item {
        id: entrada
        visible: false   // que Row y Column no le den hueco
        required property Item objetivo
        property int retraso: 0
        Component.onCompleted: { objetivo.opacity = 0; objetivo.transform = [mover]; }
        Translate { id: mover; y: 12 }
        Connections { target: nov; function onEntraResto() { anim.restart(); } }
        Connections { target: nov; function onEtapaChanged() { if (nov.etapa === 0) { anim.stop(); entrada.objetivo.opacity = 0; mover.y = 12; } } }
        SequentialAnimation {
            id: anim
            PauseAnimation { duration: entrada.retraso }
            ParallelAnimation {
                NumberAnimation { target: entrada.objetivo; property: "opacity"; to: 1; duration: 220 }
                NumberAnimation { target: mover; property: "y"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            }
        }
    }

    component Sube: ParallelAnimation {
        property string blanco
        property real h
        property real o
        property int duracion
        NumberAnimation { target: torres; property: "h" + blanco; to: h; duration: duracion; easing.type: Easing.OutCubic }
        NumberAnimation { target: torres; property: "o" + blanco; to: o; duration: duracion }
    }
    component Baja: ParallelAnimation {
        property string blanco
        property int duracion
        NumberAnimation { target: torres; property: "h" + blanco; to: 44; duration: duracion; easing.type: Easing.InOutQuad }
        NumberAnimation { target: torres; property: "o" + blanco; to: 0.35; duration: duracion }
    }

    component Boton: Rectangle {
        id: boton
        property string texto
        property string tecla
        property bool principal: false
        signal pulsado()
        width: (columna.width - 10) / 2; height: 40; radius: 12
        color: principal ? nov.c.acento : zona.containsMouse ? nov.c.hover : nov.c.tarjeta
        border.width: principal ? 0 : 1; border.color: nov.c.borde
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        scale: zona.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zona.pressed ? 80 : 340); easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.2) } }
        Row {
            anchors.centerIn: parent; spacing: 8
            Texto { anchors.verticalCenter: parent.verticalCenter; text: boton.texto; font.weight: Font.DemiBold; color: boton.principal ? nov.c.sobreAcento : nov.c.texto }
            Texto { visible: boton.tecla !== ""; anchors.verticalCenter: parent.verticalCenter; text: boton.tecla; font.pixelSize: 11; color: boton.principal ? Qt.alpha(nov.c.sobreAcento, 0.6) : nov.c.texto3 }
        }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zona; anchors.fill: parent; hoverEnabled: true; onClicked: boton.pulsado() }
    }
    component Texto: Text {
        color: nov.c.texto
        font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
    }
}
