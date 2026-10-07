#pragma once

#include <qstring.h>
#include <qvector.h>

#include "lyrics.hpp"

namespace caelestia::services {

// True when the codepoint is a latin-script letter (accents included).
[[nodiscard]] bool isLatinLetter(char32_t u);

// True when the text contains only latin-script letters (punctuation/digits are ignored).
[[nodiscard]] bool isLatinScript(const QString& text);

[[nodiscard]] bool isLatinLrc(const QVector<LyricLine>& lines);

// On-device romanization used when no curated romanized variant (e.g. NetEase romalrc) exists.
// Korean (revised romanization), kana-only Japanese, Cyrillic and Greek convert completely;
// hanzi lines without kana convert through a bundled toneless pinyin subset (a line keeps any
// character outside the subset, which rejects the line as not fully latin-script).
// Returns an empty string when the line cannot be fully romanized; callers keep the original.
[[nodiscard]] QString romanizeText(const QString& text);

// Applies romanizeText line by line; empty when no line converted (variant would equal original).
[[nodiscard]] QVector<LyricLine> romanizeLines(const QVector<LyricLine>& lines);

} // namespace caelestia::services
