pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services
import qs.utils

// TODO: Niri has no runtime config mutation for animations/shadows/blur/gaps/opacity.
// This entire GameMode implementation is a no-op placeholder.
Singleton {
    id: root

    property alias enabled: props.enabled

    property bool _autoEnabled: false

    function evaluateAutoEnable(): void {
        // TODO: Niri has no runtime config mutation
    }

    function setDynamicConfs(): void {
        // TODO: Niri has no runtime config mutation
    }

    PersistentProperties {
        id: props
        property bool enabled: false
        reloadableId: "gameMode"
    }

    IpcHandler {
        function isEnabled(): bool {
            return props.enabled;
        }
        function toggle(): void {
            props.enabled = !props.enabled;
        }
        function enable(): void {
            props.enabled = true;
        }
        function disable(): void {
            props.enabled = false;
        }
        target: "gameMode"
    }
}
