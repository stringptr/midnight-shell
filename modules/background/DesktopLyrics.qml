pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property Item wallpaper
    required property real absX
    required property real absY

    property real lyricsScale: Config.background.desktopLyrics.scale
    readonly property bool bgEnabled: Config.background.desktopLyrics.background.enabled
    readonly property bool blurEnabled: bgEnabled && Config.background.desktopLyrics.background.blur && !GameMode.enabled
    readonly property bool invertColors: Config.background.desktopLyrics.invertColors
    readonly property bool useLightSet: Colours.light ? !invertColors : invertColors
    readonly property color safePrimary: useLightSet ? Colours.palette.m3primaryContainer : Colours.palette.m3primary
    readonly property color safeSecondary: useLightSet ? Colours.palette.m3secondaryContainer : Colours.palette.m3secondary
    readonly property color safeTertiary: useLightSet ? Colours.palette.m3tertiaryContainer : Colours.palette.m3tertiary
    readonly property string sansFont: GlobalConfig.appearance.font.body.family || "Sans Serif"
    readonly property int alignment: Config.background.desktopLyrics.alignment
    readonly property bool autoHideFullscreen: Config.background.desktopLyrics.autoHideFullscreen
    readonly property bool autoHideTiled: Config.background.desktopLyrics.autoHideTiled
    
    // TODO: Niri fullscreen/tiled detection (adapted from Hyprland)
    readonly property bool hasFullscreen: false
    readonly property bool hasTiled: false

    readonly property bool shouldHide: (autoHideFullscreen && hasFullscreen) || (autoHideTiled && hasTiled)
    readonly property bool appFilterActive: Players.appFilterPasses(Config.background.desktopLyrics.appFilter, Config.background.desktopLyrics.filteredApps, Players.active)

    property bool hasLyrics: Lyrics.hasLyrics
    property int currentLyricIndex: -1
    readonly property bool isCurrentActive: currentLyricIndex >= 0

    property var player: Players.active
    readonly property int contextLines: Config.background.desktopLyrics.contextLines
    readonly property int centerSlot: contextLines
    readonly property int slotCount: contextLines * 2 + 1
    readonly property bool hasText: {
        const lines = Lyrics.lyrics;
        for (let d = -contextLines; d <= contextLines; d++) {
            const i = currentLyricIndex + d;
            if (i >= 0 && i < lines.length && (lines[i] ?? "").trim() !== "")
                return true;
        }
        return false;
    }

    property real lyricSpacing: Tokens.spacing.large * root.lyricsScale
    property int slideDir: 1
    property int lastSlideIndex: -1
    readonly property int textAlignment: {
        switch (root.alignment) {
        case 0:
            return Text.AlignLeft;
        case 2:
            return Text.AlignRight;
        default:
            return Text.AlignHCenter;
        }
    }

    function reloadTrack() {
        const p = Players.active;
        if (p) {
            Lyrics.setTrack(p.trackArtist, p.trackTitle, p.trackAlbum, p.length);
        } else {
            Lyrics.clearTrack();
        }
    }

    function forceUpdate() {
        currentLyricIndex = Lyrics.hasLyrics ? Lyrics.indexForTime(Players.active?.position ?? 0) : -1;
    }

    function lineText(d) {
        const i = currentLyricIndex + d;
        const lines = Lyrics.lyrics;
        if (i < 0 || i >= lines.length)
            return "";
        return (lines[i] ?? "").replace(/\u00A0/g, " ");
    }

    function slotY(s) {
        repeater.count; // Re-evaluate once delegates finish building
        const c = centerSlot;
        const sp = lyricSpacing;
        const center = repeater.itemAt(c);
        let y = (lyricsContainer.height - (center ? center.height : 0)) / 2;
        if (s > c) {
            for (let k = c; k < s; k++) {
                const it = repeater.itemAt(k);
                if (it && it.visible)
                    y += it.height + sp;
            }
        } else {
            for (let k = c - 1; k >= s; k--) {
                const it = repeater.itemAt(k);
                if (it && it.visible)
                    y -= it.height + sp;
            }
        }
        return y;
    }

    function slideFromY(s, dir) {
        const last = slotCount - 1;
        const it = repeater.itemAt(s);
        if (dir > 0 && s === last)
            return slotY(s) + (it && it.visible ? it.height + lyricSpacing : 0);
        if (dir < 0 && s === 0)
            return slotY(s) - (it && it.visible ? it.height + lyricSpacing : 0);
        return slotY(s + dir);
    }

    onCurrentLyricIndexChanged: {
        slideDir = currentLyricIndex > lastSlideIndex ? 1 : -1;
        lastSlideIndex = currentLyricIndex;
    }

    Component.onCompleted: {
        root.reloadTrack();
    }

    implicitWidth: 350 * root.lyricsScale
    implicitHeight: Config.background.desktopLyrics.height * root.lyricsScale

    opacity: (((root.hasLyrics && root.hasText) || Lyrics.loading) && !root.shouldHide && root.appFilterActive) ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {}
    }

    Behavior on lyricsScale {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Behavior on implicitWidth {
        Anim {
            type: Anim.StandardSmall
        }
    }

    Behavior on implicitHeight {
        Anim {
            type: Anim.StandardSmall
        }
    }

    Timer {
        running: Players.active?.isPlaying ?? false
        interval: GlobalConfig.dashboard.mediaUpdateInterval
        triggeredOnStart: true
        repeat: true
        onTriggered: {
            if (!Players.active)
                return;
            currentLyricIndex = Lyrics.indexForTime(Players.active.position);
            Players.active?.positionChanged();
        }
    }

    Connections {
        function onActiveChanged() {
            root.reloadTrack();
        }

        target: Players
    }

    Connections {
        function onPostTrackChanged() {
            root.reloadTrack();
        }

        ignoreUnknownSignals: true

        target: Players.active
    }

    Connections {
        function onHasLyricsChanged() {
            root.forceUpdate();
        }

        function onLyricsChanged() {
            root.forceUpdate();
        }

        target: Lyrics
    }

    Item {
        id: lyricsContainer

        anchors.fill: parent
        // Removed clip: true from here so the shadow doesn't get cut off

        layer.enabled: Config.background.desktopLyrics.shadow.enabled
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: Config.background.desktopLyrics.shadow.opacity
            shadowBlur: Config.background.desktopLyrics.shadow.blur
        }

        Loader {
            id: blurLoader

            asynchronous: true
            anchors.fill: parent
            active: root.blurEnabled && root.wallpaper !== null

            sourceComponent: MultiEffect {
                source: ShaderEffectSource {
                    sourceItem: root.wallpaper
                    sourceRect: Qt.rect(root.absX, root.absY, root.width, root.height)
                }
                maskSource: backgroundPlate
                maskEnabled: true
                blurEnabled: true
                blur: 1
                blurMax: 64
                autoPaddingEnabled: false
            }
        }

        StyledRect {
            id: backgroundPlate

            visible: root.bgEnabled
            anchors.fill: parent
            radius: Tokens.rounding.large * root.lyricsScale
            opacity: Config.background.desktopLyrics.background.opacity
            color: Colours.palette.m3surface

            layer.enabled: root.blurEnabled
        }

        Loader {
            id: loadingIndicator

            anchors.centerIn: parent
            asynchronous: true
            active: opacity > 0
            opacity: Lyrics.loading && !root.hasLyrics ? 1 : 0

            sourceComponent: ColumnLayout {
                spacing: Tokens.spacing.large * root.lyricsScale

                StyledRect {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: shape.implicitSize + Tokens.padding.medium * 2 * root.lyricsScale
                    implicitHeight: shape.implicitSize + Tokens.padding.medium * 2 * root.lyricsScale
                    color: Colours.palette.m3primaryContainer
                    radius: Tokens.rounding.full

                    LoadingIndicator {
                        id: shape

                        anchors.centerIn: parent
                        implicitSize: Math.round(Tokens.sizes.dashboard.mediaSectionWidth / 5 * root.lyricsScale)
                        containsIcon: true
                        color: Colours.palette.m3primary
                    }
                }

                StyledText {
                    text: qsTr("Loading lyrics...")
                    color: root.safeSecondary
                    font.pointSize: Tokens.font.title.medium.pointSize * root.lyricsScale
                    font.family: Tokens.font.title.medium.family
                    font.weight: Tokens.font.title.medium.weight
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        // --- NEW INNER CONTAINER FOR FADE MASK ---
        Item {
            id: fadeContainer

            anchors.fill: parent
            clip: true
            opacity: root.hasLyrics ? 1 : 0

            layer.enabled: true
            layer.effect: Mask {
                maskSource: fadeMask
            }

            Behavior on opacity {
                Anim {
                    type: Anim.SlowEffects
                }
            }

            Rectangle {
                id: fadeMask

                layer.enabled: true
                visible: false
                implicitWidth: fadeContainer.width
                implicitHeight: fadeContainer.height

                gradient: Gradient {
                    orientation: Gradient.Vertical

                    GradientStop {
                        color: Qt.alpha("black", 0)
                        position: 0
                    }
                    GradientStop {
                        color: Qt.alpha("black", 1)
                        position: 0.25 // fadeMargin
                    }
                    GradientStop {
                        color: Qt.alpha("black", 1)
                        position: 0.75 // 1 - fadeMargin
                    }
                    GradientStop {
                        color: Qt.alpha("black", 0)
                        position: 1
                    }
                }
            }

            Repeater {
                id: repeater

                model: root.slotCount

                delegate: Item {
                    id: slot

                    required property int index

                    readonly property int distance: index - root.centerSlot
                    readonly property bool isCenter: distance === 0
                    readonly property string line: root.lineText(distance)
                    readonly property real bigPointSize: Tokens.font.title.medium.pointSize * 1.3 * root.lyricsScale
                    readonly property real smallPointSize: Tokens.font.body.medium.pointSize * root.lyricsScale

                    width: parent.width
                    height: label.implicitHeight
                    y: root.slotY(index)
                    visible: root.isCurrentActive && line !== ""

                    Connections {
                        function onCurrentLyricIndexChanged() {
                            if (root.isCurrentActive)
                                slide.restart();
                        }

                        target: root
                    }

                    SequentialAnimation {
                        id: slide

                        PropertyAction {
                            target: slot
                            property: "y"
                            value: root.slideFromY(slot.index, root.slideDir)
                        }

                        NumberAnimation {
                            target: slot
                            property: "y"
                            to: root.slotY(slot.index)
                            duration: Tokens.anim.durations.expressiveDefaultEffects
                            easing.type: Easing.OutCubic
                        }
                    }

                    MultiEffect {
                        anchors.fill: label
                        source: label
                        scale: label.scale
                        enabled: slot.isCenter && root.isCurrentActive

                        blurEnabled: true
                        blur: 0.4

                        shadowEnabled: true
                        shadowColor: Colours.palette.m3primary
                        shadowOpacity: 0.5
                        shadowBlur: 0.6
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0

                        autoPaddingEnabled: true
                    }

                    StyledText {
                        id: label

                        anchors.fill: parent
                        text: slot.line
                        font.family: root.sansFont
                        font.pointSize: slot.isCenter ? slot.bigPointSize : slot.smallPointSize
                        font.weight: slot.isCenter ? Font.Bold : Tokens.font.body.small.weight
                        color: slot.isCenter ? Colours.palette.m3primary : root.safeSecondary
                        opacity: slot.isCenter ? 1 : Math.max(0.3, 0.6 - (Math.abs(slot.distance) - 1) * 0.15)
                        wrapMode: Text.WordWrap
                        horizontalAlignment: root.textAlignment
                    }
                }
            }
        }
    }
}
