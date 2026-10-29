import QtQuick
import "asistente.js" as Motor

// Asistente de la isla (todavia no hace nada). El dibujo y el movimiento viven en asistente.js.
// Cuando queda quieto se duerme: la animacion por cuadro se detiene y una alarma lo despierta
// justo para su siguiente gesto, asi no gasta CPU entre gesto y gesto.
Canvas {
    id: lienzo
    property string emocion: "normal"
    property bool despierto: true
    readonly property real radio: Math.min(width, height) * 0.38

    onEmocionChanged: { Motor.poner(emocion); despierto = true }
    renderStrategy: Canvas.Cooperative

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        Motor.dibujar(ctx, width / 2, height / 2, radio, 1.3);
    }

    FrameAnimation {
        running: lienzo.visible && lienzo.despierto
        onTriggered: {
            if (Motor.avanzar(Date.now(), frameTime * 60)) {
                lienzo.requestPaint();
            } else {
                lienzo.despierto = false;
                alarma.interval = Motor.msHastaGesto();
                alarma.restart();
            }
        }
    }

    Timer { id: alarma; onTriggered: lienzo.despierto = true }
}
