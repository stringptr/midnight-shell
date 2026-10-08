pragma Singleton

import Quickshell
import Caelestia.Config
import Caelestia.Models
import qs.utils

Searcher {
    id: root

    property string keyMode: ""

    function launch(entry: DesktopEntry): void {
        appDb.incrementFrequency(entry.id);

        if (entry.runInTerminal)
            Quickshell.execDetached({
                command: [...GlobalConfig.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...entry.command],
                workingDirectory: entry.workingDirectory
            });
        else
            entry.execute();
    }

    function search(search: string): var {
        const prefix = GlobalConfig.launcher.specialPrefix;

        let mode = "n";
        if (search.startsWith(`${prefix}i `))
            mode = "i";
        else if (search.startsWith(`${prefix}c `))
            mode = "c";
        else if (search.startsWith(`${prefix}d `))
            mode = "d";
        else if (search.startsWith(`${prefix}e `))
            mode = "e";
        else if (search.startsWith(`${prefix}w `))
            mode = "w";
        else if (search.startsWith(`${prefix}g `))
            mode = "g";
        else if (search.startsWith(`${prefix}k `))
            mode = "k";

        if (mode !== keyMode) {
            keyMode = mode;

            switch (mode) {
            case "i":
                keys = ["id", "name"];
                weights = [0.9, 0.1];
                break;
            case "c":
                keys = ["categories", "name"];
                weights = [0.9, 0.1];
                break;
            case "d":
                keys = ["comment", "name"];
                weights = [0.9, 0.1];
                break;
            case "e":
                keys = ["execString", "name"];
                weights = [0.9, 0.1];
                break;
            case "w":
                keys = ["startupClass", "name"];
                weights = [0.9, 0.1];
                break;
            case "g":
                keys = ["genericName", "name"];
                weights = [0.9, 0.1];
                break;
            case "k":
                keys = ["keywords", "name"];
                weights = [0.9, 0.1];
                break;
            default:
                keys = ["name"];
                weights = [1];
                break;
            }
        }

        if (mode === "n" && !search.startsWith(`${prefix}t `))
            return query(search).map(e => e.entry);

        const results = query(search.slice(prefix.length + 2)).map(e => e.entry);
        if (search.startsWith(`${prefix}t `))
            return results.filter(a => a.runInTerminal);
        return results;
    }

    function selector(item: var): string {
        return keys.map(k => item[k]).join(" ");
    }

    list: appDb.apps
    useFuzzy: GlobalConfig.launcher.useFuzzy.apps

    AppDb {
        id: appDb

        path: `${Paths.state}/apps.sqlite`
        favouriteApps: GlobalConfig.launcher.favouriteApps
        entries: DesktopEntries.applications.values.filter(a => !Strings.testRegexList(GlobalConfig.launcher.hiddenApps, a.id))
    }
}
