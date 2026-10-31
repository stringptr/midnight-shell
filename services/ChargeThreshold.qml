pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string devicePath: ""
    property bool supported: false
    property bool enabled: false
    property int settingsSupported: 0
    property int startThreshold: 0
    property int endThreshold: 0
    property bool busy: false

    // Bit 4 means the firmware chooses the actual thresholds.
    readonly property bool firmwareManaged: (settingsSupported & 4) !== 0
    // Bit 2 means a charge end threshold is available.
    readonly property bool endThresholdSupported: (settingsSupported & 2) !== 0 && endThreshold > 0

    function refresh(): void {
        if (enumerateProc.running || propsProc.running)
            return;
        enumerateProc.running = true;
    }

    function setEnabled(value: bool): void {
        if (!devicePath || setProc.running)
            return;

        // Optimistic update so the switch responds immediately.
        enabled = value;
        busy = true;

        setProc.command = ["busctl", "call", "org.freedesktop.UPower", devicePath, "org.freedesktop.UPower.Device", "EnableChargeThreshold", "b", value ? "true" : "false"];
        setProc.running = true;
    }

    function propertyValue(lines: var, index: int): string {
        const parts = (lines[index] ?? "").trim().split(" ");
        return parts.length > 1 ? parts[1] : "";
    }

    function boolValue(lines: var, index: int): bool {
        return propertyValue(lines, index) === "true";
    }

    function intValue(lines: var, index: int): int {
        return parseInt(propertyValue(lines, index), 10) || 0;
    }

    Process {
        id: enumerateProc

        command: ["upower", "-e"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(line => line.length > 0);
                const path = lines.find(line => line.includes("battery_"));

                if (!path) {
                    root.devicePath = "";
                    root.supported = false;
                    return;
                }

                root.devicePath = path.trim();
                propsProc.command = ["busctl", "get-property", "org.freedesktop.UPower", root.devicePath, "org.freedesktop.UPower.Device", "ChargeThresholdSupported", "ChargeThresholdEnabled", "ChargeThresholdSettingsSupported", "ChargeStartThreshold", "ChargeEndThreshold"];
                propsProc.running = true;
            }
        }
    }

    Process {
        id: propsProc

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length < 5) {
                    root.supported = false;
                    return;
                }

                root.supported = root.boolValue(lines, 0);
                root.enabled = root.boolValue(lines, 1);
                root.settingsSupported = root.intValue(lines, 2);
                root.startThreshold = root.intValue(lines, 3);
                root.endThreshold = root.intValue(lines, 4);
            }
        }
    }

    Process {
        id: setProc

        onExited: exitCode => {
            root.busy = false;
            if (exitCode !== 0)
                console.warn("ChargeThreshold: EnableChargeThreshold failed with exit code", exitCode);
            root.refresh();
        }
    }
}
