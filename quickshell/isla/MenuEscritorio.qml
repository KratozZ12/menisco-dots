import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Menu de clic derecho en el fondo de pantalla. Una capa transparente debajo de las ventanas
// (capa Bottom, encima del fondo de awww) recibe el clic derecho donde no hay ventana; el menu
// sale en la capa de arriba, en el punto del clic. Esc o un clic fuera lo cierran.
// Arriba el fondo actual y los dos siguientes, luego accesos rapidos, atajos a Ajustes y el boton grande.
Scope {
    id: m
    required property var raiz
    property bool abierto: false
    property var pantalla: null
    property real px: 0
    property real py: 0

    readonly property var rapidos: [
        { id: "fondo", texto: "Siguiente", icono: "shuffle" },
        { id: "flotante", texto: "Flotante", icono: "web_asset" },
        { id: "dnd", texto: "No molestar", icono: "do_not_disturb_on" },
        { id: "juego", texto: "Juego", icono: "sports_esports" },
        { id: "bloquear", texto: "Bloquear", icono: "lock" }
    ]
    readonly property var secciones: [
        { id: "apariencia", texto: "Temas", sub: "Color, letra y movimiento", icono: "palette" },
        { id: "ventanas", texto: "Ventanas", sub: "Esquinas, espacio y marco", icono: "view_column" },
        { id: "vidrio", texto: "Liquid glass", sub: "Vidrio de ventanas y dock", icono: "water_drop" },
        { id: "dock", texto: "Dock", sub: "Material, forma y posición", icono: "dock_to_bottom" },
        { id: "barra", texto: "Barra lateral", sub: "Lado y lo que muestra", icono: "dock_to_right" },
        { id: "pantallas", texto: "Pantallas", sub: "Resolución, escala y posición", icono: "desktop_windows" }
    ]
    function encendido(id) {
        return id === "flotante" ? raiz.flotanteAqui : id === "dnd" ? Estilo.noMolestar : id === "juego" ? raiz.modoJuego : false;
    }

    function abrir(pant, x, y) { pantalla = pant; px = x; py = y; abierto = true; leer.running = true; caja.entrar(); }
    // Los interruptores y "Siguiente" dejan el menu abierto para ver el cambio; lo demas lo cierra.
    function elegir(id) {
        if (id === "fondo") { Quickshell.execDetached(Estilo.comandoSiguienteFondo); releer.restart(); return; }
        if (id === "flotante") { raiz.alternarFlotante(); return; }
        if (id === "dnd") { Estilo.ponerNoMolestar(!Estilo.noMolestar); return; }
        if (id === "juego") { raiz.alternarModoJuego(); return; }
        abierto = false;
        if (id === "bloquear") raiz.bloquear();
        else if (id === "ajustes") raiz.abrirAjustes();
        else raiz.abrirAjustesEn(id);
    }
    function ponerFondo(ruta) {
        Quickshell.execDetached(["awww", "img", ruta, "--transition-type", "grow", "--transition-fps", "144"]);
        actual = ruta;
    }

    // Fondo actual y los dos que siguen, en el mismo orden que "Siguiente fondo".
    readonly property string carpetaFondos: Quickshell.env("HOME") + "/Imágenes/Wallpapers"
    property string actual: ""
    property var lista: []
    readonly property var miniaturas: {
        if (!lista.length) return [];
        const i = Math.max(0, lista.indexOf(actual.split("/").pop()));
        return [0, 1, 2].map(k => carpetaFondos + "/" + lista[(i + k) % lista.length]).filter((v, k, a) => a.indexOf(v) === k);
    }
    Process {
        id: leer
        command: ["sh", "-c", "awww query 2>/dev/null | sed -n 's/.*image: //p' | head -1; ls \"$HOME/Imágenes/Wallpapers\" | grep -iE '\\.(jpe?g|png|webp)$'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n").filter(x => x);
                m.actual = l[0] ?? "";
                m.lista = l.slice(1);
            }
        }
    }
    Timer { id: releer; interval: 400; onTriggered: leer.running = true }

    // Recibe el clic derecho sobre el fondo, uno por monitor.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: fondo
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "menisco-escritorio"
            visible: !m.raiz.modoJuego
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: e => m.abrir(fondo.modelData, e.x, e.y)
            }
        }
    }

    PanelWindow {
        id: capa
        screen: m.pantalla ?? Quickshell.screens[0]
        visible: m.abierto || caja.opacity > 0.01
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "menu-escritorio"
        WlrLayershell.keyboardFocus: m.abierto ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: m.abierto = false }
        Item { id: foco; focus: m.abierto; Keys.onEscapePressed: m.abierto = false }

        Rectangle {
            id: caja
            // Junto al cursor; si no cabe a la derecha o abajo, sale hacia el otro lado (y nunca se sale de la pantalla).
            x: Math.max(8, m.px + width + 8 > capa.width ? m.px - width : m.px)
            y: Math.max(8, Math.min(capa.height - height - 8, m.py + height + 8 > capa.height ? m.py - height : m.py))
            width: 340
            height: columna.implicitHeight + 28
            radius: 26
            color: Estilo.fondo
            border.color: Estilo.borde
            border.width: 1
            transformOrigin: x < m.px ? (y < m.py ? Item.BottomRight : Item.TopRight) : (y < m.py ? Item.BottomLeft : Item.TopLeft)
            opacity: m.abierto ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Estilo.t(m.abierto ? 200 : 140); easing.type: Easing.OutCubic } }
            function entrar() { brota.restart(); foco.forceActiveFocus(); }
            NumberAnimation { id: brota; target: caja; property: "scale"; from: 0.85; to: 1; duration: Estilo.t(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote }
            MouseArea { anchors.fill: parent }   // un clic en el borde no lo cierra

            Column {
                id: columna
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 12

                // ---- Fondos ----
                Item {
                    width: parent.width; height: 28
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Fondos"; color: Estilo.texto
                        font { family: Estilo.letra; pixelSize: 15; weight: Font.DemiBold; letterSpacing: -0.23 }
                    }
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: filaTodos.implicitWidth + 20; height: 26; radius: 13
                        color: zonaTodos.containsMouse ? Estilo.realce : Estilo.hover
                        Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
                        scale: zonaTodos.pressed ? 0.94 : 1
                        Behavior on scale { NumberAnimation { duration: Estilo.t(140); easing.type: Easing.OutCubic } }
                        Row {
                            id: filaTodos
                            anchors.centerIn: parent; spacing: 4
                            Text { text: "Todos"; color: Estilo.texto; font { family: Estilo.letra; pixelSize: 12; weight: Font.Medium } anchors.verticalCenter: parent.verticalCenter }
                            Simbolo { text: "arrow_forward"; tam: 15; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: zonaTodos; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.elegir("inicio") }
                    }
                }
                Row {
                    spacing: 6
                    Repeater {
                        model: m.miniaturas
                        delegate: Item {
                            id: mini
                            required property string modelData
                            readonly property bool esActual: modelData === m.actual
                            width: (columna.width - 12) / 3; height: 66
                            scale: zonaMini.pressed ? 0.95 : 1
                            Behavior on scale { NumberAnimation { duration: Estilo.t(140); easing.type: Easing.OutCubic } }
                            Rectangle {
                                anchors.fill: parent; radius: 14
                                color: "transparent"; border.width: 2
                                border.color: mini.esActual ? Estilo.acento : zonaMini.containsMouse ? Estilo.texto3 : "transparent"
                                Behavior on border.color { ColorAnimation { duration: Estilo.t(160) } }
                            }
                            ClippingRectangle {
                                anchors { fill: parent; margins: 4 }
                                radius: 10
                                color: Estilo.tarjeta
                                Image {
                                    anchors.fill: parent
                                    source: "file://" + mini.modelData
                                    sourceSize.width: 220
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }
                            Rectangle {
                                visible: mini.esActual
                                anchors { top: parent.top; right: parent.right; margins: 8 }
                                width: 18; height: 18; radius: 9
                                color: Estilo.acento
                                Simbolo { anchors.centerIn: parent; text: "check"; tam: 13; color: Estilo.sobreAcento }
                            }
                            MouseArea { id: zonaMini; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.ponerFondo(mini.modelData) }
                        }
                    }
                }

                // ---- Accesos rapidos ----
                Row {
                    spacing: 6
                    Repeater {
                        model: m.rapidos
                        delegate: Rectangle {
                            id: rapido
                            required property var modelData
                            readonly property bool on: m.encendido(modelData.id)
                            width: (columna.width - 24) / 5; height: 62; radius: 16
                            color: on ? Estilo.activo : zonaRapido.containsMouse ? Estilo.realce : Estilo.tarjeta
                            border.width: on ? 1 : 0; border.color: Estilo.activoBorde
                            Behavior on color { ColorAnimation { duration: Estilo.t(160) } }
                            scale: zonaRapido.pressed ? 0.94 : 1
                            Behavior on scale { NumberAnimation { duration: Estilo.t(140); easing.type: Easing.OutCubic } }
                            Column {
                                anchors.centerIn: parent; spacing: 5
                                Simbolo {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: rapido.modelData.icono; tam: 20
                                    color: rapido.on ? Estilo.iconoActivo : Estilo.texto
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: rapido.modelData.texto
                                    color: rapido.on ? Estilo.enActivo : Estilo.texto2
                                    font { family: Estilo.letra; pixelSize: 10; weight: Font.Medium }
                                }
                            }
                            MouseArea { id: zonaRapido; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.elegir(rapido.modelData.id) }
                        }
                    }
                }

                // ---- Atajos a Ajustes ----
                Column {
                    width: parent.width; spacing: 6
                    Repeater {
                        model: m.secciones
                        delegate: Rectangle {
                            id: fila
                            required property var modelData
                            width: parent.width; height: 54; radius: 14
                            color: zonaFila.containsMouse ? Estilo.realce : Estilo.tarjeta
                            Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
                            scale: zonaFila.pressed ? 0.97 : 1
                            Behavior on scale { NumberAnimation { duration: Estilo.t(140); easing.type: Easing.OutCubic } }
                            Rectangle {
                                id: burbuja
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                width: 34; height: 34; radius: 17
                                color: Estilo.hover
                                Simbolo { anchors.centerIn: parent; text: fila.modelData.icono; tam: 18; color: Estilo.acento }
                            }
                            Column {
                                anchors { left: burbuja.right; leftMargin: 12; right: flecha.left; verticalCenter: parent.verticalCenter }
                                spacing: 1
                                Text { text: fila.modelData.texto; color: Estilo.texto; font { family: Estilo.letra; pixelSize: 13; weight: Font.DemiBold; letterSpacing: -0.08 } }
                                Text { text: fila.modelData.sub; color: Estilo.texto2; font { family: Estilo.letra; pixelSize: 11 } }
                            }
                            Simbolo { id: flecha; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: "chevron_right"; tam: 18; color: Estilo.texto3 }
                            MouseArea { id: zonaFila; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.elegir(fila.modelData.id) }
                        }
                    }
                }

                // ---- Boton grande ----
                Rectangle {
                    width: parent.width; height: 48; radius: 24
                    color: zonaAjustes.containsMouse ? Estilo.aclarar(Estilo.acento) : Estilo.acento
                    Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
                    scale: zonaAjustes.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: Estilo.t(140); easing.type: Easing.OutCubic } }
                    Row {
                        anchors.centerIn: parent; spacing: 8
                        Simbolo { text: "settings"; tam: 19; color: Estilo.sobreAcento; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Ajustes"; color: Estilo.sobreAcento; font { family: Estilo.letra; pixelSize: 14; weight: Font.DemiBold } anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { id: zonaAjustes; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.elegir("ajustes") }
                }
            }
        }
    }

    component Simbolo: Text {
        property int tam: 18
        color: Estilo.texto
        font { family: "Material Symbols Rounded"; pixelSize: tam }
        font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 20 }
        renderType: Text.NativeRendering
    }
}
