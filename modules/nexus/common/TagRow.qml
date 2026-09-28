pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

ConnectedRect {
    id: root

    property alias label: label.text
    property string subtext
    property var configNode
    property string propertyName: ""
    property var values: []
    property string placeholderText: qsTr("Add app name...")

    signal valueAdded(value: string)
    signal valueRemoved(index: int)

    Layout.fillWidth: true
    implicitHeight: contentLayout.implicitHeight + contentLayout.anchors.margins * 2

    ColumnLayout {
        id: contentLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                id: label

                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            PerMonitorStatusChip {
                configNode: root.configNode
                propertyName: root.propertyName
            }

            Item {
                Layout.fillWidth: true
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.subtext !== ""
            text: root.subtext
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
            elide: Text.ElideRight
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: root.values

                delegate: StyledRect {
                    id: chip

                    required property string modelData
                    required property int index

                    implicitHeight: chipRow.implicitHeight + Tokens.padding.small * 2
                    implicitWidth: chipRow.implicitWidth + Tokens.padding.medium * 2
                    radius: Tokens.rounding.small
                    color: Colours.tPalette.m3secondaryContainer

                    RowLayout {
                        id: chipRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            text: chip.modelData
                            color: Colours.palette.m3onSecondaryContainer
                            font: Tokens.font.label.small
                        }

                        IconButton {
                            icon: "close"
                            type: IconButton.Text
                            font: Tokens.font.icon.small
                            onClicked: root.valueRemoved(chip.index)
                        }
                    }
                }
            }

            IconButton {
                id: addButton

                icon: "add"
                onClicked: addPopup.open = true

                BlobPopup {
                    id: addPopup

                    x: addButton.mapToItem(addButton.parent.parent, 0, 0).x
                    y: addButton.mapToItem(addButton.parent.parent, 0, 0).y + addButton.height + Tokens.spacing.small
                    width: addRow.implicitWidth + Tokens.padding.large * 2
                    padding: Tokens.padding.small
                    content: addRow

                    RowLayout {
                        id: addRow

                        spacing: Tokens.spacing.small

                        StyledTextField {
                            id: addInput

                            Layout.preferredWidth: 160
                            placeholderText: root.placeholderText
                            onAccepted: confirmAdd()

                            function confirmAdd(): void {
                                const text = addInput.text.trim();
                                if (text !== "") {
                                    root.valueAdded(text);
                                    addInput.clear();
                                    addPopup.open = false;
                                }
                            }
                        }

                        IconButton {
                            icon: "check"
                            onClicked: addInput.confirmAdd()
                        }
                    }
                }
            }
        }
    }
}
