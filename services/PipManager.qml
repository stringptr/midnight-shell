pragma Singleton

import QtQuick
import QtQml
import Quickshell
import qs.services
import Caelestia.Config

Singleton {
    id: root

    property var settings: GlobalConfig.services
    property int lastPipX: -1
    property int lastPipY: -1
    property double lastPipMoveTime: 0
    property string tempPipPosition: ""
    property string lastPipMonitor: ""
    property string currentPipAddress: ""

    Timer {
        id: updateDebouncer
        interval: 100 // Wait for Wayland exclusive zone & QML bindings to settle
        running: false
        repeat: false
        onTriggered: root.checkPip()
    }

    Connections {
        target: Niri
        function onWindowChanged(): void {
            updateDebouncer.restart();
        }
        function onWindowsChanged(): void {
            updateDebouncer.restart();
        }
    }

    // TODO: Niri monitor change tracking
    // Instantiator {
    //     model: Niri.outputs
    //     Connections {
    //         target: modelData
    //         function onLastIpcObjectChanged(): void {
    //             updateDebouncer.restart();
    //         }
    //     }
    // }

    Connections {
        target: GlobalConfig.services
        function onPipPositionChanged(): void {
            root.tempPipPosition = ""; // Reset temporary override on explicit setting change
            root.lastPipMoveTime = Date.now(); // Block drag-detection from falsely re-triggering
            root.checkPip();
        }
        function onPipFollowFocusChanged(): void {
            root.lastPipMoveTime = Date.now();
            root.checkPip();
        }
        function onPipPausedChanged(): void {
            if (!GlobalConfig.services.pipPaused) {
                root.checkPip();
            }
        }
    }

    Connections {
        target: GlobalConfig.bar
        function onPositionChanged(): void {
            updateDebouncer.restart();
        }
    }

    Connections {
        target: GlobalConfig.border
        function onThicknessChanged(): void {
            updateDebouncer.restart();
        }
    }

    function checkPip(): void {
        if (GlobalConfig.services.pipPaused) return;

        let foundPip = false;
        const toplevels = Niri.windows;
        for (let i = 0; i < toplevels.length; i++) {
            const t = toplevels[i];
            if (t && t.title && t.title.match(/Picture[- ]in[- ][Pp]icture/)) {
                root.movePip(t);
                foundPip = true;
            }
        }
        
        if (!foundPip) {
            root.currentPipAddress = "";
            root.lastPipX = -1;
            root.lastPipY = -1;
            root.tempPipPosition = "";
        }
    }

    function movePip(t): void {
        if (GlobalConfig.services.pipPaused) return;

        const activeTop = Niri.focusedWindow;
        if (activeTop && activeTop.id === t.id) {
            return; // Pause auto-alignment while the user is interacting with the window!
        }

        const addr = "0x" + t.id;
        
        if (root.currentPipAddress !== addr) {
            root.lastPipX = -1;
            root.lastPipY = -1;
            root.tempPipPosition = "";
            root.currentPipAddress = addr;
        }

        let output = Niri.outputs[Niri.focusedMonitorName];

        if (GlobalConfig.services.pipFollowFocus) {
            output = Niri.outputs[Niri.focusedMonitorName];
        }

        if (!output) return;

        if (root.lastPipMonitor !== output.name) {
            root.tempPipPosition = "";
            root.lastPipMonitor = output.name;
        }

        const transform = output.transform || 0;
        const isVertical = (transform % 2 !== 0);

        const rawWidth = output.mode?.width ?? 1920;
        const rawHeight = output.mode?.height ?? 1080;

        const monitor_width = (isVertical ? rawHeight : rawWidth) / (output.scale ?? 1);
        const monitor_height = (isVertical ? rawWidth : rawHeight) / (output.scale ?? 1);

        const sizeX = t.layout?.window_size?.[0] ?? 0;
        const sizeY = t.layout?.window_size?.[1] ?? 0;

        const currentX = null; // TODO: Niri does not expose absolute window position
        const currentY = null;

        if (currentX !== null && currentY !== null && root.lastPipX !== -1 && root.lastPipY !== -1 && (Date.now() - root.lastPipMoveTime > 1000)) {
            const diffX = Math.abs(currentX - root.lastPipX);
            const diffY = Math.abs(currentY - root.lastPipY);

            if (diffX > 100 || diffY > 100) {
                const relX = currentX - (output.location?.x ?? 0);
                const relY = currentY - (output.location?.y ?? 0);

                const centerX = relX + sizeX / 2;
                const centerY = relY + sizeY / 2;

                let newPos = "";
                if (centerY < monitor_height / 3) newPos += "top";
                else if (centerY > monitor_height * 2 / 3) newPos += "bottom";
                else newPos += "middle";

                if (centerX < monitor_width / 3) newPos += " left";
                else if (centerX > monitor_width * 2 / 3) newPos += " right";
                else newPos += " center";

                root.tempPipPosition = newPos.trim();
            }
        }

        const baseSize = Math.min(monitor_width, monitor_height) / 4;
        const effectiveSizeY = sizeY > 0 ? sizeY : baseSize;
        const effectiveSizeX = sizeX > 0 ? sizeX : (effectiveSizeY * 16 / 9);

        const scale_factor = baseSize / effectiveSizeY;
        const target_width = effectiveSizeX * scale_factor;
        const target_height = effectiveSizeY * scale_factor;

        const x_resize = Math.floor(Math.max(200, target_width));
        const y_resize = Math.floor(Math.max(150, target_height));

        const offset = Math.min(monitor_width, monitor_height) * 0.03;

        const bPos = GlobalConfig.bar.position;

        let res_left = 0;
        let res_top = 0;
        let res_right = 0;
        let res_bottom = 0;

        let barSize = 42;
        if (typeof Tokens !== "undefined" && typeof GlobalConfig !== "undefined") {
            const padding = Math.max(GlobalConfig.appearance.padding.small, GlobalConfig.border.thickness);
            barSize = Tokens.forScreen(output.name).sizes.bar.innerWidth + padding * 2;
        }

        if (bPos === "left") res_left += barSize;
        else if (bPos === "right") res_right += barSize;
        else if (bPos === "top") res_top += barSize;
        else if (bPos === "bottom") res_bottom += barSize;

        const avail_w = monitor_width - res_left - res_right - x_resize;
        const avail_h = monitor_height - res_top - res_bottom - y_resize;

        let base_x = (output.location?.x ?? 0) + res_left;
        let base_y = (output.location?.y ?? 0) + res_top;

        const pos = root.tempPipPosition || GlobalConfig.services.pipPosition || "";

        if (pos.includes("center")) {
            base_x += avail_w / 2;
        } else if (pos.includes("right")) {
            base_x += avail_w - offset;
        } else {
            base_x += offset; // left
        }

        if (pos.includes("middle")) {
            base_y += avail_h / 2;
        } else if (pos.includes("bottom")) {
            base_y += avail_h - offset;
        } else {
            base_y += offset; // top
        }

        const move_x = Math.floor(base_x);
        const move_y = Math.floor(base_y);

        root.lastPipX = move_x;
        root.lastPipY = move_y;
        root.lastPipMoveTime = Date.now();

        // TODO: Niri has no resizewindowpixel/movewindowpixel IPC
        // Basic PiP positioning not yet supported in Niri
        console.log("PipManager: pixel-perfect PiP positioning not yet supported in Niri");
    }
}
