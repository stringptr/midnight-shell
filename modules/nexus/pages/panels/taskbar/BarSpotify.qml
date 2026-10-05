pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Spotify")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Configuration")
        }

        ToggleRow {
            first: true
            text: qsTr("Background")
            subtext: qsTr("Render a solid background behind the Spotify widget")
            configNode: root.targetConfig.bar.spotify
            propertyName: "background"
            checked: root.targetConfig.bar.spotify.background
            onToggled: {
                root.targetConfig.bar.spotify.background = checked;
                root.targetConfig.save();
            }
        }

        ToggleRow {
            text: qsTr("Show visualizer")
            subtext: qsTr("Display animated frequency visualizer bars")
            configNode: root.targetConfig.bar.spotify
            propertyName: "showVisualiser"
            checked: root.targetConfig.bar.spotify.showVisualiser
            onToggled: {
                root.targetConfig.bar.spotify.showVisualiser = checked;
                root.targetConfig.save();
            }
        }

        StepperRow {
            label: qsTr("Max title length")
            subtext: qsTr("Cut off character count for track title")
            configNode: root.targetConfig.bar.spotify
            propertyName: "maxTitleLength"
            value: root.targetConfig.bar.spotify.maxTitleLength
            from: 5
            to: 100
            stepSize: 1
            onMoved: v => {
                root.targetConfig.bar.spotify.maxTitleLength = v;
                root.targetConfig.save();
            }
        }

        ToggleRow {
            text: qsTr("Inverted text direction")
            subtext: qsTr("Rotate text in the opposite direction when the bar is vertical")
            configNode: root.targetConfig.bar.spotify
            propertyName: "inverted"
            checked: root.targetConfig.bar.spotify.inverted
            onToggled: {
                root.targetConfig.bar.spotify.inverted = checked;
                root.targetConfig.save();
            }
        }

        ToggleRow {
            text: qsTr("Auto-hide")
            subtext: qsTr("Hide the widget when there is no media source available")
            configNode: root.targetConfig.bar.spotify
            propertyName: "autoHide"
            checked: root.targetConfig.bar.spotify.autoHide
            onToggled: {
                root.targetConfig.bar.spotify.autoHide = checked;
                root.targetConfig.save();
            }
        }

        ToggleRow {
            text: qsTr("Horizontal volume slider")
            subtext: qsTr("Place a horizontal volume slider below the playback controls in the popout")
            configNode: root.targetConfig.bar.spotify
            propertyName: "horizontalVolume"
            checked: root.targetConfig.bar.spotify.horizontalVolume
            onToggled: {
                root.targetConfig.bar.spotify.horizontalVolume = checked;
                root.targetConfig.save();
            }
        }

        SectionHeader {
            text: qsTr("App filter")
        }

        SelectRow {
            first: true
            label: qsTr("Filter mode")
            subtext: qsTr("Only show the widget for specific apps")
            configNode: root.targetConfig.bar.spotify
            propertyName: "appFilter"
            menuItems: [
                MenuItem { text: qsTr("Disabled") },
                MenuItem { text: qsTr("Whitelist") },
                MenuItem { text: qsTr("Blacklist") }
            ]
            active: {
                switch (root.targetConfig.bar.spotify.appFilter) {
                case AppFilter.Whitelist: return menuItems[1];
                case AppFilter.Blacklist: return menuItems[2];
                default: return menuItems[0];
                }
            }
            onSelected: item => {
                if (item === menuItems[1])
                    root.targetConfig.bar.spotify.appFilter = AppFilter.Whitelist;
                else if (item === menuItems[2])
                    root.targetConfig.bar.spotify.appFilter = AppFilter.Blacklist;
                else
                    root.targetConfig.bar.spotify.appFilter = AppFilter.Disabled;
                root.targetConfig.save();
            }
        }

        TagRow {
            last: true
            label: qsTr("Filtered apps")
            subtext: qsTr("App names to include or exclude (case-insensitive)")
            configNode: root.targetConfig.bar.spotify
            propertyName: "filteredApps"
            values: root.targetConfig.bar.spotify.filteredApps
            onValueAdded: value => {
                const apps = root.targetConfig.bar.spotify.filteredApps;
                apps.push(value);
                root.targetConfig.bar.spotify.filteredApps = apps;
                root.targetConfig.save();
            }
            onValueRemoved: index => {
                const apps = root.targetConfig.bar.spotify.filteredApps;
                apps.splice(index, 1);
                root.targetConfig.bar.spotify.filteredApps = apps;
                root.targetConfig.save();
            }
            enabled: root.targetConfig.bar.spotify.appFilter !== AppFilter.Disabled
        }
    }
}
