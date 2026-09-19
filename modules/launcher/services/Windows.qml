pragma Singleton

import QtQuick
import Caelestia.Config
import qs.services

QtObject {
    id: root

    property var items: []

    function reload(): void {
        updateItems();
    }

    function updateItems(): void {
        const windows = [];
        for (const win of Niri.windows) {
            windows.push({
                id: win.id,
                title: win.title || "",
                class: win.app_id || "",
                workspace_id: win.workspace_id ?? 0,
                monitor: win.output || "",
                is_focused: win.is_focused ?? false,
                is_fullscreen: win.is_fullscreen ?? false,
                is_maximized: win.is_maximized ?? false,
                is_floating: win.is_floating ?? false,
                // Stub fields for compatibility
                wayland: null,
                size: [0, 0],
                at: [0, 0],
                mapped: true,
                hidden: false,
                lastIpcObject: {
                    app_id: win.app_id,
                    class: win.app_id,
                    at: [0, 0],
                    size: [0, 0],
                    mapped: true,
                    hidden: false,
                    floating: win.is_floating ?? false,
                    pinned: false,
                    xwayland: false,
                    pid: 0,
                    fullscreen: win.is_fullscreen ? 1 : 0
                }
            });
        }
        items = windows;
    }

    function query(search: string): var {
        let results = items;
        if (GlobalConfig.launcher.windowSwitcherActiveWorkspaceOnly) {
            const activeWs = Niri.focusedWorkspaceId;
            if (activeWs) {
                results = results.filter(w => w.workspace_id === activeWs);
            }
        }
        
        if (!search)
            return results;
        const lower = search.toLowerCase();
        return results.filter(w => w.title.toLowerCase().includes(lower) || w.class.toLowerCase().includes(lower));
    }

    function focusWindow(id: int): void {
        Niri.focusWindow(id);
    }

    Component.onCompleted: {
        updateItems();
        Niri.windowOpenedOrChanged.connect(() => updateItems());
        Niri.windowClosed.connect(() => updateItems());
    }
}
