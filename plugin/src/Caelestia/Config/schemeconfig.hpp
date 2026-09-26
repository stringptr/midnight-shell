#pragma once

#include <qstring.h>

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

class SchemeConfig : public settings::ObjectNode {
    CONFIG_NODE(SchemeConfig, settings::ObjectNode)

    // External colour generation backends. When any is enabled, the shell stops
    // generating/applying colours itself (caelestia wallpaper runs with
    // --no-scheme) and runs the tool instead.
    CONFIG_GLOBAL_PROPERTY(bool, useMatugen, false)
    CONFIG_GLOBAL_PROPERTY(bool, useWallust, false)

    // Matugen. Empty string => omit the flag (tool default / config file applies)
    CONFIG_GLOBAL_PROPERTY(QString, matugenConfigPath, QString()) // -c/--config
    CONFIG_GLOBAL_PROPERTY(QString, matugenType, QString()) // -t/--type
    CONFIG_GLOBAL_PROPERTY(QString, matugenMode, QString()) // -m/--mode
    CONFIG_GLOBAL_PROPERTY(QString, matugenContrast, QString()) // --contrast (-1..1)
    CONFIG_GLOBAL_PROPERTY(QString, matugenSourceColorIndex, QString()) // --source-color-index (0..3)
    CONFIG_GLOBAL_PROPERTY(QString, matugenPrefix, QString()) // -p/--prefix
    CONFIG_GLOBAL_PROPERTY(QString, matugenOpacity, QString()) // --opacity (0.0..1.0)

    // Wallust. Empty string / false => omit the flag
    CONFIG_GLOBAL_PROPERTY(QString, wallustConfigPath, QString()) // -C/--config-file
    CONFIG_GLOBAL_PROPERTY(QString, wallustBackend, QString()) // -b/--backend
    CONFIG_GLOBAL_PROPERTY(QString, wallustColorspace, QString()) // -c/--colorspace
    CONFIG_GLOBAL_PROPERTY(QString, wallustPalette, QString()) // -p/--palette
    CONFIG_GLOBAL_PROPERTY(QString, wallustThreshold, QString()) // -t/--threshold (1..100)
    CONFIG_GLOBAL_PROPERTY(QString, wallustSaturation, QString()) // --saturation (1..100)
    CONFIG_GLOBAL_PROPERTY(QString, wallustAlpha, QString()) // -a/--alpha (0..100)
    CONFIG_GLOBAL_PROPERTY(bool, wallustCheckContrast, false) // -k/--check-contrast
    // Conflicts with -t, so when enabled the threshold flag is always omitted
    CONFIG_GLOBAL_PROPERTY(bool, wallustDynamicThreshold, false) // --dynamic-threshold
    CONFIG_GLOBAL_PROPERTY(bool, wallustSkipSequences, false) // -s/--skip-sequences
    CONFIG_GLOBAL_PROPERTY(bool, wallustSkipTemplates, false) // -T/--skip-templates
};

} // namespace caelestia::config
