pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: root

    property bool usingAsusctl: false
    property int asusProfile: PowerProfile.Balanced
    readonly property int profile: usingAsusctl ? asusProfile : PowerProfiles.profile

    function setProfile(p: int): void {
        if (!usingAsusctl) {
            PowerProfiles.profile = p;
            return;
        }

        // Optimistic, so the battery popout pill moves immediately.
        asusProfile = p;

        setProc.pending = p;
        setProc.retry = false;
        setProc.command = ["asusctl", "profile", "set", profileName(p, true)];
        if (setProc.running)
            setProc.running = false;
        setProc.running = true;
    }

    // Re-read the profile from asusctl; the battery popout calls this on open.
    function fetchProfile(): void {
        if (!usingAsusctl || getProc.running || setProc.running)
            return;

        getProc.retry = false;
        getProc.command = ["asusctl", "profile", "get"];
        getProc.running = true;
    }

    function profileName(p: int, capitalized: bool): string {
        let name = "balanced";
        if (p === PowerProfile.PowerSaver)
            name = "quiet";
        else if (p === PowerProfile.Performance)
            name = "performance";
        return capitalized ? name.charAt(0).toUpperCase() + name.slice(1) : name;
    }

    // Returns -1 when the output contains no known profile name.
    function parseProfile(output: string): int {
        const match = output.match(/\b(low-?power|quiet|balanced|performance|custom)\b/i);
        if (!match)
            return -1;

        const name = match[1].toLowerCase();
        if (name === "performance")
            return PowerProfile.Performance;
        if (name === "quiet" || name.startsWith("low"))
            return PowerProfile.PowerSaver;
        return PowerProfile.Balanced;
    }

    Process {
        id: detectProc

        running: true
        command: ["sh", "-c", "command -v asusctl >/dev/null"]

        onExited: exitCode => root.usingAsusctl = exitCode === 0 // qmllint disable signal-handler-parameters
    }

    Process {
        id: getProc

        property bool retry: false

        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = root.parseProfile(text);
                if (parsed !== -1)
                    root.asusProfile = parsed;
            }
        }

        onExited: exitCode => { // qmllint disable signal-handler-parameters
            if (exitCode === 0)
                return;

            if (!getProc.retry) {
                // Legacy syntax: asusctl profile --profile-get
                getProc.retry = true;
                getProc.command = ["asusctl", "profile", "--profile-get"];
                getProc.running = true;
            } else {
                // asusctl exists but its profile interface is unusable.
                root.usingAsusctl = false;
            }
        }
    }

    Process {
        id: setProc

        property int pending: PowerProfile.Balanced
        property bool retry: false

        onExited: exitCode => { // qmllint disable signal-handler-parameters
            if (exitCode === 0)
                return;

            if (!setProc.retry) {
                // Legacy syntax: asusctl profile -p <profile>
                setProc.retry = true;
                setProc.command = ["asusctl", "profile", "-p", root.profileName(setProc.pending, false)];
                setProc.running = true;
            } else {
                PowerProfiles.profile = setProc.pending;
            }
        }
    }
}
