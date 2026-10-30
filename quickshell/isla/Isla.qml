// Tipografia: SF Pro (Estilo.letra). Iconos: Material Symbols Rounded.
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

// Isla dinamica, pegada al borde de arriba como una muesca del monitor.
// - Normal: asistente, hora y visualizador (o grabacion / temporizador a la derecha).
// - Avisos: crece unos segundos para avisar (cancion nueva, audifonos, captura,
//   notificacion, temperatura alta, temporizador terminado) y vuelve sola.
// - Expandida: al pasar el cursor (o fija con un clic) crece hacia abajo con el boton del
//   asistente y tres pestanas: Musica (sin el boton, a todo el ancho), Acciones y Rendimiento.
// La ventana tiene tamano fijo y solo la forma de adentro se anima (si la ventana cambiara de
// tamano en cada cuadro, niri la reconfiguraria a saltos). Reserva 42 px arriba.
PanelWindow {
    id: win
    required property var raiz
    readonly property real hombro: 18                 // curva que la funde con el borde de arriba

    anchors.top: true
    implicitWidth: 720
    implicitHeight: 400
    exclusiveZone: 42
    color: "transparent"
    visible: raiz.islaVisible
    WlrLayershell.namespace: "isla"
    // Solo pide el teclado mientras se escribe la nota rapida.
    WlrLayershell.keyboardFocus: expandida && pestana === "acciones" && vistaAcciones === "nota" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    property string vistaAcciones: "botones"          // botones | nota | portapapeles
    mask: Region { x: forma.x0 - win.hombro; y: 0; width: forma.ancho + win.hombro * 2; height: forma.alto }

    // ---------------- Estado ----------------
    property bool fijada: false                      // abierta con clic: no se cierra al salir el cursor
    property bool encima: false
    readonly property bool expandida: fijada || encima
    property string pestana: "acciones"
    property var aviso: null                         // { tipo, ... } mientras se muestra un aviso
    property var colaAvisos: []

    // Con la isla abierta los avisos esperan en fila y salen al cerrarla.
    // Interruptor de Ajustes > Isla > Avisos para cada tipo (temporizador y color siempre salen: los pide usted).
    readonly property var interruptorAviso: ({ musica: "avisoMusica", bt: "avisoBt", captura: "avisoCaptura", notificacion: "avisoNotif", temperatura: "avisoTemp" })
    function avisar(a) {
        const clave = interruptorAviso[a.tipo];
        if (clave && !Estilo.valor(clave)) return;
        colaAvisos = colaAvisos.concat([a]);
        if (!aviso && !expandida) siguienteAviso();
    }
    function siguienteAviso() {
        if (!colaAvisos.length) { aviso = null; return; }
        aviso = colaAvisos[0];
        colaAvisos = colaAvisos.slice(1);
        finAviso.interval = (aviso.ms || 3200) * (({ corta: 0.65, normal: 1, larga: 1.6 })[Estilo.valor("avisoDuracion")] ?? 1);
        finAviso.restart();
    }
    Timer { id: finAviso; onTriggered: win.siguienteAviso() }
    onExpandidaChanged: {
        if (expandida) {
            if (Estilo.valor("islaPestana") !== "ultima") pestana = Estilo.valor("islaPestana");
            // el aviso que se veia vuelve a la fila (menos la musica)
            finAviso.stop();
            if (aviso && aviso.tipo !== "musica") colaAvisos = [aviso].concat(colaAvisos);
            aviso = null;
        } else if (colaAvisos.length) reanudar.restart();
    }
    Timer { id: reanudar; interval: 450; onTriggered: if (!win.expandida && !win.aviso) win.siguienteAviso() }

    // Tamano de la forma segun lo que muestra
    readonly property var tamano: expandida ? [620, 344, 36]
        : !aviso ? [360, 42, 20]
        : ({ musica: [430, 74, 26], bt: [390, 42, 20], color: [330, 42, 20], captura: [410, 94, 28], notificacion: [460, 78, 26],
             temperatura: [390, 42, 20], temporizador: [380, 42, 20] })[aviso.tipo] || [360, 42, 20]

    // ---------------- Forma ----------------
    Item {
        id: forma
        property real ancho: win.tamano[0]
        property real alto: win.tamano[1]
        property real esquina: win.tamano[2]
        Behavior on ancho { NumberAnimation { duration: Estilo.t(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
        Behavior on alto { NumberAnimation { duration: Estilo.t(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
        Behavior on esquina { NumberAnimation { duration: Estilo.t(400) } }
        readonly property real x0: (win.width - ancho) / 2
        anchors.fill: parent

        // "Squircle": curvas Bezier continuas en vez de arcos (k = 0.62, tension de la curva).
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                id: p
                readonly property real r: forma.esquina
                readonly property real x0: forma.x0
                readonly property real x1: forma.x0 + forma.ancho
                readonly property real h: forma.alto
                readonly property real k: 0.62
                readonly property real hom: Math.min(win.hombro, p.r * 0.9)
                fillColor: Estilo.fondo
                strokeWidth: -1
                startX: p.x0 - p.hom; startY: 0
                PathCubic { control1X: p.x0 - p.hom * 0.28; control1Y: 0; control2X: p.x0; control2Y: p.hom * 0.17; x: p.x0; y: p.hom }
                PathLine { x: p.x0; y: p.h - p.r }
                PathCubic { control1X: p.x0; control1Y: p.h - p.r * (1 - p.k); control2X: p.x0 + p.r * (1 - p.k); control2Y: p.h; x: p.x0 + p.r; y: p.h }
                PathLine { x: p.x1 - p.r; y: p.h }
                PathCubic { control1X: p.x1 - p.r * (1 - p.k); control1Y: p.h; control2X: p.x1; control2Y: p.h - p.r * (1 - p.k); x: p.x1; y: p.h - p.r }
                PathLine { x: p.x1; y: p.hom }
                PathCubic { control1X: p.x1; control1Y: p.hom * 0.17; control2X: p.x1 + p.hom * 0.28; control2Y: 0; x: p.x1 + p.hom; y: 0 }
            }
        }

        // Todo el contenido, recortado a la forma
        Item {
            id: dentro
            x: forma.x0; width: forma.ancho; height: forma.alto
            clip: true

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) { salir.stop(); if (Estilo.valor("islaCursor")) entrar.restart(); }
                    else { entrar.stop(); salir.restart(); }
                }
            }
            Timer { id: entrar; interval: ({ corta: 120, normal: 260, larga: 550 })[Estilo.valor("islaEspera")] ?? 260; onTriggered: win.encima = true }
            Timer { id: salir; interval: 420; onTriggered: win.encima = false }
            TapHandler {
                onTapped: {
                    if (win.aviso && win.aviso.tipo === "notificacion") { win.aviso.abrir(); win.siguienteAviso(); return; }
                    if (win.aviso && win.aviso.tipo === "captura") { Quickshell.execDetached(["xdg-open", win.aviso.ruta]); win.siguienteAviso(); return; }
                    win.fijada = !win.fijada;
                    if (!win.fijada) win.encima = false;
                }
            }

            // ---------- Tinte de la caratula (pestana Musica) ----------
            // Degradado del color principal del disco desde la izquierda; se apaga en las otras pestanas.
            Rectangle {
                anchors.fill: parent
                bottomLeftRadius: forma.esquina; bottomRightRadius: forma.esquina
                opacity: win.expandida && win.pestana === "musica" && win.musica && Estilo.valor("musicaTinte") ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Estilo.t(400) } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: win.tinte }
                    GradientStop { position: 0.45; color: Qt.rgba(win.tinte.r, win.tinte.g, win.tinte.b, 0.45) }
                    GradientStop { position: 0.85; color: Qt.rgba(win.tinte.r, win.tinte.g, win.tinte.b, 0) }
                }
            }

            // ---------- Fila de arriba ----------
            Item {
                id: cabecera
                width: parent.width; height: 42
                opacity: win.aviso ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Estilo.t(180) } }

                SystemClock { id: reloj; precision: Estilo.valor("segundos") ? SystemClock.Seconds : SystemClock.Minutes }

                // Asistente: al expandirse se va al boton grande; al abrir el lanzador, a la busqueda.
                Asistente {
                    id: asistenteIsla
                    width: 40; height: 40
                    x: 6; anchors.verticalCenter: parent.verticalCenter
                    emocion: win.raiz.emocion === "normal" && Estilo.valor("reaccionMusica") && Mpris.players.values.some(p => p.isPlaying) ? "feliz" : win.raiz.emocion
                    visible: Estilo.valor("islaAsistente")
                    ritmo: ({ tranquilo: 1.8, normal: 1, inquieto: 0.5 })[Estilo.valor("personalidad")] ?? 1
                    fondoNegro: Estilo.valor("fondoNegro")
                    readonly property bool fuera: (win.raiz.lanzadorAbierto && Estilo.valor("succion")) || win.expandida
                    onFueraChanged: if (fuera) { volver.stop(); irse.restart(); } else { irse.stop(); volver.restart(); }
                    transform: [ Scale { id: succion; origin.x: 20; origin.y: 28 }, Translate { id: caida } ]
                    SequentialAnimation {
                        id: irse
                        ParallelAnimation {
                            NumberAnimation { target: succion; property: "xScale"; to: 0.85; duration: Estilo.t(90); easing.type: Easing.OutCubic }
                            NumberAnimation { target: succion; property: "yScale"; to: 1.35; duration: Estilo.t(90); easing.type: Easing.OutCubic }
                            NumberAnimation { target: caida; property: "y"; to: 3; duration: Estilo.t(90); easing.type: Easing.OutCubic }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: succion; properties: "xScale,yScale"; to: 0; duration: Estilo.t(170); easing.type: Easing.InCubic }
                            NumberAnimation { target: caida; property: "y"; to: 9; duration: Estilo.t(170); easing.type: Easing.InCubic }
                        }
                    }
                    SequentialAnimation {
                        id: volver
                        PropertyAction { target: caida; property: "y"; value: 0 }
                        PauseAnimation { duration: Estilo.t(180) }
                        ParallelAnimation {
                            NumberAnimation { target: succion; property: "xScale"; to: 1; duration: Estilo.t(460); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) }
                            SequentialAnimation {
                                NumberAnimation { target: succion; property: "yScale"; to: 1.2; duration: Estilo.t(200); easing.type: Easing.OutCubic }
                                NumberAnimation { target: succion; property: "yScale"; to: 1; duration: Estilo.t(360); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2.5) }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 1
                    text: Qt.formatTime(reloj.date, (Estilo.valor("reloj12") ? "h:mm" : "H:mm") + (Estilo.valor("segundos") ? ":ss" : "") + (Estilo.valor("reloj12") ? " AP" : ""))
                    color: "#ffffff"
                    font { family: Estilo.letra; weight: Font.DemiBold; pixelSize: 19; letterSpacing: -0.45 }
                    font.features: { "tnum": 1 }
                }

                // Derecha: grabacion > temporizador > visualizador
                Row {
                    visible: win.raiz.grabando
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Rectangle {
                        width: 8; height: 8; radius: 4; color: "#ff453a"; anchors.verticalCenter: parent.verticalCenter
                        SequentialAnimation on opacity { running: win.raiz.grabando; loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine } }
                    }
                    Texto { text: win.mmss(win.raiz.segundosGrabando); font.weight: Font.DemiBold }
                }
                Row {
                    visible: !win.raiz.grabando && win.raiz.temporizadorRestante > 0
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Simbolo { text: "timer"; color: "#ff9f0a"; font.pixelSize: 17; anchors.verticalCenter: parent.verticalCenter }
                    Texto { text: win.mmss(win.raiz.temporizadorRestante); color: "#ff9f0a"; font.weight: Font.DemiBold }
                }
                Visualizador {
                    // En la pestana Musica se esconde: ahi ya se ve lo que suena.
                    visible: opacity > 0.01 && Estilo.valor("islaVisualizador") && !win.raiz.grabando && win.raiz.temporizadorRestante <= 0
                    opacity: win.expandida && win.pestana === "musica" && Estilo.valor("ocultarVisualizador") ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Estilo.t(200) } }
                    anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                }
            }

            // ---------- Avisos ----------
            Item {
                id: capaAviso
                anchors.fill: parent
                opacity: win.aviso ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Estilo.t(220) } }
                property var a: win.aviso || capaAviso.a   // conserva el ultimo mientras se desvanece

                Loader {
                    anchors.fill: parent
                    sourceComponent: capaAviso.a ? ({ musica: avMusica, bt: avBt, captura: avCaptura, notificacion: avNotif, color: avColor,
                                                     temperatura: avTemp, temporizador: avTimer })[capaAviso.a.tipo] ?? null : null
                }
            }

            // ---------- Expandida ----------
            Item {
                id: cuerpo
                x: 18; y: 46
                width: parent.width - 36; height: 286
                opacity: win.expandida && forma.alto > 200 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Estilo.t(win.expandida ? 260 : 120) } }

                // En Musica no sale el boton: la pagina ocupa todo el ancho.
                readonly property bool conBoton: win.pestana !== "musica" && Estilo.valor("botEnPaginas")
                BotonAsistente {
                    id: botonAsistente
                    y: 2
                    height: 276
                    emocion: asistenteIsla.emocion
                    opacity: cuerpo.conBoton ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Estilo.t(cuerpo.conBoton ? 320 : 180) } }
                }
                Connections { target: win; function onExpandidaChanged() { if (win.expandida) botonAsistente.aparecer(); } }

                Column {
                    width: cuerpo.width
                    spacing: 10

                    Selector {
                        x: botonAsistente.width + 18
                        width: 330
                        opciones: [["music_note", "Música", "musica"], ["bolt", "Acciones", "acciones"], ["speed", "Rendimiento", "rendimiento"]]
                        elegida: win.pestana
                        onElegir: c => win.pestana = c
                    }

                    Item {
                        x: cuerpo.conBoton ? botonAsistente.width + 18 : 0
                        width: parent.width - x; height: 240
                        Behavior on x { NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                        PaginaMusica { anchors.fill: parent; activa: win.pestana === "musica" }
                        PaginaAcciones { anchors.fill: parent; activa: win.pestana === "acciones" }
                        PaginaRendimiento { anchors.fill: parent; activa: win.pestana === "rendimiento" }
                    }
                }
            }
        }
    }





    // ---------------- Datos que disparan avisos ----------------
    function mmss(s) { return String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(Math.floor(s % 60)).padStart(2, "0"); }

    // Cancion nueva
    readonly property var reproductor: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    // Reproductor que muestra la pestana Musica: el elegido con las pastillas, si sigue abierto.
    property var elegido: null
    readonly property var musica: elegido && Mpris.players.values.includes(elegido) ? elegido : reproductor
    property string ultimaCancion: ""
    property bool listo: false
    Timer { interval: 2500; running: true; onTriggered: win.listo = true }
    readonly property string cancionActual: reproductor && reproductor.isPlaying ? reproductor.trackTitle + "|" + reproductor.trackArtist : ""
    onCancionActualChanged: {
        if (listo && cancionActual && cancionActual !== ultimaCancion && reproductor.trackTitle)
            avisar({ tipo: "musica", titulo: reproductor.trackTitle, artista: reproductor.trackArtist, arte: reproductor.trackArtUrl });
        if (cancionActual) ultimaCancion = cancionActual;
    }

    // Color de la caratula para el tinte. ColorQuantizer solo lee archivos locales: las
    // caratulas de internet (Spotify) se bajan antes a /tmp.
    readonly property string arte: musica && Estilo.valor("musicaTinte") ? musica.trackArtUrl : ""
    property string arteLocal: ""
    onArteChanged: {
        if (!arte) arteLocal = "";
        else if (arte.startsWith("file://")) arteLocal = arte;
        else {
            const destino = "/tmp/menisco-arte-" + Qt.md5(arte);
            bajarArte.command = ["sh", "-c", "[ -s \"$2\" ] || curl -sfL --max-time 8 -o \"$2\" \"$1\"", "sh", arte, destino];
            bajarArte.destino = destino;
            bajarArte.running = true;
        }
    }
    Process { id: bajarArte; property string destino; onExited: code => { if (code === 0) win.arteLocal = "file://" + destino; } }
    ColorQuantizer { id: cuantizador; source: win.arteLocal; depth: 3; rescaleSize: 64 }
    // El color mas vivo (con algo de brillo), oscurecido para que el texto blanco se lea encima.
    property color tinte: Estilo.fondo
    readonly property color tinteNuevo: {
        let mejor = null, puntos = -1;
        for (const c of cuantizador.colors) {
            const p = c.hsvSaturation * Math.min(1, c.hsvValue * 2);
            if (p > puntos) { puntos = p; mejor = c; }
        }
        // Caratula gris (sin color vivo): un gris un poco mas claro que la isla.
        if (!mejor || mejor.hsvSaturation < 0.08) return mejor ? Qt.hsva(0, 0, 0.3, 1) : Estilo.fondo;
        return Qt.hsva(mejor.hsvHue, Math.min(mejor.hsvSaturation, 0.7), 0.42, 1);
    }
    onTinteNuevoChanged: tinte = tinteNuevo
    Behavior on tinte { ColorAnimation { duration: Estilo.t(600) } }

    // Audifonos y bocinas que se conectan
    Instantiator {
        model: Bluetooth.devices
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectedChanged() {
                if (win.listo && modelData.connected)
                    avisoBt.restart(), win.ultimoBt = modelData;
            }
        }
    }
    property var ultimoBt: null
    // Espera un momento: la bateria llega un poco despues de conectarse.
    Timer { id: avisoBt; interval: 900; onTriggered: if (win.ultimoBt) win.avisar({ tipo: "bt", nombre: win.ultimoBt.name, bateria: win.ultimoBt.batteryAvailable ? Math.round(win.ultimoBt.battery * 100) : -1 }) }

    // Capturas nuevas (niri las guarda en ~/Pictures/Screenshots)
    FolderListModel {
        id: capturas
        folder: "file://" + Quickshell.env("HOME") + "/Pictures/Screenshots"
        nameFilters: ["*.png"]
        sortField: FolderListModel.Time
        showDirs: false
        property int anterior: -1
        // Al llegar un archivo, el modelo pasa por "cargando": se compara cuando vuelve a estar listo.
        function revisar() {
            if (status !== FolderListModel.Ready) return;
            if (anterior >= 0 && count > anterior) win.avisar({ tipo: "captura", ruta: get(0, "filePath"), ms: 4500 });
            anterior = count;
        }
        onCountChanged: revisar()
        onStatusChanged: revisar()
    }

    // Temperatura alta: se revisa cada 5 s; avisa al pasar del limite de Ajustes (80 °C de fabrica),
    // una vez hasta que baje 5 grados.
    property bool calienteAvisado: false
    Process {
        id: temperaturas
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do case $(cat $h/name) in k10temp|coretemp|zenpower) cat $h/temp1_input;; esac; done | head -1; " +
                              "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [c, g] = text.trim().split("\n").map(Number);
                const cpu = (c || 0) / 1000, gpu = g || 0, max = Math.max(cpu, gpu);
                if (max > Estilo.valor("avisoGrados") && !win.calienteAvisado) {
                    win.calienteAvisado = true;
                    win.avisar({ tipo: "temperatura", texto: (gpu >= cpu ? "GPU " : "CPU ") + Math.round(max) + " °C", ms: 4000 });
                } else if (max < Estilo.valor("avisoGrados") - 5) win.calienteAvisado = false;
            }
        }
    }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: temperaturas.running = true }

    // Notificaciones y fin del temporizador los manda la raiz
    Connections {
        target: win.raiz
        function onNotificacion(n) { win.avisar(n); }
        function onTemporizadorTerminado() { win.avisar({ tipo: "temporizador", ms: 5000 }); }
    }

    // ---------------- Avisos (contenido) ----------------
    Component {
        id: avMusica
        Row {
            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
            spacing: 12
            ClippingRectangle {
                width: 46; height: 46; radius: 10; color: "#3a3a3a"; anchors.verticalCenter: parent.verticalCenter
                Image { anchors.fill: parent; source: capaAviso.a.arte || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 46 - 12 - 46 - 12
                Texto { text: "Ahora suena"; color: "#aaa"; font.pixelSize: 11 }
                Texto { width: parent.width; text: capaAviso.a.titulo; font.weight: Font.DemiBold; font.pixelSize: 14; elide: Text.ElideRight }
                Texto { width: parent.width; text: capaAviso.a.artista || ""; color: "#aaa"; font.pixelSize: 12; elide: Text.ElideRight }
            }
            Asistente { width: 46; height: 46; emocion: "feliz"; fondoNegro: Estilo.valor("fondoNegro"); anchors.verticalCenter: parent.verticalCenter }
        }
    }
    Component {
        id: avBt
        Item {
            Simbolo { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "headphones"; font.pixelSize: 20 }
            Texto { anchors.centerIn: parent; text: capaAviso.a.nombre + "  "; font.weight: Font.DemiBold
                Texto { anchors.left: parent.right; anchors.baseline: parent.baseline; text: "conectados"; color: "#aaa" } }
            Row {
                visible: capaAviso.a.bateria >= 0
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                spacing: 3
                Simbolo { text: "battery_5_bar"; color: "#7ee28f"; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
                Texto { text: capaAviso.a.bateria + " %"; color: "#7ee28f"; font.pixelSize: 12 }
            }
        }
    }
    Component {
        id: avCaptura
        Row {
            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
            spacing: 12
            ClippingRectangle {
                width: 104; height: 62; radius: 10; color: "#3a3a3a"; anchors.verticalCenter: parent.verticalCenter
                Image { anchors.fill: parent; source: "file://" + capaAviso.a.ruta; sourceSize.width: 220; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Texto { text: "Captura guardada"; font.weight: Font.DemiBold; font.pixelSize: 14 }
                Texto { text: "Copiada al portapapeles"; color: "#aaa"; font.pixelSize: 12 }
                Row {
                    topPadding: 4; spacing: 6
                    Chip { texto: "Abrir"; blanco: true; onPulsado: { Quickshell.execDetached(["xdg-open", capaAviso.a.ruta]); win.siguienteAviso(); } }
                    Chip { texto: "Carpeta"; onPulsado: { Quickshell.execDetached(["xdg-open", capaAviso.a.ruta.replace(/\/[^/]+$/, "")]); win.siguienteAviso(); } }
                }
            }
        }
    }
    Component {
        id: avNotif
        Row {
            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
            spacing: 12
            ClippingRectangle {
                width: 40; height: 40; radius: 20; color: "#3a3a3a"; anchors.verticalCenter: parent.verticalCenter
                Image { anchors.fill: parent; source: capaAviso.a.imagen || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(80, 80) }
                Simbolo { anchors.centerIn: parent; visible: !capaAviso.a.imagen; text: "notifications"; font.pixelSize: 20; color: "#ddd" }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 40 - 12 - (Estilo.valor("reaccionNotif") ? 34 + 12 : 0)
                Texto { width: parent.width; text: capaAviso.a.app + " · ahora"; color: "#aaa"; font.pixelSize: 11; elide: Text.ElideRight }
                Texto { width: parent.width; text: capaAviso.a.resumen; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Texto { width: parent.width; text: capaAviso.a.cuerpo; color: "#ddd"; font.pixelSize: 12; elide: Text.ElideRight; maximumLineCount: 1; textFormat: Text.PlainText }
            }
            Asistente { visible: Estilo.valor("reaccionNotif"); width: 34; height: 34; emocion: "escucha"; fondoNegro: Estilo.valor("fondoNegro"); anchors.verticalCenter: parent.verticalCenter }
        }
    }
    Component {
        id: avTemp
        Item {
            Asistente { x: 8; width: 34; height: 34; emocion: "confuso"; fondoNegro: Estilo.valor("fondoNegro"); anchors.verticalCenter: parent.verticalCenter }
            Row {
                anchors.centerIn: parent; spacing: 6
                Simbolo { text: "thermostat"; color: "#ff6b6b"; font.pixelSize: 18; anchors.verticalCenter: parent.verticalCenter }
                Texto { text: capaAviso.a.texto; color: "#ff6b6b"; font.weight: Font.DemiBold; font.pixelSize: 15 }
            }
            Texto { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: "Temperatura alta"; color: "#aaa"; font.pixelSize: 12 }
        }
    }
    Component {
        id: avColor
        Item {
            Rectangle { x: 14; width: 22; height: 22; radius: 11; color: capaAviso.a.hex; border.color: "#555"; anchors.verticalCenter: parent.verticalCenter }
            Texto { anchors.centerIn: parent; text: capaAviso.a.hex; font.weight: Font.DemiBold; font.pixelSize: 15; font.features: { "tnum": 1 } }
            Texto { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: "Copiado"; color: "#aaa"; font.pixelSize: 12 }
        }
    }
    Component {
        id: avTimer
        Item {
            Simbolo { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "alarm"; color: "#ff9f0a"; font.pixelSize: 20 }
            Texto { anchors.centerIn: parent; text: "Temporizador terminado"; color: "#ff9f0a"; font.weight: Font.DemiBold; font.pixelSize: 14 }
        }
    }

    // ---------------- Paginas de la isla expandida ----------------
    component PaginaMusica: Item {
        id: pm
        property bool activa
        opacity: activa ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Estilo.t(220) } }
        readonly property var r: win.musica
        // Posicion fresca: cada 250 ms mientras se ve (la letra la necesita al cuarto de segundo).
        Timer { interval: 250; repeat: true; running: pm.visible && pm.r && pm.r.isPlaying; onTriggered: pm.r.positionChanged() }

        // ---- Letra sincronizada: letra.sh prueba LRCLIB y, si no esta, NetEase (publicas, sin cuenta) ----
        property var letra: []                  // [[segundos, linea], ...]
        property string letraDe: ""             // cancion a la que pertenece
        readonly property string cancion: r && r.trackTitle ? r.trackTitle + "|" + (r.trackArtist || "") : ""
        readonly property int lineaActual: {
            let i = -1;
            const pos = r ? r.position + 0.3 : 0;
            for (let k = 0; k < letra.length && letra[k][0] <= pos; k++) i = k;
            return i;
        }
        // Al cambiar los interruptores de letra en Ajustes se vuelve a buscar.
        readonly property string fuentes: Estilo.valor("musicaLetra") + "|" + Estilo.valor("letraNetease")
        onFuentesChanged: { letraDe = ""; letra = []; buscarLetra(); }
        function buscarLetra() {
            if (!activa || !Estilo.valor("musicaLetra") || !cancion || cancion === letraDe || buscador.running) return;
            letraDe = cancion; letra = [];
            buscador.command = [Estilo.carpeta + "/letra.sh", r.trackTitle, r.trackArtist || "", String(Math.round(r.length || 0)), Estilo.valor("letraNetease") ? "1" : "0"];
            buscador.running = true;
        }
        onCancionChanged: buscarLetra()
        onActivaChanged: buscarLetra()
        Process {
            id: buscador
            stdout: StdioCollector {
                onStreamFinished: {
                    let lrc = "";
                    try { lrc = JSON.parse(text).syncedLyrics || ""; } catch (e) {}
                    const out = [];
                    for (const l of lrc.split("\n")) {
                        const m = l.match(/^\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$/);
                        if (!m || !m[3]) continue;
                        // NetEase abre con creditos ("作词 : ...") y marcas de seccion ("[Intro]"): fuera.
                        if (/^\[.*\]$/.test(m[3]) || (out.length === 0 && /\s[:：]\s/.test(m[3]))) continue;
                        out.push([Number(m[1]) * 60 + Number(m[2]), m[3]]);
                    }
                    pm.letra = out;
                }
            }
            // Si la cancion cambio mientras buscaba, se busca la nueva al terminar.
            onExited: if (pm.cancion !== pm.letraDe) pm.buscarLetra()
        }

        // ---- Volumen de la app: sus flujos de PipeWire (por nombre de app o de nodo) ----
        readonly property string clave: r ? (r.identity || "").toLowerCase() : ""
        readonly property var flujos: !clave ? [] : Pipewire.nodes.values.filter(n => n.isStream && n.isSink && n.audio
            && [n.properties["application.name"], n.properties["application.process.binary"], n.name].some(x => (x || "").toLowerCase().includes(pm.clave)))
        PwObjectTracker { objects: pm.flujos.concat(pm.salidas) }

        // ---- Salida de audio: un clic pasa a la siguiente (audifonos, bocinas, HDMI) ----
        readonly property var salidas: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
        readonly property var salida: Pipewire.defaultAudioSink
        function siguienteSalida() {
            if (salidas.length < 2) return;
            Pipewire.preferredDefaultAudioSink = salidas[(salidas.indexOf(salida) + 1) % salidas.length];
        }

        Texto { visible: !pm.r; anchors.centerIn: parent; text: "No suena nada"; color: "#888" }
        Row {
            visible: !!pm.r
            width: parent.width
            spacing: 18

            // Caratula grande: un clic lleva a la ventana de la app que suena.
            ClippingRectangle {
                id: caratula
                width: 150; height: 150; radius: 18; color: "#3a3a3a"
                scale: zonaArte.pressed ? 0.95 : zonaArte.containsMouse ? 1.02 : 1
                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaArte.pressed ? 90 : 420); easing.type: zonaArte.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                Image { anchors.fill: parent; source: pm.r ? pm.r.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(300, 300) }
                MouseArea {
                    id: zonaArte; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["sh", "-c",
                        "id=$(niri msg -j windows | jq -r --arg k \"$1\" '[.[] | select(.app_id | ascii_downcase | contains($k))][0].id // empty'); " +
                        "[ -n \"$id\" ] && niri msg action focus-window --id \"$id\"", "sh", pm.clave])
                }
            }

            Item {
                width: parent.width - caratula.width - parent.spacing
                height: caratula.height
            Column {
                width: parent.width

                // Pastillas para elegir reproductor (solo si suena mas de uno)
                Row {
                    visible: Mpris.players.values.length > 1
                    spacing: 6; bottomPadding: 8
                    Repeater {
                        model: Mpris.players
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool elegido: modelData === pm.r
                            width: tc.implicitWidth + 18; height: 20; radius: 8
                            color: elegido ? "#ffffff" : "#26ffffff"
                            Behavior on color { ColorAnimation { duration: Estilo.t(180) } }
                            Texto { id: tc; anchors.centerIn: parent; text: modelData.identity; font.pixelSize: 10; color: parent.elegido ? "#111" : "#ddd" }
                            MouseArea { anchors.fill: parent; onClicked: win.elegido = modelData }
                        }
                    }
                }
                Texto { width: parent.width; text: pm.r ? (pm.r.trackTitle || pm.r.identity) : ""; font.weight: Font.DemiBold; font.pixelSize: 17; elide: Text.ElideRight }
                Texto { width: parent.width; topPadding: 2; text: pm.r ? [pm.r.trackArtist, pm.r.identity].filter(s => s).join(" · ") : ""; color: "#b3ffffff"; font.pixelSize: 12; elide: Text.ElideRight }
            }
            // Barra, tiempos y controles pegados al borde de abajo de la caratula
            Column {
                width: parent.width
                anchors.bottom: parent.bottom

                // Barra de progreso arrastrable (si la app deja adelantar)
                Item {
                    id: barraTiempo
                    width: parent.width; height: 14
                    readonly property real largo: pm.r && pm.r.length > 0 ? pm.r.length : 0
                    property real arrastre: -1             // fraccion mientras se arrastra
                    readonly property real fraccion: arrastre >= 0 ? arrastre : largo > 0 ? Math.min(1, pm.r.position / largo) : 0
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: "#26ffffff" }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * barraTiempo.fraccion; height: 6; radius: 3; color: "#ffffff" }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.width * barraTiempo.fraccion - width / 2
                        width: 14; height: 14; radius: 7; color: "#ffffff"
                        opacity: zonaBarra.containsMouse || zonaBarra.pressed ? 1 : 0
                        scale: zonaBarra.pressed ? 1.15 : 1
                        Behavior on opacity { NumberAnimation { duration: Estilo.t(160) } }
                        Behavior on scale { NumberAnimation { duration: Estilo.t(220); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                    }
                    MouseArea {
                        id: zonaBarra
                        anchors.fill: parent; anchors.margins: -4
                        enabled: pm.r && pm.r.canSeek && barraTiempo.largo > 0
                        hoverEnabled: true
                        function mover(m) { barraTiempo.arrastre = Math.max(0, Math.min(1, (m.x - 4) / barraTiempo.width)); }
                        onPressed: m => mover(m)
                        onPositionChanged: m => { if (pressed) mover(m); }
                        onReleased: { pm.r.position = barraTiempo.arrastre * barraTiempo.largo; barraTiempo.arrastre = -1; }
                    }
                }
                Item {
                    width: parent.width; height: 16
                    Texto { text: pm.r ? win.mmss(barraTiempo.fraccion * barraTiempo.largo) : ""; color: "#88ffffff"; font.pixelSize: 10 }
                    Texto { anchors.right: parent.right; text: barraTiempo.largo > 0 ? win.mmss(barraTiempo.largo) : ""; color: "#88ffffff"; font.pixelSize: 10 }
                }

                // Controles a la izquierda; volumen de la app y salida a la derecha
                Item {
                    width: parent.width; height: 44
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        BotonRedondo { icono: "shuffle"; tenue: !(pm.r && pm.r.shuffle); anchors.verticalCenter: parent.verticalCenter; onPulsado: if (pm.r && pm.r.shuffleSupported) pm.r.shuffle = !pm.r.shuffle }
                        BotonRedondo { icono: "skip_previous"; grande: true; onPulsado: pm.r.previous() }
                        BotonRedondo { icono: pm.r && pm.r.isPlaying ? "pause" : "play_arrow"; grande: true; blanco: true; onPulsado: pm.r.togglePlaying() }
                        BotonRedondo { icono: "skip_next"; grande: true; onPulsado: pm.r.next() }
                        BotonRedondo { icono: "repeat"; tenue: !(pm.r && pm.r.loopState !== MprisLoopState.None); anchors.verticalCenter: parent.verticalCenter; onPulsado: if (pm.r && pm.r.loopSupported) pm.r.loopState = pm.r.loopState === MprisLoopState.None ? MprisLoopState.Playlist : MprisLoopState.None }
                    }
                    Row {
                        visible: Estilo.valor("musicaAudio")
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        Simbolo { visible: pm.flujos.length > 0; text: "volume_up"; font.pixelSize: 17; color: "#ddd"; anchors.verticalCenter: parent.verticalCenter }
                        Item {
                            id: volApp
                            visible: pm.flujos.length > 0
                            width: 70; height: 18; anchors.verticalCenter: parent.verticalCenter
                            readonly property real valor: pm.flujos.length && pm.flujos[0].audio ? Math.min(1, pm.flujos[0].audio.volume) : 0
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: "#26ffffff" }
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * volApp.valor; height: 4; radius: 2; color: "#ffffff" }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4
                                function poner(m) { const v = Math.max(0, Math.min(1, (m.x - 4) / volApp.width)); for (const n of pm.flujos) if (n.audio) n.audio.volume = v; }
                                onPressed: m => poner(m)
                                onPositionChanged: m => { if (pressed) poner(m); }
                            }
                        }
                        Rectangle {
                            width: 30; height: 30; radius: 15
                            color: zonaSalida.containsMouse ? "#40ffffff" : "#26ffffff"
                            Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                            scale: zonaSalida.pressed ? 0.88 : 1
                            Behavior on scale { NumberAnimation { duration: Estilo.t(zonaSalida.pressed ? 80 : 360); easing.type: zonaSalida.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.2) } }
                            readonly property string nombre: pm.salida ? (pm.salida.name || "") : ""
                            Simbolo {
                                anchors.centerIn: parent; font.pixelSize: 17
                                text: parent.nombre.includes("bluez") ? "headphones" : parent.nombre.includes("hdmi") ? "tv" : "speaker"
                            }
                            MouseArea { id: zonaSalida; anchors.fill: parent; hoverEnabled: true; onClicked: pm.siguienteSalida() }
                        }
                    }
                }
            }
            }
        }

        // ---- Letra abajo, a todo el ancho, al estilo de Apple Music ----
        // Todas las lineas en negrita; la que suena en blanco y las demas apagadas. Al cambiar,
        // cada linea sube a su sitio con su propio retraso (las de abajo llegan un poco despues),
        // asi el bloque se mueve como una ola en vez de saltar entero.
        Item {
            id: zonaLetra
            visible: !!pm.r && pm.letra.length > 0 && Estilo.valor("musicaLetra")
            y: caratula.height + 12
            width: parent.width; height: parent.height - y
            clip: true
            readonly property real paso: 26
            Repeater {
                model: pm.letra.length
                delegate: Texto {
                    id: linea
                    required property int index
                    readonly property int distancia: index - pm.lineaActual
                    // Solo se dibujan las cercanas; las lejanas esperan fuera de la vista.
                    visible: distancia >= -2 && distancia <= 4
                    width: zonaLetra.width
                    elide: Text.ElideRight
                    text: pm.letra[index][1]
                    font.pixelSize: 15; font.weight: Font.Bold
                    y: (distancia + 1) * zonaLetra.paso
                    opacity: distancia === 0 ? 1 : distancia === 1 ? 0.38 : distancia === -1 ? 0.22 : distancia === 2 ? 0.16 : 0
                    scale: distancia === 0 ? 1 : 0.94
                    transformOrigin: Item.Left
                    Behavior on y { NumberAnimation { duration: Estilo.t(620 + Math.max(0, linea.distancia) * 70); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                    Behavior on opacity { NumberAnimation { duration: Estilo.t(420) } }
                    Behavior on scale { NumberAnimation { duration: Estilo.t(520); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(1.4) } }
                }
            }
        }
    }

    component PaginaAcciones: Item {
        id: pa
        property bool activa
        opacity: activa ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Estilo.t(220) } }
        onActivaChanged: if (!activa) win.vistaAcciones = "botones"
        Connections { target: win; function onExpandidaChanged() { if (!win.expandida) win.vistaAcciones = "botones"; } }

        function hacer(cmd) { Quickshell.execDetached(cmd); }
        readonly property bool micMudo: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio ? Pipewire.defaultAudioSource.audio.muted : false
        PwObjectTracker { objects: [Pipewire.defaultAudioSource] }

        // Color: niri deja elegir un punto con el mouse e imprime el color.
        Process {
            id: tomarColor
            command: ["niri", "msg", "pick-color"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const m = text.match(/#[0-9a-fA-F]{6}/);
                    if (!m) return;
                    Quickshell.execDetached(["wl-copy", m[0]]);
                    win.avisar({ tipo: "color", hex: m[0].toUpperCase(), ms: 3000 });
                }
            }
        }
        // Siguiente fondo de la carpeta, en orden.
        Process {
            id: siguienteFondo
            command: ["sh", "-c", "d=\"$HOME/Imágenes/Wallpapers\"; a=$(awww query | sed -n 's/.*image: //p' | head -1); " +
                "ls \"$d\" | grep -iE '\\.(jpe?g|png|webp)$' > /tmp/menisco-fondos.txt; " +
                "n=$(grep -nxF \"$(basename \"$a\")\" /tmp/menisco-fondos.txt | cut -d: -f1); " +
                "s=$(sed -n \"$(( ${n:-0} + 1 ))p\" /tmp/menisco-fondos.txt); [ -z \"$s\" ] && s=$(head -1 /tmp/menisco-fondos.txt); " +
                "awww img \"$d/$s\" --transition-type grow --transition-fps 144"]
        }

        // ---- Botones ----
        // Flow (no Grid): el temporizador ocupa dos celdas y Grid no sabe de celdas dobles.
        Flow {
            id: rejilla
            visible: win.vistaAcciones === "botones"
            width: parent.width
            spacing: 8
            readonly property real celda: (width - 24) / 4

            Accion { icono: "screenshot_region"; titulo: "Captura"; sub: "Elegir zona"; onPulsado: { win.fijada = false; win.encima = false; pa.hacer(["sh", "-c", "sleep 0.5; niri msg action screenshot"]); } }
            Accion { icono: "fullscreen"; titulo: "Pantalla"; sub: "Captura completa"; onPulsado: { win.fijada = false; win.encima = false; pa.hacer(["sh", "-c", "sleep 0.6; niri msg action screenshot-screen"]); } }
            Accion { icono: win.raiz.grabando ? "stop_circle" : "radio_button_checked"; colorIcono: "#ff453a"; titulo: win.raiz.grabando ? "Detener" : "Grabar"
                     sub: win.raiz.grabando ? win.mmss(win.raiz.segundosGrabando) : "Con sonido"; encendida: win.raiz.grabando
                     onPulsado: { if (!win.raiz.grabando) { win.fijada = false; win.encima = false; } win.raiz.alternarGrabacion(); } }
            Accion { icono: "colorize"; titulo: "Color"; sub: "Tomar de pantalla"; onPulsado: { win.fijada = false; win.encima = false; tomarColor.running = true; } }

            // Temporizador: ocupa dos celdas, con botones directos
            Rectangle {
                width: rejilla.celda * 2 + 8; height: 70; radius: 16
                color: zonaTm.containsMouse ? "#333" : "#2b2b2b"
                Behavior on color { ColorAnimation { duration: 200 } }
                MouseArea { id: zonaTm; anchors.fill: parent; hoverEnabled: true }
                Row {
                    x: 10; y: 9; spacing: 8
                    Rectangle { width: 28; height: 28; radius: 9; color: "#3a3a3a"
                        Simbolo { anchors.centerIn: parent; text: win.raiz.temporizadorRestante > 0 ? "timer_off" : "timer"; color: "#ff9f0a"; font.pixelSize: 17 } }
                    Column {
                        Texto { text: "Temporizador"; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Texto { text: win.raiz.temporizadorRestante > 0 ? "Quedan " + win.mmss(win.raiz.temporizadorRestante) : "Un toque para empezar"; color: "#888"; font.pixelSize: 10 }
                    }
                }
                Row {
                    x: 10; anchors { bottom: parent.bottom; bottomMargin: 9 } spacing: 5
                    Repeater {
                        model: win.raiz.temporizadorRestante > 0 ? [["Cancelar", 0]] : [["1 min", 60], ["5 min", 300], ["10 min", 600], ["25 min", 1500]]
                        delegate: Rectangle {
                            required property var modelData
                            width: tTm.implicitWidth + 14; height: 22; radius: 8
                            color: zc2.containsMouse ? "#444" : "#1b1b1b"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            scale: zc2.pressed ? 0.9 : 1
                            Behavior on scale { NumberAnimation { duration: Estilo.t(zc2.pressed ? 80 : 360); easing.type: zc2.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
                            Texto { id: tTm; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: 11; color: "#ddd" }
                            MouseArea { id: zc2; anchors.fill: parent; hoverEnabled: true
                                onClicked: modelData[1] > 0 ? win.raiz.iniciarTemporizador(modelData[1]) : win.raiz.cancelarTemporizador() }
                        }
                    }
                }
            }
            Accion { icono: "content_paste"; titulo: "Portapapeles"; sub: "Últimos copiados"; onPulsado: { leerHistorial.running = true; win.vistaAcciones = "portapapeles"; } }
            Accion { icono: "sports_esports"; titulo: "Modo juego"; sub: encendida ? "Activado" : "Apagado"; encendida: win.raiz.modoJuego; onPulsado: win.raiz.alternarModoJuego() }
            Accion { icono: pa.micMudo ? "mic_off" : "mic"; titulo: "Micrófono"; sub: pa.micMudo ? "Silenciado" : "Activo"; encendida: pa.micMudo
                     onPulsado: if (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio) Pipewire.defaultAudioSource.audio.muted = !pa.micMudo }
            Accion { icono: "lock"; titulo: "Bloquear"; sub: "Ahora"; onPulsado: { win.fijada = false; win.encima = false; pa.hacer(["swaylock"]); } }
            Accion { icono: "wallpaper"; titulo: "Fondo"; sub: "Siguiente"; onPulsado: siguienteFondo.running = true }
            Accion { icono: "edit_note"; titulo: "Nota"; sub: "Rápida"; onPulsado: { win.fijada = true; win.vistaAcciones = "nota"; } }
        }

        // ---- Nota rapida: se guarda sola en nota.txt ----
        Item {
            anchors.fill: parent
            visible: win.vistaAcciones === "nota"
            Volver { id: volverNota; texto: "Nota rápida" }
            FileView {
                id: archivoNota
                path: Estilo.carpeta + "/nota.txt"
                watchChanges: false
                onLoaded: if (!nota.activeFocus) nota.text = text()
            }
            Timer { id: guardarNota; interval: 500; onTriggered: archivoNota.setText(nota.text) }
            Rectangle {
                anchors { top: volverNota.bottom; topMargin: 6; left: parent.left; right: parent.right; bottom: parent.bottom }
                radius: 14; color: "#1b1b1b"
                Flickable {
                    anchors { fill: parent; margins: 12 }
                    contentHeight: nota.paintedHeight
                    clip: true
                    TextEdit {
                        id: nota
                        width: parent.width
                        wrapMode: TextEdit.Wrap
                        color: "#ffffff"; selectionColor: "#555"
                        font { family: Estilo.letra; pixelSize: 13 }
                        focus: parent.parent.parent.visible
                        onTextChanged: if (activeFocus) guardarNota.restart()
                        Keys.onEscapePressed: win.vistaAcciones = "botones"
                    }
                }
                Texto { visible: !nota.text; x: 12; y: 12; text: "Escriba aquí… se guarda solo."; color: "#666" }
            }
        }

        // ---- Portapapeles: los ultimos 6 de cliphist; un clic los vuelve a copiar ----
        property var historial: []
        Process {
            id: leerHistorial
            command: ["sh", "-c", "cliphist list | head -6"]
            stdout: StdioCollector {
                onStreamFinished: pa.historial = text.trim().split("\n").filter(l => l).map(l => {
                    const i = l.indexOf("\t");
                    const t = l.slice(i + 1);
                    return { id: l.slice(0, i), texto: /^\[\[ binary data/.test(t) ? "Imagen" : t, imagen: /^\[\[ binary data/.test(t) };
                })
            }
        }
        Item {
            anchors.fill: parent
            visible: win.vistaAcciones === "portapapeles"
            Volver { id: volverPp; texto: "Portapapeles" }
            Column {
                anchors { top: volverPp.bottom; topMargin: 4; left: parent.left; right: parent.right }
                spacing: 2
                Texto { visible: !pa.historial.length; text: "Todavía no hay nada copiado."; color: "#888"; leftPadding: 4 }
                Repeater {
                    model: pa.historial
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width; height: 32; radius: 10
                        color: zpp.containsMouse ? "#2e2e2e" : "#002e2e2e"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Simbolo { x: 8; anchors.verticalCenter: parent.verticalCenter; text: modelData.imagen ? "image" : "content_paste"; font.pixelSize: 16; color: "#aaa" }
                        Texto { x: 32; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter; text: modelData.texto; elide: Text.ElideRight; font.pixelSize: 12; textFormat: Text.PlainText }
                        MouseArea { id: zpp; anchors.fill: parent; hoverEnabled: true
                            onClicked: { pa.hacer(["sh", "-c", "cliphist decode " + modelData.id + " | wl-copy"]); win.vistaAcciones = "botones"; } }
                    }
                }
            }
        }
    }

    component Accion: Rectangle {
        id: acc
        property string icono
        property string titulo
        property string sub
        property color colorIcono: "#ffffff"
        property bool encendida: false
        signal pulsado()
        width: rejilla.celda; height: 70; radius: 16
        color: encendida ? "#ffffff" : (za.containsMouse ? "#333" : "#2b2b2b")
        Behavior on color { ColorAnimation { duration: Estilo.t(220) } }
        transform: Translate { y: za.containsMouse && !za.pressed ? -2 : 0; Behavior on y { NumberAnimation { duration: Estilo.t(360); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } } }
        scale: za.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(za.pressed ? 80 : 400); easing.type: za.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
        Rectangle {
            x: 10; y: 9; width: 28; height: 28; radius: 9
            color: acc.encendida ? "#e6e6e6" : "#3a3a3a"
            Simbolo { anchors.centerIn: parent; text: acc.icono; font.pixelSize: 17; color: acc.encendida ? "#111" : acc.colorIcono }
        }
        Column {
            x: 10; anchors { bottom: parent.bottom; bottomMargin: 8 }
            width: parent.width - 16
            Texto { text: acc.titulo; font.pixelSize: 12; font.weight: Font.DemiBold; color: acc.encendida ? "#111" : "#fff"; width: parent.width; elide: Text.ElideRight }
            Texto { text: acc.sub; font.pixelSize: 10; color: acc.encendida ? "#555" : "#888"; width: parent.width; elide: Text.ElideRight }
        }
        MouseArea { id: za; anchors.fill: parent; hoverEnabled: true; onClicked: acc.pulsado() }
    }

    component Volver: Item {
        property string texto
        width: parent.width; height: 32
        BotonRedondo { id: atr; icono: "chevron_left"; anchors.verticalCenter: parent.verticalCenter; onPulsado: win.vistaAcciones = "botones" }
        Texto { anchors { left: atr.right; leftMargin: 6; verticalCenter: parent.verticalCenter } text: parent.texto; font.pixelSize: 15; font.weight: Font.DemiBold }
    }

    component PaginaRendimiento: Item {
        id: pr
        property bool activa
        opacity: activa ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Estilo.t(220) } }

        property var dato: ({})
        property var histC: []; property var histG: []; property var histT: []
        readonly property real total: (dato.cpuW || 0) + (dato.gpuW || 0)
        function sumar(h, v) { const r = h.concat([v || 0]); return r.length > 24 ? r.slice(r.length - 24) : r; }

        // Solo mide mientras la pagina se ve
        Process {
            running: pr.activa && win.expandida
            command: ["python3", Estilo.carpeta + "/rendimiento.py", "1.2"]
            stdout: SplitParser {
                onRead: l => {
                    try { pr.dato = JSON.parse(l); } catch (e) { return; }
                    pr.histC = pr.sumar(pr.histC, pr.dato.cpuW); pr.histG = pr.sumar(pr.histG, pr.dato.gpuW);
                    pr.histT = pr.sumar(pr.histT, Math.max(pr.dato.cpuTemp || 0, pr.dato.gpuTemp || 0));
                }
            }
        }
        property string perfil: "balanced"
        Process { id: leerPerfil; running: pr.activa && win.expandida; command: ["powerprofilesctl", "get"]; stdout: StdioCollector { onStreamFinished: pr.perfil = text.trim() } }

        Column {
            width: parent.width
            spacing: 10
            Row {
                width: parent.width; spacing: 12
                Medidor { valor: pr.total; maximo: 250; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    spacing: 7; anchors.verticalCenter: parent.verticalCenter
                    readonly property real ancho: (pr.width - 96 - 12 - 14) / 3
                    Tarjeta { width: parent.ancho; icono: "memory"; titulo: "CPU"; valor: pr.dato.cpuW != null ? Math.round(pr.dato.cpuW) : "–"; unidad: "W"; hist: pr.histC }
                    Tarjeta { width: parent.ancho; icono: "developer_board"; titulo: "GPU"; valor: pr.dato.gpuW != null ? Math.round(pr.dato.gpuW) : "–"; unidad: "W"; hist: pr.histG }
                    Tarjeta { width: parent.ancho; icono: "thermostat"; titulo: "Temp."; valor: pr.dato.cpuTemp != null ? Math.round(Math.max(pr.dato.cpuTemp, pr.dato.gpuTemp || 0)) : "–"; unidad: "°C"; hist: pr.histT }
                }
            }
            Selector {
                width: parent.width
                opciones: [["eco", "Ahorro", "power-saver"], ["balance", "Equilibrado", "balanced"], ["bolt", "Máximo", "performance"]]
                colores: ({ "power-saver": "#30d158", "balanced": "#ffffff", "performance": "#ff9f0a" })
                elegida: pr.perfil
                onElegir: c => { pr.perfil = c; Quickshell.execDetached(["powerprofilesctl", "set", c]); }
            }
            Column {
                width: parent.width
                spacing: 1
                Repeater {
                    model: pr.dato.top || []
                    delegate: Rectangle {
                        required property var modelData
                        readonly property var entrada: DesktopEntries.heuristicLookup(modelData[0])
                        readonly property string nombre: modelData[0] === "qs" ? "Menisco" : entrada ? entrada.name : modelData[0].charAt(0).toUpperCase() + modelData[0].slice(1)
                        width: parent.width; height: 30; radius: 10
                        color: zonaP.containsMouse ? "#2b2b2b" : "#002b2b2b"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Image {
                            id: icoP
                            x: 6; width: 20; height: 20; anchors.verticalCenter: parent.verticalCenter
                            sourceSize: Qt.size(48, 48)
                            source: Quickshell.iconPath(modelData[0] === "qs" ? "preferences-desktop" : entrada ? entrada.icon : modelData[0], "application-x-executable")
                        }
                        Texto { x: 34; width: 76; anchors.verticalCenter: parent.verticalCenter; text: nombre; font.pixelSize: 12; elide: Text.ElideRight }
                        Rectangle {
                            x: 116; width: parent.width - 116 - 52; height: 6; radius: 3; color: "#1b1b1b"; anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                height: 6; radius: 3
                                width: parent.width * Math.min(1, modelData[1] / 25)
                                Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                                gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#9a9a9a" } GradientStop { position: 1; color: "#ffffff" } }
                            }
                        }
                        Texto { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: modelData[1].toFixed(1) + " %"; color: "#aaa"; font.pixelSize: 12; font.features: { "tnum": 1 } }
                        MouseArea { id: zonaP; anchors.fill: parent; hoverEnabled: true }
                    }
                }
            }
        }
    }

    // ---------------- Piezas ----------------
    component Texto: Text {
        color: "#ffffff"
        font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
    }
    component Simbolo: Text {
        font { family: "Material Symbols Rounded"; pixelSize: 18 }
        font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 24 }
        renderType: Text.NativeRendering
        color: "#ffffff"
    }
    component Chip: Rectangle {
        id: chip
        property string texto
        property bool blanco: false
        signal pulsado()
        width: tc.implicitWidth + 18; height: 22; radius: 8
        color: blanco ? "#ffffff" : (zc.containsMouse ? "#444" : "#3a3a3a")
        Behavior on color { ColorAnimation { duration: 140 } }
        Texto { id: tc; anchors.centerIn: parent; text: chip.texto; font.pixelSize: 11; color: chip.blanco ? "#111" : "#fff" }
        MouseArea { id: zc; anchors.fill: parent; hoverEnabled: true; onClicked: chip.pulsado() }
    }
    component BotonRedondo: Rectangle {
        id: br
        property string icono
        property bool grande: false
        property bool blanco: false
        property bool tenue: false
        signal pulsado()
        width: grande ? 44 : 32; height: width; radius: width / 2
        color: blanco ? "#ffffff" : (zb.containsMouse ? "#3a3a3a" : "#003a3a3a")
        Behavior on color { ColorAnimation { duration: 140 } }
        scale: zb.pressed ? 0.86 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zb.pressed ? 80 : 400); easing.type: zb.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
        Simbolo { anchors.centerIn: parent; text: br.icono; font.pixelSize: br.grande ? 26 : 20; color: br.blanco ? "#111" : br.tenue ? "#777" : "#fff" }
        MouseArea { id: zb; anchors.fill: parent; hoverEnabled: true; onClicked: br.pulsado() }
    }
    // Selector con pastilla que se desliza (pestanas y perfil de energia)
    component Selector: Rectangle {
        id: sel
        property var opciones: []          // [[icono, texto, clave], ...]
        property var colores: ({})
        property string elegida
        signal elegir(string clave)
        height: 32; radius: 13; color: "#1b1b1b"
        readonly property int indice: Math.max(0, opciones.findIndex(o => o[2] === elegida))
        Rectangle {
            y: 3; height: 26; radius: 10
            width: (sel.width - 6) / Math.max(1, sel.opciones.length)
            x: 3 + width * sel.indice
            color: sel.colores[sel.elegida] || "#ffffff"
            Behavior on x { NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
            Behavior on color { ColorAnimation { duration: Estilo.t(300) } }
        }
        Row {
            x: 3; y: 3
            Repeater {
                model: sel.opciones
                delegate: Item {
                    required property var modelData
                    readonly property bool on: modelData[2] === sel.elegida
                    width: (sel.width - 6) / sel.opciones.length; height: 26
                    Row {
                        anchors.centerIn: parent; spacing: 5
                        Simbolo { text: modelData[0]; font.pixelSize: 15; color: on ? "#111" : (zs.containsMouse ? "#ddd" : "#999"); anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 200 } } }
                        Texto { text: modelData[1]; font.pixelSize: 12; color: on ? "#111" : (zs.containsMouse ? "#ddd" : "#999"); anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 200 } } }
                    }
                    MouseArea { id: zs; anchors.fill: parent; hoverEnabled: true; onClicked: sel.elegir(modelData[2]) }
                }
            }
        }
    }
    // Medidor de consumo con marcas, como un velocimetro
    component Medidor: Item {
        id: med
        property real valor
        property real maximo: 250
        property real visto: valor
        Behavior on visto { NumberAnimation { duration: 1000; easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
        width: 96; height: 96
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {   // pista
                strokeColor: "#1b1b1b"; strokeWidth: 8; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 48; centerY: 48; radiusX: 35; radiusY: 35; startAngle: 135; sweepAngle: 270 }
            }
            ShapePath {   // valor
                strokeWidth: 8; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                strokeColor: "#ffffff"
                PathAngleArc { centerX: 48; centerY: 48; radiusX: 35; radiusY: 35; startAngle: 135; sweepAngle: Math.max(1, 270 * Math.min(1, med.visto / med.maximo)) }
            }
        }
        Repeater {   // marcas
            model: 21
            delegate: Rectangle {
                required property int index
                readonly property bool mayor: index % 5 === 0
                readonly property real ang: (135 + index * 13.5) * Math.PI / 180
                width: mayor ? 1.6 : 1; height: mayor ? 5 : 3; radius: 1
                color: mayor ? "#777" : "#444"
                x: 48 + Math.cos(ang) * 44 - width / 2; y: 48 + Math.sin(ang) * 44 - height / 2
                rotation: (135 + index * 13.5) + 90
            }
        }
        Column {
            anchors.centerIn: parent
            Texto { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(med.visto); font.pixelSize: 24; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
            Texto { anchors.horizontalCenter: parent.horizontalCenter; text: "vatios"; color: "#888"; font.pixelSize: 10 }
        }
    }
    // Tarjeta con mini grafica en vivo
    component Tarjeta: Rectangle {
        id: tar
        property string icono
        property string titulo
        property var valor
        property string unidad
        property var hist: []
        height: 76; radius: 15
        color: zt.containsMouse ? "#333" : "#2b2b2b"
        Behavior on color { ColorAnimation { duration: 200 } }
        transform: Translate { y: zt.containsMouse ? -2 : 0; Behavior on y { NumberAnimation { duration: Estilo.t(380); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } } }
        Row { x: 10; y: 8; spacing: 4
            Simbolo { text: tar.icono; font.pixelSize: 13; color: "#999"; anchors.verticalCenter: parent.verticalCenter }
            Texto { text: tar.titulo; color: "#999"; font.pixelSize: 11 } }
        Row { x: 10; y: 24; spacing: 3
            Texto { text: tar.valor; font.pixelSize: 17; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
            Texto { text: tar.unidad; color: "#777"; font.pixelSize: 10; anchors.baseline: parent.children[0].baseline } }
        Canvas {
            id: graf
            x: 10; y: 50; width: parent.width - 20; height: 20
            renderStrategy: Canvas.Cooperative
            onPaint: {
                const g = getContext("2d"), h = tar.hist; g.reset();
                if (h.length < 2) return;
                const mn = Math.min(...h) - 2, mx = Math.max(...h) + 2, w = width;
                const pt = (v, i) => [i / (h.length - 1) * w, 18 - (v - mn) / (mx - mn) * 15];
                g.beginPath(); h.forEach((v, i) => { const [a, b] = pt(v, i); i ? g.lineTo(a, b) : g.moveTo(a, b); });
                g.strokeStyle = "#d8d8d8"; g.lineWidth = 1.4; g.lineJoin = "round"; g.stroke();
                g.lineTo(w, 20); g.lineTo(0, 20); g.closePath();
                const gr = g.createLinearGradient(0, 0, 0, 20); gr.addColorStop(0, "rgba(255,255,255,0.18)"); gr.addColorStop(1, "rgba(255,255,255,0)");
                g.fillStyle = gr; g.fill();
                const [lx, ly] = pt(h[h.length - 1], h.length - 1);
                g.fillStyle = "#ffffff"; g.beginPath(); g.arc(lx - 1.5, ly, 2, 0, 7); g.fill();
            }
        }
        onHistChanged: graf.requestPaint()
        MouseArea { id: zt; anchors.fill: parent; hoverEnabled: true }
    }
}
