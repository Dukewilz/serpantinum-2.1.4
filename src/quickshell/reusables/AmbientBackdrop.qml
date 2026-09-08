import QtQuick
import Quickshell
import QtQuick.Effects
import "../"

Item {
    id: ambient

    property color accentColor: ThemeBackend.mauve
    property color secondaryColor: ThemeBackend.sapphire
    property color tertiaryColor: ThemeBackend.blue
    property string glyph: ""
    property real strength: 1.0
    // Main explicitly deactivates cached popups; the host passes its visibility.
    property bool active: visible
    property bool animate: active
    property bool allowWallpaper: true
    property real cornerRadius: parent && parent.radius !== undefined ? parent.radius : ThemeBackend.clampedBorderRadius
    property real topLeftRadius: parent && parent.topLeftRadius !== undefined ? parent.topLeftRadius : cornerRadius
    property real topRightRadius: parent && parent.topRightRadius !== undefined ? parent.topRightRadius : cornerRadius
    property real bottomLeftRadius: parent && parent.bottomLeftRadius !== undefined ? parent.bottomLeftRadius : cornerRadius
    property real bottomRightRadius: parent && parent.bottomRightRadius !== undefined ? parent.bottomRightRadius : cornerRadius
    enabled: false

    readonly property real baseLuma: 0.2126 * ThemeBackend.base.r + 0.7152 * ThemeBackend.base.g + 0.0722 * ThemeBackend.base.b
    readonly property real surfaceLuma: 0.2126 * ThemeBackend.surface0.r + 0.7152 * ThemeBackend.surface0.g + 0.0722 * ThemeBackend.surface0.b
    readonly property bool extremePalette: baseLuma < 0.075 || baseLuma > 0.90
    readonly property bool lowTonalSeparation: Math.abs(baseLuma - surfaceLuma) < 0.055
    readonly property real paletteBoost: extremePalette ? 1.82 : (lowTonalSeparation ? 1.48 : 1.0)
    readonly property real effectiveStrength: Math.max(0.25, strength * ThemeBackend.uiAmbientStrength)
    readonly property string wallpaperSnapshotPath: ThemeBackend.wallpaperSnapshotPath
    readonly property string liveWallpaperPath: {
        let p = (typeof Wallpaper !== "undefined" && Wallpaper) ? Wallpaper.getWallpaperPath("") : "";
        if (!p && typeof Wallpaper !== "undefined" && Wallpaper && Wallpaper.screenWallpaperPaths) {
            let map = Wallpaper.screenWallpaperPaths;
            let keys = Object.keys(map || {});
            p = keys.length > 0 ? String(map[keys[0]] || "") : "";
        }
        let lower = String(p || "").toLowerCase();
        if (lower.endsWith(".mp4") || lower.endsWith(".mkv") || lower.endsWith(".mov") || lower.endsWith(".webm")) return "";
        return p;
    }
    readonly property string wallpaperDisplayPath: liveWallpaperPath !== "" ? liveWallpaperPath : wallpaperSnapshotPath
    readonly property int wpRev: (typeof Wallpaper !== "undefined" ? Wallpaper.wallpaperRevision : 0) + ThemeBackend.wallpaperRevision
    readonly property string wallpaperSource: wallpaperDisplayPath !== "" ? ("file://" + encodeURI(wallpaperDisplayPath).replace(/#/g, "%23").replace(/\?/g, "%3F") + "?v=" + wpRev) : ""
    readonly property bool wallpaperActive: active && allowWallpaper && ThemeBackend.uiBackgroundUseWallpaper

    Connections {
        target: (typeof Wallpaper !== "undefined") ? Wallpaper : null
        function onWallpaperChanged() {
            if (ambient.wallpaperActive && wallpaperLoader.active) {
                wallpaperLoader.active = false;
                wallpaperLoader.active = true;
            }
        }
    }

    property real phase: 0
    clip: true
    opacity: ambient.wallpaperActive ? 1.0 : Math.min(1.0, effectiveStrength)

    Item {
        id: ambientContent
        anchors.fill: parent
        visible: false
        layer.enabled: ambient.visible && ambient.active

    Loader {
        id: wallpaperLoader
        anchors.fill: parent
        active: ambient.wallpaperActive
        asynchronous: false
        sourceComponent: Component {
            Image {
                source: ambient.wallpaperSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: false
                smooth: true
                visible: status === Image.Ready
                opacity: 0.95
                layer.enabled: visible && ambient.active && ThemeBackend.uiBackgroundBlur > 0.01
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: 32
                    blur: ThemeBackend.uiBackgroundBlur
                    autoPaddingEnabled: false
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(ThemeBackend.base, Math.max(0.18, Math.min(0.65, ThemeBackend.uiBackgroundOpacity * 0.55)))
        visible: ambient.wallpaperActive
    }

    NumberAnimation {
        target: ambient
        property: "phase"
        from: 0
        to: Math.PI * 2
        duration: 18000
        loops: Animation.Infinite
        running: ambient.active && ambient.animate
    }

    Rectangle {
        width: Math.max(parent.width, parent.height) * 0.62
        height: width
        radius: width / 2
        x: parent.width * 0.70 - width / 2 + Math.sin(ambient.phase) * parent.width * 0.055
        y: parent.height * 0.16 - height / 2 + Math.cos(ambient.phase * 0.8) * parent.height * 0.055
        color: Qt.alpha(ambient.accentColor, Math.min(0.16, 0.060 * ambient.paletteBoost))
        border.width: Math.max(1, width * 0.055)
        border.color: Qt.alpha(ambient.accentColor, Math.min(0.09, 0.030 * ambient.paletteBoost))
    }

    Rectangle {
        width: Math.max(parent.width, parent.height) * 0.48
        height: width
        radius: width / 2
        x: parent.width * 0.18 - width / 2 + Math.cos(ambient.phase * 0.72) * parent.width * 0.045
        y: parent.height * 0.82 - height / 2 + Math.sin(ambient.phase * 0.9) * parent.height * 0.05
        color: Qt.alpha(ambient.secondaryColor, Math.min(0.13, 0.047 * ambient.paletteBoost))
        border.width: Math.max(1, width * 0.07)
        border.color: Qt.alpha(ambient.secondaryColor, Math.min(0.075, 0.024 * ambient.paletteBoost))
    }

    Rectangle {
        width: Math.max(parent.width, parent.height) * 0.32
        height: width
        radius: width / 2
        x: parent.width * 0.48 - width / 2 + Math.sin(ambient.phase * 1.12) * parent.width * 0.035
        y: parent.height * 0.52 - height / 2 + Math.cos(ambient.phase * 0.64) * parent.height * 0.04
        color: "transparent"
        border.width: Math.max(1, width * 0.028)
        border.color: Qt.alpha(ambient.tertiaryColor, Math.min(0.11, 0.036 * ambient.paletteBoost))
    }

    Text {
        visible: ambient.glyph !== ""
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -font.pixelSize * 0.10
        anchors.bottomMargin: -font.pixelSize * 0.24
        text: ambient.glyph
        font.family: "Iosevka Nerd Font"
        font.pixelSize: Math.max(parent.height * 0.62, 140)
        color: Qt.alpha(ambient.accentColor, Math.min(0.12, 0.040 * ambient.paletteBoost))
        rotation: -8 + Math.sin(ambient.phase) * 2
    }

    }

    Rectangle {
        id: backdropMask
        anchors.fill: parent
        radius: ambient.cornerRadius
        topLeftRadius: ambient.topLeftRadius
        topRightRadius: ambient.topRightRadius
        bottomLeftRadius: ambient.bottomLeftRadius
        bottomRightRadius: ambient.bottomRightRadius
        color: "white"
        visible: false
        layer.enabled: ambient.visible && ambient.active
    }
    MultiEffect {
        anchors.fill: parent
        source: ambientContent
        maskEnabled: true
        maskSource: backdropMask
        autoPaddingEnabled: false
        visible: ambient.active
    }
}
