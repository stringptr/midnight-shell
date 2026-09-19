import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property var client

    anchors.fill: parent
    spacing: Tokens.spacing.small

    Label {
        Layout.topMargin: Tokens.padding.extraLargeIncreased

        text: root.client?.title ?? Tr.tr("No active client")
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere

        font: Tokens.font.body.builders.large.weight(Font.Medium).build()
    }

    Label {
        text: root.client?.lastIpcObject?.app_id ?? root.client?.lastIpcObject?.class ?? Tr.tr("No active client")
        color: Colours.palette.m3tertiary

        font: Tokens.font.body.large
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        Layout.leftMargin: Tokens.padding.extraLargeIncreased
        Layout.rightMargin: Tokens.padding.extraLargeIncreased
        Layout.topMargin: Tokens.spacing.medium
        Layout.bottomMargin: Tokens.spacing.largeIncreased

        color: Colours.palette.m3secondary
    }

    Detail {
        icon: "location_on"
        text: {
            const id = root.client?.id;
            if (id)
                return Tr.trCtx("ID: %1", "window id").arg(String(id));
            return Tr.trCtx("ID: unknown", "window id");
        }
        color: Colours.palette.m3primary
    }

    Detail {
        icon: "location_searching"
        // TRANSLATORS: %1/%2 = x and y position in pixels
        text: Tr.tr("Position: %1, %2").arg(root.client?.lastIpcObject.at[0] ?? -1).arg(root.client?.lastIpcObject.at[1] ?? -1)
    }

    Detail {
        icon: "resize"
        // TRANSLATORS: %1/%2 = width and height in pixels; the x is a multiplication sign
        text: Tr.tr("Size: %1 x %2").arg(root.client?.lastIpcObject.size[0] ?? -1).arg(root.client?.lastIpcObject.size[1] ?? -1)
        color: Colours.palette.m3tertiary
    }

    Detail {
        icon: "workspaces"
        // TRANSLATORS: %1 = workspace id
        text: Tr.tr("Workspace: %1").arg(root.client?.workspace_id ?? -1)
        color: Colours.palette.m3secondary
    }

    Detail {
        icon: "desktop_windows"
        text: {
            const mon = root.client?.monitor;
            if (mon)
                // TRANSLATORS: %1 = monitor name, %2 = monitor id, %3/%4 = x/y position in pixels
                return Tr.tr("Monitor: %1 (%2) at %3, %4").arg(mon.name).arg(mon.id).arg(mon.x).arg(mon.y);
            return Tr.tr("Monitor: unknown");
        }
    }

    Detail {
        icon: "page_header"
        // TODO: Niri has no initialTitle property
        text: Tr.tr("Initial title: N/A")
        color: Colours.palette.m3tertiary
    }

    Detail {
        icon: "category"
        // TODO: Niri has no initialClass property
        text: Tr.tr("Initial class: N/A")
    }

    Detail {
        icon: "account_tree"
        // TRANSLATORS: %1 = window id
        text: Tr.tr("Window id: %1").arg(String(root.client?.id ?? -1))
        color: Colours.palette.m3primary
    }

    Detail {
        icon: "picture_in_picture_center"
        // TODO: Niri has no floating property
        text: Tr.tr("Floating: N/A")
        color: Colours.palette.m3secondary
    }

    Detail {
        icon: "gradient"
        // TODO: Niri has no xwayland property
        text: Tr.tr("Xwayland: N/A")
    }

    Detail {
        icon: "keep"
        // TODO: Niri has no pinned property
        text: Tr.tr("Pinned: N/A")
        color: Colours.palette.m3secondary
    }

    Detail {
        icon: "fullscreen"
        text: root.client?.is_fullscreen ? Tr.tr("Fullscreen state: on") : Tr.tr("Fullscreen state: off")
        color: Colours.palette.m3tertiary
    }

    Item {
        Layout.fillHeight: true
    }

    component Detail: RowLayout {
        id: detail

        required property string icon
        required property string text
        property alias color: icon.color

        Layout.leftMargin: Tokens.padding.large
        Layout.rightMargin: Tokens.padding.large
        Layout.fillWidth: true

        spacing: Tokens.spacing.medium

        MaterialIcon {
            id: icon

            Layout.alignment: Qt.AlignVCenter
            text: detail.icon
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            text: detail.text
            elide: Text.ElideRight
            font: Tokens.font.body.medium
        }
    }

    component Label: StyledText {
        Layout.leftMargin: Tokens.padding.large
        Layout.rightMargin: Tokens.padding.large
        Layout.fillWidth: true
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        animate: true
    }
}
