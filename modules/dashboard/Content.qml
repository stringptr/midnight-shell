pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.filedialog
import "../../services"

Item {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker

    readonly property var dashboardTabs: {
        const allTabs = [
            {
                component: dashComponent,
                iconName: "dashboard",
                text: Tr.tr("Dashboard"),
                enabled: Config.dashboard.showDashboard
            },
            {
                component: mediaComponent,
                iconName: "queue_music",
                text: Tr.tr("Media"),
                enabled: Config.dashboard.showMedia
            },
            {
                component: performanceComponent,
                iconName: "speed",
                text: Tr.tr("Performance"),
                enabled: Config.dashboard.showPerformance
            },
            {
                component: weatherComponent,
                iconName: "cloud",
                text: Tr.tr("Weather"),
                enabled: Config.dashboard.showWeather
            },
            {
                component: providersComponent,
                iconName: "hub",
                text: Tr.tr("Providers"),
                enabled: Config.dashboard.showProviders
            },
            {
                component: containersComponent,
                iconName: "deployed_code",
                text: Tr.tr("Containers"),
                enabled: Config.dashboard.showContainers
            },
            {
                component: lastfmComponent,
                iconName: "music_note",
                text: Tr.tr("Last.fm"),
                enabled: Config.dashboard.showLastfm && Lastfm.configured
            },
            {
                component: terminalComponent,
                iconName: "terminal",
                text: qsTr("Terminal"),
                enabled: Config.dashboard.showTerminal
            }
        ];
        return allTabs.filter(tab => tab.enabled);
    }

    readonly property real nonAnimWidth: view.implicitWidth + viewWrapper.anchors.margins * 2
    readonly property real nonAnimHeight: tabs.implicitHeight + tabs.anchors.topMargin + view.implicitHeight + viewWrapper.anchors.margins * 2

    // Tabs can be disabled from Nexus while the dashboard is open, which shifts
    // or removes the current index. Keep the selection inside the visible range.
    onDashboardTabsChanged: {
        const last = root.dashboardTabs.length - 1;
        if (last >= 0 && root.screenState.dashboardTab > last)
            root.screenState.dashboardTab = last;
    }

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    Tabs {
        id: tabs

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: CUtils.clamp(anchors.margins - Config.border.thickness, 0, anchors.margins)
        anchors.margins: Tokens.padding.large

        nonAnimWidth: root.nonAnimWidth - anchors.margins * 2
        screenState: root.screenState
        tabs: root.dashboardTabs
    }

    ClippingRectangle {
        id: viewWrapper

        anchors.top: tabs.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large

        radius: Tokens.rounding.large
        color: "transparent"

        Flickable {
            id: view

            readonly property int currentIndex: root.screenState.dashboardTab
            readonly property Item currentItem: {
                repeater.count; // Trigger update on count change
                return repeater.itemAt(currentIndex);
            }

            anchors.fill: parent

            flickableDirection: Flickable.HorizontalFlick

            property real lastValidImplicitWidth: 0
            implicitWidth: currentItem ? currentItem.implicitWidth : lastValidImplicitWidth
            onImplicitWidthChanged: {
                if (currentItem) lastValidImplicitWidth = currentItem.implicitWidth;
            }

            property real lastValidImplicitHeight: 0
            implicitHeight: currentItem ? currentItem.implicitHeight : lastValidImplicitHeight
            onImplicitHeightChanged: {
                if (currentItem) lastValidImplicitHeight = currentItem.implicitHeight;
            }

            property real lastValidContentX: 0
            contentX: currentItem ? currentItem.x : lastValidContentX
            contentWidth: row.implicitWidth
            contentHeight: row.implicitHeight

            onContentXChanged: {
                if (currentItem && !moving) {
                    lastValidContentX = contentX;
                }

                if (!moving || !currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 2)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 2)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
            }

            onDragEnded: {
                if (!currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 10)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 10)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
                else
                    contentX = Qt.binding(() => currentItem?.x ?? 0);
            }

            RowLayout {
                id: row

                Repeater {
                    id: repeater

                    model: ScriptModel {
                        values: root.dashboardTabs
                    }

                    delegate: Loader {
                        id: paneLoader

                        required property int index
                        required property var modelData

                        property bool paneAlive: false

                        Layout.alignment: Qt.AlignTop

                        sourceComponent: modelData.component

                        onActiveChanged: {
                            if (active)
                                paneAlive = true;
                        }

                        onLoaded: {
                            // Last.fm owns its polling and computes activity
                            // from tabIndex. Other panes use paneActive so
                            // their animations and timers stop both when they
                            // are clipped offscreen and when the dashboard is
                            // closed (keepAlive can retain the pane itself).
                            if (!item)
                                return;
                            if (modelData.component === lastfmComponent) {
                                item.tabIndex = index;
                            } else {
                                item.paneActive = Qt.binding(() => root.screenState.dashboard && paneLoader.index === root.screenState.dashboardTab);
                            }
                        }

                        onIndexChanged: {
                            if (item && modelData.component === lastfmComponent)
                                item.tabIndex = index;
                        }

                        Component.onCompleted: active = Qt.binding(() => {
                            if (index === view.currentIndex)
                                return true;
                            if (Config.dashboard.keepAlive && paneAlive)
                                return true;
                            // Inactive Loaders have no width, so keep the
                            // neighbours around to give the Flickable a scroll
                            // target. Without this, a zero-sized start-up row
                            // makes every tab look visible and loads all panes.
                            return Math.abs(index - view.currentIndex) <= 1;
                        })
                    }
                }
            }

            Component {
                id: dashComponent

                Dash {
                    screenState: root.screenState
                    facePicker: root.facePicker
                }
            }

            Component {
                id: mediaComponent

                Media {
                    screenState: root.screenState
                }
            }

            Component {
                id: performanceComponent

                Performance {}
            }

            Component {
                id: weatherComponent

                WeatherTab {}
            }

            Component {
                id: providersComponent

                ProvidersTab {}
            }

            Component {
                id: containersComponent

                ContainersTab {}
            }

            Component {
                id: lastfmComponent

                LastfmTab {
                    screenState: root.screenState
                }
            }

            Component {
                id: terminalComponent

                TerminalTab {}
            }

            Behavior on contentX {
                Anim {}
            }
        }
    }

    Behavior on implicitWidth {
        Anim {}
    }

    Behavior on implicitHeight {
        Anim {}
    }
}
