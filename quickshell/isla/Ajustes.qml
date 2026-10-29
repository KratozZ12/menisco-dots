// Tipografia: SF Pro Text con los grosores, tamanos y tracking de la guia de Apple (macOS).
// Movimiento: curva de las hojas de iOS (0.32, 0.72, 0, 1) para entrar, InCubic corto para salir.
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Widgets

// Ventana de ajustes de los dots. Capa flotante centrada (niri no la acomoda).
// Se abre y cierra con Super+. (IPC "ajustes toggle"); Escape la cierra.
PanelWindow {
    id: ventana

    required property var raiz          // ShellRoot: guarda islaVisible

    readonly property string carpetaFondos: Quickshell.env("HOME") + "/Imágenes/Wallpapers"
    readonly property string configNiri: Quickshell.env("HOME") + "/.config/niri/config.kdl"
    readonly property string dirLniri: Quickshell.env("HOME") + "/.config/lniri"
    readonly property var curvaIos: [0.32, 0.72, 0, 1, 1, 1]
    // Rebote suave: pasa un poco de largo (~12 %) y se asienta, sin oscilar.
    readonly property var curvaRebote: [0.3, 1.55, 0.5, 1, 1, 1]

    property bool abierta: false
    property string fondoActual: ""
    property string resolucion: ""      // "5120 × 2596"; la lee "file" sin cargar la imagen entera
    property bool vidrio: false
    property bool noMolestar: false
    property bool cafe: false
    property int esquinas: 12
    property string seccion: "inicio"

    // Sigue mapeada mientras corre la animacion de cierre.
    visible: abierta || panel.opacity > 0.01
    implicitWidth: 800
    implicitHeight: 596
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ajustes"
    WlrLayershell.keyboardFocus: abierta ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function abrir() {
        leerEstado.running = true;
        abierta = true;
    }
    function cerrar() { abierta = false }

    function ejecutar(cmd) { Quickshell.execDetached(cmd) }

    // Estado que vive fuera del shell: fondo actual, vidrio y esquinas.
    Process {
        id: leerEstado
        command: ["sh", "-c",
            "awww query 2>/dev/null | sed -n 's/.*image: //p' | head -1;" +
            "test -s '" + ventana.dirLniri + "/vidrio.kdl' && echo si || echo no;" +
            "grep -oP '^\\s*geometry-corner-radius \\K[0-9]+(?=.*esquinas-ventanas)' '" + ventana.configNiri + "' || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                ventana.fondoActual = l[0] || "";
                ventana.vidrio = l[1] === "si";
                ventana.esquinas = parseInt(l[2]) || 0;
            }
        }
    }

    // El comando se arma aqui: por enlace llegaba con la ruta anterior (vacia la primera vez).
    onFondoActualChanged: if (fondoActual) { resolucion = ""; medir.command = ["file", "-b", fondoActual]; medir.running = true }
    Process {
        id: medir
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/(\d+)\s*x\s*(\d+)(?!.*\d+\s*x\s*\d+)/);
                ventana.resolucion = m ? m[1] + " × " + m[2] : "";
            }
        }
    }

    SystemClock { id: reloj; precision: SystemClock.Minutes }

    // No molestar de Hokum: --watch avisa cada vez que cambia.
    Process {
        running: true
        command: ["hokum", "dnd", "--watch"]
        stdout: SplitParser { onRead: data => ventana.noMolestar = data.trim() === "on" }
    }

    // Entrada escalonada de los bloques de Inicio al abrir la ventana.
    Entrada { objetivo: marcoHero; orden: 0 }
    Entrada { objetivo: cabFondos; orden: 1 }
    Entrada { objetivo: fondos; orden: 2 }
    Entrada { objetivo: cabOpciones; orden: 3 }
    Entrada { objetivo: rapidas; orden: 4 }

    // Modo cafe: mientras este proceso viva, el sistema no se suspende.
    Process {
        running: ventana.cafe
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=Dots", "--why=Modo café", "sleep", "infinity"]
    }

    Rectangle {
        id: panel
        width: 760
        height: 556
        anchors.centerIn: parent
        radius: 16
        color: "#242424"
        border.color: "#3a3a3a"
        border.width: 1
        clip: true

        // Entra creciendo desde 0.9 y subiendo 20 px, con rebote; sale encogiendo un poco.
        opacity: ventana.abierta ? 1 : 0
        scale: ventana.abierta ? 1 : 0.9
        transform: Translate { y: ventana.abierta ? 0 : 20; Behavior on y { NumberAnimation { duration: ventana.abierta ? 560 : 180; easing.type: ventana.abierta ? Easing.BezierSpline : Easing.InCubic; easing.bezierCurve: ventana.curvaRebote } } }
        Behavior on opacity { NumberAnimation { duration: ventana.abierta ? 260 : 160; easing.type: ventana.abierta ? Easing.OutCubic : Easing.InCubic } }
        Behavior on scale { NumberAnimation { duration: ventana.abierta ? 580 : 180; easing.type: ventana.abierta ? Easing.BezierSpline : Easing.InCubic; easing.bezierCurve: ventana.curvaRebote } }

        focus: ventana.abierta
        Keys.onEscapePressed: ventana.cerrar()

        // Barra lateral
        Rectangle {
            id: lateral
            width: 170
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 1 }
            radius: 15
            color: "#1c1c1c"
            Rectangle { width: 16; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } color: parent.color }

            readonly property var secciones: [
                { id: "inicio", texto: "Inicio", icono: "home" },
                { id: "apariencia", texto: "Apariencia", icono: "palette" },
                { id: "pantallas", texto: "Pantallas", icono: "desktop_windows" },
                { id: "isla", texto: "Isla", icono: "pill" },
                { id: "vidrio", texto: "Liquid glass", icono: "water_drop" },
                { id: "atajos", texto: "Atajos", icono: "keyboard" }
            ]
            readonly property int indice: secciones.findIndex(s => s.id === ventana.seccion)

            Text {
                id: tituloLateral
                x: 22; y: 12
                text: "Dots"; color: "#888"
                font { family: "SF Pro Text"; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.06 }
                bottomPadding: 8
            }

            // Una sola pastilla de seleccion que se desliza entre secciones.
            Rectangle {
                x: 12
                y: listaLateral.y + lateral.indice * 36
                width: lateral.width - 24
                height: 34
                radius: 9
                color: "#333"
                Behavior on y { NumberAnimation { duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: ventana.curvaRebote } }
            }

            Column {
                id: listaLateral
                x: 12
                y: tituloLateral.y + tituloLateral.height
                width: lateral.width - 24
                spacing: 2

                Repeater {
                    model: lateral.secciones
                    delegate: Rectangle {
                        id: fila
                        required property var modelData
                        readonly property bool elegida: ventana.seccion === modelData.id
                        // De 0 a 1: rellena el icono de forma progresiva.
                        property real relleno: elegida ? 1 : 0
                        Behavior on relleno { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                        width: parent.width
                        height: 34
                        radius: 9
                        color: !elegida && zona.containsMouse ? "#262626" : "transparent"
                        Behavior on color { ColorAnimation { duration: 140 } }

                        Text {
                            id: iconoLateral
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                            text: modelData.icono
                            color: fila.elegida ? "#fff" : "#bbb"
                            Behavior on color { ColorAnimation { duration: 200 } }
                            font { family: "Material Symbols Rounded"; pixelSize: 19 }
                            font.variableAxes: { "FILL": fila.relleno, "wght": 500, "opsz": 20 }
                            renderType: Text.NativeRendering   // sin esto Qt ignora los ejes de la fuente variable
                            scale: zona.pressed ? 0.85 : 1
                            Behavior on scale { NumberAnimation { duration: zona.pressed ? 80 : 340; easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 2.5 } }
                        }
                        Text {
                            anchors { verticalCenter: parent.verticalCenter; left: iconoLateral.right; leftMargin: 10 }
                            text: modelData.texto
                            color: fila.elegida ? "#fff" : "#bbb"
                            Behavior on color { ColorAnimation { duration: 200 } }
                            font { family: "SF Pro Text"; pixelSize: 13; weight: Font.Normal; letterSpacing: -0.08 }
                        }
                        MouseArea { id: zona; anchors.fill: parent; hoverEnabled: true; onClicked: ventana.seccion = modelData.id }
                    }
                }
            }
        }

        // Contenido
        Item {
            id: contenido
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right; left: lateral.right; margins: 16 }

            Pagina {
                anchors.fill: parent
                activa: ventana.seccion !== "inicio"
                Text {
                    anchors.centerIn: parent
                    text: "Próximamente"
                    color: "#666"
                    font { family: "SF Pro Text"; pixelSize: 13; weight: Font.Normal; letterSpacing: -0.08 }
                }
            }

            Pagina {
                anchors.fill: parent
                activa: ventana.seccion === "inicio"

                Column {
                    anchors.fill: parent
                    spacing: 0

                    // Hero: fondo actual con la isla en miniatura encima
                    Rectangle {
                        id: marcoHero
                        width: parent.width
                        height: 220
                        radius: 12
                        color: "#2e2e2e"
                        clip: true

                        // Debajo queda el fondo anterior; el nuevo aparece encima con un fundido
                        // y un leve acercamiento hacia atras (de 1.06 a 1).
                        property string rutaVieja: ""
                        Redondeada {
                            anchors.fill: parent
                            radio: 12
                            ruta: marcoHero.rutaVieja
                            ancho: 1000
                        }
                        Redondeada {
                            id: hero
                            anchors.fill: parent
                            radio: 12
                            ruta: ventana.fondoActual
                            ancho: 1000
                            opacity: 0
                            onListoChanged: if (listo) llegada.restart()
                        }
                        ParallelAnimation {
                            id: llegada
                            NumberAnimation { target: hero; property: "opacity"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
                            NumberAnimation { target: hero; property: "scale"; from: 1.06; to: 1; duration: 700; easing.type: Easing.BezierSpline; easing.bezierCurve: ventana.curvaIos }
                            onFinished: marcoHero.rutaVieja = ventana.fondoActual
                        }

                        Rectangle {
                            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                            width: 130; height: 18
                            radius: 9
                            color: "#242424"
                            Rectangle { width: parent.width; height: 9; color: parent.color }
                            Text {
                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                                text: Qt.formatTime(reloj.date, "h:mm")
                                color: "#fff"
                                font { family: "SF Pro Text"; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.06 }
                                renderType: Text.NativeRendering
                            }
                        }

                        Column {
                            anchors { left: parent.left; bottom: parent.bottom; margins: 14 }
                            TextoCambiante {
                                text: ventana.fondoActual ? ventana.fondoActual.split("/").pop().replace(/\.[^.]+$/, "") : "Sin fondo"
                                color: "#fff"
                                font { family: "SF Pro Text"; pixelSize: 15; weight: Font.DemiBold; letterSpacing: -0.23 }
                            }
                            TextoCambiante {
                                text: ventana.resolucion ? ventana.resolucion + " · actual" : ""
                                color: "#d0d0d0"
                                font { family: "SF Pro Text"; pixelSize: 11; weight: Font.Normal; letterSpacing: 0.06 }
                            }
                        }
                    }

                    // Selector de fondos
                    Item {
                        id: cabFondos
                        width: parent.width
                        height: 34
                        Text {
                            anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 8 }
                            text: "Fondos"; color: "#888"; font { family: "SF Pro Text"; pixelSize: 13; weight: Font.Bold; letterSpacing: -0.08 }
                        }
                        Text {
                            anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 8 }
                            text: "Abrir carpeta"; color: abrirZona.containsMouse ? "#fff" : "#888"
                            Behavior on color { ColorAnimation { duration: 140 } }
                            font { family: "SF Pro Text"; pixelSize: 12; weight: Font.Normal; letterSpacing: 0 }
                            MouseArea { id: abrirZona; anchors.fill: parent; hoverEnabled: true; onClicked: ventana.ejecutar(["xdg-open", ventana.carpetaFondos]) }
                        }
                    }

                    ListView {
                        id: fondos
                        width: parent.width
                        height: 66
                        orientation: ListView.Horizontal
                        spacing: 8
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        model: FolderListModel {
                            folder: "file://" + ventana.carpetaFondos
                            nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
                            showDirs: false
                        }

                        delegate: Item {
                            id: miniatura
                            required property string filePath
                            width: 104; height: 66
                            readonly property bool actual: filePath === ventana.fondoActual

                            // Anillo de seleccion: aparece cerrandose sobre la miniatura.
                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: "transparent"
                                border.color: "#fff"
                                border.width: 2
                                opacity: miniatura.actual ? 1 : 0
                                scale: miniatura.actual ? 1 : 1.08
                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: ventana.curvaRebote } }
                            }
                            Redondeada {
                                anchors { fill: parent; margins: 4 }
                                radio: 7
                                ruta: miniatura.filePath
                                ancho: 200
                                scale: zonaMini.pressed ? 0.94 : (zonaMini.containsMouse ? 1.04 : 1)
                                Behavior on scale { NumberAnimation { duration: zonaMini.pressed ? 90 : 320; easing.type: zonaMini.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 1.6 } }
                            }
                            MouseArea {
                                id: zonaMini
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    // Lo que se ve ahora queda debajo mientras entra el nuevo,
                                    // aunque se pulsen dos miniaturas seguidas.
                                    llegada.stop();
                                    marcoHero.rutaVieja = ventana.fondoActual;
                                    ventana.fondoActual = miniatura.filePath;
                                    ventana.ejecutar(["awww", "img", miniatura.filePath, "--transition-type", "grow", "--transition-fps", "144"]);
                                }
                            }
                        }

                        footer: Item {
                            width: 112; height: 66
                            Rectangle {
                                anchors { fill: parent; leftMargin: 8; topMargin: 4; bottomMargin: 4; rightMargin: 4 }
                                radius: 8
                                color: masZona.containsMouse ? "#262626" : "#1a1a1a"
                                Behavior on color { ColorAnimation { duration: 140 } }
                                scale: masZona.pressed ? 0.94 : 1
                                Behavior on scale { NumberAnimation { duration: masZona.pressed ? 90 : 320; easing.type: masZona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 1.6 } }
                                Text { anchors.centerIn: parent; text: "+"; color: "#888"; font.pixelSize: 22 }
                                MouseArea { id: masZona; anchors.fill: parent; hoverEnabled: true; onClicked: ventana.ejecutar(["xdg-open", ventana.carpetaFondos]) }
                            }
                        }
                    }

                    Item {
                        id: cabOpciones
                        width: parent.width
                        height: 34
                        Text {
                            anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 8 }
                            text: "Opciones rápidas"; color: "#888"; font { family: "SF Pro Text"; pixelSize: 13; weight: Font.Bold; letterSpacing: -0.08 }
                        }
                    }

                    Grid {
                        id: rapidas
                        width: parent.width
                        columns: 3
                        spacing: 8
                        readonly property real anchoTarjeta: (width - spacing * 2) / 3

                        Tarjeta {
                            icono: "water_drop"; titulo: "Liquid glass"
                            activa: ventana.vidrio
                            detalle: activa ? "Activado" : "Apagado"
                            onPulsada: {
                                ventana.vidrio = !ventana.vidrio;
                                ventana.ejecutar(["sh", "-c", ventana.vidrio
                                    ? "cp '" + ventana.dirLniri + "/vidrio-activo.kdl' '" + ventana.dirLniri + "/vidrio.kdl'"
                                    : ": > '" + ventana.dirLniri + "/vidrio.kdl'"]);
                            }
                        }
                        Tarjeta {
                            icono: "dark_mode"; titulo: "No molestar"
                            activa: ventana.noMolestar
                            detalle: activa ? "Activado" : "Apagado"
                            onPulsada: ventana.ejecutar(["hokum", "dnd", "toggle"])
                        }
                        Tarjeta {
                            icono: "pill"; titulo: "Isla"
                            activa: ventana.raiz.islaVisible
                            detalle: activa ? "Visible" : "Oculta"
                            onPulsada: ventana.raiz.islaVisible = !ventana.raiz.islaVisible
                        }
                        Tarjeta {
                            readonly property var adaptador: Bluetooth.defaultAdapter
                            readonly property var conectado: {
                                const d = Bluetooth.devices.values.find(d => d.connected);
                                return d ? d.name : "";
                            }
                            icono: "bluetooth"; titulo: "Bluetooth"
                            activa: adaptador ? adaptador.enabled : false
                            detalle: !activa ? "Apagado" : (conectado || "Encendido")
                            onPulsada: if (adaptador) adaptador.enabled = !adaptador.enabled
                        }
                        Tarjeta {
                            icono: "rounded_corner"; titulo: "Esquinas"
                            activa: false
                            detalle: ventana.esquinas + " px"
                            onPulsada: {
                                const pasos = [0, 8, 12, 20];
                                ventana.esquinas = pasos[(pasos.indexOf(ventana.esquinas) + 1) % pasos.length];
                                ventana.ejecutar(["sed", "--follow-symlinks", "-i", "-E",
                                    // Solo la linea marcada "esquinas-ventanas": el dock tiene su propio radio.
                                    "/esquinas-ventanas/ s/geometry-corner-radius [0-9]+/geometry-corner-radius " + ventana.esquinas + "/",
                                    ventana.configNiri]);
                            }
                        }
                        Tarjeta {
                            icono: "coffee"; titulo: "Modo café"
                            activa: ventana.cafe
                            detalle: activa ? "Activado" : "Apagado"
                            onPulsada: ventana.cafe = !ventana.cafe
                        }
                    }
                }
            }
        }
    }

    // Pagina: al cambiar de seccion, la nueva entra con fundido y se desliza 16 px
    // desde la derecha; la vieja se va hacia la izquierda.
    component Pagina: Item {
        id: pagina
        property bool activa
        opacity: activa ? 1 : 0
        visible: opacity > 0.01
        enabled: activa
        transform: Translate { id: desp }
        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        onActivaChanged: { deslizar.from = activa ? 16 : 0; deslizar.to = activa ? 0 : -10; deslizar.restart() }
        NumberAnimation { id: deslizar; target: desp; property: "x"; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: ventana.curvaRebote }
    }

    // Entrada escalonada: cada bloque aparece subiendo 10 px, 45 ms despues del anterior,
    // cada vez que se abre la ventana.
    component Entrada: QtObject {
        id: entrada
        property int orden
        required property Item objetivo
        readonly property Translate desplazamiento: Translate { y: 0 }
        Component.onCompleted: objetivo.transform = [desplazamiento]
        property Connections c: Connections {
            target: ventana
            function onAbiertaChanged() {
                if (!ventana.abierta) return;
                anim.restart();
            }
        }
        property SequentialAnimation anim: SequentialAnimation {
            PropertyAction { target: entrada.objetivo; property: "opacity"; value: 0 }
            PropertyAction { target: entrada.desplazamiento; property: "y"; value: 10 }
            PauseAnimation { duration: 60 + entrada.orden * 45 }
            ParallelAnimation {
                NumberAnimation { target: entrada.objetivo; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: entrada.desplazamiento; property: "y"; to: 0; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: ventana.curvaRebote }
            }
        }
    }

    // Texto que, al cambiar, se desvanece y vuelve a aparecer subiendo 4 px.
    component TextoCambiante: Text {
        id: tc
        transform: Translate { id: tcY }
        onTextChanged: cambioTexto.restart()
        SequentialAnimation {
            id: cambioTexto
            PropertyAction { target: tc; property: "opacity"; value: 0 }
            PropertyAction { target: tcY; property: "y"; value: 4 }
            ParallelAnimation {
                NumberAnimation { target: tc; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { target: tcY; property: "y"; to: 0; duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: ventana.curvaRebote }
            }
        }
    }

    // Imagen con esquinas redondeadas.
    component Redondeada: ClippingRectangle {
        id: red
        property string ruta
        property real radio
        property int ancho
        readonly property bool listo: img.status === Image.Ready

        radius: radio
        color: "transparent"
        Image {
            id: img
            anchors.fill: parent
            // Dentro de ClippingRectangle el padre es un contenedor interno: se usa el id.
            source: red.ruta ? "file://" + red.ruta : ""
            sourceSize.width: red.ancho
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    // Tarjeta de opcion rapida: blanca con texto negro cuando esta activa.
    // Al pulsar se hunde (0.95) y rebota al soltar; colores e icono cambian con fundido.
    component Tarjeta: Rectangle {
        id: tarjeta
        property string icono
        property string titulo
        property string detalle
        property bool activa
        signal pulsada()

        property real relleno: activa ? 1 : 0
        Behavior on relleno { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        width: rapidas.anchoTarjeta
        height: 76
        radius: 12
        color: activa ? "#ffffff" : (zonaT.containsMouse ? "#363636" : "#2e2e2e")
        Behavior on color { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }

        scale: zonaT.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: zonaT.pressed ? 90 : 420; easing.type: zonaT.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 2.2 } }

        Column {
            anchors { left: parent.left; top: parent.top; margins: 11 }
            spacing: 3
            Text {
                text: tarjeta.icono
                color: tarjeta.activa ? "#111" : "#ddd"
                Behavior on color { ColorAnimation { duration: 260 } }
                font { family: "Material Symbols Rounded"; pixelSize: 22 }
                // Encendida: relleno, como el centro de control del iPhone. Apagada: contorno.
                font.variableAxes: { "FILL": tarjeta.relleno, "wght": 500, "opsz": 24 }
                renderType: Text.NativeRendering
            }
            Text {
                text: tarjeta.titulo
                color: tarjeta.activa ? "#111" : "#eee"
                Behavior on color { ColorAnimation { duration: 260 } }
                font { family: "SF Pro Text"; pixelSize: 13; weight: Font.Normal; letterSpacing: -0.08 }
            }
            TextoCambiante {
                text: tarjeta.detalle
                color: tarjeta.activa ? "#555" : "#888"
                Behavior on color { ColorAnimation { duration: 260 } }
                font { family: "SF Pro Text"; pixelSize: 11; weight: Font.Normal; letterSpacing: 0.06 }
                elide: Text.ElideRight
                width: rapidas.anchoTarjeta - 22
            }
        }
        MouseArea { id: zonaT; anchors.fill: parent; hoverEnabled: true; onClicked: tarjeta.pulsada() }
    }
}
