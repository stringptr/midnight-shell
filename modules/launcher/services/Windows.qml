pragma Singleton

import QtQuick
import Caelestia.Config

QtObject {
    id: root

    property var items: []

    function reload(): void {
        updateItems();
    }

    function updateItems(): void {
        const windows = [];
        for (const client of Hypr.toplevels.values) {
            const ipc = client.lastIpcObject;
            windows.push({
                id: client.id,
                title: client.title || "",
                class: ipc?.class || ipc?.app_id || "",
                workspace: client.workspace?.name || "",
                workspace_id: client.workspace_id ?? 0,
                monitor: client.monitor?.name || "",
                wayland: client.wayland,
                size: ipc?.size || [0, 0],
                at: ipc?.at || [0, 0],
                mapped: ipc?.mapped ?? true,
                hidden: ipc?.hidden ?? false,
                lastIpcObject: ipc
            });
        }
        items = windows;
    }

    function query(search: string): var {
        let results = items;
        if (GlobalConfig.launcher.windowSwitcherActiveWorkspaceOnly) {
            // TODO: Niri workspace filtering
            const activeWs = Hypr.activeWsId;
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
        // TODO: Niri focus by window ID
        console.log("Windows.focusWindow: not yet supported in Niri, id:", id);
    }

    Component.onCompleted: {
        updateItems();
        // TODO: connect to Niri window change signals
    }
}
