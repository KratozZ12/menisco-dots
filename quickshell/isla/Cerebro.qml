pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Cerebro de la Gota, compartido por las islas de todos los monitores.
// Habla con OpenCode por gota/gota.sh (caja de solo lectura) y aplica los planes con
// gota/gota-plan.py, que es lo unico que cambia archivos, y solo tras "Hazlo".
Singleton {
    id: cerebro

    readonly property string dir: Estilo.carpeta + "/gota"
    // libre | pensando | plan | aplicando | error
    property string estado: "libre"
    property var mensajes: []          // [{ de: "yo" | "gota", texto, extra? }]
    property string paso: ""           // lo que esta haciendo ahora ("Leyendo Descargas")
    property var plan: null            // plan propuesto, esperando Hazlo / Cancelar
    property string sesion: ""         // conversacion de OpenCode que se continua
    property string nota: ""           // se antepone al siguiente mensaje ("el plan se aplico")
    property bool puedeDeshacer: false
    property string carpetaPlan: ""
    property string resumenHecho: ""   // "9 archivos movidos, 1 a la papelera"    // para "Abrir carpeta" despues de aplicar
    property real inicio: 0
    property string textoParcial: ""
    property bool escribiendo: false   // el usuario tiene texto en el campo

    readonly property bool ocupada: estado === "pensando" || estado === "aplicando"
    // Cara de la Gota: vacia = la de siempre
    readonly property string emocion: ocupada ? "pensar"
        : estado === "error" ? "confuso"
        : estado === "plan" ? "normal"
        : escribiendo ? "escucha"
        : contenta ? "feliz"
        : ""
    // Unos segundos feliz despues de contestar bien.
    property bool contenta: false
    property real fin: 0
    onFinChanged: { contenta = estado !== "error"; alegria.restart(); }
    Timer { id: alegria; interval: 6000; onTriggered: cerebro.contenta = false }
    signal termino(string texto)

    function agregar(de, texto, extra) { mensajes = mensajes.concat([{ de: de, texto: texto, extra: extra || "" }]); }

    function preguntar(texto) {
        texto = texto.trim();
        if (!texto || ocupada) return;
        if (estado === "plan") cancelar();
        agregar("yo", texto);
        const envio = (nota ? nota + "\n" : "") + texto;
        nota = "";
        estado = "pensando"; paso = ""; textoParcial = ""; inicio = Date.now();
        proceso.environment = sesion ? { GOTA_SESION: sesion } : {};
        proceso.command = [dir + "/gota.sh", envio];
        proceso.running = true;
    }
    function detener() { if (proceso.running) proceso.signal(15); }
    function nueva() {
        detener();
        mensajes = []; plan = null; sesion = ""; nota = ""; paso = ""; estado = "libre"; puedeDeshacer = false;
    }

    // Traduce una herramienta de OpenCode a una linea legible para la isla.
    function describir(herramienta, entrada) {
        const ruta = (entrada.filePath || entrada.path || "").replace(Quickshell.env("HOME"), "~");
        const cmd = (entrada.command || "").split(" ")[0];
        if (herramienta === "read") return "Leyendo " + (ruta || "un archivo");
        if (herramienta === "list" || herramienta === "glob") return "Mirando " + (ruta || "carpetas");
        if (herramienta === "grep") return "Buscando " + (entrada.pattern || "");
        if (herramienta === "bash") return ({ ls: "Mirando carpetas", du: "Midiendo espacio", df: "Midiendo espacio",
            journalctl: "Leyendo registros del sistema", systemctl: "Revisando servicios", bluetoothctl: "Revisando Bluetooth",
            rfkill: "Revisando Bluetooth", wpctl: "Revisando el sonido", pactl: "Revisando el sonido",
            "nvidia-smi": "Revisando la gráfica", cat: "Leyendo un archivo", head: "Leyendo un archivo",
            tail: "Leyendo un archivo", grep: "Buscando" })[cmd] || "Revisando";
        return "Pensando";
    }

    Process {
        id: proceso
        stdout: SplitParser {
            onRead: linea => {
                let e;
                try { e = JSON.parse(linea); } catch (x) { return; }
                if (e.sessionID) cerebro.sesion = e.sessionID;
                const p = e.part || {};
                if (e.type === "tool_use") cerebro.paso = cerebro.describir(p.tool, (p.state && p.state.input) || {});
                else if (e.type === "text") cerebro.textoParcial += (cerebro.textoParcial ? "\n" : "") + (p.text || "");
                else if (e.type === "error") cerebro.textoParcial = "__error__" + ((e.error && e.error.data && e.error.data.message) || "");
            }
        }
        onExited: (codigo, estadoSalida) => {
            const t = cerebro.textoParcial;
            cerebro.paso = "";
            if (t.startsWith("__error__") || (!t && codigo !== 0)) {
                cerebro.estado = "error"; cerebro.fin = Date.now();
                cerebro.agregar("gota", codigo === 143 ? "Me detuve." : "No pude contestar: " + (t.slice(9).split("\n")[0].slice(0, 120) || "OpenCode falló."));
                cerebro.termino("");
                return;
            }
            // El plan viene al final en un bloque ```plan { ... } ```
            const m = t.match(/```plan\s*([\s\S]*?)```/);
            let plan = null;
            if (m) { try { plan = JSON.parse(m[1]); } catch (x) { plan = null; } }
            const texto = t.replace(/```plan[\s\S]*$/, "").replace(/\*\*/g, "").trim();
            cerebro.agregar("gota", texto || (plan ? "Así lo dejaría:" : "Listo."), plan ? "plan" : "");
            cerebro.plan = plan && plan.acciones && plan.acciones.length ? plan : null;
            cerebro.estado = cerebro.plan ? "plan" : "libre"; cerebro.fin = Date.now();
            if (m && !cerebro.plan) cerebro.agregar("gota", "El plan me salió mal escrito. Pídemelo otra vez.");
            cerebro.termino(texto);
        }
    }

    // ---- Vigilante de fallos (gota/vigilar.sh, cada minuto) ----
    // Avisa una vez por problema; si se arregla y vuelve a pasar, avisa otra vez.
    signal fallo(string clave, string titulo, string detalle)
    property var fallosActivos: ({})
    Timer {
        interval: 60000; repeat: true; triggeredOnStart: true
        running: Estilo.valor("avisoFallos")
        onTriggered: vigilante.running = true
    }
    Process {
        id: vigilante
        command: [cerebro.dir + "/vigilar.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                const ahora = {};
                for (const l of text.split("\n")) {
                    const [clave, titulo, detalle] = l.split("|");
                    if (!clave || !titulo) continue;
                    ahora[clave] = true;
                    if (!cerebro.fallosActivos[clave]) cerebro.fallo(clave, titulo, detalle || "");
                }
                cerebro.fallosActivos = ahora;
            }
        }
    }
    // Lo que se le pide a la Gota al pulsar "Arreglar"
    function arreglar(titulo, detalle) {
        preguntar("Arregla esto: " + titulo.toLowerCase() + ". Lo detectó el vigilante de Menisco: " + detalle + ". Mira los registros, dime la causa en una frase y propón el arreglo.");
    }

    // ---- Planes ----
    function hazlo() {
        if (estado !== "plan" || !plan) return;
        // Carpeta comun de lo que se mueve, para "Abrir carpeta"
        const rutas = plan.acciones.map(a => a.a || a.ruta || "").filter(r => r);
        carpetaPlan = rutas.length ? rutas.reduce((c, r) => { while (c && !r.startsWith(c + "/") && r !== c) c = c.replace(/\/[^/]*$/, ""); return c; }, rutas[0].replace(/\/[^/]*$/, "")) : "";
        const n = k => plan.acciones.filter(a => a.tipo === k).length;
        resumenHecho = [n("mover") && n("mover") + (n("mover") === 1 ? " archivo movido" : " archivos movidos"),
                        n("papelera") && n("papelera") + " a la papelera",
                        n("comando") && (n("comando") === 1 ? "1 comando" : n("comando") + " comandos")].filter(x => x).join(", ") || "Hecho";
        estado = "aplicando"; paso = "Aplicando el plan";
        aplicar.command = ["sh", "-c", "printf %s \"$1\" | \"$2\" aplicar -", "sh", JSON.stringify(plan), dir + "/gota-plan.py"];
        aplicar.running = true;
    }
    function cancelar() {
        if (estado !== "plan") return;
        plan = null; estado = "libre";
        nota = "(El usuario canceló el plan anterior: no se aplicó.)";
        agregar("gota", "Vale, no toco nada.");
    }
    function deshacer() {
        deshacerProc.running = true;
    }
    Process {
        id: aplicar
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (x) { r = { ok: false, errores: ["respuesta rara del guion"] }; }
                cerebro.paso = ""; cerebro.plan = null;
                if (r.ok) {
                    cerebro.estado = "libre"; cerebro.puedeDeshacer = true; cerebro.fin = Date.now();
                    cerebro.nota = "(El plan anterior ya se aplicó: " + r.hechos + " cambios.)";
                    cerebro.agregar("gota", "Listo. " + cerebro.resumenHecho + ". Nada borrado.", "hecho");
                } else {
                    cerebro.estado = "error"; cerebro.puedeDeshacer = (r.hechos || 0) > 0; cerebro.fin = Date.now();
                    cerebro.nota = "(El plan anterior falló: " + (r.errores || []).join("; ") + ")";
                    cerebro.agregar("gota", "No pude hacerlo todo: " + (r.errores || []).slice(0, 2).join("; "), cerebro.puedeDeshacer ? "hecho" : "");
                }
                cerebro.termino("");
            }
        }
    }
    Process {
        id: deshacerProc
        command: [cerebro.dir + "/gota-plan.py", "deshacer"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (x) { r = { ok: false, errores: ["respuesta rara del guion"] }; }
                cerebro.puedeDeshacer = false;
                cerebro.nota = "(El usuario deshizo el último plan.)";
                cerebro.agregar("gota", r.ok ? "Deshecho: todo volvió a su sitio." + ((r.avisos || []).length ? " Lo de la papelera sigue allí." : "")
                                             : "No pude deshacerlo todo: " + (r.errores || []).slice(0, 2).join("; "));
            }
        }
    }
}
