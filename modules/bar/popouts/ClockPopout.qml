pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property PopoutState popouts

    implicitWidth: Tokens.sizes.bar.audioWidth
    implicitHeight: layout.implicitHeight

    function countdownStatus(): string {
        if (ClockTimer.countdownFinished)
            return Tr.tr("Time's up");
        if (ClockTimer.countdownRunning)
            return Tr.tr("Running");
        if (ClockTimer.countdownRemaining < ClockTimer.countdownDuration)
            return Tr.tr("Paused");
        return Tr.tr("Ready");
    }

    function stopwatchStatus(): string {
        if (ClockTimer.stopwatchRunning)
            return Tr.tr("Running");
        if (ClockTimer.stopwatchElapsed > 0)
            return Tr.tr("Paused");
        return Tr.tr("Ready");
    }

    function alarmStatus(): string {
        if (ClockTimer.alarmRinging)
            return Tr.tr("Ringing");
        if (ClockTimer.alarmEnabled)
            return Tr.tr("Rings at %1").arg(ClockTimer.alarmNextText);
        return Tr.tr("Off");
    }

    ColumnLayout {
        id: layout

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.topMargin: Tokens.padding.medium
            Layout.leftMargin: Tokens.padding.small
            text: Tr.tr("Clock")
            font.weight: 500
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: timerLayout.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer
            clip: true

            ColumnLayout {
                id: timerLayout

                width: parent.width - Tokens.padding.medium * 2
                x: Tokens.padding.medium
                y: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Timer")
                        font.weight: 500
                    }

                    StyledText {
                        text: root.countdownStatus()
                        color: ClockTimer.countdownFinished ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: ClockTimer.countdownText
                    font: Tokens.font.headline.builders.large.scale(1.5).build()
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: [1, 5, 10, 15, 25]

                        TextButton {
                            required property int modelData

                            type: TextButton.Tonal
                            text: modelData + "m"
                            onClicked: ClockTimer.setCountdown(modelData * 60000)
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacing.small

                    IconButton {
                        icon: "remove"
                        type: IconButton.Tonal
                        onClicked: ClockTimer.shiftCountdown(-60000)
                    }

                    IconButton {
                        icon: ClockTimer.countdownRunning ? "pause" : "play_arrow"
                        type: IconButton.Filled
                        onClicked: ClockTimer.toggleCountdown()
                    }

                    IconButton {
                        icon: "add"
                        type: IconButton.Tonal
                        onClicked: ClockTimer.shiftCountdown(60000)
                    }

                    IconButton {
                        icon: "restart_alt"
                        type: IconButton.Text
                        onClicked: ClockTimer.resetCountdown()
                    }
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: stopwatchLayout.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer
            clip: true

            ColumnLayout {
                id: stopwatchLayout

                width: parent.width - Tokens.padding.medium * 2
                x: Tokens.padding.medium
                y: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Stopwatch")
                        font.weight: 500
                    }

                    StyledText {
                        text: root.stopwatchStatus()
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: ClockTimer.stopwatchText
                    font: Tokens.font.headline.builders.large.scale(1.5).build()
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacing.small

                    IconButton {
                        icon: ClockTimer.stopwatchRunning ? "pause" : "play_arrow"
                        type: IconButton.Filled
                        onClicked: ClockTimer.toggleStopwatch()
                    }

                    IconButton {
                        icon: "restart_alt"
                        type: IconButton.Text
                        onClicked: ClockTimer.resetStopwatch()
                    }
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: alarmLayout.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer
            clip: true

            ColumnLayout {
                id: alarmLayout

                width: parent.width - Tokens.padding.medium * 2
                x: Tokens.padding.medium
                y: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Alarm")
                        font.weight: 500
                    }

                    StyledSwitch {
                        checked: ClockTimer.alarmEnabled
                        onToggled: checked ? ClockTimer.enableAlarm() : ClockTimer.disableAlarm()
                    }
                }

                CustomMouseArea {
                    id: alarmTimeArea

                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: alarmTimeRow.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: alarmTimeRow.implicitHeight + Tokens.padding.small * 2
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true
                    cursorShape: Qt.SizeVerCursor

                    readonly property bool overHour: mouseX < width / 2

                    function onWheel(event: WheelEvent): void {
                        const step = overHour ? 60 : 1;
                        ClockTimer.shiftAlarm(event.angleDelta.y > 0 ? step : -step);
                    }

                    RowLayout {
                        id: alarmTimeRow

                        anchors.centerIn: parent
                        spacing: 0

                        StyledText {
                            text: ClockTimer.pad(ClockTimer.alarmHour)
                            font: Tokens.font.headline.builders.large.scale(1.5).build()
                            color: alarmTimeArea.containsMouse && alarmTimeArea.overHour ? Colours.palette.m3primary : Colours.palette.m3onSurface
                        }

                        StyledText {
                            text: ":"
                            font: Tokens.font.headline.builders.large.scale(1.5).build()
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            text: ClockTimer.pad(ClockTimer.alarmMinute)
                            font: Tokens.font.headline.builders.large.scale(1.5).build()
                            color: alarmTimeArea.containsMouse && !alarmTimeArea.overHour ? Colours.palette.m3primary : Colours.palette.m3onSurface
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Tr.tr("Scroll over the hour or minute to adjust")
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.small
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.alarmStatus()
                    color: {
                        if (ClockTimer.alarmRinging)
                            return Colours.palette.m3error;
                        if (ClockTimer.alarmEnabled)
                            return Colours.palette.m3onSurfaceVariant;
                        return Colours.palette.m3outline;
                    }
                    font: Tokens.font.body.small
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacing.small
                    visible: ClockTimer.alarmRinging || ClockTimer.alarmEnabled

                    TextButton {
                        type: TextButton.Tonal
                        text: Tr.tr("Snooze 5m")
                        onClicked: ClockTimer.snoozeAlarm(5)
                    }

                    TextButton {
                        type: ClockTimer.alarmRinging ? TextButton.Filled : TextButton.Text
                        text: Tr.tr("Turn off")
                        onClicked: ClockTimer.disableAlarm()
                    }
                }
            }
        }
    }
}
