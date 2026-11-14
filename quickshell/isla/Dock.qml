import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Dock flotante abajo al centro. Su material se elige en Ajustes > Apariencia: Vidrio (de
// fabrica), Solido, Ahumado, Escarcha, Tinte, Contorno o Material You. El desenfoque lo pone el
// compositor (liquid glass en Lniri, desenfoque en niri) a la capa "dock"; los materiales sin
// vidrio usan la capa "dock-solido", que no lo recibe.
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

    // ---- Material ----
    readonly property string material: Estilo.valor("dockMaterial")
    readonly property bool conVidrio: Estilo.dockConVidrio(material)
    // El nombre de la capa solo se lee al crear la ventana: para cambiarlo, el dock baja y se
    // desvanece, se rehace oculto (shell.qml mira "oculto") y vuelve a subir. El espacio de las
    // ventanas lo guarda "reserva", que no se rehace: asi las ventanas no se mueven.
    property string capa: conVidrio ? "dock" : "dock-solido"
    property bool oculto: false
    onConVidrioChanged: { aparecer.stop(); bajar.restart(); }
    // Pegado al marco (Ajustes > Dock): sale del borde de abajo con hombros, como la isla arriba.
    property bool pegado: Estilo.dockPegado
    readonly property real hombro: 14
    // Sin vidrio el dock lleva la forma elegida (Ajustes > Dock > Forma) y la ventana se ensancha
    // "e" por lado para que quepan los hombros y la ola (la mas ancha: 2 x 60 px). Fijo para
    // todas las formas: si cambiara al pasar de una a otra, niri movería la ventana a saltos. Con vidrio, rectangulo redondeado: el
    // vidrio cubre la ventana entera y no sabria seguir otra forma.
    property bool sinVidrio: !conVidrio
    readonly property real e: sinVidrio ? 124 : 0
    // Cambio de forma: de la vieja a la nueva con rebote, como la isla.
    property string formaVieja: Estilo.valor("dockForma")
    property string formaNueva: Estilo.valor("dockForma")
    property real cambio: 1
    readonly property string formaElegida: Estilo.valor("dockForma")
    onFormaElegidaChanged: { formaVieja = formaNueva; formaNueva = formaElegida; animForma.restart(); }
    NumberAnimation { id: animForma; target: dock; property: "cambio"; from: 0; to: 1; duration: Estilo.t(640); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote }
    readonly property real g: Estilo.grosorMarco
    Connections { target: Estilo; function onDockPegadoChanged() { aparecer.stop(); bajar.restart(); } }
    SequentialAnimation {
        id: bajar
        ParallelAnimation {
            NumberAnimation { target: fondo; property: "opacity"; to: 0; duration: Estilo.t(180); easing.type: Easing.InCubic }
            NumberAnimation { target: subida; property: "y"; to: 16; duration: Estilo.t(200); easing.type: Easing.InCubic }
        }
        ScriptAction { script: { dock.oculto = true; dock.capa = dock.conVidrio ? "dock" : "dock-solido"; dock.pegado = Estilo.dockPegado; dock.sinVidrio = !dock.conVidrio; } }
        PauseAnimation { duration: 40 }
        ScriptAction { script: { dock.oculto = false; aparecer.restart(); } }
    }
    PanelWindow {
        id: reserva
        screen: dock.screen
        anchors.bottom: true
        // Fija: flotante o pegado, las ventanas no se mueven.
        margins.bottom: 10
        exclusiveZone: dock.icono + dock.relleno * 2 + 6   // niri ya le suma el margen de abajo
        implicitWidth: 1; implicitHeight: 1
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "dock-reserva"
    }

    // Material You: un tono oscuro del color principal del fondo de pantalla.
    readonly property color tono: Estilo.tonoDock
    readonly property var aspecto: Estilo.aspectoDock(material, tono, sobre.hovered)

    anchors.bottom: true
    margins.bottom: pegado ? 0 : 10
    exclusionMode: ExclusionMode.Ignore   // el espacio lo reserva "reserva"
    implicitWidth: fila.implicitWidth + relleno * 2 + 6 + e * 2
    implicitHeight: icono + relleno * 2 + 6 + (pegado ? g : 0)
    color: "transparent"
    WlrLayershell.namespace: capa
    Gelatina { objetivo: dock.contentItem; origenY: 1 }   // se va con la vista general
    property Region sinNada: Region {}
    mask: Estilo.vistaGeneral ? sinNada : null   // escondido no tapa la vista general

    Rectangle {
        id: fondo
        anchors { fill: parent; leftMargin: dock.e; rightMargin: dock.e; bottomMargin: dock.pegado ? dock.g : 0 }
        radius: dock.material === "materialyou" ? 24 : 22
        Behavior on radius { NumberAnimation { duration: Estilo.t(300) } }
        color: dock.sinVidrio ? "transparent" : dock.aspecto[0]
        Behavior on color { ColorAnimation { duration: Estilo.t(320) } }
        border.color: dock.aspecto[1]
        Behavior on border.color { ColorAnimation { duration: Estilo.t(320) } }
        border.width: dock.sinVidrio ? 0 : dock.aspecto[2]

        // La forma elegida. Pegado: hombros abajo que se funden con el borde del marco, y el filo
        // (solo Contorno) no cierra por abajo: sigue en el marco.
        Shape {
            id: silueta
            visible: dock.sinVidrio
            x: -dock.e; width: fondo.width + dock.e * 2; height: fondo.height + (dock.pegado ? dock.g : 0)
            preferredRendererType: Shape.CurveRenderer
            function mezcla(a, b, t) { return a.map((q, i) => [q[0] + (b[i][0] - q[0]) * t, q[1] + (b[i][1] - q[1]) * t]); }
            readonly property var mitad: mezcla(Estilo.mitadDock(dock.formaVieja, dock.e, fondo.height, dock.pegado, dock.hombro),
                                                Estilo.mitadDock(dock.formaNueva, dock.e, fondo.height, dock.pegado, dock.hombro), dock.cambio)
            ShapePath {
                fillColor: dock.aspecto[0]
                strokeWidth: -1
                PathSvg { path: Estilo.trazoDock(silueta.mitad, silueta.width / 2, dock.pegado, silueta.height) }
            }
            // Material You flotante: brillo suave arriba que se apaga hacia la mitad.
            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    y1: 0; y2: fondo.height
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, dock.material === "materialyou" && !dock.pegado ? 0.13 : 0) }
                    GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0) }
                }
                PathSvg { path: Estilo.trazoDock(silueta.mitad, silueta.width / 2, false, 0) }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: dock.material === "contorno" ? dock.aspecto[1] : "transparent"
                strokeWidth: dock.material === "contorno" ? dock.aspecto[2] : 0
                PathSvg { path: Estilo.trazoDock(silueta.mitad, silueta.width / 2, dock.pegado, dock.pegado ? -1 : 0) }
            }
        }

        // Aparece al arrancar: sube 16 px con fundido.
        opacity: 0
        transform: Translate { id: subida; y: 16 }
        Component.onCompleted: aparecer.start()
        ParallelAnimation {
            id: aparecer
            NumberAnimation { target: fondo; property: "opacity"; to: 1; duration: Estilo.t(420); easing.type: Easing.OutCubic }
            NumberAnimation { target: subida; property: "y"; to: 0; duration: Estilo.t(820); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote }
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
                Behavior on width { NumberAnimation { duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: dock.curvaIos } }
                model: modelo

                add: Transition {
                    NumberAnimation { property: "scale"; from: 0; to: 1; duration: Estilo.t(560); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(1.8) }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Estilo.t(260) }
                }
                remove: Transition {
                    NumberAnimation { property: "scale"; to: 0; duration: Estilo.t(260); easing.type: Easing.InCubic }
                    NumberAnimation { property: "opacity"; to: 0; duration: Estilo.t(220) }
                }
                displaced: Transition {
                    NumberAnimation { property: "x"; duration: Estilo.t(460); easing.type: Easing.BezierSpline; easing.bezierCurve: dock.curvaIos }
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
                        Behavior on lupa { NumberAnimation { duration: Estilo.t(sobre.hovered ? 260 : 520); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(sobre.hovered ? 1.4 : 1.8) } }
                        property real hundir: zona.pressed ? 0.88 : 1
                        Behavior on hundir { NumberAnimation { duration: Estilo.t(zona.pressed ? 90 : 460); easing.type: zona.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.6) } }
                        scale: lupa * hundir
                    }

                    // Punto de app abierta, como en el Mac: aparece creciendo.
                    Rectangle {
                        width: 4; height: 4; radius: 2
                        color: "#ffffff"
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 3 }
                        readonly property bool ver: app.ventanas.length > 0
                        opacity: ver ? 0.9 : 0
                        scale: ver ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Estilo.t(300) } }
                        Behavior on scale { NumberAnimation { duration: Estilo.t(420); easing.type: Easing.OutBack; easing.overshoot: Estilo.o(3) } }
                    }

                    MouseArea { cursorShape: Qt.PointingHandCursor
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
            // el cursor y se hunde con rebote al pulsar.
            Rectangle {
                id: botonLanzador
                width: dock.icono
                height: dock.icono
                radius: 12
                color: Qt.rgba(1, 1, 1, zonaMenu.pressed || (dock.shell && dock.shell.lanzadorAbierto) ? 0.36 : zonaMenu.containsMouse ? 0.28 : 0.16)
                Behavior on color { ColorAnimation { duration: Estilo.t(200); easing.type: Easing.OutCubic } }
                scale: zonaMenu.pressed ? 0.88 : 1
                Behavior on scale { NumberAnimation { duration: Estilo.t(zonaMenu.pressed ? 90 : 460); easing.type: zonaMenu.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: Estilo.o(2.6) } }

                Text {
                    anchors.centerIn: parent
                    text: "apps"
                    color: "#ffffff"
                    font { family: "Material Symbols Rounded"; pixelSize: 26 }
                    font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 24 }
                    renderType: Text.NativeRendering
                }
                MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaMenu; anchors.fill: parent; hoverEnabled: true; onClicked: if (dock.shell) dock.shell.lanzadorAbierto = !dock.shell.lanzadorAbierto }
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
            color: Estilo.fondo
            border.color: Estilo.borde
            border.width: 1
            transformOrigin: Item.Bottom

            // Brota desde el icono: crece desde 0.85 con rebote suave y fundido.
            ParallelAnimation {
                id: entrada
                NumberAnimation { target: caja; property: "scale"; from: 0.85; to: 1; duration: Estilo.t(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Estilo.curvaRebote }
                NumberAnimation { target: caja; property: "opacity"; from: 0; to: 1; duration: Estilo.t(200); easing.type: Easing.OutCubic }
            }

            Column {
                id: columna
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 2

                Text {
                    width: parent.width
                    leftPadding: 10; topPadding: 4; bottomPadding: 4
                    text: menu.app && menu.app.entrada ? menu.app.entrada.name : (menu.app ? menu.app.clave : "")
                    color: Estilo.texto2
                    elide: Text.ElideRight
                    font { family: Estilo.letra; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.06 }
                }

                Repeater {
                    model: menu.opciones
                    delegate: Rectangle {
                        required property var modelData
                        width: columna.width
                        height: 32
                        radius: 9
                        color: opcion.containsMouse ? Estilo.realce : Estilo.nada
                        Behavior on color { ColorAnimation { duration: Estilo.t(120) } }
                        scale: opcion.pressed ? 0.96 : 1
                        Behavior on scale { NumberAnimation { duration: Estilo.t(140); easing.type: Easing.OutCubic } }

                        Text {
                            id: iconoOpcion
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: modelData.icono
                            color: modelData.id === "cerrar" ? Estilo.peligro : Estilo.texto
                            font { family: "Material Symbols Rounded"; pixelSize: 18 }
                            font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 20 }
                            renderType: Text.NativeRendering
                        }
                        Text {
                            anchors { left: iconoOpcion.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: modelData.texto
                            color: modelData.id === "cerrar" ? Estilo.peligro : Estilo.texto
                            font { family: Estilo.letra; pixelSize: 13; weight: Font.Normal; letterSpacing: -0.08 }
                        }
                        MouseArea { cursorShape: Qt.PointingHandCursor; id: opcion; anchors.fill: parent; hoverEnabled: true; onClicked: menu.elegir(modelData.id) }
                    }
                }
            }
        }
    }
}
