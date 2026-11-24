import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// Lo que acompana a la vista general de niri (esquina de arriba a la izquierda o Super+O):
// - fondo de pantalla borroso detras de los escritorios (capa en el backdrop, ver layer-rule
//   "menisco-fondo-vista" en config.kdl),
// - minimapa en la esquina con cada ventana como un bloque con su icono; clic = ir a ella.
// La isla, el dock y los botones se van solos con una ola de colores (Gelatina).
Variants {
    id: vg
    property var raiz: null     // shell.qml pasa raizShell (ventanas y escritorios de niri)
    model: Quickshell.screens
    Scope {
        id: v
        required property var modelData
        readonly property bool abierta: Estilo.vistaGeneral

        // ---------- Fondo borroso ----------
        PanelWindow {
            screen: v.modelData
            visible: v.abierta || borroso.opacity > 0.01
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "menisco-fondo-vista"
            mask: Region {}
            Item {
                id: borroso
                anchors.fill: parent
                opacity: v.abierta ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Estilo.t(500); easing.type: Easing.OutCubic } }
                Image {
                    id: foto
                    anchors.fill: parent
                    source: Estilo.fondoPantalla ? "file://" + Estilo.fondoPantalla : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 960          // se desenfoca igual: media resolucion basta
                    asynchronous: true
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: foto
                    blurEnabled: true; blur: 1; blurMax: 64
                    brightness: -0.18
                }
            }
        }

        // ---------- Minimapa ----------
        PanelWindow {
            id: mapa
            screen: v.modelData
            visible: v.abierta || caja.opacity > 0.01
            anchors { top: true; left: true }
            margins { top: 18 + Estilo.grosorMarco; left: 18 + Estilo.grosorMarco }
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: caja.width
            implicitHeight: caja.height
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "menisco-minimapa"
            mask: Region { item: caja }

            readonly property var raiz: vg.raiz
            // Escritorios de este monitor, en orden, con sus ventanas agrupadas por columna.
            readonly property var filas: {
                const todas = Object.values(raiz?.ventanas ?? {});
                // Los tres fijos (con nombre en config.kdl) siempre; el vacio extra que niri deja al final, no.
                const ws = (raiz?.escritorios ?? []).filter(e => e.output === v.modelData.name
                    && (e.name || e.is_active || todas.some(w => w.workspace_id === e.id))).sort((a, b) => a.idx - b.idx);
                return ws.map(e => {
                    const suyas = todas.filter(w => w.workspace_id === e.id);
                    const cols = {};
                    for (const w of suyas.filter(w => !w.is_floating && w.layout?.pos_in_scrolling_layout)) {
                        const c = w.layout.pos_in_scrolling_layout[0];
                        (cols[c] = cols[c] || []).push(w);
                    }
                    const columnas = Object.keys(cols).sort((a, b) => a - b).map(c => {
                        const lista = cols[c].sort((a, b) => a.layout.pos_in_scrolling_layout[1] - b.layout.pos_in_scrolling_layout[1]);
                        return { ancho: Math.max(...lista.map(w => w.layout.tile_size[0])), ventanas: lista };
                    });
                    return { id: e.id, idx: e.idx, activo: e.is_active, columnas: columnas, sueltas: suyas.filter(w => w.is_floating) };
                });
            }
            // Escala comun: la fila mas ancha llena el minimapa; una ventana sola no pasa de 170 px.
            readonly property real anchoUtil: 300
            readonly property real escala: {
                let mayor = 1;
                for (const f of filas) mayor = Math.max(mayor, f.columnas.reduce((s, c) => s + c.ancho, 0));
                return Math.min(anchoUtil / mayor, 0.09);
            }

            Rectangle {
                id: caja
                width: 320 + 20
                height: lista.implicitHeight + 20
                radius: 18
                color: Qt.alpha(Estilo.fondo, 0.88)
                border.width: 1; border.color: Estilo.borde
                opacity: v.abierta ? 1 : 0
                scale: v.abierta ? 1 : 0.92
                transformOrigin: Item.TopLeft
                Behavior on opacity { SequentialAnimation { PauseAnimation { duration: v.abierta ? Estilo.t(250) : 0 } NumberAnimation { duration: Estilo.t(v.abierta ? 380 : 160); easing.type: Easing.OutCubic } } }
                Behavior on scale { SequentialAnimation { PauseAnimation { duration: v.abierta ? Estilo.t(250) : 0 } NumberAnimation { duration: Estilo.t(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaIos } } }

                Column {
                    id: lista
                    x: 10; y: 10
                    spacing: 6
                    Repeater {
                        model: mapa.filas.length          // indice fijo: los bloques no se recrean al moverse
                        delegate: Row {
                            id: fila
                            required property int index
                            readonly property var f: mapa.filas[index]
                            spacing: 4
                            height: 34
                            Text {
                                width: 16; height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: fila.f ? fila.f.idx : ""
                                color: fila.f && fila.f.activo ? Estilo.texto : Estilo.texto3
                                font { family: Estilo.fuenteMono; pixelSize: 12; weight: Font.DemiBold }
                                font.features: { "tnum": 1 }
                            }
                            // Escritorio vacio: solo la palabra, sin cuadro.
                            Text {
                                visible: fila.f && !fila.f.columnas.length && !fila.f.sueltas.length
                                height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: "Vacío"
                                color: Estilo.texto3
                                font { family: Estilo.letra; pixelSize: 12 }
                            }
                            Repeater {
                                model: fila.f ? fila.f.columnas : []
                                delegate: Column {
                                    id: col
                                    required property var modelData
                                    spacing: 2
                                    Repeater {
                                        model: col.modelData.ventanas
                                        delegate: Bloque {
                                            required property var modelData
                                            ventana: modelData
                                            width: Math.max(24, col.modelData.ancho * mapa.escala)
                                            height: (34 - (col.modelData.ventanas.length - 1) * 2) / col.modelData.ventanas.length
                                        }
                                    }
                                }
                            }
                            Repeater {
                                model: fila.f ? fila.f.sueltas : []
                                delegate: Bloque { required property var modelData; ventana: modelData; width: 30; height: 34; suelta: true }
                            }
                        }
                    }
                }
            }
        }
    }

    component Bloque: Rectangle {
        id: b
        property var ventana: null
        property bool suelta: false
        readonly property var entrada: ventana ? DesktopEntries.heuristicLookup(ventana.app_id ?? "") : null
        radius: 7
        color: zona.containsMouse ? Estilo.realce : Estilo.tarjeta
        border.width: ventana && ventana.is_focused ? 1.5 : suelta ? 1 : 0
        border.color: ventana && ventana.is_focused ? Estilo.texto : Estilo.linea
        Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
        Image {
            anchors.centerIn: parent
            width: Math.min(18, parent.height - 6); height: width
            sourceSize.width: 48; sourceSize.height: 48       // los PNG de hicolor solo cargan pedidos a 48
            source: Quickshell.iconPath(b.entrada ? b.entrada.icon : (b.ventana?.app_id ?? ""), "application-x-executable")
            visible: parent.width >= 20
        }
        MouseArea {
            id: zona
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["sh", "-c", "niri msg action focus-window --id " + b.ventana.id + " && niri msg action close-overview"])
        }
    }
}
