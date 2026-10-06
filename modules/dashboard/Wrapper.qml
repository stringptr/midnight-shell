pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.filedialog
import qs.utils

Item {
    id: root

    required property ScreenState screenState
    readonly property FileDialog facePicker: FileDialog {
        title: Tr.tr("Select a profile picture")
        filterLabel: Tr.tr("Image files")
        filters: Images.validImageExtensions
        onAccepted: path => {
            if (CUtils.copyFile(Qt.resolvedUrl(path), Qt.resolvedUrl(`${Paths.home}/.face`)))
                // TRANSLATORS: %1 = a file path
                Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "low", "-h", `STRING:image-path:${path}`, Tr.tr("Profile picture changed"), Tr.tr("Profile picture changed to %1").arg(Paths.shortenHome(path))]);
            else
                // TRANSLATORS: %1 = a file path
                Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "critical", Tr.tr("Unable to change profile picture"), Tr.tr("Failed to change profile picture to %1").arg(Paths.shortenHome(path))]);
        }
    }

    readonly property real nonAnimHeight: (content.item as Content)?.nonAnimHeight ?? 0
    readonly property bool shouldBeActive: screenState.dashboard && Config.dashboard.enabled

    // Set CAELESTIA_DEBUG_DASH=1 to log toggle -> build -> first frame timings
    readonly property bool debugOpen: Quickshell.env("CAELESTIA_DEBUG_DASH") === "1"
    property real debugToggleAt: 0
    property bool debugAwaitingFrame: false

    readonly property bool contentReady: content.status === Loader.Ready || content.status === Loader.Error
    property real offsetScale: shouldBeActive && contentReady ? 0 : 1

    // The expressive bezier overshoots offsetScale past 0, and this ~1000px
    // slide would retreat the panel past blob.frag's bridge reach
    // (2-sqrt2)*smoothing, tearing the junction band for a frame. Soft-clamp
    // the retreat so the overshoot stays under the reach: C1 at m = t,
    // asymptote 2t = 0.8 * reach.
    function smoothRetreat(m) {
        const t = 0.4 * (2 - Math.SQRT2) * Config.border.smoothing;
        return m <= t ? m : 2 * t - t * t / m;
    }

    visible: offsetScale < 1
    anchors.topMargin: smoothRetreat((-implicitHeight - 5) * offsetScale)
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 854 // Hard coded fallback for first open
    opacity: 1 - offsetScale

    onShouldBeActiveChanged: {
        if (debugOpen) {
            console.log(`[dash-open] ${shouldBeActive ? "toggle open, content " + (content.active ? "held" : "cold") : "close"}`);
            if (shouldBeActive) {
                debugToggleAt = Date.now();
                debugAwaitingFrame = true;
            }
        }
    }

    // Frame probe is inert unless CAELESTIA_DEBUG_DASH=1 logging is enabled
    FrameAnimation {
        running: root.debugOpen && root.debugAwaitingFrame

        onTriggered: {
            if (!root.debugAwaitingFrame)
                return;
            root.debugAwaitingFrame = false;
            console.log(`[dash-open] first frame +${Math.round(Date.now() - root.debugToggleAt)}ms`);
        }
    }

    Behavior on offsetScale {
        Anim {}
    }

    Loader {
        id: content

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom

        active: root.shouldBeActive || root.visible || Config.dashboard.keepAlive

        onLoaded: {
            if (root.debugOpen && root.debugToggleAt > 0)
                console.log(`[dash-open] content built +${Math.round(Date.now() - root.debugToggleAt)}ms`);
        }

        onActiveChanged: {
            if (!active && root.debugOpen)
                console.log("[dash-open] content released");
        }

        sourceComponent: Content {
            screenState: root.screenState
            facePicker: root.facePicker
        }
    }
}
