pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

// TODO: Niri has no concept of special/scratchpad workspaces.
// This component is commented out as a no-op placeholder.
Item {
    id: root

    required property ShellScreen screen
}
