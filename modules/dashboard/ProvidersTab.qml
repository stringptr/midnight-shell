import QtQuick
import QtQuick.Layouts
import Quickshell
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
    implicitHeight: layout.implicitHeight

    function statusColour(status: string): color {
        switch (status) {
        case "ok":
            return Colours.palette.m3primary;
        case "limited":
            return Colours.palette.m3tertiary;
        case "error":
            return Colours.palette.m3error;
        default:
            return Colours.palette.m3onSurfaceVariant;
        }
    }

    function statusIcon(status: string): string {
        switch (status) {
        case "ok":
            return "check_circle";
        case "limited":
            return "hourglass_bottom";
        case "error":
            return "error";
        case "inactive":
            return "pause_circle";
        case "checking":
            return "progress_activity";
        default:
            return "help";
        }
    }

    function statusLabel(status: string): string {
        switch (status) {
        case "ok":
            return Tr.tr("OK");
        case "limited":
            return Tr.tr("Limited");
        case "error":
            return Tr.tr("Error");
        case "inactive":
            return Tr.tr("Inactive");
        case "checking":
            return Tr.tr("Checking");
        default:
            return Tr.tr("Unknown");
        }
    }

    function humanDuration(ms: real): string {
        let seconds = Math.max(0, Math.floor(ms / 1000));
        const days = Math.floor(seconds / 86400);
        seconds %= 86400;
        const hours = Math.floor(seconds / 3600);
        seconds %= 3600;
        const minutes = Math.floor(seconds / 60);
        let out = "";
        if (days > 0)
            out += `${days}d `;
        if (days > 0 || hours > 0)
            out += `${hours}h `;
        out += `${minutes}m`;
        return out.trim();
    }

    function resetLabel(entry: var): string {
        if (entry.resetAt && !isNaN(entry.resetAt))
            return "";
        if (entry.status === "limited")
            return Tr.tr("No reset time reported by provider");
        return "";
    }

    function sinceLabel(entry: var): string {
        if (!entry.since || isNaN(entry.since))
            return "";
        return Tr.tr("since %1 ago").arg(root.humanDuration(Date.now() - entry.since));
    }

    function detailLabel(entry: var): string {
        const parts = [];
        if (entry.reason)
            parts.push(entry.reason);
        const since = root.sinceLabel(entry);
        if (since)
            parts.push(since);
        if (entry.lockCount > 0)
            parts.push(Tr.trN("%n model locked", "%n models locked", entry.lockCount));
        return parts.join("  -  ");
    }

    function formatTokens(value: real): string {
        if (!value || !isFinite(value))
            return "";
        const units = [
            { value: 1e9, suffix: "B" },
            { value: 1e6, suffix: "M" },
            { value: 1e3, suffix: "K" }
        ];
        for (let i = 0; i < units.length; i++) {
            if (value < units[i].value)
                continue;
            const scaled = value / units[i].value;
            return `${Number(scaled.toFixed(scaled < 10 ? 1 : 0))}${units[i].suffix}`;
        }
        return String(Math.round(value));
    }

    function metaLabel(entry: var): string {
        const parts = [];
        if (entry.plan)
            parts.push(entry.plan);
        if (entry.limitText)
            parts.push(Tr.tr("Limit %1").arg(entry.limitText));
        if (entry.usedPercent >= 0)
            parts.push(Tr.tr("%1% used").arg(entry.usedPercent));
        if (entry.resetAt && !isNaN(entry.resetAt))
            parts.push(Tr.tr("Resets in %1").arg(root.humanDuration(entry.resetAt - Date.now())));
        if (entry.modelCount > 0)
            parts.push(Tr.trN("%n model", "%n models", entry.modelCount));
        if (entry.contextTokens > 0)
            parts.push(Tr.tr("%1 context").arg(root.formatTokens(entry.contextTokens)));
        return parts.join("  -  ");
    }

    function openDashboard(entry: var): void {
        const url = entry.link && entry.link.length > 0 ? entry.link : "";
        const profile = entry.dashboardProfile && entry.dashboardProfile.length > 0 ? entry.dashboardProfile : "";
        if (profile) {
            Quickshell.execDetached(["zen-browser", "-P", profile, "--new-window", url || "https://tokenharbor.ai/dashboard"]);
            return;
        }
        if (url.length > 0)
            Qt.openUrlExternally(url);
    }

    Timer {
        interval: LlmProviders.refreshInterval
        running: root.paneActive
        repeat: true
        onTriggered: LlmProviders.refresh()
    }

    Timer {
        interval: LlmProviders.usageRefreshInterval
        running: root.paneActive
        repeat: true
        onTriggered: LlmProviders.refreshUsage(false)
    }

    onPaneActiveChanged: {
        if (paneActive) {
            LlmProviders.refresh();
            LlmProviders.refreshUsage(false);
        }
    }

    Component.onCompleted: {
        if (paneActive) {
            LlmProviders.refresh();
            LlmProviders.refreshUsage(false);
        }
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            Layout.fillWidth: true

            Column {
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: Tr.tr("Providers")
                    font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: Tr.tr("Quota and rate-limit status")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                visible: LlmProviders.lastUpdated !== null
                text: LlmProviders.lastUpdated !== null ? Tr.tr("Updated %1").arg(LlmProviders.lastUpdated.toLocaleTimeString(Qt.locale(), Units.twelveHourClock ? "h:mm AP" : "HH:mm")) : ""
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        StyledText {
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            visible: LlmProviders.errorMessage.length > 0
            text: Tr.tr("Could not read provider data: %1").arg(LlmProviders.errorMessage)
            font: Tokens.font.body.small
            color: Colours.palette.m3error
        }

        Repeater {
            model: LlmProviders.providers

            delegate: ProviderCard {
                entry: modelData
                colour: root.statusColour(modelData.status)
                icon: root.statusIcon(modelData.status)
                label: root.statusLabel(modelData.status)
                resetText: root.resetLabel(modelData)
                detailText: root.detailLabel(modelData)
                metaText: root.metaLabel(modelData)
            }
        }
    }

    component ProviderCard: StyledRect {
        id: card

        property var entry
        property color colour
        property string icon
        property string label
        property string resetText
        property string detailText
        property string metaText

        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.large
        Layout.rightMargin: Tokens.padding.large
        implicitHeight: cardLayout.implicitHeight + Tokens.padding.large * 2

        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: cardLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Tokens.padding.large
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    text: card.icon
                    fill: 1
                    color: card.colour
                    fontStyle: Tokens.font.icon.large
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: card.entry.title
                        font: Tokens.font.title.medium
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        text: `${card.entry.source} - ${card.entry.subtitle}`
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                StyledRect {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: badgeText.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: badgeText.implicitHeight + Tokens.padding.extraSmall * 2
                    radius: Tokens.rounding.full
                    color: Qt.rgba(card.colour.r, card.colour.g, card.colour.b, 0.15)

                    StyledText {
                        id: badgeText

                        anchors.centerIn: parent
                        text: card.label
                        font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                        color: card.colour
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: card.metaText.length > 0
                text: card.metaText
                wrapMode: Text.WordWrap
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurface
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.extraSmall
                visible: card.entry.usedPercent >= 0
                implicitHeight: 6
                radius: Tokens.rounding.full
                color: Colours.tPalette.m3surfaceContainerHigh

                StyledRect {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(100, card.entry.usedPercent)) / 100
                    radius: Tokens.rounding.full
                    color: card.colour
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: card.detailText.length > 0
                text: card.detailText
                wrapMode: Text.WordWrap
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                visible: card.resetText.length > 0
                text: card.resetText
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurface
            }

            RowLayout {
                Layout.fillWidth: true
                visible: card.entry.usage !== null || card.entry.link.length > 0

                StyledText {
                    visible: card.entry.usage !== null
                    text: card.entry.usage !== null ? Tr.tr("%1 requests today").arg(card.entry.usage.requests) : ""
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Item {
                    Layout.fillWidth: true
                }

                CustomMouseArea {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: linkRow.implicitWidth
                    implicitHeight: linkRow.implicitHeight
                    visible: card.entry.link.length > 0 || (card.entry.dashboardProfile !== undefined && card.entry.dashboardProfile.length > 0)
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.openDashboard(card.entry)

                    RowLayout {
                        id: linkRow

                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            text: Tr.tr("Open dashboard")
                            font: Tokens.font.body.small
                            color: Colours.palette.m3primary
                        }

                        MaterialIcon {
                            text: "open_in_new"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.medium
                        }
                    }
                }
            }
        }
    }
}
