// Hyprland-to-Niri compatibility layer
// This file provides a thin delegation layer so that existing code referencing
// Hypr.* continues to work while the backend is now Niri IPC.
// TODO: Eventually migrate all callers to use Niri.* directly and remove this file.

pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config

Singleton {
    id: root

    // --- Core properties (delegated to Niri) ---
    // toplevels: provide array-like interface matching Hyprland.toplevels.values
    readonly property var toplevels: ({
        get values() { return Niri.windows; }
    })

    // workspaces: provide array-like interface matching Hyprland.workspaces.values
    readonly property var workspaces: ({
        get values() { return Niri.allWorkspaces; }
    })

    // monitors: provide array-like interface matching Hyprland.monitors.values
    readonly property var monitors: ({
        get values() {
            var result = [];
            var outputs = Niri.outputs;
            for (var name in outputs) {
                var o = outputs[name];
                result.push({
                    name: name,
                    width: o.active_mode?.resolution?.width ?? 0,
                    height: o.active_mode?.resolution?.height ?? 0,
                    scale: o.scale ?? 1,
                    x: o.position?.x ?? 0,
                    y: o.position?.y ?? 0,
                    transform: o.transform ?? 0
                });
            }
            return result;
        }
    })

    // Niri has no Lua scripting
    readonly property bool usingLua: false

    // Active window (Niri equivalent)
    readonly property var activeToplevel: Niri.focusedWindow?.id ? Niri.focusedWindow : null

    // Workspace and monitor focus
    readonly property var focusedWorkspace: {
        if (Niri.focusedWorkspaceIndex >= 0 && Niri.focusedWorkspaceIndex < Niri.allWorkspaces.length) {
            return Niri.allWorkspaces[Niri.focusedWorkspaceIndex];
        }
        return null;
    }

    readonly property var focusedMonitor: ({
        name: Niri.focusedMonitorName,
        lastIpcObject: ({
            specialWorkspace: { name: "" }
        })
    })

    readonly property int activeWsId: Niri.focusedWorkspaceId ?? 1

    // Keyboard state (delegated to Niri C++ IPC)
    readonly property bool capsLock: Niri.capsLock
    readonly property bool numLock: Niri.numLock
    readonly property string defaultKbLayout: Niri.defaultKbLayout
    readonly property string kbLayoutFull: {
        var arr = Niri.kbLayoutsArray;
        var idx = Niri.kbLayoutIndex;
        if (arr && idx >= 0 && idx < arr.length) return arr[idx];
        return "Unknown";
    }
    readonly property string kbLayout: Niri.kbLayout

    // HyprExtras removed — not needed for Niri
    // TODO: Remove all callers of Hypr.extras, Hypr.options, Hypr.devices

    property string lastSpecialWorkspace: ""

    signal configReloaded

    // Dispatch: translate common Hyprland commands to Niri actions
    function dispatch(request) {
        if (!request || typeof request !== "string") return;

        const parts = request.split(" ");
        const cmd = parts[0];

        if (cmd === "workspace") {
            const arg = parts[1];
            if (arg && !arg.startsWith("special:")) {
                const num = parseInt(arg);
                if (!isNaN(num)) {
                    Niri.switchToWorkspaceByNumber(num);
                } else {
                    Niri.switchToWorkspace(arg);
                }
            }
        } else if (cmd === "focuswindow") {
            // "focuswindow address:0x..." — not directly supported in Niri
            // TODO: implement window focus by address if needed
            console.warn("Hypr.dispatch: focuswindow by address not supported in Niri");
        } else if (cmd === "closewindow") {
            Niri.closeFocusedWindow();
        } else if (cmd === "togglespecialworkspace") {
            // Niri has no special workspaces
            // TODO: implement scratchpad/scratch equivalent
            console.warn("Hypr.dispatch: special workspaces not supported in Niri");
        } else if (cmd === "dpms" && parts[1] === "off") {
            Quickshell.execDetached(["niri", "msg", "action", "power-off-monitors"]);
        } else if (cmd === "dpms" && parts[1] === "on") {
            Quickshell.execDetached(["niri", "msg", "action", "power-on-monitors"]);
        } else {
            console.warn("Hypr.dispatch: unhandled command:", request);
        }
    }

    function cycleSpecialWorkspace(direction) {
        // Niri has no special workspaces
        // TODO: implement scratchpad/scratch equivalent
        console.warn("Hypr.cycleSpecialWorkspace: not supported in Niri");
    }

    function monitorNames() {
        return Object.keys(Niri.outputs);
    }

    function monitorFor(screen) {
        // Map a Quickshell screen to a Niri output-compatible object
        if (!screen) return null;
        const outputs = Niri.outputs;
        const name = screen.name || "";
        if (outputs[name]) {
            return {
                name: name,
                lastIpcObject: outputs[name],
                width: outputs[name].active_mode?.resolution?.width ?? 0,
                height: outputs[name].active_mode?.resolution?.height ?? 0,
                scale: outputs[name].scale ?? 1,
                x: outputs[name].position?.x ?? 0,
                y: outputs[name].position?.y ?? 0
            };
        }
        // Fallback: return first output
        for (var k in outputs) {
            return {
                name: k,
                lastIpcObject: outputs[k],
                width: outputs[k].active_mode?.resolution?.width ?? 0,
                height: outputs[k].active_mode?.resolution?.height ?? 0,
                scale: outputs[k].scale ?? 1,
                x: outputs[k].position?.x ?? 0,
                y: outputs[k].position?.y ?? 0
            };
        }
        return null;
    }

    function toplevelsForWs(ws) {
        return Niri.windows.filter(t => t.workspace_id === ws);
    }

    function isToplevelIgnored(toplevel) {
        if (!toplevel || !toplevel.app_id) return true;
        return false;
    }

    function reloadDynamicConfs() {
        // Niri does not need dynamic config reload for keyboard LED bindings
        // LED state is polled via sysfs in the C++ NiriIpc class
    }
}
