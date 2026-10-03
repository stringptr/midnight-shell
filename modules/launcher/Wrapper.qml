pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.modules.launcher.services

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property var panels

    readonly property bool shouldBeActive: screenState.launcher && Config.launcher.enabled

    readonly property real maxHeight: {
        let max = screen.height - Config.border.thickness * 2 + Tokens.padding.extraLarge;
        if (screenState.dashboard)
            max -= panels.dashboard.nonAnimHeight;
        return max;
    }

    property real offsetScale: shouldBeActive ? 0 : 1

    // Expressive overshoot past flush would retreat this panel past
    // blob.frag's bridge reach (2-sqrt2)*smoothing and tear the junction band.
    // Soft-clamp the retreat (C1 at m = t, asymptote 2t = 0.8 * reach); the
    // bar-bottom height overshoot keeps its junction edge pinned and skips it.
    function smoothRetreat(m) {
        const t = 0.4 * (2 - Math.SQRT2) * Config.border.smoothing;
        return m <= t ? m : 2 * t - t * t / m;
    }

    onShouldBeActiveChanged: {
        if (shouldBeActive)
            implicitHeight = Qt.binding(() => content.implicitHeight);
        else
            implicitHeight = implicitHeight; // Break binding during close anim
    }

    clip: Config.bar.position === "bottom"
    visible: offsetScale < 1
    anchors.bottomMargin: smoothRetreat((Config.bar.position === "bottom" ? 0 : -implicitHeight - 5) * offsetScale)
    height: Config.bar.position === "bottom" ? implicitHeight * (1 - offsetScale) : implicitHeight
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 630 // Hard coded fallback for first open
    opacity: 1 - offsetScale

    Component.onCompleted: Qt.callLater(() => Apps) // Load apps on init

    Behavior on offsetScale {
        Anim {}
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight
        }
    }
}
