import QtQuick
import "asistente.js" as Motor

// Asistente de la isla (todavia no hace nada). El dibujo y el movimiento viven en asistente.js.
// Cuando queda quieto se duerme: la animacion por cuadro se detiene y una alarma lo despierta
// justo para su siguiente gesto, asi no gasta CPU entre gesto y gesto.
Canvas {
    id: lienzo
    property string emocion: "normal"
    property real ritmo: 1
    property bool fondoNegro: false
    onRitmoChanged: Motor.ponerRitmo(ritmo)
    // Gota elegida en Ajustes > Asistente. Con la isla negra, una gota casi negra se perderia:
    // se aclara un poco.
    property var gota: Estilo.gota
    function aplicarGota() {
        const c = Qt.color(gota.color);
        let rgb = [c.r * 255, c.g * 255, c.b * 255];
        if (fondoNegro && rgb[0] + rgb[1] + rgb[2] < 60) rgb = [44, 44, 46];
        Motor.personalizar(gota.forma, rgb, gota.cambia);
        despierto = true;
    }
    onGotaChanged: aplicarGota()
    onFondoNegroChanged: aplicarGota()
    Component.onCompleted: aplicarGota()
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

    function parpadear() { Motor.parpadear(Date.now(), 1); despierto = true }
}
