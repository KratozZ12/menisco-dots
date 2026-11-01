import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

// Visualizador de audio de la isla: 5 barras redondeadas que siguen el sonido real (cava).
// En silencio las barras se aplanan y aparece una sola linea ondulada, suave, que se desliza.
// Barras y onda son piezas nativas (Rectangle y Shape), no un Canvas: con NVIDIA cada repintado
// de un Canvas sube una imagen nueva a la grafica, y eso solo era ~20 % de un nucleo del shell.
Item {
    id: vis

    readonly property var forma: [0.55, 0.8, 1, 0.8, 0.55]   // mas altas al centro
    readonly property real anchoBarra: 3.5
    readonly property real hueco: 3
    readonly property real alto: 22
    readonly property real ancho: 5 * anchoBarra + 4 * hueco
    readonly property real cy: height / 2

    property var niveles: [0, 0, 0, 0, 0]     // lo que manda cava, de 0 a 1
    property var vistos: [0, 0, 0, 0, 0]      // lo dibujado: sube rapido, baja despacio
    property bool suena: false
    property real mezcla: 1                   // 0 = barras, 1 = linea ondulada
    property var puntosOnda: []

    implicitWidth: ancho + 4
    implicitHeight: alto + 4

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

    Repeater {
        model: 5
        Rectangle {
            required property int index
            readonly property real h: Math.max(vis.anchoBarra, vis.alto * vis.vistos[index] * (1 - vis.mezcla))
            x: 2 + index * (vis.anchoBarra + vis.hueco)
            y: vis.cy - h / 2
            width: vis.anchoBarra; height: h; radius: vis.anchoBarra / 2
            color: "#ffffff"
            opacity: 1 - vis.mezcla
            visible: opacity > 0.01
        }
    }

    // Linea ondulada plana: poca altura y onda larga, nada de picos.
    Shape {
        anchors.fill: parent
        visible: vis.mezcla > 0.01
        opacity: vis.mezcla
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "#ffffff"
            strokeWidth: 1.6
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: vis.puntosOnda }
        }
    }

    // Con musica, 30 cuadros por segundo, lo mismo que manda cava (cava.conf): cada cuadro de la isla
    // cuesta CPU aunque cambie poco, y a 60 gastaba casi el doble. En silencio la onda avanza menos
    // de medio pixel por cuadro: con 15 por segundo no se nota la diferencia.
    Timer {
        interval: vis.suena || vis.mezcla < 0.99 ? 33 : 66
        repeat: true
        running: vis.visible
        onTriggered: vis.avanzar(interval / 16.7)
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

        if (mezcla > 0.01) {
            const t = Date.now();
            const amp = 1.3 * mezcla, onda = 14, largo = ancho * (0.55 + 0.45 * mezcla);
            const inicio = 2 + (ancho - largo) / 2;
            const p = [];
            for (let x = 0; x <= largo; x += 1)
                p.push(Qt.point(inicio + x, cy + Math.sin(x / onda * Math.PI * 2 - t / 520) * amp));
            puntosOnda = p;
        }
    }
}
