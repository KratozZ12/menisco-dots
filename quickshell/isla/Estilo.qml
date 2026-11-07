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
        tema: "champan",               // onix | champan | medianoche | rubi | jade
        letra: "SF Pro",                // SF Pro | Inter
        esquinas: 20, espacio: 16, borde: 40,
        islaAsistente: true, islaVisualizador: true, reloj12: false, segundos: false,
        personalidad: "normal",         // tranquilo | normal | inquieto
        reaccionMusica: true,
        // Isla: como se abre y que avisos muestra (los avisos se ajustan en Notificaciones)
        islaForma: "clasica", islaImagen: "",   // imagen de fondo de la pestana Acciones ("" = ninguna)
          // clasica | biselada | octagono | ola | liquida | recta | pildora
        islaCursor: true, islaEspera: "normal", islaPestana: "acciones",   // pestana: musica | acciones | rendimiento | ultima
        avisoMusica: true, avisoBt: true, avisoCaptura: true, avisoTemp: true,
        avisoGrados: 80, avisoDuracion: "normal",                          // corta | normal | larga
        avisoBateria: true, avisoSalida: false, avisoFallos: true,
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

    // ---- Color ----
    // Cinco temas en negro. Las piezas leen solo estos nombres, nunca un gris escrito a mano:
    // fondo (paneles), tarjeta (bloques dentro del panel), hover, hundido (campos y pistas),
    // borde y linea (filos finos), texto/texto2/texto3, apagado (interruptor sin activar),
    // activo + enActivo + iconoActivo + activoBorde (lo que esta encendido), acento (deslizadores,
    // interruptores, seleccion) y sobreAcento (la perilla encima del acento).
    readonly property var temas: ({
        onix:       { nombre: "Ónix", fondo: "#000000", tarjeta: "#0f0f0f", hover: "#1c1c1c", hundido: "#171717",
                      borde: "#1affffff", linea: "#12ffffff", texto: "#f5f5f5", texto2: "#8c8c8c", texto3: "#5c5c5c",
                      apagado: "#2a2a2a", activo: "#f5f5f5", enActivo: "#000000", iconoActivo: "#000000",
                      activoBorde: "#00000000", acento: "#f5f5f5", sobreAcento: "#000000" },
        champan:    { nombre: "Champán", fondo: "#000000", tarjeta: "#0f0f0f", hover: "#1c1c1c", hundido: "#171717",
                      borde: "#1affffff", linea: "#12ffffff", texto: "#f5f5f5", texto2: "#8c8c8c", texto3: "#5c5c5c",
                      apagado: "#2a2a2a", activo: "#1d1810", enActivo: "#f2e6d0", iconoActivo: "#d9b77e",
                      activoBorde: "#59d9b77e", acento: "#d9b77e", sobreAcento: "#000000" },
        medianoche: { nombre: "Medianoche", fondo: "#06070a", tarjeta: "#0e1016", hover: "#1a1e27", hundido: "#151821",
                      borde: "#1aa0b4ff", linea: "#12a0b4ff", texto: "#eef1f7", texto2: "#858c9b", texto3: "#5a6070",
                      apagado: "#262a35", activo: "#121a2c", enActivo: "#e3eaff", iconoActivo: "#8fb0ff",
                      activoBorde: "#598fb0ff", acento: "#8fb0ff", sobreAcento: "#06070a" },
        rubi:       { nombre: "Rubí", fondo: "#0a0808", tarjeta: "#130f0f", hover: "#201a1a", hundido: "#1a1515",
                      borde: "#17ffebe6", linea: "#10ffebe6", texto: "#f6f1f0", texto2: "#968a88", texto3: "#665c5a",
                      apagado: "#2c2525", activo: "#e5484d", enActivo: "#ffffff", iconoActivo: "#ffffff",
                      activoBorde: "#00000000", acento: "#e5484d", sobreAcento: "#ffffff" },
        jade:       { nombre: "Jade", fondo: "#050807", tarjeta: "#0b110e", hover: "#16201c", hundido: "#121a17",
                      borde: "#17b4ffdc", linea: "#10b4ffdc", texto: "#eef5f2", texto2: "#84958f", texto3: "#5a6a65",
                      apagado: "#22302b", activo: "#0e1f19", enActivo: "#dcf5ea", iconoActivo: "#5fd4a8",
                      activoBorde: "#595fd4a8", acento: "#5fd4a8", sobreAcento: "#050807" }
    })
    readonly property var ordenTemas: ["onix", "champan", "medianoche", "rubi", "jade"]
    readonly property var tema: temas[valor("tema")] || temas.champan
    readonly property color fondo: tema.fondo
    readonly property color tarjeta: tema.tarjeta
    readonly property color hover: tema.hover
    readonly property color nada: Qt.alpha(tema.hover, 0)     // hover apagado: transparente del mismo tono
    readonly property color hundido: tema.hundido
    readonly property color borde: tema.borde
    readonly property color linea: tema.linea
    readonly property color texto: tema.texto
    readonly property color texto2: tema.texto2
    readonly property color texto3: tema.texto3
    readonly property color apagado: tema.apagado
    readonly property color activo: tema.activo
    readonly property color enActivo: tema.enActivo
    readonly property color iconoActivo: tema.iconoActivo
    readonly property color activoBorde: tema.activoBorde
    readonly property color acento: tema.acento
    readonly property color sobreAcento: tema.sobreAcento
    readonly property color peligro: "#ff6b6b"

    // Hokum dibuja las notificaciones: su tema (themes/menisco.kdl, que parte de "capsule") se
    // reescribe con los colores del tema elegido. Hokum lee #RRGGBBAA; Qt da #AARRGGBB.
    function rgba(c) { const s = String(c); return s.length === 9 ? "#" + s.slice(3) + s.slice(1, 3) : s; }
    FileView { id: temaHokum; path: Quickshell.env("HOME") + "/.config/hokum/themes/menisco.kdl"; blockWrites: false }
    function escribirHokum() {
        temaHokum.setText(`// Lo escribe Menisco (Estilo.qml) al cambiar de color; no editar a mano.
theme "capsule"
name "Menisco"
tokens {
    fill "${rgba(tema.tarjeta)}"
    text "${rgba(tema.texto)}"
    muted "${rgba(tema.texto2)}"
    faint "${rgba(tema.texto3)}"
    border 1 "${rgba(tema.borde)}"
    accent "${rgba(tema.acento)}"
    shadow "soft"
}
`);
    }
    onTemaChanged: escribirHokum()
    Component.onCompleted: escribirHokum()

    // Mitad izquierda de la forma de la isla (Ajustes > Isla > Forma). Todas tienen los mismos
    // 8 puntos (inicio arriba, hombro, lado, esquina de abajo), asi se puede pasar de una a la
    // clasica mezclando numeros. La derecha es su espejo.
    //   [S inicio, A y B control del hombro, P fin del hombro, L1 fin del lado, K1 y K2 control
    //    de la esquina, Bt inicio del fondo]
    // x0 = borde izquierdo del fondo, h = alto, r = radio de las esquinas, hom = hombro clasico.
    function mitadForma(f, x0, h, r, hom) {
        const k = 0.62;
        switch (f) {
        case "biselada": {          // trapecio: lados en diagonal hasta un fondo plano
            const d = Math.min(h, 60) * 1.15, j = 5, lg = Math.hypot(d, h), ux = d / lg, uy = h / lg;
            return [[x0 - d - j, 0], [x0 - d - j * 0.4, 0], [x0 - d + ux * j * 0.4, uy * j * 0.4], [x0 - d + ux * j, uy * j],
                    [x0 - ux * j, h - uy * j], [x0 - ux * j * 0.4, h - uy * j * 0.4], [x0 + j * 0.4, h], [x0 + j, h]];
        }
        case "octagono": {          // lados rectos y las esquinas de abajo cortadas
            const c = 12;
            return [[x0, 0], [x0, 0.3], [x0, 0.6], [x0, 1], [x0, h - c], [x0 + c * 0.33, h - c * 0.67], [x0 + c * 0.67, h - c * 0.33], [x0 + c, h]];
        }
        case "ola": {               // una sola curva desde el borde de arriba hasta el fondo
            // proporcional al alto (con tope al abrirse); el fondo plano llega hasta el contenido
            const b = Math.min(h, 60), f = [x0 + b * 0.1, h];
            return [[x0 - b * 2, 0], [x0 - b, 0], [x0 - b * 0.55, h], f, f, f, f, f];
        }
        case "liquida":             // la clasica con hombros largos
            return [[x0 - hom * 3, 0], [x0 - hom * 0.9, 0], [x0 - hom * 0.2, hom * 0.4], [x0, hom * 1.1],
                    [x0, Math.max(hom * 1.1, h - r)], [x0, h - r * (1 - k)], [x0 + r * (1 - k), h], [x0 + r, h]];
        case "recta": {             // bloque con esquinas casi vivas
            const q = 4;
            return [[x0, 0], [x0, 0.3], [x0, 0.6], [x0, 1], [x0, h - q], [x0, h - q * (1 - k)], [x0 + q * (1 - k), h], [x0 + q, h]];
        }
        case "pildora": {           // suelta del borde: arriba queda un hueco
            const g = 5, R = Math.min((h - g) / 2, 30);
            return [[x0 + R, g], [x0 + R * (1 - k), g], [x0, g + R * k], [x0, g + R], [x0, h - R], [x0, h - R * (1 - k)], [x0 + R * (1 - k), h], [x0 + R, h]];
        }
        default:                    // clasica
            return [[x0 - hom, 0], [x0 - hom * 0.28, 0], [x0, hom * 0.17], [x0, hom], [x0, h - r],
                    [x0, h - r * (1 - k)], [x0 + r * (1 - k), h], [x0 + r, h]];
        }
    }

    // Cuanto se ensancha cada forma alrededor del contenido y cuanto baja el contenido, para que
    // la Gota y el reloj queden bien dentro: [margen a cada lado, bajada].
    function ajusteForma(f) {
        return ({ octagono: [6, 0], pildora: [12, 2.5] })[f] || [0, 0];
    }

    // Camino SVG de la forma entera: la mitad izquierda y su espejo alrededor de cx.
    function trazoForma(l, cx) {
        const m = q => [2 * cx - q[0], q[1]];
        const n = q => q[0].toFixed(2) + " " + q[1].toFixed(2);
        const [S, A, B, P, L1, K1, K2, Bt] = l;
        return `M${n(S)} C${n(A)} ${n(B)} ${n(P)} L${n(L1)} C${n(K1)} ${n(K2)} ${n(Bt)} L${n(m(Bt))} `
             + `C${n(m(K2))} ${n(m(K1))} ${n(m(L1))} L${n(m(P))} C${n(m(B))} ${n(m(A))} ${n(m(S))} Z`;
    }
    readonly property var formasIsla: [["clasica", "Clásica"], ["biselada", "Biselada"], ["octagono", "Octágono"], ["ola", "Ola"],
                                       ["liquida", "Líquida"], ["recta", "Recta"], ["pildora", "Píldora"]]

    // ---- Aspecto ----
    readonly property string letra: valor("letra") === "Inter" ? "Inter Display" : "SF Pro Text"

    // Bluetooth: al encender, primero se quita el bloqueo de rfkill (Plasma lo deja bloqueado al
    // apagarlo desde alli, y con el bloqueo BlueZ se niega a encender). Apagar no bloquea.
    // Si BlueZ ya lo tiene encendido, el boton solo se ve apagado porque Quickshell se perdio el
    // aviso (ver shell.qml): se apaga y enciende para que se entere.
    function bluetooth(adaptador, encender) {
        if (encender) Quickshell.execDetached(["sh", "-c", "rfkill unblock bluetooth; sleep 0.5; bluetoothctl show | grep -q 'Powered: yes' && bluetoothctl power off; bluetoothctl power on"]);
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
