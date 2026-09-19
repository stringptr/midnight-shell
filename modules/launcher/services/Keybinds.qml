pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Internal
import qs.services

QtObject {
    id: root

    property var keybinds: []
    property bool initialized: false

    signal loaded

    readonly property string configPath: Quickshell.env("HOME") + "/.config/niri/config.kdl"
    readonly property string scriptsDir: Quickshell.shellDir + "/modules/keybinds/scripts"

    property FileView configFileView: FileView {
        path: root.configPath
        onContentChanged: root.reload()
    }

    property Process parserProcess: Process {
        running: false
        command: ["sh", "-c", `python3 '${root.scriptsDir}/expand.py' < '${root.configPath}' 2>/dev/null | python3 '${root.scriptsDir}/extract_binds.py' 2>/dev/null | python3 '${root.scriptsDir}/pretty_print_binds.py' 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (Array.isArray(parsed)) {
                        root.keybinds = parsed;
                        root.initialized = true;
                        root.loaded();
                    }
                } catch (e) {
                    console.error("Failed to parse niri keybinds: " + e);
                }
            }
        }
        onRunningChanged: {
            if (!running && !root.initialized) {
                root.keybinds = [];
                root.initialized = true;
                root.loaded();
            }
        }
    }

    function loadKeybinds(): void {
        if (initialized && keybinds.length > 0)
            return;
        keybinds = [];
        initialized = false;
        parserProcess.running = true;
    }

    function reload(): void {
        keybinds = [];
        initialized = false;
        if (!parserProcess.running)
            parserProcess.running = true;
    }

    function query(searchText): var {
        if (!searchText)
            return keybinds;

        const queryText = searchText.toLowerCase().trim();
        return keybinds.filter(k =>
            (k.key && k.key.toLowerCase().includes(queryText)) ||
            (k.action && k.action.toLowerCase().includes(queryText))
        );
    }

    function execute(item): void {
        if (!item)
            return;

        const action = (item.action || "").toLowerCase().trim();
        if (!action)
            return;

        // Map human-readable actions to Niri IPC calls
        if (action.includes("close window") || action.includes("close-window")) {
            Niri.closeFocusedWindow();
        } else if (action.includes("toggle floating") || action.includes("toggle-window-floating")) {
            Niri.toggleWindowFloating();
        } else if (action.includes("toggle fullscreen") || action.includes("fullscreen")) {
            Niri.toggleFullscreen();
        } else if (action.includes("toggle maximize") || action.includes("maximize")) {
            Niri.toggleMaximize();
        } else if (action.includes("toggle overview") || action.includes("overview")) {
            Niri.toggleOverview();
        } else if (action.includes("center window")) {
            Niri.centerWindow();
        } else if (action.includes("focus column left")) {
            NiriIpc.action("focus-column-left");
        } else if (action.includes("focus column right")) {
            NiriIpc.action("focus-column-right");
        } else if (action.includes("focus window up")) {
            NiriIpc.action("focus-window-up");
        } else if (action.includes("focus window down")) {
            NiriIpc.action("focus-window-down");
        } else if (action.includes("focus workspace up")) {
            Niri.switchToWorkspaceUpDown("up");
        } else if (action.includes("focus workspace down")) {
            Niri.switchToWorkspaceUpDown("down");
        } else if (action.includes("move column left")) {
            NiriIpc.action("move-column-left");
        } else if (action.includes("move column right")) {
            NiriIpc.action("move-column-right");
        } else if (action.includes("move window up")) {
            NiriIpc.action("move-window-up");
        } else if (action.includes("move window down")) {
            NiriIpc.action("move-window-down");
        } else if (action.includes("spawn")) {
            // Extract the command after "spawn " if present
            const spawnMatch = action.match(/spawn\s+(.+)/);
            if (spawnMatch) {
                Quickshell.execDetached(["sh", "-c", spawnMatch[1]]);
            }
        } else {
            console.log("Keybinds: unhandled action:", item.action);
        }
    }

    Component.onCompleted: {
        loadKeybinds();
    }
}
