import QtQuick
import QtQuick.Shapes
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

    readonly property real g: Estilo.grosorMarco
    readonly property real r: Estilo.valor("esquinas") + g   // sigue la curva de las ventanas
    property color abajo: Estilo.colorMarcoAbajo
    Behavior on abajo { ColorAnimation { duration: Estilo.t(600) } }

    Shape {
        anchors.fill: parent
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
}
