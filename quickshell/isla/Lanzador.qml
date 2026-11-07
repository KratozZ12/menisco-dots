import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth

// Lanzador (Super+D): una pildora en el centro de la pantalla, con la Gota dentro. Al abrirse no
// muestra nada mas; al escribir, la misma pildora crece hacia abajo con los resultados dentro,
// el primero grande. Busca calculadora, temporizador, apps, acciones, archivos, emojis (":palabra") y web.
// Esc o un clic fuera lo cierran.
PanelWindow {
    id: lanz

    required property var raiz          // lanzadorAbierto, temporizador, ajustes

    readonly property string carpeta: Quickshell.env("HOME") + "/.config/quickshell/isla"
    readonly property bool abierta: raiz.lanzadorAbierto
    readonly property int maximo: 7     // tarjetas a la vista

    property string consulta: ""
    property int elegido: 0
    property var usos: ({})            // { idDesktop: veces abierta }: desempata entre apps
    property var encontrados: []       // archivos que coinciden con la busqueda
    readonly property bool noMolestar: Estilo.noMolestar
    property string confirmar: ""      // accion que espera un segundo Enter (apagar, reiniciar)

    // 0 -> 1 al abrir, con rebote; al cerrar baja rapido y la ventana se oculta al llegar a 0.
    property real mostrar: abierta ? 1 : 0
    Behavior on mostrar { NumberAnimation { duration: Estilo.t(lanz.abierta ? 460 : 150); easing.type: Easing.BezierSpline; easing.bezierCurve: lanz.abierta ? Estilo.curvaRebote : Estilo.curvaIos } }

    visible: abierta || mostrar > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "lanzador"
    WlrLayershell.keyboardFocus: abierta ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onAbiertaChanged: {
        if (abierta) {
            consulta = ""; buscador.text = ""; elegido = 0; confirmar = ""; encontrados = [];
            buscador.forceActiveFocus();
        }
    }

    function cerrar() { raiz.lanzadorAbierto = false }
    function escribir(texto) { buscador.text = texto }
    function ejecutar(cmd) { Quickshell.execDetached(cmd) }

    // ---- Datos ----
    FileView {
        id: archivoUsos
        path: lanz.carpeta + "/lanzador.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { lanz.usos = JSON.parse(text()); } catch (e) {} }
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

    // Archivos: plocate en la carpeta personal, sin carpetas ocultas.
    Process {
        id: buscarArchivos
        stdout: StdioCollector {
            onStreamFinished: {
                const casa = Quickshell.env("HOME") + "/";
                lanz.encontrados = text.trim().split("\n")
                    .filter(p => p.startsWith(casa) && !p.slice(casa.length).split("/").some(s => s.startsWith(".")))
                    .slice(0, 3)
                    .map(p => ({ nombre: p.split("/").pop(), ruta: p, carpeta: "~/" + p.slice(casa.length).split("/").slice(0, -1).join("/") }));
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

    // emojis.json: [emoji, "palabras en espanol e ingles"], los comunes primero (~1700).
    property var emojis: []
    FileView {
        path: lanz.carpeta + "/emojis.json"
        onLoaded: { try { lanz.emojis = JSON.parse(text()); } catch (e) {} }
    }
    // Apps por nombre, y tambien por su descripcion, palabras clave y tipo: "minecraft"
    // encuentra Prism Launcher porque su descripcion lo menciona. Primero lo que coincide
    // en el nombre; a igualdad, la que mas se abre.
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
        return r.sort((a, b) => b.p - a.p || (usos[b.e.id] || 0) - (usos[a.e.id] || 0) || a.e.name.length - b.e.name.length);
    }
    function sinAcentos(s) { return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase(); }
    function buscarEmojis(k, max) {
        const r = [];
        for (const e of emojis) {
            if (r.length >= max) break;
            if (!k || e[1].split(" ").some(p => p.startsWith(k))) r.push(e);
        }
        return r;
    }

    // ---- Resultados al escribir ----
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
        { titulo: "Captura de pantalla", icono: "screenshot_region", fn: () => ejecutar(["sh", "-c", "sleep 0.4; qs -p '" + Estilo.carpeta + "' ipc call captura abrir zona"]) },
        { titulo: "Ajustes de Menisco", icono: "tune", fn: () => raiz.abrirAjustes() }
    ]
    readonly property var resultados: {
        const t = consulta.trim(), tl = t.toLowerCase(), r = [];
        if (!t) return r;
        if (tl.startsWith(":")) {   // ":" = solo emojis
            for (const e of buscarEmojis(sinAcentos(tl.slice(1)), maximo)) r.push({ tipo: "emoji", titulo: e[0], sub: e[1].split(" ")[0] });
            return r;
        }
        // "temporizador 5 min", "timer 30 s", "temporizador 1 h"
        const tm = tl.match(/^(?:temporizador|timer|alarma)\s+(\d+(?:[.,]\d+)?)\s*(s|seg|segundos?|m|min|minutos?|h|horas?)?$/);
        if (tm) {
            const n = parseFloat(tm[1].replace(",", ".")), u = (tm[2] || "min")[0];
            const seg = Math.round(n * (u === "s" ? 1 : u === "h" ? 3600 : 60));
            r.push({ tipo: "timer", titulo: "Temporizador de " + tm[1] + " " + ({ s: "s", m: "min", h: "h" })[u], sub: "Cuenta regresiva en la isla", segundos: seg });
        }
        if (raiz.temporizadorRestante > 0 && /^(cancelar|parar|detener|temporizador|timer)/.test(tl))
            r.push({ tipo: "timerFin", titulo: "Cancelar temporizador", sub: "Quedan " + Math.ceil(raiz.temporizadorRestante / 60) + " min" });
        const c = calcular(t);
        if (c !== null) r.push({ tipo: "calc", titulo: c.toLocaleString(Qt.locale("es_MX"), "f", Number.isInteger(c) ? 0 : Math.min(6, String(c).split(".")[1].length)), sub: t + " =", valor: String(c) });
        for (const x of buscarApps(sinAcentos(t)).slice(0, 4))
            r.push({ tipo: "app", titulo: x.e.name, sub: x.sub, entrada: x.e });
        for (const a of acciones.filter(a => a.titulo.toLowerCase().includes(tl)).slice(0, 2))
            r.push({ tipo: "accion", titulo: a.titulo, sub: "", accion: a });
        if (tl.length >= 2)
            for (const e of buscarEmojis(sinAcentos(tl), 2)) r.push({ tipo: "emoji", titulo: e[0], sub: e[1].split(" ")[0] });
        for (const f of encontrados)
            r.push({ tipo: "archivo", titulo: f.nombre, sub: f.carpeta, ruta: f.ruta });
        if (c === null) r.push({ tipo: "web", titulo: "Buscar “" + t + "” en la web", sub: "" });
        return r.slice(0, maximo);
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
    // Lo que dice la tarjeta a la derecha, y lo que hace Enter en la grande
    readonly property var etiquetas: ({ app: "App", accion: "Acción", emoji: "Emoji", web: "Web", calc: "Calculadora", timer: "Temporizador", timerFin: "Temporizador" })
    readonly property var verbos: ({ app: "abrir", calc: "copiar", emoji: "copiar", archivo: "abrir", web: "buscar", timer: "iniciar", timerFin: "cancelar", accion: "hacer" })

    // Un clic fuera de la pildora y las tarjetas lo cierra.
    MouseArea { anchors.fill: parent; onClicked: lanz.cerrar() }

    // ---- La pildora ----
    Rectangle {
        id: pildora
        // un tercio de pantalla hacia abajo: tiene sitio para crecer
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: Math.round(parent.height * 0.28) }
        width: 600
        readonly property bool abiertaAbajo: lanz.resultados.length > 0
        height: 54 + (abiertaAbajo ? lista.implicitHeight + 10 : 0)
        // Crece con rebote; al encogerse no rebota (se pasaria por debajo de su alto y se veria roto).
        Behavior on height {
            id: animAlto
            NumberAnimation { duration: Estilo.t(420); easing.type: Easing.BezierSpline; easing.bezierCurve: animAlto.targetValue < pildora.height ? Estilo.curvaIos : Estilo.curvaRebote }
        }
        radius: abiertaAbajo ? 24 : 27
        Behavior on radius { NumberAnimation { duration: Estilo.t(300) } }
        color: Estilo.fondo
        border.width: 1; border.color: Estilo.borde
        clip: true
        opacity: Math.min(1, lanz.mostrar * 1.6)
        transform: [
            Scale { origin.x: 300; origin.y: 27; xScale: 0.9 + 0.1 * lanz.mostrar; yScale: 0.9 + 0.1 * lanz.mostrar },
            Translate { y: (1 - lanz.mostrar) * -14 }
        ]
        MouseArea { anchors.fill: parent; onClicked: buscador.forceActiveFocus() }

        Item {
            id: cabeza
            width: parent.width; height: 54

            Rectangle {
                id: nido
                x: 9; anchors.verticalCenter: parent.verticalCenter
                width: 36; height: 36; radius: 18
                color: Estilo.tarjeta; border.width: 1; border.color: Estilo.borde
                Asistente {
                    id: asistente
                    anchors.centerIn: parent
                    width: 32; height: 32
                    emocion: lanz.emocion
                    fondoNegro: true
                    // Llega despues de la pildora: crece desde un punto, se estira y se asienta, y parpadea.
                    transform: Scale { id: llegadaEsc; origin.x: 16; origin.y: 16; xScale: 0; yScale: 0 }
                }
            }
            SequentialAnimation {
                id: llegada
                PropertyAction { target: llegadaEsc; properties: "xScale,yScale"; value: 0 }
                PauseAnimation { duration: Estilo.t(160) }
                ParallelAnimation {
                    NumberAnimation { target: llegadaEsc; property: "xScale"; to: 1; duration: Estilo.t(480); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2.2) }
                    SequentialAnimation {
                        NumberAnimation { target: llegadaEsc; property: "yScale"; to: 1.25; duration: Estilo.t(200); easing.type: Easing.OutCubic }
                        NumberAnimation { target: llegadaEsc; property: "yScale"; to: 1; duration: Estilo.t(360); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(2.5) }
                    }
                }
                ScriptAction { script: asistente.parpadear() }
            }
            Connections {
                target: lanz
                function onAbiertaChanged() { if (lanz.abierta) llegada.restart(); }
            }

            TextInput {
                id: buscador
                anchors { left: nido.right; leftMargin: 12; right: pistaEsc.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                color: Estilo.texto
                selectionColor: Qt.alpha(Estilo.acento, 0.4)
                font { family: Estilo.letra; pixelSize: 17; letterSpacing: -0.2 }
                clip: true
                onTextChanged: { lanz.consulta = text; lanz.confirmar = ""; lanz.elegido = 0; esperaArchivos.restart(); }
                Keys.onEscapePressed: lanz.cerrar()
                Keys.onDownPressed: lanz.elegido = Math.min(lanz.elegido + 1, lanz.resultados.length - 1)
                Keys.onUpPressed: lanz.elegido = Math.max(lanz.elegido - 1, 0)
                Keys.onTabPressed: lanz.elegido = (lanz.elegido + 1) % Math.max(1, lanz.resultados.length)
                Keys.onReturnPressed: lanz.activar(lanz.resultados[lanz.elegido])
                Keys.onEnterPressed: lanz.activar(lanz.resultados[lanz.elegido])
                Texto {
                    visible: !buscador.text
                    text: "Buscar apps, archivos, acciones…"
                    color: Estilo.texto3
                    font.pixelSize: 17; font.letterSpacing: -0.2
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Texto {
                id: pistaEsc
                anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                text: "Esc"; color: Estilo.texto3; font.pixelSize: 11
            }
        }
        Rectangle {   // linea entre la busqueda y los resultados
            x: 16; y: 54; width: parent.width - 32; height: 1
            color: Estilo.linea
            opacity: pildora.abiertaAbajo ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Estilo.t(200) } }
        }

        // ---- Los resultados ----
        // Modelo por indice (no el arreglo de resultados): al escribir las filas que ya estan
        // solo cambian de contenido, y solo las nuevas entran con su animacion.
        Column {
            id: lista
            x: 6; y: 60; width: parent.width - 12
            spacing: 2
            Repeater {
                model: lanz.resultados.length
                delegate: Tarjeta {
                    required property int index
                    datos: lanz.resultados[index] || null
                    grande: index === 0
                    marcada: index === lanz.elegido
                    orden: index
                }
            }
        }
    }

    component Tarjeta: Rectangle {
        id: t
        property var datos
        property bool grande
        property bool marcada
        property int orden
        readonly property string tipo: datos ? datos.tipo : ""
        readonly property bool conInterruptor: tipo === "accion" && !!datos.accion.interruptor
        readonly property bool encendido: conInterruptor && (datos.accion.interruptor === "bt" ? (Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false) : lanz.noMolestar)
        readonly property bool rojo: tipo === "accion" && !!datos.accion.rojo
        readonly property string titulo: !datos ? "" : lanz.confirmar === datos.titulo ? datos.titulo + ": pulse Enter otra vez" : tipo === "emoji" ? datos.sub : datos.titulo

        width: lista.width
        height: grande ? 70 : 42
        radius: grande ? 18 : 14
        color: marcada ? Estilo.activo : zona.containsMouse ? Estilo.hover : Estilo.nada
        border.width: 1; border.color: marcada ? Estilo.activoBorde : "transparent"
        Behavior on color { ColorAnimation { duration: Estilo.t(140) } }
        Behavior on height { NumberAnimation { duration: Estilo.t(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }

        // Entrada al aparecer: baja un poco y se asienta, cada una un instante despues que la anterior.
        opacity: 0
        transform: Translate { id: bajada; y: -6 }
        Component.onCompleted: entrada.start()
        ParallelAnimation {
            id: entrada
            SequentialAnimation {
                PauseAnimation { duration: Estilo.t(Math.min(t.orden, 5) * 28) }
                ParallelAnimation {
                    NumberAnimation { target: t; property: "opacity"; to: 1; duration: Estilo.t(200); easing.type: Easing.OutCubic }
                    NumberAnimation { target: bajada; property: "y"; to: 0; duration: Estilo.t(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote }
                }
            }
        }
        scale: zona.pressed ? 0.98 : 1
        Behavior on scale { NumberAnimation { duration: Estilo.t(zona.pressed ? 80 : 320); easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2) } }

        // Icono: el de la app, un emoji o un simbolo; la calculadora no lleva (el numero es grande)
        Item {
            id: icono
            visible: t.tipo !== "calc" || !t.grande
            x: t.grande ? 12 : 10
            width: t.grande ? 48 : 26; height: width
            anchors.verticalCenter: parent.verticalCenter
            Image {
                anchors.fill: parent; visible: t.tipo === "app"
                sourceSize: Qt.size(64, 64)
                source: t.tipo === "app" ? Quickshell.iconPath(t.datos.entrada.icon, "application-x-executable") : ""
            }
            Rectangle {
                anchors.fill: parent; visible: t.tipo !== "app"
                radius: t.grande ? 14 : 8
                color: t.marcada ? Qt.alpha(Estilo.iconoActivo, 0.12) : Estilo.tarjeta
                Text { anchors.centerIn: parent; visible: t.tipo === "emoji"; text: t.datos ? t.datos.titulo : ""; font.pixelSize: t.grande ? 28 : 16 }
                Simbolo {
                    anchors.centerIn: parent; visible: t.tipo !== "emoji"
                    font.pixelSize: t.grande ? 26 : 17
                    color: t.rojo ? Estilo.peligro : t.marcada ? Estilo.iconoActivo : Estilo.texto
                    text: t.tipo === "accion" ? t.datos.accion.icono
                        : ({ archivo: "description", web: "travel_explore", calc: "calculate", timer: "timer", timerFin: "timer_off" })[t.tipo] || ""
                }
            }
        }

        Column {
            anchors { left: icono.visible ? icono.right : parent.left; leftMargin: icono.visible ? 12 : 22
                      right: lado.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 1
            Texto {   // en la calculadora grande, la cuenta va arriba del resultado
                visible: t.grande && t.tipo === "calc"
                text: t.datos ? t.datos.sub : ""; color: t.marcada ? Qt.alpha(Estilo.enActivo, 0.6) : Estilo.texto2; font.pixelSize: 12
            }
            Texto {
                width: parent.width
                text: t.titulo
                elide: Text.ElideRight
                color: t.rojo ? Estilo.peligro : t.marcada ? Estilo.enActivo : Estilo.texto
                font.pixelSize: t.grande ? (t.tipo === "calc" ? 28 : 17) : 13
                font.weight: t.grande ? Font.DemiBold : Font.Normal
                font.features: { "tnum": 1 }
            }
            Texto {
                visible: t.grande && t.tipo !== "calc" && t.datos && t.datos.sub !== "" && t.tipo !== "emoji"
                width: parent.width; elide: Text.ElideRight
                text: t.datos ? t.datos.sub : ""
                color: t.marcada ? Qt.alpha(Estilo.enActivo, 0.6) : Estilo.texto2; font.pixelSize: 12
            }
        }

        // A la derecha: interruptor, teclas (en la grande) o el tipo de resultado
        Item {
            id: lado
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            width: t.conInterruptor ? 34 : t.grande ? teclas.implicitWidth : Math.min(200, etiqueta.implicitWidth)
            height: 22
            Rectangle {
                visible: t.conInterruptor
                width: 34; height: 20; radius: 10; anchors.verticalCenter: parent.verticalCenter
                color: t.encendido ? Estilo.acento : Estilo.apagado
                Behavior on color { ColorAnimation { duration: Estilo.t(200) } }
                Rectangle {
                    width: 16; height: 16; radius: 8; y: 2
                    color: t.encendido ? Estilo.sobreAcento : Estilo.texto2
                    x: t.encendido ? 16 : 2
                    Behavior on x { NumberAnimation { duration: Estilo.t(320); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(1.6) } }
                }
            }
            Row {
                id: teclas
                visible: !t.conInterruptor && t.grande
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Tecla { texto: "Enter"; tenue: !t.marcada }
                Texto { text: lanz.verbos[t.tipo] || ""; font.pixelSize: 11; color: t.marcada ? Qt.alpha(Estilo.enActivo, 0.7) : Estilo.texto3; anchors.verticalCenter: parent.verticalCenter }
            }
            Texto {
                id: etiqueta
                visible: !t.conInterruptor && !t.grande
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: Math.min(200, implicitWidth); elide: Text.ElideMiddle
                text: t.tipo === "archivo" ? t.datos.sub : lanz.etiquetas[t.tipo] || ""
                color: t.marcada ? Qt.alpha(Estilo.enActivo, 0.7) : Estilo.texto3; font.pixelSize: 11
            }
        }

        MouseArea { id: zona; anchors.fill: parent; hoverEnabled: true; onClicked: lanz.activar(t.datos); onEntered: lanz.elegido = t.orden }
    }

    component Tecla: Rectangle {
        property string texto
        property bool tenue
        width: tt.implicitWidth + 12; height: 20; radius: 6
        color: Estilo.hundido; border.width: 1; border.color: Estilo.borde
        Texto { id: tt; anchors.centerIn: parent; text: parent.texto; font.pixelSize: 10; color: parent.tenue ? Estilo.texto2 : Estilo.texto }
    }
    component Texto: Text {
        color: Estilo.texto
        font { family: Estilo.letra; pixelSize: 13; letterSpacing: -0.08 }
    }
    component Simbolo: Text {
        font { family: "Material Symbols Rounded"; pixelSize: 18 }
        font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 20 }
        renderType: Text.NativeRendering
    }
}
