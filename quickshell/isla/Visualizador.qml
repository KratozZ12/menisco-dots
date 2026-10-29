import QtQuick
import Quickshell
import Quickshell.Io

// Visualizador de audio de la isla: 5 barras redondeadas que siguen el sonido real (cava).
// En silencio las barras se aplanan y aparece una sola linea ondulada, suave, que se desliza.
Canvas {
    id: vis

    readonly property var forma: [0.55, 0.8, 1, 0.8, 0.55]   // mas altas al centro
    readonly property real anchoBarra: 3.5
    readonly property real hueco: 3
    readonly property real alto: 22

    property var niveles: [0, 0, 0, 0, 0]     // lo que manda cava, de 0 a 1
    property var vistos: [0, 0, 0, 0, 0]      // lo dibujado: sube rapido, baja despacio
    property bool suena: false
    property real mezcla: 1                   // 0 = barras, 1 = linea ondulada

    implicitWidth: 5 * anchoBarra + 4 * hueco + 4
    implicitHeight: alto + 4
    renderStrategy: Canvas.Cooperative

    Process {
        running: true
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/quickshell/isla/cava.conf"]
        stdout: SplitParser {
            onRead: linea => {
                const v = linea.split(";").filter(s => s !== "").map(n => Math.min(1, parseInt(n) / 100));
                if (v.length !== 5) return;
                vis.niveles = v;
                if (v.some(n => n > 0.02)) { vis.suena = true; silencio.restart(); }
            }
        }
    }
    // Sin sonido un rato (o cava dormido) = silencio.
    Timer { id: silencio; interval: 900; onTriggered: vis.suena = false }

    onPaint: {
        const c = getContext("2d");
        c.reset();
        const cy = height / 2, x0 = 2;
        const ancho = 5 * anchoBarra + 4 * hueco;

        c.globalAlpha = 1 - mezcla;
        c.fillStyle = "#ffffff";
        for (let i = 0; i < 5; i++) {
            const h = Math.max(anchoBarra, alto * vistos[i] * (1 - mezcla));
            c.beginPath();
            c.roundedRect(x0 + i * (anchoBarra + hueco), cy - h / 2, anchoBarra, h, anchoBarra / 2, anchoBarra / 2);
            c.fill();
        }

        // Linea ondulada plana: poca altura y onda larga, nada de picos.
        if (mezcla > 0.01) {
            const t = Date.now();
            const amp = 1.3 * mezcla, onda = 14, largo = ancho * (0.55 + 0.45 * mezcla);
            const inicio = x0 + (ancho - largo) / 2;
            c.globalAlpha = mezcla;
            c.strokeStyle = "#ffffff";
            c.lineWidth = 1.6;
            c.lineCap = "round";
            c.beginPath();
            for (let x = 0; x <= largo; x += 0.5) {
                const y = cy + Math.sin(x / onda * Math.PI * 2 - t / 520) * amp;
                if (x === 0) c.moveTo(inicio, y); else c.lineTo(inicio + x, y);
            }
            c.stroke();
        }
    }

    // Con musica: a cada cuadro. En silencio la onda va lenta, basta con 30 cuadros por segundo.
    FrameAnimation {
        running: vis.visible && (vis.suena || vis.mezcla < 0.99)
        onTriggered: vis.avanzar(frameTime * 60)
    }
    Timer {
        interval: 33
        repeat: true
        running: vis.visible && !vis.suena && vis.mezcla >= 0.99
        onTriggered: vis.avanzar(2)
    }

    function avanzar(dt) {
        const v = vistos.slice();
        for (let i = 0; i < 5; i++) {
            const objetivo = suena ? niveles[i] * forma[i] : 0;
            const k = objetivo > v[i] ? 0.35 : 0.12;
            v[i] += (objetivo - v[i]) * Math.min(1, k * dt);
        }
        vistos = v;
        mezcla += ((suena ? 0 : 1) - mezcla) * Math.min(1, 0.08 * dt);
        requestPaint();
    }
}
