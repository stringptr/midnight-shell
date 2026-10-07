#pragma once

#include <qbytearray.h>

namespace caelestia::services {

// Decrypts QQ Music QRC lyric payloads (hex-decoded input, custom 3DES-EDE).
// Returns an empty array when the input is malformed; callers still inflate the result.
[[nodiscard]] QByteArray qrc3desDecrypt(const QByteArray& cipher);

} // namespace caelestia::services
