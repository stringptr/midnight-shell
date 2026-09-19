import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.images
import qs.utils
import qs.services
import qs.modules.nexus.common
import Quickshell
import Quickshell.Widgets
import Caelestia

PageBase {
    id: root

    title: qsTr("Game mode")
    isSubPage: true

    ColumnLayout {
        id: layout
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Auto-enable rules")
        }

        ToggleRow {
            first: true
            text: qsTr("Enable automatically")
            subtext: qsTr("Turn on game mode when a target window is focused or running")
            configNode: root.targetConfig.utilities.gameMode
            propertyName: "autoEnable"
            checked: root.targetConfig.utilities.gameMode.autoEnable
            onToggled: {
                root.targetConfig.utilities.gameMode.autoEnable = checked;
                root.targetConfig.save();
            }
        }

        NavRow {
            last: true
            icon: "ads_click"
            text: qsTr("Target windows")
            subtext: qsTr("Add or remove auto-enable targets")
            onClicked: root.nState.openSubPage(3)
        }

        // TODO: Niri has no runtime config mutation for animations/blur/gaps/shadows
        ToggleRow {
            text: qsTr("Disable window transparency")
            last: true
            configNode: root.targetConfig.utilities.gameMode
            propertyName: "disableWindowTransparency"
            checked: root.targetConfig.utilities.gameMode.disableWindowTransparency
            onToggled: {
                root.targetConfig.utilities.gameMode.disableWindowTransparency = checked;
                root.targetConfig.save();
            }
        }

        SectionHeader {
            text: qsTr("MiDnight feature overrides")
        }

        ToggleRow {
            first: true
            text: qsTr("Disable shell transparency")
            configNode: root.targetConfig.utilities.gameMode
            propertyName: "disableShellTransparency"
            checked: root.targetConfig.utilities.gameMode.disableShellTransparency
            onToggled: {
                root.targetConfig.utilities.gameMode.disableShellTransparency = checked;
                root.targetConfig.save();
            }
        }
        ToggleRow {
            text: qsTr("Disable toast notifications transparency")
            configNode: root.targetConfig.utilities.gameMode
            propertyName: "disableToastTransparency"
            checked: root.targetConfig.utilities.gameMode.disableToastTransparency
            onToggled: {
                root.targetConfig.utilities.gameMode.disableToastTransparency = checked;
                root.targetConfig.save();
            }
        }
        ToggleRow {
            text: qsTr("Disable desktop lyrics")
            configNode: root.targetConfig.utilities.gameMode
            propertyName: "disableDesktopLyrics"
            checked: root.targetConfig.utilities.gameMode.disableDesktopLyrics
            onToggled: {
                root.targetConfig.utilities.gameMode.disableDesktopLyrics = checked;
                root.targetConfig.save();
            }
        }
        ToggleRow {
            text: qsTr("Disable visualizer")
            configNode: root.targetConfig.utilities.gameMode
            propertyName: "disableVisualizer"
            checked: root.targetConfig.utilities.gameMode.disableVisualizer
            onToggled: {
                root.targetConfig.utilities.gameMode.disableVisualizer = checked;
                root.targetConfig.save();
            }
        }
        ToggleRow {
            text: qsTr("Disable shimeji pets")
            last: true
            configNode: root.targetConfig.utilities.gameMode
            propertyName: "disableShimeji"
            checked: root.targetConfig.utilities.gameMode.disableShimeji
            onToggled: {
                root.targetConfig.utilities.gameMode.disableShimeji = checked;
                root.targetConfig.save();
            }
        }
    }
}
