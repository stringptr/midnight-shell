#pragma once

namespace caelestia::services {

// Toneless pinyin for a hanzi from the bundled 3500-char common subset, nullptr when outside it.
[[nodiscard]] const char* pinyinFor(char32_t ch);

} // namespace caelestia::services
