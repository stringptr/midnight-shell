pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Thin integration with the external sunsetr daemon (https://github.com/psi4j/sunsetr).
//
// The shell never starts the sunsetr daemon: it is expected to already be
// running (systemd user service / compositor autostart). We mirror its live
// state from the event socket and drive it via the `sunsetr` CLI.
//
// The OSD's icon tap toggles the manual night light override on or off. The
// automatic schedule is selected from Settings. The two manual presets are
// created from the base config's night/day values when this service starts, but
// only if the user has not defined them yet.
Singleton {
    id: root

    // Preset directories under ~/.config/sunsetr/presets/. Edit these if you
    // name your presets differently. "auto" always maps to `sunsetr preset default`.
    readonly property string onPreset: "night"
    readonly property string offPreset: "day"

    // Neutral daylight temperature; at or above this the warm filter is considered off.
    readonly property int neutralTemp: 6500

    property bool available: false
    readonly property bool running: eventSocket.connected
    property bool presetsChecked: false
    property bool presetsReady: false

    // Live state mirrored from sunsetr.
    property string activePreset: "default"
    property string period: "day"
    property string state: "stable"
    property int temperature: neutralTemp
    property real gamma: 100

    // "auto" | "on" | "off", derived from which preset sunsetr reports active.
    readonly property string mode: activePreset === onPreset ? "on" : activePreset === offPreset ? "off" : "auto"

    // True when the warm filter is actually engaged, regardless of how we got there
    // (a forced preset, or the auto schedule currently being in its night window).
    readonly property bool active: temperature < neutralTemp

    readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/sunsetr-events.sock`

    readonly property string presetScript: `
config_home="$XDG_CONFIG_HOME"
[ -n "$config_home" ] || config_home="$HOME/.config"
base="$config_home/sunsetr/sunsetr.toml"
presets="$config_home/sunsetr/presets"
on_name="$1"
off_name="$2"

read_value() {
    [ -f "$base" ] || return 0
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$base" | head -n 1 | sed "s/[[:space:]]*#.*$//"
}

write_preset() {
    [ -f "$1" ] && return
    printf 'transition_mode = "static"\\nstatic_temp = %s\\nstatic_gamma = %s\\n' "$2" "$3" > "$1"
}

night_temp=$(read_value night_temp)
night_gamma=$(read_value night_gamma)
day_temp=$(read_value day_temp)
day_gamma=$(read_value day_gamma)

[ -n "$night_temp" ] || night_temp=3300
[ -n "$night_gamma" ] || night_gamma=90
[ -n "$day_temp" ] || day_temp=6500
[ -n "$day_gamma" ] || day_gamma=100

mkdir -p "$presets/$on_name" "$presets/$off_name"
write_preset "$presets/$on_name/sunsetr.toml" "$night_temp" "$night_gamma"
write_preset "$presets/$off_name/sunsetr.toml" "$day_temp" "$day_gamma"
`

    function setMode(newMode: string): void {
        if (newMode === "auto") {
            if (activePreset !== "default")
                setPreset("default");
        } else if (newMode === "on") {
            if (activePreset !== onPreset)
                setPreset(onPreset);
        } else if (newMode === "off") {
            if (activePreset !== offPreset)
                setPreset(offPreset);
        }
    }

    // The icon on the brightness OSD only toggles the manual override. The
    // automatic schedule is left to the Settings selector.
    function toggle(): void {
        setMode(active ? "off" : "on");
    }

    function setPreset(name: string): void {
        if (!available)
            return;
        Quickshell.execDetached(["sunsetr", "preset", name]);
    }

    function ensurePresets(): void {
        if (presetsChecked)
            return;
        presetsChecked = true;
        presetProc.running = true;
    }

    function applyStatus(json: string): void {
        let o;
        try {
            o = JSON.parse(json);
        } catch (e) {
            return;
        }
        activePreset = o.active_preset ?? activePreset;
        period = o.period ?? period;
        state = o.state ?? state;
        temperature = Math.round(o.current_temp ?? temperature);
        gamma = o.current_gamma ?? gamma;
    }

    function handleEvent(line: string): void {
        const trimmed = line.trim();
        if (trimmed.length === 0)
            return;

        let o;
        try {
            o = JSON.parse(trimmed);
        } catch (e) {
            return;
        }

        switch (o.event_type) {
        case "state_applied":
            activePreset = o.active_preset ?? activePreset;
            period = o.period ?? period;
            state = o.state ?? state;
            temperature = Math.round(o.current_temp ?? temperature);
            gamma = o.current_gamma ?? gamma;
            break;
        case "period_changed":
            period = o.to_period ?? period;
            break;
        case "preset_changed":
            activePreset = o.to_preset ?? "default";
            period = o.target_period ?? period;
            temperature = Math.round(o.target_temp ?? temperature);
            gamma = o.target_gamma ?? gamma;
            break;
        case "config_changed":
            period = o.target_period ?? period;
            temperature = Math.round(o.target_temp ?? temperature);
            gamma = o.target_gamma ?? gamma;
            break;
        }
    }

    function requestConnection(): void {
        eventSocket.connected = false;
        eventSocket.connected = true;
    }

    onAvailableChanged: {
        if (available) {
            ensurePresets();
            requestConnection();
        }
    }

    IpcHandler {
        target: "sunsetr"

        function setMode(mode: string): void {
            root.setMode(mode);
        }

        function toggle(): void {
            root.toggle();
        }

        function getMode(): string {
            return root.mode;
        }
    }

    Process {
        id: availProc

        running: true
        command: ["sh", "-c", "command -v sunsetr >/dev/null"]

        onExited: exitCode => root.available = exitCode === 0 // qmllint disable signal-handler-parameters
    }

    Process {
        id: presetProc

        command: ["sh", "-c", root.presetScript, "sunsetr-presets", root.onPreset, root.offPreset]
        onExited: exitCode => root.presetsReady = exitCode === 0 // qmllint disable signal-handler-parameters
    }

    // Seed full state on connect: the event socket only streams changes, not a snapshot.
    Process {
        id: statusProc

        command: ["sunsetr", "status", "--json"]

        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t.length > 0)
                    root.applyStatus(t);
            }
        }
    }

    Socket {
        id: eventSocket

        path: root.socketPath
        parser: SplitParser {
            onRead: data => root.handleEvent(data) // qmllint disable signal-handler-parameters
        }

        onConnectedChanged: {
            if (eventSocket.connected)
                statusProc.running = true;
        }
    }

    // Retry the socket while sunsetr is installed but not (yet) reachable, so we
    // pick it up if it starts after the shell. connected reads as the actual state,
    // so this only polls while we're genuinely disconnected.
    Timer {
        interval: 4000
        repeat: true
        running: root.available && !eventSocket.connected

        onTriggered: root.requestConnection()
    }
}
