pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia

// Aggregates LLM provider account status for the dashboard "Providers" tab.
//
// Sources:
//   - 9Router: read-only query of ~/.9router/db/data.sqlite for connection
//     status, plus two local API calls authenticated with the 9Router CLI
//     token: /api/usage/<connectionId> for quotas and /api/models for context
//     windows. Tokens are never selected, only limit metadata.
//   - Token Harbor: each provider entry in ~/.config/opencode/opencode.json is
//     probed with a single /v1/models request to report basic connectivity.
//     Account usage comes from the gateway's x-th-free-used-pct and
//     x-th-free-resets headers, which are only sent on a successful chat
//     completion, so a tiny completion to a free model is used as a probe
//     (see scripts/tokenharbor-usage.py). Context comes from the 9Router model
//     catalog. The API keys come from opencode's credential store (opencode.db),
//     because they are entered through the opencode /connect flow rather than the
//     config file. Keys stay in memory and are never displayed or logged.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string routerDbPath: `${home}/.9router/db/data.sqlite`
    readonly property string opencodeConfigPath: `${home}/.config/opencode/opencode.json`
    readonly property string opencodeDbPath: `${home}/.local/share/opencode/opencode.db`
    readonly property string tokenHarborConfigPath: `${home}/.tokenharbor/config.json`
    readonly property string dashboardConfigPath: `${home}/.config/caelestia/llm-providers.json`
    readonly property string usageScriptPath: `${home}/.config/quickshell/caelestia/scripts/tokenharbor-usage.py`

    // Token Harbor allowances reset on a rolling 7-day window, so checking twice
    // a day is enough. Each check spends one tiny completion, so the interval is
    // deliberately generous.
    readonly property int usageRefreshInterval: 12 * 60 * 60 * 1000

    // Only integration_id and the key field are read. Opened read-only so the
    // query cannot write to opencode's database.
    readonly property string credentialQuery: "SELECT integration_id, value FROM credential WHERE integration_id LIKE 'tokenharbor%';"

    // Only limit metadata is extracted, never accessToken/refreshToken.
    readonly property string routerQuery: `SELECT json_object(
        'connections', (SELECT json_group_array(json_object(
            'id', id,
            'provider', provider,
            'name', name,
            'email', email,
            'isActive', isActive,
            'rateLimitedUntil', json_extract(data, '$.rateLimitedUntil'),
            'testStatus', json_extract(data, '$.testStatus'),
            'errorCode', json_extract(data, '$.errorCode'),
            'lastError', json_extract(data, '$.lastError'),
            'lastErrorAt', json_extract(data, '$.lastErrorAt'),
            'modelLocks', (SELECT json_group_object(je.key, je.value) FROM json_each(providerConnections.data) je WHERE je.key LIKE 'modelLock_%')
        )) FROM providerConnections),
        'usage', (SELECT data FROM usageDaily ORDER BY dateKey DESC LIMIT 1)
    ) AS out;`

    property int refreshInterval: 60000
    property var providers: []
    property var lastUpdated: null
    property string errorMessage: ""

    property var routerConnections: []
    property var routerUsage: null
    property string fallbackKey: ""
    property var opencodeKeys: ({})
    property bool credentialsLoaded: false
    property var tokenHarborProviders: []
    property var probes: ({})
    property var dashboardProfiles: ({})
    property var usageProbes: ({})
    property var usageQueue: []
    property var usageCurrent: null
    property bool usageProbing: false
    property real lastUsageProbe: 0
    property string cliToken: ""
    property var routerQuotas: ({})
    property var modelCaps: ({})
    property var modelCapsById: ({})
    readonly property var providerAliases: ({
        kiro: "kr"
    })

    function refresh(): void {
        if (!routerProc.running)
            routerProc.running = true;
        if (!root.credentialsLoaded && !credentialProc.running)
            credentialProc.running = true;
        if (root.cliToken)
            root.fetchRouterMeta();
        else if (!cliTokenProc.running)
            cliTokenProc.running = true;
        probeTokenHarbor();
    }

    function handleRouterOutput(text: string): void {
        try {
            const wrapper = JSON.parse(text);
            const out = JSON.parse(wrapper[0].out);
            root.routerConnections = out.connections ?? [];
            root.routerUsage = out.usage ? JSON.parse(out.usage) : null;
            root.errorMessage = "";
        } catch (e) {
            root.routerConnections = [];
            root.routerUsage = null;
            root.errorMessage = String(e);
        }
        root.rebuild();
        root.fetchRouterQuotas();
    }

    function rebuild(): void {
        const list = [];
        for (const connection of root.routerConnections)
            list.push(root.routerCard(connection));
        // One row per configured entry. Token Harbor entries are separate
        // accounts, so they are intentionally not merged into a single card.
        for (const provider of root.tokenHarborProviders)
            list.push(root.tokenCard(provider));
        root.providers = list;
        root.lastUpdated = new Date();
    }

    function routerCard(connection: var): var {
        const now = Date.now();
        const locks = [];
        let soonest = 0;

        const modelLocks = connection.modelLocks || {};
        for (const key in modelLocks) {
            const raw = modelLocks[key];
            if (!raw)
                continue;
            const until = Date.parse(raw);
            if (isNaN(until) || until <= now)
                continue;
            locks.push({ name: String(key).replace(/^modelLock_/, ""), until: until });
            if (!soonest || until < soonest)
                soonest = until;
        }

        const rateUntil = connection.rateLimitedUntil ? Date.parse(connection.rateLimitedUntil) : NaN;
        const hasRate = !isNaN(rateUntil) && rateUntil > now;
        if (hasRate && (!soonest || rateUntil < soonest))
            soonest = rateUntil;

        const error = (connection.lastError || "").toLowerCase();
        const quota = hasRate || locks.length > 0 || error.includes("limit") || error.includes("quota") || connection.errorCode === 429;

        let status = "unknown";
        if (connection.isActive === 0)
            status = "inactive";
        else if (quota)
            status = "limited";
        else if (connection.lastError || connection.errorCode || connection.testStatus === "unavailable" || connection.testStatus === "error")
            status = "error";
        else if (connection.testStatus === "active" || connection.testStatus === "ok")
            status = "ok";

        const info = root.quotaInfo(root.routerQuotas[connection.id]);
        if (info && info.resetAt > 0 && (!soonest || info.resetAt < soonest))
            soonest = info.resetAt;

        return {
            id: `router:${connection.provider}:${connection.name ?? ""}`,
            title: root.titleCase(connection.provider),
            subtitle: connection.email ? `${connection.name || "Account"} (${connection.email})` : (connection.name || "Account"),
            source: "9Router",
            status: status,
            reason: root.reasonText(connection.lastError, connection.errorCode),
            since: connection.lastErrorAt ? Date.parse(connection.lastErrorAt) : NaN,
            resetAt: soonest || NaN,
            lockCount: locks.length,
            usage: root.providerUsage(connection.provider),
            plan: info ? info.plan : "",
            limitText: info ? root.quotaLimitText(info) : "",
            usedPercent: info && info.percent >= 0 ? info.percent : -1,
            contextTokens: root.contextForProvider(connection.provider),
            link: ""
        };
    }

    function tokenCard(provider: var): var {
        const probe = root.probes[provider.id] || { status: "checking", detail: "" };
        const mapping = root.dashboardProfiles[provider.id] || {};
        const usage = root.usageProbes[provider.id] || {};
        const usedPercent = usage.usedPercent >= 0 ? usage.usedPercent : -1;
        return {
            id: `tokenharbor:${provider.id}`,
            title: provider.name,
            subtitle: mapping.profile || provider.id,
            dashboardProfile: mapping.profile || "",
            source: "Token Harbor",
            status: probe.status,
            reason: probe.detail,
            since: NaN,
            resetAt: usage.resetAt && !isNaN(usage.resetAt) ? usage.resetAt : NaN,
            lockCount: 0,
            usage: null,
            plan: "Free",
            limitText: usedPercent >= 0 ? "" : "not reported",
            usedPercent: usedPercent,
            modelCount: (provider.models || []).length,
            contextTokens: root.contextForProvider(provider.id, provider.models),
            link: mapping.url || "https://tokenharbor.ai/dashboard"
        };
    }

    function providerUsage(provider: string): var {
        const byProvider = root.routerUsage ? root.routerUsage.byProvider : null;
        if (!byProvider)
            return null;
        const entry = byProvider[provider];
        if (!entry)
            return null;
        return { requests: entry.requests ?? 0 };
    }

    function reasonText(lastError: string, errorCode: var): string {
        if (lastError) {
            const reason = lastError.match(/"reason"\s*:\s*"([^"]+)"/);
            if (reason)
                return reason[1];
            const message = lastError.match(/"message"\s*:\s*"([^"]+)"/);
            if (message)
                return message[1];
            return lastError.replace(/^\[\d+\]:\s*/, "");
        }
        return errorCode ? `Error ${errorCode}` : "";
    }

    function titleCase(value: string): string {
        if (!value)
            return "";
        return value.charAt(0).toUpperCase() + value.slice(1);
    }

    // Shapes the /api/usage/<connectionId> payload into what the card needs.
    function quotaInfo(data: var): var {
        if (!data || !data.quotas)
            return null;
        const limits = [];
        let percent = -1;
        let resetAt = 0;
        for (const name in data.quotas) {
            const quota = data.quotas[name] || {};
            if (quota.unlimited === true) {
                limits.push({
                    name: name,
                    unlimited: true
                });
                continue;
            }
            const total = Number(quota.total) || 0;
            const used = Number(quota.used) || 0;
            const value = total > 0 ? Math.min(100, Math.round((used / total) * 100)) : -1;
            limits.push({
                name: name,
                used: used,
                total: total,
                unlimited: false
            });
            if (value >= 0 && value > percent)
                percent = value;
            const reset = quota.resetAt ? Date.parse(quota.resetAt) : NaN;
            if (!isNaN(reset) && (!resetAt || reset < resetAt))
                resetAt = reset;
        }
        return {
            plan: data.plan || "",
            limits: limits,
            percent: percent,
            resetAt: resetAt
        };
    }

    function quotaLimitText(info: var): string {
        if (!info)
            return "";
        const parts = [];
        for (const limit of info.limits) {
            if (limit.unlimited)
                parts.push(`${root.titleCase(limit.name)}: unlimited`);
            else if (limit.total > 0)
                parts.push(`${limit.used} / ${limit.total} ${root.titleCase(limit.name)}`);
            else
                parts.push(root.titleCase(limit.name));
        }
        return parts.join(", ");
    }

    function contextForProvider(provider: string, models: var): real {
        let best = 0;
        if (models && models.length) {
            for (const model of models) {
                const caps = root.modelCapsById[model];
                if (caps && caps.context > best)
                    best = caps.context;
            }
        }
        if (best)
            return best;
        const aliases = [root.providerAliases[provider], provider];
        for (const alias of aliases) {
            const caps = alias ? root.modelCaps[alias] : null;
            if (caps && caps.context > best)
                best = caps.context;
        }
        return best;
    }

    function fetchRouterMeta(): void {
        if (!root.cliToken)
            return;
        root.fetchRouterCatalog();
        root.fetchRouterQuotas();
    }

    // The 9Router HTTP API is local-only: it accepts the CLI token derived from
    // machine-id and auth/cli-secret, not the router API key.
    function fetchRouterCatalog(): void {
        Requests.get("http://127.0.0.1:20128/api/models", (body, meta) => {
            try {
                const models = JSON.parse(body).models || [];
                const byProvider = {};
                const byId = {};
                for (const model of models) {
                    const caps = model.caps || {};
                    const context = Number(caps.contextWindow) || 0;
                    if (!context)
                        continue;
                    const provider = String(model.provider || "");
                    if (provider && (!byProvider[provider] || context > byProvider[provider].context))
                        byProvider[provider] = { context: context };
                    const keys = [model.model, model.fullModel, model.routedModel];
                    for (const key of keys) {
                        if (key && (!byId[key] || context > byId[key].context))
                            byId[key] = { context: context };
                    }
                }
                root.modelCaps = byProvider;
                root.modelCapsById = byId;
                root.rebuild();
            } catch (e) {
                console.warn("LlmProviders: cannot parse model catalog:", e);
            }
        }, (err, meta) => {
            console.warn("LlmProviders: cannot read model catalog:", err);
        }, { "x-9r-cli-token": root.cliToken });
    }

    function fetchRouterQuotas(): void {
        if (!root.cliToken)
            return;
        for (const connection of root.routerConnections) {
            const id = connection.id;
            if (!id)
                continue;
            Requests.get(`http://127.0.0.1:20128/api/usage/${id}`, (body, meta) => {
                try {
                    const data = JSON.parse(body);
                    const next = Object.assign({}, root.routerQuotas);
                    next[id] = data;
                    root.routerQuotas = next;
                    root.rebuild();
                } catch (e) {
                    console.warn("LlmProviders: cannot parse quota:", e);
                }
            }, (err, meta) => {}, { "x-9r-cli-token": root.cliToken });
        }
    }

    function resolveKey(provider: var): string {
        const stored = root.opencodeKeys[provider.id];
        if (stored)
            return stored;
        if (provider.envName) {
            const value = Quickshell.env(provider.envName);
            if (value)
                return value;
        }
        return root.fallbackKey;
    }

    function probeTokenHarbor(): void {
        for (const provider of root.tokenHarborProviders) {
            const key = root.resolveKey(provider);
            if (!key) {
                root.setProbe(provider.id, "unknown", "No API key");
                continue;
            }
            const base = String(provider.baseURL || "https://tokenharbor.ai/v1").replace(/\/+$/, "");
            Requests.get(`${base}/models`, (body, meta) => root.setProbe(provider.id, "ok", ""), (err, meta) => {
                const code = meta && meta.statusCode ? meta.statusCode : 0;
                if (code === 401)
                    root.setProbe(provider.id, "error", "Key rejected (401)");
                else if (code === 403)
                    root.setProbe(provider.id, "error", "Blocked (403)");
                else if (code === 0)
                    root.setProbe(provider.id, "error", "Unreachable");
                else
                    root.setProbe(provider.id, "error", `HTTP ${code}`);
            }, { Authorization: `Bearer ${key}` });
        }
        root.refreshUsage(false);
    }

    function setProbe(id: string, status: string, detail: string): void {
        const next = Object.assign({}, root.probes);
        next[id] = { status: status, detail: detail };
        root.probes = next;
        root.rebuild();
    }

    // Checks the free-allowance counters for every Token Harbor provider. Each
    // check costs one tiny completion, so calls are throttled unless forced.
    function refreshUsage(force: bool): void {
        if (root.usageProbing)
            return;
        if (!force && Date.now() - root.lastUsageProbe < root.usageRefreshInterval)
            return;
        const jobs = [];
        for (const provider of root.tokenHarborProviders) {
            if (!root.resolveKey(provider))
                continue;
            const model = (provider.models || []).find(m => /:free$/.test(m));
            if (!model)
                continue;
            jobs.push({
                id: provider.id,
                base: String(provider.baseURL || "https://tokenharbor.ai/v1").replace(/\/+$/, ""),
                model: model
            });
        }
        if (jobs.length === 0)
            return;
        root.lastUsageProbe = Date.now();
        root.usageQueue = jobs;
        root.pumpUsageQueue();
    }

    function pumpUsageQueue(): void {
        if (root.usageProbing || root.usageQueue.length === 0)
            return;
        const job = root.usageQueue[0];
        root.usageCurrent = job;
        root.usageProbing = true;
        usageProc.command = ["/usr/bin/python3", root.usageScriptPath, job.id, job.base, job.model];
        usageProc.running = true;
    }

    function handleUsageOutput(text: string): void {
        const job = root.usageCurrent;
        const lines = text.trim().split("\n");
        const parts = (lines[lines.length - 1] || "").split("|");
        if (job) {
            const next = Object.assign({}, root.usageProbes);
            if (parts[0] === "ok" || parts[0] === "exhausted") {
                const percent = parts[0] === "exhausted" ? 100 : Number(parts[1]);
                const reset = parts[2] ? Date.parse(parts[2]) : NaN;
                next[job.id] = {
                    usedPercent: parts[0] === "exhausted" ? 100 : (isFinite(percent) ? percent : -1),
                    resetAt: isNaN(reset) ? NaN : reset,
                    at: Date.now()
                };
            } else {
                next[job.id] = { usedPercent: -1, resetAt: NaN, at: Date.now() };
            }
            root.usageProbes = next;
        }
        root.usageQueue = root.usageQueue.slice(1);
        root.usageCurrent = null;
        root.usageProbing = false;
        root.rebuild();
        root.pumpUsageQueue();
    }

    function handleDashboardConfig(text: string): void {
        try {
            root.dashboardProfiles = JSON.parse(text);
        } catch (e) {
            root.dashboardProfiles = {};
        }
        root.rebuild();
    }

    function parseOpencode(text: string): void {
        const list = [];
        try {
            const config = JSON.parse(text);
            const providers = config.provider || {};
            for (const id in providers) {
                const provider = providers[id];
                const options = provider.options || {};
                const base = String(options.baseURL || "");
                if (!base.includes("tokenharbor.ai") && !id.toLowerCase().startsWith("tokenharbor"))
                    continue;
                const reference = String(options.apiKey || "");
                const envMatch = reference.match(/\{env:([A-Za-z0-9_]+)\}/);
                list.push({
                    id: id,
                    name: provider.name || id,
                    baseURL: base || "https://tokenharbor.ai/v1",
                    envName: envMatch ? envMatch[1] : "",
                    models: Object.keys(provider.models || {})
                });
            }
        } catch (e) {
            console.warn("LlmProviders: cannot parse opencode.json:", e);
        }
        root.tokenHarborProviders = list;
        if (!root.credentialsLoaded && !credentialProc.running)
            credentialProc.running = true;
        root.probeTokenHarbor();
        root.rebuild();
    }

    function handleTokenConfig(text: string): void {
        try {
            root.fallbackKey = JSON.parse(text).key || "";
        } catch (e) {
            root.fallbackKey = "";
        }
    }

    // Extracts Token Harbor keys from opencode's credential store. The keys stay
    // in memory only: they are never displayed, logged, or written anywhere.
    function handleCredentials(text: string): void {
        let rows = null;
        try {
            rows = JSON.parse(text);
        } catch (e) {
            return;
        }
        const keys = {};
        if (Array.isArray(rows)) {
            for (const row of rows) {
                try {
                    const data = JSON.parse(row.value);
                    if (data && data.key)
                        keys[row.integration_id] = data.key;
                } catch (e) {}
            }
        }
        root.opencodeKeys = keys;
        root.credentialsLoaded = true;
        root.probeTokenHarbor();
        root.rebuild();
    }

    FileView {
        id: opencodeFile

        path: root.opencodeConfigPath
        watchChanges: true
        printErrors: false

        onLoaded: root.parseOpencode(text())
        onFileChanged: reload()
    }

    FileView {
        id: tokenHarborFile

        path: root.tokenHarborConfigPath
        watchChanges: true
        printErrors: false

        onLoaded: root.handleTokenConfig(text())
        onFileChanged: reload()
    }

    FileView {
        id: dashboardFile

        path: root.dashboardConfigPath
        watchChanges: true
        printErrors: false

        onLoaded: root.handleDashboardConfig(text())
        onFileChanged: reload()
    }

    Process {
        id: routerProc

        command: ["sqlite3", "-json", root.routerDbPath, root.routerQuery]

        stdout: StdioCollector {
            onStreamFinished: root.handleRouterOutput(text)
        }
    }

    Process {
        id: credentialProc

        command: ["sqlite3", "-readonly", "-json", root.opencodeDbPath, root.credentialQuery]

        stdout: StdioCollector {
            onStreamFinished: root.handleCredentials(text)
        }
    }

    Process {
        id: usageProc

        stdout: StdioCollector {
            onStreamFinished: root.handleUsageOutput(text)
        }
    }

    Process {
        id: cliTokenProc

        command: ["bash", "-c", `printf '%s9r-cli-auth%s' "$(cat '${root.home}/.9router/machine-id')" "$(cat '${root.home}/.9router/auth/cli-secret')" | sha256sum | cut -c1-16`]

        stdout: StdioCollector {
            onStreamFinished: {
                const token = text.trim();
                if (!token || token === root.cliToken)
                    return;
                root.cliToken = token;
                root.fetchRouterMeta();
            }
        }
    }
}
