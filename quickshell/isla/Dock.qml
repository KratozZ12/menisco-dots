import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Dock flotante abajo al centro: la unica pieza de vidrio de Menisco. Su material se elige en
// Ajustes > Dock: Vidrio (de fabrica), Ahumado, Escarcha y Tinte llevan vidrio (desenfoque y liquid
// glass del compositor, solo dentro del cuerpo: BackgroundEffect.blurRegion); Solido, Contorno y
// Material You no, y usan la capa "dock-solido", que no lo recibe.
// Apps: primero las fijadas (dock.json); despues, tras un separador, las abiertas sin fijar.
// Clic derecho: un solo menu para todas (accion de la app, fijar o quitar, cerrar si esta abierta).
// Movimiento calmo: transiciones cortas (180 ms) sin rebote.
PanelWindow {
    id: dock

    // Se llama "shell" y no "raiz": con "raiz: raiz" en shell.qml la propiedad se enlazaba
    // consigo misma (null) en vez de con la raiz del shell, y el boton no hacia nada.
    property var shell: null   // para abrir el lanzador y decirle de donde brotar

    // ---- Medidas (Ajustes > Dock > Tamano de iconos) ----
    readonly property int icono: Math.max(40, Math.min(64, Estilo.valor("dockIcono")))
    readonly property int relleno: Math.round(icono * 0.19)
    readonly property int pie: 6                                // hueco bajo los iconos para el indicador
    readonly property int radioIcono: Math.round(icono * 0.225)
    readonly property int radio: radioIcono + relleno           // radio concentrico
    readonly property int alto: icono + relleno * 2 + pie       // alto del cuerpo
    readonly property bool aumento: Estilo.valor("dockAumento")
    // Aire sobre el cuerpo para el icono que crece (x1.16 desde abajo y 6 px mas arriba).
    readonly property int aire: aumento ? Math.ceil(icono * 0.16) + 8 : 0
    function anim(ms) { return Estilo.t(ms); }

    // ---- Apps fijadas, guardadas en dock.json ----
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

    // Lo que deberia verse: las fijadas, y las abiertas sin fijar (si el ajuste lo permite).
    readonly property var deseadasFijadas: ancladas.map(a => ({ clave: a.ventana, escritorio: a.escritorio, anclada: true }))
    readonly property var deseadasSueltas: {
        DesktopEntries.applications.values.length;   // reevaluar cuando terminen de cargar los .desktop
        if (!Estilo.valor("dockSinFijar")) return [];
        const lista = [];
        for (const t of ToplevelManager.toplevels.values) {
            if (!t.appId || ancladas.some(a => a.ventana === t.appId) || lista.some(x => x.clave === t.appId)) continue;
            const e = DesktopEntries.heuristicLookup(t.appId);
            lista.push({ clave: t.appId, escritorio: e ? e.id : "", anclada: false });
        }
        return lista;
    }
    onDeseadasFijadasChanged: sincronizar(modeloFijadas, deseadasFijadas)
    onDeseadasSueltasChanged: sincronizar(modeloSueltas, deseadasSueltas)
    Component.onCompleted: { sincronizar(modeloFijadas, deseadasFijadas); sincronizar(modeloSueltas, deseadasSueltas); }

    // Se edita el modelo pieza por pieza (en vez de reemplazarlo) para que solo
    // anime el icono que entra o sale y el resto conserve su estado.
    ListModel { id: modeloFijadas }
    ListModel { id: modeloSueltas }
    function sincronizar(modelo, d) {
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
    readonly property var aspecto: Estilo.aspectoDock(material, Estilo.tonoDock)
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
    // todas las formas: si cambiara al pasar de una a otra, niri movería la ventana a saltos. Con
    // vidrio, "e" es el margen de la sombra.
    property bool sinVidrio: !conVidrio
    readonly property real e: sinVidrio ? 124 : 28
    // Cambio de forma: de la vieja a la nueva.
    property string formaVieja: Estilo.valor("dockForma")
    property string formaNueva: Estilo.valor("dockForma")
    property real cambio: 1
    readonly property string formaElegida: Estilo.valor("dockForma")
    onFormaElegidaChanged: { formaVieja = formaNueva; formaNueva = formaElegida; animForma.restart(); }
    NumberAnimation { id: animForma; target: dock; property: "cambio"; from: 0; to: 1; duration: dock.anim(180); easing.type: Easing.OutCubic }
    readonly property real g: Estilo.grosorMarco
    Connections { target: Estilo; function onDockPegadoChanged() { aparecer.stop(); bajar.restart(); } }
    // Cuanto baja el cuerpo al aparecer o al cambiar de capa.
    property real bajada: 16
    SequentialAnimation {
        id: bajar
        ParallelAnimation {
            NumberAnimation { target: fondo; property: "opacity"; to: 0; duration: dock.anim(180); easing.type: Easing.InCubic }
            NumberAnimation { target: dock; property: "bajada"; to: 16; duration: dock.anim(180); easing.type: Easing.InCubic }
        }
        ScriptAction { script: { dock.oculto = true; dock.capa = dock.conVidrio ? "dock" : "dock-solido"; dock.pegado = Estilo.dockPegado; dock.sinVidrio = !dock.conVidrio; } }
        PauseAnimation { duration: 40 }
        ScriptAction { script: { dock.oculto = false; aparecer.restart(); } }
    }
    ParallelAnimation {
        id: aparecer
        NumberAnimation { target: fondo; property: "opacity"; to: 1; duration: dock.anim(180); easing.type: Easing.OutCubic }
        NumberAnimation { target: dock; property: "bajada"; to: 0; duration: dock.anim(220); easing.type: Easing.OutCubic }
    }

    // ---- Ocultar (Ajustes > Dock > Ocultar) ----
    // "siempre": se esconde bajo el borde y vuelve al llevar el cursor abajo; se va de nuevo
    // pasado el retraso. ponytail: "ventana" (si una ventana lo toca) se guarda pero todavia se
    // comporta como "nunca": hace falta saber donde esta cada ventana en la pantalla.
    readonly property bool seEsconde: Estilo.valor("dockOcultar") === "siempre"
    property bool cerca: false
    Connections {
        target: sobre
        function onHoveredChanged() { if (sobre.hovered) { esperaOcultar.stop(); dock.cerca = true; } else esperaOcultar.restart(); }
    }
    Timer { id: esperaOcultar; interval: Math.max(0, Estilo.valor("dockRetraso")); onTriggered: dock.cerca = false }
    readonly property bool escondido: seEsconde && !cerca && !menu.visible && !Estilo.vistaGeneral
    property real escondeY: escondido ? alto + 12 : 0
    Behavior on escondeY { NumberAnimation { duration: dock.anim(180); easing.type: Easing.OutCubic } }

    PanelWindow {
        id: reserva
        screen: dock.screen
        anchors.bottom: true
        // Fija: flotante o pegado, las ventanas no se mueven. Escondido, no reserva nada.
        margins.bottom: 10
        exclusiveZone: dock.seEsconde ? 0 : dock.alto   // niri ya le suma el margen de abajo
        implicitWidth: 1; implicitHeight: 1
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "dock-reserva"
    }

    anchors.bottom: true
    margins.bottom: 0
    exclusionMode: ExclusionMode.Ignore   // el espacio lo reserva "reserva"
    implicitWidth: fila.implicitWidth + relleno * 2 + 6 + e * 2
    implicitHeight: aire + alto + (pegado ? g : 10)
    color: "transparent"
    WlrLayershell.namespace: capa
    Gelatina { objetivo: dock.contentItem; origenY: 1 }   // se va con la vista general

    // El vidrio, solo dentro del cuerpo (el aire de arriba y la sombra quedan fuera).
    BackgroundEffect.blurRegion: conVidrio ? regionVidrio : null
    property Region regionVidrio: Region { item: fondo; radius: dock.radio }
    // Lo que recibe clics: el cuerpo, y el aire de arriba mientras el cursor esta en el dock
    // (para el icono que crece). Escondido, una franja de 3 px en el borde de abajo.
    property Region sinNada: Region {}
    property Region regionCuerpo: Region { item: fondo; Region { item: levantado } }
    property Region regionFranja: Region { item: franja }
    mask: Estilo.vistaGeneral ? sinNada : escondido ? regionFranja : regionCuerpo

    Item {
        id: levantado
        x: fondo.x; y: fondo.y - dock.aire
        width: fondo.width; height: sobre.hovered ? dock.aire : 0
    }
    Item { id: franja; x: fondo.x; y: dock.height - 3; width: fondo.width; height: 3 }
    HoverHandler { id: sobre }

    // ---- Sombra exterior suave (solo con vidrio), recortada para que no oscurezca el cuerpo ----
    Item {
        id: sombra
        anchors.fill: parent
        visible: dock.conVidrio && !dock.sinVidrio
        opacity: fondo.opacity
        layer.enabled: visible
        layer.effect: MultiEffect { maskEnabled: true; maskInverted: true; maskSource: mascaraCuerpo }
        RectangularShadow {
            x: fondo.x; y: fondo.y + 4; width: fondo.width; height: fondo.height
            radius: dock.radio; blur: 22; spread: 0
            color: Qt.rgba(0, 0, 0, 0.32)
        }
    }
    Item {
        id: mascaraCuerpo
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { x: fondo.x; y: fondo.y; width: fondo.width; height: fondo.height; radius: dock.radio; color: "black" }
    }

    Rectangle {
        id: fondo
        x: dock.e
        y: dock.aire + dock.bajada + dock.escondeY
        width: dock.width - dock.e * 2
        height: dock.alto
        radius: dock.radio
        color: dock.sinVidrio ? "transparent" : dock.aspecto.relleno
        Behavior on color { ColorAnimation { duration: dock.anim(180) } }

        // Reflejo del material: blanco tenue arriba que se apaga hacia el 40 % del alto.
        Rectangle {
            anchors.fill: parent
            radius: dock.radio
            visible: !dock.sinVidrio && dock.aspecto.reflejo > 0
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, dock.aspecto.reflejo) }
                GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
        // Filo de 1 px con degradado: brillante arriba, tenue en los lados, casi nada abajo.
        Shape {
            id: filo
            anchors.fill: parent
            visible: !dock.sinVidrio
            preferredRendererType: Shape.CurveRenderer
            function rect(x, y, w, h, r) {
                return `M${x + r} ${y} H${x + w - r} A${r} ${r} 0 0 1 ${x + w} ${y + r} V${y + h - r} A${r} ${r} 0 0 1 ${x + w - r} ${y + h} `
                     + `H${x + r} A${r} ${r} 0 0 1 ${x} ${y + h - r} V${y + r} A${r} ${r} 0 0 1 ${x + r} ${y} Z`;
            }
            ShapePath {
                strokeWidth: -1
                fillRule: ShapePath.OddEvenFill
                fillGradient: LinearGradient {
                    y1: 0; y2: fondo.height
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, dock.aspecto.filo ? dock.aspecto.filo[0] : 0) }
                    GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, dock.aspecto.filo ? dock.aspecto.filo[1] : 0) }
                    GradientStop { position: 0.7; color: Qt.rgba(1, 1, 1, dock.aspecto.filo ? dock.aspecto.filo[1] : 0) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, dock.aspecto.filo ? dock.aspecto.filo[2] : 0) }
                }
                PathSvg {
                    readonly property real a: dock.aspecto.ancho
                    path: filo.rect(0, 0, fondo.width, fondo.height, dock.radio)
                        + " " + filo.rect(a, a, fondo.width - 2 * a, fondo.height - 2 * a, Math.max(0, dock.radio - a))
                }
            }
        }

        // Sin vidrio: la forma elegida. Pegado: hombros abajo que se funden con el borde del marco,
        // y el filo (Solido y Contorno) no cierra por abajo: sigue en el marco.
        Shape {
            id: silueta
            visible: dock.sinVidrio
            x: -dock.e; width: fondo.width + dock.e * 2; height: fondo.height + (dock.pegado ? dock.g : 0)
            preferredRendererType: Shape.CurveRenderer
            function mezcla(a, b, t) { return a.map((q, i) => [q[0] + (b[i][0] - q[0]) * t, q[1] + (b[i][1] - q[1]) * t]); }
            readonly property var mitad: mezcla(Estilo.mitadDock(dock.formaVieja, dock.e, fondo.height, dock.pegado, dock.hombro),
                                                Estilo.mitadDock(dock.formaNueva, dock.e, fondo.height, dock.pegado, dock.hombro), dock.cambio)
            readonly property bool conFilo: dock.material === "contorno" || dock.material === "solido"
            ShapePath {
                fillColor: dock.aspecto.relleno
                strokeWidth: -1
                PathSvg { path: Estilo.trazoDock(silueta.mitad, silueta.width / 2, dock.pegado, silueta.height) }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: silueta.conFilo ? Qt.rgba(1, 1, 1, dock.aspecto.filo[0]) : "transparent"
                strokeWidth: silueta.conFilo ? dock.aspecto.ancho : 0
                PathSvg { path: Estilo.trazoDock(silueta.mitad, silueta.width / 2, dock.pegado, dock.pegado ? -1 : 0) }
            }
        }

        // Aparece al arrancar: sube 16 px con fundido.
        opacity: 0
        Component.onCompleted: aparecer.start()

        Row {
            id: fila
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: dock.relleno }
            spacing: 10

            ListView {
                id: listaFijadas
                orientation: ListView.Horizontal
                interactive: false
                spacing: 10
                height: dock.icono
                // El ancho se anima: el cuerpo (y su vidrio) crece o se encoge con suavidad.
                width: Math.max(0, contentWidth)
                Behavior on width { NumberAnimation { duration: dock.anim(180); easing.type: Easing.OutCubic } }
                model: modeloFijadas
                add: Transition { NumberAnimation { properties: "scale,opacity"; from: 0; to: 1; duration: dock.anim(180); easing.type: Easing.OutCubic } }
                remove: Transition { NumberAnimation { properties: "scale,opacity"; to: 0; duration: dock.anim(180); easing.type: Easing.InCubic } }
                displaced: Transition { NumberAnimation { property: "x"; duration: dock.anim(180); easing.type: Easing.OutCubic } }
                delegate: Icono {}
            }

            Separador { visible: modeloSueltas.count > 0 }

            // Abiertas sin fijar: despues de las fijadas; al cerrarse, se van.
            ListView {
                id: listaSueltas
                visible: modeloSueltas.count > 0 || width > 1
                orientation: ListView.Horizontal
                interactive: false
                spacing: 10
                height: dock.icono
                width: Math.max(0, contentWidth)
                Behavior on width { NumberAnimation { duration: dock.anim(180); easing.type: Easing.OutCubic } }
                model: modeloSueltas
                add: Transition { NumberAnimation { properties: "scale,opacity"; from: 0; to: 1; duration: dock.anim(180); easing.type: Easing.OutCubic } }
                remove: Transition { NumberAnimation { properties: "scale,opacity"; to: 0; duration: dock.anim(180); easing.type: Easing.InCubic } }
                displaced: Transition { NumberAnimation { property: "x"; duration: dock.anim(180); easing.type: Easing.OutCubic } }
                delegate: Icono {}
            }

            Separador {}

            // Todas las apps (lo mismo que Super+D): no crece; se aclara al pasar el cursor.
            Rectangle {
                id: botonLanzador
                width: dock.icono
                height: dock.icono
                radius: dock.radioIcono
                color: Qt.rgba(1, 1, 1, zonaMenu.pressed || (dock.shell && dock.shell.lanzadorAbierto) ? 0.3 : zonaMenu.containsMouse ? 0.22 : 0.12)
                Behavior on color { ColorAnimation { duration: dock.anim(180); easing.type: Easing.OutCubic } }
                scale: zonaMenu.pressed ? 0.92 : 1
                Behavior on scale { NumberAnimation { duration: dock.anim(120); easing.type: Easing.OutCubic } }

                Text {
                    anchors.centerIn: parent
                    text: "apps"
                    color: "#ffffff"
                    font { family: "Material Symbols Rounded"; pixelSize: Math.round(dock.icono * 0.55) }
                    font.variableAxes: { "FILL": 1, "wght": 500, "opsz": 24 }
                    renderType: Text.NativeRendering
                }
                MouseArea { cursorShape: Qt.PointingHandCursor; id: zonaMenu; anchors.fill: parent; hoverEnabled: true; onClicked: if (dock.shell) dock.shell.lanzadorAbierto = !dock.shell.lanzadorAbierto }
            }
        }
    }

    component Separador: Rectangle {
        width: 1
        height: dock.icono - 12
        y: 6
        color: Estilo.borde
    }

    // ---- Icono de una app ----
    component Icono: Item {
        id: app
        required property string clave
        required property string escritorio
        required property bool anclada

        // byId() no se reevalua cuando terminan de cargar los .desktop; la lista si.
        readonly property var entrada: DesktopEntries.applications.values.find(e => e.id === escritorio)
                                       ?? DesktopEntries.heuristicLookup(clave)
        readonly property string nombre: entrada ? entrada.name : clave
        readonly property var ventanas: ToplevelManager.toplevels.values.filter(t => t.appId === clave)
        readonly property bool abierta: ventanas.length > 0
        readonly property bool enfocada: ventanas.some(t => t.activated)
        readonly property bool encima: zona.containsMouse && !menu.visible
        onEncimaChanged: {
            if (encima && Estilo.valor("dockNombre")) etiqueta.mostrar(app);
            else if (etiqueta.app === app) etiqueta.ocultar();
        }

        width: dock.icono
        height: dock.icono

        Image {
            id: imagen
            anchors.fill: parent
            source: Quickshell.iconPath(app.entrada ? app.entrada.icon : app.clave, "application-x-executable")
            // Mas grande que el icono para que siga nitido al crecer (los PNG de hicolor no cargan a 46).
            sourceSize: Qt.size(Math.round(dock.icono * 1.25), Math.round(dock.icono * 1.25))
            smooth: true; mipmap: true
            transformOrigin: Item.Bottom
            // Aumento: solo este icono crece (x1.16) y sube 6 px; los vecinos no se mueven.
            readonly property bool crece: app.encima && dock.aumento
            scale: (crece ? 1.16 : 1) * (zona.pressed ? 0.92 : 1)
            Behavior on scale { NumberAnimation { duration: dock.anim(180); easing.type: Easing.OutCubic } }
            transform: Translate {
                y: imagen.crece ? -6 : 0
                Behavior on y { NumberAnimation { duration: dock.anim(180); easing.type: Easing.OutCubic } }
            }
            // Sin aumento: un leve aclarado.
            layer.enabled: !dock.aumento
            layer.effect: MultiEffect {
                brightness: app.encima ? 0.12 : 0
                Behavior on brightness { NumberAnimation { duration: dock.anim(180) } }
            }
        }

        // Indicador: punto blanco si esta abierta; pildora del acento si ademas tiene el foco.
        Rectangle {
            readonly property bool pildora: app.enfocada && Estilo.valor("dockIndicador") === "pildora"
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 3 }
            width: pildora ? 14 : 4; height: 4; radius: 2
            color: pildora ? Estilo.acento : Qt.rgba(1, 1, 1, 0.6)
            opacity: app.abierta ? 1 : 0
            Behavior on width { NumberAnimation { duration: dock.anim(180); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: dock.anim(180) } }
            Behavior on opacity { NumberAnimation { duration: dock.anim(180) } }
        }

        MouseArea {
            id: zona
            // Mientras crece, la zona sube con el icono: si no, el borde de arriba parpadea.
            anchors { fill: parent; topMargin: imagen.crece ? -dock.aire : 0 }
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) { menu.abrirPara(app); return; }
                if (!app.abierta) { if (app.entrada) app.entrada.execute(); return; }
                // Abierta: la enfoca; con "Siguiente ventana", pasa a la siguiente de esa app.
                const v = app.ventanas, i = v.findIndex(t => t.activated);
                if (Estilo.valor("dockClic") === "siguiente") v[(i + 1) % v.length].activate();
                else (i >= 0 ? v[i] : v[0]).activate();
            }
        }
    }

    // ---- Nombre al pasar el cursor: pildora negra encima del icono ----
    PopupWindow {
        id: etiqueta
        property var app: null
        function mostrar(a) { app = a; visible = true; fundido.restart(); }
        function ocultar() { visible = false; }
        anchor.item: app
        anchor.rect: Qt.rect(0, -(dock.aire + 2), app ? app.width : 0, 0)
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        implicitWidth: textoEtiqueta.implicitWidth + 22
        implicitHeight: 28
        color: "transparent"
        mask: Region {}                 // no recibe el cursor
        Rectangle {
            id: pildoraEtiqueta
            anchors.fill: parent
            radius: 8
            color: Qt.alpha(Estilo.fondo, 0.86)
            NumberAnimation { id: fundido; target: pildoraEtiqueta; property: "opacity"; from: 0; to: 1; duration: dock.anim(180); easing.type: Easing.OutCubic }
            Text {
                id: textoEtiqueta
                anchors.centerIn: parent
                text: etiqueta.app ? etiqueta.app.nombre : ""
                color: Estilo.texto
                font { family: Estilo.letra; pointSize: 9.375;   // 12.5 px (pixelSize solo admite enteros)
                weight: Font.Medium }
            }
        }
    }

    // ---- Menu de clic derecho: uno solo para todas las apps ----
    // Nombre; accion de la app (Abrir, o Nueva ventana y Ventanas si tiene varias); Fijar o
    // Quitar; y Cerrar, solo si esta abierta.
    PopupWindow {
        id: menu
        property var app: null
        property bool verVentanas: false
        readonly property bool abierta: app ? app.abierta : false
        readonly property var opciones: {
            if (!app) return [];
            const l = [];
            if (abierta) {
                l.push({ id: "nueva", texto: "Nueva ventana", icono: "add_box" });
                if (app.ventanas.length > 1) {
                    l.push({ id: "ventanas", texto: "Ventanas", icono: "select_window", cuenta: app.ventanas.length });
                    if (verVentanas) app.ventanas.forEach((t, i) => l.push({ id: "ventana", texto: t.title || app.nombre, icono: "", indice: i }));
                }
            } else l.push({ id: "abrir", texto: "Abrir", icono: "open_in_new" });
            l.push({ id: "-" });
            l.push(app.anclada ? { id: "quitar", texto: "Quitar del dock", icono: "keep_off" }
                               : { id: "fijar", texto: "Fijar en el dock", icono: "keep" });
            if (abierta) { l.push({ id: "-" }); l.push({ id: "cerrar", texto: "Cerrar", icono: "close" }); }
            return l;
        }

        function abrirPara(item) {
            etiqueta.ocultar();
            app = item;
            verVentanas = false;
            visible = true;
            entrada.restart();
        }
        function elegir(o) {
            const a = app;
            if (o.id === "ventanas") { verVentanas = !verVentanas; return; }
            visible = false;
            if (o.id === "cerrar") a.ventanas.forEach(t => t.close());
            else if (o.id === "fijar") dock.anclar(a.clave, a.entrada ? a.entrada.id : "");
            else if (o.id === "quitar") dock.desanclar(a.clave);
            else if ((o.id === "abrir" || o.id === "nueva") && a.entrada) a.entrada.execute();
            else if (o.id === "ventana" && a.ventanas[o.indice]) a.ventanas[o.indice].activate();
        }

        anchor.item: app
        anchor.rect: Qt.rect(0, -10, app ? app.width : 0, 0)
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        grabFocus: true                 // un clic fuera lo cierra
        implicitWidth: 228
        implicitHeight: columna.implicitHeight + 12
        color: "transparent"

        Rectangle {
            id: caja
            anchors.fill: parent
            radius: 14
            color: Estilo.tarjeta
            border.color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            transformOrigin: Item.Bottom

            ParallelAnimation {
                id: entrada
                NumberAnimation { target: caja; property: "scale"; from: 0.96; to: 1; duration: dock.anim(180); easing.type: Easing.OutCubic }
                NumberAnimation { target: caja; property: "opacity"; from: 0; to: 1; duration: dock.anim(180); easing.type: Easing.OutCubic }
            }

            Column {
                id: columna
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }

                Text {
                    width: parent.width
                    leftPadding: 10; topPadding: 6; bottomPadding: 6
                    text: menu.app ? menu.app.nombre : ""
                    color: Estilo.texto2
                    elide: Text.ElideRight
                    font { family: Estilo.letra; pixelSize: 12 }
                }

                Repeater {
                    model: menu.opciones
                    delegate: Item {
                        id: fila
                        required property var modelData
                        readonly property bool raya: modelData.id === "-"
                        readonly property bool peligro: modelData.id === "cerrar"
                        readonly property bool sub: modelData.id === "ventana"
                        width: columna.width
                        height: raya ? 9 : 34
                        Rectangle {
                            visible: fila.raya
                            anchors.verticalCenter: parent.verticalCenter
                            x: 8; width: parent.width - 16; height: 1
                            color: Estilo.linea
                        }
                        Rectangle {
                            visible: !fila.raya
                            anchors.fill: parent
                            radius: 9
                            color: opcion.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0)
                            Behavior on color { ColorAnimation { duration: dock.anim(120) } }
                            Text {
                                id: iconoOpcion
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                width: 16
                                text: fila.modelData.icono || ""
                                // Rojo suave: no hay token para este tono.
                                color: fila.peligro ? "#f28b82" : Estilo.texto
                                font { family: "Material Symbols Rounded"; pixelSize: 16 }
                                font.variableAxes: { "FILL": 0, "wght": 400, "opsz": 20 }
                                renderType: Text.NativeRendering
                            }
                            Text {
                                anchors { left: iconoOpcion.right; leftMargin: fila.sub ? 14 : 10; right: cuenta.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                text: fila.modelData.texto || ""
                                elide: Text.ElideRight
                                color: fila.peligro ? "#f28b82" : fila.sub ? Estilo.texto2 : Estilo.texto
                                font { family: Estilo.letra; pointSize: 10.125 }   // 13.5 px
                            }
                            Text {
                                id: cuenta
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                text: fila.modelData.cuenta || ""
                                color: Estilo.texto2
                                font { family: Estilo.letra; pointSize: 10.125 }   // 13.5 px
                            }
                            MouseArea { id: opcion; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: menu.elegir(fila.modelData) }
                        }
                    }
                }
            }
        }
    }
}
