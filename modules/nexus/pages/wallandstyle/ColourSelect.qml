import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import qs.modules.launcher.services

PageBase {
    id: root

    title: Tr.tr("Colours")
    isSubPage: true

    readonly property list<var> variantData: [
        { name: "vibrant", label: qsTr("Vibrant") },
        { name: "tonalspot", label: qsTr("Tonal Spot") },
        { name: "expressive", label: qsTr("Expressive") },
        { name: "fidelity", label: qsTr("Fidelity") },
        { name: "content", label: qsTr("Content") },
        { name: "fruitsalad", label: qsTr("Fruit Salad") },
        { name: "rainbow", label: qsTr("Rainbow") },
        { name: "neutral", label: qsTr("Neutral") },
        { name: "monochrome", label: qsTr("Monochrome") }
    ]

    // Tool option lists. "" means "omit the flag" (tool default / config file applies)
    readonly property var matugenTypes: ["", "scheme-tonal-spot", "scheme-vibrant", "scheme-expressive", "scheme-fidelity", "scheme-content", "scheme-monochrome", "scheme-neutral", "scheme-rainbow", "scheme-fruit-salad", "scheme-smart"]
    readonly property var matugenModes: ["", "dark", "light", "smart"]
    readonly property var wallustBackends: ["", "full", "resized", "wal", "thumb", "fast-resize", "kmeans"]
    readonly property var wallustColorspaces: ["", "lab", "lab-mixed", "lch", "lch-mixed", "salience", "lch-ansi"]
    readonly property var wallustPalettes: [
        "", "dark", "dark16", "dark-comp", "dark-comp16",
        "ansi-dark", "ansi-dark16",
        "hard-dark", "hard-dark16", "hard-dark-comp", "hard-dark-comp16",
        "salience-dark", "salience-dark16", "salience-dark-balanced", "salience-dark-balanced16",
        "salience-dark-distributed", "salience-dark-distributed16", "salience-dark-low", "salience-dark-low16",
        "light", "light16", "light-comp", "light-comp16",
        "soft-dark", "soft-dark16", "soft-dark-comp", "soft-dark-comp16",
        "soft-light", "soft-light16", "soft-light-comp", "soft-light-comp16",
        "salience-light", "salience-light16", "salience-light-balanced", "salience-light-balanced16",
        "salience-light-distributed", "salience-light-distributed16", "salience-light-low", "salience-light-low16"
    ]

    function optionActive(value: string, items: var): var {
        for (let i = 0; i < items.length; i++) {
            if (String(items[i].modelData) === value)
                return items[i];
        }
        return null;
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Variants {
            id: schemeItems
            model: Schemes.list
            MenuItem {
                required property var modelData
                text: `${modelData.name} ${modelData.flavour}`
                onClicked: {
                    if (Wallpapers.externalColours) return;
                    Quickshell.execDetached(["caelestia", "scheme", "set", "-n", modelData.name, "-f", modelData.flavour]);
                }
            }
        }

        Variants {
            id: variantItems
            model: root.variantData
            MenuItem {
                required property var modelData
                text: modelData.label
                onClicked: {
                    if (Wallpapers.externalColours) return;
                    Quickshell.execDetached(["caelestia", "scheme", "set", "-v", modelData.name]);
                }
            }
        }

        Variants {
            id: matugenTypeItems
            model: root.matugenTypes
            MenuItem {
                required property var modelData
                text: modelData === "" ? qsTr("Default") : modelData
                onClicked: {
                    GlobalConfig.scheme.matugenType = modelData;
                    GlobalConfig.save();
                }
            }
        }

        Variants {
            id: matugenModeItems
            model: root.matugenModes
            MenuItem {
                required property var modelData
                text: modelData === "" ? qsTr("Default") : modelData
                onClicked: {
                    GlobalConfig.scheme.matugenMode = modelData;
                    GlobalConfig.save();
                }
            }
        }

        Variants {
            id: wallustBackendItems
            model: root.wallustBackends
            MenuItem {
                required property var modelData
                text: modelData === "" ? qsTr("Default") : modelData
                onClicked: {
                    GlobalConfig.scheme.wallustBackend = modelData;
                    GlobalConfig.save();
                }
            }
        }

        Variants {
            id: wallustColorspaceItems
            model: root.wallustColorspaces
            MenuItem {
                required property var modelData
                text: modelData === "" ? qsTr("Default") : modelData
                onClicked: {
                    GlobalConfig.scheme.wallustColorspace = modelData;
                    GlobalConfig.save();
                }
            }
        }

        Variants {
            id: wallustPaletteItems
            model: root.wallustPalettes
            MenuItem {
                required property var modelData
                text: modelData === "" ? qsTr("Default") : modelData
                onClicked: {
                    GlobalConfig.scheme.wallustPalette = modelData;
                    GlobalConfig.save();
                }
            }
        }

        SectionHeader {
            first: true
            text: qsTr("Colour generation")
        }

        ToggleRow {
            first: true
            Layout.fillWidth: true
            text: qsTr("Use Matugen")
            subtext: qsTr("Generate colours with matugen instead of caelestia (scheme.json is written by your matugen config templates)")
            checked: GlobalConfig.scheme.useMatugen
            onToggled: {
                GlobalConfig.scheme.useMatugen = checked;
                GlobalConfig.save();
                Wallpapers.refreshColours();
            }
        }

        ToggleRow {
            last: true
            Layout.fillWidth: true
            text: qsTr("Use Wallust")
            subtext: qsTr("Run wallust on every wallpaper change; it applies its own sequences, templates and hooks")
            checked: GlobalConfig.scheme.useWallust
            onToggled: {
                GlobalConfig.scheme.useWallust = checked;
                GlobalConfig.save();
                Wallpapers.refreshColours();
            }
        }

        SectionHeader {
            visible: GlobalConfig.scheme.useMatugen
            text: qsTr("Matugen parameters")
        }

        TextFieldRow {
            visible: GlobalConfig.scheme.useMatugen
            first: true
            label: qsTr("Config file")
            subtext: qsTr("Leave empty to use the default config path")
            value: GlobalConfig.scheme.matugenConfigPath
            placeholderText: "~/.config/matugen/config.toml"
            onEditingFinished: value => {
                GlobalConfig.scheme.matugenConfigPath = value;
                GlobalConfig.save();
            }
        }

        SelectRow {
            visible: GlobalConfig.scheme.useMatugen
            label: qsTr("Scheme type")
            subtext: qsTr("Material scheme algorithm, passed as -t (default scheme-tonal-spot)")
            menuItems: matugenTypeItems.instances
            active: root.optionActive(GlobalConfig.scheme.matugenType, menuItems)
            fallbackText: GlobalConfig.scheme.matugenType || qsTr("Default")
        }

        SelectRow {
            visible: GlobalConfig.scheme.useMatugen
            label: qsTr("Mode")
            subtext: qsTr("Colour scheme mode, passed as -m (default dark)")
            menuItems: matugenModeItems.instances
            active: root.optionActive(GlobalConfig.scheme.matugenMode, menuItems)
            fallbackText: GlobalConfig.scheme.matugenMode || qsTr("Default")
        }

        TextFieldRow {
            visible: GlobalConfig.scheme.useMatugen
            smallField: true
            label: qsTr("Contrast")
            subtext: qsTr("From -1 (min) to 1 (max), 0 is standard. Empty to omit")
            value: GlobalConfig.scheme.matugenContrast
            placeholderText: "0"
            onEditingFinished: value => {
                GlobalConfig.scheme.matugenContrast = value;
                GlobalConfig.save();
            }
        }

        TextFieldRow {
            visible: GlobalConfig.scheme.useMatugen
            smallField: true
            label: qsTr("Source colour index")
            subtext: qsTr("Which extracted colour to use, 0-3. Empty to omit")
            value: GlobalConfig.scheme.matugenSourceColorIndex
            placeholderText: "0"
            onEditingFinished: value => {
                GlobalConfig.scheme.matugenSourceColorIndex = value;
                GlobalConfig.save();
            }
        }

        TextFieldRow {
            visible: GlobalConfig.scheme.useMatugen
            label: qsTr("Prefix")
            subtext: qsTr("Prefix added before template paths. Empty to omit")
            value: GlobalConfig.scheme.matugenPrefix
            onEditingFinished: value => {
                GlobalConfig.scheme.matugenPrefix = value;
                GlobalConfig.save();
            }
        }

        TextFieldRow {
            visible: GlobalConfig.scheme.useMatugen
            last: true
            smallField: true
            label: qsTr("Opacity")
            subtext: qsTr("Template colour opacity, 0.0-1.0. Empty to omit")
            value: GlobalConfig.scheme.matugenOpacity
            placeholderText: "1.0"
            onEditingFinished: value => {
                GlobalConfig.scheme.matugenOpacity = value;
                GlobalConfig.save();
            }
        }

        SectionHeader {
            visible: GlobalConfig.scheme.useWallust
            text: qsTr("Wallust parameters")
        }

        TextFieldRow {
            visible: GlobalConfig.scheme.useWallust
            first: true
            label: qsTr("Config file")
            subtext: qsTr("Leave empty to use the default config path")
            value: GlobalConfig.scheme.wallustConfigPath
            placeholderText: "~/.config/wallust/wallust.toml"
            onEditingFinished: value => {
                GlobalConfig.scheme.wallustConfigPath = value;
                GlobalConfig.save();
            }
        }

        SelectRow {
            visible: GlobalConfig.scheme.useWallust
            label: qsTr("Backend")
            subtext: qsTr("Colour extraction backend, passed as -b (default fast-resize)")
            menuItems: wallustBackendItems.instances
            active: root.optionActive(GlobalConfig.scheme.wallustBackend, menuItems)
            fallbackText: GlobalConfig.scheme.wallustBackend || qsTr("Default")
        }

        SelectRow {
            visible: GlobalConfig.scheme.useWallust
            label: qsTr("Colorspace")
            subtext: qsTr("Colour sorting space, passed as -c (default lch)")
            menuItems: wallustColorspaceItems.instances
            active: root.optionActive(GlobalConfig.scheme.wallustColorspace, menuItems)
            fallbackText: GlobalConfig.scheme.wallustColorspace || qsTr("Default")
        }

        SelectRow {
            visible: GlobalConfig.scheme.useWallust
            label: qsTr("Palette")
            subtext: qsTr("Output palette, passed as -p (default from config)")
            menuItems: wallustPaletteItems.instances
            active: root.optionActive(GlobalConfig.scheme.wallustPalette, menuItems)
            fallbackText: GlobalConfig.scheme.wallustPalette || qsTr("Default")
        }

        TextFieldRow {
            visible: GlobalConfig.scheme.useWallust
            smallField: true
            label: qsTr("Threshold")
            subtext: qsTr("1-100, ignored when dynamic threshold is on. Empty to omit")
            value: GlobalConfig.scheme.wallustThreshold
            placeholderText: "20"
            onEditingFinished: value => {
                GlobalConfig.scheme.wallustThreshold = value;
                GlobalConfig.save();
            }
        }

        TextFieldRow {
            visible: GlobalConfig.scheme.useWallust
            smallField: true
            label: qsTr("Saturation")
            subtext: qsTr("Extra saturation, 1-100. Empty to omit")
            value: GlobalConfig.scheme.wallustSaturation
            placeholderText: "10"
            onEditingFinished: value => {
                GlobalConfig.scheme.wallustSaturation = value;
                GlobalConfig.save();
            }
        }

        TextFieldRow {
            visible: GlobalConfig.scheme.useWallust
            smallField: true
            label: qsTr("Alpha")
            subtext: qsTr("Template alpha, 0-100. Empty to omit")
            value: GlobalConfig.scheme.wallustAlpha
            placeholderText: "100"
            onEditingFinished: value => {
                GlobalConfig.scheme.wallustAlpha = value;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            visible: GlobalConfig.scheme.useWallust
            Layout.fillWidth: true
            text: qsTr("Dynamic threshold")
            subtext: qsTr("Automatically pick the threshold, passed as --dynamic-threshold")
            checked: GlobalConfig.scheme.wallustDynamicThreshold
            onToggled: {
                GlobalConfig.scheme.wallustDynamicThreshold = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            visible: GlobalConfig.scheme.useWallust
            Layout.fillWidth: true
            text: qsTr("Check contrast")
            subtext: qsTr("Ensure readable contrast against the background, passed as -k")
            checked: GlobalConfig.scheme.wallustCheckContrast
            onToggled: {
                GlobalConfig.scheme.wallustCheckContrast = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            visible: GlobalConfig.scheme.useWallust
            Layout.fillWidth: true
            text: qsTr("Skip terminal sequences")
            subtext: qsTr("Do not recolour open terminals, passed as -s")
            checked: GlobalConfig.scheme.wallustSkipSequences
            onToggled: {
                GlobalConfig.scheme.wallustSkipSequences = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            visible: GlobalConfig.scheme.useWallust
            last: true
            Layout.fillWidth: true
            text: qsTr("Skip templates")
            subtext: qsTr("Do not render templates, passed as -T")
            checked: GlobalConfig.scheme.wallustSkipTemplates
            onToggled: {
                GlobalConfig.scheme.wallustSkipTemplates = checked;
                GlobalConfig.save();
            }
        }

        SectionHeader {
            visible: !Wallpapers.externalColours
            text: qsTr("General")
        }

        ToggleRow {
            visible: !Wallpapers.externalColours
            first: true
            last: true
            Layout.fillWidth: true
            text: qsTr("Smart colour scheme")
            subtext: qsTr("Derive theme mode and variant from the wallpaper")
            checked: GlobalConfig.services.smartScheme
            onToggled: {
                GlobalConfig.services.smartScheme = checked;
                GlobalConfig.save();
            }
        }

        SectionHeader {
            visible: !Wallpapers.externalColours
            text: qsTr("Scheme Settings")
        }

        SelectRow {
            visible: !Wallpapers.externalColours
            first: true
            label: qsTr("Colour Scheme")
            subtext: qsTr("Select your base colour scheme style")
            menuItems: schemeItems.instances
            active: {
                const current = Colours.scheme + " " + Colours.flavour;
                const list = menuItems;
                for (let i = 0; i < list.length; i++) {
                    if (list[i].text === current)
                        return list[i];
                }
                return null;
            }
            fallbackText: Colours.scheme + " " + Colours.flavour
        }

        SelectRow {
            visible: !Wallpapers.externalColours
            last: true
            label: qsTr("Scheme Variant")
            subtext: qsTr("Select the color distribution algorithm")
            menuItems: variantItems.instances
            active: {
                const current = Colours.variant;
                let match = null;
                for (let i = 0; i < root.variantData.length; i++) {
                    if (root.variantData[i].name === current) {
                        match = root.variantData[i];
                        break;
                    }
                }
                if (!match) return null;
                const list = menuItems;
                for (let i = 0; i < list.length; i++) {
                    if (list[i].text === match.label)
                        return list[i];
                }
                return null;
            }
            fallbackText: Colours.variant
        }
    }
}
