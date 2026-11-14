import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import "formas.js" as Formas

// Pantalla de bloqueo (aprobada la opcion "como el iPhone"): el fondo desenfocado, la hora arriba,
// en el centro lo que suena (portada a la izquierda, letra a la derecha) y abajo la Gota, el
// usuario y una pildora para la contrasena.
// - Cada tecla: la Gota cambia de forma y color y en la pildora aparece esa misma forma. Solo al
//   pulsar Enter pone la cara de acierto (capsula verde) o de error (trebol).
// - Al entrar: la pantalla sube sola como si se arrastrara; su borde de abajo es liquid glass
//   (vidrio-bloqueo.frag) y detras queda el fondo desenfocado. Luego aparece el escritorio con
//   un fundido: es una foto tomada justo antes de bloquear, asi no salta nada al desbloquear.
// Usa el bloqueo de sesion de Wayland (ext-session-lock): si Quickshell se cae con la pantalla
// bloqueada, niri la deja bloqueada. La contrasena la comprueba PAM con /etc/pam.d/swaylock.
// IPC: "bloqueo bloquear"; "bloqueo ensayo" muestra lo mismo sin bloquear (Esc lo cierra).
Scope {
    id: bloqueo

    property string clave: ""
    property string estado: "escribiendo"          // escribiendo | comprobando | error | dentro
    property bool ensayo: false
    property string fondo: ""
    property int foto: 0                            // cambia con cada bloqueo: recarga las fotos
    property int fotoLista: 0                       // la foto ya escrita (antes no se puede cargar)
    readonly property string carpetaFotos: Quickshell.env("XDG_RUNTIME_DIR")

    // Desbloqueo, en dos tiempos: la hoja sube (0 -> 1) y luego aparece el escritorio (0 -> 1).
    property bool animando: false
    property real subida: 0
    property real aparicion: 0

    // La Gota: forma y color nuevos con cada tecla.
    readonly property var colores: ["#ff3b30", "#ff6a00", "#ff9f0a", "#00c96f", "#14b8a6", "#1186ff", "#a26bff", "#ff2d92", "#94653a"]
    property var gota: Estilo.gota
    function gotaNueva() {
        let f = gota.forma, c = gota.color;
        while (f === gota.forma) f = Formas.LISTA[Math.floor(Math.random() * Formas.LISTA.length)];
        while (c === gota.color) c = colores[Math.floor(Math.random() * colores.length)];
        gota = { forma: f, color: c, cambia: true };
    }

    function preparar() {
        clave = ""; estado = "escribiendo"; animando = false; subida = 0; aparicion = 0;
        formas.clear(); gota = Estilo.gota;
    }
    // Antes de bloquear: cierra lo abierto, espera a que se vaya y saca una foto de cada pantalla.
    function bloquear() {
        if (cerrojo.locked || fotografiar.running) return;
        preparar(); foto++; destino = "bloquear"; esperaFoto.restart();
    }
    function ensayar() { preparar(); foto++; destino = "ensayo"; esperaFoto.restart(); }
    // Solo en el ensayo: hace como si la contrasena fuera buena, para ver la salida.
    function ensayarSalida() { if (ensayo && !animando) { estado = "dentro"; clave = ""; entrar.restart(); } }
    property string destino: ""
    Timer { id: esperaFoto; interval: 320; onTriggered: { leerFondo.running = true; fotografiar.running = true; } }
    Process {
        id: fotografiar
        command: ["sh", "-c", "rm -f \"$1\"/menisco-bloqueo-*.png; for o in $(niri msg -j outputs | jq -r 'keys[]'); do grim -o \"$o\" \"$1/menisco-bloqueo-$o-$2.png\"; done",
                  "sh", bloqueo.carpetaFotos, String(bloqueo.foto)]
        // Pase lo que pase con la foto, se bloquea igual.
        onExited: { bloqueo.fotoLista = bloqueo.foto; if (bloqueo.destino === "bloquear") cerrojo.locked = true; else bloqueo.ensayo = true; }
    }
    Process {
        id: leerFondo
        command: ["sh", "-c", "awww query 2>/dev/null | sed -n 's/.*image: //p' | head -1"]
        stdout: StdioCollector { onStreamFinished: bloqueo.fondo = text.trim() }
    }

    // ---- Contrasena ----
    ListModel { id: formas }       // una forma por letra: { forma, tinte }
    function teclear(ev) {
        if (estado === "comprobando" || estado === "dentro" || animando) return;
        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { comprobar(); return; }
        if (ev.key === Qt.Key_Escape) {
            if (ensayo && !clave) { ensayo = false; return; }
            clave = ""; formas.clear(); estado = "escribiendo"; gota = Estilo.gota; return;
        }
        if (ev.key === Qt.Key_Backspace) {
            if (!clave) return;
            clave = clave.slice(0, -1); if (formas.count > clave.length) formas.remove(formas.count - 1);
            estado = "escribiendo"; gotaNueva(); return;
        }
        if (ev.text && ev.text.length === 1 && ev.text.charCodeAt(0) >= 32) {
            if (estado === "error") formas.clear();
            clave += ev.text; estado = "escribiendo"; gotaNueva();
            if (formas.count < 16) formas.append({ forma: gota.forma, tinte: gota.color });
        }
    }
    function comprobar() {
        if (!clave) return;
        estado = "comprobando";
        pam.start();
    }
    PamContext {
        id: pam
        config: "swaylock"
        onResponseRequiredChanged: if (responseRequired) respond(bloqueo.clave)
        onCompleted: result => {
            if (result === PamResult.Success) { bloqueo.estado = "dentro"; bloqueo.clave = ""; entrar.restart(); }
            else bloqueo.fallo();
        }
        onError: bloqueo.fallo()
    }
    function fallo() { clave = ""; estado = "error"; borrarFormas.restart(); }
    Timer { id: borrarFormas; interval: 650; onTriggered: formas.clear() }

    SequentialAnimation {
        id: entrar
        PauseAnimation { duration: 380 }                  // que se vea la cara de acierto
        ScriptAction { script: bloqueo.animando = true }
        NumberAnimation { target: bloqueo; property: "subida"; from: 0; to: 1; duration: Estilo.t(820); easing.type: Easing.InOutCubic }
        NumberAnimation { target: bloqueo; property: "aparicion"; from: 0; to: 1; duration: Estilo.t(420); easing.type: Easing.OutCubic }
        ScriptAction {
            script: {
                if (bloqueo.ensayo) bloqueo.ensayo = false; else cerrojo.locked = false;
                Quickshell.execDetached(["sh", "-c", "rm -f \"$1\"/menisco-bloqueo-*.png", "sh", bloqueo.carpetaFotos]);
            }
        }
    }

    WlSessionLock {
        id: cerrojo
        WlSessionLockSurface {
            id: superficie
            color: "black"
            Pantalla { anchors.fill: parent; nombre: superficie.screen ? superficie.screen.name : "" }
        }
    }

    // Ensayo: lo mismo en una ventana comun, sin bloquear la sesion.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: ventanaEnsayo
            required property var modelData
            screen: modelData
            visible: bloqueo.ensayo
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "bloqueo-ensayo"
            WlrLayershell.keyboardFocus: bloqueo.ensayo ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "black"
            Pantalla { anchors.fill: parent; nombre: ventanaEnsayo.modelData.name }
        }
    }

    // ---------------- Una pantalla ----------------
    component Pantalla: Item {
        id: pan
        property string nombre
        focus: true
        Keys.onPressed: ev => { bloqueo.teclear(ev); ev.accepted = true; }
        Component.onCompleted: forceActiveFocus()

        Image {
            id: imagen
            anchors.fill: parent
            source: bloqueo.fondo ? "file://" + bloqueo.fondo : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 1280
            asynchronous: true
            visible: false
        }

        // Lo de detras: el fondo desenfocado y, al final, el escritorio que aparece.
        Item {
            id: detras
            anchors.fill: parent
            visible: bloqueo.animando
            MultiEffect {
                anchors.fill: parent
                source: imagen
                blurEnabled: true; blur: 1 - bloqueo.aparicion; blurMax: 64
            }
            Image {
                anchors.fill: parent
                source: pan.nombre && bloqueo.fotoLista > 0 ? "file://" + bloqueo.carpetaFotos + "/menisco-bloqueo-" + pan.nombre + "-" + bloqueo.fotoLista + ".png" : ""
                cache: false; asynchronous: true
                opacity: bloqueo.aparicion
            }
        }

        // La pantalla de bloqueo en si.
        Item {
            id: hoja
            anchors.fill: parent
            MultiEffect {
                anchors.fill: parent
                source: imagen
                blurEnabled: true; blur: 1; blurMax: 64
                saturation: 0.15; brightness: -0.22
            }
            Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.25 }

            // Fecha y hora
            SystemClock { id: reloj; precision: SystemClock.Seconds }
            Column {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.08 }
                spacing: -6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: reloj.date.toLocaleDateString(Qt.locale("es_MX"), "dddd d 'de' MMMM")
                    color: "#ffffff"; opacity: 0.85
                    font { family: Estilo.letra; pixelSize: 22; weight: Font.DemiBold }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(reloj.date, Estilo.valor("reloj12") ? "h:mm" : "H:mm")
                    color: "#ffffff"
                    font { family: "SF Pro Display"; pixelSize: 128; weight: Font.Light; letterSpacing: -3; features: { "tnum": 1 } }
                }
            }

            Musica { anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: parent.height * 0.02 } }

            // Abajo: la Gota, el usuario y la contrasena
            Column {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: parent.height * 0.1 }
                spacing: 12
                Rectangle {
                    id: nido
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64; height: 64; radius: 32; color: "#000000"
                    border.width: 1; border.color: zonaGota.containsMouse ? "#66ffffff" : "#33ffffff"
                    Behavior on border.color { ColorAnimation { duration: Estilo.t(160) } }
                    scale: zonaGota.pressed ? 0.88 : zonaGota.containsMouse ? 1.06 : 1
                    Behavior on scale { NumberAnimation { duration: Estilo.t(zonaGota.pressed ? 90 : 420); easing.type: zonaGota.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.6) } }
                    Asistente {
                        anchors.centerIn: parent
                        width: 56; height: 56
                        fondoNegro: true
                        gota: bloqueo.gota
                        emocion: bloqueo.estado === "error" ? "confuso" : bloqueo.estado === "dentro" ? "feliz" : "normal"
                    }
                    // Un toque: otra forma, por gusto.
                    MouseArea { id: zonaGota; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { pan.forceActiveFocus(); if (bloqueo.estado !== "comprobando" && bloqueo.estado !== "dentro") bloqueo.gotaNueva(); } }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Quickshell.env("USER")
                    color: "#ffffff"; font { family: Estilo.letra; pixelSize: 15; weight: Font.DemiBold }
                }
                Pildora { anchors.horizontalCenter: parent.horizontalCenter; foco: pan }
            }
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 28 }
                text: bloqueo.ensayo ? "Ensayo · Esc para salir" : "Escriba su contraseña y pulse Enter"
                color: "#ffffff"; opacity: 0.5
                font { family: Estilo.letra; pixelSize: 12 }
            }
        }

        // Desbloqueo: el shader dibuja la hoja subiendo con su borde de vidrio sobre lo de detras.
        ShaderEffectSource { id: texHoja; sourceItem: hoja; hideSource: bloqueo.animando; live: true; visible: false }
        ShaderEffectSource { id: texDetras; sourceItem: detras; hideSource: bloqueo.animando; live: true; visible: false }
        ShaderEffect {
            anchors.fill: parent
            visible: bloqueo.animando
            property var hoja: texHoja
            property var detras: texDetras
            property size tam: Qt.size(width, height)
            property real borde: height * (1 - bloqueo.subida)
            property real radio: 56
            property real banda: 150
            property real fuerza: 70
            property real croma: 0.45
            fragmentShader: Qt.resolvedUrl("vidrio-bloqueo.frag.qsb")
        }
    }

    // ---------------- Pildora de la contrasena ----------------
    component Pildora: Rectangle {
        id: pil
        property Item foco
        width: 280; height: 46; radius: 23
        readonly property bool mal: bloqueo.estado === "error"
        color: mal ? "#59ff453a" : zonaPil.containsMouse ? "#3dffffff" : "#2effffff"
        border.width: 1; border.color: mal ? "#b3ff453a" : zonaPil.containsMouse ? "#73ffffff" : "#40ffffff"
        Behavior on color { ColorAnimation { duration: Estilo.t(180) } }
        Behavior on border.color { ColorAnimation { duration: Estilo.t(180) } }
        scale: zonaPil.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zonaPil.pressed ? 80 : 380); easing.type: zonaPil.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
        transform: Translate { id: temblor }
        SequentialAnimation {
            running: pil.mal
            NumberAnimation { target: temblor; property: "x"; to: -14; duration: 50 }
            NumberAnimation { target: temblor; property: "x"; to: 12; duration: 70 }
            NumberAnimation { target: temblor; property: "x"; to: -8; duration: 60 }
            NumberAnimation { target: temblor; property: "x"; to: 5; duration: 50 }
            NumberAnimation { target: temblor; property: "x"; to: 0; duration: 60 }
        }
        MouseArea { id: zonaPil; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.IBeamCursor; onClicked: if (pil.foco) pil.foco.forceActiveFocus() }

        Text {
            anchors.centerIn: parent
            opacity: formas.count === 0 ? (pil.mal ? 0.95 : 0.55) : 0
            Behavior on opacity { NumberAnimation { duration: Estilo.t(160) } }
            text: pil.mal ? "Contraseña incorrecta" : "Contraseña"
            color: "#ffffff"; font { family: Estilo.letra; pixelSize: 14 }
        }
        // Mientras comprueba, las formas hacen una ola.
        property real fase: 0
        NumberAnimation on fase { running: bloqueo.estado === "comprobando"; from: 0; to: Math.PI * 2; duration: 900; loops: Animation.Infinite }
        ListView {
            id: lista
            anchors.centerIn: parent
            width: Math.min(contentWidth, pil.width - 36); height: 20
            orientation: ListView.Horizontal
            interactive: false
            spacing: 6
            model: formas
            delegate: Item {
                id: f
                required property string forma
                required property string tinte
                required property int index
                width: 14; height: 20
                Shape {
                    id: dibujo
                    anchors.centerIn: parent
                    width: 14; height: 14
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real ola: bloqueo.estado === "comprobando" ? Math.max(0, Math.sin(pil.fase - f.index * 0.55)) : 0
                    y: -ola * 4
                    // La forma nace del color que tomo la Gota y se queda blanca; si falla, roja.
                    property color pintura: f.tinte
                    Timer { running: true; interval: 420; onTriggered: dibujo.pintura = "#ffffff" }
                    ShapePath {
                        fillColor: pil.mal ? "#ff6961" : dibujo.pintura
                        Behavior on fillColor { ColorAnimation { duration: Estilo.t(380) } }
                        strokeWidth: -1
                        PathPolyline {
                            path: {
                                const r = Formas.radios(f.forma), n = r.length, pts = [];
                                for (let i = 0; i <= n; i += 4) {
                                    const j = i % n, t = j / n * Math.PI * 2;
                                    pts.push(Qt.point(7 + Math.cos(t) * r[j] * 7, 7 - Math.sin(t) * r[j] * 7));
                                }
                                return pts;
                            }
                        }
                    }
                }
            }
            // Nace girando desde nada y se pasa un poco; al borrar se encoge.
            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "scale"; from: 0; to: 1; duration: Estilo.t(420); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(3) }
                    NumberAnimation { property: "rotation"; from: -120; to: 0; duration: Estilo.t(480); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(1.6) }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Estilo.t(140) }
                }
            }
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "scale"; to: 0; duration: Estilo.t(200); easing.type: Easing.InBack }
                    NumberAnimation { property: "opacity"; to: 0; duration: Estilo.t(200) }
                }
            }
            displaced: Transition { NumberAnimation { property: "x"; duration: Estilo.t(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
            Behavior on width { NumberAnimation { duration: Estilo.t(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
        }
        // Cursor que parpadea: dice que la pildora escucha.
        Rectangle {
            width: 2; height: 20; radius: 1; color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
            x: formas.count ? lista.x + lista.width + 6 : pil.width / 2 - 50
            Behavior on x { NumberAnimation { duration: Estilo.t(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
            visible: bloqueo.estado === "escribiendo"
            SequentialAnimation on opacity { running: parent.visible; loops: Animation.Infinite
                NumberAnimation { to: 0; duration: 500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine } }
        }
    }

    // ---------------- Lo que suena: portada y letra ----------------
    component Musica: Row {
        id: mu
        // Lo que suena; si nada suena, el ultimo reproductor de musica (los navegadores, al final).
        readonly property var r: Mpris.players.values.find(p => p.isPlaying)
            ?? Mpris.players.values.find(p => p.trackTitle && !/chrom|firefox|helium|zen|brave/i.test(p.identity + p.desktopEntry))
            ?? Mpris.players.values.find(p => p.trackTitle) ?? null
        visible: !!r && !!r.trackTitle
        spacing: 56
        Timer { interval: 250; repeat: true; running: mu.visible && mu.r && mu.r.isPlaying; onTriggered: mu.r.positionChanged() }

        // Letra sincronizada (letra.sh: LRCLIB y NetEase), igual que en la isla.
        property var letra: []
        property string letraDe: ""
        readonly property string cancion: r && r.trackTitle ? r.trackTitle + "|" + (r.trackArtist || "") : ""
        readonly property int actual: {
            let i = -1;
            const pos = r ? r.position + 0.3 : 0;
            for (let k = 0; k < letra.length && letra[k][0] <= pos; k++) i = k;
            return i;
        }
        function buscar() {
            if (!cancion || cancion === letraDe || buscador.running) return;
            letraDe = cancion; letra = [];
            buscador.command = [Estilo.carpeta + "/letra.sh", r.trackTitle, r.trackArtist || "", String(Math.round(r.length || 0)), Estilo.valor("letraNetease") ? "1" : "0"];
            buscador.running = true;
        }
        onCancionChanged: buscar()
        Component.onCompleted: buscar()
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
                        if (/^\[.*\]$/.test(m[3]) || (out.length === 0 && /\s[:：]\s/.test(m[3]))) continue;
                        out.push([Number(m[1]) * 60 + Number(m[2]), m[3]]);
                    }
                    mu.letra = out;
                }
            }
            onExited: if (mu.cancion !== mu.letraDe) mu.buscar()
        }

        // Portada (un toque: pausa o sigue)
        Rectangle {
            id: portada
            width: 300; height: 300; radius: 26; color: "#22ffffff"
            clip: true
            scale: zonaPortada.pressed ? 0.95 : 1
            Behavior on scale { NumberAnimation { duration: Estilo.t(zonaPortada.pressed ? 90 : 420); easing.type: zonaPortada.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.2) } }
            Image {
                anchors.fill: parent
                source: mu.r ? mu.r.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(600, 600)
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: mascara }
            }
            Rectangle { id: mascara; anchors.fill: parent; radius: 26; visible: false; layer.enabled: true }
            MouseArea { id: zonaPortada; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (mu.r && mu.r.canTogglePlaying) mu.r.togglePlaying() }
        }

        // Letra, centrada: la que suena grande y blanca; las de alrededor apagadas, subiendo en ola.
        Item {
            id: zonaLetra
            width: 560; height: portada.height
            clip: true
            readonly property real paso: 46
            Repeater {
                model: mu.letra.length
                delegate: Text {
                    id: linea
                    required property int index
                    readonly property int distancia: index - mu.actual
                    visible: distancia >= -2 && distancia <= 3
                    width: zonaLetra.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: mu.letra[index][1]
                    color: "#ffffff"
                    font { family: Estilo.letra; pixelSize: 28; weight: Font.Bold }
                    y: zonaLetra.height / 2 - height / 2 + distancia * zonaLetra.paso
                    opacity: distancia === 0 ? 1 : Math.abs(distancia) === 1 ? 0.35 : 0.15
                    scale: distancia === 0 ? 1 : 0.86
                    Behavior on y { NumberAnimation { duration: Estilo.t(620 + Math.max(0, linea.distancia) * 70); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } }
                    Behavior on opacity { NumberAnimation { duration: Estilo.t(420) } }
                    Behavior on scale { NumberAnimation { duration: Estilo.t(520); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(1.4) } }
                }
            }
            // Sin letra: titulo y artista, centrados.
            Column {
                visible: mu.letra.length === 0
                anchors.centerIn: parent
                width: parent.width
                spacing: 6
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: mu.r ? mu.r.trackTitle : ""; color: "#ffffff"; font { family: Estilo.letra; pixelSize: 28; weight: Font.Bold } }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: mu.r ? mu.r.trackArtist || "" : ""; color: "#ffffff"; opacity: 0.6; font { family: Estilo.letra; pixelSize: 18 } }
            }
        }
    }
}
