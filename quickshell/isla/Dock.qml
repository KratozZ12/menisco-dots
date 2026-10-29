import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Dock flotante abajo al centro. El fondo es casi transparente: el vidrio lo pone
// el compositor (liquid glass en Lniri, desenfoque en niri), por la capa "dock".
// Apps: primero las ancladas (dock.json) y despues las abiertas sin anclar; al abrir o
// cerrar una, el dock crece o se encoge y el icono entra o sale con rebote.
// Clic derecho: menu con Abrir / Quitar del dock (cerrada) o Anclar / Cerrar (abierta).
PanelWindow {
    id: dock

    // Se llama "shell" y no "raiz": con "raiz: raiz" en shell.qml la propiedad se enlazaba
    // consigo misma (null) en vez de con la raiz del shell, y el boton no hacia nada.
    property var shell: null   // para abrir el lanzador y decirle de donde brotar

    readonly property int icono: 46
    readonly property int relleno: 9
    readonly property var curvaIos: [0.32, 0.72, 0, 1, 1, 1]
    readonly property var curvaRebote: [0.3, 1.55, 0.5, 1, 1, 1]   // pasa un poco de largo y se asienta

    // Lupa: hasta +14 % justo bajo el cursor, cayendo en campana (sigma 40 px).
    readonly property real lupaMax: 0.14
    readonly property real lupaAncho: 40
    function aumento(item) {
        if (!sobre.hovered) return 0;
        const centro = item.mapToItem(fondo, item.width / 2, 0).x;
        const d = sobre.point.position.x - centro;
        return Math.exp(-(d * d) / (2 * lupaAncho * lupaAncho));
    }

    // ---- Apps ancladas, guardadas en dock.json ----
    // escritorio: id del .desktop (icono y comando). ventana: app_id de sus ventanas en niri.
    readonly property var porDefecto: [
        { escritorio: "helium", ventana: "helium" },
        { escritorio: "claude-desktop-unofficial", ventana: "com.anthropic.Claude" },
        { escritorio: "org.gnome.Nautilus", ventana: "org.gnome.Nautilus" }
    ]
    property var ancladas: porDefecto

    FileView {
        id: guardado
        path: Quickshell.env("HOME") + "/.config/quickshell/isla/dock.json"
        watchChanges: true              // si no existe todavia, lo lee en cuanto aparezca
        onFileChanged: reload()
        onLoaded: { try { dock.ancladas = JSON.parse(text()); } catch (e) {} }
    }
    function guardar(lista) {
        ancladas = lista;
        guardado.setText(JSON.stringify(lista, null, 2));
    }
    function anclar(clave, escritorio) {
        if (ancladas.some(a => a.ventana === clave)) return;
        guardar(ancladas.concat([{ escritorio: escritorio || clave, ventana: clave }]));
    }
    function desanclar(clave) { guardar(ancladas.filter(a => a.ventana !== clave)); }

    // Lo que deberia verse: ancladas + abiertas que no esten ancladas.
    readonly property var deseadas: {
        DesktopEntries.applications.values.length;   // reevaluar cuando terminen de cargar los .desktop
        const lista = ancladas.map(a => ({ clave: a.ventana, escritorio: a.escritorio, anclada: true }));
        for (const t of ToplevelManager.toplevels.values) {
            if (!t.appId || lista.some(x => x.clave === t.appId)) continue;
            const e = DesktopEntries.heuristicLookup(t.appId);
            lista.push({ clave: t.appId, escritorio: e ? e.id : "", anclada: false });
        }
        return lista;
    }
    onDeseadasChanged: sincronizar()
    Component.onCompleted: sincronizar()

    // Se edita el modelo pieza por pieza (en vez de reemplazarlo) para que solo
    // anime el icono que entra o sale y el resto conserve su estado.
    ListModel { id: modelo }
    function sincronizar() {
        const d = deseadas;
        for (let i = modelo.count - 1; i >= 0; i--)
            if (!d.some(x => x.clave === modelo.get(i).clave)) modelo.remove(i);
        d.forEach((x, i) => {
            let j = -1;
            for (let k = 0; k < modelo.count; k++) if (modelo.get(k).clave === x.clave) { j = k; break; }
            if (j < 0) { modelo.insert(i, x); return; }
            if (j !== i) modelo.move(j, i, 1);
            modelo.setProperty(i, "anclada", x.anclada);
            modelo.setProperty(i, "escritorio", x.escritorio);
        });
    }

    anchors.bottom: true
    margins.bottom: 10
    exclusiveZone: implicitHeight   // niri ya le suma el margen de abajo
    implicitWidth: fila.implicitWidth + relleno * 2 + 6
    implicitHeight: icono + relleno * 2 + 6
    color: "transparent"
    WlrLayershell.namespace: "dock"

    Rectangle {
        id: fondo
        anchors.fill: parent
        radius: 22
        color: Qt.rgba(1, 1, 1, sobre.hovered ? 0.06 : 0.03)   // casi nada: que se vea la refraccion
        Behavior on color { ColorAnimation { duration: 260 } }
        border.color: Qt.rgba(1, 1, 1, 0.18)
        border.width: 1

        // Aparece al arrancar: sube 16 px con fundido.
        opacity: 0
        transform: Translate { id: subida; y: 16 }
        Component.onCompleted: aparecer.start()
        ParallelAnimation {
            id: aparecer
            NumberAnimation { target: fondo; property: "opacity"; to: 1; duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: subida; property: "y"; to: 0; duration: 820; easing.type: Easing.BezierSpline; easing.bezierCurve: dock.curvaRebote }
        }

        HoverHandler { id: sobre }

        Row {
            id: fila
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -2
            spacing: 10

            ListView {
                id: lista
                orientation: ListView.Horizontal
                interactive: false
                spacing: 10
                height: dock.icono
                // El ancho se anima: la capa (y su vidrio) crece o se encoge con suavidad.
                width: Math.max(0, contentWidth)
                Behavior on width { NumberAnimation { duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: dock.curvaIos } }
                model: modelo

                add: Transition {
                    NumberAnimation { property: "scale"; from: 0; to: 1; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260 }
                }
                remove: Transition {
                    NumberAnimation { property: "scale"; to: 0; duration: 260; easing.type: Easing.InCubic }
                    NumberAnimation { property: "opacity"; to: 0; duration: 220 }
                }
                displaced: Transition {
                    NumberAnimation { property: "x"; duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: dock.curvaIos }
                }

                delegate: Item {
                    id: app
                    required property string clave
                    required property string escritorio
                    required property bool anclada

                    // byId() no se reevalua cuando terminan de cargar los .desktop; la lista si.
                    readonly property var entrada: DesktopEntries.applications.values.find(e => e.id === escritorio)
                                                   ?? DesktopEntries.heuristicLookup(clave)
                    readonly property var ventanas: ToplevelManager.toplevels.values.filter(t => t.appId === clave)
                    readonly property real f: dock.aumento(app)

                    width: dock.icono
                    height: dock.icono

                    Image {
                        anchors.fill: parent
                        source: Quickshell.iconPath(app.entrada ? app.entrada.icon : app.clave, "application-x-executable")
                        // Pedirlo a 48: los iconos PNG de hicolor (el de Claude) no cargan a 46.
                        sourceSize: Qt.size(48, 48)
                        smooth: true
                        transformOrigin: Item.Bottom

                        property real lupa: 1 + dock.lupaMax * app.f
                        // Rebote suave al crecer y al volver. (SpringAnimation aqui dejaba la lupa congelada.)
                        Behavior on lupa { NumberAnimation { duration: sobre.hovered ? 260 : 520; easing.type: Easing.OutBack; easing.overshoot: sobre.hovered ? 1.4 : 1.8 } }
                        property real hundir: zona.pressed ? 0.88 : 1
                        Behavior on hundir { NumberAnimation { duration: zona.pressed ? 90 : 460; easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 2.6 } }
                        scale: lupa * hundir
                    }

                    // Punto de app abierta, como en el Mac: aparece creciendo.
                    Rectangle {
                        width: 4; height: 4; radius: 2
                        color: "#ffffff"
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 3 }
                        opacity: app.ventanas.length > 0 ? 0.9 : 0
                        scale: app.ventanas.length > 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                        Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                    }

                    MouseArea {
                        id: zona
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) { menu.abrirPara(app); return; }
                            // Abierta: la trae al frente (alternando si tiene varias). Cerrada: la abre.
                            if (app.ventanas.length > 0) (app.ventanas.find(t => !t.activated) ?? app.ventanas[0]).activate();
                            else if (app.entrada) app.entrada.execute();
                        }
                    }
                }
            }

            Rectangle {
                width: 1
                height: dock.icono - 12
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.35)
            }

            // Menu de apps (lo mismo que Super+D): no se agranda; se aclara al pasar
            // el cursor y se hunde con rebote al pulsar. El lanzador brota de aqui.
            Rectangle {
                id: botonLanzador
                Binding {
                    target: dock.shell
                    property: "origenLanzadorX"
                    // mapToItem no avisa si el dock cambia de ancho; leer los anchos fuerza a recalcular.
                    value: { fila.width; fondo.width; return botonLanzador.mapToItem(fondo, botonLanzador.width / 2, 0).x - fondo.width / 2; }
                    when: dock.shell !== null
                }
                width: dock.icono
                height: dock.icono
                radius: 12
                color: Qt.rgba(1, 1, 1, zonaMenu.pressed || (dock.shell && dock.shell.lanzadorAbierto) ? 0.36 : zonaMenu.containsMouse ? 0.28 : 0.16)
                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                scale: zonaMenu.pressed ? 0.88 : 1
                Behavior on scale { NumberAnimation { duration: zonaMenu.pressed ? 90 : 460; easing.type: zonaMenu.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 2.6 } }

                Text {
                    anchors.centerIn: parent
                    text: "apps"
                    color: "#ffffff"
                    font { family: "Material Symbols Rounded"; pixelSize: 26 }
                    font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 24 }
                    renderType: Text.NativeRendering
                }
                MouseArea { id: zonaMenu; anchors.fill: parent; hoverEnabled: true; onClicked: if (dock.shell) dock.shell.lanzadorAbierto = !dock.shell.lanzadorAbierto }
            }
        }
    }

    // ---- Menu de clic derecho ----
    PopupWindow {
        id: menu
        property var app: null
        readonly property bool abierta: app ? app.ventanas.length > 0 : false
        readonly property var opciones: !app ? []
            : abierta ? (app.anclada ? [{ id: "cerrar", texto: "Cerrar", icono: "close" }]
                                     : [{ id: "anclar", texto: "Anclar al dock", icono: "keep" },
                                        { id: "cerrar", texto: "Cerrar", icono: "close" }])
                      : [{ id: "abrir", texto: "Abrir", icono: "open_in_new" },
                         { id: "quitar", texto: "Quitar del dock", icono: "keep_off" }]

        function abrirPara(item) {
            app = item;
            visible = true;
            entrada.restart();
        }
        function elegir(id) {
            const a = app;
            visible = false;
            if (id === "cerrar") a.ventanas.forEach(t => t.close());
            else if (id === "anclar") dock.anclar(a.clave, a.entrada ? a.entrada.id : "");
            else if (id === "quitar") dock.desanclar(a.clave);
            else if (id === "abrir" && a.entrada) a.entrada.execute();
        }

        anchor.item: app
        anchor.rect: Qt.rect(0, -10, app ? app.width : 0, 0)
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        grabFocus: true                 // un clic fuera lo cierra
        implicitWidth: 190
        implicitHeight: columna.implicitHeight + 12
        color: "transparent"

        Rectangle {
            id: caja
            anchors.fill: parent
            radius: 14
            color: "#242424"
            border.color: "#3a3a3a"
            border.width: 1
            transformOrigin: Item.Bottom

            // Brota desde el icono: crece desde 0.85 con rebote suave y fundido.
            ParallelAnimation {
                id: entrada
                NumberAnimation { target: caja; property: "scale"; from: 0.85; to: 1; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: dock.curvaRebote }
                NumberAnimation { target: caja; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
            }

            Column {
                id: columna
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2

                Text {
                    width: parent.width
                    leftPadding: 10; topPadding: 4; bottomPadding: 4
                    text: menu.app && menu.app.entrada ? menu.app.entrada.name : (menu.app ? menu.app.clave : "")
                    color: "#888"
                    elide: Text.ElideRight
                    font { family: "SF Pro Text"; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.06 }
                }

                Repeater {
                    model: menu.opciones
                    delegate: Rectangle {
                        required property var modelData
                        width: columna.width
                        height: 32
                        radius: 9
                        color: opcion.containsMouse ? "#333" : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: opcion.pressed ? 0.96 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                        Text {
                            id: iconoOpcion
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: modelData.icono
                            color: modelData.id === "cerrar" ? "#ff6b6b" : "#ddd"
                            font { family: "Material Symbols Rounded"; pixelSize: 18 }
                            font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 20 }
                            renderType: Text.NativeRendering
                        }
                        Text {
                            anchors { left: iconoOpcion.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: modelData.texto
                            color: modelData.id === "cerrar" ? "#ff6b6b" : "#eee"
                            font { family: "SF Pro Text"; pixelSize: 13; weight: Font.Normal; letterSpacing: -0.08 }
                        }
                        MouseArea { id: opcion; anchors.fill: parent; hoverEnabled: true; onClicked: menu.elegir(modelData.id) }
                    }
                }
            }
        }
    }
}
