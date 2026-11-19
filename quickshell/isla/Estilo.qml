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
    // Archivos temporales: /run/user/<uid>, privado de cada usuario. En /tmp un archivo de otra cuenta no se puede sobrescribir.
    readonly property string tmp: Quickshell.env("XDG_RUNTIME_DIR")

    property var datos: ({})
    readonly property var porDefecto: ({
        velocidad: "normal",            // lenta | normal | rapida
        rebote: "suave",                // nada | suave | mucho
        tema: "champan",               // ver ordenTemas
        letra: "SF Pro",                // SF Pro | Inter
        esquinas: 20, espacio: 16, borde: 40, marco: false, dockPegado: true,
        islaAsistente: true, islaVisualizador: true, reloj12: false, segundos: false,
        personalidad: "normal",         // tranquilo | normal | inquieto
        reaccionMusica: true,
        // Isla: como se abre y que avisos muestra (los avisos se ajustan en Notificaciones)
        dockMaterial: "vidrio", dockForma: "redondeada",   // vidrio | solido | ahumado | escarcha | tinte | contorno | materialyou
        islaForma: "clasica", islaImagen: "",   // imagen de fondo de la pestana Acciones ("" = ninguna)
          // clasica | biselada | octagono | ola | liquida | recta | pildora
        islaAjustar: false, islaCursor: true, islaEspera: "normal", islaPestana: "acciones",   // pestana: musica | acciones | rendimiento | ultima
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
    // Isla pequena: que muestra cada hueco. Sin la clave guardada se deduce de los
    // interruptores viejos (islaAsistente / islaVisualizador).
    readonly property var huecosDefecto: ({ izquierda: "asistente", centro: "hora", derecha: "visualizador" })
    readonly property var huecos: datos.islaHuecos ? Object.assign({}, huecosDefecto, datos.islaHuecos)
        : { izquierda: valor("islaAsistente") ? "asistente" : "nada", centro: "hora", derecha: valor("islaVisualizador") ? "visualizador" : "nada" }
    // Hueco donde esta un miniwidget ("" si no esta). Hora y fecha cuentan como el mismo reloj.
    function ladoDe(id) {
        const grupo = id === "hora" || id === "fecha" ? ["hora", "fecha"] : [id];
        for (const k of ["izquierda", "centro", "derecha"]) if (grupo.includes(huecos[k])) return k;
        return "";
    }
    // Poner algo que ya estaba en otro hueco lo intercambia con lo de este.
    function ponerHueco(lado, id) {
        const h = Object.assign({}, huecos);
        const otro = id === "nada" ? "" : ladoDe(id);
        if (otro && otro !== lado) h[otro] = h[lado] === "fecha" && otro !== "centro" ? "hora" : h[lado];
        h[lado] = id;
        poner("islaHuecos", h);
    }
    // Botones de las esquinas de arriba (Esquina.qml), de izquierda a derecha como se ven.
    // Sin la clave guardada: como antes, Menisco enfrente de la barra, que sigue a barra.lado.
    readonly property var botones: datos.botonesArriba ? Object.assign({ izquierda: [], derecha: [] }, datos.botonesArriba)
        : barra.lado === "izquierda"
            ? { izquierda: (barra.boton ? ["barra"] : []).concat(["bandeja"]), derecha: ["menisco"] }
            : { izquierda: ["menisco"], derecha: ["bandeja"].concat(barra.boton ? ["barra"] : []) }
    // [clave, nombre, icono]
    readonly property var botonesCatalogo: [["menisco", "Menisco (ajustes)", "deployed_code"], ["barra", "Barra lateral", "auto_awesome"],
        ["bandeja", "Bandeja de iconos", "more_horiz"], ["lanzador", "Lanzador", "apps"], ["captura", "Captura", "screenshot_region"],
        ["nomolestar", "No molestar", "do_not_disturb_on"], ["juego", "Modo juego", "sports_esports"], ["vista", "Vista general", "grid_view"],
        ["flotante", "Escritorio flotante", "web_asset"], ["bloquear", "Bloquear", "lock"], ["fondo", "Siguiente fondo", "wallpaper"]]
    // ---- Perfiles de diseño (Ajustes > Apariencia) ----
    // Guardan solo la apariencia; nunca el No molestar, el fondo ni rutas personales.
    readonly property var clavesPerfil: ["tema", "letra", "velocidad", "rebote", "marco", "esquinas", "espacio", "borde",
        "dockMaterial", "dockForma", "dockPegado", "islaForma", "islaHuecos", "botonesArriba", "vidrio"]
    readonly property var perfiles: datos.perfiles || []
    readonly property var fotoActual: {
        const d = {};
        for (const k of clavesPerfil) d[k] = k === "islaHuecos" ? huecos : k === "botonesArriba" ? botones : valor(k);
        return JSON.parse(JSON.stringify(d));
    }
    // El perfil que coincide en todo con lo que se ve ahora (-1 si ninguno)
    readonly property int perfilActivo: perfiles.findIndex(p => clavesPerfil.every(k => JSON.stringify(p.datos[k]) === JSON.stringify(fotoActual[k])))
    function guardarPerfil(nombre) { poner("perfiles", perfiles.concat([{ nombre: nombre, datos: fotoActual }])); }
    function actualizarPerfil(i) { const l = perfiles.slice(); l[i] = { nombre: l[i].nombre, datos: fotoActual }; poner("perfiles", l); }
    function renombrarPerfil(i, n) { const l = perfiles.slice(); l[i] = { nombre: n, datos: l[i].datos }; poner("perfiles", l); }
    function borrarPerfil(i) { poner("perfiles", perfiles.filter((p, j) => j !== i)); }
    function aplicarPerfil(i) {
        const p = perfiles[i];
        if (!p) return;
        const d = Object.assign({}, datos, p.datos);   // una sola escritura del archivo
        datos = d;
        archivo.setText(JSON.stringify(d, null, 2));
        // Lo que vive en niri / Lniri
        niri(["esquinas", valor("esquinas")]);
        niri(["espacio", valor("espacio")]);
        niri(["borde", valor("borde")]);
        niri(["vidrio", JSON.stringify(valor("vidrio"))]);
    }
    function ponerBotones(b) { poner("botonesArriba", { izquierda: b.izquierda.slice(), derecha: b.derecha.slice() }); }
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
    // t(ms): duracion ajustada a la velocidad elegida. En modo juego todo es instantaneo.
    property bool juego: false                      // lo pone shell.qml (modoJuego)
    readonly property real factorTiempo: juego ? 0 : ({ lenta: 1.45, normal: 1, rapida: 0.7 })[valor("velocidad")] ?? 1
    function t(ms) { return ms * factorTiempo; }
    // o(x): sobrepaso de Easing.OutBack segun el rebote elegido (0 = sin rebote).
    readonly property real factorRebote: ({ nada: 0, suave: 1, mucho: 1.7 })[valor("rebote")] ?? 1
    function o(x) { return Math.max(0.0001, x * factorRebote); }
    // Curva con rebote (pasa de largo y se asienta); sin rebote es la curva de iOS.
    readonly property var curvaIos: [0.32, 0.72, 0, 1, 1, 1]
    readonly property var curvaRebote: factorRebote === 0 ? curvaIos
        : [0.3, 1 + 0.55 * factorRebote, 0.5, 1, 1, 1]

    // ---- Color ----
    // Diez temas oscuros. Las piezas leen solo estos nombres, nunca un gris escrito a mano:
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
        // Rubi y Jade: dos tonos. El acento va en interruptores y barras; lo encendido es una tarjeta
        // oscura con el icono de color y un filo de otro tono (oro rosa, oro viejo).
        rubi:       { nombre: "Rubí", fondo: "#0b0607", tarjeta: "#150b0d", hover: "#231316", hundido: "#1c0f12",
                      borde: "#1fffd0d6", linea: "#12ffd0d6", texto: "#f7ecee", texto2: "#a08a8e", texto3: "#6e5a5e",
                      apagado: "#2e1a1e", activo: "#2a0e14", enActivo: "#ffe3e6", iconoActivo: "#ff5a6e",
                      activoBorde: "#8ce9a88f", acento: "#e8384f", sobreAcento: "#ffffff" },
        jade:       { nombre: "Jade", fondo: "#040907", tarjeta: "#0a1410", hover: "#13211b", hundido: "#0f1a15",
                      borde: "#1fbfe8d2", linea: "#12bfe8d2", texto: "#eaf4ef", texto2: "#8aa39a", texto3: "#5b6f68",
                      apagado: "#1d2c26", activo: "#0f2a20", enActivo: "#e3f6ec", iconoActivo: "#7fe0b5",
                      activoBorde: "#99c9a45c", acento: "#4fc497", sobreAcento: "#04140d" },
        // Pantalla de terminal vieja: hasta el texto va en ambar.
        fosforo:    { nombre: "Fósforo", fondo: "#0a0702", tarjeta: "#130e05", hover: "#21180a", hundido: "#1a1307",
                      borde: "#26ffb347", linea: "#14ffb347", texto: "#ffd9a0", texto2: "#b08a52", texto3: "#6e5530",
                      apagado: "#2c2210", activo: "#ffb347", enActivo: "#1a1003", iconoActivo: "#1a1003",
                      activoBorde: "#00000000", acento: "#ffb347", sobreAcento: "#1a1003" },
        // Noche azulada: verde agua en lo encendido y filo violeta.
        aurora:     { nombre: "Aurora", fondo: "#05060c", tarjeta: "#0c0f1a", hover: "#171b2b", hundido: "#121524",
                      borde: "#1f9fb0ff", linea: "#129fb0ff", texto: "#eef0ff", texto2: "#8a90b0", texto3: "#5a5f7a",
                      apagado: "#232842", activo: "#141533", enActivo: "#e8e4ff", iconoActivo: "#3ee0c5",
                      activoBorde: "#80a77bff", acento: "#3ee0c5", sobreAcento: "#05060c" },
        // Gris calido de lapiz con piezas de cobre.
        grafito:    { nombre: "Grafito", fondo: "#0c0b0a", tarjeta: "#171513", hover: "#24211e", hundido: "#1d1a17",
                      borde: "#1fffe2c8", linea: "#12ffe2c8", texto: "#f1ebe5", texto2: "#9a918a", texto3: "#66605a",
                      apagado: "#2e2a26", activo: "#c87941", enActivo: "#140b04", iconoActivo: "#140b04",
                      activoBorde: "#00000000", acento: "#d98a52", sobreAcento: "#140b04" },
        // Tokio de noche: icono magenta, filo e interruptores cian.
        neon:       { nombre: "Neón", fondo: "#050308", tarjeta: "#0e0a14", hover: "#1a1324", hundido: "#140f1d",
                      borde: "#26ff4fd8", linea: "#14ff4fd8", texto: "#f6eefe", texto2: "#9a8bb0", texto3: "#64587a",
                      apagado: "#261c33", activo: "#1a0b24", enActivo: "#ffe6fb", iconoActivo: "#ff4fd8",
                      activoBorde: "#9922e5ff", acento: "#22e5ff", sobreAcento: "#050308" },
        // El unico sin negro puro: gris azulado suave, poco contraste.
        niebla:     { nombre: "Niebla", fondo: "#101317", tarjeta: "#181c21", hover: "#232830", hundido: "#1d2228",
                      borde: "#24dbe7f5", linea: "#16dbe7f5", texto: "#dfe6ee", texto2: "#8b96a3", texto3: "#5f6874",
                      apagado: "#2c323b", activo: "#dfe6ee", enActivo: "#101317", iconoActivo: "#101317",
                      activoBorde: "#00000000", acento: "#a9c3dc", sobreAcento: "#101317" }
    })
    readonly property var ordenTemas: ["onix", "champan", "medianoche", "rubi", "jade", "fosforo", "aurora", "grafito", "neon", "niebla"]
    readonly property var tema: temas[valor("tema")] || temas.champan
    readonly property color fondo: tema.fondo
    readonly property color tarjeta: tema.tarjeta
    readonly property color hover: tema.hover
    readonly property color nada: Qt.alpha(tema.hover, 0)     // hover apagado: transparente del mismo tono
    readonly property color hundido: tema.hundido
    // Hover: el tono de hover aclarado para que se note sobre cualquier fondo del tema.
    readonly property color realce: Qt.tint(tema.hover, Qt.alpha(tema.texto, 0.09))
    function aclarar(c) { return Qt.tint(c, Qt.alpha(tema.texto, 0.14)) }
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

    // ---- Color propio de cada ajuste (la paleta de sistema de Apple) ----
    // Solo en detalles: la burbuja del icono, el interruptor encendido y un filo fino. Nunca de relleno.
    readonly property var tonos: ({
        bt: "#0a84ff", red: "#30d158", wifi: "#30d158", dnd: "#bf5af2", cafe: "#ff9f0a", captura: "#64d2ff",
        isla: "#5ac8fa", vidrio: "#64d2ff", grabar: "#ff375f", juego: "#ff375f", mic: "#ff9f0a", sonido: "#ff2d55",
        temporizador: "#ff9f0a", cronometro: "#ffd60a", color: "#ff6482", portapapeles: "#a2845e", fondo: "#32ade6",
        tema: "#bf5af2", ajustes: "#8e8e93", bloquear: "#7d7aff", salir: "#8e8e93", suspender: "#5e5ce6",
        reiniciar: "#ff9f0a", apagar: "#ff453a", papelera: "#ff453a"
    })
    function tono(id) { return tonos[id] || "#8e8e93"; }
    // Siguiente fondo de ~/Imágenes/Wallpapers, en orden (isla y lanzador).
    readonly property var comandoSiguienteFondo: ["sh", "-c", "d=\"$HOME/Imágenes/Wallpapers\"; a=$(awww query | sed -n 's/.*image: //p' | head -1); " +
        "ls \"$d\" | grep -iE '\\.(jpe?g|png|webp)$' > $XDG_RUNTIME_DIR/menisco-fondos.txt; " +
        "n=$(grep -nxF \"$(basename \"$a\")\" $XDG_RUNTIME_DIR/menisco-fondos.txt | cut -d: -f1); " +
        "s=$(sed -n \"$(( ${n:-0} + 1 ))p\" $XDG_RUNTIME_DIR/menisco-fondos.txt); [ -z \"$s\" ] && s=$(head -1 $XDG_RUNTIME_DIR/menisco-fondos.txt); " +
        "awww img \"$d/$s\" --transition-type grow --transition-fps 144"]

    // ---- Formas del dock (solo sin vidrio: el vidrio cubre la ventana entera) ----
    // Mitad izquierda como tres curvas: abajo (esquina, u hombro si va pegado), lado y arriba.
    // Diez puntos [S, a1, b1, P1, a2, b2, P2, a3, b3, T]; todas las formas tienen los mismos, asi
    // que el dock pasa de una a otra mezclando punto a punto. x0 = lado del cuerpo, h = alto.
    readonly property var formasDock: [["redondeada", "Redondeada"], ["capsula", "Cápsula"], ["biselada", "Biselada"],
                                       ["octagono", "Octágono"], ["ola", "Ola"], ["liquida", "Líquida"], ["recta", "Recta"]]
    function mitadDock(f, x0, h, pegado, s) {
        const k = 0.62;
        const sum = (p, q, t) => [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t];
        const recta = (A, B) => [sum(A, B, 1 / 3), sum(A, B, 2 / 3), B];
        const esquina = (A, C, B, kk) => [sum(A, C, kk), sum(B, C, kk), B];
        // una sola cubica partida en tres (de Casteljau) para que tenga los mismos puntos
        const partir = (P0, P1, P2, P3) => {
            const en = t => { const a = sum(P0, P1, t), b = sum(P1, P2, t), c = sum(P2, P3, t), d = sum(a, b, t), e = sum(b, c, t); return [a, b, c, d, e, sum(d, e, t)]; };
            const c1 = en(1 / 3), q = c1[5];
            const r = (u, v) => sum(u, v, 0.5);    // tramo [1/3, 1]: se vuelve a partir a la mitad
            const R0 = q, R1 = c1[4], R2 = c1[2], R3 = P3;
            const m01 = r(R0, R1), m12 = r(R1, R2), m23 = r(R2, R3), m012 = r(m01, m12), m123 = r(m12, m23), mid = r(m012, m123);
            return [P0, c1[0], c1[3], q, m01, m012, mid, m123, m23, R3];
        };
        const lado = (xb, xt, rb, rt) => {
            const L = Math.hypot(xt - xb, h), u = [(xt - xb) / L, -h / L];
            const Cb = [xb, h], Ct = [xt, 0];
            const abajo = pegado ? esquina([xb - s, h], Cb, [xb + u[0] * s, h + u[1] * s], 0.75)
                                 : esquina([xb + rb, h], Cb, [xb + u[0] * rb, h + u[1] * rb], k);
            const P2 = [xt - u[0] * rt, -u[1] * rt];          // a rt de la esquina de arriba, sobre el lado
            const arriba = esquina(P2, Ct, [xt + rt, 0], k);
            const S = pegado ? [xb - s, h] : [xb + rb, h];
            return [S, ...abajo, ...recta(abajo[2], P2), ...arriba];
        };
        const chafl = (c) => {
            const S = pegado ? [x0 - s, h] : [x0 + c, h];
            const abajo = pegado ? esquina(S, [x0, h], [x0, h - s], 0.75) : recta(S, [x0, h - c]);
            return [S, ...abajo, ...recta(abajo[2], [x0, c]), ...recta([x0, c], [x0 + c, 0])];
        };
        switch (f) {
        case "capsula":   return lado(x0, x0, h / 2, h / 2);
        case "biselada":  return lado(x0, x0 + 10, 6, 6);
        case "octagono":  return chafl(14);
        case "recta":     return lado(x0, x0, 4, 4);
        case "ola": {     // pegado, la de la isla al reves: una sola curva larga desde el borde del marco
            const b = Math.min(h, 60);
            return pegado ? partir([x0 - b * 2, h], [x0 - b, h], [x0 - b * 0.55, 0], [x0 + b * 0.1, 0])
                          : partir([x0 + 8, h], [x0 - 12, h], [x0 - 2, 0], [x0 + 24, 0]);
        }
        case "liquida": { // pegado, la clasica con hombros largos (como la isla); flotante, la redondeada
            const r = Math.min(22, h / 2);
            if (!pegado) return lado(x0, x0, r, r);
            const P1 = [x0, h - s * 1.1], P2 = [x0, r];
            return [[x0 - s * 3, h], [x0 - s * 0.9, h], [x0 - s * 0.2, h - s * 0.4], P1, ...recta(P1, P2), ...esquina(P2, [x0, 0], [x0 + r, 0], k)];
        }
        default:          return lado(x0, x0, Math.min(22, h / 2), Math.min(22, h / 2));   // redondeada
        }
    }
    // Contorno completo de la mitad l reflejada en cx. abajo = alto hasta donde baja el relleno
    // pegado (cubre la franja del marco); -1 = sin cerrar por abajo (el filo de Contorno pegado).
    function trazoDock(l, cx, pegado, abajo) {
        const m = q => [2 * cx - q[0], q[1]];
        const n = q => q[0].toFixed(2) + " " + q[1].toFixed(2);
        const [S, a1, b1, P1, a2, b2, P2, a3, b3, T] = l;
        const p = `M${n(S)} C${n(a1)} ${n(b1)} ${n(P1)} C${n(a2)} ${n(b2)} ${n(P2)} C${n(a3)} ${n(b3)} ${n(T)} L${n(m(T))} `
                + `C${n(m(b3))} ${n(m(a3))} ${n(m(P2))} C${n(m(b2))} ${n(m(a2))} ${n(m(P1))} C${n(m(b1))} ${n(m(a1))} ${n(m(S))}`;
        if (abajo < 0) return p;
        return pegado ? p + ` V${abajo.toFixed(2)} H${S[0].toFixed(2)} Z` : p + " Z";
    }

    // ---- Materiales del dock (Dock.qml y sus muestras en Ajustes) ----
    function dockConVidrio(m) { return ["vidrio", "ahumado", "escarcha", "tinte"].includes(m); }
    // Material You: el color mas vivo del fondo de pantalla, llevado a un tono oscuro.
    // Casi gris: el acento del tema, para que nunca quede apagado.
    function tonoMaterialYou(colores) {
        let mejor = null, puntos = -1;
        for (const c of colores) {
            const p = c.hsvSaturation * Math.min(1, c.hsvValue * 2);
            if (p > puntos) { puntos = p; mejor = c; }
        }
        const base = mejor && mejor.hsvSaturation > 0.12 ? mejor : acento;
        return Qt.hsla(base.hslHue, Math.min(0.32, Math.max(0.18, base.hslSaturation * 0.5)), 0.17, 1);
    }
    // Tono de Material You del fondo de pantalla actual (el dock y el fundido del marco).
    property string fondoPantalla: ""
    Process {
        id: leerFondo
        command: ["sh", "-c", "awww query 2>/dev/null | sed -n 's/.*image: //p' | head -1"]
        stdout: StdioCollector { onStreamFinished: estilo.fondoPantalla = text.trim() }
    }
    Timer { running: estilo.valor("dockMaterial") === "materialyou"; repeat: true; triggeredOnStart: true; interval: 5000; onTriggered: leerFondo.running = true }
    ColorQuantizer { id: cuantizador; source: estilo.fondoPantalla ? "file://" + estilo.fondoPantalla : ""; depth: 3; rescaleSize: 64 }
    readonly property color tonoDock: tonoMaterialYou(cuantizador.colors)
    // Dock pegado al borde de abajo del marco: hace falta el marco y un material sin vidrio
    // (el vidrio no se puede fundir con el marco).
    readonly property bool dockPegado: valor("dockPegado") && grosorMarco > 0 && !dockConVidrio(valor("dockMaterial"))
    // Color al que baja el marco: el del dock pegado de Material You; en los demas, el negro de siempre.
    readonly property color colorMarcoAbajo: dockPegado && valor("dockMaterial") === "materialyou" ? tonoDock : fondo
    // [relleno, filo, ancho del filo] de cada material
    function aspectoDock(m, tono, encima) {
        return ({
            vidrio:      [Qt.rgba(1, 1, 1, encima ? 0.06 : 0.03), Qt.rgba(1, 1, 1, 0.18), 1],
            solido:      [fondo, borde, 1],
            ahumado:     [Qt.rgba(0, 0, 0, 0.5), Qt.rgba(1, 1, 1, 0.1), 1],
            escarcha:    [Qt.rgba(1, 1, 1, encima ? 0.26 : 0.22), Qt.rgba(1, 1, 1, 0.42), 1],
            tinte:       [Qt.alpha(acento, encima ? 0.22 : 0.16), Qt.alpha(acento, 0.45), 1],
            contorno:    [Qt.rgba(1, 1, 1, 0), Qt.rgba(1, 1, 1, 0.5), 1.5],
            materialyou: [tono, Qt.alpha(Qt.hsla(tono.hslHue, 0.6, 0.85, 1), 0.18), 1]
        })[m] || [Qt.rgba(1, 1, 1, 0.03), Qt.rgba(1, 1, 1, 0.18), 1];
    }

    // ---- Aspecto ----
    // Marco de pantalla (Marco.qml): grosor real, 0 si esta apagado. La isla baja lo mismo.
    readonly property int grosorMarco: valor("marco") ? 6 : 0
    property real anchoBandeja: 0          // lo escribe Bandeja.qml; la oreja del marco se ensancha
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
    // Vista general de niri abierta (la pone shell.qml): la isla, el dock y los botones se van
    // con una ola de colores (Gelatina) y salen el fondo borroso y el minimapa.
    property bool vistaGeneral: false
    onVistaGeneralChanged: if (vistaGeneral) leerFondo.running = true
    property bool noMolestar: false
    function ponerNoMolestar(v) { Quickshell.execDetached(["hokum", "dnd", v ? "on" : "off"]); }
    Process {
        running: true
        command: ["hokum", "dnd", "--watch"]
        stdout: SplitParser { onRead: data => estilo.noMolestar = data.trim() === "on" }
    }

    function niri(args) { Quickshell.execDetached(["python3", carpeta + "/menisco-niri.py"].concat(args)); }
}
