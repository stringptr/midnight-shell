pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.bar

StyledWindow {
    id: root

    Config.screen: screen.name

    readonly property alias bar: bar
    readonly property alias interactionWrapper: interactions

    readonly property ScreenState screenState: ShellState.forScreen(screen)

    // TODO: Niri has no special workspaces
    readonly property bool hasSpecialWorkspace: false
    readonly property bool hasFullscreenOnNormalWs: {
        const wins = Niri.getActiveWorkspaceWindows();
        return wins ? wins.some(t => t.is_fullscreen) : false;
    }
    readonly property bool hasFullscreen: hasFullscreenOnNormalWs

    property real fsTransitionProg: hasFullscreen ? 1 : 0
    readonly property real sdfBorderOffset: 2 * fsTransitionProg // SDFs joins are not exact, so offset by 2px to ensure nothing shows
    readonly property real borderThickness: contentItem.Config.border.thickness * (1 - fsTransitionProg)
    readonly property real borderRounding: contentItem.Config.border.rounding * (1 - fsTransitionProg)
    readonly property real shadowOpacity: 0.7 * (1 - fsTransitionProg)
    readonly property real borderLayoutThickness: hasFullscreen ? 0 : contentItem.Config.border.thickness

    property color surfaceColour: Colours.tPalette.m3surface

    // Compositor blur behind the shell chrome (niri ext-background-effect).
    // Only active while the shell surface is actually translucent.
    readonly property bool shellBlurActive: GlobalConfig.appearance.blur.enabled
        && !GlobalConfig.appearance.pitchBlack
        && root.surfaceColour.a < 1.0

    // BlobInvertedRect draws the screen frame: its inner edge sits
    // `borderThickness` from each screen edge, or `bar.implicitWidth/Height` on
    // the bar's side. Four strips frost that ring exactly, with no halo.
    readonly property bool blurFrameEnabled: !GlobalConfig.appearance.islands
    readonly property real blurFrameThickness: blurFrameEnabled ? Math.max(0, root.borderThickness - root.sdfBorderOffset) : 0
    readonly property real blurFrameLeft: blurFrameEnabled && Config.bar.position === "left" ? Math.max(0, bar.implicitWidth - root.sdfBorderOffset) : blurFrameThickness
    readonly property real blurFrameRight: blurFrameEnabled && Config.bar.position === "right" ? Math.max(0, bar.implicitWidth - root.sdfBorderOffset) : blurFrameThickness
    readonly property real blurFrameTop: blurFrameEnabled && Config.bar.position === "top" ? Math.max(0, bar.implicitHeight - root.sdfBorderOffset) : blurFrameThickness
    readonly property real blurFrameBottom: blurFrameEnabled && Config.bar.position === "bottom" ? Math.max(0, bar.implicitHeight - root.sdfBorderOffset) : blurFrameThickness

    readonly property int dragMaskPadding: {
        if (focusGrab.active || panels.popouts.isDetached)
            return 0;

        // TODO: Niri has no special workspace or window count check
        const wins = Niri.getActiveWorkspaceWindows();
        if (wins && wins.length > 0)
            return 0;

        const thresholds = [];
        for (const panel of ["dashboard", "launcher", "session", "sidebar"])
            if (contentItem.Config[panel].enabled)
                thresholds.push(contentItem.Config[panel].dragThreshold);
        return Math.max(...thresholds);
    }

    onHasFullscreenChanged: {
        screenState.launcher = false;
        screenState.session = false;
        screenState.dashboard = false;
        panels.popouts.close();
    }

    name: "drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: (fsTransitionProg > 0 && contentItem.Config.general.showOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: screenState.launcher || screenState.session || screenState.dashboard || screenState.sidebar || panels.popouts.hasCurrent ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    mask: hasFullscreen ? emptyRegion : regions

    BackgroundEffect.blurRegion: shellBlurActive ? blurRegionRef : null

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Behavior on fsTransitionProg {
        Anim {}
    }

    Behavior on surfaceColour {
        CAnim {}
    }

    Region {
        id: emptyRegion

        x: panels.notifications.x + panels.leftMargin
        y: panels.notifications.y + panels.topMargin
        width: panels.notifications.width
        height: panels.notifications.height

        Region {
            x: root.width - width
            y: panels.osdWrapper.y + panels.topMargin
            width: panels.osdWrapper.width * (1 - panels.osd.offsetScale) + panels.topMargin
            height: panels.osd.height
        }
    }

    Regions {
        id: regions

        bar: bar
        panels: panels
        win: root
    }

    Region {
        id: blurRegionRef

        // Keep a non-empty offscreen region: Quickshell sends
        // set_blur_region(nullptr) for an empty QRegion, and Niri then falls back
        // to blurring the whole surface geometry, which in xray mode erases every
        // window behind the shell.
        Region {
            x: -100
            y: -100
            width: 1
            height: 1
        }

        // Screen border frame (BlobInvertedRect), four strips. Their union is the
        // ring; only the rounded inner corners are a sub-pixel mismatch.
        Region {
            x: 0
            y: 0
            width: root.width
            height: root.blurFrameTop
        }

        Region {
            x: 0
            y: root.height - root.blurFrameBottom
            width: root.width
            height: root.blurFrameBottom
        }

        Region {
            x: 0
            y: 0
            width: root.blurFrameLeft
            height: root.height
        }

        Region {
            x: root.width - root.blurFrameRight
            y: 0
            width: root.blurFrameRight
            height: root.height
        }

        // Islands mode: the frame is hidden and the bar is a floating blob instead.
        Region {
            x: bar.x
            y: bar.y
            width: GlobalConfig.appearance.islands && bar.visible ? bar.width : 0
            height: GlobalConfig.appearance.islands && bar.visible ? bar.height : 0
            radius: Tokens.rounding.extraLarge
        }

        // One region per PanelBg blob, at the same coordinates as the drawn
        // chrome. Collapsed to zero while the panel is hidden: a boolean gate, so
        // animated geometry never churns out set_blur_region per frame.
        Region {
            x: dashBg.x
            y: dashBg.y
            width: dashBg.visible ? dashBg.width : 0
            height: dashBg.visible ? dashBg.height : 0
            radius: dashBg.radius
        }

        Region {
            x: launcherBg.x
            y: launcherBg.y
            width: launcherBg.visible ? launcherBg.width : 0
            height: launcherBg.visible ? launcherBg.height : 0
            radius: launcherBg.radius
        }

        Region {
            x: sessionBg.x
            y: sessionBg.y
            width: sessionBg.visible ? sessionBg.width : 0
            height: sessionBg.visible ? sessionBg.height : 0
            radius: sessionBg.radius
        }

        Region {
            x: sidebarBg.x
            y: sidebarBg.y
            width: sidebarBg.visible ? sidebarBg.width : 0
            height: sidebarBg.visible ? sidebarBg.height : 0
            radius: sidebarBg.radius
        }

        Region {
            x: osdBg.x
            y: osdBg.y
            width: osdBg.visible ? osdBg.width : 0
            height: osdBg.visible ? osdBg.height : 0
            radius: osdBg.radius
        }

        Region {
            x: workspaceOverviewBg.x
            y: workspaceOverviewBg.y
            width: workspaceOverviewBg.visible ? workspaceOverviewBg.width : 0
            height: workspaceOverviewBg.visible ? workspaceOverviewBg.height : 0
            radius: workspaceOverviewBg.radius
        }

        Region {
            x: notifsBg.x
            y: notifsBg.y
            width: notifsBg.visible ? notifsBg.width : 0
            height: notifsBg.visible ? notifsBg.height : 0
            radius: notifsBg.radius
        }

        Region {
            x: utilsBg.x
            y: utilsBg.y
            width: utilsBg.visible ? utilsBg.width : 0
            height: utilsBg.visible ? utilsBg.height : 0
            radius: utilsBg.radius
        }

        Region {
            x: popoutBg.x
            y: popoutBg.y
            width: popoutBg.visible ? popoutBg.width : 0
            height: popoutBg.visible ? popoutBg.height : 0
            radius: popoutBg.radius
        }
    }

    // TODO: Niri has no HyprlandFocusGrab equivalent; using plain Item
    Item {
        id: focusGrab

        property bool active: {
            const s = root.screenState;
            const conf = root.contentItem.Config;
            if (s.workspaceDrawer) return true;
            if ((s.launcher && conf.launcher.enabled) || (s.session && conf.session.enabled) || (s.sidebar && conf.sidebar.enabled))
                return true;
            if (!conf.dashboard.showOnHover && s.dashboard && conf.dashboard.enabled)
                return true;
            if (panels.popouts.currentName.startsWith("traymenu") && (panels.popouts.current as StackView)?.depth > 1)
                return true;
            return false;
        }
        onActiveChanged: {
            if (!active) {
                root.screenState.workspaceDrawer = false;
                root.screenState.launcher = false;
                root.screenState.session = false;
                root.screenState.sidebar = false;
                root.screenState.dashboard = false;
                panels.popouts.hasCurrent = false;
                bar.closeTray();
            }
        }
    }

    StyledRect {
        anchors.fill: parent
        opacity: (root.screenState.session && Config.session.enabled) || panels.popouts.detachedMode !== "" ? 0.5 : 0
        color: Colours.palette.m3scrim

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Item {
        id: layoutContainer

        Config.screen: root.screen.name
        anchors.fill: parent
        opacity: GlobalConfig.appearance.pitchBlack ? 1 : (Colours.transparency.enabled ? Colours.transparency.base : root.surfaceColour.a)
        layer.enabled: GlobalConfig.appearance.shadow.enabled
        layer.effect: MultiEffect {
            shadowEnabled: GlobalConfig.appearance.shadow.enabled
            blurMax: GlobalConfig.appearance.shadow.blurMax
            shadowColor: Qt.alpha(Colours.palette.m3shadow, Math.max(0, root.shadowOpacity))
        }

        BlobGroup {
            id: blobGroup

            color: GlobalConfig.appearance.pitchBlack ? "#000000" : root.surfaceColour
            smoothing: root.contentItem.Config.border.smoothing
        }

        BlobInvertedRect {
            Config.screen: root.screen.name
            anchors.fill: parent
            anchors.margins: -50 // Make border thicker to smooth out bulge from closed drawers
            group: GlobalConfig.appearance.islands ? null : blobGroup
            visible: !GlobalConfig.appearance.islands
            radius: root.borderRounding
            borderLeft: (Config.bar.position === "left" ? bar.implicitWidth : root.borderThickness) - anchors.margins - root.sdfBorderOffset
            borderRight: (Config.bar.position === "right" ? bar.implicitWidth : root.borderThickness) - anchors.margins - root.sdfBorderOffset
            borderTop: (Config.bar.position === "top" ? bar.implicitHeight : root.borderThickness) - anchors.margins - root.sdfBorderOffset
            borderBottom: (Config.bar.position === "bottom" ? bar.implicitHeight : root.borderThickness) - anchors.margins - root.sdfBorderOffset
        }

        BlobRect {
            visible: GlobalConfig.appearance.islands
            group: GlobalConfig.appearance.islands ? blobGroup : null
            x: bar.x
            y: bar.y
            implicitWidth: bar.width
            implicitHeight: bar.height
            radius: Tokens.rounding.extraLarge
            deformScale: (0.1 * Config.appearance.deformScale) / 10000
        }

        PanelBg {
            id: dashBg

            panel: panels.dashboard
            deformAmount: 0.1
        }

        PanelBg {
            id: launcherBg

            panel: panels.launcher
            deformAmount: 0.1
        }

        PanelBg {
            id: sessionBg

            panel: panels.sessionWrapper
            deformAmount: 0.2
            x: panels.sessionWrapper.x + panels.leftMargin
            implicitWidth: panels.sessionWrapper.width
        }

        PanelBg {
            id: sidebarBg

            panel: panels.sidebar
            deformAmount: 0.03
            implicitHeight: panel.height * (1 / rawDeformMatrix.m22) + 2
            
            property bool connectedToPopout: (Config.bar.position === "top" || Config.bar.position === "bottom") && panels.popouts.sidebarOpen && panels.popouts.currentSection === "end" && panels.popouts.implicitWidth <= Tokens.sizes.sidebar.width + 1 && !panels.popouts.isDockPopout
            
            exclude: {
                let arr = [];
                if (panels.sidebar.offsetScale <= 0.08) arr.push(utilsBg);
                if (connectedToPopout) arr.push(popoutBg);
                return arr;
            }
            
            topLeftRadius: GlobalConfig.appearance.islands ? radius : ((Config.bar.position === "top" && connectedToPopout) ? 0 : (Config.bar.position === "bottom" ? Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius : radius))
            topRightRadius: GlobalConfig.appearance.islands ? radius : ((Config.bar.position === "top" && connectedToPopout) ? 0 : (Config.bar.position === "bottom" ? Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius : radius))
            bottomLeftRadius: GlobalConfig.appearance.islands ? radius : ((Config.bar.position === "bottom" && connectedToPopout) ? 0 : (Config.bar.position === "right" ? radius : Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius))
            bottomRightRadius: GlobalConfig.appearance.islands ? radius : ((Config.bar.position === "bottom" && connectedToPopout) ? 0 : (Config.bar.position === "right" ? Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius : radius))
        }

        PanelBg {
            id: osdBg

            panel: panels.osdWrapper
            deformAmount: 0.25
            x: panels.osdWrapper.x + panels.leftMargin
            implicitWidth: panels.osdWrapper.width
        }

        PanelBg {
            id: workspaceOverviewBg
            
            panel: panels.workspaceOverview
            deformAmount: 0.03
            
            exclude: []
            
            property bool isAnchoredRight: Config.bar.position === "right"
            topRightRadius: GlobalConfig.appearance.islands ? radius : (!isAnchoredRight ? radius : Math.max(0, Math.min(1, panels.workspaceOverview.offsetScale / 0.3)) * radius)
            bottomRightRadius: GlobalConfig.appearance.islands ? radius : (!isAnchoredRight ? radius : Math.max(0, Math.min(1, panels.workspaceOverview.offsetScale / 0.3)) * radius)
            topLeftRadius: GlobalConfig.appearance.islands ? radius : (isAnchoredRight ? radius : Math.max(0, Math.min(1, panels.workspaceOverview.offsetScale / 0.3)) * radius)
            bottomLeftRadius: GlobalConfig.appearance.islands ? radius : (isAnchoredRight ? radius : Math.max(0, Math.min(1, panels.workspaceOverview.offsetScale / 0.3)) * radius)
        }

        PanelBg {
            id: notifsBg

            panel: panels.notifications
        }

        PanelBg {
            id: utilsBg

            panel: panels.utilities
            deformAmount: panels.sidebar.visible ? 0.1 : 0.15
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [sidebarBg]
            topLeftRadius: GlobalConfig.appearance.islands ? radius : (Config.bar.position === "right" ? radius : (Config.bar.position === "bottom" ? radius : Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius))
            topRightRadius: GlobalConfig.appearance.islands ? radius : (Config.bar.position === "right" ? Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius : (Config.bar.position === "bottom" ? radius : Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius))
            bottomLeftRadius: GlobalConfig.appearance.islands ? radius : (Config.bar.position === "bottom" ? Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius : radius)
            bottomRightRadius: GlobalConfig.appearance.islands ? radius : (Config.bar.position === "bottom" ? Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius : radius)
        }

        PanelBg {
            id: popoutBg

            // Extra width/height to prevent dynamic movement deformation partially detaching panel from bar
            property real extraShift: panels.popouts.isDetached ? 0 : 0.2
            property bool connectedToSidebar: (bar.position === "top" || bar.position === "bottom") && panels.popouts.sidebarOpen && panels.popouts.currentSection === "end" && panels.popouts.implicitWidth <= Tokens.sizes.sidebar.width + 1 && !panels.popouts.isDockPopout

            panel: panels.popoutsWrapper
            deformAmount: connectedToSidebar ? 0.03 : (panels.popouts.isDetached ? 0.05 : panels.popouts.hasCurrent ? 0.15 : 0.1)
            exclude: connectedToSidebar ? [sidebarBg] : []
            
            x: {
                const baseX = panels.popoutsWrapper.x + panels.popouts.x + panels.leftMargin;
                if (bar.position === "left")
                    return baseX - panels.popouts.implicitWidth * extraShift;
                return baseX;
            }
            implicitWidth: {
                if (bar.position === "left" || bar.position === "right")
                    return panels.popouts.implicitWidth * (1 + extraShift);
                return panels.popouts.implicitWidth;
            }
            
            bottomLeftRadius: GlobalConfig.appearance.islands ? radius : ((bar.position === "top" && connectedToSidebar) ? 0 : radius)
            bottomRightRadius: GlobalConfig.appearance.islands ? radius : ((bar.position === "top" && connectedToSidebar) ? 0 : radius)
            topLeftRadius: GlobalConfig.appearance.islands ? radius : ((bar.position === "bottom" && connectedToSidebar) ? 0 : radius)
            topRightRadius: GlobalConfig.appearance.islands ? radius : ((bar.position === "bottom" && connectedToSidebar) ? 0 : radius)

            y: {
                const baseY = panels.popoutsWrapper.y + panels.popouts.y + panels.topMargin;
                if (bar.position === "top")
                    return baseY - panels.popouts.implicitHeight * extraShift;
                if (bar.position === "bottom" && connectedToSidebar)
                    return baseY - Tokens.spacing.medium - 10;
                return baseY;
            }
            implicitHeight: {
                if (bar.position === "top" || bar.position === "bottom") {
                    let h = panels.popouts.implicitHeight * (1 + extraShift);
                    if (connectedToSidebar) h += Tokens.spacing.medium + 10;
                    return h;
                }
                return panels.popouts.implicitHeight;
            }

            Behavior on extraShift {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
        }
    }

    Interactions {
        id: interactions

        screen: root.screen
        popouts: panels.popouts
        screenState: root.screenState
        panels: panels
        bar: bar
        borderThickness: root.borderLayoutThickness
        fullscreen: root.hasFullscreen

        states: [
            State {
                name: "left"
                Config.screen: root.screen.name
                when: Config.bar.position === "left"

                AnchorChanges {
                    target: bar
                    anchors.left: parent.left
                    anchors.right: undefined
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                }
                PropertyChanges {
                    target: bar
                    width: bar.implicitWidth
                    height: undefined
                    anchors.topMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.bottomMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.leftMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.rightMargin: 0
                }
            },

            State {
                name: "right"
                Config.screen: root.screen.name
                when: Config.bar.position === "right"

                AnchorChanges {
                    target: bar
                    anchors.left: undefined
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                }
                PropertyChanges {
                    target: bar
                    width: bar.implicitWidth
                    height: undefined
                    anchors.topMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.bottomMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.leftMargin: 0
                    anchors.rightMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                }
            },

            State {
                name: "top"
                Config.screen: root.screen.name
                when: Config.bar.position === "top"

                AnchorChanges {
                    target: bar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: undefined
                }
                PropertyChanges {
                    target: bar
                    width: undefined
                    height: bar.implicitHeight
                    anchors.leftMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.rightMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.topMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.bottomMargin: 0
                }
            },

            State {
                name: "bottom"
                Config.screen: root.screen.name
                when: Config.bar.position === "bottom"

                AnchorChanges {
                    target: bar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: undefined
                    anchors.bottom: parent.bottom
                }
                PropertyChanges {
                    target: bar
                    width: undefined
                    height: bar.implicitHeight
                    anchors.leftMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.rightMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.bottomMargin: GlobalConfig.appearance.islands ? Tokens.spacing.extraLarge : 0
                    anchors.topMargin: 0
                }
            }
        ]

        Panels {
            id: panels

            screen: root.screen
            screenState: root.screenState
            bar: bar
            borderThickness: root.borderThickness

            utilities.horizontalStretch: (sidebarBg.rawDeformMatrix.m11 - 1) / 2 + 1
            utilities.deformMatrix: utilsBg.rawDeformMatrix

            dashboard.transform: Matrix4x4 {
                matrix: dashBg.deformMatrix
            }
            launcher.transform: Matrix4x4 {
                matrix: launcherBg.deformMatrix
            }
            session.transform: Matrix4x4 {
                matrix: sessionBg.deformMatrix
            }
            sidebar.transform: Matrix4x4 {
                matrix: sidebarBg.deformMatrix
            }
            osd.transform: Matrix4x4 {
                matrix: osdBg.deformMatrix
            }
            notifications.transform: Matrix4x4 {
                matrix: notifsBg.deformMatrix
            }
            workspaceOverview.transform: Matrix4x4 {
                matrix: workspaceOverviewBg.deformMatrix
            }
            utilities.transform: Matrix4x4 {
                matrix: utilsBg.deformMatrix
            }
            popouts.transform: Matrix4x4 {
                matrix: popoutBg.deformMatrix
            }
        }

        BarWrapper {
            id: bar

            screen: root.screen
            screenState: root.screenState
            popouts: panels.popouts

            fullscreen: root.hasFullscreen
        }
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "rootWindow"
        component: root
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "interactionWrapper"
        component: interactions
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "bar"
        component: bar
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "panels"
        component: panels
    }

    component PanelBg: BlobRect {
        required property Item panel
        property real deformAmount: 0.15
        Config.screen: root.screen.name

        visible: panel.visible
        group: panel.visible ? blobGroup : null
        x: panel.x + panels.leftMargin
        y: panel.y + panels.topMargin
        implicitWidth: panel.width
        implicitHeight: panel.height
        radius: Tokens.rounding.extraLarge
        deformScale: (deformAmount * Config.appearance.deformScale) / 10000
    }
}
