pragma Singleton
import QtQuick
import Quickshell

QtObject {
    function entryFor(appId) {
        let name = String(appId || "").trim();
        if (!name) return null;
        return DesktopEntries.byId(name.replace(/\.desktop$/, ""))
            || DesktopEntries.heuristicLookup(name);
    }
    function checkedSource(value) {
        let icon = String(value || "").trim();
        if (!icon) return "";
        if (icon.startsWith("image://icon/")) icon = icon.substring(13);
        if (icon.startsWith("/")) return "file://" + encodeURI(icon).replace(/#/g, "%23").replace(/\?/g, "%3F");
        if (/^(file:|qrc:|data:|https?:|image:)/.test(icon)) return icon;
        return Quickshell.iconPath(icon, true);
    }
    function source(icon, appId) {
        let direct = checkedSource(icon);
        if (direct) return direct;
        let entry = entryFor(appId);
        return entry ? checkedSource(entry.icon) : "";
    }
}
