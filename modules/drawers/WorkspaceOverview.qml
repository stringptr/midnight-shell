pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils
Item {
    id: root

    required property ShellScreen screen

    readonly property ScreenState screenState: ShellState.forScreen(screen)
    property real offsetScale: screenState.workspaceDrawer ? 0 : 1

    anchors.top: parent.top
    anchors.bottom: parent.bottom
    property real slideAmount: (-implicitWidth - Config.border.thickness - Tokens.spacing.medium) * offsetScale
    anchors.leftMargin: slideAmount
    anchors.rightMargin: slideAmount
    
    implicitWidth: 200
    visible: offsetScale < 0.999
    opacity: 1 - offsetScale

    Behavior on offsetScale { Anim {} }

    Item {
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            StyledText {
                text: qsTr("Workspaces")
                font: Tokens.font.title.large
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: Tokens.spacing.small
            }

            VerticalFadeListView {
                id: wsList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Tokens.spacing.medium

                model: 10

                delegate: Item {
                    id: wsDelegate
                    required property int index
                    readonly property int workspaceId: index + 1
                    readonly property int activeWsId: {
                        const outputWs = Niri.allWorkspaces.filter(w => w.output === root.screen.name);
                        const focused = outputWs.find(w => w.is_focused);
                        return focused ? focused.id : (outputWs.length > 0 ? outputWs[0].id : 1);
                    }
                    readonly property bool isActive: activeWsId === workspaceId
                    
                    property int activeDrags: 0
                    z: activeDrags > 0 ? 100 : 0
                    
                    property list<var> windows: Niri.windows.filter(t => {
                        return t.workspace_id === workspaceId;
                    })
                    
                    property var niriOutput: Niri.outputs[root.screen.name] ?? null
                    property bool isPortrait: niriOutput && (niriOutput.transform === "90" || niriOutput.transform === "270" || niriOutput.transform === 1 || niriOutput.transform === 3)
                    property real mw: niriOutput && niriOutput.mode ? (isPortrait ? niriOutput.mode.height : niriOutput.mode.width) : 1920
                    property real mh: niriOutput && niriOutput.mode ? (isPortrait ? niriOutput.mode.width : niriOutput.mode.height) : 1080
                    property real mx: niriOutput && niriOutput.location ? niriOutput.location.x : 0
                    property real my: niriOutput && niriOutput.location ? niriOutput.location.y : 0
                    
                    // TODO: Niri doesn't expose absolute window positions (at/size)
                    // Using output dimensions as fallback for workspace thumbnails
                    property real inactiveOffsetX: 0
                    property real inactiveOffsetY: 0
                    property real contentMinX: 0
                    property real contentMaxX: mw
                    property real contentMinY: 0
                    property real contentMaxY: mh
                    property real targetMw: mw
                    property real targetMh: mh
                    property real targetMinX: 0
                    property real targetMinY: 0

                    property real effectiveMw: targetMw
                    property real effectiveMh: targetMh
                    property real effectiveMinX: targetMinX
                    property real effectiveMinY: targetMinY

                    Behavior on effectiveMw { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Behavior on effectiveMh { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Behavior on effectiveMinX { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Behavior on effectiveMinY { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    width: ListView.view.width
                    implicitHeight: width * (effectiveMh / effectiveMw)

                    Item {
                        id: bgContainer
                        anchors.fill: parent
                        clip: true

                        layer.enabled: true
                        layer.effect: Mask {
                            maskSource: maskItem
                        }

                        Image {
                            id: wallpaperImage
                            width: (wsDelegate.mw / wsDelegate.effectiveMw) * parent.width
                            height: (wsDelegate.mh / wsDelegate.effectiveMh) * parent.height
                            x: -(wsDelegate.effectiveMinX / wsDelegate.effectiveMw) * parent.width
                            y: -(wsDelegate.effectiveMinY / wsDelegate.effectiveMh) * parent.height
                            source: Wallpapers.current ? (Wallpapers.getThumbnailPath(Wallpapers.current) || "") : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            smooth: true
                            mipmap: true

                            StyledRect {
                                anchors.fill: parent
                                color: Colours.palette.m3surfaceContainer
                                opacity: isActive ? 0.3 : 0.6
                            }
                        }
                    }

                    Item {
                        id: maskItem
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        Rectangle {
                            anchors.fill: parent
                            radius: Tokens.rounding.large
                            color: "black"
                        }
                    }

                    StyledRect {
                        anchors.fill: parent
                        color: "transparent"
                        radius: Tokens.rounding.large
                        border.width: isActive ? 2 : 0
                        border.color: isActive ? Colours.palette.m3primary : "transparent"
                        
                        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }

                    DropArea {
                        anchors.fill: parent
                        onDropped: drop => {
                            const client = drop.source;
                            if (client) {
                                // TODO: Niri doesn't support move-to-workspace by address
                                console.log("WorkspaceOverview: move to workspace not yet supported in Niri");
                            }
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.large
                        onClicked: {
                            Niri.switchToWorkspace(workspaceId);
                            screenState.workspaceDrawer = false;
                        }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacing.small
                        // Do not clip here so the drag target can float out

                        Repeater {
                            id: windowRepeater
                            model: wsDelegate.windows
                            delegate: Item {
                                id: windowContainer
                                required property var modelData

                                // Niri doesn't expose absolute window positions (at/size)
                                // Using layout.window_size for dimensions, stubbing position
                                property real rawLogicalX: 0
                                property real rawLogicalY: 0
                                property real rawLogicalW: modelData.layout?.window_size?.width ?? 200
                                property real rawLogicalH: modelData.layout?.window_size?.height ?? 150
                                
                                property bool isDragging: dragArea.drag.active
                                onIsDraggingChanged: {
                                    if (isDragging) wsDelegate.activeDrags++;
                                    else wsDelegate.activeDrags--;
                                }
                                z: dragArea.drag.active ? 100 : 0

                                Behavior on rawLogicalX { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                Behavior on rawLogicalY { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                Behavior on rawLogicalW { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                Behavior on rawLogicalH { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                
                                x: ((rawLogicalX - wsDelegate.effectiveMinX) / wsDelegate.effectiveMw * parent.width)
                                y: ((rawLogicalY - wsDelegate.effectiveMinY) / wsDelegate.effectiveMh * parent.height)
                                width: (rawLogicalW / wsDelegate.effectiveMw * parent.width)
                                height: (rawLogicalH / wsDelegate.effectiveMh * parent.height)

                                Item {
                                    id: windowVisualProxy
                                    width: parent.width
                                    height: parent.height
                                    
                                    opacity: dragArea.drag.active ? 0.8 : 1
                                    scale: dragArea.drag.active ? 1.05 : 1
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    
                                    Drag.active: dragArea.drag.active
                                    Drag.keys: ["window"]
                                    Drag.hotSpot.x: width / 2
                                    Drag.hotSpot.y: height / 2
                                    Drag.source: windowContainer.modelData

                                    StyledRect {
                                        id: windowBg
                                        anchors.fill: parent
                                        color: Colours.palette.m3surfaceContainer
                                        radius: Tokens.rounding.medium
                                    }

                                    Rectangle {
                                        id: windowMask
                                        anchors.fill: parent
                                        radius: Tokens.rounding.medium
                                        layer.enabled: true
                                        visible: false
                                    }

                                    Item {
                                        anchors.fill: parent
                                        layer.enabled: true
                                        layer.effect: Mask {
                                            maskSource: windowMask
                                        }

                                        Item {
                                            anchors.fill: parent
                                            clip: true

                                            StyledRect {
                                                anchors.fill: parent
                                                color: Colours.palette.m3surfaceContainer
                                                opacity: isActive ? 0.3 : 0.6
                                            }
                                        }

                                        SafeScreencopy {
                                            anchors.fill: parent
                                            captureSource: {
                                                const win = windowContainer.modelData;
                                                if (!win || !win.wayland) return null;
                                                return win.wayland;
                                            }
                                            live: windowBg.visible
                                        }

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 32
                                            height: 32
                                            radius: Tokens.rounding.medium
                                            color: Colours.tPalette.m3surface
                                        }

                                        IconImage {
                                            anchors.centerIn: parent
                                            source: Icons.getAppIcon(windowContainer.modelData.app_id ?? "", "image-missing")
                                            width: 64
                                            height: 64
                                            scale: 20 / 64
                                            asynchronous: true
                                        }
                                    }

                                    StyledRect {
                                        anchors.fill: parent
                                        color: "transparent"
                                        border.width: 2
                                        border.color: dragArea.containsMouse ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                                        radius: Tokens.rounding.medium
                                        
                                        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    }
                                }

                                MouseArea {
                                    id: dragArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    drag.target: windowVisualProxy
                                    drag.axis: Drag.XAndYAxis
                                    cursorShape: Qt.PointingHandCursor
                                    
                                    property bool wasDragged: false
                                    property real pressX: 0
                                    property real pressY: 0

                                    onPressed: (mouse) => {
                                        wasDragged = false;
                                        pressX = mouse.x;
                                        pressY = mouse.y;
                                    }

                                    onPositionChanged: (mouse) => {
                                        if (Math.abs(mouse.x - pressX) > 5 || Math.abs(mouse.y - pressY) > 5) {
                                            wasDragged = true;
                                        }
                                    }

                                    onReleased: (mouse) => {
                                        if (wasDragged) {
                                            windowVisualProxy.Drag.drop();
                                            windowVisualProxy.x = 0;
                                            windowVisualProxy.y = 0;
                                        } else {
                                            // TODO: Niri doesn't support focus by address
                                            console.log("WorkspaceOverview: focus by address not yet supported in Niri");
                                            screenState.workspaceDrawer = false;
                                        }
                                        wasDragged = false;
                                    }

                                    onClicked: mouse => {
                                        mouse.accepted = true;
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        id: wsIdText
                        visible: windowRepeater.count === 0
                        text: workspaceId.toString()
                        font: Tokens.font.title.large
                        color: isActive ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: Tokens.spacing.medium
                        anchors.bottomMargin: 0
                    }
                }
            }
        }
    }
}
