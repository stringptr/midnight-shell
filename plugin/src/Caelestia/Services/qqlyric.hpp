#pragma once

#include <qstring.h>
#include <qvector.h>

#include "lyrics.hpp"

namespace caelestia::services {

// Decrypts a QQ Music QRC payload: hex -> custom 3DES -> zlib -> UTF-8 XML.
// Returns an empty string on any failure; callers skip the romanized variant then.
[[nodiscard]] QString qqDecryptQrc(const QString& hex);

// Extracts the timed lines from a decrypted QRC XML document (time in seconds).
// Keeps empty-text lines: they mirror the LRC structure and mark lines without
// romanization. Only malformed lines are dropped.
[[nodiscard]] QVector<LyricLine> qqParseQrc(const QString& xml);

// Builds the romanized variant aligned 1:1 with the original lines. Prefers exact
// index pairing (QRC is line-parallel to the LRC); a non-empty latin QRC text
// replaces the original text, everything else keeps it. When line counts differ,
// falls back to pairing each original line with the nearest QRC line within 500 ms.
// Empty when no line was replaced.
[[nodiscard]] QVector<LyricLine> qqAlignRomanized(
    const QVector<LyricLine>& original, const QVector<LyricLine>& qrc);

} // namespace caelestia::services
