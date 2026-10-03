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
    // the bar's side. Four strips frost the straight ring; the rounded inner
    // corners and the smin junction fillets get their own patches below.
    readonly property bool blurFrameEnabled: !GlobalConfig.appearance.islands
    readonly property real blurFrameThickness: blurFrameEnabled ? Math.max(0, root.borderThickness - root.sdfBorderOffset) : 0
    readonly property real blurFrameLeft: blurFrameEnabled && Config.bar.position === "left" ? Math.max(0, bar.implicitWidth - root.sdfBorderOffset) : blurFrameThickness
    readonly property real blurFrameRight: blurFrameEnabled && Config.bar.position === "right" ? Math.max(0, bar.implicitWidth - root.sdfBorderOffset) : blurFrameThickness
    readonly property real blurFrameTop: blurFrameEnabled && Config.bar.position === "top" ? Math.max(0, bar.implicitHeight - root.sdfBorderOffset) : blurFrameThickness
    readonly property real blurFrameBottom: blurFrameEnabled && Config.bar.position === "bottom" ? Math.max(0, bar.implicitHeight - root.sdfBorderOffset) : blurFrameThickness
    // How far off the frame inner edge a panel edge can drift while blob.frag's
    // smin still bridges the gap with chrome: (2 - sqrt2) * smoothing.
    readonly property real blurBridgeReach: (2 - Math.SQRT2) * root.Config.border.smoothing
    // blob.frag's border-sink onset (preOff): past this penetration the inner
    // wall recedes, so junction patches must not anchor on it (keeps popouts,
    // which sit inside the border, inert as tested).
    readonly property real blurSinkMargin: root.Config.border.smoothing * (2 - Math.SQRT2) * 0.5

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

    // Mirrors BlobShape::accumulateInvertedFill (blobshape.cpp): how much of a
    // blob's corner radius survives the frame's inner edge. A corner flush with
    // the edge gets factor 0 (the drawn chrome squares it off to k_minR = 2),
    // a corner `smoothing` away keeps its full radius; islands mode has no
    // frame, so the factor is 1.
    function frameFillFactor(x, y) {
        if (!blurFrameEnabled)
            return 1;
        const k = root.Config.border.smoothing;
        const d = Math.min(x - blurFrameLeft, (width - blurFrameRight) - x, y - blurFrameTop, (height - blurFrameBottom) - y);
        const t = Math.max(0, Math.min(1, d / k));
        return t * t * (3 - 2 * t);
    }

    // Mirrors BlobRect::cornerRadii plus applyCornerFill's inverted fill: the
    // blur region must round where the drawn chrome rounds, otherwise the
    // squared-off corner lens stays unblurred. Rounding may drop below the
    // drawn k_minR = 2 — those sub-pixel lens pixels are always smin-filled by
    // the adjacent frame, so covering them keeps the region inside the chrome.
    function blurCornerRadius(bg, cx, cy, explicitRadius) {
        const maxR = Math.min(bg.width, bg.height) / 2;
        const base = Math.min(explicitRadius >= 0 ? explicitRadius : bg.radius, maxR);
        return Math.round(base * frameFillFactor(cx, cy));
    }

    // The drawn fillet reaches past a panel edge that stops short of the wall:
    // where the edge's perpendicular extent `ext` shrinks below smoothing, the
    // circular smin's corner case still fills rows out to
    //   eps(ext) = k + (ext - sqrt(max(2k^2 - ext^2, 0))) / 2,
    // clamped to [0, k] (eps(0) = preOff, eps(k) = k). Junction patches must
    // collapse with that depth instead of min(k, ext), which shortens ahead of
    // the chrome and leaves the drawn bulge uncovered in the tail.
    function blurJunctionExtent(ext) {
        const k = root.Config.border.smoothing;
        if (ext >= k)
            return k;
        if (ext <= -k)
            return 0;
        return Math.max(0, Math.min(k, k + (ext - Math.sqrt(Math.max(2 * k * k - ext * ext, 0))) / 2));
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

        // Screen border frame (BlobInvertedRect): four strips frost the straight
        // ring, four wedges frost the rounded inner corners (corner square minus
        // the hole's corner disc) — together they match the drawn frame exactly.
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

        FrameWedge {
            cx: root.blurFrameLeft
            cy: root.blurFrameTop
            dx: 1
            dy: 1
        }

        FrameWedge {
            cx: root.width - root.blurFrameRight
            cy: root.blurFrameTop
            dx: -1
            dy: 1
        }

        FrameWedge {
            cx: root.blurFrameLeft
            cy: root.height - root.blurFrameBottom
            dx: 1
            dy: -1
        }

        FrameWedge {
            cx: root.width - root.blurFrameRight
            cy: root.height - root.blurFrameBottom
            dx: -1
            dy: -1
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
        // chrome, with the drawn per-corner radii (flush corners square off via
        // frameFillFactor). Collapsed to zero while the panel is hidden:
        // a boolean gate, so animated geometry never churns out set_blur_region
        // per frame.
        Region {
            x: dashBg.x
            y: dashBg.y
            width: dashBg.visible ? dashBg.width : 0
            height: dashBg.visible ? dashBg.height : 0
            topLeftRadius: root.blurCornerRadius(dashBg, dashBg.x, dashBg.y, dashBg.topLeftRadius)
            topRightRadius: root.blurCornerRadius(dashBg, dashBg.x + dashBg.width, dashBg.y, dashBg.topRightRadius)
            bottomLeftRadius: root.blurCornerRadius(dashBg, dashBg.x, dashBg.y + dashBg.height, dashBg.bottomLeftRadius)
            bottomRightRadius: root.blurCornerRadius(dashBg, dashBg.x + dashBg.width, dashBg.y + dashBg.height, dashBg.bottomRightRadius)
        }

        Region {
            x: launcherBg.x
            y: launcherBg.y
            width: launcherBg.visible ? launcherBg.width : 0
            height: launcherBg.visible ? launcherBg.height : 0
            topLeftRadius: root.blurCornerRadius(launcherBg, launcherBg.x, launcherBg.y, launcherBg.topLeftRadius)
            topRightRadius: root.blurCornerRadius(launcherBg, launcherBg.x + launcherBg.width, launcherBg.y, launcherBg.topRightRadius)
            bottomLeftRadius: root.blurCornerRadius(launcherBg, launcherBg.x, launcherBg.y + launcherBg.height, launcherBg.bottomLeftRadius)
            bottomRightRadius: root.blurCornerRadius(launcherBg, launcherBg.x + launcherBg.width, launcherBg.y + launcherBg.height, launcherBg.bottomRightRadius)
        }

        Region {
            x: sessionBg.x
            y: sessionBg.y
            width: sessionBg.visible ? sessionBg.width : 0
            height: sessionBg.visible ? sessionBg.height : 0
            topLeftRadius: root.blurCornerRadius(sessionBg, sessionBg.x, sessionBg.y, sessionBg.topLeftRadius)
            topRightRadius: root.blurCornerRadius(sessionBg, sessionBg.x + sessionBg.width, sessionBg.y, sessionBg.topRightRadius)
            bottomLeftRadius: root.blurCornerRadius(sessionBg, sessionBg.x, sessionBg.y + sessionBg.height, sessionBg.bottomLeftRadius)
            bottomRightRadius: root.blurCornerRadius(sessionBg, sessionBg.x + sessionBg.width, sessionBg.y + sessionBg.height, sessionBg.bottomRightRadius)
        }

        Region {
            x: sidebarBg.x
            y: sidebarBg.y
            width: sidebarBg.visible ? sidebarBg.width : 0
            height: sidebarBg.visible ? sidebarBg.height : 0
            topLeftRadius: root.blurCornerRadius(sidebarBg, sidebarBg.x, sidebarBg.y, sidebarBg.topLeftRadius)
            topRightRadius: root.blurCornerRadius(sidebarBg, sidebarBg.x + sidebarBg.width, sidebarBg.y, sidebarBg.topRightRadius)
            bottomLeftRadius: root.blurCornerRadius(sidebarBg, sidebarBg.x, sidebarBg.y + sidebarBg.height, sidebarBg.bottomLeftRadius)
            bottomRightRadius: root.blurCornerRadius(sidebarBg, sidebarBg.x + sidebarBg.width, sidebarBg.y + sidebarBg.height, sidebarBg.bottomRightRadius)
        }

        Region {
            x: osdBg.x
            y: osdBg.y
            width: osdBg.visible ? osdBg.width : 0
            height: osdBg.visible ? osdBg.height : 0
            topLeftRadius: root.blurCornerRadius(osdBg, osdBg.x, osdBg.y, osdBg.topLeftRadius)
            topRightRadius: root.blurCornerRadius(osdBg, osdBg.x + osdBg.width, osdBg.y, osdBg.topRightRadius)
            bottomLeftRadius: root.blurCornerRadius(osdBg, osdBg.x, osdBg.y + osdBg.height, osdBg.bottomLeftRadius)
            bottomRightRadius: root.blurCornerRadius(osdBg, osdBg.x + osdBg.width, osdBg.y + osdBg.height, osdBg.bottomRightRadius)
        }

        Region {
            x: workspaceOverviewBg.x
            y: workspaceOverviewBg.y
            width: workspaceOverviewBg.visible ? workspaceOverviewBg.width : 0
            height: workspaceOverviewBg.visible ? workspaceOverviewBg.height : 0
            topLeftRadius: root.blurCornerRadius(workspaceOverviewBg, workspaceOverviewBg.x, workspaceOverviewBg.y, workspaceOverviewBg.topLeftRadius)
            topRightRadius: root.blurCornerRadius(workspaceOverviewBg, workspaceOverviewBg.x + workspaceOverviewBg.width, workspaceOverviewBg.y, workspaceOverviewBg.topRightRadius)
            bottomLeftRadius: root.blurCornerRadius(workspaceOverviewBg, workspaceOverviewBg.x, workspaceOverviewBg.y + workspaceOverviewBg.height, workspaceOverviewBg.bottomLeftRadius)
            bottomRightRadius: root.blurCornerRadius(workspaceOverviewBg, workspaceOverviewBg.x + workspaceOverviewBg.width, workspaceOverviewBg.y + workspaceOverviewBg.height, workspaceOverviewBg.bottomRightRadius)
        }

        Region {
            x: notifsBg.x
            y: notifsBg.y
            width: notifsBg.visible ? notifsBg.width : 0
            height: notifsBg.visible ? notifsBg.height : 0
            topLeftRadius: root.blurCornerRadius(notifsBg, notifsBg.x, notifsBg.y, notifsBg.topLeftRadius)
            topRightRadius: root.blurCornerRadius(notifsBg, notifsBg.x + notifsBg.width, notifsBg.y, notifsBg.topRightRadius)
            bottomLeftRadius: root.blurCornerRadius(notifsBg, notifsBg.x, notifsBg.y + notifsBg.height, notifsBg.bottomLeftRadius)
            bottomRightRadius: root.blurCornerRadius(notifsBg, notifsBg.x + notifsBg.width, notifsBg.y + notifsBg.height, notifsBg.bottomRightRadius)
        }

        Region {
            x: utilsBg.x
            y: utilsBg.y
            width: utilsBg.visible ? utilsBg.width : 0
            height: utilsBg.visible ? utilsBg.height : 0
            topLeftRadius: root.blurCornerRadius(utilsBg, utilsBg.x, utilsBg.y, utilsBg.topLeftRadius)
            topRightRadius: root.blurCornerRadius(utilsBg, utilsBg.x + utilsBg.width, utilsBg.y, utilsBg.topRightRadius)
            bottomLeftRadius: root.blurCornerRadius(utilsBg, utilsBg.x, utilsBg.y + utilsBg.height, utilsBg.bottomLeftRadius)
            bottomRightRadius: root.blurCornerRadius(utilsBg, utilsBg.x + utilsBg.width, utilsBg.y + utilsBg.height, utilsBg.bottomRightRadius)
        }

        Region {
            x: popoutBg.x
            y: popoutBg.y
            width: popoutBg.visible ? popoutBg.width : 0
            height: popoutBg.visible ? popoutBg.height : 0
            topLeftRadius: root.blurCornerRadius(popoutBg, popoutBg.x, popoutBg.y, popoutBg.topLeftRadius)
            topRightRadius: root.blurCornerRadius(popoutBg, popoutBg.x + popoutBg.width, popoutBg.y, popoutBg.topRightRadius)
            bottomLeftRadius: root.blurCornerRadius(popoutBg, popoutBg.x, popoutBg.y + popoutBg.height, popoutBg.bottomLeftRadius)
            bottomRightRadius: root.blurCornerRadius(popoutBg, popoutBg.x + popoutBg.width, popoutBg.y + popoutBg.height, popoutBg.bottomRightRadius)
        }

        // Cove fillets where panel corners sit on the frame's inner edge (the
        // circular smin in blob.frag fills the empty quadrant beside them).
        // Stays active through the animation overshoot, up to bridge reach.
        PanelCoves {
            bg: dashBg
        }

        PanelCoves {
            bg: launcherBg
        }

        PanelCoves {
            bg: sessionBg
        }

        PanelCoves {
            bg: sidebarBg
        }

        PanelCoves {
            bg: osdBg
        }

        PanelCoves {
            bg: workspaceOverviewBg
        }

        PanelCoves {
            bg: notifsBg
        }

        PanelCoves {
            bg: utilsBg
        }

        PanelCoves {
            bg: popoutBg
        }

        // Transient bridge strips: while the panel animation overshoots and a
        // panel edge drifts off the frame inner edge by 0 < gap < smoothing,
        // the shader still fills the gap (one full band up to bridge reach, two
        // fillet bands beyond it). Full band minus a carved middle, which
        // degenerates to nothing below reach.
        PanelBridges {
            bg: dashBg
        }

        PanelBridges {
            bg: launcherBg
        }

        PanelBridges {
            bg: sessionBg
        }

        PanelBridges {
            bg: sidebarBg
        }

        PanelBridges {
            bg: osdBg
        }

        PanelBridges {
            bg: workspaceOverviewBg
        }

        PanelBridges {
            bg: notifsBg
        }

        PanelBridges {
            bg: utilsBg
        }

        PanelBridges {
            bg: popoutBg
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

    component FrameWedge: Region {
        // Covers one rounded inner corner of the frame's hole: the corner square
        // (side borderRounding) minus the hole's corner disc of the same radius,
        // centred on the square's interior far corner. Matches the drawn arc
        // pixel for pixel; the strips already cover everything outside the square.
        property real cx
        property real cy
        property real dx
        property real dy
        readonly property int r: Math.round(root.borderRounding)
        readonly property bool active: root.blurFrameEnabled && r > 0

        x: dx > 0 ? cx : cx - r
        y: dy > 0 ? cy : cy - r
        width: active ? r : 0
        height: active ? r : 0

        Region {
            shape: RegionShape.Ellipse
            x: dx > 0 ? cx : cx - 2 * r
            y: dy > 0 ? cy : cy - 2 * r
            width: active ? 2 * r : 0
            height: active ? 2 * r : 0
            intersection: Intersection.Subtract
        }
    }

    component FrameCove: Region {
        // The circular-smin cove blob.frag draws where a panel meets the frame's
        // inner edge: quarter-square minus quarter-disc of side `smoothing` in
        // the empty quadrant at the junction corner. Exact by construction —
        // material iff (k-a)^2+(k-b)^2 > k^2 within [0,k]^2. The junction axis
        // is anchored at the frame edge (not the panel corner) so the patch
        // tracks the shader's fillet while the panel drifts during overshoot.
        // The square is clipped to the panel's extent across the junction: a
        // shrinking panel collapses its cove with the geometry instead of
        // popping a full k x k when `visible` flips, and a translating panel's
        // cove stays up while its edge still crosses the wall. Once blob.frag's
        // opposite-edge sink (preOff) recedes the wall the anchor sits on, the
        // patch mutes with it.
        required property Item panel
        property real cx
        property real cy
        property int hx
        property int hy
        property bool active
        readonly property int k: Math.round(root.Config.border.smoothing)
        // A wall counts as a junction for this corner only when the corner sits
        // within reach of it AND either the corner is past the wall (gap <= 0)
        // or the panel does not extend across the whole gap toward it. A panel
        // that spans the wall (e.g. a nearly-exited utility panel whose bottom
        // edge crosses the bottom wall) fills the gap with its own body — no
        // fillet is drawn there, so the patch must not anchor or count it.
        readonly property bool onTop: gapOn(cy - root.blurFrameTop, panel.y <= root.blurFrameTop)
        readonly property bool onBottom: gapOn((root.height - root.blurFrameBottom) - cy, panel.y + panel.height >= root.height - root.blurFrameBottom)
        readonly property bool onLeft: gapOn(cx - root.blurFrameLeft, panel.x <= root.blurFrameLeft)
        readonly property bool onRight: gapOn((root.width - root.blurFrameRight) - cx, panel.x + panel.width >= root.width - root.blurFrameRight)
        // The clipped side keeps the square anchored at the wall it grows out
        // of, so the patch extends wall-outward exactly like the drawn fillet
        // (anchoring at the far k-edge instead would grow inward from mid-hole
        // — the patch slides toward the wall, backwards against the chrome).
        readonly property real sqX: onLeft ? root.blurFrameLeft : (onRight ? (root.width - root.blurFrameRight) - clipW : (hx > 0 ? cx : cx - k))
        readonly property real sqY: onTop ? root.blurFrameTop : (onBottom ? (root.height - root.blurFrameBottom) - clipH : (hy > 0 ? cy : cy - k))
        // blob.frag sinks a wall once the rect's opposite edge passes it by
        // preOff (blurSinkMargin); the anchor on that wall is gone then.
        readonly property bool sunk: (onTop && panel.y + panel.height < root.blurFrameTop - root.blurSinkMargin)
            || (onBottom && panel.y > (root.height - root.blurFrameBottom) + root.blurSinkMargin)
            || (onLeft && panel.x + panel.width < root.blurFrameLeft - root.blurSinkMargin)
            || (onRight && panel.x > (root.width - root.blurFrameRight) + root.blurSinkMargin)
        // Perpendicular extent of the panel at the junction: the square's side
        // across the wall tracks how far the panel still reaches — as the
        // shader's smin corner-case fill does, so the patch collapses with the
        // chrome instead of shortening ahead of it (see blurJunctionExtent);
        // the along-edge side stays k.
        readonly property real clipW: onLeft ? root.blurJunctionExtent(panel.x + panel.width - root.blurFrameLeft) : (onRight ? root.blurJunctionExtent((root.width - root.blurFrameRight) - panel.x) : k)
        readonly property real clipH: onTop ? root.blurJunctionExtent(panel.y + panel.height - root.blurFrameTop) : (onBottom ? root.blurJunctionExtent((root.height - root.blurFrameBottom) - panel.y) : k)
        readonly property bool live: active && !sunk

        function gapOn(gap, span) {
            return gap <= root.blurBridgeReach && (gap <= 0 || !span);
        }

        x: sqX
        y: sqY
        width: live ? clipW : 0
        height: live ? clipH : 0

        Region {
            shape: RegionShape.Ellipse
            x: hx > 0 ? sqX : sqX - k
            y: hy > 0 ? sqY : sqY - k
            width: live ? 2 * k : 0
            height: live ? 2 * k : 0
            intersection: Intersection.Subtract
        }
    }

    component PanelCoves: Region {
        // Up to four FrameCoves for one panel's corners: one fires per corner
        // that sits on exactly one frame inner edge (corners on two edges lie
        // under the strips/wedge already, corners on none have no cove). The
        // quadrant points out of the panel and into the hole. Side proximity
        // has no lower bound here — deep penetration is handled per-cove by
        // FrameCove's sink mute and perpendicular-extent clip. An edge within
        // reach does not count when the panel body itself spans the whole gap
        // toward that wall: no fillet is drawn there, and counting it would
        // flip n to 1 (or 2) at the wrong corner — a nearly-exited utility
        // panel would lose its live cove while its drawn fillet persists.
        required property Item bg

        function edgeOn(gap, span) {
            return gap <= root.blurBridgeReach && (gap <= 0 || !span);
        }

        function coveActive(cx, cy) {
            if (!root.blurFrameEnabled || !bg.visible)
                return false;
            const n = (edgeOn(cy - root.blurFrameTop, bg.y <= root.blurFrameTop) ? 1 : 0) + (edgeOn((root.height - root.blurFrameBottom) - cy, bg.y + bg.height >= root.height - root.blurFrameBottom) ? 1 : 0) + (edgeOn(cx - root.blurFrameLeft, bg.x <= root.blurFrameLeft) ? 1 : 0) + (edgeOn((root.width - root.blurFrameRight) - cx, bg.x + bg.width >= root.width - root.blurFrameRight) ? 1 : 0);
            return n === 1;
        }

        function coveHx(cx, isLeft) {
            if (edgeOn(cx - root.blurFrameLeft, bg.x <= root.blurFrameLeft))
                return 1;
            if (edgeOn((root.width - root.blurFrameRight) - cx, bg.x + bg.width >= root.width - root.blurFrameRight))
                return -1;
            return isLeft ? -1 : 1;
        }

        function coveHy(cy, isTop) {
            if (edgeOn(cy - root.blurFrameTop, bg.y <= root.blurFrameTop))
                return 1;
            if (edgeOn((root.height - root.blurFrameBottom) - cy, bg.y + bg.height >= root.height - root.blurFrameBottom))
                return -1;
            return isTop ? -1 : 1;
        }

        FrameCove {
            panel: bg
            cx: bg.x
            cy: bg.y
            hx: coveHx(cx, true)
            hy: coveHy(cy, true)
            active: coveActive(cx, cy)
        }

        FrameCove {
            panel: bg
            cx: bg.x + bg.width
            cy: bg.y
            hx: coveHx(cx, false)
            hy: coveHy(cy, true)
            active: coveActive(cx, cy)
        }

        FrameCove {
            panel: bg
            cx: bg.x
            cy: bg.y + bg.height
            hx: coveHx(cx, true)
            hy: coveHy(cy, false)
            active: coveActive(cx, cy)
        }

        FrameCove {
            panel: bg
            cx: bg.x + bg.width
            cy: bg.y + bg.height
            hx: coveHx(cx, false)
            hy: coveHy(cy, false)
            active: coveActive(cx, cy)
        }
    }

    component PanelBridges: Region {
        // Transient bridge strips on the four frame-adjacent sides. blob.frag's
        // smin keeps filling the gap between a drifting panel edge and the
        // frame inner edge up to (2-sqrt2)*smoothing (one full band), and as
        // two fillet bands of depth d up to smoothing beyond that, with
        //   d = (g - sqrt(max(g^2 - 2(k-g)^2, 0))) / 2.
        // The strip is the full band minus a carved-out middle: below reach the
        // middle degenerates to height 0, above it only the fillets remain.
        // Band corners at the panel end reuse the drawn per-corner radii so the
        // strip lines up with the panel region; frame-end corners are square.
        required property Item bg

        readonly property int k: Math.round(root.Config.border.smoothing)
        readonly property real gapTop: bg.y - root.blurFrameTop
        readonly property real gapBottom: (root.height - root.blurFrameBottom) - (bg.y + bg.height)
        readonly property real gapLeft: bg.x - root.blurFrameLeft
        readonly property real gapRight: (root.width - root.blurFrameRight) - (bg.x + bg.width)

        function bandOn(gap) {
            return root.blurFrameEnabled && bg.visible && gap > 0 && gap < k;
        }

        function carve(gap) {
            if (gap <= 0)
                return 0;
            const kg = k - gap;
            return (gap - Math.sqrt(Math.max(gap * gap - 2 * kg * kg, 0))) / 2;
        }

        Region {
            x: bg.x
            y: root.blurFrameTop
            width: bandOn(gapTop) ? bg.width : 0
            height: bandOn(gapTop) ? gapTop : 0
            bottomLeftRadius: root.blurCornerRadius(bg, bg.x, bg.y, bg.topLeftRadius)
            bottomRightRadius: root.blurCornerRadius(bg, bg.x + bg.width, bg.y, bg.topRightRadius)

            Region {
                x: bg.x
                y: root.blurFrameTop + carve(gapTop)
                width: parent.width
                height: Math.max(0, gapTop - 2 * carve(gapTop))
                intersection: Intersection.Subtract
            }
        }

        Region {
            x: bg.x
            y: root.height - root.blurFrameBottom
            width: bandOn(gapBottom) ? bg.width : 0
            height: bandOn(gapBottom) ? gapBottom : 0
            topLeftRadius: root.blurCornerRadius(bg, bg.x, bg.y + bg.height, bg.bottomLeftRadius)
            topRightRadius: root.blurCornerRadius(bg, bg.x + bg.width, bg.y + bg.height, bg.bottomRightRadius)

            Region {
                x: bg.x
                y: root.height - root.blurFrameBottom - carve(gapBottom)
                width: parent.width
                height: Math.max(0, gapBottom - 2 * carve(gapBottom))
                intersection: Intersection.Subtract
            }
        }

        Region {
            x: root.blurFrameLeft
            y: bg.y
            width: bandOn(gapLeft) ? gapLeft : 0
            height: bandOn(gapLeft) ? bg.height : 0
            topRightRadius: root.blurCornerRadius(bg, bg.x, bg.y, bg.topLeftRadius)
            bottomRightRadius: root.blurCornerRadius(bg, bg.x, bg.y + bg.height, bg.bottomLeftRadius)

            Region {
                x: root.blurFrameLeft + carve(gapLeft)
                y: bg.y
                width: Math.max(0, gapLeft - 2 * carve(gapLeft))
                height: parent.height
                intersection: Intersection.Subtract
            }
        }

        Region {
            x: root.width - root.blurFrameRight
            y: bg.y
            width: bandOn(gapRight) ? gapRight : 0
            height: bandOn(gapRight) ? bg.height : 0
            topLeftRadius: root.blurCornerRadius(bg, bg.x + bg.width, bg.y, bg.topRightRadius)
            bottomLeftRadius: root.blurCornerRadius(bg, bg.x + bg.width, bg.y + bg.height, bg.bottomRightRadius)

            Region {
                x: root.width - root.blurFrameRight - carve(gapRight)
                y: bg.y
                width: Math.max(0, gapRight - 2 * carve(gapRight))
                height: parent.height
                intersection: Intersection.Subtract
            }
        }
    }
}
