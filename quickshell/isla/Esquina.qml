import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

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
                sourceComponent: modelData === "bandeja" ? hueco : modelData === "reproductor" ? reproductor : modelData === "minidock" ? miniDock : boton
                property string clave: modelData
                // no item.visible: hereda el del Loader y, una vez apagado, no vuelve a encenderse
                visible: !item || item.mostrar === undefined || item.mostrar
            }
        }
    }

    // Hueco de la bandeja: la pildora es otra ventana, encima.
    Component {
        id: hueco
        Item {
            id: h
            readonly property bool mostrar: width > 0
            width: Estilo.anchoBandeja; height: 34; visible: mostrar
            // La bandeja se pone sola encima: le dice cuanto hay entre el borde y este hueco.
            Binding { target: Estilo; property: "sepBandeja"; value: esq.derecha ? esq.width - (fila.x + h.parent.x + h.width) : fila.x + h.parent.x }
        }
    }

    // ---- Audio: microfono y volumen ----
    PwObjectTracker { objects: [Pipewire.defaultAudioSource, Pipewire.defaultAudioSink] }
    readonly property bool micMudo: !!Pipewire.defaultAudioSource?.audio?.muted
    readonly property bool volMudo: !!Pipewire.defaultAudioSink?.audio?.muted

    // ---- Mini reproductor: caratula y pausa; con el cursor encima, titulo y controles ----
    readonly property var musica: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property bool pildora: Estilo.valor("reproductorForma") === "pildora"
    readonly property string modoTinte: Estilo.valor("reproductorTinte")
    // Color de la caratula (mismo calculo que la isla). ColorQuantizer solo lee archivos locales.
    readonly property string arte: musica && modoTinte !== "nada" ? musica.trackArtUrl || "" : ""
    property string arteLocal: ""
    onArteChanged: {
        if (!arte) arteLocal = "";
        else if (arte.startsWith("file://")) arteLocal = arte;
        else {
            const destino = Estilo.tmp + "/menisco-arte-" + Qt.md5(arte);
            bajarArte.command = ["sh", "-c", "[ -s \"$2\" ] || curl -sfL --max-time 8 -o \"$2\" \"$1\"", "sh", arte, destino];
            bajarArte.destino = destino;
            bajarArte.running = true;
        }
    }
    Process { id: bajarArte; property string destino; onExited: code => { if (code === 0) esq.arteLocal = "file://" + destino; } }
    ColorQuantizer { id: cuantizador; source: esq.arteLocal; depth: 3; rescaleSize: 64 }
    property color tinte: Estilo.fondo
    readonly property color tinteNuevo: {
        let mejor = null, puntos = -1;
        for (const c of cuantizador.colors) {
            const p = c.hsvSaturation * Math.min(1, c.hsvValue * 2);
            if (p > puntos) { puntos = p; mejor = c; }
        }
        if (!mejor || mejor.hsvSaturation < 0.08) return mejor ? Qt.hsva(0, 0, 0.3, 1) : Estilo.fondo;
        return Qt.hsva(mejor.hsvHue, Math.min(mejor.hsvSaturation, 0.7), 0.45, 1);
    }
    onTinteNuevoChanged: tinte = tinteNuevo
    Behavior on tinte { ColorAnimation { duration: Estilo.t(600) } }

    Component {
        id: reproductor
        Rectangle {
            id: rp
            readonly property bool mostrar: !!esq.musica
            visible: mostrar
            // abre: el ancho, con la curva de los paneles y sin rebote. Titulo y botones entran
            // despues, cada uno con su retraso; al cerrar se van sin esperar.
            readonly property bool encima: zonaRp.containsMouse
            property real abre: encima ? 1 : 0
            Behavior on abre { NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
            property real info: encima ? 1 : 0
            Behavior on info { SequentialAnimation {
                PauseAnimation { duration: rp.encima ? Estilo.t(90) : 0 }
                NumberAnimation { duration: Estilo.t(rp.encima ? 380 : 180); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } } }
            property real ctl1: encima ? 1 : 0
            Behavior on ctl1 { SequentialAnimation {
                PauseAnimation { duration: rp.encima ? Estilo.t(120) : 0 }
                NumberAnimation { duration: Estilo.t(rp.encima ? 320 : 140); easing.type: rp.encima ? Easing.OutBack : Easing.OutCubic; easing.overshoot: Estilo.o(2) } } }
            property real ctl2: encima ? 1 : 0
            Behavior on ctl2 { SequentialAnimation {
                PauseAnimation { duration: rp.encima ? Estilo.t(170) : 0 }
                NumberAnimation { duration: Estilo.t(rp.encima ? 320 : 140); easing.type: rp.encima ? Easing.OutBack : Easing.OutCubic; easing.overshoot: Estilo.o(2) } } }
            readonly property real anchoInfo: Math.min(140, Math.max(tituloRp.implicitWidth, artistaRp.implicitWidth))
            width: 64 + abre * (anchoInfo + 9 + 12 + 56); height: 34
            radius: esq.pildora ? 17 : 12
            color: Estilo.fondo
            clip: true
            MouseArea { id: zonaRp; anchors.fill: parent; hoverEnabled: true }
            // Tinte de la caratula: desde ella hacia el centro, o subiendo desde abajo.
            Rectangle {
                id: tinteRp
                anchors.fill: parent; radius: parent.radius
                visible: esq.modoTinte !== "nada"
                readonly property bool abajo: esq.modoTinte === "abajo"
                gradient: Gradient {
                    orientation: tinteRp.abajo ? Gradient.Vertical : Gradient.Horizontal
                    GradientStop { position: 0; color: tinteRp.abajo ? Qt.alpha(esq.tinte, 0) : esq.tinte }
                    GradientStop { position: tinteRp.abajo ? 0.3 : 0.45; color: Qt.alpha(esq.tinte, tinteRp.abajo ? 0 : 0.35) }
                    GradientStop { position: 1; color: tinteRp.abajo ? esq.tinte : Qt.alpha(esq.tinte, 0) }
                }
            }
            ClippingRectangle {
                x: 5; anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24; radius: esq.pildora ? 12 : 7; color: Estilo.hover
                Text { anchors.centerIn: parent; text: "music_note"; font { family: "Material Symbols Rounded"; pixelSize: 15 } renderType: Text.NativeRendering; color: Estilo.texto2; visible: !arteRp.source.toString() }
                Image { id: arteRp; anchors.fill: parent; source: esq.musica ? esq.musica.trackArtUrl || "" : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(64, 64) }
            }
            Column {
                x: 38 - 8 * (1 - rp.info); anchors.verticalCenter: parent.verticalCenter
                width: rp.anchoInfo
                opacity: rp.info
                visible: opacity > 0.01
                Text { id: tituloRp; width: parent.width; elide: Text.ElideRight; text: esq.musica ? esq.musica.trackTitle : ""; color: Estilo.texto; font { family: Estilo.letra; pixelSize: 12; weight: Font.DemiBold } }
                Text { id: artistaRp; width: parent.width; elide: Text.ElideRight; text: esq.musica ? esq.musica.trackArtist : ""; color: Qt.alpha(Estilo.texto, 0.65); font { family: Estilo.letra; pixelSize: 11 } }
            }
            // Pausa siempre a la vista; al abrirse le deja el borde a "siguiente" y "anterior" sale a su izquierda.
            BotonMini { x: rp.width - 30 - 28 * rp.abre; icono: esq.musica && esq.musica.isPlaying ? "pause" : "play_arrow"; tam: 20; onPulsado: if (esq.musica) esq.musica.togglePlaying() }
            BotonMini { x: rp.width - 30 - 56 * rp.abre; icono: "skip_previous"; opacity: rp.ctl1; scale: 0.6 + 0.4 * rp.ctl1; visible: opacity > 0.01; onPulsado: if (esq.musica) esq.musica.previous() }
            BotonMini { x: rp.width - 30; icono: "skip_next"; opacity: rp.ctl2; scale: 0.6 + 0.4 * rp.ctl2; visible: opacity > 0.01; onPulsado: if (esq.musica) esq.musica.next() }
        }
    }
    component BotonMini: Text {
        id: bm
        property string icono
        property int tam: 18
        signal pulsado()
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: 20
        horizontalAlignment: Text.AlignHCenter
        text: icono
        font { family: "Material Symbols Rounded"; pixelSize: tam }
        font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 24 }
        renderType: Text.NativeRendering   // sin esto el relleno no se aplica y salen huecos
        color: zonaBm.containsMouse ? Estilo.texto : Qt.alpha(Estilo.texto, 0.85)
        MouseArea { id: zonaBm; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bm.pulsado() }
    }

    // ---- Mini dock: las apps que se eligen en Ajustes > Botones (ids de .desktop), con un punto si estan abiertas ----
    readonly property var appsDock: Estilo.valor("miniDockApps") || []
    Component {
        id: miniDock
        Rectangle {
            readonly property bool mostrar: esq.appsDock.length > 0
            visible: mostrar
            width: filaDock.width + 10; height: 34; radius: esq.pildora ? 17 : 12
            color: Estilo.fondo
            Row {
                id: filaDock
                x: 5; anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Repeater {
                    model: esq.appsDock
                    delegate: Item {
                        id: app
                        required property string modelData
                        readonly property var entrada: DesktopEntries.applications.values.find(e => e.id === modelData) ?? null
                        readonly property var ventanas: ToplevelManager.toplevels.values.filter(t => t.appId === modelData
                            || (DesktopEntries.heuristicLookup(t.appId) || {}).id === modelData)
                        width: 26; height: 30
                        IconImage {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 2
                            implicitSize: 22
                            source: Quickshell.iconPath(app.entrada ? app.entrada.icon : app.modelData, "application-x-executable")
                            scale: zonaApp.pressed ? 0.85 : zonaApp.containsMouse ? 1.12 : 1
                            Behavior on scale { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                        }
                        Rectangle {   // abierta
                            visible: app.ventanas.length > 0
                            anchors.horizontalCenter: parent.horizontalCenter; y: 26
                            width: 4; height: 3; radius: 1.5; color: Estilo.texto2
                        }
                        MouseArea {
                            id: zonaApp
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            // ponytail: con varias ventanas de la misma app va a la primera sin enfocar
                            onClicked: {
                                if (app.ventanas.length > 0) (app.ventanas.find(t => !t.activated) ?? app.ventanas[0]).activate();
                                else if (app.entrada) app.entrada.execute();
                            }
                        }
                    }
                }
            }
        }
    }

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
            // Grabando, el boton se estira para mostrar el tiempo.
            readonly property bool grabando: clave === "grabar" && esq.raiz.grabando
            width: grabando ? tiempoGrab.implicitWidth + 32 : 34; height: 34; radius: 12
            Behavior on width { NumberAnimation { duration: Estilo.t(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
            color: encendido ? Estilo.activo : zona.containsMouse ? Estilo.realce : Estilo.fondo
            Behavior on color { ColorAnimation { duration: Estilo.t(220) } }
            scale: zona.pressed ? 0.86 : 1
            Behavior on scale { NumberAnimation { duration: Estilo.t(zona.pressed ? 80 : 420); easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.6) } }
            readonly property color tinta: encendido ? Estilo.iconoActivo
                : (clave === "micro" && esq.micMudo) || clave === "grabar" ? Estilo.peligro : Estilo.texto
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
                visible: b.clave !== "menisco" && b.clave !== "barra" && !b.grabando
                anchors.centerIn: parent
                text: b.clave === "micro" && esq.micMudo ? "mic_off" : b.clave === "volumen" && esq.volMudo ? "volume_off"
                    : (Estilo.botonesCatalogo.find(c => c[0] === b.clave) || ["", "", "help"])[2]
                font { family: "Material Symbols Rounded"; pixelSize: 19 }
                font.variableAxes: { "FILL": b.encendido ? 1 : 0, "wght": 500, "opsz": 24 }
                renderType: Text.NativeRendering
                color: b.tinta
                scale: b.crece
                Behavior on scale { NumberAnimation { duration: Estilo.t(300); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
            }

            Row {   // grabando: punto rojo que late y el tiempo
                visible: b.grabando
                anchors.centerIn: parent
                spacing: 6
                Rectangle {
                    width: 8; height: 8; radius: 4; color: Estilo.peligro; anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on opacity { running: b.grabando; loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine } }
                }
                Text {
                    id: tiempoGrab
                    text: String(Math.floor(esq.raiz.segundosGrabando / 60)).padStart(2, "0") + ":" + String(esq.raiz.segundosGrabando % 60).padStart(2, "0")
                    color: Estilo.texto; font { family: Estilo.letra; pixelSize: 13; weight: Font.DemiBold } font.features: { "tnum": 1 }
                }
            }

            MouseArea {
                id: zona
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: esq.pulsar(b.clave)
                // Volumen: la rueda sube y baja de 5 en 5 (hasta 150 %, como la tecla).
                onWheel: w => {
                    if (b.clave !== "volumen") return;
                    Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", w.angleDelta.y > 0 ? "5%+" : "5%-"]);
                }
            }
        }
    }

    function pulsar(clave) {
        if (clave === "menisco") ajustes.abierta ? ajustes.cerrar() : raiz.abrirAjustes();
        else if (clave === "barra") raiz.barraAbierta = !raiz.barraAbierta;
        else if (clave === "micro") Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
        else if (clave === "volumen") Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
        else if (clave === "color") Quickshell.execDetached(["qs", "-p", Estilo.carpeta, "ipc", "call", "gota_" + (esq.screen ? esq.screen.name : ""), "elegirColor"]);
        else if (clave === "grabar") raiz.alternarGrabacion();
        else if (clave === "captura") raiz.abrirCaptura();
        else if (clave === "nomolestar") Estilo.ponerNoMolestar(!Estilo.noMolestar);
        else if (clave === "juego") raiz.alternarModoJuego();
        else if (clave === "vista") Quickshell.execDetached(["niri", "msg", "action", "toggle-overview"]);
        else if (clave === "flotante") raiz.alternarFlotante();
        else if (clave === "bloquear") raiz.bloquear();
        else if (clave === "fondo") Quickshell.execDetached(Estilo.comandoSiguienteFondo);
    }
}
