pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    signal wallpaperChanged(string screenName, string path, string transition)
    signal playbackChanged(string screenName, string state)
    signal wallpaperCleared(string screenName)

    property var screenWallpapers: ({})
    property var screenWallpaperPaths: ({})
    property string currentWallpaperPath: ""
    property int wallpaperRevision: 0

    function setWallpaper(screenName, path, transition) {
        let clean = String(path || "").trim();
        if (clean !== "") {
            root.currentWallpaperPath = clean;
            let slash = clean.lastIndexOf("/");
            let name = slash !== -1 ? clean.substring(slash + 1) : clean;
            let mapP = Object.assign({}, root.screenWallpaperPaths);
            let mapN = Object.assign({}, root.screenWallpapers);
            if (screenName === "all" || !screenName) {
                mapP["all"] = clean;
                mapN["all"] = name;
                for (let k of Object.keys(mapP)) {
                    mapP[k] = clean;
                    mapN[k] = name;
                }
            } else {
                mapP[screenName] = clean;
                mapN[screenName] = name;
            }
            root.screenWallpaperPaths = mapP;
            root.screenWallpapers = mapN;
            root.wallpaperRevision++;
        }
        root.wallpaperChanged(screenName, path, transition ? transition : "fade");
    }

    function getWallpaper(screenName) {
        if (root.currentWallpaperPath && (!screenName || screenName === "" || screenName === "all")) {
            let slash = root.currentWallpaperPath.lastIndexOf("/");
            return slash !== -1 ? root.currentWallpaperPath.substring(slash + 1) : root.currentWallpaperPath;
        }
        if (screenName && root.screenWallpapers && root.screenWallpapers[screenName]) {
            return root.screenWallpapers[screenName];
        }
        let keys = Object.keys(root.screenWallpapers || {});
        return keys.length > 0 ? root.screenWallpapers[keys[0]] : "";
    }

    function getWallpaperPath(screenName) {
        if (root.currentWallpaperPath && (!screenName || screenName === "" || screenName === "all")) {
            return root.currentWallpaperPath;
        }
        if (screenName && root.screenWallpaperPaths && root.screenWallpaperPaths[screenName]) {
            return root.screenWallpaperPaths[screenName];
        }
        if (root.currentWallpaperPath) return root.currentWallpaperPath;
        let keys = Object.keys(root.screenWallpaperPaths || {});
        return keys.length > 0 ? root.screenWallpaperPaths[keys[0]] : "";
    }

    function setPlayback(screenName, state) {
        root.playbackChanged(screenName, state);
    }

    function clearWallpaper(screenName) {
        root.wallpaperCleared(screenName);
    }

    IpcHandler {
        target: "wallpaper"

        function setWallpaper(screenName: string, path: string, transition: string): void {
            root.setWallpaper(screenName, path, transition);
        }

        function getWallpaper(screenName: string): string {
            return root.getWallpaper(screenName);
        }

        function getWallpaperPath(screenName: string): string {
            return root.getWallpaperPath(screenName);
        }

        function setPlayback(screenName: string, state: string): void {
            root.setPlayback(screenName, state);
        }

        function clearWallpaper(screenName: string): void {
            root.clearWallpaper(screenName);
        }
    }
}
