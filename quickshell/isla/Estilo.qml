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
        tema: "onix",                   // ver ordenTemas
        superficies: "suave",           // suave | negro
        seguirFondo: true, fondoAcento: "", fondoAcento2: "",   // tema "delfondo"
        letra: "SF Pro",                // SF Pro | Inter
        esquinas: 20, espacio: 16, borde: 40, marco: false, dockPegado: true,
        islaAsistente: true, islaVisualizador: true, reloj12: false, segundos: false,
        personalidad: "normal",         // tranquilo | normal | inquieto
        reaccionMusica: true,
        // Isla: como se abre y que avisos muestra (los avisos se ajustan en Notificaciones)
        dockMaterial: "vidrio", dockForma: "redondeada",   // vidrio | solido | ahumado | escarcha | tinte | contorno | materialyou
        islaForma: "clasica", islaFormaAbierta: "clasica",
        reproductorForma: "redondeada", reproductorTinte: "nada", miniDockApps: [],   // botones de arriba
        islaImagen: "",   // imagen de fondo de la pestana Acciones ("" = ninguna)
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
    // Las claves que ya no existen (el lanzador se quito) se descartan al leer.
    // Cuatro sitios, de izquierda a derecha: esquina izquierda, junto a la isla por la izquierda,
    // junto a la isla por la derecha y esquina derecha. Cada boton esta en uno solo.
    readonly property var zonasBotones: ["izquierda", "izquierdaIsla", "derechaIsla", "derecha"]
    readonly property var botones: datos.botonesArriba ? (b => {
            const r = {};
            for (const z of zonasBotones) r[z] = (b[z] || []).filter(c => botonesCatalogo.some(x => x[0] === c));
            return r;
        })(datos.botonesArriba)
        : barra.lado === "izquierda"
            ? { izquierda: (barra.boton ? ["barra"] : []).concat(["bandeja"]), izquierdaIsla: [], derechaIsla: [], derecha: ["menisco"] }
            : { izquierda: ["menisco"], izquierdaIsla: [], derechaIsla: [], derecha: ["bandeja"].concat(barra.boton ? ["barra"] : []) }
    function zonaDe(c) { return zonasBotones.find(z => botones[z].includes(c)) || "" }
    // [clave, nombre, icono]
    readonly property var botonesCatalogo: [["menisco", "Menisco (ajustes)", "deployed_code"], ["barra", "Barra lateral", "auto_awesome"],
        ["bandeja", "Bandeja de iconos", "more_horiz"], ["reproductor", "Mini reproductor", "play_circle"], ["minidock", "Mini dock", "dock_to_bottom"],
        ["micro", "Micrófono", "mic"], ["volumen", "Volumen", "volume_up"], ["color", "Color", "colorize"], ["grabar", "Grabar", "radio_button_checked"],
        ["captura", "Captura", "screenshot_region"],
        ["nomolestar", "No molestar", "do_not_disturb_on"], ["juego", "Modo juego", "sports_esports"], ["vista", "Vista general", "grid_view"],
        ["flotante", "Escritorio flotante", "web_asset"], ["bloquear", "Bloquear", "lock"], ["fondo", "Siguiente fondo", "wallpaper"]]
    // ---- Perfiles de diseño (Ajustes > Apariencia) ----
    // Guardan solo la apariencia; nunca el No molestar, el fondo ni rutas personales.
    readonly property var clavesPerfil: ["tema", "letra", "velocidad", "rebote", "marco", "esquinas", "espacio", "borde",
        "dockMaterial", "dockForma", "dockPegado", "islaForma", "islaFormaAbierta", "islaHuecos", "botonesArriba", "reproductorForma", "reproductorTinte", "vidrio"]
    readonly property var perfiles: datos.perfiles || []
    readonly property var fotoActual: {
        const d = {};
        for (const k of clavesPerfil) d[k] = k === "islaHuecos" ? huecos : k === "botonesArriba" ? botones : valor(k);
        return JSON.parse(JSON.stringify(d));
    }
    // El perfil que coincide en todo con lo que se ve ahora (-1 si ninguno)
    // Claves que un perfil viejo no tiene (agregadas despues) no cuentan: si no, ninguno saldria activo.
    readonly property int perfilActivo: perfiles.findIndex(p => clavesPerfil.every(k => !(k in p.datos) || JSON.stringify(p.datos[k]) === JSON.stringify(fotoActual[k])))
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
    function ponerBotones(b) { const r = {}; for (const z of zonasBotones) r[z] = (b[z] || []).slice(); poner("botonesArriba", r); }
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
        onLoaded: {
            let d;
            try { d = JSON.parse(text()); } catch (e) { return; }
            // Temas quitados el 20/11/2026: pasan a su pariente mas cercano, en el archivo y en los perfiles.
            const viejos = { jade: "agave", rubi: "obsidiana", medianoche: "tinta", niebla: "onix", grafito: "champan" };
            let cambio = false;
            if (viejos[d.tema]) { d.tema = viejos[d.tema]; cambio = true; }
            for (const p of d.perfiles || [])
                if (p.datos && viejos[p.datos.tema]) { p.datos.tema = viejos[p.datos.tema]; cambio = true; }
            estilo.datos = d;
            if (cambio) setText(JSON.stringify(d, null, 2));
        }
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
    // Doce temas oscuros (con "Del fondo"). Las piezas leen solo estos nombres, nunca un gris escrito a mano:
    // fondo (paneles), tarjeta (bloques dentro del panel), hover, hundido (campos y pistas),
    // borde y linea (filos finos), texto/texto2/texto3, apagado (interruptor sin activar),
    // activo + enActivo + iconoActivo + activoBorde (lo que esta encendido), acento (deslizadores,
    // interruptores, seleccion) y sobreAcento (la perilla encima del acento).
    // acento2: segundo tono, solo decorativo (franja de la tarjeta del tema, rayo y halo de la Gota).
    // texto2/texto3 pasan 4.5:1 sobre fondo y tarjeta en todos.
    readonly property var temasFijos: ({
        // El original: negro de verdad; el blanco marca lo que se toca.
        onix:       { nombre: "Ónix", desc: "El original", fondo: "#000000", tarjeta: "#141416", hover: "#1c1c1f", hundido: "#0c0c0e",
                      lateral: "#060607", luz: "#ffffff",
                      borde: "#1fffffff", linea: "#14ffffff", texto: "#f2f2f3", texto2: "#a1a1a6", texto3: "#7e7e84",
                      apagado: "#2a2a2d", activo: "#f2f2f3", enActivo: "#000000", iconoActivo: "#000000",
                      activoBorde: "#00000000", acento: "#f2f2f3", acento2: "#8e8e93", sobreAcento: "#000000" },
        champan:     { nombre: "Champán", desc: "Dorado y burbujas", fondo: "#050403", tarjeta: "#13110d", hover: "#1b1812", hundido: "#0b0a08",
                      borde: "#1ff5e8d0", linea: "#14f5e8d0", texto: "#f5f1ea", texto2: "#96938d", texto3: "#827f79",
                      apagado: "#232018", activo: "#e6c68a", enActivo: "#000000", iconoActivo: "#000000",
                      activoBorde: "#00000000", acento: "#e6c68a", acento2: "#f5e9d0", sobreAcento: "#000000" },
        mercurio:    { nombre: "Mercurio", desc: "Plata líquida", fondo: "#050507", tarjeta: "#131418", hover: "#1b1c21", hundido: "#0b0c0f",
                      borde: "#1fe9ebef", linea: "#14e9ebef", texto: "#eef0f4", texto2: "#96989c", texto3: "#7e8084",
                      apagado: "#23252c", activo: "#c9ced6", enActivo: "#000000", iconoActivo: "#000000",
                      activoBorde: "#00000000", acento: "#c9ced6", acento2: "#8e96a3", sobreAcento: "#000000" },
        tinta:       { nombre: "Tinta", desc: "Azul de pluma", fondo: "#04050a", tarjeta: "#0f1220", hover: "#15192c", hundido: "#090b14",
                      borde: "#1fbdcbfd", linea: "#14bdcbfd", texto: "#eef1fb", texto2: "#9598a3", texto3: "#7c7f8b",
                      apagado: "#1c2139", activo: "#5b7cfa", enActivo: "#000000", iconoActivo: "#000000",
                      activoBorde: "#00000000", acento: "#5b7cfa", acento2: "#2b3a8c", sobreAcento: "#000000" },
        aurora:      { nombre: "Aurora", desc: "Verde y violeta", fondo: "#040807", tarjeta: "#0d1614", hover: "#121e1b", hundido: "#080e0d",
                      borde: "#1fcbfae6", linea: "#14cbfae6", texto: "#ecf7f3", texto2: "#939d9a", texto3: "#78827f",
                      apagado: "#172623", activo: "#7cf2c0", enActivo: "#000000", iconoActivo: "#000000",
                      activoBorde: "#00000000", acento: "#7cf2c0", acento2: "#b59cff", sobreAcento: "#000000" },
        cempasuchil: { nombre: "Cempasúchil", desc: "Flor y papel picado", fondo: "#080503", tarjeta: "#17100a", hover: "#1f160e", hundido: "#0f0a06",
                      borde: "#1fffd0a5", linea: "#14ffd0a5", texto: "#fbf0e6", texto2: "#a0968e", texto3: "#877e76",
                      apagado: "#281d12", activo: "#ff8a1f", enActivo: "#000000", iconoActivo: "#000000",
                      activoBorde: "#00000000", acento: "#ff8a1f", acento2: "#9b5cf0", sobreAcento: "#000000" },
        fosforo:    { nombre: "Fósforo", desc: "Ámbar de terminal", fondo: "#0a0702", tarjeta: "#130e05", hover: "#21180a", hundido: "#1a1307",
                      borde: "#26ffb347", linea: "#14ffb347", texto: "#ffd9a0", texto2: "#b08a52", texto3: "#977645",
                      apagado: "#2c2210", activo: "#ffb347", enActivo: "#1a1003", iconoActivo: "#1a1003",
                      activoBorde: "#00000000", acento: "#ffb347", acento2: "#b8701c", sobreAcento: "#1a1003" },
        neon:        { nombre: "Neón", desc: "Tokio de noche", fondo: "#050308", tarjeta: "#0e0a14", hover: "#130e1b", hundido: "#09060d",
                      borde: "#1fa3f5fa", linea: "#14a3f5fa", texto: "#f6eefe", texto2: "#9993a0", texto3: "#807a87",
                      apagado: "#181222", activo: "#19e6f2", enActivo: "#000000", iconoActivo: "#000000",
                      activoBorde: "#00000000", acento: "#19e6f2", acento2: "#ff3dcb", sobreAcento: "#000000" },
        obsidiana:   { nombre: "Obsidiana", desc: "Vidrio volcánico", fondo: "#070404", tarjeta: "#160d0c", hover: "#1e1210", hundido: "#0e0808",
                      borde: "#1fffc3b1", linea: "#14ffc3b1", texto: "#f8edeb", texto2: "#9e9392", texto3: "#857b79",
                      apagado: "#271715", activo: "#ff6a3d", enActivo: "#000000", iconoActivo: "#000000",
                      activoBorde: "#00000000", acento: "#ff6a3d", acento2: "#8c2f1c", sobreAcento: "#000000" },
        agave:       { nombre: "Agave", desc: "Verde del campo", fondo: "#040706", tarjeta: "#0e1614", hover: "#141e1c", hundido: "#080e0c",
                      borde: "#1fcce9dd", linea: "#14cce9dd", texto: "#eaf4f0", texto2: "#929b98", texto3: "#7a8380",
                      apagado: "#1a2724", activo: "#7fc8a9", enActivo: "#000000", iconoActivo: "#000000",
                      activoBorde: "#00000000", acento: "#7fc8a9", acento2: "#3e7d6a", sobreAcento: "#000000" },
        pitahaya:    { nombre: "Pitahaya", desc: "Rosa y verde", fondo: "#08040a", tarjeta: "#170e19", hover: "#1f1421", hundido: "#0f0811",
                      borde: "#1fffb9da", linea: "#14ffb9da", texto: "#f9edf6", texto2: "#9f949e", texto3: "#867b85",
                      apagado: "#281a2a", activo: "#ff4fa3", enActivo: "#000000", iconoActivo: "#000000",
                      activoBorde: "#00000000", acento: "#ff4fa3", acento2: "#7bd88f", sobreAcento: "#000000" }
    })
    // "Del fondo": el acento sale del fondo de pantalla; las superficies son negro con un 4-5 % de el.
    // Con "Seguir al fondo" apagado se queda el ultimo acento calculado (fondoAcento).
    function colorVivo(colores) {
        let mejor = null, puntos = -1;
        for (const c of colores) {
            const p = c.hsvSaturation * Math.min(1, c.hsvValue * 2);
            if (p > puntos) { puntos = p; mejor = c; }
        }
        if (!mejor || mejor.hsvSaturation < 0.12) return Qt.color("#d8d8dc");
        return Qt.hsla(mejor.hslHue, Math.min(0.8, Math.max(0.45, mejor.hslSaturation)), 0.72, 1);
    }
    readonly property color acentoFondo: valor("seguirFondo") || !valor("fondoAcento") ? colorVivo(cuantizador.colors) : Qt.color(valor("fondoAcento"))
    // acento2 de "Del fondo": el segundo color mas vivo del mismo cuantizador, con otro matiz si lo hay;
    // si el fondo solo tiene uno, el acento oscurecido.
    function colorVivo2(colores, a) {
        let mejor = null, puntos = -1;
        for (const c of colores) {
            const d = Math.abs(c.hslHue - a.hslHue), dh = Math.min(d, 1 - d);
            const p = c.hsvSaturation * Math.min(1, c.hsvValue * 2);
            if (dh > 0.08 && c.hsvSaturation > 0.12 && p > puntos) { puntos = p; mejor = c; }
        }
        if (!mejor) return Qt.hsla(a.hslHue, a.hslSaturation * 0.8, 0.42, 1);
        return Qt.hsla(mejor.hslHue, Math.min(0.75, Math.max(0.4, mejor.hslSaturation)), 0.6, 1);
    }
    readonly property color acento2Fondo: valor("seguirFondo") || !valor("fondoAcento2") ? colorVivo2(cuantizador.colors, acentoFondo) : Qt.color(valor("fondoAcento2"))
    readonly property var temaFondo: {
        const a = acentoFondo, t = (base, k) => Qt.tint(base, Qt.alpha(a, k));
        return { nombre: "Del fondo", desc: "Automático", fondo: t("#000000", 0.045), tarjeta: t("#141416", 0.05), hover: t("#1c1c1f", 0.06),
                 hundido: t("#0c0c0e", 0.05), lateral: t("#060607", 0.045), luz: a,
                 borde: Qt.alpha(t("#ffffff", 0.3), 0.12), linea: Qt.alpha(t("#ffffff", 0.3), 0.08),
                 texto: "#f2f2f3", texto2: "#a1a1a6", texto3: "#86868c", apagado: t("#2a2a2d", 0.08),
                 activo: a, enActivo: "#000000", iconoActivo: "#000000", activoBorde: "#00000000", acento: a, acento2: acento2Fondo, sobreAcento: "#000000" };
    }
    readonly property var temas: Object.assign({ delfondo: temaFondo }, temasFijos)
    // Los seis de arriba se ven siempre en Ajustes; el resto, con "Mostrar más".
    readonly property var ordenTemas: ["onix", "delfondo", "champan", "mercurio", "tinta", "aurora",
        "cempasuchil", "fosforo", "neon", "obsidiana", "agave", "pitahaya"]
    // Superficies "negro": fondo, tarjetas y menu de Ónix con el acento del tema elegido.
    readonly property var tema: {
        const t = temas[valor("tema")] || temas.onix;
        if (valor("superficies") !== "negro" || t === temas.onix) return t;
        const o = temas.onix;
        return Object.assign({}, t, { fondo: o.fondo, tarjeta: o.tarjeta, hover: o.hover, hundido: o.hundido, lateral: o.lateral });
    }
    // Al cambiar de tema cada color pasa al nuevo en un fundido (Behavior), no de golpe.
    property color fondo: tema.fondo
    Behavior on fondo { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color tarjeta: tema.tarjeta
    Behavior on tarjeta { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color hover: tema.hover
    Behavior on hover { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    readonly property color nada: Qt.alpha(hover, 0)     // hover apagado: transparente del mismo tono
    property color hundido: tema.hundido
    Behavior on hundido { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    // Menu lateral de Ajustes: el fondo apenas mas claro (Ónix: #060607).
    property color lateral: tema.lateral ?? Qt.tint(tema.fondo, Qt.alpha(tema.texto, 0.025))
    Behavior on lateral { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    // La unica luz de Ajustes (rayo y halo de la Gota, luz de arriba): blanca en Ónix, el acento en los demas.
    property color luz: tema.luz ?? tema.acento
    Behavior on luz { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    // Hover: el tono de hover aclarado para que se note sobre cualquier fondo del tema.
    readonly property color realce: Qt.tint(hover, Qt.alpha(texto, 0.09))
    function aclarar(c) { return Qt.tint(c, Qt.alpha(texto, 0.14)) }
    property color borde: tema.borde
    Behavior on borde { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color linea: tema.linea
    Behavior on linea { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color texto: tema.texto
    Behavior on texto { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color texto2: tema.texto2
    Behavior on texto2 { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color texto3: tema.texto3
    Behavior on texto3 { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color apagado: tema.apagado
    Behavior on apagado { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color activo: tema.activo
    Behavior on activo { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color enActivo: tema.enActivo
    Behavior on enActivo { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color iconoActivo: tema.iconoActivo
    Behavior on iconoActivo { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color activoBorde: tema.activoBorde
    Behavior on activoBorde { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color acento: tema.acento
    Behavior on acento { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color acento2: tema.acento2 ?? Qt.darker(tema.acento, 1.6)
    Behavior on acento2 { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
    property color sobreAcento: tema.sobreAcento
    Behavior on sobreAcento { ColorAnimation { duration: estilo.t(450); easing.type: Easing.InOutQuad } }
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
            // el corte crece con el alto: 12 en la isla pequena, ~28 en la vista grande
            const c = Math.max(12, Math.min(28, h * 0.08));
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
    // Cada 5 s cuando el color depende del fondo (dock Material You o tema "Del fondo"); si no, una vez
    // por minuto, para que la muestra de "Del fondo" en Ajustes ya tenga su color.
    Timer {
        readonly property bool importa: estilo.valor("dockMaterial") === "materialyou" || (estilo.valor("tema") === "delfondo" && estilo.valor("seguirFondo"))
        running: true; repeat: true; triggeredOnStart: true; interval: importa ? 5000 : 60000
        onTriggered: leerFondo.running = true
    }
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
    readonly property int anchoMarco: 6
    readonly property int grosorMarco: valor("marco") ? anchoMarco : 0
    property real sepBandeja: -1           // lo escribe Esquina.qml: distancia del borde al hueco de la bandeja
    property real xBandeja: 0              // junto a la isla: x del hueco desde el borde izquierdo (Esquina.qml)
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
