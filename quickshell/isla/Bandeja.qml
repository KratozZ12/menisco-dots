import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Services.SystemTray

// Pildora de bandeja: apps en segundo plano, junto al boton de la barra lateral.
// Clic izquierdo abre la app, clic central su accion secundaria, clic derecho su propio menu.
// Los submenus se abren dentro del mismo cuadro, con una fila para volver.
PanelWindow {
    id: bandeja

    // Va en la esquina que la tenga en Ajustes > Esquinas, en su hueco: 10 de margen y
    // 34 + 8 por cada boton que quede entre ella y el borde.
    readonly property bool izquierda: Estilo.botones.izquierda.includes("bandeja")
    readonly property var listaLado: izquierda ? Estilo.botones.izquierda : Estilo.botones.derecha
    readonly property int indice: listaLado.indexOf("bandeja")
    readonly property int separacion: 10 + 42 * (izquierda ? indice : listaLado.length - 1 - indice)

    visible: SystemTray.items.values.length > 0 && indice >= 0
    anchors { top: true; right: !izquierda; left: izquierda }
    // Sin margen arriba (niri no aplica uno que cambia antes de mostrarse): la pildora baja por dentro.
    margins { right: separacion; left: separacion }
    mask: Region { item: pastilla }
    // La oreja del marco (BotonBarra) se ensancha para guardarla.
    Binding { target: Estilo; property: "anchoBandeja"; value: bandeja.visible ? bandeja.implicitWidth : 0 }
    implicitWidth: fila.implicitWidth + 8
    implicitHeight: 34 + 4 + Estilo.grosorMarco
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "bandeja"
    Gelatina { objetivo: bandeja.contentItem; origenY: 0 }   // se va con la vista general

    Rectangle {
        id: pastilla
        anchors { fill: parent; topMargin: 4 + Estilo.grosorMarco }
        radius: height / 2
        color: Estilo.fondo

        Row {
            id: fila
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                id: iconos
                model: SystemTray.items
                delegate: Rectangle {
                    id: icono
                    required property var modelData
                    width: 26; height: 26; radius: 13
                    color: zona.containsMouse || (menu.visible && menu.item === modelData) ? Estilo.realce : Estilo.nada
                    Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
                    scale: zona.pressed ? 0.86 : 1
                    Behavior on scale { NumberAnimation { duration: Estilo.t(zona.pressed ? 80 : 420); easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.6) } }

                    IconImage { anchors.centerIn: parent; implicitSize: 18; source: icono.modelData.icon }

                    MouseArea { cursorShape: Qt.PointingHandCursor
                        id: zona
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: mouse => {
                            const app = icono.modelData;
                            if (mouse.button === Qt.RightButton || app.onlyMenu) menu.abrirPara(icono);
                            else if (mouse.button === Qt.MiddleButton) app.secondaryActivate();
                            else app.activate();
                        }
                    }
                }
            }
        }
    }

    // Para probar sin raton: qs -p ~/.config/quickshell/isla ipc call bandeja menu 0
    IpcHandler {
        target: "bandeja"
        function menu(i: int): void { if (iconos.itemAt(i)) menu.abrirPara(iconos.itemAt(i)); }
        function cerrar(): void { menu.visible = false; }
    }

    // ---- Menu de clic derecho: el que manda la propia app, con el estilo del menu del dock ----
    PopupWindow {
        id: menu
        property var item: null       // la app (SystemTrayItem)
        property var ancla: null      // su icono en la pildora
        property var pila: []         // submenus abiertos; se ve el ultimo

        function abrirPara(d) {
            if (!d.modelData.hasMenu) return;
            item = d.modelData; ancla = d; pila = [];
            visible = true;
            entrada.restart();
        }
        // Las etiquetas de DBusMenu marcan el atajo de teclado con "_" ("_Salir"); "__" es un guion bajo de verdad.
        function limpiar(t) { return (t || "").replace(/_(.)/g, "$1"); }

        anchor.item: ancla
        anchor.rect: Qt.rect(0, ancla ? ancla.height + 8 : 0, ancla ? ancla.width : 0, 0)
        anchor.edges: Edges.Top | (bandeja.izquierda ? Edges.Left : Edges.Right)
        anchor.gravity: Edges.Bottom | (bandeja.izquierda ? Edges.Right : Edges.Left)
        grabFocus: true                 // un clic fuera lo cierra
        implicitWidth: 210
        implicitHeight: columna.implicitHeight + 12
        color: "transparent"

        QsMenuOpener {
            id: abridor
            menu: menu.pila.length ? menu.pila[menu.pila.length - 1] : (menu.item ? menu.item.menu : null)
        }

        Rectangle {
            id: caja
            anchors.fill: parent
            radius: 14
            color: Estilo.fondo
            border.color: Estilo.borde
            border.width: 1
            transformOrigin: bandeja.izquierda ? Item.TopLeft : Item.TopRight

            ParallelAnimation {
                id: entrada
                NumberAnimation { target: caja; property: "scale"; from: 0.85; to: 1; duration: Estilo.t(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote }
                NumberAnimation { target: caja; property: "opacity"; from: 0; to: 1; duration: Estilo.t(200); easing.type: Easing.OutCubic }
            }

            Column {
                id: columna
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2

                // Cabecera: nombre de la app, o "‹ submenu" para volver un nivel.
                Rectangle {
                    width: columna.width; height: 24; radius: 9
                    color: volver.containsMouse && menu.pila.length ? Estilo.realce : Estilo.nada
                    Text {
                        id: flecha
                        visible: menu.pila.length > 0
                        anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                        text: "chevron_left"; color: Estilo.texto2
                        font { family: "Material Symbols Rounded"; pixelSize: 16 }
                        renderType: Text.NativeRendering
                    }
                    Text {
                        anchors { left: menu.pila.length ? flecha.right : parent.left; leftMargin: menu.pila.length ? 2 : 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: menu.pila.length ? menu.limpiar(menu.pila[menu.pila.length - 1].text)
                              : menu.item ? (menu.item.tooltipTitle || menu.item.title || menu.item.id) : ""
                        color: Estilo.texto2
                        elide: Text.ElideRight
                        font { family: Estilo.letra; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.06 }
                    }
                    MouseArea { cursorShape: Qt.PointingHandCursor; id: volver; anchors.fill: parent; hoverEnabled: true; enabled: menu.pila.length > 0; onClicked: menu.pila = menu.pila.slice(0, -1) }
                }

                Repeater {
                    model: abridor.children
                    delegate: Rectangle {
                        id: fila2
                        required property var modelData
                        readonly property bool separador: modelData.isSeparator
                        width: columna.width
                        height: separador ? 9 : 32
                        radius: 9
                        color: !separador && opcion.containsMouse && modelData.enabled ? Estilo.realce : Estilo.nada
                        Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
                        scale: opcion.pressed ? 0.96 : 1
                        Behavior on scale { NumberAnimation { duration: Estilo.t(140); easing.type: Easing.OutCubic } }

                        Rectangle { visible: fila2.separador; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: Estilo.linea }

                        Text {
                            visible: !fila2.separador
                            anchors { left: parent.left; leftMargin: 10; right: marca.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            text: menu.limpiar(fila2.modelData.text)
                            color: fila2.modelData.enabled ? Estilo.texto : Estilo.texto3
                            elide: Text.ElideRight
                            font { family: Estilo.letra; pixelSize: 13; weight: Font.Normal; letterSpacing: -0.08 }
                        }
                        // A la derecha: flecha si abre un submenu, palomita si es una opcion marcada.
                        Text {
                            id: marca
                            visible: !fila2.separador
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            text: fila2.modelData.hasChildren ? "chevron_right"
                                  : fila2.modelData.buttonType !== QsMenuButtonType.None && fila2.modelData.checkState === Qt.Checked ? "check" : ""
                            color: Estilo.texto2
                            font { family: "Material Symbols Rounded"; pixelSize: 16 }
                            renderType: Text.NativeRendering
                        }

                        MouseArea { cursorShape: Qt.PointingHandCursor
                            id: opcion
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !fila2.separador && fila2.modelData.enabled
                            onClicked: {
                                if (fila2.modelData.hasChildren) { menu.pila = menu.pila.concat([fila2.modelData]); return; }
                                fila2.modelData.triggered();
                                menu.visible = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
