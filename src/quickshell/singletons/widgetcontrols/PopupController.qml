pragma Singleton
import QtQuick

QtObject {
    property var receiver: null
    property var launcherWindow: null
    property var clipboardWindow: null

    function handleCommand(command, widget, argument) {
        if (!receiver) {
            console.warn("Popup controller is not ready:", widget);
            return;
        }
        receiver.handleCommand(String(command || ""), String(widget || ""), String(argument || ""));
    }
}
