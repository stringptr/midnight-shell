pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.modules.drawers

MouseArea {
    id: root

    enum Side {
        Top,
        Bottom,
        Left,
        Right
    }

    required property Item attachTo
    property int attachSideX: Menu.Right
    property int attachSideY: Menu.Bottom
    property int thisSideX: Menu.Right
    property int thisSideY: Menu.Top
    property real marginX
    property real marginY

    property list<MenuItem> items
    // Entries that do not apply are dropped from the model rather than hidden:
    // a MenuItem is a plain QtObject with no visibility of its own.
    readonly property list<MenuItem> visibleItems: (root.items ?? []).filter(entry => entry.visible !== false)
    property MenuItem active: root.visibleItems[0] ?? null
    property bool expanded
    property real maxHeight: 320

    // The surface the rows sit on. Exposed so callers can measure the menu
    // before deciding which way it has to unfold.
    readonly property alias backgroundItem: menu
    // Drops the surface fill and its elevation, leaving the rows on whatever is
    // behind the menu (the desktop, for the desktop context menu).
    property bool transparentBackground: false
    // Unfold sideways from the anchor instead of dropping down.
    property bool revealHorizontal: false
    // A right click repositions the menu through rightClickedAt() rather than
    // closing it.
    property bool rightClickReposition: false

    // Set for one event loop turn by replayReveal() to re-run the unfold.
    property bool replaying: false

    signal itemSelected(item: MenuItem)
    // Right click at (x, y) in the parent's coordinates, while repositioning.
    signal rightClickedAt(real x, real y)

    // Replays the unfold animation without closing the menu. Used when the menu
    // is re-anchored somewhere else while it is already open.
    function replayReveal(): void {
        if (!revealHorizontal || !expanded)
            return;
        replaying = true;
        replayTimer.restart();
    }

    parent: {
        let node = root.attachTo;
        let interactionsNode = null;
        
        while (node && node.parent) {
            if (node.utilitiesShortcutActive !== undefined) {
                interactionsNode = node;
            }
            node = node.parent;
        }

        if (interactionsNode) {
            return interactionsNode;
        }

        return node || root.parent;
    }
    anchors.fill: parent

    enabled: expanded
    hoverEnabled: expanded
    cursorShape: expanded ? Qt.ArrowCursor : undefined
    acceptedButtons: rightClickReposition ? Qt.LeftButton | Qt.RightButton : Qt.AllButtons
    onClicked: mouse => {
        if (rightClickReposition && mouse.button === Qt.RightButton) {
            rightClickedAt(mouse.x, mouse.y);
            return;
        }
        expanded = false;
    }

    Timer {
        id: replayTimer

        interval: 0
        onTriggered: root.replaying = false
    }

    opacity: expanded ? 1 : 0

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    TransformWatcher {
        id: watcher

        a: root.parent
        b: root.attachTo
    }

    Elevation {
        id: menu

        x: {
            watcher.transform; // mapToItem is not reactive so this forces updates
            const item = root.attachTo;
            let off = root.attachSideX === Menu.Left ? 0 : item.width;
            if (root.thisSideX === Menu.Right)
                off -= width;
            return item.mapToItem(root.parent, off, 0).x + root.marginX;
        }
        y: {
            watcher.transform; // mapToItem is not reactive so this forces updates
            const item = root.attachTo;
            let off = root.attachSideY === Menu.Top ? 0 : item.height;
            if (root.thisSideY === Menu.Bottom)
                off -= height;
            return item.mapToItem(root.parent, 0, off).y + root.marginY;
        }

        radius: Tokens.rounding.large
        level: root.transparentBackground ? 0 : 2

        implicitWidth: Math.max(200, column.implicitWidth + Tokens.padding.extraSmall * 2)
        implicitHeight: Math.min(root.maxHeight, column.implicitHeight + Tokens.padding.extraSmall * 2)

        transform: Scale {
            id: menuScale

            // 0 collapsed, 1 unfolded; flipping it is what the Behavior animates,
            // so reveal direction only decides which axis is scaled.
            property real progress: (root.expanded && !root.replaying) ? 1 : 0

            xScale: root.revealHorizontal ? progress : 1
            yScale: root.revealHorizontal ? 1 : 0.1 + 0.9 * progress
            origin.x: root.thisSideX === Menu.Right ? menu.width : 0
            origin.y: root.thisSideY === Menu.Bottom ? menu.height : 0

            Behavior on progress {
                Anim {
                    type: root.revealHorizontal ? Anim.FastEffects : Anim.DefaultEffects
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.expanded
            hoverEnabled: true
            onWheel: e => e.accepted = true
        }

        StyledRect {
            anchors.fill: parent
            radius: parent.radius
            color: root.transparentBackground ? "transparent" : Colours.palette.m3surfaceContainerLow

            Flickable {
                id: flickable

                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall
                contentWidth: width
                contentHeight: column.implicitHeight
                clip: true

                interactive: contentHeight > height

                ScrollBar.vertical: StyledScrollBar {
                    flickable: flickable
                }

                ColumnLayout {
                    id: column

                    width: parent.width
                    spacing: 0

                    Repeater {
                        id: repeater

                        model: root.visibleItems

                    StyledRect {
                        id: item

                        required property int index
                        required property MenuItem modelData
                        readonly property bool active: modelData === root?.active

                        Layout.fillWidth: true
                        implicitWidth: menuOptionRow.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: menuOptionRow.implicitHeight + Tokens.padding.medium * 2

                        radius: active ? Tokens.rounding.medium : Tokens.rounding.extraSmall
                        topLeftRadius: index === 0 ? Tokens.rounding.medium : radius
                        topRightRadius: index === 0 ? Tokens.rounding.medium : radius
                        bottomLeftRadius: index === repeater?.count - 1 ? Tokens.rounding.medium : radius
                        bottomRightRadius: index === repeater?.count - 1 ? Tokens.rounding.medium : radius

                        color: Qt.alpha(Colours.palette.m3tertiaryContainer, active ? 1 : 0)

                        Behavior on radius {
                            Anim {}
                        }

                        StateLayer {
                            topLeftRadius: parent.topLeftRadius
                            topRightRadius: parent.topRightRadius
                            bottomLeftRadius: parent.bottomLeftRadius
                            bottomRightRadius: parent.bottomRightRadius

                            color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                            disabled: !root.expanded
                            onClicked: {
                                root.itemSelected(item.modelData);
                                root.active = item.modelData;
                                item.modelData.clicked();
                                root.expanded = false;
                            }
                        }

                        RowLayout {
                            id: menuOptionRow

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                Layout.alignment: Qt.AlignVCenter
                                text: item.modelData?.icon ?? ""
                                color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                text: item.modelData?.text ?? ""
                                color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                            }

                            Loader {
                                asynchronous: true
                                Layout.alignment: Qt.AlignVCenter
                                active: item.modelData?.trailingIcon.length > 0
                                visible: active

                                sourceComponent: MaterialIcon {
                                    text: item.modelData.trailingIcon
                                    color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }
        }
        }
    }
}
