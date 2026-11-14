import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Modo captura (Super+Shift+S): reemplaza el de niri, que no deja cambiar colores ni opciones.
// Congela el monitor con grim (una foto con cursor y otra sin el), se dibuja encima y se elige
// zona o pantalla sobre esa foto; captura.py recorta, guarda en ~/Pictures/Screenshots (la isla
// ve llegar el archivo y muestra la miniatura) y copia al portapapeles.
// La zona puede tener forma (rectangulo, circulo, triangulo, corazon o lazo a mano): toda forma es
// una lista de puntos de 0 a 1 dentro de su caja, asi se dibuja, se mueve, se estira y se recorta
// igual. Lo de fuera de la forma queda transparente en la imagen.
// "Ventana" usa la captura de ventana de niri: niri no dice donde esta cada ventana en pantalla,
// asi que se elige de una lista.
PanelWindow {
    id: cap

    property bool abierta: false
    property string modo: "zona"            // zona | ventana | pantalla
    property string forma: "rectangulo"     // rectangulo | circulo | triangulo | corazon | lazo
    property bool menuFormas: false
    property bool cursor: false
    property bool editar: false
    property string salida: ""
    property real escala: 1
    property int vez: 0                      // cambia la url de la foto para que no salga la anterior
    property var ventanas: []
    // Zona elegida (su caja), en pixeles logicos; ancho 0 = nada elegido todavia
    property real sx: 0; property real sy: 0; property real sw: 0; property real sh: 0
    readonly property bool hayZona: sw > 2 && sh > 2
    property var lazo: []                    // puntos del lazo, de 0 a 1 dentro de la caja

    // Puntos de cada forma, de 0 a 1 dentro de su caja
    function puntosDe(f) {
        const n = 72, l = [];
        if (f === "circulo") for (let i = 0; i < n; i++) { const t = i / n * 2 * Math.PI; l.push([0.5 + 0.5 * Math.cos(t), 0.5 + 0.5 * Math.sin(t)]); }
        else if (f === "triangulo") return [[0.5, 0], [1, 1], [0, 1]];
        else if (f === "corazon") {
            // curva clasica del corazon (x de -16 a 16, y de -17 a 12), llevada a la caja
            for (let i = 0; i < n; i++) {
                const t = i / n * 2 * Math.PI;
                const x = 16 * Math.pow(Math.sin(t), 3);
                const y = 13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t);
                l.push([(x + 16) / 32, (12 - y) / 29]);
            }
        }
        else if (f === "lazo") return lazo;
        else return [[0, 0], [1, 0], [1, 1], [0, 1]];
        return l;
    }
    readonly property var puntos: puntosDe(forma)

    // 0 -> 1 al abrir. El velo y la pista siguen "aparecer"; la barra sube con "subida" (con rebote).
    property real aparecer: abierta ? 1 : 0
    Behavior on aparecer { NumberAnimation { duration: Estilo.t(220); easing.type: Easing.OutCubic } }
    property real subida: abierta ? 1 : 0
    Behavior on subida { NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
    // 1 mientras se arrastra la zona: la barra, la pista y el menu se apartan para no estorbar.
    property real oculta: arrastre.pressed ? 1 : 0
    Behavior on oculta { NumberAnimation { duration: Estilo.t(arrastre.pressed ? 140 : 320); easing.type: arrastre.pressed ? Easing.OutQuad : Easing.OutCubic } }

    // Marco: la caja que se ve. Sigue a la zona al arrastrar; al cambiar de modo viaja con rebote
    // (a toda la pantalla en Pantalla, al centro y a nada en Ventana).
    readonly property var destino: modo === "pantalla" ? [0, 0, lienzo.width, lienzo.height]
        : modo === "zona" && hayZona ? [sx, sy, sw, sh]
        : [lienzo.width / 2, lienzo.height / 2, 0, 0]
    property bool viajando: false
    property real mx: destino[0]; property real my: destino[1]
    property real mw: destino[2]; property real mh: destino[3]
    Behavior on mx { enabled: cap.viajando; NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
    Behavior on my { enabled: cap.viajando; NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
    Behavior on mw { enabled: cap.viajando; NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
    Behavior on mh { enabled: cap.viajando; NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
    Timer { id: finViaje; interval: Estilo.t(480); onTriggered: cap.viajando = false }
    function ponerModo(m) {
        if (m === modo) return;
        menuFormas = false;
        viajando = true; finViaje.restart();
        modo = m;
    }
    function ponerForma(f) {
        menuFormas = false;
        if (f === forma) return;
        forma = f;
        if (f === "lazo") { sx = 0; sy = 0; sw = 0; sh = 0; lazo = []; }   // el lazo se dibuja de cero
    }

    readonly property string foto: Estilo.tmp + "/menisco-captura.png"
    readonly property string fotoCursor: Estilo.tmp + "/menisco-captura-cursor.png"

    function abrir(m) {
        if (abierta) return;
        modo = m || "zona";
        menuFormas = false;
        sx = 0; sy = 0; sw = 0; sh = 0; lazo = [];
        monitor.running = true;
    }
    function cerrar() { abierta = false; menuFormas = false; }
    function capturar() {
        if (modo === "ventana") return;
        const entera = modo === "pantalla" || !hayZona;
        const z = entera ? [0, 0, lienzo.width, lienzo.height] : [sx, sy, sw, sh];
        const conForma = !entera && forma !== "rectangulo" && puntos.length > 2;
        cerrar();
        Quickshell.execDetached(["python3", Estilo.carpeta + "/captura.py", "guardar", cursor ? fotoCursor : foto,
                                 z[0], z[1], z[2], z[3], escala, editar ? "1" : "0", conForma ? JSON.stringify(puntos) : ""]);
    }
    function capturarVentana(id) {
        cerrar();
        const ordenes = `niri msg action screenshot-window --id ${id} --show-pointer ${cursor}`
            + (editar ? `; python3 '${Estilo.carpeta}/captura.py' editar-ultima` : "");
        Quickshell.execDetached(["sh", "-c", ordenes]);
    }

    visible: abierta
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "captura"
    WlrLayershell.keyboardFocus: abierta ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // 1) monitor con el foco  2) foto congelada  3) ventanas de ese espacio  4) se muestra
    Process {
        id: monitor
        command: ["niri", "msg", "-j", "focused-output"]
        stdout: StdioCollector {
            onStreamFinished: {
                let o = null;
                try { o = JSON.parse(text); } catch (e) {}
                cap.salida = o?.name ?? Quickshell.screens[0].name;
                cap.escala = o?.logical?.scale ?? 1;
                cap.screen = Quickshell.screens.find(s => s.name === cap.salida) ?? Quickshell.screens[0];
                congelar.running = true;
            }
        }
    }
    Process {
        id: congelar
        command: ["sh", "-c", `grim -o '${cap.salida}' '${cap.foto}' && grim -c -o '${cap.salida}' '${cap.fotoCursor}'`]
        onExited: code => { if (code === 0) leerVentanas.running = true; }
    }
    Process {
        id: leerVentanas
        command: ["python3", Estilo.carpeta + "/captura.py", "ventanas", cap.salida]
        stdout: StdioCollector {
            onStreamFinished: {
                try { cap.ventanas = JSON.parse(text); } catch (e) { cap.ventanas = []; }
                cap.vez++;
                cap.abierta = true;
                foco.forceActiveFocus();
            }
        }
    }

    Item { id: lienzo; anchors.fill: parent }   // el width/height del PanelWindow anclado da 0
    Item {
        id: foco
        focus: true
        Keys.onEscapePressed: cap.menuFormas ? cap.menuFormas = false : cap.cerrar()
        Keys.onReturnPressed: cap.capturar()
        Keys.onEnterPressed: cap.capturar()
        Keys.onSpacePressed: cap.capturar()
    }

    // La pantalla congelada
    Image {
        anchors.fill: parent
        source: cap.vez ? "file://" + (cap.cursor ? cap.fotoCursor : cap.foto) + "?" + cap.vez : ""
        cache: false
        smooth: false
    }

    // Velo con un hueco de la forma elegida (en Pantalla, el hueco es la pantalla entera).
    readonly property var poligono: (modo === "pantalla" ? puntosDe("rectangulo") : puntos).map(p => [mx + p[0] * mw, my + p[1] * mh])
    readonly property string trazo: poligono.length > 2 && mw > 0.5 && mh > 0.5
        ? "M" + poligono.map(p => p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" L") + " Z" : ""
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Qt.rgba(0, 0, 0, 0.5 * cap.aparecer)
            fillRule: ShapePath.OddEvenFill
            strokeWidth: -1
            PathSvg { path: `M0 0 H${lienzo.width} V${lienzo.height} H0 Z ` + cap.trazo }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: cap.modo === "zona" ? Estilo.acento : Qt.alpha(Estilo.acento, 0.7)
            strokeWidth: cap.trazo ? (cap.modo === "pantalla" ? 4 : 1.5) : 0
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: cap.trazo || "M0 0" }
        }
    }

    // Arrastrar: fuera de la zona empieza una nueva, dentro la mueve, en una esquina la estira.
    // Con el lazo, fuera de la zona se dibuja a mano.
    MouseArea {
        id: arrastre
        anchors.fill: parent
        enabled: cap.modo === "zona"
        cursorShape: Qt.CrossCursor
        property string accion: ""
        property real ax: 0; property real ay: 0      // punto fijo (nueva / esquina) o agarre (mover)
        property real ox: 0; property real oy: 0
        property var trazoLazo: []                    // puntos del lazo en pantalla mientras se dibuja
        function dentro(px, py) { return px >= cap.sx && px <= cap.sx + cap.sw && py >= cap.sy && py <= cap.sy + cap.sh; }
        function cerrarLazo() {
            const xs = trazoLazo.map(p => p[0]), ys = trazoLazo.map(p => p[1]);
            const x0 = Math.min(...xs), y0 = Math.min(...ys), w = Math.max(...xs) - x0, h = Math.max(...ys) - y0;
            cap.sx = x0; cap.sy = y0; cap.sw = w; cap.sh = h;
            cap.lazo = trazoLazo.map(p => [w ? (p[0] - x0) / w : 0, h ? (p[1] - y0) / h : 0]);
        }
        onPressed: e => {
            cap.menuFormas = false;
            const m = 12;
            const esquinas = [[cap.sx, cap.sy], [cap.sx + cap.sw, cap.sy], [cap.sx, cap.sy + cap.sh], [cap.sx + cap.sw, cap.sy + cap.sh]];
            const i = cap.hayZona ? esquinas.findIndex(c => Math.abs(e.x - c[0]) < m && Math.abs(e.y - c[1]) < m) : -1;
            if (i >= 0) {
                accion = "estirar"; ax = esquinas[3 - i][0]; ay = esquinas[3 - i][1];
            } else if (cap.hayZona && dentro(e.x, e.y)) {
                accion = "mover"; ax = e.x; ay = e.y; ox = cap.sx; oy = cap.sy;
            } else if (cap.forma === "lazo") {
                accion = "lazo"; trazoLazo = [[e.x, e.y]]; cap.sw = 0; cap.sh = 0; cap.lazo = [];
            } else {
                accion = "nueva"; ax = e.x; ay = e.y; cap.sx = e.x; cap.sy = e.y; cap.sw = 0; cap.sh = 0;
            }
        }
        onPositionChanged: e => {
            if (!pressed) return;
            const px = Math.max(0, Math.min(lienzo.width, e.x)), py = Math.max(0, Math.min(lienzo.height, e.y));
            if (accion === "mover") {
                cap.sx = Math.max(0, Math.min(lienzo.width - cap.sw, ox + e.x - ax));
                cap.sy = Math.max(0, Math.min(lienzo.height - cap.sh, oy + e.y - ay));
            } else if (accion === "lazo") {
                const u = trazoLazo[trazoLazo.length - 1];
                if (Math.hypot(px - u[0], py - u[1]) < 3) return;   // sin puntos de mas
                trazoLazo = trazoLazo.concat([[px, py]]);
                if (trazoLazo.length > 2) cerrarLazo();
            } else {
                cap.sx = Math.min(ax, px); cap.sy = Math.min(ay, py);
                cap.sw = Math.abs(px - ax); cap.sh = Math.abs(py - ay);
            }
        }
        onReleased: if (accion === "lazo" && trazoLazo.length < 3) { cap.sw = 0; cap.sh = 0; cap.lazo = []; }
        onDoubleClicked: cap.capturar()
    }

    // Esquinas y medidas de la caja
    Item {
        visible: cap.modo === "zona" && cap.hayZona
        x: cap.mx; y: cap.my; width: cap.mw; height: cap.mh
        Rectangle {   // la caja punteada solo cuando la forma no es el rectangulo
            visible: cap.forma !== "rectangulo"
            anchors.fill: parent; color: "transparent"; radius: 3
            border.width: 1; border.color: Qt.alpha(Estilo.acento, 0.35)
        }
        Repeater {
            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
            delegate: Rectangle {
                required property var modelData
                width: 10; height: 10; radius: 3; color: Estilo.acento
                x: modelData[0] * parent.width - 5; y: modelData[1] * parent.height - 5
            }
        }
        Rectangle {
            readonly property bool abajo: cap.sy < 34
            x: 0; y: abajo ? parent.height + 8 : -height - 8
            width: medida.implicitWidth + 16; height: 22; radius: 8
            color: Estilo.fondo; border.width: 1; border.color: Estilo.borde
            Texto { id: medida; anchors.centerIn: parent; font.pixelSize: 11; font.features: { "tnum": 1 }
                text: Math.round(cap.sw * cap.escala) + " × " + Math.round(cap.sh * cap.escala) }
        }
    }

    // Pista central cuando todavia no hay zona
    Rectangle {
        visible: cap.modo === "zona" && !cap.hayZona
        anchors.centerIn: parent
        opacity: cap.aparecer * (1 - cap.oculta); scale: 0.9 + 0.1 * cap.subida
        width: pista.implicitWidth + 28; height: 34; radius: 12
        color: Estilo.fondo; border.width: 1; border.color: Estilo.borde
        Texto { id: pista; anchors.centerIn: parent
            text: (cap.forma === "lazo" ? "Dibuje la forma con el ratón" : "Arrastre para elegir una zona") + " · Espacio captura todo · Esc cancela" }
    }

    // Lista de ventanas (modo Ventana): entra creciendo desde el centro, con rebote.
    Rectangle {
        id: cajaVentanas
        property real entra: cap.modo === "ventana" ? 1 : 0
        Behavior on entra { NumberAnimation { duration: Estilo.t(cap.modo === "ventana" ? 420 : 160); easing.type: Easing.BezierSpline; easing.bezierCurve: cap.modo === "ventana" ? Estilo.curvaRebote : Estilo.curvaIos } }
        visible: entra > 0.01
        anchors.centerIn: parent
        opacity: Math.min(1, entra * 1.6) * cap.aparecer; scale: 0.8 + 0.2 * entra
        width: 420; height: listaV.implicitHeight + 24
        radius: 18; color: Estilo.fondo; border.width: 1; border.color: Estilo.borde
        Column {
            id: listaV
            x: 12; y: 12; width: parent.width - 24; spacing: 2
            Texto { text: "Elija una ventana"; color: Estilo.texto2; font.pixelSize: 12; leftPadding: 8; bottomPadding: 6 }
            Texto { visible: !cap.ventanas.length; text: "No hay ventanas en este espacio."; leftPadding: 8; bottomPadding: 6 }
            Repeater {
                model: cap.ventanas
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: listaV.width; height: 40; radius: 10
                    color: zonaV.containsMouse ? Estilo.realce : Estilo.nada
                    Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
                    // cada fila llega un poco despues que la anterior
                    opacity: Math.max(0, Math.min(1, cajaVentanas.entra * 3 - index * 0.35))
                    scale: zonaV.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: Estilo.t(zonaV.pressed ? 80 : 300); easing.type: zonaV.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                    Image {
                        id: iconoV
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; sourceSize: Qt.size(48, 48)
                        source: Quickshell.iconPath(DesktopEntries.applications.values.find(d => d.id.toLowerCase() === modelData.app.toLowerCase() || (d.startupClass || "").toLowerCase() === modelData.app.toLowerCase())?.icon ?? modelData.app, "application-x-executable")
                    }
                    Texto { anchors { left: iconoV.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: modelData.titulo; elide: Text.ElideRight }
                    MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaV; anchors.fill: parent; hoverEnabled: true; onClicked: cap.capturarVentana(modelData.id) }
                }
            }
        }
    }

    // Barra de abajo
    Rectangle {
        id: barra
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 28 }
        opacity: Math.min(1, cap.aparecer * 1.5) * (1 - cap.oculta)
        transform: Translate { y: (1 - cap.subida) * 70 + cap.oculta * 18 }
        width: filaBarra.implicitWidth + 14; height: 46; radius: 16
        color: Estilo.fondo; border.width: 1; border.color: Estilo.borde
        Behavior on width { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
        MouseArea { anchors.fill: parent }    // que un clic en la barra no empiece una zona
        Row {
            id: filaBarra
            anchors.centerIn: parent; spacing: 8
            // Modos: una pastilla que se desliza a la opcion elegida
            Rectangle {
                width: filaModos.implicitWidth + 4; height: 34; radius: 11; color: Estilo.hundido
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    readonly property Item hijo: repModos.count, repModos.itemAt(["zona", "ventana", "pantalla"].indexOf(cap.modo))
                    x: hijo ? hijo.x + 2 : 2; width: hijo ? hijo.width : 0
                    y: 2; height: 30; radius: 9
                    color: Estilo.activo; border.width: 1; border.color: Estilo.activoBorde
                    Behavior on x { NumberAnimation { duration: Estilo.t(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                    Behavior on width { NumberAnimation { duration: Estilo.t(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                }
                Row {
                    id: filaModos
                    x: 2; anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        id: repModos
                        model: [["zona", "screenshot_region", "Zona"], ["ventana", "select_window", "Ventana"], ["pantalla", "desktop_windows", "Pantalla"]]
                        delegate: Item {
                            required property var modelData
                            readonly property bool on: cap.modo === modelData[0]
                            width: filaModo.implicitWidth + 20; height: 30
                            Rectangle {
                                anchors.fill: parent; radius: 15
                                color: !on && zonaModo.containsMouse ? Estilo.realce : Estilo.nada
                                Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                            }
                            Row {
                                id: filaModo
                                anchors.centerIn: parent; spacing: 6
                                scale: zonaModo.pressed ? 0.88 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaModo.pressed ? 80 : 380); easing.type: zonaModo.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.6) } }
                                Simbolo { text: modelData[1]; color: on ? Estilo.iconoActivo : Estilo.texto; anchors.verticalCenter: parent.verticalCenter
                                    Behavior on color { ColorAnimation { duration: Estilo.t(200) } } }
                                Texto { text: modelData[2]; color: on ? Estilo.enActivo : Estilo.texto; anchors.verticalCenter: parent.verticalCenter
                                    Behavior on color { ColorAnimation { duration: Estilo.t(200) } } }
                            }
                            MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaModo; anchors.fill: parent; hoverEnabled: true; onClicked: cap.ponerModo(modelData[0]) }
                        }
                    }
                }
            }
            Rectangle { width: 1; height: 22; color: Estilo.linea; anchors.verticalCenter: parent.verticalCenter }
            Opcion {
                id: botonForma
                visible: cap.modo === "zona"
                icono: ({ rectangulo: "crop_square", circulo: "circle", triangulo: "change_history", corazon: "favorite", lazo: "gesture" })[cap.forma]
                texto: "Forma"; flecha: true; encendida: cap.menuFormas
                onPulsada: cap.menuFormas = !cap.menuFormas
            }
            Opcion { icono: "arrow_selector_tool"; texto: "Cursor"; encendida: cap.cursor; onPulsada: cap.cursor = !cap.cursor }
            Opcion { icono: "edit"; texto: "Editar"; encendida: cap.editar; onPulsada: cap.editar = !cap.editar }
            Rectangle { width: 1; height: 22; color: Estilo.linea; anchors.verticalCenter: parent.verticalCenter }
            Rectangle {
                visible: cap.modo !== "ventana"
                anchors.verticalCenter: parent.verticalCenter
                width: filaCap.implicitWidth + 26; height: 34; radius: 11
                color: zonaCap.containsMouse ? Qt.lighter(Estilo.acento, 1.08) : Estilo.acento
                scale: zonaCap.pressed ? 0.92 : 1
                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaCap.pressed ? 80 : 340); easing.type: zonaCap.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
                Row {
                    id: filaCap
                    anchors.centerIn: parent; spacing: 7
                    Texto { text: "Capturar"; font.weight: Font.DemiBold; color: Estilo.sobreAcento }
                    Texto { text: "Espacio"; font.pixelSize: 11; color: Qt.alpha(Estilo.sobreAcento, 0.55); anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaCap; anchors.fill: parent; hoverEnabled: true; onClicked: cap.capturar() }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 34; height: 34; radius: 11
                color: zonaX.containsMouse ? Estilo.realce : Estilo.nada
                scale: zonaX.pressed ? 0.85 : 1
                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaX.pressed ? 80 : 300); easing.type: zonaX.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
                Simbolo { anchors.centerIn: parent; text: "close"; color: Estilo.texto }
                MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaX; anchors.fill: parent; hoverEnabled: true; onClicked: cap.cerrar() }
            }
        }
    }

    // Menu de formas: brota del boton Forma, encima de la barra
    Rectangle {
        id: menu
        property real entra: cap.menuFormas && cap.modo === "zona" ? 1 : 0
        Behavior on entra { NumberAnimation { duration: Estilo.t(cap.menuFormas ? 380 : 140); easing.type: Easing.BezierSpline; easing.bezierCurve: cap.menuFormas ? Estilo.curvaRebote : Estilo.curvaIos } }
        visible: entra > 0.01
        // centro del boton Forma (mapToItem no se recalcula al moverse la barra; esto si)
        readonly property real base: barra.x + filaBarra.x + botonForma.x + botonForma.width / 2
        x: Math.max(12, Math.min(lienzo.width - width - 12, base - width / 2))
        y: barra.y - height - 10
        width: filaFormas.implicitWidth + 12; height: 64; radius: 16
        color: Estilo.fondo; border.width: 1; border.color: Estilo.borde
        opacity: Math.min(1, entra * 1.5) * (1 - cap.oculta)
        transformOrigin: Item.Bottom
        scale: 0.7 + 0.3 * entra
        MouseArea { anchors.fill: parent }
        Row {
            id: filaFormas
            anchors.centerIn: parent; spacing: 4
            Repeater {
                model: [["rectangulo", "crop_square", "Rectángulo"], ["circulo", "circle", "Círculo"], ["triangulo", "change_history", "Triángulo"],
                        ["corazon", "favorite", "Corazón"], ["lazo", "gesture", "Lazo"]]
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool on: cap.forma === modelData[0]
                    width: 70; height: 52; radius: 11
                    color: on ? Estilo.activo : zonaF.containsMouse ? Estilo.realce : Estilo.nada
                    border.width: 1; border.color: on ? Estilo.activoBorde : "transparent"
                    Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                    // en cascada: cada forma aparece un poco despues que la anterior
                    opacity: Math.max(0, Math.min(1, menu.entra * 2.2 - index * 0.25))
                    scale: zonaF.pressed ? 0.88 : 1
                    Behavior on scale { NumberAnimation { duration: Estilo.t(zonaF.pressed ? 80 : 360); easing.type: zonaF.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.6) } }
                    Column {
                        anchors.centerIn: parent; spacing: 3
                        Simbolo { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[1]; font.pixelSize: 20; color: on ? Estilo.iconoActivo : Estilo.texto }
                        Texto { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[2]; font.pixelSize: 11; color: on ? Estilo.enActivo : Estilo.texto }
                    }
                    MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaF; anchors.fill: parent; hoverEnabled: true; onClicked: cap.ponerForma(modelData[0]) }
                }
            }
        }
    }

    component Opcion: Rectangle {
        id: op
        property string icono
        property string texto
        property bool encendida
        property bool flecha: false
        signal pulsada()
        anchors.verticalCenter: parent.verticalCenter
        width: filaOp.implicitWidth + 18; height: 34; radius: 11
        color: encendida ? Estilo.activo : zonaOp.containsMouse ? Estilo.realce : Estilo.nada
        border.width: 1; border.color: encendida ? Estilo.activoBorde : "transparent"
        Behavior on color { ColorAnimation { duration: Estilo.t(160) } }
        scale: zonaOp.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zonaOp.pressed ? 80 : 380); easing.type: zonaOp.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.6) } }
        Row {
            id: filaOp
            anchors.centerIn: parent; spacing: 6
            Simbolo { text: op.icono; color: op.encendida ? Estilo.iconoActivo : Estilo.texto; anchors.verticalCenter: parent.verticalCenter }
            Texto { text: op.texto; color: op.encendida ? Estilo.enActivo : Estilo.texto; anchors.verticalCenter: parent.verticalCenter }
            Simbolo {
                visible: op.flecha; text: "expand_less"; font.pixelSize: 16; color: Estilo.texto2; anchors.verticalCenter: parent.verticalCenter
                rotation: op.encendida ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Estilo.t(300); easing.type: Easing.OutBack } }
            }
        }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaOp; anchors.fill: parent; hoverEnabled: true; onClicked: op.pulsada() }
    }
    component Texto: Text {
        color: Estilo.texto
        font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
    }
    component Simbolo: Text {
        color: Estilo.texto
        font { family: "Material Symbols Rounded"; pixelSize: 17 }
        font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 20 }
        renderType: Text.NativeRendering
    }
}
