pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services

// TODO: handle this better later

Item {
    id: model

    property alias visibleModel: visibleModel
    property string activeLabel: ""
    property int activeIndex: -1
    property var _xkbMap: ({})
    property bool _notifiedLimit: false

    function start() {
        xkbXmlBase.running = true;
        fetchLayoutsFromNiri.running = true;
    }

    function refresh() {
        _notifiedLimit = false;
        fetchLayoutsFromNiri.running = true;
    }

    function switchTo(idx) {
        // Niri supports "switch-layout next/prev"; calculate shortest cyclic path
        const arr = Niri.kbLayoutsArray;
        if (!arr || arr.length === 0) return;
        const current = Niri.kbLayoutIndex;
        const n = arr.length;
        const diff = ((idx - current) % n + n) % n;
        const cmd = diff <= n / 2 ? "next" : "prev";
        const steps = diff <= n / 2 ? diff : n - diff;
        for (let i = 0; i < steps; i++) {
            Quickshell.execDetached(["niri", "msg", "action", "switch-layout", cmd]);
        }
    }

    function _buildXmlMap(xml) {
        const map = {};

        const re = /<name>\s*([^<]+?)\s*<\/name>[\s\S]*?<description>\s*([^<]+?)\s*<\/description>/g;

        let m;
        while ((m = re.exec(xml)) !== null) {
            const code = (m[1] || "").trim();
            const desc = (m[2] || "").trim();
            if (!code || !desc)
                continue;
            map[code] = _short(desc);
        }

        if (Object.keys(map).length === 0)
            return;

        _xkbMap = map;

        if (layoutsModel.count > 0) {
            const tmp = [];
            for (let i = 0; i < layoutsModel.count; i++) {
                const it = layoutsModel.get(i);
                tmp.push({
                    layoutIndex: it.layoutIndex,
                    token: it.token,
                    label: _pretty(it.token)
                });
            }
            layoutsModel.clear();
            tmp.forEach(t => layoutsModel.append(t));
            _rebuildVisible();
        }
    }

    function _short(desc) {
        const m = desc.match(/^(.*)\((.*)\)$/);
        if (!m)
            return desc;
        const lang = m[1].trim();
        const region = m[2].trim();
        const code = (region.split(/[,\s-]/)[0] || region).slice(0, 2).toUpperCase();
        // TRANSLATORS: %1 = language, %2 = layout code
        return Tr.trCtx("%1 (%2)", "keyboard layout language and code").arg(lang).arg(code);
    }

    function _setLayouts(layouts) {
        layoutsModel.clear();
        const seen = new Set();
        let idx = 0;

        for (const token of layouts) {
            if (!token || seen.has(token))
                continue;
            seen.add(token);
            layoutsModel.append({
                layoutIndex: idx,
                token: token,
                label: _pretty(token)
            });
            idx++;
        }
    }

    function _rebuildVisible() {
        visibleModel.clear();

        let arr = [];
        for (let i = 0; i < layoutsModel.count; i++)
            arr.push(layoutsModel.get(i));

        arr = arr.filter(i => i.layoutIndex !== activeIndex);
        arr.forEach(i => visibleModel.append(i));

        if (!GlobalConfig.utilities.toasts.kbLimit)
            return;

        if (layoutsModel.count > 4) {
            Toaster.toast(Tr.tr("Keyboard layout limit"), Tr.tr("XKB supports only 4 layouts at a time"), "warning");
        }
    }

    function _pretty(token) {
        const code = token.replace(/\(.*\)$/, "").trim();
        if (_xkbMap[code])
            // TRANSLATORS: %1 = layout code, %2 = layout name
            return Tr.trCtx("%1 - %2", "keyboard layout code and name").arg(code.toUpperCase()).arg(_xkbMap[code]);
        // TRANSLATORS: %1 = layout code, %2 = layout name
        return Tr.trCtx("%1 - %2", "keyboard layout code and name").arg(code.toUpperCase()).arg(code);
    }

    visible: false

    ListModel {
        id: visibleModel
    }

    ListModel {
        id: layoutsModel
    }

    Process {
        id: xkbXmlBase

        command: ["xmllint", "--xpath", "//layout/configItem[name and description]", "/usr/share/X11/xkb/rules/base.xml"]
        stdout: StdioCollector {
            onStreamFinished: model._buildXmlMap(text)
        }
        onRunningChanged: if (!running && (typeof xkbXmlBase.exitCode !== "undefined") && xkbXmlBase.exitCode !== 0) // qmllint disable missing-property
            xkbXmlEvdev.running = true
    }

    Process {
        id: xkbXmlEvdev

        command: ["xmllint", "--xpath", "//layout/configItem[name and description]", "/usr/share/X11/xkb/rules/evdev.xml"]
        stdout: StdioCollector {
            onStreamFinished: model._buildXmlMap(text)
        }
    }

    Process {
        id: fetchLayoutsFromNiri

        // Fetch keyboard layout info directly from Niri IPC
        command: ["niri", "msg", "keyboard-layouts"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    const names = j?.names || [];
                    if (names.length > 0) {
                        model._setLayouts(names);
                        model.activeIndex = j?.current_idx ?? 0;
                        model.activeLabel = (model.activeIndex >= 0 && model.activeIndex < layoutsModel.count) ? layoutsModel.get(model.activeIndex).label : "";
                        model._rebuildVisible();
                        return;
                    }
                } catch (e) {}
                // Fallback: try Niri properties
                const layouts = Niri.kbLayoutsArray;
                if (layouts && layouts.length > 0) {
                    model._setLayouts(layouts);
                    model.activeIndex = Niri.kbLayoutIndex;
                    model.activeLabel = (model.activeIndex >= 0 && model.activeIndex < layoutsModel.count) ? layoutsModel.get(model.activeIndex).label : "";
                    model._rebuildVisible();
                }
            }
        }
    }
}
