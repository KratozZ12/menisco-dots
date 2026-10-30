import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell.Widgets

// Boton vertical del asistente (isla expandida). Todavia no hace nada: es la puerta para
// hablar con el cuando se conecte. Capas, de atras hacia adelante:
// halo azul difuso que gira, borde de luz que gira, cuerpo oscuro con tres luces que flotan
// y se mezclan (desenfocadas), resplandor detras de la cara, chispas que suben, el asistente.
Item {
    id: boton
    property alias emocion: cara.emocion
    readonly property bool encima: sobre.hovered
    signal pulsado()

    function aparecer() { cara.parpadear(); }

    width: 132
    height: 276
    scale: zona.pressed ? 0.95 : (sobre.hovered ? 1.03 : 1)
    Behavior on scale { NumberAnimation { duration: Estilo.t(zona.pressed ? 90 : 480); easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.2) } }

    // Angulo de la luz que recorre halo y borde (una vuelta cada 5 s).
    // Con "Luz que gira" apagado todo se queda quieto (giro, luces, latido y chispas).
    // Tampoco se anima mientras no se ve (isla cerrada u otra pestana): una animacion infinita
    // invisible sigue despertando al dibujado en cada cuadro.
    readonly property bool animar: Estilo.valor("botLuz") && boton.visible
    property real giro: 0
    NumberAnimation on giro { running: boton.animar; from: 0; to: 360; duration: 5000; loops: Animation.Infinite }

    // Halo exterior: la luz, difuminada; se intensifica con el cursor encima.
    Item {
        anchors.fill: parent
        opacity: sobre.hovered ? 1 : 0.65
        Behavior on opacity { NumberAnimation { duration: 400 } }
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 40; autoPaddingEnabled: true }
        Shape {
        x: -14; y: -14
        width: boton.width + 28; height: boton.height + 28
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: ConicalGradient {
                centerX: boton.width / 2 + 14; centerY: boton.height / 2 + 14
                angle: boton.giro
                    GradientStop { position: 0.0; color: "#003aa0ff" }
                    GradientStop { position: 0.15; color: "#663aa0ff" }
                    GradientStop { position: 0.35; color: "#003aa0ff" }
                    GradientStop { position: 0.55; color: "#557d7aff" }
                    GradientStop { position: 0.75; color: "#0000a0ff" }
                    GradientStop { position: 0.88; color: "#555ac8fa" }
                    GradientStop { position: 1.0; color: "#003aa0ff" }
            }
            PathRectangle { x: 0; y: 0; width: boton.width + 28; height: boton.height + 28; radius: 48 }
        }
    }
    }

    // Borde de luz nitido
    Shape {
        x: -1.5; y: -1.5
        width: boton.width + 3.0; height: boton.height + 3.0
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: ConicalGradient {
                centerX: boton.width / 2 + 1.5; centerY: boton.height / 2 + 1.5
                angle: boton.giro
                    GradientStop { position: 0.0; color: "#008fd4ff" }
                    GradientStop { position: 0.14; color: "#ff8fd4ff" }
                    GradientStop { position: 0.33; color: "#008fd4ff" }
                    GradientStop { position: 0.53; color: "#00a29bff" }
                    GradientStop { position: 0.69; color: "#ffa29bff" }
                    GradientStop { position: 0.89; color: "#00a29bff" }
                    GradientStop { position: 1.0; color: "#008fd4ff" }
            }
            PathRectangle { x: 0; y: 0; width: boton.width + 3.0; height: boton.height + 3.0; radius: 35.5 }
        }
    }

    ClippingRectangle {
        id: cuerpo
        anchors.fill: parent
        radius: 34
        color: "#070a12"

        // Tres luces que flotan cada una a su ritmo; desenfocadas juntas parecen una sola luz viva.
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 52 }
            component Luz: Rectangle {
                id: luz
                property real dx1; property real dy1; property real dx2; property real dy2
                property real s1: 1; property real s2: 1.25
                property int periodo: 7000
                width: 110; height: 110; radius: 55
                x: boton.width / 2 - 55 + dx1; y: boton.height / 2 - 55 + dy1
                SequentialAnimation on x { running: boton.animar; loops: Animation.Infinite
                    NumberAnimation { to: boton.width / 2 - 55 + luz.dx2; duration: luz.periodo / 2; easing.type: Easing.InOutSine }
                    NumberAnimation { to: boton.width / 2 - 55 + luz.dx1; duration: luz.periodo / 2; easing.type: Easing.InOutSine } }
                SequentialAnimation on y { running: boton.animar; loops: Animation.Infinite
                    NumberAnimation { to: boton.height / 2 - 55 + luz.dy2; duration: luz.periodo / 2; easing.type: Easing.InOutSine }
                    NumberAnimation { to: boton.height / 2 - 55 + luz.dy1; duration: luz.periodo / 2; easing.type: Easing.InOutSine } }
                SequentialAnimation on scale { running: boton.animar; loops: Animation.Infinite
                    NumberAnimation { from: luz.s1; to: luz.s2; duration: luz.periodo / 2; easing.type: Easing.InOutSine }
                    NumberAnimation { from: luz.s2; to: luz.s1; duration: luz.periodo / 2; easing.type: Easing.InOutSine } }
            }
            Luz { color: "#0a84ff"; dx1: -30; dy1: 60; dx2: 30; dy2: -50; periodo: 7000 }
            Luz { color: "#2fd3ff"; opacity: 0.75; dx1: 30; dy1: -60; dx2: -25; dy2: 55; s1: 1.15; s2: 0.85; periodo: 8500 }
            Luz { color: "#6e5bff"; opacity: 0.7; dx1: 0; dy1: 90; dx2: 10; dy2: -80; s1: 0.9; s2: 1.25; periodo: 10000 }
            // Resplandor detras de la cara, que late
            Rectangle {
                width: 90; height: 90; radius: 45
                x: boton.width / 2 - 45; y: boton.height * 0.44 - 45
                color: "#5ac8fa"
                opacity: 0.5
                SequentialAnimation on opacity { running: boton.animar; loops: Animation.Infinite
                    NumberAnimation { from: 0.35; to: 0.7; duration: 1600; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.7; to: 0.35; duration: 1600; easing.type: Easing.InOutSine } }
            }
        }

        // Luz que sube desde la base
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 80
            gradient: Gradient {
                GradientStop { position: 0; color: "#000a84ff" }
                GradientStop { position: 1; color: "#330a84ff" }
            }
        }

        // Chispas que suben flotando y titilan (mas rapido con el cursor encima)
        Repeater {
            model: Estilo.valor("botChispas") ? 18 : 0
            delegate: Rectangle {
                id: chispa
                required property int index
                readonly property real azar: (index * 0.6180339) % 1
                width: 1.5 + azar * 2.2; height: width; radius: width / 2
                color: "#bee6ff"
                x: 8 + ((index * 37) % (boton.width - 16))
                y: boton.height + 4 - chispa.azar * boton.height    // donde se queda si la luz no se mueve
                SequentialAnimation on y {
                    running: boton.animar
                    loops: Animation.Infinite
                    NumberAnimation { from: boton.height + 4 - chispa.azar * boton.height; to: -6; duration: (5000 + chispa.azar * 6000) * (1 - chispa.azar * 0.0) * (sobre.hovered ? 0.55 : 1) }
                    NumberAnimation { from: boton.height + 4; to: boton.height + 4 - chispa.azar * boton.height; duration: 0 }
                }
                SequentialAnimation on opacity { running: boton.animar; loops: Animation.Infinite
                    NumberAnimation { from: 0.15; to: 0.75; duration: 800 + chispa.azar * 900; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.75; to: 0.15; duration: 800 + chispa.azar * 900; easing.type: Easing.InOutSine } }
            }
        }

        // Filo interior tenue
        Rectangle { anchors.fill: parent; radius: 34; color: "transparent"; border.width: 1; border.color: "#228fd4ff" }
    }

    // El asistente, con resplandor azul alrededor de la cabeza y los ojos
    Asistente {
        id: cara
        width: 84; height: 84
        x: (boton.width - width) / 2
        y: boton.height * 0.44 - height / 2 + salto
        property real salto: 0
        fondoNegro: true
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#3aa0ff"; shadowBlur: 1; shadowHorizontalOffset: 0; shadowVerticalOffset: 0; autoPaddingEnabled: true }
        SequentialAnimation {
            id: saltito
            NumberAnimation { target: cara; property: "salto"; to: -9; duration: Estilo.t(140); easing.type: Easing.OutCubic }
            NumberAnimation { target: cara; property: "salto"; to: 0; duration: Estilo.t(520); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(3) }
        }
    }

    Column {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        spacing: 2
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Estilo.gota.nombre; color: "#ffffff"; font { family: Estilo.letra; pixelSize: 13; weight: Font.DemiBold } }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Estilo.valor("botSub"); color: "#d8ecff"; font { family: Estilo.letra; pixelSize: 11; letterSpacing: 0.6 } }
    }

    // Onda de luz al pulsar
    Rectangle {
        id: onda
        width: 70; height: 70; radius: 35
        x: (boton.width - width) / 2; y: boton.height * 0.44 - height / 2
        color: "transparent"; border.width: 2; border.color: "#9fdcff"
        opacity: 0
        ParallelAnimation {
            id: ondaAnim
            NumberAnimation { target: onda; property: "scale"; from: 0.3; to: 3.2; duration: 1000; easing.type: Easing.OutCubic }
            NumberAnimation { target: onda; property: "opacity"; from: 0.9; to: 0; duration: 1000; easing.type: Easing.OutCubic }
        }
    }

    HoverHandler { id: sobre; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        id: zona
        anchors.fill: parent
        onClicked: { ondaAnim.restart(); saltito.restart(); cara.parpadear(); boton.pulsado(); }
    }
}
