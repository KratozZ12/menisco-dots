// Tipografia SF Pro (Estilo.letra); iconos Material Symbols Rounded; grises de Menisco.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

// Barra lateral (centro de control): entra por la derecha con Super+A y se va con Escape.
// Pagina principal: hora, botones rapidos, sonido, musica, calendario y energia.
// Subpaginas: Bluetooth, Red y Salida de sonido.
PanelWindow {
    id: barra

    required property var raiz
    required property var ajustes       // comparte No molestar y Modo cafe con la ventana de ajustes

    readonly property bool abierta: raiz.barraAbierta
    property string pagina: "inicio"
    property string confirmar: ""        // "reiniciar" o "apagar" esperan un segundo clic

    // Lado, altura y ancho salen de los ajustes (seccion Barra lateral).
    readonly property var cfg: Estilo.barra
    readonly property bool derecha: cfg.lado !== "izquierda"
    anchors.right: derecha
    anchors.left: !derecha
    // La ventana es mas grande que el panel (holgura a cada lado): cuando el rebote lo agranda
    // un poco, no choca con los bordes de la ventana ni se ve cortado.
    readonly property int holgura: 24
    implicitWidth: cfg.ancho + holgura * 2
    // Alto fijo (toda la pantalla): si la ventana cambiara de alto con cada pagina, niri tendria
    // que reconfigurarla en cada cuadro de la animacion y se veia a saltos. Solo el panel cambia;
    // la mascara hace que el resto no reciba clics.
    implicitHeight: screen ? screen.height : 1080
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "barra"
    WlrLayershell.keyboardFocus: abierta ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    visible: abierta || panel.mostrar > 0.01
    mask: Region { x: panel.x; y: panel.y; width: panel.width; height: panel.height }

    onAbiertaChanged: {
        if (abierta) { pagina = "inicio"; confirmar = ""; leerRed.running = true; panel.forceActiveFocus(); }
        else if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false;
    }
    function cerrar() { raiz.barraAbierta = false }
    function ejecutar(cmd) { Quickshell.execDetached(cmd) }
    function ir(p) {
        pagina = p;
        if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = p === "bt";
        if (p === "red") leerRed.running = true;
    }

    // ---- Red (NetworkManager) ----
    property var cables: []     // [{ dispositivo, conectado, velocidad }]
    property var redesWifi: []  // [{ ssid, senal, segura, activa }]
    property bool hayWifi: false
    Process {
        id: leerRed
        running: true   // al arrancar, para que el boton Red no cambie de color mientras la barra entra
        command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE device; echo ---; " +
            "for d in /sys/class/net/*; do [ -f $d/speed ] && echo \"$(basename $d):$(cat $d/speed 2>/dev/null)\"; done; echo ---; " +
            "nmcli -t -f ACTIVE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [dev, vel, wifi] = text.split("---\n").map(s => (s || "").trim().split("\n").filter(l => l));
                const velocidades = {};
                for (const l of vel) { const [d, s] = l.split(":"); velocidades[d] = parseInt(s); }
                barra.cables = dev.map(l => l.split(":")).filter(c => c[1] === "ethernet")
                    .map(c => ({ dispositivo: c[0], conectado: c[2] === "connected", velocidad: velocidades[c[0]] || 0 }));
                barra.hayWifi = dev.some(l => l.split(":")[1] === "wifi");
                const vistas = {};
                barra.redesWifi = wifi.map(l => l.split(":")).filter(w => w[1] && !vistas[w[1]] && (vistas[w[1]] = true))
                    .map(w => ({ activa: w[0] === "yes", ssid: w[1], senal: parseInt(w[2]) || 0, segura: !!w[3] }));
            }
        }
    }
    property string redPidiendo: ""     // SSID que espera contrasena
    function conectarWifi(ssid, clave) {
        ejecutar(clave ? ["nmcli", "device", "wifi", "connect", ssid, "password", clave] : ["nmcli", "device", "wifi", "connect", ssid]);
        redPidiendo = "";
        releerRed.restart();
    }
    Timer { id: releerRed; interval: 2500; onTriggered: leerRed.running = true }

    // ---- Sonido ----
    readonly property var salida: Pipewire.defaultAudioSink
    readonly property var entrada: Pipewire.defaultAudioSource
    readonly property var salidas: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var apps: Pipewire.nodes.values.filter(n => n.isSink && n.isStream && n.audio)
    // Nombre legible de un flujo de audio: "PipeWire ALSA [sonora]" -> "Sonora".
    function nombreApp(n) {
        const s = n.properties["application.name"] || n.name || "";
        const m = s.match(/\[(.+)\]/);
        const r = m ? m[1] : s;
        return r.charAt(0).toUpperCase() + r.slice(1);
    }
    // Una fila por app aunque abra varios flujos (Sonora abre tres): el deslizador mueve todos.
    readonly property var appsAgrupadas: {
        const g = {};
        for (const n of apps) (g[nombreApp(n)] = g[nombreApp(n)] || []).push(n);
        return Object.keys(g).map(k => ({ nombre: k, nodos: g[k] }));
    }
    PwObjectTracker { objects: [barra.salida, barra.entrada].concat(barra.apps) }

    readonly property var reproductor: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    SystemClock { id: reloj; precision: SystemClock.Minutes }

    // ---- Panel ----
    Rectangle {
        id: panel
        // Alto = pagina visible + botones de energia (solo en inicio); se anima al cambiar de pagina.
        readonly property real altoPagina: [pInicio, pBt, pRed, pSonido].find(p => p.activa).implicitHeight
        property real alto: 28 + altoPagina
        // Solo al cambiar de pagina: al abrir, el alto ya debe ser el final (si no, se ve crecer).
        Behavior on alto { enabled: panel.mostrar > 0.99; NumberAnimation { duration: Estilo.t(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
        width: barra.cfg.ancho
        height: Math.min(alto, parent.height - barra.holgura * 2)
        x: barra.derecha ? parent.width - width - (barra.holgura - 14) : barra.holgura - 14
        // Arriba: bajo la isla. Abajo: sobre el dock. Centro: al medio.
        y: barra.cfg.altura === "arriba" ? 56
         : barra.cfg.altura === "abajo" ? parent.height - height - 96
         : (parent.height - height) / 2
        radius: 24
        color: Estilo.fondo
        border.color: "#3a3a3a"
        border.width: 1
        clip: true
        // Apertura: llega desde la derecha recorriendo solo 48 px, crece desde 0.92 con el
        // borde derecho como eje, y aparece con fundido; el rebote cabe en la holgura de la ventana.
        // Cierre: corto y sin rebote. "mostrar" va de 0 a 1 y de ella sale todo.
        property real mostrar: 0
        states: State { name: "abierta"; when: barra.abierta; PropertyChanges { target: panel; mostrar: 1 } }
        transitions: [
            Transition { to: "abierta"; NumberAnimation { property: "mostrar"; duration: Estilo.t(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote } },
            // Cierre: arranca de inmediato y frena al final; el fundido acompana todo el recorrido.
            Transition { from: "abierta"; NumberAnimation { property: "mostrar"; duration: Estilo.t(300); easing.type: Easing.OutCubic } }
        ]
        opacity: barra.abierta ? Math.min(1, mostrar * 2.2) : mostrar
        transformOrigin: barra.derecha ? Item.Right : Item.Left
        scale: 0.92 + 0.08 * mostrar
        transform: Translate { x: (1 - panel.mostrar) * 48 * (barra.derecha ? 1 : -1) }
        focus: barra.abierta
        Keys.onEscapePressed: barra.pagina === "inicio" ? barra.cerrar() : barra.ir("inicio")

        // Paginas: entran deslizandose desde el lado hacia el que se navega.
        Item {
            anchors { fill: parent; margins: 14 }

            Pagina {
                id: pInicio
                activa: barra.pagina === "inicio"
                lado: -1
                // Mismo aire entre todas las secciones, en cualquier orden que se pongan.
                spacing: 14

                // Hora y fecha
                Item {
                    width: parent.width; height: 52
                    Column {
                        Texto { text: Qt.formatTime(reloj.date, Estilo.valor("reloj12") ? "h:mm AP" : "H:mm"); font.pixelSize: 24; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
                        Texto { text: Qt.locale("es_MX").toString(reloj.date, "dddd d 'de' MMMM"); color: "#888"; font.pixelSize: 12 }
                    }
                    Redondo { anchors { right: parent.right; verticalCenter: parent.verticalCenter } icono: "tune"; onPulsado: { barra.cerrar(); barra.raiz.abrirAjustes(); } }
                }

                // Secciones visibles en el orden elegido en los ajustes.
                Repeater {
                    model: barra.cfg.secciones.filter(s => s.ver)
                    delegate: Loader {
                        required property var modelData
                        width: pInicio.width
                        sourceComponent: ({ rapidos: cRapidos, sonido: cSonido, musica: cMusica, calendario: cCalendario, energia: cEnergia })[modelData.id] ?? null
                    }
                }
            }

            Pagina {
                id: pBt
                activa: barra.pagina === "bt"
                Volver { text: "Bluetooth" }
                Rapido {
                    width: parent.width
                    icono: "bluetooth"; titulo: activa ? "Encendido" : "Apagado"; detalle: ""
                    activa: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false
                    onPulsado: Estilo.bluetooth(Bluetooth.defaultAdapter, !activa)
                }
                Encabezado { text: "Mis dispositivos"; visible: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled }
                Repeater {
                    model: Bluetooth.devices.values.filter(d => d.paired && Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled)
                    delegate: FilaLista {
                        required property var modelData
                        icono: modelData.icon && modelData.icon.includes("headset") || modelData.icon === "audio-headphones" ? "headphones"
                             : modelData.icon && modelData.icon.includes("audio") ? "speaker" : "devices_other"
                        titulo: modelData.name
                        detalle: modelData.pairing ? "Emparejando…"
                               : modelData.connected ? "Conectado" + (modelData.batteryAvailable ? " · " + Math.round(modelData.battery * 100) + " %" : "")
                               : "Toque para conectar"
                        marcada: modelData.connected
                        onPulsada: modelData.connected ? modelData.disconnect() : modelData.connect()
                    }
                }
                Encabezado { text: "Buscando cerca…"; visible: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled }
                Repeater {
                    model: Bluetooth.devices.values.filter(d => !d.paired && d.name && Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled).slice(0, 6)
                    delegate: FilaLista {
                        required property var modelData
                        icono: "devices_other"; titulo: modelData.name
                        detalle: modelData.pairing ? "Emparejando…" : "Toque para emparejar"
                        tenue: true
                        onPulsada: { modelData.trusted = true; modelData.pair(); }
                    }
                }
            }

            Pagina {
                id: pRed
                activa: barra.pagina === "red"
                Volver { text: "Red" }
                Repeater {
                    model: barra.cables
                    delegate: FilaLista {
                        required property var modelData
                        icono: "lan"; titulo: "Cable (" + modelData.dispositivo + ")"
                        detalle: modelData.conectado ? "Conectado" + (modelData.velocidad > 0 ? " · " + (modelData.velocidad >= 1000 ? modelData.velocidad / 1000 + " Gb/s" : modelData.velocidad + " Mb/s") : "") : "Desconectado"
                        marcada: modelData.conectado
                    }
                }
                Encabezado { text: "Wi-Fi" }
                Texto {
                    visible: !barra.hayWifi
                    width: parent.width; wrapMode: Text.Wrap; color: "#888"; font.pixelSize: 12; leftPadding: 8; rightPadding: 8
                    text: "Este equipo no tiene Wi-Fi."
                }
                Repeater {
                    model: barra.hayWifi ? barra.redesWifi.slice(0, 10) : []
                    delegate: Column {
                        required property var modelData
                        width: parent.width
                        FilaLista {
                            icono: modelData.senal > 66 ? "network_wifi" : modelData.senal > 33 ? "network_wifi_2_bar" : "network_wifi_1_bar"
                            titulo: modelData.ssid
                            detalle: modelData.activa ? "Conectada" : modelData.segura ? "Protegida" : "Abierta"
                            marcada: modelData.activa
                            onPulsada: if (!modelData.activa) { if (modelData.segura) barra.redPidiendo = modelData.ssid; else barra.conectarWifi(modelData.ssid, ""); }
                        }
                        Rectangle {
                            visible: barra.redPidiendo === modelData.ssid
                            width: parent.width; height: visible ? 38 : 0; radius: 12; color: "#1b1b1b"
                            TextInput {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                color: "#fff"; font { family: Estilo.letra; pixelSize: 13 }
                                focus: parent.visible
                                onAccepted: barra.conectarWifi(modelData.ssid, text)
                                Texto { visible: !parent.text; text: "Contraseña y Enter"; color: "#777"; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                }
            }

            Pagina {
                id: pSonido
                activa: barra.pagina === "sonido"
                Volver { text: "Salida de sonido" }
                Repeater {
                    model: barra.salidas
                    delegate: FilaLista {
                        required property var modelData
                        readonly property string nombre: modelData.nickname || modelData.description || modelData.name
                        icono: /blue|buds|head|auric/i.test(modelData.name + nombre) ? "headphones" : /hdmi|display/i.test(modelData.name + nombre) ? "tv" : "speaker"
                        titulo: nombre
                        detalle: ""
                        marcada: barra.salida === modelData
                        onPulsada: Pipewire.preferredDefaultAudioSink = modelData
                    }
                }
                Encabezado { text: "Apps"; visible: barra.appsAgrupadas.length > 0 }
                Column {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: barra.appsAgrupadas
                        delegate: Nivel {
                            required property var modelData
                            etiqueta: modelData.nombre
                            valor: modelData.nodos[0].audio ? Math.min(1, modelData.nodos[0].audio.volume) : 0
                            onCambiar: v => modelData.nodos.forEach(n => { if (n.audio) n.audio.volume = v; })
                        }
                }
                }
            }
        }

    }

    // ---- Secciones de la pagina principal (se ordenan y ocultan desde los ajustes) ----
    // Que hace cada boton rapido; los ids son los que se eligen en los ajustes.
    function rapido(id) {
        const bt = Bluetooth.defaultAdapter, btOn = bt ? bt.enabled : false;
        const conectado = Bluetooth.devices.values.find(d => d.connected);
        const cable = cables.some(c => c.conectado), wifi = redesWifi.find(w => w.activa);
        const m = (s) => String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
        switch (id) {
        case "red": return { icono: cable ? "lan" : "wifi", titulo: "Red", flecha: true, activa: cable || !!wifi,
                             detalle: cable ? "Cable conectado" : wifi ? wifi.ssid : "Sin conexión", fn: () => ir("red") };
        case "bt": return { icono: "bluetooth", titulo: "Bluetooth", flecha: true, activa: btOn,
                            detalle: !btOn ? "Apagado" : conectado ? conectado.name : "Encendido", fn: () => ir("bt") };
        case "dnd": return { icono: "dark_mode", titulo: "No molestar", activa: ajustes.noMolestar,
                             detalle: ajustes.noMolestar ? "Activado" : "Apagado", fn: () => Estilo.poner("noMolestar", !ajustes.noMolestar) };
        case "cafe": return { icono: "coffee", titulo: "Modo café", activa: ajustes.cafe,
                              detalle: ajustes.cafe ? "Sin suspender" : "Apagado", fn: () => ajustes.cafe = !ajustes.cafe };
        case "captura": return { icono: "screenshot_region", titulo: "Captura", activa: false, detalle: "Elegir zona",
                                 fn: () => { cerrar(); ejecutar(["sh", "-c", "sleep 0.5; niri msg action screenshot"]); } };
        case "isla": return { icono: "pill", titulo: "Isla", activa: raiz.islaVisible, detalle: raiz.islaVisible ? "Visible" : "Oculta",
                              fn: () => raiz.islaVisible = !raiz.islaVisible };
        case "vidrio": return { icono: "water_drop", titulo: "Liquid glass", activa: ajustes.vidrio, detalle: ajustes.vidrio ? "Activado" : "Apagado",
                                fn: () => ajustes.alternarVidrio(!ajustes.vidrio) };
        case "grabar": return { icono: raiz.grabando ? "stop_circle" : "videocam", titulo: raiz.grabando ? "Grabando" : "Grabar pantalla",
                                activa: raiz.grabando, detalle: raiz.grabando ? m(raiz.segundosGrabando) : "Con sonido",
                                fn: () => { if (!raiz.grabando) cerrar(); raiz.alternarGrabacion(); } };
        }
        return null;
    }

    Component {
        id: cRapidos
        Grid {
            id: botones
            columns: 2; spacing: 8
            readonly property real ancho: (width - 8) / 2
            Repeater {
                model: barra.cfg.rapidos
                delegate: Rapido {
                    required property string modelData
                    readonly property var info: barra.rapido(modelData) || ({})
                    width: botones.ancho
                    icono: info.icono || ""; titulo: info.titulo || ""; detalle: info.detalle || ""
                    activa: !!info.activa; flecha: !!info.flecha
                    onPulsado: if (info.fn) info.fn()
                }
            }
        }
    }

    Component {
        id: cSonido
        Column {
            spacing: 8
            Encabezado { text: "Sonido"; topPadding: 0; bottomPadding: -2 }
            Nivel {
                icono: barra.salida && barra.salida.audio && barra.salida.audio.muted ? "volume_off" : "volume_up"
                valor: barra.salida && barra.salida.audio ? Math.min(1, barra.salida.audio.volume) : 0
                onCambiar: v => { if (barra.salida && barra.salida.audio) { barra.salida.audio.muted = false; barra.salida.audio.volume = v; } }
                onIcono_pulsado: if (barra.salida && barra.salida.audio) barra.salida.audio.muted = !barra.salida.audio.muted
                flecha: true; onFlecha_pulsada: barra.ir("sonido")
            }
            Nivel {
                icono: barra.entrada && barra.entrada.audio && barra.entrada.audio.muted ? "mic_off" : "mic"
                valor: barra.entrada && barra.entrada.audio ? Math.min(1, barra.entrada.audio.volume) : 0
                onCambiar: v => { if (barra.entrada && barra.entrada.audio) { barra.entrada.audio.muted = false; barra.entrada.audio.volume = v; } }
                onIcono_pulsado: if (barra.entrada && barra.entrada.audio) barra.entrada.audio.muted = !barra.entrada.audio.muted
            }
        }
    }

    Component {
        id: cMusica
        Column {
            visible: !!barra.reproductor
            Encabezado { text: "Reproduciendo"; topPadding: 0 }
            Rectangle {
                width: parent.width; height: 72; radius: 16; color: "#2e2e2e"
                ClippingRectangle {
                    id: caratula
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 52; height: 52; radius: 10; color: "#3a3a3a"
                    Image { anchors.fill: parent; source: barra.reproductor ? barra.reproductor.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                }
                Column {
                    anchors { left: caratula.right; leftMargin: 10; right: controles.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Texto { width: parent.width; text: barra.reproductor ? (barra.reproductor.trackTitle || barra.reproductor.identity) : ""; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    Texto { width: parent.width; text: barra.reproductor ? (barra.reproductor.trackTitle ? [barra.reproductor.trackArtist, barra.reproductor.identity].filter(s => s).join(" · ") : "Sin título") : ""; color: "#888"; font.pixelSize: 11; elide: Text.ElideRight }
                }
                Row {
                    id: controles
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Redondo { icono: "skip_previous"; chico: true; onPulsado: barra.reproductor.previous() }
                    Redondo { icono: barra.reproductor && barra.reproductor.isPlaying ? "pause" : "play_arrow"; chico: true; blanco: true; onPulsado: barra.reproductor.togglePlaying() }
                    Redondo { icono: "skip_next"; chico: true; onPulsado: barra.reproductor.next() }
                }
            }
        }
    }

    Component {
        id: cCalendario
        Column {
            Encabezado { text: Qt.locale("es_MX").toString(reloj.date, "MMMM yyyy"); topPadding: 0 }
            Calendario { width: parent.width }
        }
    }

    Component {
        id: cEnergia
        Item {
            height: filaEnergia.implicitHeight
            Row {
                id: filaEnergia
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 26
                Repeater {
                    model: [
                        { id: "bloquear", icono: "lock", texto: "Bloquear" },
                        { id: "salir", icono: "logout", texto: "Salir" },
                        { id: "reiniciar", icono: "restart_alt", texto: "Reiniciar" },
                        { id: "apagar", icono: "power_settings_new", texto: "Apagar" }
                    ]
                    delegate: Column {
                        required property var modelData
                        spacing: 4
                        Redondo {
                            anchors.horizontalCenter: parent.horizontalCenter
                            icono: modelData.icono
                            rojo: modelData.id === "apagar" || barra.confirmar === modelData.id
                            onPulsado: {
                                const id = modelData.id;
                                if ((id === "reiniciar" || id === "apagar") && barra.confirmar !== id) { barra.confirmar = id; return; }
                                barra.cerrar();
                                if (id === "bloquear") barra.ejecutar(["swaylock"]);
                                else if (id === "salir") barra.ejecutar(["niri", "msg", "action", "quit"]);
                                else if (id === "reiniciar") barra.ejecutar(["systemctl", "reboot"]);
                                else barra.ejecutar(["systemctl", "poweroff"]);
                            }
                        }
                        Texto {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: barra.confirmar === modelData.id ? "¿Seguro?" : modelData.texto
                            color: barra.confirmar === modelData.id ? "#ff6b6b" : "#888"; font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }

    // ---- Piezas ----
    component Texto: Text {
        color: "#eee"
        font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
    }
    component Simbolo: Text {
        property real relleno: 1
        font { family: "Material Symbols Rounded"; pixelSize: 20 }
        font.variableAxes: { "FILL": relleno, "wght": 500, "opsz": 24 }
        renderType: Text.NativeRendering
    }
    component Encabezado: Texto {
        color: "#888"; font.pixelSize: 11; font.weight: Font.Bold
        leftPadding: 4; topPadding: 14; bottomPadding: 6
    }
    component Pagina: Column {
        id: pag
        property bool activa
        property int lado: 1                // -1: entra desde la izquierda (volver a inicio)
        width: parent.width
        spacing: 0
        visible: opacity > 0.01
        opacity: activa ? 1 : 0
        enabled: activa
        // La que sale se va rapido (120 ms); la que entra se desliza 18 px en 320 ms, sin rebote largo.
        Behavior on opacity { NumberAnimation { duration: Estilo.t(pag.activa ? 240 : 120); easing.type: Easing.OutCubic } }
        transform: Translate { id: corrimiento }
        onActivaChanged: if (activa) { entrar.from = 18 * pag.lado; entrar.restart(); }
        NumberAnimation { id: entrar; target: corrimiento; property: "x"; to: 0; duration: Estilo.t(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos }
    }
    component Volver: Item {
        property alias text: tituloVolver.text
        width: parent.width; height: 46
        Redondo { id: atras; icono: "chevron_left"; chico: true; anchors.verticalCenter: parent.verticalCenter; onPulsado: barra.ir("inicio") }
        Texto { id: tituloVolver; anchors { left: atras.right; leftMargin: 8; verticalCenter: parent.verticalCenter } font.pixelSize: 17; font.weight: Font.DemiBold }
    }
    component Redondo: Rectangle {
        id: red
        property string icono
        property bool chico: false
        property bool blanco: false
        property bool rojo: false
        signal pulsado()
        width: chico ? 32 : 40; height: width; radius: width / 2
        color: blanco ? "#ffffff" : (zonaR.containsMouse ? "#3a3a3a" : "#2e2e2e")
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        scale: zonaR.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zonaR.pressed ? 80 : 380); easing.type: zonaR.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
        Simbolo { anchors.centerIn: parent; text: red.icono; color: red.blanco ? "#111" : red.rojo ? "#ff6b6b" : "#ddd"; font.pixelSize: red.chico ? 20 : 19 }
        MouseArea { id: zonaR; anchors.fill: parent; hoverEnabled: true; onClicked: red.pulsado() }
    }
    component Rapido: Rectangle {
        id: rap
        property string icono
        property string titulo
        property string detalle
        property bool activa
        property bool flecha: false
        signal pulsado()
        property real relleno: activa ? 1 : 0
        Behavior on relleno { NumberAnimation { duration: Estilo.t(260) } }
        height: 56; radius: 16
        color: activa ? "#ffffff" : (zonaQ.containsMouse ? "#363636" : "#2e2e2e")
        Behavior on color { ColorAnimation { duration: Estilo.t(260) } }
        scale: zonaQ.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zonaQ.pressed ? 90 : 420); easing.type: zonaQ.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.2) } }
        Simbolo { id: iq; x: 12; anchors.verticalCenter: parent.verticalCenter; text: rap.icono; relleno: rap.relleno; color: rap.activa ? "#111" : "#ddd" }
        Column {
            anchors { left: iq.right; leftMargin: 9; right: parent.right; rightMargin: rap.flecha ? 26 : 8; verticalCenter: parent.verticalCenter }
            Texto { text: rap.titulo; color: rap.activa ? "#111" : "#eee"; font.weight: Font.DemiBold; width: parent.width; elide: Text.ElideRight }
            Texto { visible: rap.detalle !== ""; text: rap.detalle; color: rap.activa ? "#555" : "#888"; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
        }
        Simbolo { visible: rap.flecha; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: "chevron_right"; font.pixelSize: 16; color: rap.activa ? "#777" : "#888" }
        MouseArea { id: zonaQ; anchors.fill: parent; hoverEnabled: true; onClicked: rap.pulsado() }
    }
    component Nivel: Rectangle {
        id: niv
        property string icono: ""
        property string etiqueta: ""
        property real valor
        property bool flecha: false
        signal cambiar(real v)
        signal icono_pulsado()
        signal flecha_pulsada()
        property real vivo: valor
        onValorChanged: if (!zonaN.pressed) vivo = valor
        width: parent.width; height: 40; radius: 14; color: "#2e2e2e"
        Simbolo { id: inv; visible: niv.icono !== ""; x: 10; anchors.verticalCenter: parent.verticalCenter; text: niv.icono; font.pixelSize: 19; color: "#ddd"
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: niv.icono_pulsado() } }
        Texto { id: etq; visible: niv.etiqueta !== ""; x: 12; width: 76; anchors.verticalCenter: parent.verticalCenter; text: niv.etiqueta; font.pixelSize: 12; elide: Text.ElideRight }
        Rectangle {
            id: pista
            anchors { left: niv.etiqueta ? etq.right : inv.right; leftMargin: 10; right: valorTxt.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            height: 20; radius: 10; color: "#1b1b1b"
            Rectangle { height: parent.height; radius: 10; color: "#f2f2f2"; width: Math.max(height, parent.width * niv.vivo) }
            MouseArea {
                id: zonaN
                anchors.fill: parent
                function mover(m) { niv.vivo = Math.max(0, Math.min(1, m.x / width)); niv.cambiar(niv.vivo); }
                onPressed: m => mover(m)
                onPositionChanged: m => mover(m)
            }
        }
        Texto { id: valorTxt; anchors { right: niv.flecha ? fl.left : parent.right; rightMargin: niv.flecha ? 2 : 10; verticalCenter: parent.verticalCenter } width: 28; horizontalAlignment: Text.AlignRight; text: Math.round(niv.vivo * 100); color: "#aaa"; font.pixelSize: 11; font.features: { "tnum": 1 } }
        Simbolo { id: fl; visible: niv.flecha; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: "chevron_right"; font.pixelSize: 18; color: "#888"
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: niv.flecha_pulsada() } }
    }
    component FilaLista: Rectangle {
        id: fl2
        property string icono
        property string titulo
        property string detalle
        property bool marcada: false
        property bool tenue: false
        signal pulsada()
        width: parent ? parent.width : 0; height: detalle ? 48 : 40; radius: 12
        color: marcada ? "#2e2e2e" : (zonaL.containsMouse ? "#2a2a2a" : "#002a2a2a")
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        opacity: tenue ? 0.75 : 1
        Simbolo { id: il; x: 10; anchors.verticalCenter: parent.verticalCenter; text: fl2.icono; font.pixelSize: 19; color: "#ddd" }
        Column {
            anchors { left: il.right; leftMargin: 10; right: parent.right; rightMargin: 34; verticalCenter: parent.verticalCenter }
            Texto { text: fl2.titulo; width: parent.width; elide: Text.ElideRight }
            Texto { visible: fl2.detalle !== ""; text: fl2.detalle; color: "#888"; font.pixelSize: 11; width: parent.width; elide: Text.ElideRight }
        }
        Simbolo { visible: fl2.marcada; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: "check"; font.pixelSize: 18; color: "#fff" }
        MouseArea { id: zonaL; anchors.fill: parent; hoverEnabled: true; onClicked: fl2.pulsada() }
    }
    component Calendario: Rectangle {
        id: cal
        height: rejilla.implicitHeight + 16; radius: 16; color: "#2e2e2e"
        readonly property date hoy: reloj.date
        readonly property bool lunes: barra.cfg.semanaLunes
        readonly property int primerDia: (new Date(hoy.getFullYear(), hoy.getMonth(), 1).getDay() + (lunes ? 6 : 0)) % 7
        readonly property int dias: new Date(hoy.getFullYear(), hoy.getMonth() + 1, 0).getDate()
        Grid {
            id: rejilla
            anchors { fill: parent; margins: 8 }
            columns: 7; rowSpacing: 2
            Repeater {
                model: cal.lunes ? ["L", "M", "M", "J", "V", "S", "D"] : ["D", "L", "M", "M", "J", "V", "S"]
                Texto { required property string modelData; width: rejilla.width / 7; horizontalAlignment: Text.AlignHCenter; text: modelData; color: "#666"; font.pixelSize: 11; font.weight: Font.Bold }
            }
            Repeater {
                model: cal.primerDia + cal.dias
                delegate: Item {
                    required property int index
                    readonly property int dia: index - cal.primerDia + 1
                    width: rejilla.width / 7; height: 24
                    Rectangle { anchors.centerIn: parent; width: 26; height: 22; radius: 8; color: "#ffffff"; visible: parent.dia === cal.hoy.getDate() }
                    Texto { anchors.centerIn: parent; visible: parent.dia > 0; text: parent.dia; font.pixelSize: 11; font.features: { "tnum": 1 }
                        color: parent.dia === cal.hoy.getDate() ? "#111" : "#bbb"; font.weight: parent.dia === cal.hoy.getDate() ? Font.Bold : Font.Normal }
                }
            }
        }
    }
}
