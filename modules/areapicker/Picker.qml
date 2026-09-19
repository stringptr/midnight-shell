pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia
import Caelestia.I18n
import qs.components
import qs.components.effects
import qs.services

MouseArea {
    id: root

    required property LazyLoader loader
    required property ShellScreen screen

    property bool onClient

    // Niri doesn't expose border/rounding config via IPC, use sensible defaults
    property int borderWidth: 2
    property int rounding: 8

    property real realBorderWidth: onClient ? borderWidth : 2
    property real realRounding: onClient ? rounding : 0

    property real ssx
    property real ssy

    property real sx: 0
    property real sy: 0
    property real ex: screen.width
    property real ey: screen.height

    property real rsx: Math.min(sx, ex)
    property real rsy: Math.min(sy, ey)
    property real sw: Math.abs(sx - ex)
    property real sh: Math.abs(sy - ey)

    // Get windows in current workspace using Niri service
    property var clients: {
        if (!Niri.niriAvailable) return [];
        return Niri.getActiveWorkspaceWindows().slice().sort((a, b) => {
            const aPos = a.layout?.pos_in_scrolling_layout || [0, 0];
            const bPos = b.layout?.pos_in_scrolling_layout || [0, 0];
            if (aPos[0] !== bPos[0]) return aPos[0] - bPos[0];
            return aPos[1] - bPos[1];
        });
    }

    // Estimate window screen position from Niri layout data
    function getWindowGeometry(window) {
        if (!window?.layout?.window_size) return null;

        const size = window.layout.window_size;
        const pos = window.layout.pos_in_scrolling_layout ?? [0, 0];

        const focusedWindow = Niri.focusedWindow;
        if (!focusedWindow?.layout?.pos_in_scrolling_layout) {
            return {
                x: (screen.width - size[0]) / 2,
                y: (screen.height - size[1]) / 2,
                w: size[0],
                h: size[1]
            };
        }

        const focusedPos = focusedWindow.layout.pos_in_scrolling_layout;
        const focusedSize = focusedWindow.layout.window_size ?? [screen.width, screen.height];

        const colOffset = pos[0] - focusedPos[0];
        const rowOffset = pos[1] - focusedPos[1];

        const focusedX = focusedSize[0] < screen.width ? (screen.width - focusedSize[0]) / 2 : 0;
        const focusedY = focusedSize[1] < screen.height ? (screen.height - focusedSize[1]) / 2 : 0;

        return {
            x: focusedX + (colOffset * size[0]),
            y: focusedY + (rowOffset * size[1]),
            w: size[0],
            h: size[1]
        };
    }

    function checkClientRects(x: real, y: real): void {
        for (const client of clients) {
            const geom = getWindowGeometry(client);
            if (!geom) continue;

            const cx = geom.x;
            const cy = geom.y;
            const cw = geom.w;
            const ch = geom.h;

            if (cx <= x && cy <= y && cx + cw >= x && cy + ch >= y) {
                onClient = true;
                sx = cx;
                sy = cy;
                ex = cx + cw;
                ey = cy + ch;
                break;
            }
        }
    }

    function save(): void {
        const isSearch = root.loader.searchMode;
        const tmpfile = isSearch
            ? Qt.resolvedUrl("/tmp/caelestia-search.png")
            : Qt.resolvedUrl(`/tmp/caelestia-picker-${Quickshell.processId}-${Date.now()}.png`);
        CUtils.saveItem(screencopy, tmpfile, Qt.rect(Math.ceil(rsx), Math.ceil(rsy), Math.floor(sw), Math.floor(sh)), path => {
            if (isSearch) {
                Quickshell.execDetached(["touch", "/tmp/caelestia-search.done"]);
            } else if (root.loader.clipboardOnly) {
                Quickshell.execDetached(["caelestia", "screenshot", "--copy", "--file", path]);
            } else {
                Quickshell.execDetached(["caelestia", "screenshot", "--file", path]);
            }
            Audio.playCameraClick();
            closeAnim.start();
        });
    }

    onClientsChanged: checkClientRects(mouseX, mouseY)

    anchors.fill: parent
    opacity: 0
    hoverEnabled: true
    cursorShape: Qt.CrossCursor

    Component.onCompleted: {
        // Break binding if frozen
        if (loader.freeze)
            clients = clients;

        opacity = 1;

        const c = clients[0];
        if (c) {
            const geom = getWindowGeometry(c);
            if (geom) {
                onClient = true;
                sx = geom.x;
                sy = geom.y;
                ex = geom.x + geom.w;
                ey = geom.y + geom.h;
            } else {
                sx = screen.width / 2 - 100;
                sy = screen.height / 2 - 100;
                ex = screen.width / 2 + 100;
                ey = screen.height / 2 + 100;
            }
        } else {
            sx = screen.width / 2 - 100;
            sy = screen.height / 2 - 100;
            ex = screen.width / 2 + 100;
            ey = screen.height / 2 + 100;
        }
    }

    onPressed: event => {
        ssx = event.x;
        ssy = event.y;
    }

    onReleased: {
        if (closeAnim.running)
            return;

        if (root.loader.freeze) {
            save();
        } else {
            overlay.visible = border.visible = false;
            screencopy.visible = false;
            screencopy.active = true;
        }
    }

    onPositionChanged: event => {
        const x = event.x;
        const y = event.y;

        if (pressed) {
            onClient = false;
            sx = ssx;
            sy = ssy;
            ex = x;
            ey = y;
        } else {
            checkClientRects(x, y);
        }
    }

    focus: true
    Keys.onEscapePressed: closeAnim.start()

    SequentialAnimation {
        id: closeAnim

        PropertyAction {
            target: root.loader
            property: "closing"
            value: true
        }
        ParallelAnimation {
            Anim {
                target: root
                property: "opacity"
                to: 0
                type: Anim.StandardLarge
            }
            Anim {
                target: root
                properties: "rsx,rsy"
                to: 0
            }
            Anim {
                target: root
                property: "sw"
                to: root.screen.width
            }
            Anim {
                target: root
                property: "sh"
                to: root.screen.height
            }
        }
        PropertyAction {
            target: root.loader
            property: "activeAsync"
            value: false
        }
    }

    // Re-check client rects when focused workspace changes
    Connections {
        target: Niri

        function onFocusedWorkspaceIdChanged(): void {
            root.checkClientRects(root.mouseX, root.mouseY);
        }
    }

    Loader {
        id: screencopy

        asynchronous: true
        anchors.fill: parent

        active: root.loader.freeze

        sourceComponent: ScreencopyView {
            captureSource: root.screen

            onHasContentChanged: {
                if (hasContent && !root.loader.freeze) {
                    overlay.visible = border.visible = true;
                    root.save();
                }
            }
        }
    }

    StyledRect {
        id: overlay

        anchors.fill: parent
        color: Colours.palette.m3secondaryContainer
        opacity: 0.3

        layer.enabled: true
        layer.effect: Mask {
            maskSource: selectionWrapper
            maskInverted: true
        }
    }

    Item {
        id: selectionWrapper

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            id: selectionRect

            radius: root.realRounding
            x: root.rsx
            y: root.rsy
            implicitWidth: root.sw
            implicitHeight: root.sh
        }
    }

    Rectangle {
        id: border

        color: "transparent"
        radius: root.realRounding > 0 ? root.realRounding + root.realBorderWidth : 0
        border.width: root.realBorderWidth
        border.color: Colours.palette.m3primary

        x: selectionRect.x - root.realBorderWidth
        y: selectionRect.y - root.realBorderWidth
        implicitWidth: selectionRect.implicitWidth + root.realBorderWidth * 2
        implicitHeight: selectionRect.implicitHeight + root.realBorderWidth * 2

        Behavior on border.color {
            CAnim {}
        }
    }

    Behavior on opacity {
        Anim {
            type: Anim.StandardLarge
        }
    }

    Behavior on rsx {
        enabled: !root.pressed

        Anim {}
    }

    Behavior on rsy {
        enabled: !root.pressed

        Anim {}
    }

    Behavior on sw {
        enabled: !root.pressed

        Anim {}
    }

    Behavior on sh {
        enabled: !root.pressed

        Anim {}
    }
}
