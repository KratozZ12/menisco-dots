import QtQuick
import QtMultimedia
import Quickshell.Widgets

// Demo de una version en la pagina Menisco (Ajustes): un video en bucle, solo imagen, sin sonido,
// sobre su poster. Los archivos viven en assets/versiones/demos/{video,poster}/<archivo>.
// Solo reproduce mientras "activa"; al cambiar de archivo o dejar de estar activa, el reproductor
// suelta el video anterior (source vacio), asi nunca hay dos a la vez. En modo juego, solo el poster.
Item {
    id: demo
    property string archivo: ""
    property string descripcion: ""
    property bool activa: false
    property real radio: 22
    readonly property url carpeta: Qt.resolvedUrl("assets/versiones/demos/")
    // El primer cuadro ya llego: hasta entonces se ve el poster, sin parpadeo en negro.
    property bool listo: false

    Accessible.role: Accessible.Animation
    Accessible.name: descripcion

    ClippingRectangle {
        anchors.fill: parent
        radius: demo.radio
        color: Estilo.hundido
        Image {
            anchors.fill: parent
            source: demo.archivo ? demo.carpeta + "poster/" + demo.archivo + ".jpg" : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        VideoOutput {
            id: salida
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
            opacity: demo.listo ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
    }

    MediaPlayer {
        id: reproductor
        videoOutput: salida
        loops: MediaPlayer.Infinite
        source: demo.activa && demo.archivo && !Estilo.juego ? demo.carpeta + "video/" + demo.archivo + ".mp4" : ""
        onSourceChanged: {
            demo.listo = false;
            if (source.toString()) play(); else stop();
        }
        onPositionChanged: if (reproductor.position > 0 && !demo.listo) demo.listo = true
    }
}
