import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Aviso de volumen: capsula horizontal que se llena de liquido con borde ondulado.
// Aparece sobre el dock al cambiar el volumen o el silencio y se va a los 1.8 s.
PanelWindow {
    id: osd

    readonly property var salida: Pipewire.defaultAudioSink
    readonly property real volumen: salida && salida.audio ? Math.min(salida.audio.volume, 1) : 0
    readonly property bool mudo: salida && salida.audio ? salida.audio.muted : false
    readonly property var curvaIos: [0.32, 0.72, 0, 1, 1, 1]

    property bool mostrar: false
    property bool listo: false          // no avisar con el valor inicial al arrancar
    property real visto: volumen        // nivel dibujado: persigue al real con un resorte
    property real velocidad: 0
    property real agite: 0              // golpe de oleaje en cada cambio

    PwObjectTracker { objects: [osd.salida] }

    onVolumenChanged: avisar()
    onMudoChanged: avisar()
    Timer { interval: 800; running: true; onTriggered: osd.listo = true }
    Timer { id: ocultar; interval: 1800; onTriggered: osd.mostrar = false }

    function avisar() {
        if (!listo) return;
        agite = 1;
        mostrar = true;
        ocultar.restart();
    }

    anchors.bottom: true
    margins.bottom: 96                  // encima del dock (64 de alto + 10 de margen + aire)
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 220
    implicitHeight: 38
    color: "transparent"
    visible: mostrar || capsula.opacity > 0.01
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "volumen"
    mask: Region {}                     // no roba clics

    Item {
        id: capsula
        anchors.fill: parent
        opacity: osd.mostrar ? 1 : 0
        scale: osd.mostrar ? 1 : 0.92
        // Entra y sale despacio: fundido largo y escala con la curva de iOS en ambos sentidos.
        Behavior on opacity { NumberAnimation { duration: osd.mostrar ? 380 : 480; easing.type: osd.mostrar ? Easing.OutCubic : Easing.InOutCubic } }
        Behavior on scale { NumberAnimation { duration: osd.mostrar ? 650 : 480; easing.type: Easing.BezierSpline; easing.bezierCurve: osd.curvaIos } }

        Canvas {
            id: lienzo
            anchors.fill: parent
            renderStrategy: Canvas.Cooperative

            onPaint: {
                const c = getContext("2d");
                const w = width, h = height, r = h / 2;
                c.reset();

                // Vidrio de fondo
                c.beginPath();
                c.roundedRect(0, 0, w, h, r, r);
                c.fillStyle = "rgba(36,36,36,0.92)";
                c.fill();
                c.save();
                c.clip();

                // Liquido: el borde derecho ondula; se agita mas si el volumen cambia rapido.
                const t = Date.now();
                const amp = 0.9 + Math.abs(osd.velocidad) * 45 + osd.agite * 1.4;
                const borde = w * osd.visto;
                c.beginPath();
                c.moveTo(0, 0);
                for (let y = 0; y <= h; y += 2)
                    c.lineTo(borde + Math.sin(y / 6 + t / 380) * amp + Math.sin(y / 3.5 - t / 290) * amp * 0.35, y);
                c.lineTo(0, h);
                c.closePath();
                c.fillStyle = osd.mudo ? "#8a8a8a" : "#f2f2f2";
                c.fill();
                c.restore();
            }
        }

        // Icono y numero: oscuros cuando el liquido los cubre, blancos cuando no.
        Text {
            id: icono
            anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
            text: osd.mudo || osd.visto < 0.005 ? "volume_off" : osd.visto < 0.5 ? "volume_down" : "volume_up"
            color: osd.visto * capsula.width > x + width * 0.7 ? "#1c1c1c" : "#ffffff"
            Behavior on color { ColorAnimation { duration: 320; easing.type: Easing.InOutCubic } }
            font { family: "Material Symbols Rounded"; pixelSize: 18 }
            font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 24 }
            renderType: Text.NativeRendering
        }
        Text {
            anchors { right: parent.right; rightMargin: 15; verticalCenter: parent.verticalCenter; verticalCenterOffset: 1 }
            text: osd.mudo ? "" : Math.round(osd.visto * 100)
            color: osd.visto * capsula.width > x + width * 0.5 ? "#1c1c1c" : "#ffffff"
            Behavior on color { ColorAnimation { duration: 320; easing.type: Easing.InOutCubic } }
            font { family: "SF Pro Text"; pixelSize: 13; weight: Font.DemiBold; letterSpacing: -0.08 }
            font.features: { "tnum": 1 }
        }
    }

    // Resorte del nivel y oleaje; solo corre mientras el aviso esta en pantalla.
    FrameAnimation {
        running: osd.visible
        onTriggered: {
            const objetivo = osd.mudo ? 0 : osd.volumen;
            // Resorte blando: el nivel llega sin prisa y casi sin pasarse.
            osd.velocidad = (osd.velocidad + (objetivo - osd.visto) * 0.045) * 0.8;
            osd.visto += osd.velocidad;
            osd.agite *= 0.95;
            lienzo.requestPaint();
        }
    }
}
