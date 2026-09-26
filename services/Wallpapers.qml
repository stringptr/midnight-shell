pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    // When an external colour tool (matugen/wallust) is enabled, the shell must
    // never generate or apply colours itself
    readonly property bool externalColours: GlobalConfig.scheme.useMatugen || GlobalConfig.scheme.useWallust
    readonly property list<string> schemeArg: externalColours ? ["--no-scheme"] : []
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")

    property bool showPreview: false
    property bool enableAnimation: true
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear

    readonly property list<string> validVideoExtensions: ["mp4", "webm", "mkv"]
    property string wallpaperMode: "static"
    property string cacheBuster: ""
    property string rollbackPath: ""
    property string rollbackMode: ""
    property bool isTrackingRollback: false
    
    // Track and restore the last used wallpaper per mode using low-overhead execution
    property string lastStatic: ""
    property string lastAnimated: ""

    property var _hashCache: ({})

    Timer {
        id: colorReleaseTimer
        interval: 180 
        repeat: false
        onTriggered: {
            // Safety check: only clear the preview if no new lock has been engaged
            if (!previewColourLock && pendingPreviewClear) {
                Colours.showPreview = false;
                pendingPreviewClear = false;
            }
        }
    }

    function djb2_hash(s) {
        if (!s) return "0";
        if (_hashCache[s] !== undefined) return _hashCache[s];

        let h = 5381;
        for (let i = 0; i < s.length; i++) {
            h = ((h << 5) + h) + s.charCodeAt(i);
            h |= 0;
        }
        const res = (h >>> 0).toString(10);
        _hashCache[s] = res;
        return res;
    }

    function getWallpaperThumb(path, buster) {
        let clean = String(path || "").split(/[?#]/)[0];
        if (clean.indexOf("file://") === 0) clean = clean.substring(7);
        let b = buster !== undefined ? buster : cacheBuster;
        return Paths.cache + "/videothumbs/" + djb2_hash(clean) + ".jpg" + (b ? "?v=" + b : "");
    }

    function isVideo(path: string): bool {
        if (!path) return false;
        const clean = String(path).split(/[?#]/)[0].toLowerCase();
        const index = clean.lastIndexOf(".");
        const ext = index >= 0 ? clean.slice(index + 1) : "";
        return validVideoExtensions.includes(ext);
    }

    readonly property var categories: {
        let dummy = root.list;
        const baseDir = Paths.wallsdir;
        let cats = [];
        for (let i = 0; i < root.list.length; i++) {
            let p = root.list[i].parentDir;
            if (p.includes("steamapps/workshop/content/431960")) {
                let cat = "Wallpaper Engine";
                if (!cats.includes(cat)) cats.push(cat);
                continue;
            }
            if (p !== baseDir) {
                let cat = p.slice(baseDir.length + 1);
                if (cat.includes("/")) cat = cat.slice(0, cat.indexOf("/"));
                if (!cats.includes(cat)) cats.push(cat);
            }
        }
        return ["Main"].concat(cats.sort());
    }

    readonly property var grouped: {
        let dummy = root.list;
        const baseDir = Paths.wallsdir;
        let grp = { "Main": [] };
        for (let i = 0; i < root.list.length; i++) {
            let w = root.list[i];
            let p = w.parentDir;
            if (p.includes("steamapps/workshop/content/431960")) {
                let cat = "Wallpaper Engine";
                if (!grp[cat]) grp[cat] = [];
                grp[cat].push(w);
                continue;
            }
            if (p === baseDir) {
                grp["Main"].push(w);
            } else {
                let cat = p.slice(baseDir.length + 1);
                if (cat.includes("/")) cat = cat.slice(0, cat.indexOf("/"));
                if (!grp[cat]) grp[cat] = [];
                grp[cat].push(w);
            }
        }
        return grp;
    }

    function getCategoryFor(w: FileSystemEntry): string {
        if (w.parentDir.includes("steamapps/workshop/content/431960")) {
            return "Wallpaper Engine";
        }
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setWallpaperMode(mode) {
        wallpaperMode = mode;
    }

    function applyWallpaper(path: string): void {
        if (!path) return;
        Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...smartArg, ...schemeArg]);
        if (externalColours) runExternalColours(path, "");
    }

    // Runs the enabled external colour tools for a wallpaper. modeOverride
    // ("light"/"dark") replaces the configured matugen mode; wallust only gets
    // it as a palette when matugen is not handling the mode.
    function runExternalColours(path: string, modeOverride: string): void {
        if (!path) return;
        const img = getThumbnailPath(path);
        const cfg = GlobalConfig.scheme;

        if (cfg.useMatugen) {
            const matugenCmd = ["matugen", "image", img];
            if (cfg.matugenConfigPath) matugenCmd.push("-c", cfg.matugenConfigPath);
            if (cfg.matugenType) matugenCmd.push("-t", cfg.matugenType);
            const mode = modeOverride || cfg.matugenMode;
            if (mode) matugenCmd.push("-m", mode);
            if (cfg.matugenContrast) matugenCmd.push("--contrast", cfg.matugenContrast);
            if (cfg.matugenSourceColorIndex) matugenCmd.push("--source-color-index", cfg.matugenSourceColorIndex);
            if (cfg.matugenPrefix) matugenCmd.push("-p", cfg.matugenPrefix);
            if (cfg.matugenOpacity) matugenCmd.push("--opacity", cfg.matugenOpacity);
            Quickshell.execDetached(matugenCmd);
        }

        if (cfg.useWallust) {
            const wallustCmd = ["wallust", "run", img];
            if (cfg.wallustConfigPath) wallustCmd.push("-C", cfg.wallustConfigPath);
            if (cfg.wallustBackend) wallustCmd.push("-b", cfg.wallustBackend);
            if (cfg.wallustColorspace) wallustCmd.push("-c", cfg.wallustColorspace);
            // Mode override wins over the configured palette (-p can only be given once)
            if (modeOverride && !cfg.useMatugen) {
                wallustCmd.push("-p", modeOverride === "light" ? "light" : "dark");
            } else if (cfg.wallustPalette) {
                wallustCmd.push("-p", cfg.wallustPalette);
            }
            // --dynamic-threshold conflicts with -t
            if (cfg.wallustDynamicThreshold) {
                wallustCmd.push("--dynamic-threshold");
            } else if (cfg.wallustThreshold) {
                wallustCmd.push("-t", cfg.wallustThreshold);
            }
            if (cfg.wallustSaturation) wallustCmd.push("--saturation", cfg.wallustSaturation);
            if (cfg.wallustAlpha) wallustCmd.push("-a", cfg.wallustAlpha);
            if (cfg.wallustCheckContrast) wallustCmd.push("-k");
            if (cfg.wallustSkipSequences) wallustCmd.push("-s");
            if (cfg.wallustSkipTemplates) wallustCmd.push("-T");
            Quickshell.execDetached(wallustCmd);
        }
    }

    // Regenerate colours after a backend toggle change: runs the enabled tools
    // when external, otherwise restores caelestia's own colours
    function refreshColours(): void {
        applyWallpaper(actualCurrent || fallback);
    }

    function captureRollbackState() {
        if (!isTrackingRollback) {
            rollbackPath = actualCurrent;
            rollbackMode = wallpaperMode;
            isTrackingRollback = true;
        }
    }

    onWallpaperModeChanged: {
        captureRollbackState();
        
        const target = wallpaperMode === "animated" ? lastAnimated : lastStatic;

        if (target !== "") {
            actualCurrent = target;
            if (showPreview) {
                previewPath = target;
                if (!externalColours && String(Colours.scheme).startsWith("dynamic")) {
                    if (!getPreviewColoursProc.running) {
                        getPreviewColoursProc.startFor(target);
                    }
                }
            } else {
                applyWallpaper(target);
            }
        }
    }

    onEnableAnimationChanged: {
        Quickshell.execDetached(["sh", "-c", "mkdir -p '" + Paths.state + "/wallpaper' && echo '" + (enableAnimation ? "1" : "0") + "' > '" + Paths.state + "/wallpaper/enable_animation.txt'"]);
    }

    function setRandom(): void {
        if (randomProc.running) randomProc.running = false;
        randomProc.command = ["caelestia", "wallpaper", "-r", ...smartArg, ...schemeArg];
        randomProc.running = true;
    }

    // Runs the random wallpaper switch so external tools can be started once
    // the new wallpaper path is known (path.txt is written by the CLI)
    Process {
        id: randomProc

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || !root.externalColours) return;
            const wall = CUtils.readFile(root.currentNamePath).trim();
            if (wall) root.runExternalColours(wall, "");
        }
    }

    function setWallpaper(path: string): void {
        let clean = String(path || "").split(/[?#]/)[0];
        if (clean.indexOf("file://") === 0) clean = clean.substring(7);
        if (!clean) return;

        let targetPath = clean;
        if (path.endsWith("project.json")) {
            let content = CUtils.readFile(path);
            try {
                let json = JSON.parse(content);
                if (json.preview) {
                    targetPath = path.substring(0, path.length - 12) + json.preview;
                }
            } catch (e) {
                console.warn("Failed to parse project.json:", e);
            }
        }

        actualCurrent = targetPath;
        isTrackingRollback = false;

        previewColourLock = true;
        pendingPreviewClear = false;

        if (isVideo(targetPath)) {
            lastAnimated = targetPath;
            wallpaperMode = "animated";
            Quickshell.execDetached(["sh", "-c", "mkdir -p '" + Paths.state + "/wallpaper' && echo '" + targetPath + "' > '" + Paths.state + "/wallpaper/last_animated.txt'"]);
        } else {
            lastStatic = targetPath;
            wallpaperMode = "static";
            Quickshell.execDetached(["sh", "-c", "mkdir -p '" + Paths.state + "/wallpaper' && echo '" + targetPath + "' > '" + Paths.state + "/wallpaper/last_static.txt'"]);
        }

        stopPreview();

        applyWallpaper(targetPath);
    }

    function preview(path: string): void {
        captureRollbackState();

        let clean = String(path || "").split(/[?#]/)[0];
        if (clean.indexOf("file://") === 0) clean = clean.substring(7);
        if (!clean) return;

        if (previewPath === clean && showPreview) return;

        previewPath = clean;
        showPreview = true;

        if (!externalColours && String(Colours.scheme).startsWith("dynamic")) {
            if (!getPreviewColoursProc.running) {
                getPreviewColoursProc.startFor(clean);
            }
        }
    }

    function stopPreview(): void {
        showPreview = false;
        
        if (getPreviewColoursProc.running) {
            getPreviewColoursProc.running = false;
        }

        if (isTrackingRollback) {
            wallpaperMode = rollbackMode;
            actualCurrent = rollbackPath;
            isTrackingRollback = false;
            
            applyWallpaper(rollbackPath);
        }

        if (previewColourLock) {
            pendingPreviewClear = true;
        } else {
            Colours.showPreview = false;
            pendingPreviewClear = false;
        }
    }

    function getThumbnailPath(path: string): string {
        if (path.endsWith("project.json")) {
            let content = CUtils.readFile(path);
            try {
                let json = JSON.parse(content);
                if (json.preview) {
                    return path.substring(0, path.length - 12) + json.preview;
                }
            } catch (e) {
                console.warn("Failed to parse project.json:", e);
            }
            return path;
        }
        if (isVideo(path)) {
            return getWallpaperThumb(path);
        }
        return path;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear) {
            colorReleaseTimer.restart();
        }
    }

    list: wallpapers.entries
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: `${Paths.state}/wallpaper/enable_animation.txt`
        printErrors: false
        onLoaded: {
            const val = text().trim();
            if (val === "0") root.enableAnimation = false;
            else if (val === "1") root.enableAnimation = true;
        }
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg, ...root.schemeArg]);
            }
            root.actualCurrent = wall;
            root.previewColourLock = false;

            if (root.isVideo(root.actualCurrent)) {
                wallpaperMode = "animated";
                if (!root.lastAnimated) root.lastAnimated = wall;
            } else {
                wallpaperMode = "static";
                if (!root.lastStatic) root.lastStatic = wall;
            }
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg, ...root.schemeArg]);
        }
    }

    FileView {
        path: `${Paths.state}/wallpaper/last_static.txt`
        printErrors: false
        onLoaded: {
            const val = text().trim();
            if (val) root.lastStatic = val;
        }
    }

    FileView {
        path: `${Paths.state}/wallpaper/last_animated.txt`
        printErrors: false
        onLoaded: {
            const val = text().trim();
            if (val) root.lastAnimated = val;
        }
    }

    function updateCombinedList() {
        let arr = [];
        for (let i = 0; i < wallpapers.entries.length; i++) {
            arr.push(wallpapers.entries[i]);
        }
        for (let i = 0; i < weWallpapers.entries.length; i++) {
            arr.push(weWallpapers.entries[i]);
        }
        root.list = arr;
    }

    property alias weVolume: weAdapter.volume
    property alias weSilent: weAdapter.silent
    
    Component.onCompleted: CUtils.mkdirp(Paths.state + "/wallpaper")

    FileView {
        id: weStore

        path: `${Paths.state}/wallpaper/wallpaper-engine.json`
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: weAdapter

            property real volume: 0.15
            property bool silent: false
        }
    }

    FileSystemModel {
        id: wallpapers
        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Files
        nameFilters: Array.from(Images.validImageExtensions).concat(Array.from(Images.validVideoExtensions)).map(e => `*.${e}`).concat(["project.json"])
        onEntriesChanged: root.updateCombinedList()
    }

    FileSystemModel {
        id: weWallpapers
        recursive: true
        path: Quickshell.env("HOME") + "/.local/share/Steam/steamapps/workshop/content/431960"
        filter: FileSystemModel.Files
        nameFilters: ["project.json"]
        onEntriesChanged: root.updateCombinedList()
    }

    Process {
        id: getPreviewColoursProc

        property string currentProcessingPath: ""

        command: ["caelestia", "wallpaper", "-p", currentProcessingPath, ...root.smartArg]

        function startFor(path) {
            if (!path || root.externalColours) return;
            currentProcessingPath = path;
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.showPreview) return;

                const raw = text ? text.trim() : "";
                if (raw) {
                    try {
                        JSON.parse(raw);
                        Colours.load(raw, true);
                        Colours.showPreview = true;
                    } catch (e) {
                        // Ignore incomplete or invalid output
                    }
                }

                if (root.showPreview && root.previewPath !== "" && root.previewPath !== getPreviewColoursProc.currentProcessingPath) {
                    getPreviewColoursProc.startFor(root.previewPath);
                }
            }
        }
    }

    property bool _refreshing: false
    property bool restoreWallpaperMode: false
    property var itemBusters: ({})

    FileView {
        path: "/tmp/caelestia_thumb_ready.txt"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const raw = text().trim();
            if (!raw) return;
            
            const lines = raw.split("\n");
            let busters = Object.assign({}, root.itemBusters);
            let changed = false;
            const now = Date.now().toString();

            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (line.indexOf("file://") === 0) line = line.substring(7);
                if (line && !busters[line]) {
                    busters[line] = now;
                    busters["file://" + line] = now;
                    changed = true;
                }
            }
            if (changed) {
                root.itemBusters = busters;
            }
        }
    }

    function refreshAnimatedThumbs() {
        if (_refreshing) return;
        itemBusters = {};
        _refreshing = true;
        _extractThumbsProc.running = true;
    }

    Process {
        id: _extractThumbsProc

        command: ["caelestia", "wallpaper", "--extract-thumbs"]
        onExited: (exitCode, exitStatus) => {
            root._refreshing = false;
            root.cacheBuster = Date.now().toString();
            root.restoreWallpaperMode = true;
        }
    }
}
