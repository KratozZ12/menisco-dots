pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Ajustes de Menisco compartidos por todas las piezas: se leen y guardan en menisco.json.
// Lo que vive en niri o Lniri (esquinas, espacio, borde, monitores, vidrio, atajos) lo
// escribe menisco-niri.py; aqui solo se recuerda el valor elegido.
Singleton {
    id: estilo

    readonly property string carpeta: Quickshell.env("HOME") + "/.config/quickshell/isla"

    property var datos: ({})
    readonly property var porDefecto: ({
        velocidad: "normal",            // lenta | normal | rapida
        rebote: "suave",                // nada | suave | mucho
        fondoNegro: false,
        letra: "SF Pro",                // SF Pro | Inter
        esquinas: 20, espacio: 16, borde: 40,
        islaAsistente: true, islaVisualizador: true, reloj12: false, segundos: false,
        personalidad: "normal",         // tranquilo | normal | inquieto
        reaccionMusica: true,
        // Isla: como se abre y que avisos muestra (los avisos se ajustan en Notificaciones)
        islaCursor: true, islaEspera: "normal", islaPestana: "acciones",   // pestana: musica | acciones | rendimiento | ultima
        avisoMusica: true, avisoBt: true, avisoCaptura: true, avisoTemp: true,
        avisoGrados: 80, avisoDuracion: "normal",                          // corta | normal | larga
        avisoBateria: true, avisoSalida: false,
        // Notificaciones: No molestar automatico y aviso de "ahora suena"
        dndPantallaCompleta: true, dndGrabando: true,
        musicaIgnorar: [], musicaNoAlFrente: true, musicaConCaratula: false, musicaReanudar: false,   // musicaIgnorar: identity de MPRIS
        hokumApps: [],                  // apps listadas en Por aplicacion (sus reglas viven en el config.kdl de Hokum)
        // Pestana Musica de la isla
        musicaLetra: true, letraNetease: true, musicaTinte: true, musicaAudio: true, ocultarVisualizador: true,
        // Asistente
        // Gotas guardadas (forma y color de reposo); la activa es la que vive en la isla.
        gotas: [{ nombre: "Gota", forma: "esfera", color: "#0b0b0c", cambia: true }], gotaActiva: 0,
        botSub: "Pregúntame",
        botLuz: true, botChispas: true, botEnPaginas: true, succion: true,
        vidrio: { refraccion: 70, aberracion: 95, desenfoque: 20, brillo: 35, dock: true, ventanas: true, notificaciones: false },
        barra: { lado: "derecha", altura: "centro", ancho: 340, boton: true, borde: false, clicFuera: true,
                 secciones: [{ id: "rapidos", ver: true }, { id: "sonido", ver: true }, { id: "musica", ver: true },
                             { id: "calendario", ver: true }, { id: "energia", ver: true }],
                 rapidos: ["red", "bt", "dnd", "cafe"], semanaLunes: true }
    })
    function valor(clave) { return datos[clave] !== undefined ? datos[clave] : porDefecto[clave]; }
    // Ajustes de la barra lateral, con los que falten tomados de porDefecto.
    readonly property var barra: Object.assign({}, porDefecto.barra, datos.barra || {})
    readonly property var gotas: valor("gotas")
    readonly property int gotaActiva: Math.min(valor("gotaActiva"), gotas.length - 1)
    readonly property var gota: gotas[gotaActiva] || porDefecto.gotas[0]
    function guardarGota(i, g) {                      // i = -1 agrega una nueva y la activa
        const l = gotas.slice();
        if (i < 0) { l.push(g); poner("gotas", l); poner("gotaActiva", l.length - 1); }
        else { l[i] = g; poner("gotas", l); }
    }
    function borrarGota(i) {
        if (gotas.length < 2) return;
        const activa = gotaActiva;
        poner("gotas", gotas.filter((g, j) => j !== i));
        poner("gotaActiva", activa > i ? activa - 1 : Math.min(activa, gotas.length - 1));
    }
    function ponerBarra(clave, v) { const b = Object.assign({}, barra); b[clave] = v; poner("barra", b); }

    function poner(clave, v) {
        const d = Object.assign({}, datos);
        d[clave] = v;
        datos = d;
        archivo.setText(JSON.stringify(d, null, 2));
    }

    FileView {
        id: archivo
        path: estilo.carpeta + "/menisco.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { estilo.datos = JSON.parse(text()); } catch (e) {} }
    }

    // ---- Movimiento ----
    // t(ms): duracion ajustada a la velocidad elegida.
    readonly property real factorTiempo: ({ lenta: 1.45, normal: 1, rapida: 0.7 })[valor("velocidad")] ?? 1
    function t(ms) { return ms * factorTiempo; }
    // o(x): sobrepaso de Easing.OutBack segun el rebote elegido (0 = sin rebote).
    readonly property real factorRebote: ({ nada: 0, suave: 1, mucho: 1.7 })[valor("rebote")] ?? 1
    function o(x) { return Math.max(0.0001, x * factorRebote); }
    // Curva con rebote (pasa de largo y se asienta); sin rebote es la curva de iOS.
    readonly property var curvaIos: [0.32, 0.72, 0, 1, 1, 1]
    readonly property var curvaRebote: factorRebote === 0 ? curvaIos
        : [0.3, 1 + 0.55 * factorRebote, 0.5, 1, 1, 1]

    // ---- Aspecto ----
    readonly property color fondo: valor("fondoNegro") ? "#000000" : "#242424"
    readonly property string letra: valor("letra") === "Inter" ? "Inter Display" : "SF Pro Text"

    // Bluetooth: al encender, primero se quita el bloqueo de rfkill (Plasma lo deja bloqueado al
    // apagarlo desde alli, y con el bloqueo BlueZ se niega a encender). Apagar no bloquea.
    function bluetooth(adaptador, encender) {
        if (encender) Quickshell.execDetached(["sh", "-c", "rfkill unblock bluetooth; sleep 0.5; bluetoothctl power on"]);
        else if (adaptador) adaptador.enabled = false;
    }

    // ---- No molestar: lo guarda Hokum (que recibe las notificaciones) ----
    // --watch avisa cada vez que cambia, venga de donde venga (Hokum, la barra, el lanzador...).
    property bool noMolestar: false
    function ponerNoMolestar(v) { Quickshell.execDetached(["hokum", "dnd", v ? "on" : "off"]); }
    Process {
        running: true
        command: ["hokum", "dnd", "--watch"]
        stdout: SplitParser { onRead: data => estilo.noMolestar = data.trim() === "on" }
    }

    function niri(args) { Quickshell.execDetached(["python3", carpeta + "/menisco-niri.py"].concat(args)); }
}
