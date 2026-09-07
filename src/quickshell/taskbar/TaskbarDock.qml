import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../"

// v24 taskbar port for the Serpantinum 2.0.7 single-shell runtime.
// The dock is disabled by default and reads only Config's taskbar object.
Scope {
    id: root

    readonly property var defaults: ({
        "enabled": false,
        "autoHide": true,
        "showFavorites": true,
        "showRunning": true,
        "scalePercent": 88
    })
    property var configRevision: Config.rawSettings
    readonly property var settings: {
        let ignored = configRevision;
        return Config.getSetting("taskbar", defaults) || defaults;
    }
    readonly property bool enabled: settings.enabled === true
    readonly property bool autoHide: settings.autoHide !== false
    readonly property bool showFavorites: settings.showFavorites !== false
    readonly property bool showRunning: settings.showRunning !== false
    readonly property real dockScale: Math.max(0.65, Math.min(1.10,
        Number(settings.scalePercent !== undefined ? settings.scalePercent : 88) / 100.0))
    readonly property var barSettings: Config.getSetting("bar", {}) || ({})
    readonly property string barPosition: barSettings.position || "top"

    property var clients: []
    property int activeWorkspaceId: 1
    property bool edgeReveal: false
    property bool dockHover: false
    property bool collapsed: false

    readonly property var favorites: [
        { label: "Terminal", desktop: "kitty", icon: "kitty", classes: ["kitty", "org.wezfurlong.wezterm", "foot"] },
        { label: "Firefox", desktop: "firefox", icon: "firefox", classes: ["firefox", "firefoxdeveloperedition"] },
        { label: "Files", desktop: "org.gnome.Nautilus", icon: "system-file-manager", classes: ["org.gnome.nautilus", "nautilus", "thunar", "dolphin"] },
        { label: "Notes", desktop: "org.gnome.TextEditor", icon: "accessories-text-editor", classes: ["org.gnome.texteditor", "gnome-text-editor", "obsidian", "notes"] }
    ]

    function d(value) { return Math.max(1, Math.round(value * dockScale)); }

    function clientKey(client) {
        return (String(client.class || "") + " " + String(client.initialClass || "") + " " + String(client.title || "")).toLowerCase();
    }

    function favoriteForClient(client) {
        let key = clientKey(client);
        for (let i = 0; i < favorites.length; ++i) {
            let wanted = favorites[i].classes || [];
            for (let j = 0; j < wanted.length; ++j) {
                if (key.indexOf(String(wanted[j]).toLowerCase()) >= 0) return favorites[i];
            }
        }
        return null;
    }

    function clientFor(favorite) {
        let wanted = favorite.classes || [];
        for (let i = 0; i < clients.length; ++i) {
            let key = clientKey(clients[i]);
            for (let j = 0; j < wanted.length; ++j) {
                if (key.indexOf(String(wanted[j]).toLowerCase()) >= 0) return clients[i];
            }
        }
        return null;
    }

    function buildRunningApps(sourceClients) {
        if (!showRunning) return [];
        let groups = {};
        let result = [];
        for (let i = 0; i < sourceClients.length; ++i) {
            let client = sourceClients[i] || {};
            if (client.mapped === false || client.hidden === true || favoriteForClient(client)) continue;
            let key = String(client.initialClass || client.class || client.title || "").toLowerCase();
            if (!key) continue;
            if (!groups[key]) {
                groups[key] = {
                    key: key,
                    label: client.title || client.class || "Application",
                    icon: client.initialClass || client.class || "application-x-executable",
                    client: client,
                    count: 1
                };
                result.push(groups[key]);
            } else {
                groups[key].count++;
            }
        }
        return result;
    }

    readonly property var runningApps: buildRunningApps(clients)
    readonly property bool activeWorkspaceHasWindows: {
        for (let i = 0; i < clients.length; ++i) {
            let client = clients[i] || {};
            let workspace = client.workspace || {};
            if (Number(workspace.id) === activeWorkspaceId && client.mapped !== false && client.hidden !== true) return true;
        }
        return false;
    }
    readonly property bool dockHidden: enabled && autoHide && activeWorkspaceHasWindows && !edgeReveal && !dockHover

    function focusClient(client) {
        if (client && client.address)
            Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + client.address]);
    }

    function focusOrLaunch(favorite) {
        let client = clientFor(favorite);
        if (client && client.address) focusClient(client);
        else Quickshell.execDetached(["gtk-launch", favorite.desktop]);
    }

    function revealTemporarily() {
        edgeReveal = true;
        collapsed = false;
        hideDelay.restart();
    }

    onDockHiddenChanged: {
        if (dockHidden) collapseDelay.restart();
        else {
            collapseDelay.stop();
            collapsed = false;
        }
    }

    IpcHandler {
        target: "taskbarDock"
        function show(): void { root.revealTemporarily(); }
        function hide(): void { root.edgeReveal = false; }
        function toggle(): void { root.edgeReveal ? root.edgeReveal = false : root.revealTemporarily(); }
        function refresh(): void { if (!stateReader.running) stateReader.running = true; }
    }

    Timer {
        id: hideDelay
        interval: 1050
        repeat: false
        onTriggered: if (!root.dockHover) root.edgeReveal = false
    }

    Timer {
        id: collapseDelay
        interval: 340
        repeat: false
        onTriggered: if (root.dockHidden) root.collapsed = true
    }

    Process {
        id: stateReader
        command: ["bash", "-c",
            "if command -v hyprctl >/dev/null 2>&1; then " +
            "printf '{\"workspace\":'; hyprctl -j activeworkspace 2>/dev/null || printf '{\"id\":1}'; " +
            "printf ',\"clients\":'; hyprctl -j clients 2>/dev/null || printf '[]'; printf '}'; " +
            "else printf '{\"workspace\":{\"id\":1},\"clients\":[]}'; fi"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let state = JSON.parse((this.text || "{}").trim());
                    root.clients = state.clients || [];
                    root.activeWorkspaceId = Number((state.workspace || {}).id || 1);
                } catch (error) {
                    root.clients = [];
                }
            }
        }
    }

    Timer {
        // Avoid spawning two hyprctl JSON processes more than three times per
        // second.  Workspace/app state does not need sub-second polling.
        interval: 1200
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!stateReader.running) stateReader.running = true
    }

    PanelWindow {
        id: edgeWindow
        visible: root.enabled && root.dockHidden
        anchors { left: true; right: true; bottom: true }
        implicitHeight: 3
        color: "transparent"
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "serpantinum-v24-taskbar-edge"

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.revealTemporarily()
        }
    }

    PanelWindow {
        id: dockWindow
        visible: root.enabled
        anchors { bottom: true }
        margins { bottom: root.barPosition === "bottom" ? root.d(62) : root.d(10) }
        implicitWidth: dockRow.implicitWidth + root.d(28)
        implicitHeight: root.collapsed ? 1 : root.d(70)
        color: "transparent"
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "serpantinum-v24-taskbar"

        Rectangle {
            id: dockSurface
            width: dockRow.implicitWidth + root.d(28)
            height: root.d(62)
            x: (dockWindow.width - width) / 2
            y: root.dockHidden ? dockWindow.height + root.d(8) : root.d(4)
            opacity: root.dockHidden ? 0 : 1
            radius: Math.min(height / 2, root.d(20))
            color: Qt.alpha(ThemeBackend.base, Math.max(0.84, ThemeBackend.uiBackgroundOpacity))
            border.width: 1
            border.color: Qt.alpha(ThemeBackend.surface2, 0.34)

            Behavior on y { NumberAnimation { duration: 330; easing.type: Easing.InOutCubic } }
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: {
                    root.dockHover = true;
                    root.edgeReveal = true;
                    hideDelay.stop();
                }
                onExited: {
                    root.dockHover = false;
                    hideDelay.restart();
                }
            }

            RowLayout {
                id: dockRow
                anchors.centerIn: parent
                spacing: root.d(5)

                Rectangle {
                    width: root.d(40); height: root.d(40); radius: root.d(13)
                    color: launcherMouse.containsMouse ? ThemeBackend.surface1 : "transparent"
                    Text { anchors.centerIn: parent; text: "󰀻"; color: ThemeBackend.text; font.family: "Iosevka Nerd Font"; font.pixelSize: root.d(18) }
                    MouseArea {
                        id: launcherMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "applauncher"])
                    }
                }

                Rectangle { visible: root.showFavorites; width: 1; height: root.d(28); color: Qt.alpha(ThemeBackend.surface2, 0.55) }

                Repeater {
                    model: root.showFavorites ? root.favorites : []
                    Rectangle {
                        id: favoriteItem
                        required property var modelData
                        readonly property var runningClient: root.clientFor(modelData)
                        width: root.d(44); height: root.d(44); radius: root.d(14)
                        scale: favoriteMouse.containsMouse ? 1.14 : 1.0
                        y: favoriteMouse.containsMouse ? -root.d(4) : 0
                        color: favoriteMouse.containsMouse ? Qt.alpha(ThemeBackend.mauve, 0.16) : "transparent"
                        Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }
                        Behavior on y { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

                        Image {
                            anchors.centerIn: parent
                            width: root.d(27); height: root.d(27)
                            source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                            fillMode: Image.PreserveAspectFit
                            sourceSize: Qt.size(root.d(32), root.d(32))
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: favoriteItem.runningClient ? root.d(12) : root.d(4)
                            height: root.d(3); radius: root.d(2)
                            color: ThemeBackend.mauve
                            opacity: favoriteItem.runningClient ? 1 : 0.24
                        }
                        MouseArea { id: favoriteMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.focusOrLaunch(modelData) }
                    }
                }

                Repeater {
                    model: root.runningApps
                    Rectangle {
                        id: runningItem
                        required property var modelData
                        width: root.d(44); height: root.d(44); radius: root.d(14)
                        scale: runningMouse.containsMouse ? 1.14 : 1.0
                        y: runningMouse.containsMouse ? -root.d(4) : 0
                        color: runningMouse.containsMouse ? Qt.alpha(ThemeBackend.blue, 0.16) : "transparent"
                        Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }
                        Behavior on y { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

                        Image {
                            anchors.centerIn: parent
                            width: root.d(27); height: root.d(27)
                            source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                            fillMode: Image.PreserveAspectFit
                            sourceSize: Qt.size(root.d(32), root.d(32))
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            spacing: root.d(2)
                            Repeater {
                                model: Math.min(3, runningItem.modelData.count)
                                Rectangle { width: root.d(5); height: root.d(3); radius: root.d(2); color: ThemeBackend.blue }
                            }
                        }
                        MouseArea { id: runningMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.focusClient(modelData.client) }
                    }
                }
            }
        }
    }
}
