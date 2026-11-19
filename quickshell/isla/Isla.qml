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
import Quickshell.Services.UPower

// Isla dinamica, pegada al borde de arriba como una muesca del monitor.
// - Normal: asistente, hora y visualizador (o grabacion / temporizador a la derecha).
// - Avisos: crece unos segundos para avisar (cancion nueva, audifonos, captura,
//   temperatura alta, bateria baja, salida de audio, temporizador terminado, color copiado)
//   y vuelve sola. No molestar los calla (menos temporizador y color, que los pide usted). Las notificaciones
//   del sistema no: esas las muestra Hokum.
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
    exclusiveZone: 42 + Estilo.grosorMarco
    color: "transparent"
    visible: raiz.islaVisible
    WlrLayershell.namespace: "isla"
    Gelatina { objetivo: win.contentItem; origenY: 0 }   // se va con la vista general
    // Solo pide el teclado mientras se escribe la nota rapida o se habla con la Gota.
    WlrLayershell.keyboardFocus: expandida && (conGota || (pestana === "acciones" && vistaAcciones === "nota")) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    property bool conGota: false                      // conversacion con la Gota en vez de las pestanas
    property string vistaAcciones: "botones"          // botones | nota | portapapeles
    // Con marco, la forma baja lo que mide el borde pero la ventana sigue pegada arriba: el cursor
    // empujado contra el borde de la pantalla tambien la abre.
    // En la vista general esta escondida: sin mascara no se abre al pasar por arriba.
    mask: Region { x: forma.x0 - win.hombro; y: 0; width: Estilo.vistaGeneral ? 0 : forma.ancho + win.hombro * 2; height: forma.alto + Estilo.grosorMarco }

    // ---------------- Estado ----------------
    property bool fijada: false                      // abierta con clic: no se cierra al salir el cursor
    property bool encima: false
    readonly property bool expandida: fijada || encima
    onFijadaChanged: raiz.islasFijadas += fijada ? 1 : -1
    Connections { target: win.raiz; function onClicFuera() { win.conGota = false; win.fijada = false; win.encima = false; } }
    property string pestana: "acciones"
    property var aviso: null                         // { tipo, ... } mientras se muestra un aviso
    property var colaAvisos: []
    property bool calendario: false                  // clic en la hora con la isla abierta

    // Con la isla abierta los avisos esperan en fila y salen al cerrarla.
    // Interruptor de Ajustes > Notificaciones para cada tipo (temporizador y color siempre salen: los pide usted).
    readonly property var interruptorAviso: ({ musica: "avisoMusica", bt: "avisoBt", captura: "avisoCaptura", temperatura: "avisoTemp",
                                               bateria: "avisoBateria", salida: "avisoSalida", fallo: "avisoFallos" })
    function avisar(a) {
        const clave = interruptorAviso[a.tipo];
        if (clave && (!Estilo.valor(clave) || Estilo.noMolestar)) return;
        // Solo cuenta la cancion de ahora: la nueva reemplaza a la que esperaba o a la que se ve.
        if (a.tipo === "musica") {
            colaAvisos = colaAvisos.filter(x => x.tipo !== "musica");
            if (aviso?.tipo === "musica") { aviso = a; finAviso.restart(); return; }
        }
        colaAvisos = colaAvisos.concat([a]);
        // Mientras la isla termina de cerrarse (reanudar) espera: reanudar lo saca al acabar.
        if (!aviso && !expandida && !reanudar.running) siguienteAviso();
    }
    function siguienteAviso() {
        if (!colaAvisos.length) { aviso = null; return; }
        aviso = colaAvisos[0];
        colaAvisos = colaAvisos.slice(1);
        finAviso.interval = (aviso.ms || 3200) * (({ corta: 0.65, normal: 1, larga: 1.6 })[Estilo.valor("avisoDuracion")] ?? 1);
        finAviso.restart();
    }
    Timer { id: finAviso; onTriggered: win.siguienteAviso() }
    // 0 = fila de arriba, 1 = aviso. Una sola animacion: la primera mitad apaga uno y la segunda
    // enciende el otro, asi nunca se ven los dos textos encimados.
    property real fundidoAviso: aviso ? 1 : 0
    Behavior on fundidoAviso { NumberAnimation { duration: Estilo.t(320) } }
    onExpandidaChanged: {
        if (expandida) {
            if (Estilo.valor("islaPestana") !== "ultima") pestana = Estilo.valor("islaPestana");
            // el aviso que se veia vuelve a la fila (menos la musica)
            finAviso.stop();
            if (aviso && aviso.tipo !== "musica") colaAvisos = [aviso].concat(colaAvisos);
            aviso = null;
        } else {
            // Si no esta trabajando ni esperando un "Hazlo", al cerrar se vuelve a las pestanas.
            if (!Cerebro.ocupada && Cerebro.estado !== "plan") conGota = false;
            calendario = false;
            reanudar.restart();   // siempre: tambien frena los avisos que lleguen durante el cierre
        }
    }
    Timer { id: reanudar; interval: 450; onTriggered: if (!win.expandida && !win.aviso) win.siguienteAviso() }

    // Tamano de la forma segun lo que muestra
    readonly property var tamano: expandida ? [620, 344, 36]
        : !aviso ? [anchoPequena, 42, 20]
        : ({ gota: [440, 42, 20], fallo: [420, 42, 20], musica: [430, 74, 26], bt: [420, 42, 20], color: [330, 42, 20], captura: [410, 94, 28],
             temperatura: [390, 42, 20], temporizador: [380, 42, 20], modo: [320, 42, 20], bateria: [390, 42, 20], salida: [400, 42, 20] })[aviso.tipo] || [360, 42, 20]

    // Ajustar contenido (Ajustes > Isla): con uno o dos huecos ocupados, el ancho justo para lo que
    // hay. Cada lado pide su distancia al borde (margen + ancho) y el centro su ancho; con algo al
    // centro y algo a un lado, la isla tiene que dejar 24 px entre los dos a cada lado del centro.
    // ponytail: con grabacion o temporizador a la derecha vuelve a 360 en vez de medir esa fila.
    // Uno solo, este donde este, va al centro (si no, un asistente a la izquierda quedaba ladeado).
    readonly property bool centrarSolo: Estilo.valor("islaAjustar") && !derechaOcupada
        && ["izquierda", "centro", "derecha"].filter(k => Estilo.huecos[k] !== "nada").length === 1
    readonly property real anchoPequena: {
        if (!Estilo.valor("islaAjustar") || derechaOcupada) return 360;
        const h = Estilo.huecos;
        const medir = lado => {
            const tipo = h[lado];
            if (tipo === "nada") return -1;
            if (tipo === "asistente") return lado === "centro" || centrarSolo ? 40 : 46;
            const w = tipo === "hora" || tipo === "fecha" ? hora.implicitWidth
                : tipo === "visualizador" ? visIsla.width
                : (minis.count === 3 ? minis.itemAt(["izquierda", "centro", "derecha"].indexOf(lado)).width : 0);
            return lado === "centro" || centrarSolo ? w : 18 + w;
        };
        const iz = medir("izquierda"), ce = medir("centro"), de = medir("derecha");
        const usados = [iz, ce, de].filter(v => v >= 0);
        if (usados.length === 0 || usados.length === 3) return 360;
        let ancho = 0;
        if (centrarSolo) ancho = Math.max(iz, ce, de) + 36;
        else if (ce >= 0) ancho = Math.max(ce + 36, 2 * (Math.max(iz, de, 0) + (iz >= 0 || de >= 0 ? 24 : 0)) + ce);
        else ancho = (iz >= 0 ? iz : 0) + (de >= 0 ? de : 0) + (usados.length === 2 ? 24 : 18);
        return Math.min(360, Math.max(100, Math.ceil(ancho)));
    }

    // ---------------- Forma ----------------
    Item {
        id: forma
        property real ancho: win.tamano[0]
        property real alto: win.tamano[1]
        property real esquina: win.tamano[2]
        Behavior on ancho { NumberAnimation { duration: Estilo.t(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
        // Al encogerse no rebota: el rebote la pasaba de largo por debajo de su alto normal y la
        // dejaba unos cuadros como una tira finisima con los hombros torcidos.
        Behavior on alto {
            id: animAlto
            NumberAnimation { duration: Estilo.t(560); easing.type: Easing.BezierSpline; easing.bezierCurve: animAlto.targetValue < forma.alto ? Estilo.curvaIos : Estilo.curvaRebote }
        }
        Behavior on esquina { NumberAnimation { duration: Estilo.t(400) } }
        readonly property real x0: (win.width - ancho) / 2
        anchors { fill: parent; topMargin: Estilo.grosorMarco }   // sale del borde de arriba del marco
        // 0 = la forma elegida en Ajustes, 1 = la clasica. Abierta siempre es la clasica: al abrirse
        // se transforma poco a poco, al mismo ritmo que crece.
        property real aClasica: win.expandida ? 1 : 0
        Behavior on aClasica { NumberAnimation { duration: Estilo.t(280); easing.type: Easing.OutCubic } }
        // Cambio de forma en Ajustes: de la vieja a la nueva con rebote (cambio va de 0 a 1 y se pasa un poco).
        readonly property string elegida: Estilo.valor("islaForma")
        property string vieja: elegida
        property string nueva: elegida
        property real cambio: 1
        onElegidaChanged: { vieja = nueva; nueva = elegida; animCambio.restart(); }
        NumberAnimation { id: animCambio; target: forma; property: "cambio"; from: 0; to: 1; duration: Estilo.t(640); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote }
        function mezcla(a, b, t) { return a.map((q, i) => [q[0] + (b[i][0] - q[0]) * t, q[1] + (b[i][1] - q[1]) * t]); }
        readonly property var ajusteV: Estilo.ajusteForma(vieja)
        readonly property var ajusteN: Estilo.ajusteForma(nueva)
        // el contenido baja lo que pida la forma (la pildora lo centra en su capsula); abierta, nada
        readonly property real bajada: (ajusteV[1] + (ajusteN[1] - ajusteV[1]) * cambio) * (1 - aClasica)
        readonly property string trazo: {
            const hom = Math.min(win.hombro, esquina * 0.9);
            const v = Estilo.mitadForma(vieja, x0 - ajusteV[0], alto, esquina, hom);
            const n = Estilo.mitadForma(nueva, x0 - ajusteN[0], alto, esquina, hom);
            const c = Estilo.mitadForma("clasica", x0, alto, esquina, hom);
            return Estilo.trazoForma(mezcla(mezcla(v, n, cambio), c, aClasica), x0 + ancho / 2);
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Estilo.fondo
                strokeWidth: -1
                PathSvg { path: forma.trazo }
            }
        }

        // Franja del marco sobre la isla: el cursor pegado al borde de arriba cuenta como encima.
        Item {
            x: forma.x0; y: -Estilo.grosorMarco; width: forma.ancho; height: Estilo.grosorMarco
            HoverHandler { id: hoverFranja; onHoveredChanged: forma.cursorCambio() }
        }
        function cursorCambio() {
            if (hoverIsla.hovered || hoverFranja.hovered) { salir.stop(); if (Estilo.valor("islaCursor")) entrar.restart(); }
            else { entrar.stop(); salir.restart(); }
        }

        // Todo el contenido, recortado a la forma
        Item {
            id: dentro
            x: forma.x0; y: forma.bajada; width: forma.ancho; height: forma.alto
            clip: true

            HoverHandler {
                id: hoverIsla
                onHoveredChanged: forma.cursorCambio()
            }
            Timer { id: entrar; interval: ({ corta: 120, normal: 260, larga: 550 })[Estilo.valor("islaEspera")] ?? 260; onTriggered: win.encima = true }
            Timer { id: salir; interval: 420; onTriggered: win.encima = false }
            TapHandler {
                onTapped: {
                    if (win.aviso && win.aviso.tipo === "captura") { Quickshell.execDetached(["xdg-open", win.aviso.ruta]); win.siguienteAviso(); return; }
                    if (win.aviso && (win.aviso.tipo === "gota" || win.aviso.tipo === "fallo")) { win.conGota = true; win.fijada = true; return; }
                    // Un clic dentro la deja abierta; se cierra con un clic fuera (shell.clicFuera) o Esc.
                    win.fijada = true;
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

            // ---------- Imagen de fondo (pestana Acciones, Ajustes > Isla) ----------
            // Arriba se ve la imagen y hacia abajo se funde con el fondo, para que todo se lea.
            Item {
                id: fondoAcciones
                anchors.fill: parent
                readonly property string ruta: Estilo.valor("islaImagen")
                opacity: win.expandida && win.pestana === "acciones" && ruta ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Estilo.t(400); easing.type: Easing.OutCubic } }
                // arriba no hay esquinas (la isla sale del borde): el recorte sube fuera de la vista
                ClippingRectangle {
                    anchors { fill: parent; topMargin: -forma.esquina }
                    radius: forma.esquina
                    color: "transparent"
                    Image {
                        anchors.fill: parent
                        source: fondoAcciones.ruta ? "file://" + fondoAcciones.ruta : ""   // (dentro de ClippingRectangle, parent no es el Item de afuera)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 1280
                    }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.alpha(Estilo.fondo, 0.2) }
                            GradientStop { position: 0.5; color: Qt.alpha(Estilo.fondo, 0.6) }
                            GradientStop { position: 1; color: Qt.alpha(Estilo.fondo, 0.94) }
                        }
                    }
                }
            }

            // ---------- Fila de arriba ----------
            Item {
                id: cabecera
                width: parent.width; height: 42
                opacity: Math.max(0, 1 - win.fundidoAviso * 2)

                SystemClock { id: reloj; precision: Estilo.valor("segundos") ? SystemClock.Seconds : SystemClock.Minutes }

                // Asistente: al expandirse se va al boton grande; al abrir el lanzador, a la busqueda.
                Asistente {
                    id: asistenteIsla
                    width: 40; height: 40
                    anchors.verticalCenter: parent.verticalCenter
                    emocion: Cerebro.emocion ? Cerebro.emocion
                        : win.raiz.emocion === "normal" && Estilo.valor("reaccionMusica") && Mpris.players.values.some(p => p.isPlaying) ? "feliz" : win.raiz.emocion
                    readonly property string lado: Estilo.ladoDe("asistente")
                    visible: lado !== "" && !(lado === "derecha" && win.derechaOcupada)
                    x: lado === "centro" || win.centrarSolo ? (parent.width - 40) / 2 : lado === "derecha" ? parent.width - 46 : 6
                    ritmo: ({ tranquilo: 1.8, normal: 1, inquieto: 0.5 })[Estilo.valor("personalidad")] ?? 1
                    fondoNegro: true
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

                // Con la isla abierta la hora es un boton: abre y cierra el calendario.
                Rectangle {
                    anchors.centerIn: parent
                    width: hora.implicitWidth + (win.expandida ? 40 : 0); height: 28; radius: 14
                    color: zonaHora.containsMouse || win.calendario ? Estilo.realce : Estilo.nada
                    opacity: win.expandida ? 1 : 0
                    Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                    Behavior on opacity { NumberAnimation { duration: Estilo.t(200) } }
                    Simbolo {
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: "expand_more"; font.pixelSize: 16; color: Estilo.texto2
                        rotation: win.calendario ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                    }
                    MouseArea {
                        id: zonaHora
                        anchors.fill: parent
                        enabled: win.expandida
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Sin fijar, el clic solo la fija (la hora queda justo donde uno pulsa para fijar la isla).
                        onClicked: {
                            if (!win.fijada) { win.fijada = true; return; }
                            win.calendario = !win.calendario;
                            if (win.calendario) win.conGota = false;
                        }
                    }
                }
                Text {
                    id: hora
                    // Pequena: en el hueco elegido (con fecha si asi se pidio). Abierta: siempre al centro.
                    readonly property string lado: Estilo.ladoDe("hora")
                    readonly property bool conFecha: !win.expandida && Estilo.huecos.centro === "fecha"
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: win.expandida ? -9 : win.centrarSolo ? 0
                        : lado === "izquierda" ? -(parent.width / 2 - 18 - implicitWidth / 2)
                        : lado === "derecha" ? parent.width / 2 - 18 - implicitWidth / 2 : 0
                    Behavior on anchors.horizontalCenterOffset { NumberAnimation { duration: Estilo.t(200) } }
                    anchors.verticalCenterOffset: 1
                    opacity: win.expandida || (lado !== "" && !(lado === "derecha" && win.derechaOcupada)) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Estilo.t(200) } }
                    text: (conFecha ? Qt.locale("es_MX").toString(reloj.date, "ddd d MMM").replace(/\./g, "") + " · " : "")
                        + Qt.formatTime(reloj.date, (Estilo.valor("reloj12") ? "h:mm" : "H:mm") + (Estilo.valor("segundos") ? ":ss" : "") + (Estilo.valor("reloj12") ? " AP" : ""))
                    color: Estilo.texto
                    font { family: Estilo.letra; weight: Font.DemiBold; pixelSize: conFecha ? 17 : 19; letterSpacing: -0.45 }
                    font.features: { "tnum": 1 }
                }

                // Miniwidgets de datos (Ajustes > Isla > Isla pequena), uno por hueco. El del centro
                // se esconde con la isla abierta: ahi va el boton de la hora.
                Repeater {
                    id: minis
                    model: ["izquierda", "centro", "derecha"]
                    delegate: Item {
                        id: mini
                        required property string modelData
                        readonly property string tipo: Estilo.huecos[modelData]
                        readonly property bool deDatos: ["temperatura", "cpu", "volumen", "escritorios", "caratula"].includes(tipo)
                        width: contenidoMini.implicitWidth; height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        x: modelData === "centro" || win.centrarSolo ? (parent.width - width) / 2 : modelData === "izquierda" ? 18 : parent.width - 18 - width
                        opacity: deDatos && !(modelData === "derecha" && win.derechaOcupada) && !(modelData === "centro" && win.expandida) ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Estilo.t(200) } }
                        Row {
                            id: contenidoMini
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            // Icono + numero: temperatura, CPU, volumen
                            Simbolo {
                                visible: ["temperatura", "cpu", "volumen"].includes(mini.tipo)
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 17
                                color: mini.tipo === "temperatura" && win.temperatura >= Estilo.valor("avisoGrados") ? Estilo.peligro : Estilo.texto2
                                text: mini.tipo === "temperatura" ? "thermostat" : mini.tipo === "cpu" ? "memory"
                                    : win.volumenMudo ? "volume_off" : "volume_up"
                            }
                            Texto {
                                visible: ["temperatura", "cpu", "volumen"].includes(mini.tipo)
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                                text: mini.tipo === "temperatura" ? win.temperatura + "°" : mini.tipo === "cpu" ? win.usoCpu + "%" : win.volumen
                            }
                            // Escritorios de este monitor: el activo es una pastilla, los demas puntos
                            Repeater {
                                model: mini.tipo === "escritorios" ? win.escritoriosAqui : []
                                delegate: Rectangle {
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: modelData.is_active ? 16 : 6; height: 6; radius: 3
                                    color: modelData.is_active ? Estilo.texto : Estilo.texto3
                                    Behavior on width { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                                    Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                                }
                            }
                            // Caratula de lo que suena (sin disco: la nota)
                            ClippingRectangle {
                                visible: mini.tipo === "caratula" && !!win.musica
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24; height: 24; radius: 7
                                color: Estilo.hover
                                Simbolo { anchors.centerIn: parent; text: "music_note"; font.pixelSize: 15; color: Estilo.texto2; visible: !portada.source.toString() }
                                Image {
                                    id: portada
                                    anchors.fill: parent
                                    source: mini.tipo === "caratula" && win.musica ? win.musica.trackArtUrl || "" : ""
                                    fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(64, 64)
                                    opacity: win.musica && win.musica.isPlaying ? 1 : 0.5
                                }
                            }
                        }
                    }
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
                Row {   // cronometro (desde el lanzador), en el mismo sitio; el temporizador tiene prioridad
                    visible: !win.raiz.grabando && win.raiz.temporizadorRestante <= 0 && win.raiz.cronometroInicio > 0
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Simbolo { text: "timer_play"; color: Estilo.tono("cronometro"); font.pixelSize: 17; anchors.verticalCenter: parent.verticalCenter }
                    Texto { text: win.mmss(win.raiz.cronometroSegundos); color: Estilo.tono("cronometro"); font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
                }
                Visualizador {
                    id: visIsla
                    // En la pestana Musica se esconde: ahi ya se ve lo que suena.
                    readonly property string lado: Estilo.ladoDe("visualizador")
                    visible: opacity > 0.01 && lado !== "" && !Estilo.juego && !(lado === "derecha" && win.derechaOcupada)
                    opacity: win.expandida && ((win.pestana === "musica" && Estilo.valor("ocultarVisualizador")) || lado === "centro") ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Estilo.t(200) } }
                    x: lado === "centro" || win.centrarSolo ? (parent.width - width) / 2 : lado === "izquierda" ? 18 : parent.width - 18 - width
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ---------- Avisos ----------
            Item {
                id: capaAviso
                anchors.fill: parent
                opacity: Math.max(0, win.fundidoAviso * 2 - 1)
                visible: opacity > 0.01
                property var a: win.aviso || capaAviso.a   // conserva el ultimo mientras se desvanece

                Loader {
                    anchors.fill: parent
                    sourceComponent: capaAviso.a ? ({ gota: avGota, fallo: avFallo, musica: avMusica, bt: avBt, captura: avCaptura, color: avColor,
                                                     temperatura: avTemp, temporizador: avTimer, modo: avModo, bateria: avBateria, salida: avSalida })[capaAviso.a.tipo] ?? null : null
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

                // El boton solo sale en Acciones; en Musica y Rendimiento la pagina ocupa todo el ancho.
                readonly property bool conBoton: !win.calendario && (win.conGota || (win.pestana === "acciones" && Estilo.valor("botEnPaginas")))
                BotonAsistente {
                    id: botonAsistente
                    y: 2
                    height: 276
                    emocion: asistenteIsla.emocion
                    onPulsado: { win.conGota = !win.conGota; win.fijada = win.conGota; }
                    opacity: cuerpo.conBoton ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Estilo.t(cuerpo.conBoton ? 320 : 180) } }
                }
                Connections { target: win; function onExpandidaChanged() { if (win.expandida) botonAsistente.aparecer(); } }

                PaginaGota {
                    x: botonAsistente.width + 18
                    width: cuerpo.width - x; height: cuerpo.height
                    activa: win.conGota
                }

                Column {
                    width: cuerpo.width
                    spacing: 10
                    opacity: win.conGota || win.calendario ? 0 : 1
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Estilo.t(win.conGota ? 140 : 260) } }

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

                PaginaCalendario { anchors.fill: parent; activa: win.calendario }
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
    // El aviso sale del primero que suene sin estar callado en Ajustes > Notificaciones.
    readonly property var reproductorAviso: Mpris.players.values.find(p => p.isPlaying && !Estilo.valor("musicaIgnorar").includes(p.identity)) ?? null
    readonly property string cancionActual: reproductorAviso ? reproductorAviso.trackTitle + "|" + reproductorAviso.trackArtist : ""
    onCancionActualChanged: {
        const r = reproductorAviso;
        // Al pausar, cancionActual se vacia: volver a la misma cancion solo avisa si se pidio.
        if (listo && cancionActual && r.trackTitle && (cancionActual !== ultimaCancion || Estilo.valor("musicaReanudar"))
                && (r.trackArtUrl || !Estilo.valor("musicaConCaratula")))
            avisarMusica({ tipo: "musica", titulo: r.trackTitle, artista: r.trackArtist, arte: r.trackArtUrl,
                           apps: [r.desktopEntry, r.identity].filter(x => x).map(x => x.toLowerCase()) });
        if (cancionActual) ultimaCancion = cancionActual;
    }
    // "No avisar si la app esta al frente": se pregunta a niri por la ventana con el foco.
    property var musicaPendiente: null
    function avisarMusica(a) {
        if (!Estilo.valor("musicaNoAlFrente")) { avisar(a); return; }
        musicaPendiente = a;
        ventanaFrente.running = true;
    }
    Process {
        id: ventanaFrente
        command: ["niri", "msg", "-j", "focused-window"]
        stdout: StdioCollector {
            onStreamFinished: {
                let id = "";
                try { id = (JSON.parse(text)?.app_id ?? "").toLowerCase(); } catch (e) {}
                const a = win.musicaPendiente;
                win.musicaPendiente = null;
                if (a && !(id && a.apps.some(x => id.includes(x) || x.includes(id)))) win.avisar(a);
            }
        }
    }

    // Color de la caratula para el tinte. ColorQuantizer solo lee archivos locales: las
    // caratulas de internet (Spotify) se bajan antes a Estilo.tmp.
    readonly property string arte: musica && Estilo.valor("musicaTinte") ? musica.trackArtUrl : ""
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
                    avisoBt.restart(), win.ultimoBt = modelData, win.ultimoBtMs = Date.now();
            }
        }
    }
    property var ultimoBt: null
    property real ultimoBtMs: 0
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
    property int temperatura: 0                      // la mas alta de CPU y GPU, para el miniwidget

    // ---- Datos de los miniwidgets de la isla pequena ----
    // Grabacion, temporizador y cronometro le ganan el hueco derecho a cualquier miniwidget.
    readonly property bool derechaOcupada: raiz.grabando || raiz.temporizadorRestante > 0 || raiz.cronometroInicio > 0
    PwObjectTracker { objects: [win.salidaAudio] }
    readonly property bool volumenMudo: !!salidaAudio?.audio?.muted
    readonly property int volumen: Math.round((salidaAudio?.audio?.volume ?? 0) * 100)
    // Escritorios de este monitor, sin el vacio que niri deja siempre al final.
    readonly property var escritoriosAqui: raiz.escritorios
        .filter(w => w.output === win.screen?.name && (w.name || w.active_window_id !== null || w.is_active))
        .sort((a, b) => a.idx - b.idx)
    // Uso de CPU: /proc/stat cada 2 s, solo si algun hueco lo muestra.
    property int usoCpu: 0
    property var cpuAntes: null
    Process {
        id: lecturaCpu
        command: ["head", "-1", "/proc/stat"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = text.trim().split(/\s+/).slice(1).map(Number);
                const total = n.reduce((a, b) => a + b, 0), libre = n[3] + (n[4] || 0);
                if (win.cpuAntes) {
                    const dt = total - win.cpuAntes[0];
                    if (dt > 0) win.usoCpu = Math.round(100 * (1 - (libre - win.cpuAntes[1]) / dt));
                }
                win.cpuAntes = [total, libre];
            }
        }
    }
    Timer { interval: 2000; repeat: true; triggeredOnStart: true; running: Estilo.ladoDe("cpu") !== ""; onTriggered: lecturaCpu.running = true }

    Process {
        id: temperaturas
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do case $(cat $h/name) in k10temp|coretemp|zenpower) cat $h/temp1_input;; esac; done | head -1; " +
                              "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [c, g] = text.trim().split("\n").map(Number);
                const cpu = (c || 0) / 1000, gpu = g || 0, max = Math.max(cpu, gpu);
                win.temperatura = Math.round(max);
                if (max > Estilo.valor("avisoGrados") && !win.calienteAvisado) {
                    win.calienteAvisado = true;
                    win.avisar({ tipo: "temperatura", texto: (gpu >= cpu ? "GPU " : "CPU ") + Math.round(max) + " °C", ms: 4000 });
                } else if (max < Estilo.valor("avisoGrados") - 5) win.calienteAvisado = false;
            }
        }
    }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: temperaturas.running = true }

    // Bateria baja de mandos, audifonos o ratones (UPower, no la de la laptop): avisa al bajar
    // de 20 %, una vez hasta que pase de 30 %.
    property var bateriasAvisadas: ({})
    Instantiator {
        model: UPower.devices
        delegate: Connections {
            required property var modelData
            target: modelData
            function onPercentageChanged() { win.revisarBateria(modelData) }
        }
    }
    function revisarBateria(d) {
        if (d.isLaptopBattery || !d.isPresent) return;
        const p = d.percentage > 1 ? d.percentage : d.percentage * 100;   // ponytail: 0..1 o 0..100 segun version de Quickshell
        if (p <= 20 && !bateriasAvisadas[d.nativePath]) {
            bateriasAvisadas[d.nativePath] = true;
            avisar({ tipo: "bateria", nombre: d.model || "Dispositivo", bateria: Math.round(p), ms: 4500 });
        } else if (p > 30) delete bateriasAvisadas[d.nativePath];
    }

    // Cambio de salida de audio. Si acaba de conectarse un Bluetooth, ese aviso ya lo dice.
    readonly property var salidaAudio: Pipewire.defaultAudioSink
    onSalidaAudioChanged: if (listo && salidaAudio && Date.now() - ultimoBtMs > 4000) avisoSalida.restart()
    Timer {
        id: avisoSalida; interval: 600
        onTriggered: if (win.salidaAudio) win.avisar({ tipo: "salida", nombre: win.salidaAudio.description || win.salidaAudio.nickname || win.salidaAudio.name })
    }

    // El fin del temporizador lo manda la raiz
    Connections {
        target: win.raiz
        function onTemporizadorTerminado() { win.avisar({ tipo: "temporizador", ms: 5000 }); }
        // Super+Alt+F: sale en la isla del monitor de ese escritorio. Pulsar de nuevo reemplaza el
        // aviso en vez de ponerlo en fila.
        function onModoCambiado(flotante, salida, numero) {
            if (win.screen && salida && win.screen.name !== salida) return;
            const a = { tipo: "modo", flotante: flotante, numero: numero, ms: 1500 };
            win.colaAvisos = win.colaAvisos.filter(x => x.tipo !== "modo");
            if (win.aviso?.tipo === "modo") { win.aviso = a; finAviso.interval = 1500; finAviso.restart(); }
            else win.avisar(a);
        }
    }

    // ---------------- Avisos (contenido) ----------------
    Component {
        id: avMusica
        Row {
            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
            spacing: 12
            ClippingRectangle {
                width: 46; height: 46; radius: 10; color: Estilo.hover; anchors.verticalCenter: parent.verticalCenter
                Image { anchors.fill: parent; source: capaAviso.a.arte || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 46 - 12 - 46 - 12
                Texto { text: "Ahora suena"; color: Estilo.texto2; font.pixelSize: 11 }
                Texto { width: parent.width; text: capaAviso.a.titulo; font.weight: Font.DemiBold; font.pixelSize: 14; elide: Text.ElideRight }
                Texto { width: parent.width; text: capaAviso.a.artista || ""; color: Estilo.texto2; font.pixelSize: 12; elide: Text.ElideRight }
            }
            Asistente { width: 46; height: 46; emocion: "feliz"; fondoNegro: true; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    // qs -p ~/.config/quickshell/isla ipc call gota_HDMI-A-1 abrir | preguntar "texto" | pestana acciones
    IpcHandler {
        target: "gota_" + (win.screen ? win.screen.name : "")
        function abrir(): void { win.conGota = true; win.fijada = true; }
        function pestana(p: string): void { win.conGota = false; win.pestana = p; win.fijada = true; }
        function vista(v: string): void { win.vistaAcciones = v; }
        // Para probar: ... ipc call gota_HDMI-A-1 calendario   (otra vez lo cierra)
        function calendario(): void { win.conGota = false; win.fijada = true; win.calendario = !win.calendario; }
        function cerrar(): void { win.conGota = false; win.fijada = false; win.encima = false; }
        function preguntar(texto: string): void { abrir(); Cerebro.preguntar(texto); }
        function avisoBt(nombre: string, bateria: int): void { win.avisar({ tipo: "bt", nombre: nombre, bateria: bateria }); }
        function avisoMusica(titulo: string, artista: string): void { win.avisar({ tipo: "musica", titulo: titulo, artista: artista, arte: "" }); }
    }
    Connections {
        target: Cerebro
        function onTermino(texto) {
            if (win.expandida && win.conGota) return;
            win.avisar({ tipo: "gota", texto: Cerebro.estado === "plan" ? "Tengo un plan listo. Ábreme para verlo."
                                        : (texto || Cerebro.mensajes.length && Cerebro.mensajes[Cerebro.mensajes.length - 1].texto || "Listo.").split("\n")[0], ms: 6000 });
        }
    }
    Connections {
        target: Cerebro
        function onFallo(clave, titulo, detalle) { win.avisar({ tipo: "fallo", titulo: titulo, detalle: detalle, ms: 12000 }); }
    }
    // Fallo detectado: la Gota confundida, que es y "Arreglar" (le pasa el problema)
    Component {
        id: avFallo
        Item {
            Asistente { x: 8; width: 30; height: 30; anchors.verticalCenter: parent.verticalCenter; emocion: "confuso" }
            Texto { x: 46; width: parent.width - 46 - arreglar.width - 26; anchors.verticalCenter: parent.verticalCenter; text: capaAviso.a.titulo; elide: Text.ElideRight; font.weight: Font.DemiBold }
            Chip {
                id: arreglar
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                texto: "Arreglar"; blanco: true
                onPulsado: { const a = capaAviso.a; win.siguienteAviso(); win.conGota = true; win.fijada = true; Cerebro.arreglar(a.titulo, a.detalle); }
            }
        }
    }
    Component {
        id: avGota
        Item {
            Asistente { x: 8; width: 30; height: 30; anchors.verticalCenter: parent.verticalCenter; emocion: Cerebro.emocion || "feliz" }
            Texto { x: 46; width: parent.width - 62; anchors.verticalCenter: parent.verticalCenter; text: capaAviso.a.texto; elide: Text.ElideRight; font.weight: Font.DemiBold }
        }
    }
    Component {
        id: avBt
        Item {
            Simbolo { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "headphones"; font.pixelSize: 20 }
            // Nombre y "conectados" centrados juntos en 240 px (el aviso mide 420: 90 libres a cada lado
            // para el icono y la bateria). Fijo, no el ancho vivo: al encogerse la isla el nombre se recortaba.
            Row {
                anchors.centerIn: parent
                spacing: 6
                Texto { width: Math.min(implicitWidth, 240 - conectados.width - 6); text: capaAviso.a.nombre; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Texto { id: conectados; text: "conectados"; color: Estilo.texto2 }
            }
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
                width: 104; height: 62; radius: 10; color: Estilo.hover; anchors.verticalCenter: parent.verticalCenter
                Image { anchors.fill: parent; source: "file://" + capaAviso.a.ruta; sourceSize.width: 220; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Texto { text: "Captura guardada"; font.weight: Font.DemiBold; font.pixelSize: 14 }
                Texto { text: "Copiada al portapapeles"; color: Estilo.texto2; font.pixelSize: 12 }
                Row {
                    topPadding: 4; spacing: 6
                    Chip { texto: "Abrir"; blanco: true; onPulsado: { Quickshell.execDetached(["xdg-open", capaAviso.a.ruta]); win.siguienteAviso(); } }
                    Chip { texto: "Carpeta"; onPulsado: { Quickshell.execDetached(["xdg-open", capaAviso.a.ruta.replace(/\/[^/]+$/, "")]); win.siguienteAviso(); } }
                }
            }
        }
    }
    Component {
        id: avTemp
        Item {
            Asistente { x: 8; width: 34; height: 34; emocion: "confuso"; fondoNegro: true; anchors.verticalCenter: parent.verticalCenter }
            Row {
                anchors.centerIn: parent; spacing: 6
                Simbolo { text: "thermostat"; color: Estilo.peligro; font.pixelSize: 18; anchors.verticalCenter: parent.verticalCenter }
                Texto { text: capaAviso.a.texto; color: Estilo.peligro; font.weight: Font.DemiBold; font.pixelSize: 15 }
            }
            Texto { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: "Temperatura alta"; color: Estilo.texto2; font.pixelSize: 12 }
        }
    }
    Component {
        id: avColor
        Item {
            Rectangle { x: 14; width: 22; height: 22; radius: 11; color: capaAviso.a.hex; border.color: Estilo.texto3; anchors.verticalCenter: parent.verticalCenter }
            Texto { anchors.centerIn: parent; text: capaAviso.a.hex; font.weight: Font.DemiBold; font.pixelSize: 15; font.features: { "tnum": 1 } }
            Texto { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: "Copiado"; color: Estilo.texto2; font.pixelSize: 12 }
        }
    }
    Component {
        id: avBateria
        Item {
            Simbolo { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "battery_alert"; color: Estilo.peligro; font.pixelSize: 20 }
            Texto { anchors.centerIn: parent; width: parent.width - 150; horizontalAlignment: Text.AlignHCenter; text: capaAviso.a.nombre; font.weight: Font.DemiBold; elide: Text.ElideRight }
            Texto { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: capaAviso.a.bateria + " %"; color: Estilo.peligro; font.pixelSize: 12 }
        }
    }
    Component {
        id: avSalida
        Item {
            Simbolo { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "volume_up"; font.pixelSize: 20 }
            Texto { anchors.centerIn: parent; width: parent.width - 150; horizontalAlignment: Text.AlignHCenter; text: capaAviso.a.nombre; font.weight: Font.DemiBold; elide: Text.ElideRight }
            Texto { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: "Salida"; color: Estilo.texto2; font.pixelSize: 12 }
        }
    }
    // Modo del escritorio: pastilla blanca con icono negro si flota, gris si va en fila.
    Component {
        id: avModo
        Item {
            Rectangle {
                x: 12; width: 28; height: 28; radius: 14; anchors.verticalCenter: parent.verticalCenter
                color: capaAviso.a.flotante ? Estilo.texto : Estilo.realce
                Simbolo { anchors.centerIn: parent; text: capaAviso.a.flotante ? "web_asset" : "view_column"; font.pixelSize: 18; color: capaAviso.a.flotante ? Estilo.fondo : Estilo.texto }
            }
            Texto { x: 52; anchors.verticalCenter: parent.verticalCenter; text: capaAviso.a.flotante ? "Flotante" : "En fila"; font.weight: Font.DemiBold; font.pixelSize: 15 }
            Texto { anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter } visible: capaAviso.a.numero > 0; text: "Escritorio " + capaAviso.a.numero; color: Estilo.texto2; font.pixelSize: 12 }
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
    // Calendario (clic en la hora): hoy en grande a la izquierda, el mes a la derecha.
    // Las flechas cambian de mes y "Hoy" vuelve al actual. Sin eventos por ahora.
    component PaginaCalendario: Item {
        id: pc
        property bool activa: false
        opacity: activa ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Estilo.t(activa ? 260 : 120) } }
        onActivaChanged: if (activa) desfase = 0
        property int desfase: 0                     // meses desde el actual
        readonly property date hoy: reloj.date
        readonly property date mes: new Date(hoy.getFullYear(), hoy.getMonth() + desfase, 1)
        readonly property bool lunes: Estilo.barra?.semanaLunes ?? true
        readonly property int primerDia: (mes.getDay() + (lunes ? 6 : 0)) % 7
        readonly property int dias: new Date(mes.getFullYear(), mes.getMonth() + 1, 0).getDate()
        function nombre(d, f) { const s = Qt.locale("es_ES").toString(d, f); return s.charAt(0).toUpperCase() + s.slice(1); }

        Rectangle {
            id: hoyGrande
            width: 150; height: parent.height - 6
            radius: 24; color: Estilo.tarjeta
            Column {
                anchors.centerIn: parent
                spacing: 2
                Texto { anchors.horizontalCenter: parent.horizontalCenter; text: pc.hoy.getDate(); font.pixelSize: 56; font.weight: Font.Light; font.features: { "tnum": 1 } }
                Texto { anchors.horizontalCenter: parent.horizontalCenter; text: pc.nombre(pc.hoy, "dddd"); font.pixelSize: 15; font.weight: Font.DemiBold }
                Texto { anchors.horizontalCenter: parent.horizontalCenter; text: pc.nombre(pc.hoy, "MMMM"); color: Estilo.texto2; font.pixelSize: 12 }
            }
        }

        Item {
            anchors { left: hoyGrande.right; leftMargin: 18; right: parent.right; top: parent.top; bottom: parent.bottom }
            Item {
                id: cabeceraMes
                width: parent.width; height: 30
                Texto { anchors.verticalCenter: parent.verticalCenter; x: 6; text: pc.nombre(pc.mes, "MMMM yyyy"); font.pixelSize: 16; font.weight: Font.DemiBold }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    BotonMes { icono: "chevron_left"; onPulsado: pc.desfase-- }
                    BotonMes { texto: "Hoy"; apagado: pc.desfase === 0; onPulsado: pc.desfase = 0 }
                    BotonMes { icono: "chevron_right"; onPulsado: pc.desfase++ }
                }
            }
            Grid {
                id: rejillaMes
                anchors { top: cabeceraMes.bottom; topMargin: 6; left: parent.left; right: parent.right }
                columns: 7
                Repeater {
                    model: pc.lunes ? ["L", "M", "X", "J", "V", "S", "D"] : ["D", "L", "M", "X", "J", "V", "S"]
                    Texto { required property string modelData; required property int index; width: rejillaMes.width / 7; height: 24; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: modelData; color: (pc.lunes ? index >= 5 : index === 0 || index === 6) ? Estilo.texto3 : Estilo.texto2; font.pixelSize: 11; font.weight: Font.Bold }
                }
                // 42 casillas fijas: el modelo no cambia al pasar de mes, solo lo que dice cada una.
                Repeater {
                    model: 42
                    delegate: Item {
                        required property int index
                        readonly property int dia: index - pc.primerDia + 1
                        readonly property bool valido: dia > 0 && dia <= pc.dias
                        readonly property bool esHoy: valido && pc.desfase === 0 && dia === pc.hoy.getDate()
                        readonly property bool finde: pc.lunes ? index % 7 >= 5 : index % 7 === 0 || index % 7 === 6
                        width: rejillaMes.width / 7; height: 34
                        Rectangle { anchors.centerIn: parent; width: 30; height: 30; radius: 15; color: Estilo.texto; visible: parent.esHoy }
                        Texto {
                            anchors.centerIn: parent; visible: parent.valido; text: parent.dia
                            font.pixelSize: 13; font.features: { "tnum": 1 }
                            font.weight: parent.esHoy ? Font.DemiBold : Font.Normal
                            color: parent.esHoy ? Estilo.fondo : parent.finde ? Estilo.texto2 : Estilo.texto
                        }
                    }
                }
            }
        }
    }
    component BotonMes: Rectangle {
        id: bm
        property string icono: ""
        property string texto: ""
        property bool apagado: false
        signal pulsado()
        width: texto ? etiqueta.implicitWidth + 18 : 28; height: 26; radius: 13
        color: zonaBm.containsMouse && !apagado ? Estilo.realce : Estilo.hundido
        opacity: apagado ? 0.45 : 1
        scale: zonaBm.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(140); easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
        Simbolo { anchors.centerIn: parent; visible: !!bm.icono; text: bm.icono; font.pixelSize: 18; color: Estilo.texto }
        Texto { id: etiqueta; anchors.centerIn: parent; visible: !!bm.texto; text: bm.texto; font.pixelSize: 12; font.weight: Font.DemiBold }
        MouseArea { id: zonaBm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!bm.apagado) bm.pulsado() }
    }
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

        Texto { visible: !pm.r; anchors.centerIn: parent; text: "No suena nada"; color: Estilo.texto2 }
        Row {
            visible: !!pm.r
            width: parent.width
            spacing: 18

            // Caratula grande: un clic lleva a la ventana de la app que suena.
            ClippingRectangle {
                id: caratula
                width: 150; height: 150; radius: 18; color: Estilo.hover
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
                            color: elegido ? "#ffffff" : zReprod.containsMouse ? "#40ffffff" : "#26ffffff"
                            Behavior on color { ColorAnimation { duration: Estilo.t(180) } }
                            Texto { id: tc; anchors.centerIn: parent; text: modelData.identity; font.pixelSize: 10; color: parent.elegido ? Estilo.enActivo : Estilo.texto }
                            MouseArea { cursorShape: Qt.PointingHandCursor; id: zReprod; hoverEnabled: true; anchors.fill: parent; onClicked: win.elegido = modelData }
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
                    MouseArea { cursorShape: Qt.PointingHandCursor
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
                        Simbolo { visible: pm.flujos.length > 0; text: "volume_up"; font.pixelSize: 17; color: Estilo.texto; anchors.verticalCenter: parent.verticalCenter }
                        Item {
                            id: volApp
                            visible: pm.flujos.length > 0
                            width: 70; height: 18; anchors.verticalCenter: parent.verticalCenter
                            readonly property real valor: pm.flujos.length && pm.flujos[0].audio ? Math.min(1, pm.flujos[0].audio.volume) : 0
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: "#26ffffff" }
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * volApp.valor; height: 4; radius: 2; color: "#ffffff" }
                            MouseArea { cursorShape: Qt.PointingHandCursor
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
                            MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaSalida; anchors.fill: parent; hoverEnabled: true; onClicked: pm.siguienteSalida() }
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
        Connections {
            target: win
            function onExpandidaChanged() { if (!win.expandida) win.vistaAcciones = "botones"; }
            function onVistaAccionesChanged() { if (win.vistaAcciones === "portapapeles") leerHistorial.running = true; }
        }

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
            command: Estilo.comandoSiguienteFondo
        }

        // ---- Botones ----
        // Tres grupos: las capturas en una barra partida en cuatro, dos interruptores, y abajo el
        // temporizador con las utilidades (solo icono).
        Column {
            visible: win.vistaAcciones === "botones"
            width: parent.width
            spacing: 10

            ClippingRectangle {
                width: parent.width; height: 66; radius: 20
                color: Estilo.tarjeta
                Row {
                    anchors.fill: parent
                    Segmento { icono: "screenshot_region"; texto: "Zona"
                               onPulsado: { win.fijada = false; win.encima = false; pa.hacer(["sh", "-c", "sleep 0.5; qs -p '" + Estilo.carpeta + "' ipc call captura abrir zona"]); } }
                    Segmento { icono: "fullscreen"; texto: "Pantalla"
                               onPulsado: { win.fijada = false; win.encima = false; pa.hacer(["sh", "-c", "sleep 0.6; niri msg action screenshot-screen"]); } }
                    Segmento { icono: win.raiz.grabando ? "stop_circle" : "radio_button_checked"; colorIcono: "#ff453a"
                               texto: win.raiz.grabando ? win.mmss(win.raiz.segundosGrabando) : "Grabar"
                               onPulsado: { if (!win.raiz.grabando) { win.fijada = false; win.encima = false; } win.raiz.alternarGrabacion(); } }
                    Segmento { icono: "colorize"; texto: "Color"; ultimo: true
                               onPulsado: { win.fijada = false; win.encima = false; tomarColor.running = true; } }
                }
            }

            Row {
                width: parent.width
                spacing: 10
                Interruptor { icono: "sports_esports"; texto: "Modo juego"; encendido: win.raiz.modoJuego; onPulsado: win.raiz.alternarModoJuego() }
                Interruptor { icono: pa.micMudo ? "mic_off" : "mic"; texto: "Micrófono"; encendido: !pa.micMudo
                              onPulsado: if (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio) Pipewire.defaultAudioSource.audio.muted = !pa.micMudo }
            }

            Row {
                width: parent.width
                spacing: 8
                Rectangle {
                    id: tempo
                    // Un booleano aparte: si el modelo del Repeater dependiera del tiempo restante,
                    // se recrearian los botones en cada tic.
                    readonly property bool corriendo: win.raiz.temporizadorRestante > 0
                    width: parent.width - 4 * (46 + 8); height: 46; radius: 18
                    color: Estilo.tarjeta
                    Row {
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Simbolo { text: tempo.corriendo ? "timer_off" : "timer"; font.pixelSize: 19; anchors.verticalCenter: parent.verticalCenter }
                        Texto { visible: tempo.corriendo; text: win.mmss(win.raiz.temporizadorRestante); font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                        Repeater {
                            model: tempo.corriendo ? [["Cancelar", 0]] : [["1", 60], ["5", 300], ["10", 600], ["25", 1500]]
                            delegate: Rectangle {
                                required property var modelData
                                anchors.verticalCenter: parent.verticalCenter
                                width: tTm.implicitWidth + 18; height: 26; radius: 13
                                color: zc2.containsMouse ? Estilo.apagado : Estilo.hundido
                                Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
                                scale: zc2.pressed ? 0.9 : 1
                                Behavior on scale { NumberAnimation { duration: Estilo.t(zc2.pressed ? 80 : 360); easing.type: zc2.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
                                Texto { id: tTm; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: 11 }
                                MouseArea { cursorShape: Qt.PointingHandCursor; id: zc2; anchors.fill: parent; hoverEnabled: true
                                    onClicked: modelData[1] > 0 ? win.raiz.iniciarTemporizador(modelData[1]) : win.raiz.cancelarTemporizador() }
                            }
                        }
                        Texto { visible: !tempo.corriendo; text: "min"; color: Estilo.texto2; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                BotonIcono { icono: "content_paste"; onPulsado: win.vistaAcciones = "portapapeles" }
                BotonIcono { icono: "edit_note"; onPulsado: { win.fijada = true; win.vistaAcciones = "nota"; } }
                BotonIcono { icono: "wallpaper"; onPulsado: siguienteFondo.running = true }
                BotonIcono { icono: "lock"; onPulsado: { win.fijada = false; win.encima = false; win.raiz.bloquear(); } }
            }
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
                radius: 14; color: Estilo.hundido
                Flickable {
                    anchors { fill: parent; margins: 12 }
                    contentHeight: nota.paintedHeight
                    clip: true
                    TextEdit {
                        id: nota
                        width: parent.width
                        wrapMode: TextEdit.Wrap
                        color: Estilo.texto; selectionColor: Estilo.texto3
                        font { family: Estilo.letra; pixelSize: 13 }
                        focus: parent.parent.parent.visible
                        onTextChanged: if (activeFocus) guardarNota.restart()
                        Keys.onEscapePressed: win.vistaAcciones = "botones"
                    }
                }
                Texto { visible: !nota.text; x: 12; y: 12; text: "Escriba aquí… se guarda solo."; color: Estilo.texto3 }
            }
        }

        // ---- Portapapeles: los ultimos 6 de cliphist; un clic los vuelve a copiar ----
        // Las imagenes se sacan a Estilo.tmp/menisco-clip-<id> para mostrar la miniatura.
        property var historial: []
        Process {
            id: leerHistorial
            command: ["sh", "-c", "rm -f $XDG_RUNTIME_DIR/menisco-clip-*; cliphist list | head -6 | while IFS=\"$(printf '\\t')\" read -r id t; do " +
                "case \"$t\" in \"[[ binary data\"*) cliphist decode \"$id\" > $XDG_RUNTIME_DIR/menisco-clip-$id;; esac; printf '%s\\t%s\\n' \"$id\" \"$t\"; done"]
            stdout: StdioCollector {
                onStreamFinished: pa.historial = text.trim().split("\n").filter(l => l).map(l => {
                    const i = l.indexOf("\t");
                    const t = l.slice(i + 1);
                    const img = /^\[\[ binary data .* (\d+x\d+) \]\]/.exec(t);
                    return { id: l.slice(0, i), texto: img ? "Imagen · " + img[1].replace("x", "×") : t, imagen: !!img };
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
                Texto { visible: !pa.historial.length; text: "Todavía no hay nada copiado."; color: Estilo.texto2; leftPadding: 4 }
                Repeater {
                    model: pa.historial
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width; height: 32; radius: 10
                        color: zpp.containsMouse ? Estilo.realce : Estilo.nada
                        Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
                        Simbolo { visible: !modelData.imagen; x: 8; anchors.verticalCenter: parent.verticalCenter; text: "content_paste"; font.pixelSize: 16; color: Estilo.texto2 }
                        ClippingRectangle {
                            id: miniatura
                            visible: modelData.imagen
                            x: 4; width: 52; height: 26; radius: 6; color: Estilo.hundido
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                                anchors.fill: parent
                                source: modelData.imagen ? "file://" + Estilo.tmp + "/menisco-clip-" + modelData.id : ""
                                sourceSize.height: 52
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true; cache: false
                            }
                        }
                        Texto { x: modelData.imagen ? 64 : 32; width: parent.width - x - 8; anchors.verticalCenter: parent.verticalCenter; text: modelData.texto; elide: Text.ElideRight; font.pixelSize: 12; textFormat: Text.PlainText }
                        MouseArea { cursorShape: Qt.PointingHandCursor; id: zpp; anchors.fill: parent; hoverEnabled: true
                            onClicked: { pa.hacer(["sh", "-c", "cliphist decode " + modelData.id + " | wl-copy"]); win.vistaAcciones = "botones"; } }
                    }
                }
            }
        }
    }

    // Piezas de la pestana Acciones. Hover gris claro, y al pulsar se encogen y rebotan.
    component Segmento: Rectangle {
        id: seg
        property string icono
        property string texto
        property color colorIcono: Estilo.texto
        property bool ultimo: false
        signal pulsado()
        width: parent.width / 4; height: parent.height
        color: zs.containsMouse ? Estilo.realce : Estilo.nada
        Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
        Column {
            anchors.centerIn: parent
            spacing: 5
            scale: zs.pressed ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: Estilo.t(zs.pressed ? 80 : 400); easing.type: zs.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
            Simbolo { anchors.horizontalCenter: parent.horizontalCenter; text: seg.icono; font.pixelSize: 22; color: seg.colorIcono }
            Texto { anchors.horizontalCenter: parent.horizontalCenter; text: seg.texto; font.pixelSize: 11; color: Estilo.texto2 }
        }
        // Raya que separa del siguiente, del color de la isla
        Rectangle { visible: !seg.ultimo; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Estilo.fondo }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zs; anchors.fill: parent; hoverEnabled: true; onClicked: seg.pulsado() }
    }
    component Interruptor: Rectangle {
        id: itr
        property string icono
        property string texto
        property bool encendido: false
        signal pulsado()
        width: (parent.width - 10) / 2; height: 52; radius: 18
        color: encendido ? Estilo.activo : (zi.containsMouse ? Estilo.realce : Estilo.tarjeta)
        border.width: 1; border.color: encendido ? Estilo.activoBorde : Estilo.linea
        Behavior on color { ColorAnimation { duration: Estilo.t(220) } }
        scale: zi.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zi.pressed ? 80 : 400); easing.type: zi.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
        Simbolo { x: 12; anchors.verticalCenter: parent.verticalCenter; text: itr.icono; font.pixelSize: 21; color: itr.encendido ? Estilo.iconoActivo : Estilo.texto }
        Texto { x: 43; anchors.verticalCenter: parent.verticalCenter; text: itr.texto; font.pixelSize: 12; font.weight: Font.DemiBold; color: itr.encendido ? Estilo.enActivo : Estilo.texto }
        Rectangle {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: 34; height: 20; radius: 10
            color: itr.encendido ? Estilo.enActivo : Estilo.apagado
            Behavior on color { ColorAnimation { duration: Estilo.t(220) } }
            Rectangle {
                y: 3; width: 14; height: 14; radius: 7
                x: itr.encendido ? 17 : 3
                Behavior on x { NumberAnimation { duration: Estilo.t(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
                color: itr.encendido ? Estilo.activo : Estilo.texto2
            }
        }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zi; anchors.fill: parent; hoverEnabled: true; onClicked: itr.pulsado() }
    }
    component BotonIcono: Rectangle {
        id: bi
        property string icono
        signal pulsado()
        width: 46; height: 46; radius: 16
        color: zbi.containsMouse ? Estilo.realce : Estilo.tarjeta
        Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
        scale: zbi.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zbi.pressed ? 80 : 400); easing.type: zbi.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
        Simbolo { anchors.centerIn: parent; text: bi.icono; font.pixelSize: 20 }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zbi; anchors.fill: parent; hoverEnabled: true; onClicked: bi.pulsado() }
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
                Medidor { valor: pr.dato.ramUsada || 0; maximo: pr.dato.ramTotal || 16; anchors.verticalCenter: parent.verticalCenter
                          etiqueta: pr.dato.ramTotal ? "de " + pr.dato.ramTotal.toFixed(1) + " GB" : "RAM" }
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
                colores: ({ "power-saver": "#30d158", "performance": "#ff9f0a" })
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
                        color: zonaP.containsMouse ? Estilo.realce : Estilo.nada
                        Behavior on color { ColorAnimation { duration: Estilo.t(150) } }
                        Image {
                            id: icoP
                            x: 6; width: 20; height: 20; anchors.verticalCenter: parent.verticalCenter
                            sourceSize: Qt.size(48, 48)
                            source: Quickshell.iconPath(modelData[0] === "qs" ? "preferences-desktop" : entrada ? entrada.icon : modelData[0], "application-x-executable")
                        }
                        Texto { x: 34; width: 76; anchors.verticalCenter: parent.verticalCenter; text: nombre; font.pixelSize: 12; elide: Text.ElideRight }
                        Rectangle {
                            x: 116; width: parent.width - 116 - 52; height: 6; radius: 3; color: Estilo.hundido; anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                height: 6; radius: 3
                                width: parent.width * Math.min(1, modelData[1] / 25)
                                Behavior on width { NumberAnimation { duration: Estilo.t(900); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                                gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#9a9a9a" } GradientStop { position: 1; color: "#ffffff" } }
                            }
                        }
                        Texto { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: modelData[1].toFixed(1) + " %"; color: Estilo.texto2; font.pixelSize: 12; font.features: { "tnum": 1 } }
                        MouseArea { id: zonaP; anchors.fill: parent; hoverEnabled: true }
                    }
                }
            }
        }
    }

    // ---- Gota: conversacion con el asistente (se abre con el boton grande) ----
    // Mismo marco que las pestanas: la isla no cambia de tamano. La logica vive en Cerebro.qml.
    component PaginaGota: Item {
        id: pg
        property bool activa
        opacity: activa ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Estilo.t(activa ? 280 : 140) } }
        transform: Translate { y: pg.activa ? 0 : 8; Behavior on y { NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } } }
        onActivaChanged: if (activa) campo.forceActiveFocus()

        // Segundos pensando
        property int segundos: 0
        Timer { interval: 1000; repeat: true; running: Cerebro.ocupada && pg.visible; onTriggered: pg.segundos = Math.round((Date.now() - Cerebro.inicio) / 1000) }
        Connections { target: Cerebro; function onEstadoChanged() { pg.segundos = 0; } }

        // El plan, resumido por carpeta destino: [[icono, texto, detalle]]
        function resumen(plan) {
            if (!plan) return [];
            const casa = Quickshell.env("HOME"), grupos = {}, filas = [];
            let papelera = 0;
            for (const a of plan.acciones) {
                if (a.tipo === "mover") { const d = a.a.replace(/\/[^/]*$/, "").replace(casa, "~"); grupos[d] = (grupos[d] || 0) + 1; }
                else if (a.tipo === "papelera") papelera++;
                else if (a.tipo === "comando") filas.push(["terminal", a.cmd.join(" "), "comando"]);
            }
            const lista = Object.keys(grupos).sort().map(d => ["folder", d.replace(/^.*\//, ""), grupos[d] + (grupos[d] === 1 ? " archivo" : " archivos")]);
            if (papelera) lista.push(["delete", "A la papelera", papelera + (papelera === 1 ? " archivo" : " archivos")]);
            return lista.concat(filas);
        }

        // ---- Cabecera ----
        Item {
            id: cabGota
            width: parent.width; height: 26
            Texto { text: Estilo.gota.nombre; font { pixelSize: 15; weight: Font.DemiBold } anchors.verticalCenter: parent.verticalCenter }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 6
                Texto {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Cerebro.ocupada ? (Cerebro.estado === "aplicando" ? "Aplicando… " : "Pensando… ") + pg.segundos + " s" : ""
                    color: Estilo.texto2; font.pixelSize: 11
                }
                BotonRedondo { icono: Cerebro.ocupada ? "stop" : "edit_square"; tenue: !Cerebro.ocupada && !Cerebro.mensajes.length; onPulsado: Cerebro.ocupada ? Cerebro.detener() : Cerebro.nueva() }
            }
        }

        // ---- Conversacion ----
        ListView {
            id: charla
            anchors { top: cabGota.bottom; topMargin: 6; bottom: entrada.top; bottomMargin: 8; left: parent.left; right: parent.right }
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: Cerebro.mensajes
            onCountChanged: Qt.callLater(positionViewAtEnd)
            footer: Item { width: charla.width; height: pieGota.implicitHeight + 6; Column { id: pieGota; y: 6; width: parent.width; spacing: 8
                // Pensando: lo que hace ahora
                Row {
                    visible: Cerebro.ocupada
                    spacing: 6
                    Simbolo { text: "progress_activity"; color: Estilo.texto2; font.pixelSize: 15; RotationAnimation on rotation { running: Cerebro.ocupada && pg.visible; from: 0; to: 360; duration: 1100; loops: Animation.Infinite } }
                    Texto { text: Cerebro.paso || "Pensando"; color: Estilo.texto2; font.pixelSize: 12 }
                }
                // Plan: espera Hazlo / Cancelar
                Rectangle {
                    visible: Cerebro.estado === "plan"
                    width: parent.width; height: colPlan.implicitHeight + 20
                    radius: 14; color: Estilo.hundido
                    Column {
                        id: colPlan
                        x: 12; y: 10; width: parent.width - 24; spacing: 2
                        Repeater {
                            model: pg.resumen(Cerebro.plan)
                            delegate: Item {
                                required property var modelData
                                width: colPlan.width; height: 24
                                Simbolo { text: modelData[0]; color: Estilo.texto2; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
                                Texto { x: 22; width: parent.width - 120; elide: Text.ElideRight; text: modelData[1]; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                Texto { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: modelData[2]; color: Estilo.texto2; font.pixelSize: 11 }
                            }
                        }
                        Item {
                            width: colPlan.width; height: 30
                            Texto { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 140; elide: Text.ElideRight; text: Cerebro.plan ? Cerebro.plan.resumen || "" : ""; color: Estilo.texto2; font.pixelSize: 11 }
                            Row {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 6
                                BotonTexto { texto: "Cancelar"; onPulsado: Cerebro.cancelar() }
                                BotonTexto { texto: "Hazlo"; blanco: true; onPulsado: Cerebro.hazlo() }
                            }
                        }
                    }
                }
            } }
            delegate: Item {
                id: burbuja
                required property var modelData
                required property int index
                readonly property bool mia: modelData.de === "yo"
                readonly property bool ultima: index === Cerebro.mensajes.length - 1
                width: charla.width
                height: fondoB.height + (acciones.visible ? acciones.height + 6 : 0)
                Rectangle {
                    id: fondoB
                    anchors.right: burbuja.mia ? parent.right : undefined
                    width: Math.min(textoB.implicitWidth, charla.width * (burbuja.mia ? 0.78 : 1)) + (burbuja.mia ? 22 : 0)
                    height: textoB.height + (burbuja.mia ? 14 : 0)
                    radius: 12
                    color: burbuja.mia ? Estilo.tarjeta : "transparent"
                    Texto {
                        id: textoB
                        x: burbuja.mia ? 11 : 0; y: burbuja.mia ? 7 : 0
                        width: Math.min(implicitWidth, charla.width * (burbuja.mia ? 0.78 : 1))
                        wrapMode: Text.Wrap
                        text: burbuja.modelData.texto
                        color: burbuja.mia ? Estilo.texto : Estilo.texto
                        font.pixelSize: 13
                        lineHeight: 1.15
                    }
                }
                // Despues de aplicar un plan: Deshacer y Abrir carpeta
                Row {
                    id: acciones
                    visible: burbuja.modelData.extra === "hecho" && burbuja.ultima
                    anchors.top: fondoB.bottom; anchors.topMargin: 6
                    spacing: 6
                    BotonTexto { visible: Cerebro.puedeDeshacer; texto: "Deshacer"; icono: "undo"; onPulsado: Cerebro.deshacer() }
                    BotonTexto { visible: Cerebro.carpetaPlan !== ""; texto: "Abrir carpeta"; onPulsado: Quickshell.execDetached(["xdg-open", Cerebro.carpetaPlan]) }
                }
            }
        }

        // Sin conversacion: sugerencias
        Column {
            visible: !Cerebro.mensajes.length && !Cerebro.ocupada
            anchors { left: parent.left; right: parent.right; bottom: entrada.top; bottomMargin: 10 }
            spacing: 8
            Texto { text: "¿Qué hago?"; color: Estilo.texto2; font.pixelSize: 12 }
            Flow {
                width: parent.width; spacing: 6
                Repeater {
                    model: ["Acomoda mis descargas", "¿Qué ocupa más espacio?", "¿Cómo está el Bluetooth?", "¿Por qué no suena nada?"]
                    delegate: BotonTexto { required property string modelData; texto: modelData; onPulsado: Cerebro.preguntar(modelData) }
                }
            }
        }

        // ---- Campo para escribir ----
        Rectangle {
            id: entrada
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 38; radius: 13
            color: Estilo.hundido
            border.width: 1; border.color: campo.activeFocus ? Estilo.apagado : "transparent"
            TextInput {
                id: campo
                anchors { left: parent.left; leftMargin: 13; right: enviar.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                clip: true
                color: Estilo.texto; selectionColor: Estilo.texto3
                font { family: Estilo.letra; pixelSize: 13 }
                onTextChanged: Cerebro.escribiendo = text !== ""
                onAccepted: { if (text.trim() && !Cerebro.ocupada) { Cerebro.preguntar(text); text = ""; } }
                Keys.onEscapePressed: { win.conGota = false; win.fijada = false; win.encima = false; }
                Texto { visible: !campo.text; anchors.verticalCenter: parent.verticalCenter; text: Cerebro.ocupada ? "Espera a que termine…" : "Pídele algo a " + Estilo.gota.nombre; color: Estilo.texto3 }
            }
            Rectangle {
                id: enviar
                anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
                width: 28; height: 28; radius: 9
                color: campo.text && !Cerebro.ocupada ? (zEnviar.containsMouse ? Estilo.aclarar(Estilo.acento) : Estilo.acento) : Estilo.hover
                Behavior on color { ColorAnimation { duration: Estilo.t(160) } }
                Simbolo { anchors.centerIn: parent; text: "arrow_upward"; font.pixelSize: 18; color: campo.text && !Cerebro.ocupada ? Estilo.sobreAcento : Estilo.texto3 }
                MouseArea { cursorShape: Qt.PointingHandCursor; id: zEnviar; hoverEnabled: true; anchors.fill: parent; onClicked: campo.accepted() }
            }
        }
    }
    // Boton con texto (y quiza icono): blanco = la accion principal
    component BotonTexto: Rectangle {
        id: bt
        property string texto
        property string icono: ""
        property bool blanco: false
        signal pulsado()
        width: filaBt.implicitWidth + 22; height: 28; radius: 9
        color: blanco ? Estilo.activo : (zbt.containsMouse ? Estilo.realce : Estilo.tarjeta)
        border.width: 1; border.color: blanco ? Estilo.activoBorde : Estilo.linea
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        scale: zbt.pressed ? 0.93 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zbt.pressed ? 80 : 380); easing.type: zbt.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.2) } }
        Row {
            id: filaBt
            anchors.centerIn: parent
            spacing: 4
            Simbolo { visible: bt.icono !== ""; text: bt.icono; font.pixelSize: 15; color: bt.blanco ? Estilo.iconoActivo : Estilo.texto; anchors.verticalCenter: parent.verticalCenter }
            Texto { text: bt.texto; font.pixelSize: 12; color: bt.blanco ? Estilo.enActivo : Estilo.texto; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zbt; anchors.fill: parent; hoverEnabled: true; onClicked: bt.pulsado() }
    }

    // ---------------- Piezas ----------------
    component Texto: Text {
        color: Estilo.texto
        font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
    }
    component Simbolo: Text {
        font { family: "Material Symbols Rounded"; pixelSize: 18 }
        font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 24 }
        renderType: Text.NativeRendering
        color: Estilo.texto
    }
    component Chip: Rectangle {
        id: chip
        property string texto
        property bool blanco: false
        signal pulsado()
        width: tc.implicitWidth + 18; height: 22; radius: 8
        color: blanco ? Estilo.activo : (zc.containsMouse ? Estilo.apagado : Estilo.hover)
        border.width: 1; border.color: blanco ? Estilo.activoBorde : Estilo.linea
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        Texto { id: tc; anchors.centerIn: parent; text: chip.texto; font.pixelSize: 11; color: chip.blanco ? Estilo.enActivo : Estilo.texto }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zc; anchors.fill: parent; hoverEnabled: true; onClicked: chip.pulsado() }
    }
    component BotonRedondo: Rectangle {
        id: br
        property string icono
        property bool grande: false
        property bool blanco: false
        property bool tenue: false
        signal pulsado()
        width: grande ? 44 : 32; height: width; radius: width / 2
        color: blanco ? Estilo.activo : (zb.containsMouse ? Estilo.realce : Estilo.nada)
        border.width: 1; border.color: blanco ? Estilo.activoBorde : Estilo.linea
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        scale: zb.pressed ? 0.86 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zb.pressed ? 80 : 400); easing.type: zb.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
        Simbolo { anchors.centerIn: parent; text: br.icono; font.pixelSize: br.grande ? 26 : 20; color: br.blanco ? Estilo.iconoActivo : br.tenue ? Estilo.texto3 : Estilo.texto }
        MouseArea { cursorShape: Qt.PointingHandCursor; id: zb; anchors.fill: parent; hoverEnabled: true; onClicked: br.pulsado() }
    }
    // Selector con pastilla que se desliza (pestanas y perfil de energia)
    component Selector: Rectangle {
        id: sel
        property var opciones: []          // [[icono, texto, clave], ...]
        property var colores: ({})
        property string elegida
        signal elegir(string clave)
        height: 32; radius: 13; color: Estilo.hundido
        readonly property int indice: Math.max(0, opciones.findIndex(o => o[2] === elegida))
        readonly property bool pinta: !!colores[elegida]     // opcion con color propio (perfiles de energia)
        Rectangle {
            y: 3; height: 26; radius: 10
            width: (sel.width - 6) / Math.max(1, sel.opciones.length)
            x: 3 + width * sel.indice
            color: sel.pinta ? sel.colores[sel.elegida] : Estilo.activo
            border.width: 1; border.color: sel.pinta ? "transparent" : Estilo.activoBorde
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
                    Rectangle {
                        anchors.fill: parent; radius: height / 2
                        color: !on && zs.containsMouse ? Estilo.realce : Estilo.nada
                        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
                    }
                    Row {
                        anchors.centerIn: parent; spacing: 5
                        Simbolo { text: modelData[0]; font.pixelSize: 15; color: on ? (sel.pinta ? "#111111" : Estilo.enActivo) : (zs.containsMouse ? Estilo.texto : Estilo.texto2); anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: Estilo.t(200) } } }
                        Texto { text: modelData[1]; font.pixelSize: 12; color: on ? (sel.pinta ? "#111111" : Estilo.enActivo) : (zs.containsMouse ? Estilo.texto : Estilo.texto2); anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: Estilo.t(200) } } }
                    }
                    MouseArea { cursorShape: Qt.PointingHandCursor; id: zs; anchors.fill: parent; hoverEnabled: true; onClicked: sel.elegir(modelData[2]) }
                }
            }
        }
    }
    // Medidor de la RAM en uso (GB), con marcas como un velocimetro
    component Medidor: Item {
        id: med
        property real valor
        property real maximo
        property string etiqueta
        property real visto: valor
        Behavior on visto { NumberAnimation { duration: Estilo.t(1000); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
        width: 96; height: 96
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {   // pista
                strokeColor: Estilo.hundido; strokeWidth: 8; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 48; centerY: 48; radiusX: 35; radiusY: 35; startAngle: 135; sweepAngle: 270 }
            }
            ShapePath {   // valor
                strokeWidth: 8; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                strokeColor: Estilo.acento
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
                color: mayor ? Estilo.texto3 : Estilo.apagado
                x: 48 + Math.cos(ang) * 44 - width / 2; y: 48 + Math.sin(ang) * 44 - height / 2
                rotation: (135 + index * 13.5) + 90
            }
        }
        Column {
            anchors.centerIn: parent
            Texto { anchors.horizontalCenter: parent.horizontalCenter; text: med.visto.toFixed(1); font.pixelSize: 24; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
            Texto { anchors.horizontalCenter: parent.horizontalCenter; text: med.etiqueta; color: Estilo.texto2; font.pixelSize: 10 }
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
        color: zt.containsMouse ? Estilo.realce : Estilo.tarjeta
        Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
        transform: Translate { y: zt.containsMouse ? -2 : 0; Behavior on y { NumberAnimation { duration: Estilo.t(380); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } } }
        Row { x: 10; y: 8; spacing: 4
            Simbolo { text: tar.icono; font.pixelSize: 13; color: Estilo.texto2; anchors.verticalCenter: parent.verticalCenter }
            Texto { text: tar.titulo; color: Estilo.texto2; font.pixelSize: 11 } }
        Row { x: 10; y: 24; spacing: 3
            Texto { text: tar.valor; font.pixelSize: 17; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
            Texto { text: tar.unidad; color: Estilo.texto3; font.pixelSize: 10; anchors.baseline: parent.children[0].baseline } }
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
                g.strokeStyle = Estilo.texto; g.lineWidth = 1.4; g.lineJoin = "round"; g.stroke();
                g.lineTo(w, 20); g.lineTo(0, 20); g.closePath();
                const gr = g.createLinearGradient(0, 0, 0, 20); gr.addColorStop(0, "rgba(255,255,255,0.18)"); gr.addColorStop(1, "rgba(255,255,255,0)");
                g.fillStyle = gr; g.fill();
                const [lx, ly] = pt(h[h.length - 1], h.length - 1);
                g.fillStyle = Estilo.acento; g.beginPath(); g.arc(lx - 1.5, ly, 2, 0, 7); g.fill();
            }
        }
        onHistChanged: graf.requestPaint()
        MouseArea { id: zt; anchors.fill: parent; hoverEnabled: true }
    }
}
