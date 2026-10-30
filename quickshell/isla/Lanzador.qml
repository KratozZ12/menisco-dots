// Tipografia SF Pro Text (HIG); iconos Material Symbols Rounded; grises de Menisco.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.Mpris

// Lanzador: brota del boton de cuadricula del dock (Super+D) y regresa a el al cerrar.
// Sin texto: musica, frecuentes, ventanas abiertas y recientes. Al escribir: calculadora,
// apps, acciones, archivos, emojis (":palabra") y busqueda web. El asistente vive en la barra.
PanelWindow {
    id: lanz

    required property var raiz          // abierta, origen del brote, ajustes

    readonly property var curvaIos: [0.32, 0.72, 0, 1, 1, 1]
    readonly property var curvaRebote: [0.3, 1.55, 0.5, 1, 1, 1]
    readonly property string carpeta: Quickshell.env("HOME") + "/.config/quickshell/isla"
    readonly property bool abierta: raiz.lanzadorAbierto

    property string consulta: ""
    property int elegido: 0
    property var usos: ({})            // { idDesktop: veces abierta } para "Frecuentes"
    property var recientes: []         // [{ nombre, ruta, carpeta }]
    property var encontrados: []       // archivos que coinciden con la busqueda
    readonly property bool noMolestar: Estilo.noMolestar
    property string confirmar: ""      // accion que espera un segundo Enter (apagar, reiniciar)

    visible: abierta || panel.escala > 0.01
    anchors.bottom: true
    // Ventana con holgura alrededor del panel: el rebote del brote no choca con sus bordes.
    readonly property int holgura: 24
    margins.bottom: 100 - holgura       // el panel queda donde estaba, encima del dock
    implicitWidth: 500 + holgura * 2
    implicitHeight: 560 + holgura
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "lanzador"
    WlrLayershell.keyboardFocus: abierta ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Mascara con numeros, no con "item": el panel se anima con una transformacion de escala,
    // y con "item" la mascara se calculaba con el panel a escala 0 y los clics lo atravesaban.
    mask: Region { x: panel.x; y: panel.y; width: panel.width; height: panel.height }

    onAbiertaChanged: {
        if (abierta) {
            consulta = ""; buscador.text = ""; elegido = 0; confirmar = "";
            buscador.forceActiveFocus();
        } else {
            leerRecientes.running = true;   // se precargan al cerrar: al abrir el panel ya tiene su alto final
        }
    }

    function cerrar() { raiz.lanzadorAbierto = false }
    function ejecutar(cmd) { Quickshell.execDetached(cmd) }

    // ---- Datos ----
    FileView {
        path: lanz.carpeta + "/lanzador.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { lanz.usos = JSON.parse(text()); } catch (e) {} }
        id: archivoUsos
    }
    function abrirApp(entrada) {
        if (!entrada) return;
        const u = Object.assign({}, usos);
        u[entrada.id] = (u[entrada.id] || 0) + 1;
        usos = u;
        archivoUsos.setText(JSON.stringify(u));
        entrada.execute();
        cerrar();
    }

    readonly property var apps: DesktopEntries.applications.values.filter(e => !e.noDisplay)
    readonly property var frecuentes: {
        const porUso = apps.filter(e => usos[e.id]).sort((a, b) => usos[b.id] - usos[a.id]);
        const base = ["helium", "claude-desktop-unofficial", "org.gnome.Nautilus", "kitty", "steam", "spotify"]
            .map(id => apps.find(e => e.id === id)).filter(e => e && !porUso.includes(e));
        return porUso.concat(base).slice(0, 6);
    }

    // Recientes: el historial de GTK, los 6 mas nuevos que todavia existen.
    Process {
        id: leerRecientes
        running: true
        command: ["python3", "-c", "import re,os,urllib.parse as u\n" +
            "t=open(os.path.expanduser('~/.local/share/recently-used.xbel'),encoding='utf-8').read()\n" +
            "v=re.findall(r'href=\"file://([^\"]+)\"[^>]*modified=\"([^\"]+)\"',t)\n" +
            "v=sorted(v,key=lambda x:x[1],reverse=True);s=set()\n" +
            "for r,_ in v:\n" +
            " p=u.unquote(r)\n" +
            " if p in s or not os.path.isfile(p): continue\n" +
            " s.add(p);print(p)\n" +
            " if len(s)>=6: break"]
        stdout: StdioCollector {
            onStreamFinished: lanz.recientes = text.trim().split("\n").filter(p => p)
                .map(p => ({ nombre: p.split("/").pop(), ruta: p, carpeta: p.split("/").slice(-2, -1)[0] }))
        }
    }

    // Archivos: plocate en la carpeta personal, sin carpetas ocultas.
    Process {
        id: buscarArchivos
        stdout: StdioCollector {
            onStreamFinished: {
                const casa = Quickshell.env("HOME") + "/";
                lanz.encontrados = text.trim().split("\n")
                    .filter(p => p.startsWith(casa) && !p.slice(casa.length).split("/").some(s => s.startsWith(".")))
                    .slice(0, 4)
                    .map(p => ({ nombre: p.split("/").pop(), ruta: p, carpeta: p.split("/").slice(-2, -1)[0] }));
            }
        }
    }
    Timer {
        id: esperaArchivos
        interval: 180
        onTriggered: {
            if (lanz.consulta.length < 2 || lanz.consulta.startsWith(":")) { lanz.encontrados = []; return; }
            buscarArchivos.command = ["plocate", "-i", "-b", "-l", "60", lanz.consulta];
            buscarArchivos.running = true;
        }
    }


    readonly property var reproductor: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    Timer {   // la posicion de MPRIS no avisa sola: se refresca mientras se ve
        interval: 1000; repeat: true
        running: lanz.visible && lanz.reproductor && lanz.reproductor.isPlaying
        onTriggered: lanz.reproductor.positionChanged()
    }

    // emojis.json: [emoji, "palabras en espanol e ingles"], los comunes primero (~1700).
    property var emojis: []
    FileView {
        path: lanz.carpeta + "/emojis.json"
        onLoaded: { try { lanz.emojis = JSON.parse(text()); } catch (e) {} }
    }
    // Apps por nombre, y tambien por su descripcion, palabras clave y tipo: "minecraft"
    // encuentra Prism Launcher porque su descripcion lo menciona. Primero lo que coincide
    // en el nombre; el subtitulo dice por que salio cuando no es por el nombre.
    function buscarApps(k) {
        const r = [];
        for (const e of apps) {
            const nombre = sinAcentos(e.name);
            const claves = (e.keywords || []).map(sinAcentos);
            const tipo = sinAcentos(e.genericName || "");
            const desc = sinAcentos(e.comment || "");
            let p = 0, sub = e.genericName || e.comment || "Aplicación";
            if (nombre.startsWith(k)) p = 100;
            else if (nombre.split(/[\s.-]+/).some(w => w.startsWith(k))) p = 80;
            else if (nombre.includes(k)) p = 60;
            else if (claves.some(w => w.startsWith(k)) || tipo.includes(k)) { p = 40; sub = e.comment || e.genericName || sub; }
            else if (k.length >= 3 && desc.includes(k)) { p = 20; sub = e.comment; }
            if (p) r.push({ e: e, p: p, sub: sub });
        }
        return r.sort((a, b) => b.p - a.p || a.e.name.length - b.e.name.length);
    }
    function sinAcentos(s) { return s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase(); }
    function buscarEmojis(k, max) {
        const r = [];
        for (const e of emojis) {
            if (r.length >= max) break;
            if (!k || e[1].split(" ").some(p => p.startsWith(k))) r.push(e);
        }
        return r;
    }

    // ---- Resultados al escribir (lista plana con secciones, para navegar con flechas) ----
    function calcular(t) {
        if (!/^[\d\s.+\-*/()%^]+$/.test(t) || !/\d/.test(t) || !/[+\-*/%^]/.test(t)) return null;
        try { const r = Function("return (" + t.replace(/\^/g, "**") + ")")(); return Number.isFinite(r) ? Math.round(r * 1e6) / 1e6 : null; }
        catch (e) { return null; }
    }
    readonly property var acciones: [
        { titulo: "Apagar", icono: "power_settings_new", rojo: true, peligro: true, fn: () => ejecutar(["systemctl", "poweroff"]) },
        { titulo: "Reiniciar", icono: "restart_alt", peligro: true, fn: () => ejecutar(["systemctl", "reboot"]) },
        { titulo: "Bloquear pantalla", icono: "lock", fn: () => ejecutar(["swaylock"]) },
        { titulo: "Cerrar sesión", icono: "logout", fn: () => ejecutar(["niri", "msg", "action", "quit"]) },
        { titulo: "Bluetooth", icono: "bluetooth", interruptor: "bt", fn: () => { const a = Bluetooth.defaultAdapter; Estilo.bluetooth(a, !(a && a.enabled)); } },
        { titulo: "No molestar", icono: "dark_mode", interruptor: "dnd", fn: () => Estilo.ponerNoMolestar(!lanz.noMolestar) },
        { titulo: "Captura de pantalla", icono: "screenshot_region", fn: () => ejecutar(["sh", "-c", "sleep 0.4; niri msg action screenshot"]) },
        { titulo: "Ajustes de Menisco", icono: "tune", fn: () => raiz.abrirAjustes() }
    ]
    readonly property var resultados: {
        const t = consulta.trim(), tl = t.toLowerCase(), r = [];
        if (!t) return r;
        if (tl.startsWith(":")) {   // ":" = solo emojis, muchos
            for (const e of buscarEmojis(sinAcentos(tl.slice(1)), 40)) r.push({ seccion: "Emojis", tipo: "emoji", titulo: e[0], sub: e[1].split(" ")[0] });
            return marcarSecciones(r);
        }
        // "temporizador 5 min", "timer 30 s", "temporizador 1 h"
        const tm = tl.match(/^(?:temporizador|timer|alarma)\s+(\d+(?:[.,]\d+)?)\s*(s|seg|segundos?|m|min|minutos?|h|horas?)?$/);
        if (tm) {
            const n = parseFloat(tm[1].replace(",", ".")), u = (tm[2] || "min")[0];
            const seg = Math.round(n * (u === "s" ? 1 : u === "h" ? 3600 : 60));
            r.push({ seccion: "Temporizador", tipo: "timer", titulo: "Iniciar temporizador de " + tm[1] + " " + ({ s: "s", m: "min", h: "h" })[u], sub: "Cuenta regresiva en la isla", segundos: seg });
        }
        if (raiz.temporizadorRestante > 0 && /^(cancelar|parar|detener|temporizador|timer)/.test(tl))
            r.push({ seccion: "Temporizador", tipo: "timerFin", titulo: "Cancelar temporizador", sub: "Quedan " + Math.ceil(raiz.temporizadorRestante / 60) + " min" });
        const c = calcular(t);
        if (c !== null) r.push({ seccion: "Calculadora", tipo: "calc", titulo: c.toLocaleString(Qt.locale("es_MX"), "f", Number.isInteger(c) ? 0 : Math.min(6, String(c).split(".")[1].length)), sub: t + " =", valor: String(c) });
        for (const x of buscarApps(sinAcentos(t)).slice(0, 5))
            r.push({ seccion: "Apps", tipo: "app", titulo: x.e.name, sub: x.sub, entrada: x.e });
        for (const a of acciones.filter(a => a.titulo.toLowerCase().includes(tl)).slice(0, 3))
            r.push({ seccion: "Acciones", tipo: "accion", titulo: a.titulo, sub: "", accion: a });
        if (tl.length >= 2)         // en la busqueda normal, los 3 mejores emojis
            for (const e of buscarEmojis(sinAcentos(tl), 3)) r.push({ seccion: "Emojis", tipo: "emoji", titulo: e[0], sub: e[1].split(" ")[0] });
        for (const f of encontrados)
            r.push({ seccion: "Archivos", tipo: "archivo", titulo: f.nombre, sub: f.carpeta, ruta: f.ruta });
        if (c === null) r.push({ seccion: "Web", tipo: "web", titulo: "Buscar “" + t + "”", sub: "en Helium" });
        return marcarSecciones(r);
    }
    // El titulo de seccion va dentro del primer resultado de cada una (los modelos de lista
    // simples no admiten secciones de ListView).
    function marcarSecciones(r) {
        r.forEach((x, i) => x.encabezado = i === 0 || r[i - 1].seccion !== x.seccion);
        return r;
    }
    readonly property string emocion: {
        if (!consulta.trim()) return "normal";
        if (consulta.trim().startsWith(":")) return resultados.length ? "emocion" : "confuso";
        const utiles = resultados.filter(x => x.tipo !== "web").length;
        if (resultados.some(x => x.tipo === "calc") || utiles === 1) return "feliz";
        return utiles === 0 ? "confuso" : "pensar";
    }
    onResultadosChanged: elegido = Math.min(elegido, Math.max(0, resultados.length - 1))

    function activar(x) {
        if (!x) return;
        switch (x.tipo) {
        case "app": abrirApp(x.entrada); return;
        case "calc": ejecutar(["wl-copy", x.valor]); cerrar(); return;
        case "timer": raiz.iniciarTemporizador(x.segundos); cerrar(); return;
        case "timerFin": raiz.cancelarTemporizador(); cerrar(); return;
        case "emoji": ejecutar(["wl-copy", x.titulo]); cerrar(); return;
        case "archivo": ejecutar(["xdg-open", x.ruta]); cerrar(); return;
        case "web": ejecutar(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(consulta.trim())]); cerrar(); return;
        case "accion":
            if (x.accion.peligro && confirmar !== x.titulo) { confirmar = x.titulo; return; }
            x.accion.fn();
            if (!x.accion.interruptor) cerrar();
            return;
        }
    }

    // ---- Panel ----
    Rectangle {
        id: panel
        // Escala 0..1 del brote; el origen esta en el boton del dock, debajo del panel.
        property real escala: 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: lanz.holgura }
        height: Math.min(lanz.height - lanz.holgura * 2, contenido.implicitHeight + barra.height + 34)
        Behavior on height { enabled: lanz.abierta && panel.escala > 0.99; NumberAnimation { duration: Estilo.t(320); easing.type: Easing.BezierSpline; easing.bezierCurve: lanz.curvaIos } }
        radius: 22
        color: Estilo.fondo
        border.color: "#3a3a3a"
        border.width: 1
        clip: true
        opacity: lanz.abierta ? Math.min(1, escala * 3) : escala
        transform: Scale {
            origin.x: panel.width / 2 + raiz.origenLanzadorX
            origin.y: panel.height + 40
            xScale: panel.escala
            yScale: panel.escala
        }

        states: State { name: "abierto"; when: lanz.abierta; PropertyChanges { target: panel; escala: 1 } }
        transitions: [
            // Rebote corto (~4 %): con el rebote general de Menisco el panel se pasaba de largo y se veia brusco.
            Transition { to: "abierto"; NumberAnimation { property: "escala"; duration: Estilo.t(520); easing.type: Easing.BezierSpline; easing.bezierCurve: [0.25, 1.18, 0.4, 1, 1, 1] } },
            Transition { from: "abierto"; NumberAnimation { property: "escala"; duration: Estilo.t(280); easing.type: Easing.OutCubic } }
        ]

        Keys.onEscapePressed: lanz.cerrar()

        // ---- Contenido de arriba: inicio o resultados ----
        Item {
            id: contenido
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            implicitHeight: lanz.consulta.trim() ? Math.min(380, lista.contentHeight) : inicio.implicitHeight

            Column {
                id: inicio
                width: parent.width
                visible: !lanz.consulta.trim()
                spacing: 0

                // Lo que suena
                Rectangle {
                    visible: !!lanz.reproductor
                    width: parent.width; height: visible ? 62 : 0
                    radius: 14; color: "#1b1b1b"
                    ClippingRectangle {
                        id: caratula
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 46; height: 46; radius: 9; color: "#333"
                        Image { anchors.fill: parent; source: lanz.reproductor ? lanz.reproductor.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                    }
                    Column {
                        anchors { left: caratula.right; leftMargin: 10; right: controles.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Texto { width: parent.width; text: lanz.reproductor ? lanz.reproductor.trackTitle : ""; color: "#fff"; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Texto { width: parent.width; text: lanz.reproductor ? lanz.reproductor.trackArtist + " · " + lanz.reproductor.identity : ""; color: "#888"; font.pixelSize: 11; elide: Text.ElideRight }
                        Rectangle {
                            width: parent.width; height: 3; radius: 2; color: "#333"
                            Rectangle {
                                height: 3; radius: 2; color: "#fff"
                                width: lanz.reproductor && lanz.reproductor.length > 0 ? parent.width * Math.min(1, lanz.reproductor.position / lanz.reproductor.length) : 0
                                Behavior on width { NumberAnimation { duration: Estilo.t(900) } }
                            }
                        }
                    }
                    Row {
                        id: controles
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        Boton { icono: "skip_previous"; onPulsado: lanz.reproductor.previous() }
                        Boton { icono: lanz.reproductor && lanz.reproductor.isPlaying ? "pause" : "play_arrow"; lleno: true; onPulsado: lanz.reproductor.togglePlaying() }
                        Boton { icono: "skip_next"; onPulsado: lanz.reproductor.next() }
                    }
                }

                Titulo { text: "Frecuentes" }
                Row {
                    width: parent.width
                    Repeater {
                        model: lanz.frecuentes
                        delegate: Item {
                            required property var modelData
                            width: inicio.width / 6; height: 66
                            Column {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 4
                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 42; height: 42; sourceSize: Qt.size(48, 48)
                                    source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                                    scale: zonaF.pressed ? 0.88 : (zonaF.containsMouse ? 1.08 : 1)
                                    Behavior on scale { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2) } }
                                }
                                Texto { anchors.horizontalCenter: parent.horizontalCenter; width: inicio.width / 6 - 6; horizontalAlignment: Text.AlignHCenter; text: modelData.name; font.pixelSize: 11; color: "#ddd"; elide: Text.ElideRight }
                            }
                            MouseArea { id: zonaF; anchors.fill: parent; hoverEnabled: true; onClicked: lanz.abrirApp(modelData) }
                        }
                    }
                }

                Titulo { text: "Ventanas abiertas"; visible: ToplevelManager.toplevels.values.length > 0 }
                Repeater {
                    model: ToplevelManager.toplevels.values.slice(0, 4)
                    delegate: Fila {
                        required property var modelData
                        width: inicio.width
                        iconoApp: (DesktopEntries.heuristicLookup(modelData.appId) || {}).icon || modelData.appId
                        titulo: modelData.title
                        derecha: "ir"
                        onPulsada: { modelData.activate(); lanz.cerrar(); }
                    }
                }

                Titulo { text: "Recientes"; visible: lanz.recientes.length > 0 }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: lanz.recientes
                        delegate: Rectangle {
                            required property var modelData
                            width: Math.min(inicio.width, chip.implicitWidth + 36); height: 26; radius: 9
                            color: zonaR.containsMouse ? "#383838" : "#2e2e2e"
                            Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
                            Simbolo { x: 8; anchors.verticalCenter: parent.verticalCenter; text: "description"; font.pixelSize: 14; color: "#aaa" }
                            Texto { id: chip; x: 28; width: parent.width - 36; anchors.verticalCenter: parent.verticalCenter; text: modelData.nombre; font.pixelSize: 11; color: "#ddd"; elide: Text.ElideMiddle }
                            MouseArea { id: zonaR; anchors.fill: parent; hoverEnabled: true; onClicked: { lanz.ejecutar(["xdg-open", modelData.ruta]); lanz.cerrar(); } }
                        }
                    }
                }
            }

            ListView {
                id: lista
                width: parent.width
                height: Math.min(380, contentHeight)
                visible: lanz.consulta.trim() !== ""
                interactive: contentHeight > height
                model: lanz.resultados
                currentIndex: lanz.elegido
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                delegate: Column {
                    id: celda
                    required property var modelData
                    required property int index
                    width: lista.width
                    Titulo { visible: celda.modelData.encabezado; text: celda.modelData.seccion }
                    Fila {
                    readonly property var modelData: celda.modelData
                    readonly property int index: celda.index
                    width: lista.width
                    marcada: index === lanz.elegido
                    grande: modelData.tipo === "calc"
                    emoji: modelData.tipo === "emoji"
                    iconoApp: modelData.tipo === "app" ? modelData.entrada.icon : ""
                    simbolo: ({ accion: modelData.accion ? modelData.accion.icono : "", archivo: "description", web: "travel_explore", calc: "calculate", timer: "timer", timerFin: "timer_off" })[modelData.tipo] || ""
                    rojo: modelData.tipo === "accion" && !!modelData.accion.rojo
                    titulo: lanz.confirmar === modelData.titulo ? modelData.titulo + ": pulse Enter otra vez" : modelData.titulo
                    sub: modelData.sub
                    interruptor: modelData.tipo === "accion" && modelData.accion.interruptor
                        ? (modelData.accion.interruptor === "bt" ? (Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false) : lanz.noMolestar)
                        : undefined
                    derecha: index === lanz.elegido ? "Enter" : ""
                    onPulsada: lanz.activar(modelData)
                    onEncima: lanz.elegido = index
                    }
                }
            }
        }

        // ---- Barra de busqueda, abajo, con el asistente ----
        Rectangle {
            id: barra
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
            height: 42
            radius: 12
            color: "#1b1b1b"

            Asistente {
                id: asistente
                width: 32; height: 32
                x: 6; anchors.verticalCenter: parent.verticalCenter
                emocion: lanz.emocion
                // Llega despues de que el panel empieza a brotar: crece desde un punto, se
                // estira y se aplasta antes de asentarse, y parpadea al llegar.
                transform: Scale { id: llegadaEsc; origin.x: 16; origin.y: 16; xScale: 0; yScale: 0 }
            }
            SequentialAnimation {
                id: llegada
                PropertyAction { target: llegadaEsc; properties: "xScale,yScale"; value: 0 }
                PauseAnimation { duration: Estilo.t(300) }
                ParallelAnimation {
                    NumberAnimation { target: llegadaEsc; property: "xScale"; to: 1; duration: Estilo.t(520); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2.2) }
                    SequentialAnimation {
                        NumberAnimation { target: llegadaEsc; property: "yScale"; to: 1.25; duration: Estilo.t(220); easing.type: Easing.OutCubic }
                        NumberAnimation { target: llegadaEsc; property: "yScale"; to: 1; duration: Estilo.t(380); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2.5) }
                    }
                }
                ScriptAction { script: asistente.parpadear() }
            }
            NumberAnimation { id: salida; target: llegadaEsc; properties: "xScale,yScale"; to: 0; duration: Estilo.t(200); easing.type: Easing.InBack; easing.overshoot: Estilo.o(1.6) }
            Connections {
                target: lanz
                function onAbiertaChanged() { if (lanz.abierta) { salida.stop(); llegada.restart(); } else { llegada.stop(); salida.restart(); } }
            }

            TextInput {
                id: buscador
                anchors { left: parent.left; leftMargin: 46; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                color: "#ffffff"
                selectionColor: "#555"
                font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
                clip: true
                onTextChanged: { lanz.consulta = text; lanz.confirmar = ""; lanz.elegido = 0; esperaArchivos.restart(); }
                Keys.onEscapePressed: lanz.cerrar()
                Keys.onDownPressed: lanz.elegido = Math.min(lanz.elegido + 1, lanz.resultados.length - 1)
                Keys.onUpPressed: lanz.elegido = Math.max(lanz.elegido - 1, 0)
                Keys.onReturnPressed: lanz.activar(lanz.resultados[lanz.elegido])
                Keys.onEnterPressed: lanz.activar(lanz.resultados[lanz.elegido])

                Texto {
                    visible: !buscador.text
                    text: "Buscar apps, archivos, acciones…"
                    color: "#777"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ---- Piezas ----
    component Texto: Text {
        color: "#eee"
        font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
    }
    component Titulo: Texto {
        color: "#888"
        font { pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.06 }
        leftPadding: 4; topPadding: 12; bottomPadding: 6
    }
    component Simbolo: Text {
        font { family: "Material Symbols Rounded"; pixelSize: 18 }
        font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 20 }
        renderType: Text.NativeRendering
    }
    component Boton: Rectangle {
        id: boton
        property string icono
        property bool lleno: false
        signal pulsado()
        width: 30; height: 30; radius: 15
        color: lleno ? "#fff" : (zonaB.containsMouse ? "#333" : "#00333333")
        Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
        scale: zonaB.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zonaB.pressed ? 80 : 380); easing.type: zonaB.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.4) } }
        Simbolo { anchors.centerIn: parent; text: boton.icono; color: boton.lleno ? "#111" : "#ddd"; font.pixelSize: 20 }
        MouseArea { id: zonaB; anchors.fill: parent; hoverEnabled: true; onClicked: boton.pulsado() }
    }
    component Fila: Rectangle {
        id: fila
        property string iconoApp: ""
        property string simbolo: ""
        property bool emoji: false
        property bool grande: false
        property bool rojo: false
        property bool marcada: false
        property string titulo
        property string sub: ""
        property string derecha: ""
        property var interruptor: undefined
        signal pulsada()
        signal encima()

        height: grande ? 74 : (sub ? 44 : 36)
        radius: 10
        color: marcada || zonaFila.containsMouse ? "#333" : "#00333333"
        Behavior on color { ColorAnimation { duration: Estilo.t(110) } }

        Item {
            id: icono
            visible: !fila.grande
            x: 8; width: 28; height: 28; anchors.verticalCenter: parent.verticalCenter
            Image { anchors.fill: parent; visible: fila.iconoApp !== ""; sourceSize: Qt.size(48, 48); source: fila.iconoApp ? Quickshell.iconPath(fila.iconoApp, "application-x-executable") : "" }
            Rectangle {
                anchors.fill: parent; radius: 8; color: "#2e2e2e"
                visible: fila.iconoApp === ""
                Simbolo { anchors.centerIn: parent; visible: !fila.emoji; text: fila.simbolo; color: fila.rojo ? "#ff6b6b" : "#ddd" }
                Text { anchors.centerIn: parent; visible: fila.emoji; text: fila.titulo; font.pixelSize: 18 }
            }
        }
        Column {
            anchors { left: fila.grande ? parent.left : icono.right; leftMargin: fila.grande ? 14 : 10; right: parent.right; rightMargin: 60; verticalCenter: parent.verticalCenter }
            spacing: 1
            Texto { visible: fila.grande; text: fila.sub; color: "#888"; font.pixelSize: 11 }
            Texto {
                width: parent.width
                text: fila.emoji ? fila.sub : fila.titulo
                color: fila.rojo ? "#ff6b6b" : "#eee"
                elide: Text.ElideRight
                font.pixelSize: fila.grande ? 28 : 13
                font.weight: fila.grande ? Font.DemiBold : Font.Normal
                font.features: { "tnum": 1 }
            }
            Texto { visible: !fila.grande && fila.sub !== "" && !fila.emoji; width: parent.width; text: fila.sub; color: "#888"; font.pixelSize: 11; elide: Text.ElideRight }
        }
        Texto {
            visible: fila.interruptor === undefined
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: fila.derecha; color: "#777"; font.pixelSize: 11
        }
        Rectangle {   // interruptor de Bluetooth / No molestar
            visible: fila.interruptor !== undefined
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            width: 34; height: 20; radius: 10
            color: fila.interruptor ? "#fff" : "#444"
            Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
            Rectangle {
                width: 16; height: 16; radius: 8; color: Estilo.fondo; y: 2
                x: fila.interruptor ? 16 : 2
                Behavior on x { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(1.6) } }
            }
        }
        MouseArea { id: zonaFila; anchors.fill: parent; hoverEnabled: true; onClicked: fila.pulsada(); onEntered: fila.encima() }
    }
}
