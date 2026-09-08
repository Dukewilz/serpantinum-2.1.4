pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: config

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string userConfigDir: homeDir + "/.config/serpantinum"
    readonly property string settingsJsonPath: Quickshell.env("QS_SETTINGS") ? Quickshell.env("QS_SETTINGS") : (userConfigDir + "/settings.json")
    readonly property string lastGoodJsonPath: settingsJsonPath + ".v24-last-good"

    property bool dataReady: false
    property bool loadFailed: false
    property var rawSettings: ({})
    property var pendingPatch: ({})
    property var activePatch: ({})
    property bool writeInFlight: false
    property bool reloadRequested: false

    signal settingsLoaded()

    function getSetting(key, fallbackValue) {
        return (rawSettings && rawSettings.hasOwnProperty(key)) ? rawSettings[key] : fallbackValue;
    }

    function hasKeys(obj) {
        return obj && Object.keys(obj).length > 0;
    }

    function mergeObjects(base, patch) {
        let merged = Object.assign({}, base || ({}));
        if (patch) {
            for (let key in patch) merged[key] = patch[key];
        }
        return merged;
    }

    // Coalesce rapid slider events and keep exactly one writer process active.
    // The JSON payload and path are argv values, so quotes in settings cannot
    // become shell syntax. The on-disk merge remains atomic and lock-protected.
    function queueJsonPatch(dataObj) {
        if (!dataReady || !dataObj || typeof dataObj !== "object" || Array.isArray(dataObj)) return;
        pendingPatch = mergeObjects(pendingPatch, dataObj);
        writeDebounce.restart();
    }

    function startNextWrite() {
        if (writeInFlight || !hasKeys(pendingPatch)) return;

        activePatch = pendingPatch;
        pendingPatch = ({});
        settingsWriter.command = [
            "bash", "-c",
            "set -e; path=$1; backup=$2; patch=$3; " +
            "mkdir -p -- \"$(dirname -- \"$path\")\"; " +
            "exec 9>\"${path}.lock\"; flock 9; " +
            "if ! jq -e 'type == \"object\"' \"$path\" >/dev/null 2>&1; then " +
            "  if jq -e 'type == \"object\"' \"$backup\" >/dev/null 2>&1; then recovery=$(mktemp \"${path}.recover.XXXXXX\"); cp -f -- \"$backup\" \"$recovery\"; chmod 600 \"$recovery\"; mv -f -- \"$recovery\" \"$path\"; else exit 65; fi; " +
            "fi; " +
            "tmp=$(mktemp \"${path}.tmp.XXXXXX\"); " +
            "trap 'rm -f -- \"$tmp\"' EXIT; " +
            "jq --argjson patch \"$patch\" 'if type == \"object\" then . + $patch else error(\"settings root is not an object\") end' \"$path\" > \"$tmp\"; " +
            "jq -e 'type == \"object\"' \"$tmp\" >/dev/null; " +
            "chmod 600 \"$tmp\"; mv -f -- \"$tmp\" \"$path\"; trap - EXIT; " +
            "backup_tmp=$(mktemp \"${backup}.tmp.XXXXXX\"); cp -f -- \"$path\" \"$backup_tmp\"; chmod 600 \"$backup_tmp\"; mv -f -- \"$backup_tmp\" \"$backup\"",
            "serpantinum-config-writer",
            settingsJsonPath,
            lastGoodJsonPath,
            JSON.stringify(activePatch)
        ];
        writeInFlight = true;
        settingsWriter.running = true;
    }

    function setSetting(key, value) {
        if (!dataReady) return;
        let patch = ({});
        patch[key] = value;
        let temp = Object.assign({}, rawSettings);
        temp[key] = value;
        rawSettings = temp;
        queueJsonPatch(patch);
    }

    function updateJsonBulk(dataObj) {
        if (!dataReady || !dataObj || typeof dataObj !== "object" || Array.isArray(dataObj)) return;
        let temp = Object.assign({}, rawSettings);
        for (let key in dataObj) temp[key] = dataObj[key];
        rawSettings = temp;
        queueJsonPatch(dataObj);
    }

    // Super+R must not destroy a debounced change.  Flush the queue and only
    // reload once the atomic writer has completed successfully.
    function requestReload() {
        reloadRequested = true;
        writeDebounce.stop();
        if (!writeInFlight && hasKeys(pendingPatch)) {
            startNextWrite();
        } else if (!writeInFlight) {
            reloadTimer.restart();
        }
    }

    Timer {
        id: writeDebounce
        interval: 120
        repeat: false
        onTriggered: config.startNextWrite()
    }

    Timer {
        id: reloadTimer
        interval: 30
        repeat: false
        onTriggered: {
            if (config.writeInFlight || config.hasKeys(config.pendingPatch)) {
                config.requestReload();
                return;
            }
            config.reloadRequested = false;
            Quickshell.reload(true);
        }
    }

    Process {
        id: settingsWriter
        running: false
        onExited: (exitCode) => {
            let completedPatch = config.activePatch;
            config.writeInFlight = false;
            config.activePatch = ({});
            if (exitCode !== 0) {
                // Preserve the user's most recent values in memory so a
                // transient I/O failure cannot silently turn into defaults.
                config.pendingPatch = config.mergeObjects(completedPatch, config.pendingPatch);
                config.reloadRequested = false;
                console.warn("Serpantinum settings write failed with exit code", exitCode);
                return;
            }
            if (config.hasKeys(config.pendingPatch)) {
                if (config.reloadRequested) config.startNextWrite();
                else writeDebounce.restart();
            } else if (settingsWatcher.path) {
                settingsWatcher.reload();
                if (config.reloadRequested) reloadTimer.restart();
            }
        }
    }

    Process {
        id: settingsBootstrap
        running: false
        onExited: (exitCode) => {
            config.loadFailed = exitCode !== 0;
            if (config.loadFailed) console.warn("Settings recovery failed; showing read-only defaults. Original settings retained.");
            if (settingsWatcher.path) settingsWatcher.reload();
        }
    }

    FileView {
        id: settingsWatcher
        path: config.settingsJsonPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                let raw = typeof text === "function" ? text() : text;
                if (typeof raw !== "string" || raw.trim().length === 0) return;

                let diskSettings = JSON.parse(raw.trim());
                if (!diskSettings || typeof diskSettings !== "object" || Array.isArray(diskSettings)) return;

                // A FileView reload from an earlier atomic rename must not
                // roll the live UI back while a newer write waits.
                if (config.writeInFlight || config.hasKeys(config.pendingPatch)) {
                    diskSettings = config.mergeObjects(diskSettings, config.activePatch);
                    diskSettings = config.mergeObjects(diskSettings, config.pendingPatch);
                }
                config.rawSettings = diskSettings;
                config.loadFailed = false;
                config.dataReady = true;
                config.settingsLoaded();
            } catch (e) {
                // Keep the last in-memory state and never announce an invalid
                // or transiently empty file as ready; Guide defaults must not
                // be allowed to overwrite it.
                console.warn("Ignoring invalid Serpantinum settings JSON:", e);
            }
        }
    }

    Component.onCompleted: {
        if (!settingsWatcher.path) return;
        settingsBootstrap.command = [
            "bash", "-c",
            "set -e; path=$1; backup=$2; mkdir -p -- \"$(dirname -- \"$path\")\"; " +
            "exec 9>\"${path}.lock\"; flock 9; " +
            "if jq -e 'type == \"object\"' \"$path\" >/dev/null 2>&1; then :; " +
            "elif jq -e 'type == \"object\"' \"$backup\" >/dev/null 2>&1; then recovery=$(mktemp \"${path}.recover.XXXXXX\"); cp -f -- \"$backup\" \"$recovery\"; chmod 600 \"$recovery\"; mv -f -- \"$recovery\" \"$path\"; " +
            "elif [ ! -s \"$path\" ]; then printf '{}' > \"$path\"; " +
            "else exit 65; fi; " +
            "tmp=$(mktemp \"${backup}.tmp.XXXXXX\"); cp -f -- \"$path\" \"$tmp\"; chmod 600 \"$tmp\"; mv -f -- \"$tmp\" \"$backup\"",
            "serpantinum-config-bootstrap",
            settingsJsonPath,
            lastGoodJsonPath
        ];
        settingsBootstrap.running = true;
    }
}
