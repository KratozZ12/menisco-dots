import QtQuick
import QtQuick.Shapes

// Esquina de arriba del marco ensanchada para guardar los botones de Menisco, de la barra y la
// bandeja. Baja hasta donde llega la isla cerrada; un hombro la funde con el borde de arriba
// (hacia la isla) y otro con el del costado. Dibujada para la esquina izquierda; espejo = derecha.
Shape {
    id: oreja
    property real ancho                          // desde el borde de la pantalla
    Behavior on ancho { NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } }
    property bool espejo: false
    readonly property real g: Estilo.grosorMarco
    readonly property real alto: g + 42          // lo mismo que la isla cerrada
    readonly property real s: 14                 // hombros
    readonly property real r: 12                 // esquina de abajo
    width: ancho + s; height: alto + s
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { xScale: oreja.espejo ? -1 : 1; origin.x: oreja.width / 2 }
    ShapePath {
        fillColor: Estilo.fondo
        strokeWidth: -1
        PathSvg {
            path: {
                const a = oreja.ancho, h = oreja.alto, g = oreja.g, s = oreja.s, r = oreja.r;
                return `M0 0H${a + s}V${g}Q${a} ${g} ${a} ${g + s}V${h - r}Q${a} ${h} ${a - r} ${h}` +
                       `H${g + s}Q${g} ${h} ${g} ${h + s}H0Z`;
            }
        }
    }
}
