import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// Marco de pantalla: un borde del color de la isla alrededor del monitor, con las esquinas de
// adentro redondeadas. La isla baja lo mismo que el grosor y sale del borde de arriba sin costura.
// Va en la capa de abajo: las ventanas a pantalla completa lo tapan. No reserva espacio: el
// hueco entre ventanas de niri (15 px) ya es mas ancho que el marco.
// ponytail: con "Espacio entre ventanas" por debajo de grosor, las ventanas tapan el marco.
PanelWindow {
    id: marco
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "marco"
    color: "transparent"
    mask: Region {}

    // Al encender brota de la isla: sale del centro de arriba, corre por los dos lados y baja hasta
    // juntarse abajo. Al apagar, el mismo camino al reves. Se dibuja con una mascara: dos trazos
    // gruesos (uno por lado) que se alargan con dashOffset y solo dejan ver el marco donde pasan.
    property bool encendido: false
    property real avance: encendido ? 1 : 0
    Behavior on avance { NumberAnimation { duration: Estilo.t(900); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
    visible: avance > 0
    readonly property bool animando: avance > 0 && avance < 1
    readonly property real g: Estilo.anchoMarco   // grosorMarco ya es 0 mientras se apaga
    readonly property real r: Estilo.valor("esquinas") + g   // sigue la curva de las ventanas
    property color abajo: Estilo.colorMarcoAbajo
    Behavior on abajo { ColorAnimation { duration: Estilo.t(600) } }

    Shape {
        id: dibujo
        anchors.fill: parent
        // Quieto, sin mascara. Animando, pasa por la mascara como efecto de su propia capa (con una
        // copia escondida aparte, al apagar la copia salia vacia y el marco se iba de golpe).
        layer.enabled: marco.animando
        layer.effect: MultiEffect { maskEnabled: true; maskSource: mascara }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            // Fundido largo: negro arriba (con la isla) hasta la mitad, y desde ahi baja al color
            // del dock pegado. Sin dock de color, los dos extremos son el mismo negro.
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: marco.height
                GradientStop { position: 0.45; color: Estilo.fondo }
                GradientStop { position: 1; color: marco.abajo }
            }
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            PathSvg {
                path: {
                    const w = marco.width, h = marco.height, g = marco.g, r = marco.r;
                    return `M0 0H${w}V${h}H0Z ` +
                           `M${g + r} ${g}H${w - g - r}Q${w - g} ${g} ${w - g} ${g + r}` +
                           `V${h - g - r}Q${w - g} ${h - g} ${w - g - r} ${h - g}` +
                           `H${g + r}Q${g} ${h - g} ${g} ${h - g - r}V${g + r}Q${g} ${g} ${g + r} ${g}Z`;
                }
            }
        }
    }

    // Camino de la mascara: del centro de arriba hasta el centro de abajo, por un lado.
    readonly property real largo: width / 2 + height + width / 2
    readonly property real ancho: 80             // grosor del trazo; Qt mide el dash en grosores, no en px
    Shape {
        id: mascara
        anchors.fill: parent
        visible: false
        layer.enabled: marco.animando
        ShapePath {
            strokeColor: "white"; fillColor: "transparent"; strokeWidth: marco.ancho; capStyle: ShapePath.FlatCap
            strokeStyle: ShapePath.DashLine
            dashPattern: [marco.largo / marco.ancho, marco.largo / marco.ancho]
            dashOffset: marco.largo / marco.ancho * (1 - marco.avance)
            PathSvg { path: `M${marco.width / 2} 0H0V${marco.height}H${marco.width / 2}` }
        }
        ShapePath {
            strokeColor: "white"; fillColor: "transparent"; strokeWidth: marco.ancho; capStyle: ShapePath.FlatCap
            strokeStyle: ShapePath.DashLine
            dashPattern: [marco.largo / marco.ancho, marco.largo / marco.ancho]
            dashOffset: marco.largo / marco.ancho * (1 - marco.avance)
            PathSvg { path: `M${marco.width / 2} 0H${marco.width}V${marco.height}H${marco.width / 2}` }
        }
    }
}
