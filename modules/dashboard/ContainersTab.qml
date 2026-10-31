import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    // Set by Content.qml. Poll only while this pane is the visible tab.
    property bool paneActive: false

    implicitWidth: 840
    implicitHeight: 440

    function stateIcon(state: string): string {
        switch (state) {
        case "running":
            return "play_circle";
        case "paused":
            return "pause_circle";
        case "created":
            return "pending";
        case "exited":
            return "stop_circle";
        default:
            return "help";
        }
    }

    function stateColour(container: var): color {
        if (container.running)
            return Colours.palette.m3primary;
        if (container.state === "paused")
            return Colours.palette.m3tertiary;
        return Colours.palette.m3onSurfaceVariant;
    }

    function stateLabel(container: var): string {
        if (container.running)
            return Tr.tr("On");
        return Tr.tr("Idle");
    }

    function actionLabel(container: var): string {
        if (container.state === "paused")
            return Tr.tr("Resume");
        if (container.running)
            return Tr.tr("Stop");
        return Tr.tr("Run");
    }

    function actionIcon(container: var): string {
        if (container.running)
            return "stop";
        return "play_arrow";
    }

    function triggerAction(container: var): void {
        if (container.state === "paused")
            Podman.unpauseContainer(container.id);
        else if (container.running)
            Podman.stopContainer(container.id);
        else
            Podman.startContainer(container.id);
    }

    Timer {
        interval: Podman.refreshInterval
        running: root.paneActive
        repeat: true
        onTriggered: Podman.refresh()
    }

    onPaneActiveChanged: {
        if (paneActive)
            Podman.refresh();
    }

    Component.onCompleted: {
        if (paneActive)
            Podman.refresh();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true

            Column {
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: Tr.tr("Containers")
                    font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: Tr.tr("Podman containers that are on or idle")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                visible: Podman.lastUpdated !== null
                text: Podman.lastUpdated !== null ? Tr.tr("Updated %1").arg(Podman.lastUpdated.toLocaleTimeString(Qt.locale(), Units.twelveHourClock ? "h:mm AP" : "HH:mm")) : ""
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: Podman.errorMessage.length > 0
            text: Tr.tr("Could not list containers: %1").arg(Podman.errorMessage)
            wrapMode: Text.WordWrap
            font: Tokens.font.body.small
            color: Colours.palette.m3error
        }

        StyledText {
            Layout.fillWidth: true
            visible: Podman.actionError.length > 0
            text: Podman.actionError
            wrapMode: Text.WordWrap
            font: Tokens.font.body.small
            color: Colours.palette.m3error
        }

        Flickable {
            id: flick

            Layout.fillWidth: true
            Layout.fillHeight: true

            clip: true
            contentWidth: width
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: StyledScrollBar {
                flickable: flick
            }

            ColumnLayout {
                id: body

                width: flick.width
                spacing: Tokens.spacing.small

                SectionHeader {
                    text: Tr.tr("Running")
                    count: Podman.running.length
                }

                StyledText {
                    Layout.leftMargin: Tokens.padding.small
                    visible: Podman.running.length === 0
                    text: Tr.tr("No containers are running")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Repeater {
                    model: Podman.running

                    delegate: ContainerCard {
                        entry: modelData
                    }
                }

                SectionHeader {
                    Layout.topMargin: Tokens.spacing.medium
                    text: Tr.tr("Idle")
                    count: Podman.idle.length
                }

                StyledText {
                    Layout.leftMargin: Tokens.padding.small
                    visible: Podman.idle.length === 0
                    text: Tr.tr("No idle containers")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Repeater {
                    model: Podman.idle

                    delegate: ContainerCard {
                        entry: modelData
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.padding.small
                }
            }
        }
    }

    component SectionHeader: RowLayout {
        id: header

        property string text
        property int count

        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        spacing: Tokens.spacing.small

        StyledText {
            text: header.text
            font: Tokens.font.title.small
            color: Colours.palette.m3onSurface
        }

        StyledRect {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: countText.implicitWidth + Tokens.padding.small * 2
            implicitHeight: countText.implicitHeight + Tokens.padding.extraSmall * 2
            radius: Tokens.rounding.full
            color: Colours.tPalette.m3surfaceContainerHigh

            StyledText {
                id: countText

                anchors.centerIn: parent
                text: String(header.count)
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }

    component ContainerCard: StyledRect {
        id: card

        property var entry

        Layout.fillWidth: true
        implicitHeight: cardLayout.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: cardLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Tokens.padding.medium
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.stateIcon(card.entry.state)
                    fill: 1
                    color: root.stateColour(card.entry)
                    fontStyle: Tokens.font.icon.large
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: card.entry.name
                        elide: Text.ElideRight
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: card.entry.image
                        elide: Text.ElideMiddle
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                StyledRect {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: stateText.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: stateText.implicitHeight + Tokens.padding.extraSmall * 2
                    radius: Tokens.rounding.full
                    color: Qt.rgba(root.stateColour(card.entry).r, root.stateColour(card.entry).g, root.stateColour(card.entry).b, 0.15)

                    StyledText {
                        id: stateText

                        anchors.centerIn: parent
                        text: root.stateLabel(card.entry)
                        font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                        color: root.stateColour(card.entry)
                    }
                }

                StyledRect {
                    id: actionButton

                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: actionRow.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: actionRow.implicitHeight + Tokens.padding.extraSmall * 2
                    radius: Tokens.rounding.full
                    opacity: Podman.actionRunning ? 0.5 : 1
                    color: {
                        const c = card.entry.running ? Colours.palette.m3error : Colours.palette.m3primary;
                        return Qt.rgba(c.r, c.g, c.b, actionArea.containsMouse ? 0.22 : 0.12);
                    }

                    RowLayout {
                        id: actionRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: root.actionIcon(card.entry)
                            color: card.entry.running ? Colours.palette.m3error : Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: root.actionLabel(card.entry)
                            font: Tokens.font.body.small
                            color: card.entry.running ? Colours.palette.m3error : Colours.palette.m3primary
                        }
                    }

                    CustomMouseArea {
                        id: actionArea

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        enabled: !Podman.actionRunning
                        onClicked: root.triggerAction(card.entry)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    text: card.entry.status
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: card.entry.ports.length > 0
                    text: card.entry.ports
                    elide: Text.ElideRight
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}