import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtMultimedia
import "../"

ShellRoot {
    id: globalRoot

    Variants {
        id: root
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: barWindow

                required property var modelData
                screen: modelData

                WlrLayershell.namespace: "wallpaper-bg"
                WlrLayershell.layer: WlrLayer.Background

                focusable: false
                exclusionMode: ExclusionMode.Ignore
                mask: Region {}
                color: "#0a0a0f"

                anchors { top: true; bottom: true; left: true; right: true }

                readonly property string wpCacheDir: Caching.getCacheDir("wallpaper")
                readonly property string wpStatePath: wpCacheDir + "/current_" + barWindow.screen.name
                readonly property string wpCopyDir: wpCacheDir + "/copy_" + barWindow.screen.name
                readonly property string wpSnapshotPath: wpCacheDir + "/current_wallpaper.png"
                readonly property string wpMonitorSnapshotPath: wpCacheDir + "/current_wallpaper_" + barWindow.screen.name + ".png"

                property string currentWallpaperPath: ""
                property string originalFileName: ""
                property int activeLayer: 0
                property string pathA: ""
                property bool isVideoA: false
                property string pathB: ""
                property bool isVideoB: false
                property bool playbackPaused: false

                readonly property var transitionSettings: {
                    let themeCfg = Config.getSetting("theme", {});
                    return themeCfg && themeCfg.wallpaperTransition ? themeCfg.wallpaperTransition : {};
                }
                readonly property int transitionDuration: Math.max(350, Math.min(1800,
                    transitionSettings.duration !== undefined ? Number(transitionSettings.duration) : 950))
                property string transitionType: "expressive"
                property real transitionOriginX: width * 0.5
                property real transitionOriginY: height * 0.5
                property real transitionProgress: 1.0
                property bool isPreloading: false
                property var pendingWallpaper: null

                Component.onCompleted: restorePoller.running = true

                onCurrentWallpaperPathChanged: {
                    if (currentWallpaperPath) {
                        Wallpaper.currentWallpaperPath = currentWallpaperPath;
                        Wallpaper.wallpaperRevision++;
                    }
                    if (barWindow.screen && barWindow.screen.name) {
                        let map = Object.assign({}, Wallpaper.screenWallpaperPaths);
                        map[barWindow.screen.name] = currentWallpaperPath;
                        map["all"] = currentWallpaperPath;
                        Wallpaper.screenWallpaperPaths = map;
                    }
                }

                onOriginalFileNameChanged: {
                    if (barWindow.screen && barWindow.screen.name) {
                        let map = Object.assign({}, Wallpaper.screenWallpapers);
                        map[barWindow.screen.name] = originalFileName;
                        map["all"] = originalFileName;
                        Wallpaper.screenWallpapers = map;
                    }
                }

                Connections {
                    target: Wallpaper

                    function onWallpaperChanged(screenName, path, transition) {
                        if (screenName === "all" || screenName === barWindow.screen.name)
                            barWindow.changeWallpaper(path, transition);
                    }

                    function onPlaybackChanged(screenName, state) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            if (state === "pause") {
                                barWindow.playbackPaused = true;
                                barWindow.stopA();
                                barWindow.stopB();
                            } else if (state === "play") {
                                barWindow.playbackPaused = false;
                                if (barWindow.activeLayer === 0 && barWindow.isVideoA) barWindow.playA();
                                if (barWindow.activeLayer === 1 && barWindow.isVideoB) barWindow.playB();
                            }
                        }
                    }

                    function onWallpaperCleared(screenName) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            transitionAnim.stop();
                            videoWarmUpTimer.stop();
                            barWindow.pendingWallpaper = null;
                            barWindow.isPreloading = false;
                            barWindow.transitionProgress = 1;
                            barWindow.currentWallpaperPath = "";
                            barWindow.pathA = "";
                            barWindow.pathB = "";
                            barWindow.isVideoA = false;
                            barWindow.isVideoB = false;
                            barWindow.originalFileName = "";
                            barWindow.stopA();
                            barWindow.stopB();
                            Quickshell.execDetached(["bash", "-c", "rm -f '" + barWindow.wpStatePath + "' '" + barWindow.wpStatePath + "_name'"]);
                        }
                    }
                }

                Process {
                    id: restorePoller
                    running: false
                    command: [
                        "bash", "-c",
                        "F1='" + barWindow.wpStatePath + "'; F2='" + barWindow.wpStatePath + "_name'; [ -f \"$F1\" ] && cat \"$F1\" || true; echo '---SPLIT---'; [ -f \"$F2\" ] && cat \"$F2\" || true"
                    ]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let parts = this.text.split("---SPLIT---");
                            let savedPath = parts[0] ? parts[0].trim() : "";
                            let savedName = parts[1] ? parts[1].trim() : "";
                            if (savedPath !== "") {
                                barWindow.originalFileName = savedName;
                                if (typeof Wallpaper !== "undefined") {
                                    Wallpaper.currentWallpaperPath = savedPath;
                                    Wallpaper.wallpaperRevision++;
                                }
                                barWindow._loadNew(savedPath, false);
                                if (barWindow.isVideo(savedPath)) {
                                    videoSnapshotProcess.targetPath = savedPath;
                                    videoSnapshotProcess.running = false;
                                    videoSnapshotProcess.running = true;
                                }
                                if (savedName !== "") {
                                    let histFile = barWindow.wpCacheDir + "/history.txt";
                                    Quickshell.execDetached(["bash", "-c",
                                        "HIST='" + histFile + "'; if [ -f \"$HIST\" ]; then if [ \"$(head -n 1 \"$HIST\" 2>/dev/null)\" != '" + savedName + "' ]; then grep -v -F -x '" + savedName + "' \"$HIST\" > \"$HIST.tmp\" 2>/dev/null || true; printf '%s\n' '" + savedName + "' | cat - \"$HIST.tmp\" > \"$HIST\" 2>/dev/null; rm -f \"$HIST.tmp\"; fi; else printf '%s\n' '" + savedName + "' > \"$HIST\"; fi"
                                    ]);
                                }
                            }
                        }
                    }
                }

                Timer {
                    id: videoWarmUpTimer
                    interval: 250
                    repeat: false
                    onTriggered: barWindow.triggerTransition()
                }

                Process {
                    id: videoSnapshotProcess
                    running: false
                    property string targetPath: ""
                    command: [
                        "bash", "-c",
                        "ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null || ffmpeg -y -hide_banner -loglevel error -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null; cp -f \"$2\" \"$3\" 2>/dev/null || true",
                        "_",
                        targetPath,
                        barWindow.wpSnapshotPath,
                        barWindow.wpMonitorSnapshotPath
                    ]
                }

                function isVideo(p) {
                    let lp = p.toLowerCase();
                    return lp.endsWith(".mp4") || lp.endsWith(".mkv") ||
                           lp.endsWith(".mov") || lp.endsWith(".webm");
                }

                function playA() {
                    if (videoLoaderA.item && typeof videoLoaderA.item.play === "function") {
                        videoLoaderA.item.play();
                    }
                }

                function stopA() {
                    if (videoLoaderA.item && typeof videoLoaderA.item.stop === "function") {
                        videoLoaderA.item.stop();
                    }
                }

                function playB() {
                    if (videoLoaderB.item && typeof videoLoaderB.item.play === "function") {
                        videoLoaderB.item.play();
                    }
                }

                function stopB() {
                    if (videoLoaderB.item && typeof videoLoaderB.item.stop === "function") {
                        videoLoaderB.item.stop();
                    }
                }

                Timer {
                    id: preloadSafetyTimer
                    interval: 350
                    repeat: false
                    onTriggered: {
                        if (barWindow.isPreloading) {
                            barWindow.triggerTransition();
                        }
                    }
                }

                function triggerTransition() {
                    videoWarmUpTimer.stop();
                    preloadSafetyTimer.stop();
                    if (!barWindow.isPreloading) return;
                    barWindow.isPreloading = false;
                    barWindow.persistWallpaper(barWindow.currentWallpaperPath);
                    transitionAnim.restart();
                }

                function checkIncomingImage() {
                    if (!isPreloading) return;
                    let video = activeLayer === 0 ? isVideoA : isVideoB;
                    if (video) return;
                    let incoming = activeLayer === 0 ? imgA : imgB;
                    if (incoming.status === Image.Ready) {
                        triggerTransition();
                    } else if (incoming.status === Image.Error) {
                        console.warn("Wallpaper image failed; retaining previous wallpaper", incoming.source);
                        activeLayer = 1 - activeLayer;
                        isPreloading = false;
                        transitionProgress = 1;
                        currentWallpaperPath = activeLayer === 0 ? pathA : pathB;
                        drainPendingWallpaper();
                    }
                }

                function drainPendingWallpaper() {
                    if (!pendingWallpaper) return;
                    let pending = pendingWallpaper;
                    pendingWallpaper = null;
                    changeWallpaper(pending.path, pending.type);
                }

                function normalizeTransition(value) {
                    let candidate = String(value || transitionSettings.mode || "expressive").toLowerCase();
                    return (candidate === "expressive" || candidate === "outer" || candidate === "radial") ? "expressive" : "fade";
                }

                function layerOpacity(isIncoming, progress) {
                    if (barWindow.isPreloading && isIncoming) return 0.0;
                    if (barWindow.transitionType === "expressive") return 1.0;
                    return isIncoming ? progress : 1.0;
                }

                function radialMaxRadius() {
                    let farX = Math.max(transitionOriginX, width - transitionOriginX);
                    let farY = Math.max(transitionOriginY, height - transitionOriginY);
                    return Math.sqrt(farX * farX + farY * farY) + 4;
                }

                function _loadNew(path, force) {
                    if (!path) return;
                    if (!force && path === barWindow.currentWallpaperPath) return;

                    let cleanPath = String(path).trim();
                    let vid = barWindow.isVideo(cleanPath);

                    let slash = cleanPath.lastIndexOf("/");
                    let filename = cleanPath.substring(slash + 1);
                    if (!filename.startsWith("wallpaper.")) {
                        barWindow.originalFileName = filename;
                    }

                    transitionAnim.stop();
                    videoWarmUpTimer.stop();
                    preloadSafetyTimer.stop();
                    barWindow.transitionProgress = 0.0;
                    barWindow.isPreloading = true;
                    preloadSafetyTimer.restart();

                    if (barWindow.activeLayer === 1) {
                        barWindow.pathA = cleanPath;
                        barWindow.isVideoA = vid;
                        barWindow.activeLayer = 0;
                        if (vid) {
                            barWindow.playA();
                            videoWarmUpTimer.restart();
                        } else {
                            Qt.callLater(barWindow.checkIncomingImage);
                        }
                    } else {
                        barWindow.pathB = cleanPath;
                        barWindow.isVideoB = vid;
                        barWindow.activeLayer = 1;
                        if (vid) {
                            barWindow.playB();
                            videoWarmUpTimer.restart();
                        } else {
                            Qt.callLater(barWindow.checkIncomingImage);
                        }
                    }

                    barWindow.currentWallpaperPath = cleanPath;
                }

                function persistWallpaper(cleanPath) {
                    let slash = cleanPath.lastIndexOf("/");
                    let origName = cleanPath.substring(slash + 1);
                    let dot = cleanPath.lastIndexOf(".");
                    let ext = (dot !== -1 && dot > slash) ? cleanPath.substring(dot) : "";
                    let dest = wpCopyDir + "/wallpaper" + ext;
                    let histFile = wpCacheDir + "/history.txt";
                    let vid = barWindow.isVideo(cleanPath);
                    let snapshotPath = barWindow.wpSnapshotPath;
                    let monSnapshotPath = barWindow.wpMonitorSnapshotPath;
                    Quickshell.execDetached([
                        "bash", "-c",
                        "set -e; mkdir -p -- \"$1\"; " +
                        "printf '%s' \"$2\" > \"$3\"; printf '%s' \"$4\" > \"${3}_name\"; " +
                        "cp -f -- \"$2\" \"$5\"; " +
                        "if [ \"$6\" = image ]; then cp -f -- \"$2\" \"$7\"; cp -f -- \"$2\" \"$8\"; fi; " +
                        "exec 9>\"${10}.lock\"; flock 9; " +
                        "hist_tmp=$(mktemp \"${10}.tmp.XXXXXX\"); trap 'rm -f -- \"$hist_tmp\"' EXIT; " +
                        "printf '%s\\n' \"$4\" > \"$hist_tmp\"; " +
                        "if [ -f \"${10}\" ]; then grep -v -F -x -- \"$4\" \"${10}\" >> \"$hist_tmp\" || true; fi; " +
                        "mv -f -- \"$hist_tmp\" \"${10}\"",
                        "serpantinum-wallpaper-state", wpCopyDir, cleanPath, wpStatePath,
                        origName, dest, vid ? "video" : "image", snapshotPath,
                        monSnapshotPath, "", histFile
                    ]);

                    if (vid) {
                        videoSnapshotProcess.targetPath = cleanPath;
                        videoSnapshotProcess.running = false;
                        videoSnapshotProcess.running = true;
                    }

                }

                function changeWallpaper(path, ttype) {
                    if (!path) return;
                    if (transitionAnim.running || isPreloading) {
                        pendingWallpaper = {path: path, type: ttype};
                        return;
                    }

                    let cleanPath = String(path).trim();
                    let slash = cleanPath.lastIndexOf("/");
                    let origName = cleanPath.substring(slash + 1);
                    let dot = cleanPath.lastIndexOf(".");
                    let ext = (dot !== -1 && dot > slash) ? cleanPath.substring(dot) : "";
                    let dest = wpCopyDir + "/wallpaper" + ext;
                    let histFile = wpCacheDir + "/history.txt";
                    let vid = barWindow.isVideo(cleanPath);
                    let outgoingVideo = barWindow.activeLayer === 0 ? barWindow.isVideoA : barWindow.isVideoB;
                    barWindow.transitionType = (vid || outgoingVideo) ? "fade" : barWindow.normalizeTransition(ttype);
                    barWindow.transitionOriginX = barWindow.width * 0.5;
                    barWindow.transitionOriginY = barWindow.height * 0.5;
                    let snapshotPath = barWindow.wpSnapshotPath;
                    let monSnapshotPath = barWindow.wpMonitorSnapshotPath;

                    barWindow._loadNew(cleanPath, true);
                }

                PropertyAnimation {
                    id: transitionAnim
                    target: barWindow
                    property: "transitionProgress"
                    from: 0.0
                    to: 1.0
                    duration: barWindow.transitionDuration
                    easing.type: Easing.OutCubic

                    onFinished: {
                        Qt.callLater(barWindow.drainPendingWallpaper);
                        if (barWindow.activeLayer === 0) {
                            barWindow.stopB();
                            barWindow.pathB = "";
                            barWindow.isVideoB = false;
                        } else {
                            barWindow.stopA();
                            barWindow.pathA = "";
                            barWindow.isVideoA = false;
                        }
                    }
                }

                Component {
                    id: videoLayerCompA
                    Item {
                        anchors.fill: parent
                        function play() { playerA.play(); }
                        function stop() { playerA.stop(); }

                        MediaPlayer {
                            id: playerA
                            source: barWindow.isVideoA && barWindow.pathA ? "file://" + barWindow.pathA : ""
                            videoOutput: videoOutputA
                            loops: MediaPlayer.Infinite
                            onMediaStatusChanged: {
                                if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && barWindow.activeLayer === 0 && barWindow.isVideoA && !barWindow.playbackPaused) {
                                    playerA.play();
                                }
                            }
                        }

                        VideoOutput {
                            id: videoOutputA
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                        }
                    }
                }

                Component {
                    id: videoLayerCompB
                    Item {
                        anchors.fill: parent
                        function play() { playerB.play(); }
                        function stop() { playerB.stop(); }

                        MediaPlayer {
                            id: playerB
                            source: barWindow.isVideoB && barWindow.pathB ? "file://" + barWindow.pathB : ""
                            videoOutput: videoOutputB
                            loops: MediaPlayer.Infinite
                            onMediaStatusChanged: {
                                if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && barWindow.activeLayer === 1 && barWindow.isVideoB && !barWindow.playbackPaused) {
                                    playerB.play();
                                }
                            }
                        }

                        VideoOutput {
                            id: videoOutputB
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                        }
                    }
                }

                Item {
                    id: scene
                    anchors.fill: parent
                    clip: true

                    Item {
                        id: layerA
                        width: parent.width
                        height: parent.height

                        readonly property bool isIncoming: barWindow.activeLayer === 0
                        readonly property real p: barWindow.transitionProgress
                        readonly property bool radialIncoming: barWindow.transitionType === "expressive" && isIncoming && p < 1.0
                        readonly property real circleRadius: Math.max(0, barWindow.radialMaxRadius() * p)

                        z: isIncoming ? 2 : 1
                        visible: isIncoming || p < 1.0
                        opacity: barWindow.layerOpacity(isIncoming, p)

                        Item {
                            id: contentA
                            anchors.fill: parent
                            visible: !layerA.radialIncoming
                            layer.enabled: layerA.radialIncoming

                            Image {
                                id: imgA
                                onStatusChanged: Qt.callLater(barWindow.checkIncomingImage)
                                anchors.fill: parent
                                source: !barWindow.isVideoA && barWindow.pathA ? "file://" + barWindow.pathA : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: !barWindow.isVideoA && barWindow.pathA !== ""
                                cache: true
                                sourceSize.width: parent.width > 0 ? parent.width : 0
                                sourceSize.height: parent.height > 0 ? parent.height : 0
                            }

                            Loader {
                                id: videoLoaderA
                                anchors.fill: parent
                                active: barWindow.isVideoA && barWindow.pathA !== ""
                                asynchronous: false
                                sourceComponent: videoLayerCompA
                                visible: barWindow.isVideoA
                                onLoaded: {
                                    if (item && barWindow.activeLayer === 0 && barWindow.isVideoA && !barWindow.playbackPaused) item.play();
                                }
                            }
                        }

                        Item {
                            id: radialMaskA
                            anchors.fill: parent
                            visible: false
                            layer.enabled: layerA.radialIncoming
                            Rectangle {
                                width: layerA.circleRadius * 2
                                height: width
                                radius: width / 2
                                x: barWindow.transitionOriginX - width / 2
                                y: barWindow.transitionOriginY - height / 2
                                color: "white"
                                antialiasing: true
                            }
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: contentA
                            maskEnabled: true
                            maskSource: radialMaskA
                            maskSpreadAtMin: 0.08
                            autoPaddingEnabled: false
                            visible: layerA.radialIncoming
                        }

                        Rectangle {
                            visible: layerA.radialIncoming && layerA.circleRadius > 2
                            width: layerA.circleRadius * 2
                            height: width
                            radius: width / 2
                            x: barWindow.transitionOriginX - width / 2
                            y: barWindow.transitionOriginY - height / 2
                            color: "transparent"
                            border.width: 3
                            border.color: Qt.alpha(ThemeBackend.text, 0.35 * (1.0 - layerA.p))
                            antialiasing: true
                        }
                    }

                    Item {
                        id: layerB
                        width: parent.width
                        height: parent.height

                        readonly property bool isIncoming: barWindow.activeLayer === 1
                        readonly property real p: barWindow.transitionProgress
                        readonly property bool radialIncoming: barWindow.transitionType === "expressive" && isIncoming && p < 1.0
                        readonly property real circleRadius: Math.max(0, barWindow.radialMaxRadius() * p)

                        z: isIncoming ? 2 : 1
                        visible: isIncoming || p < 1.0
                        opacity: barWindow.layerOpacity(isIncoming, p)

                        Item {
                            id: contentB
                            anchors.fill: parent
                            visible: !layerB.radialIncoming
                            layer.enabled: layerB.radialIncoming

                            Image {
                                id: imgB
                                onStatusChanged: Qt.callLater(barWindow.checkIncomingImage)
                                anchors.fill: parent
                                source: !barWindow.isVideoB && barWindow.pathB ? "file://" + barWindow.pathB : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: !barWindow.isVideoB && barWindow.pathB !== ""
                                cache: true
                                sourceSize.width: parent.width > 0 ? parent.width : 0
                                sourceSize.height: parent.height > 0 ? parent.height : 0
                            }

                            Loader {
                                id: videoLoaderB
                                anchors.fill: parent
                                active: barWindow.isVideoB && barWindow.pathB !== ""
                                asynchronous: false
                                sourceComponent: videoLayerCompB
                                visible: barWindow.isVideoB
                                onLoaded: {
                                    if (item && barWindow.activeLayer === 1 && barWindow.isVideoB && !barWindow.playbackPaused) item.play();
                                }
                            }
                        }

                        Item {
                            id: radialMaskB
                            anchors.fill: parent
                            visible: false
                            layer.enabled: layerB.radialIncoming
                            Rectangle {
                                width: layerB.circleRadius * 2
                                height: width
                                radius: width / 2
                                x: barWindow.transitionOriginX - width / 2
                                y: barWindow.transitionOriginY - height / 2
                                color: "white"
                                antialiasing: true
                            }
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: contentB
                            maskEnabled: true
                            maskSource: radialMaskB
                            maskSpreadAtMin: 0.08
                            autoPaddingEnabled: false
                            visible: layerB.radialIncoming
                        }

                        Rectangle {
                            visible: layerB.radialIncoming && layerB.circleRadius > 2
                            width: layerB.circleRadius * 2
                            height: width
                            radius: width / 2
                            x: barWindow.transitionOriginX - width / 2
                            y: barWindow.transitionOriginY - height / 2
                            color: "transparent"
                            border.width: 3
                            border.color: Qt.alpha(ThemeBackend.text, 0.35 * (1.0 - layerB.p))
                            antialiasing: true
                        }
                    }
                }
            }
        }
    }
}
