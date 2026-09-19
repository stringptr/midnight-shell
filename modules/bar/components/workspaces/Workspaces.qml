pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

StyledClippingRect {
    id: root

    required property ShellScreen screen
    required property bool fullscreen

    // TODO: Niri has no special workspaces — always false
    readonly property bool onSpecial: false
    readonly property int activeWsId: Niri.focusedWorkspaceId ?? 1

    readonly property var occupied: {
        const occ = {};
        for (const ws of Niri.allWorkspaces) {
            const wins = Niri.getWindowsByWorkspaceId(ws.id);
            occ[ws.id] = wins ? wins.length > 0 : false;
        }
        return occ;
    }
    readonly property int groupOffset: Math.floor((activeWsId - 1) / Config.bar.workspaces.shown) * Config.bar.workspaces.shown

    property real blur: onSpecial ? 1 : 0

    readonly property bool isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"

    implicitWidth: isHorizontal ? (layout.implicitWidth + Tokens.padding.small) : Tokens.sizes.bar.innerWidth
    implicitHeight: isHorizontal ? Tokens.sizes.bar.innerWidth : (layout.implicitHeight + Tokens.padding.small)

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    Item {
        anchors.fill: parent
        scale: root.onSpecial ? 0.8 : 1
        opacity: root.onSpecial ? 0.5 : 1
        visible: !root.fullscreen

        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: root.blur
            blurMax: 32
        }

        Loader {
            asynchronous: true
            active: Config.bar.workspaces.occupiedBg

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall

            sourceComponent: OccupiedBg {
                workspaces: workspaces
                occupied: root.occupied
                groupOffset: root.groupOffset
            }
        }

        GridLayout {
            id: layout

            anchors.centerIn: parent
            columns: isHorizontal ? -1 : 1
            rows: isHorizontal ? 1 : -1
            flow: isHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
            columnSpacing: Math.floor(Tokens.spacing.small)
            rowSpacing: Math.floor(Tokens.spacing.small)

            Repeater {
                id: workspaces

                model: Config.bar.workspaces.shown

                Workspace {
                    activeWsId: root.activeWsId
                    occupied: root.occupied
                    groupOffset: root.groupOffset
                }
            }
        }

        Loader {
            asynchronous: true
            anchors.horizontalCenter: isHorizontal ? undefined : parent.horizontalCenter
            anchors.verticalCenter: isHorizontal ? parent.verticalCenter : undefined
            active: Config.bar.workspaces.activeIndicator

            sourceComponent: ActiveIndicator {
                activeWsId: root.activeWsId
                workspaces: workspaces
                mask: layout
                fullscreen: root.fullscreen
            }
        }

        MouseArea {
            anchors.fill: layout
            onClicked: event => {
                const ws = (layout.childAt(event.x, event.y) as Workspace)?.ws;
                if (!ws)
                    return;
                if (Niri.focusedWorkspaceId !== ws)
                    Niri.switchToWorkspaceByNumber(ws);
                // TODO: Niri has no special workspace toggle
            }
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    // TODO: Niri has no special workspaces — loader commented out
    // Loader {
    //     id: specialWs
    //     ...
    // }

    Behavior on blur {
        Anim {
            type: Anim.StandardSmall
        }
    }
}
