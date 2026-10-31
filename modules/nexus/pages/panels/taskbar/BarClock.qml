pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Clock")
    isSubPage: true

    // There must be one entry for each value of the AlarmMissed enum.
    readonly property list<MenuItem> missedItems: [
        MenuItem {
            text: Tr.tr("Ring when the shell wakes")
            value: AlarmMissed.Ring
        },
        MenuItem {
            text: Tr.tr("Skip it")
            value: AlarmMissed.Skip
        },
        MenuItem {
            text: Tr.tr("Wait for the next day")
            value: AlarmMissed.NextDay
        }
    ]

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ToggleRow {
            first: true
            text: qsTr("Background")
            configNode: root.targetConfig.bar.clock
            propertyName: "background"
            checked: root.targetConfig.bar.clock.background
            onToggled: {
                root.targetConfig.bar.clock.background = checked;
                root.targetConfig.save();
            }
        }

        ToggleRow {
            text: qsTr("Show date")
            configNode: root.targetConfig.bar.clock
            propertyName: "showDate"
            checked: root.targetConfig.bar.clock.showDate
            onToggled: {
                root.targetConfig.bar.clock.showDate = checked;
                root.targetConfig.save();
            }
        }

        ToggleRow {
            text: qsTr("Show icon")
            configNode: root.targetConfig.bar.clock
            propertyName: "showIcon"
            checked: root.targetConfig.bar.clock.showIcon
            onToggled: {
                root.targetConfig.bar.clock.showIcon = checked;
                root.targetConfig.save();
            }
        }

        ToggleRow {
            text: qsTr("Show seconds")
            configNode: root.targetConfig.bar.clock
            propertyName: "showSeconds"
            checked: root.targetConfig.bar.clock.showSeconds
            onToggled: {
                root.targetConfig.bar.clock.showSeconds = checked;
                root.targetConfig.save();
            }
        }

        ToggleRow {
            text: qsTr("Uppercase AM/PM")
            subtext: qsTr("Applies in 12-hour mode")
            configNode: root.targetConfig.bar.clock
            propertyName: "uppercaseAmPm"
            checked: root.targetConfig.bar.clock.uppercaseAmPm
            onToggled: {
                root.targetConfig.bar.clock.uppercaseAmPm = checked;
                root.targetConfig.save();
            }
        }

        SectionHeader {
            text: qsTr("Alarm")
        }

        StepperRow {
            first: true
            Layout.fillWidth: true
            label: qsTr("Sound interval")
            subtext: qsTr("Seconds between repeats while the alarm sounds")
            configNode: root.targetConfig.bar.clock.alarm
            propertyName: "soundInterval"
            value: root.targetConfig.bar.clock.alarm.soundInterval
            from: 1
            to: 60
            stepSize: 1
            onMoved: v => {
                root.targetConfig.bar.clock.alarm.soundInterval = v;
                root.targetConfig.save();
            }
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Ring for")
            subtext: qsTr("Seconds before the sound stops. The notification stays until dismissed")
            configNode: root.targetConfig.bar.clock.alarm
            propertyName: "soundDuration"
            value: root.targetConfig.bar.clock.alarm.soundDuration
            from: 0
            to: 300
            stepSize: 10
            onMoved: v => {
                root.targetConfig.bar.clock.alarm.soundDuration = v;
                root.targetConfig.save();
            }
        }

        SelectRow {
            last: true
            Layout.fillWidth: true
            label: qsTr("Missed alarm")
            subtext: qsTr("Applies when the alarm is more than a minute late, for example after the shell was closed")
            menuItems: root.missedItems
            active: root.missedItems.find(i => i.value === root.targetConfig.bar.clock.alarm.missedAction) ?? root.missedItems[0]
            onSelected: item => {
                root.targetConfig.bar.clock.alarm.missedAction = item.value;
                root.targetConfig.save();
            }
        }
    }
}
