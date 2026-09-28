pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

ItemList {
    id: root

    property var nodes: []
    property int currentId: -1
    property string iconName: "speaker"
    property bool showVolume: false

    signal selected(node: PwNode)
    signal volumeChanged(node: PwNode, vol: real)

    last: true
    showList: true

    model: ScriptModel {
        values: [...root.nodes].sort((a, b) => (a.description || a.name || "").localeCompare(b.description || b.name || ""))
    }

    delegate: Item {
        id: device

        required property PwNode modelData
        required property int index
        readonly property bool active: device.modelData?.id === root.currentId

        anchors.left: root.list.contentItem.left
        anchors.right: root.list.contentItem.right
        implicitHeight: col.implicitHeight + col.anchors.margins * 2

        StateLayer {
            radius: Tokens.rounding.extraSmall
            bottomLeftRadius: device.index === root?.list.count - 1 ? Tokens.rounding.extraLarge : radius
            bottomRightRadius: device.index === root?.list.count - 1 ? Tokens.rounding.extraLarge : radius
            onClicked: root.selected(device.modelData)
        }

        ColumnLayout {
            id: col

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            anchors.bottomMargin: root.showVolume ? Tokens.padding.medium + Tokens.spacing.extraSmall : Tokens.padding.medium
            spacing: 0

            RowLayout {
                id: deviceLayout

                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.largeIncreased - Tokens.padding.medium
                Layout.rightMargin: Tokens.padding.largeIncreased - Tokens.padding.medium
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: implicitHeight
                    implicitHeight: devIcon.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.full
                    color: device.active ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                    MaterialIcon {
                        id: devIcon

                        anchors.centerIn: parent
                        text: root.iconName
                        color: device.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                        fontStyle: Tokens.font.icon.medium
                        fill: device.active ? 1 : 0

                        Behavior on fill {
                            Anim {}
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: device.modelData?.description || device.modelData?.name || Tr.trCtx("Unknown", "unknown audio device")
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                MaterialIcon {
                    text: "check"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.medium
                    opacity: device.active ? 1 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }
            }

            RowLayout {
                id: volumeRow

                visible: root.showVolume
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.extraSmall
                Layout.leftMargin: Tokens.padding.largeIncreased - Tokens.padding.medium
                Layout.rightMargin: Tokens.padding.largeIncreased - Tokens.padding.medium
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: Icons.getVolumeIcon(Audio.getNodeVolume(device.modelData), Audio.getNodeMuted(device.modelData))
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                CustomMouseArea {
                    function onWheel(event: WheelEvent): void {
                        const step = GlobalConfig.services.audioIncrement;
                        const cur = Audio.getNodeVolume(device.modelData);
                        if (event.angleDelta.y > 0)
                            root.volumeChanged(device.modelData, Math.min(1, cur + step));
                        else if (event.angleDelta.y < 0)
                            root.volumeChanged(device.modelData, Math.max(0, cur - step));
                    }

                    Layout.fillWidth: true
                    implicitHeight: Tokens.padding.medium * 2

                    StyledSlider {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: parent.implicitHeight

                        radius: Tokens.rounding.small
                        from: 0
                        to: 1
                        value: Audio.getNodeVolume(device.modelData)
                        enabled: !Audio.getNodeMuted(device.modelData)
                        onInteraction: v => root.volumeChanged(device.modelData, v)
                    }
                }

                MaterialIcon {
                    text: Audio.getNodeMuted(device.modelData) ? "volume_off" : "volume_up"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small

                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: Audio.setNodeMuted(device.modelData, !Audio.getNodeMuted(device.modelData))
                    }
                }
            }
        }
    }
}
