pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property var client

    Layout.preferredWidth: preview.implicitWidth + Tokens.padding.extraLargeIncreased
    Layout.fillHeight: true

    StyledClippingRect {
        id: preview

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: label.top
        anchors.topMargin: Tokens.padding.large
        anchors.bottomMargin: Tokens.spacing.medium

        implicitWidth: view.implicitWidth

        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.medium

        Loader {
            asynchronous: true
            anchors.centerIn: parent
            active: !root.client

            sourceComponent: ColumnLayout {
                spacing: 0

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "web_asset_off"
                    color: Colours.palette.m3outline
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(3).build()
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Tr.tr("No active client")
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.builders.large.size(28).weight(Font.Medium).build()
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Tr.tr("Try switching to a window")
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.large
                }
            }
        }

        SafeScreencopy {
            id: view

            anchors.fill: parent

            captureSource: {
                const client = root.client;
                if (!client || !client.wayland) return null; // qmllint disable unresolved-type
                const size = client.layout?.window_size;
                if (size && (size[0] <= 0 || size[1] <= 0)) return null;
                return client.wayland;
            }
            live: visible

            constraintSize.width: (root.client && root.client.layout?.window_size && root.client.layout.window_size[1] > 0) ? parent.height * Math.min(root.screen.width / root.screen.height, root.client.layout.window_size[0] / root.client.layout.window_size[1]) : parent.height
            constraintSize.height: parent.height
        }
    }

    StyledText {
        id: label

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.padding.large

        animate: true
        text: {
            const client = root.client;
            if (!client)
                return Tr.tr("No active client");

            const output = Niri.outputs[client.output];
            const pos = client.layout?.pos_in_scrolling_layout;
            // TRANSLATORS: %1 = window title, %2 = monitor name, %3/%4 = column/row position
            return Tr.tr("%1 on monitor %2 at %3, %4").arg(client.title).arg(output?.name ?? "unknown").arg(pos?.[0] ?? -1).arg(pos?.[1] ?? -1);
        }
    }
}
