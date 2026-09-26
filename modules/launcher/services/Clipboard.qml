pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Images

QtObject {
    id: root

    property var items: []
    property bool _loaded: false
    property var _sortedCache: null

    readonly property string imageCacheDir: "/tmp/caelestia-clipboard"

    property Component waitTimer: Component {
        Timer {
            property string imgPath
            property var callback

            interval: 1000
            repeat: false

            onTriggered: callback(imgPath)
        }
    }

    property Process fetcher: Process {
        running: false
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const result = [];
                const lines = text.trim().split("\n");

                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i];
                    if (!line)
                        continue;

                    const match = line.match(/^(\d+)\t(.+)/);
                    if (!match)
                        continue;

                    result.push({
                        id: parseInt(match[1]),
                        preview: match[2],
                        isImage: /^\[\[ binary data \d+ KiB png \d+x\d+ \]\]/.test(match[2])
                    });
                }

                root.items = result;
                root._loaded = true;
                root._sortedCache = null;
                preloadImages();
            }
        }
    }

    function reload(): void {
        if (_loaded)
            return;
        fetcher.running = true;
    }

    function preloadImages(): void {
        for (const item of items) {
            if (item.isImage && item.id) {
                const imgPath = getImagePath(item.id);
                Quickshell.execDetached(["sh", "-c", "mkdir -p " + imageCacheDir + " && cliphist decode " + item.id + " > " + imgPath + " 2>&1"]);
            }
        }
    }

    function getSortedItems(): var {
        if (!items.length)
            return [];
        // Return cached result if items haven't changed
        if (_sortedCache !== null && _loaded)
            return _sortedCache;
        const favClips = new Set((GlobalConfig.launcher.favouriteClips || []).map(String));
        const favs = [];
        const rest = [];
        for (const item of items) {
            if (favClips.has(String(item.id))) {
                favs.push(item);
            } else {
                rest.push(item);
            }
        }
        const sorted = [...favs, ...rest];
        _sortedCache = sorted;
        return sorted;
    }

    function getImagePath(clipId: int): string {
        return imageCacheDir + "/" + clipId + ".png";
    }

    function ensureImageCached(id: int, onReady: var): void {
        const imgPath = getImagePath(id);
        Quickshell.execDetached(["sh", "-c", "mkdir -p " + imageCacheDir + " && cliphist decode " + id + " > " + imgPath + " 2>&1"]);
        const timer = waitTimer.createObject(root, {
            imgPath: imgPath,
            callback: onReady
        });
    }
}
