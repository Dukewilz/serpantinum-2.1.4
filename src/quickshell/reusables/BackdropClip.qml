pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// For decorative children only. Interactive controls stay outside this layer.
Item {
    id: backdrop
    property real cornerRadius: 0
    enabled: false
    clip: true
    layer.enabled: visible && width > 0 && height > 0 && cornerRadius > 0
    layer.effect: MultiEffect {
        autoPaddingEnabled: false
        maskEnabled: true
        maskSource: Rectangle {
            parent: backdrop
            width: backdrop.width
            height: backdrop.height
            radius: backdrop.cornerRadius
            color: "white"
            visible: false
            layer.enabled: backdrop.visible
        }
    }
}
