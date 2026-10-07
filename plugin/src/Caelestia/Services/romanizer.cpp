#include "romanizer.hpp"

#include <qhash.h>

#include "pinyin_data.hpp"

namespace caelestia::services {

using Qt::StringLiterals::operator""_s;

namespace {

enum class Script { Latin, Hangul, Kana, Han, Cyrillic, Greek, Mark, Other };

[[nodiscard]] Script classify(const char32_t u) {
    if ((u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || (u >= 0xC0 && u <= 0x24F)
        || (u >= 0x1E00 && u <= 0x1EFF) || (u >= 0x2C60 && u <= 0x2C7F) || (u >= 0xA720 && u <= 0xA7FF)
        || (u >= 0xFF21 && u <= 0xFF3A) || (u >= 0xFF41 && u <= 0xFF5A)) {
        return Script::Latin;
    }
    if ((u >= 0xAC00 && u <= 0xD7A3) || (u >= 0x1100 && u <= 0x11FF) || (u >= 0x3130 && u <= 0x318F)) {
        return Script::Hangul;
    }
    if ((u >= 0x3040 && u <= 0x30FF) || (u >= 0x31F0 && u <= 0x31FF)) {
        return Script::Kana;
    }
    if ((u >= 0x4E00 && u <= 0x9FFF) || (u >= 0x3400 && u <= 0x4DBF) || (u >= 0xF900 && u <= 0xFAFF)) {
        return Script::Han;
    }
    if ((u >= 0x400 && u <= 0x4FF) || (u >= 0x500 && u <= 0x52F) || (u >= 0xA640 && u <= 0xA69F)) {
        return Script::Cyrillic;
    }
    if ((u >= 0x370 && u <= 0x3FF) || (u >= 0x1F00 && u <= 0x1FFF)) {
        return Script::Greek;
    }
    if (u >= 0x300 && u <= 0x36F) {
        return Script::Mark;
    }
    return Script::Other;
}

[[nodiscard]] bool isVowelChar(const QChar c) {
    const char16_t v = c.unicode();
    return v == u'a' || v == u'i' || v == u'u' || v == u'e' || v == u'o';
}

void appendCp(QString& out, const char32_t u) {
    if (u <= 0xFFFF) {
        out.append(QChar(static_cast<char16_t>(u)));
        return;
    }
    const char32_t v = u - 0x10000;
    out.append(QChar(static_cast<char16_t>(0xD800 + (v >> 10))));
    out.append(QChar(static_cast<char16_t>(0xDC00 + (v & 0x3FF))));
}

// --- Korean: jamo decomposition with basic nasal assimilation ---------------------

// Choseong positions (ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ)
constexpr int kChoseongNieun = 2;
constexpr int kChoseongMieum = 6;
constexpr int kChoseongIeung = 11;

// Jongseong that shifts onto a following empty-onset (ㅇ) syllable: 국어 -> gugeo
[[nodiscard]] const char* movableOnset(const int ti) {
    switch (ti) {
    case 1:
        return "g";
    case 2:
        return "kk";
    case 7:
        return "d";
    case 8:
        return "r";
    case 17:
        return "b";
    case 19:
        return "s";
    case 20:
        return "ss";
    case 22:
        return "j";
    case 23:
        return "ch";
    case 24:
        return "k";
    case 25:
        return "t";
    case 26:
        return "p";
    default:
        return nullptr;
    }
}

[[nodiscard]] QString hangulSyllable(const char32_t s, const int nextChoseong, QString* onset) {
    static constexpr const char* kChoseong[] = { "g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s",
        "ss", "", "j", "jj", "ch", "k", "t", "p", "h" };
    static constexpr const char* kJungseong[] = { "a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa",
        "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i" };
    // Jongseong positions in syllable order:
    // none ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ
    static constexpr const char* kJongseong[] = { "", "k", "k", "k", "n", "n", "n", "t", "l", "k", "m", "p",
        "t", "t", "p", "l", "m", "p", "p", "t", "t", "ng", "t", "t", "k", "t", "p", "h" };

    const int si = static_cast<int>(s - 0xAC00);
    const int li = si / (21 * 28);
    const int vi = (si % (21 * 28)) / 28;
    const int ti = si % 28;

    QString out = QString::fromUtf8(kChoseong[li]) + QString::fromUtf8(kJungseong[vi]);
    if (ti == 0) {
        return out;
    }

    if (nextChoseong == kChoseongNieun || nextChoseong == kChoseongMieum) {
        // Nasal assimilation before a nasal onset: k-class -> ng, t-class -> n, p-class -> m
        switch (ti) {
        case 1:
        case 2:
        case 3:
        case 9:
        case 24:
            out += u"ng"_s;
            break;
        case 7:
        case 12:
        case 13:
        case 19:
        case 20:
        case 22:
        case 23:
        case 25:
            out += u"n"_s;
            break;
        case 11:
        case 14:
        case 17:
        case 18:
        case 26:
            out += u"m"_s;
            break;
        default:
            out += QString::fromUtf8(kJongseong[ti]);
            break;
        }
    } else if (nextChoseong == kChoseongIeung && ti == 27) {
        // ㅎ drops before a vowel-initial syllable (좋아 -> joa)
    } else if (nextChoseong == kChoseongIeung && movableOnset(ti) != nullptr) {
        // Liaison: 국어 -> gugeo (onset moves to the next syllable)
        if (onset != nullptr) {
            *onset = QString::fromUtf8(movableOnset(ti));
        }
    } else {
        out += QString::fromUtf8(kJongseong[ti]);
    }
    return out;
}

// --- Japanese: kana -> hepburn ----------------------------------------------------

[[nodiscard]] const QHash<char32_t, const char*>& kanaTable() {
    static const QHash<char32_t, const char*> k_map = {
        { 0x3042, "a" },   { 0x3044, "i" },   { 0x3046, "u" },   { 0x3048, "e" },   { 0x304A, "o" },
        { 0x3041, "a" },   { 0x3043, "i" },   { 0x3045, "u" },   { 0x3047, "e" },   { 0x3049, "o" },
        { 0x304B, "ka" },  { 0x304D, "ki" },  { 0x304F, "ku" },  { 0x3051, "ke" },  { 0x3053, "ko" },
        { 0x304C, "ga" },  { 0x304E, "gi" },  { 0x3050, "gu" },  { 0x3052, "ge" },  { 0x3054, "go" },
        { 0x3055, "sa" },  { 0x3057, "shi" }, { 0x3059, "su" },  { 0x305B, "se" },  { 0x305D, "so" },
        { 0x3056, "za" },  { 0x3058, "ji" },  { 0x305A, "zu" },  { 0x305C, "ze" },  { 0x305E, "zo" },
        { 0x305F, "ta" },  { 0x3061, "chi" }, { 0x3064, "tsu" }, { 0x3066, "te" },  { 0x3068, "to" },
        { 0x3060, "da" },  { 0x3062, "ji" },  { 0x3065, "zu" },  { 0x3067, "de" },  { 0x3069, "do" },
        { 0x306A, "na" },  { 0x306B, "ni" },  { 0x306C, "nu" },  { 0x306D, "ne" },  { 0x306E, "no" },
        { 0x306F, "ha" },  { 0x3072, "hi" },  { 0x3075, "fu" },  { 0x3078, "he" },  { 0x307B, "ho" },
        { 0x3070, "ba" },  { 0x3073, "bi" },  { 0x3076, "bu" },  { 0x3079, "be" },  { 0x307C, "bo" },
        { 0x3071, "pa" },  { 0x3074, "pi" },  { 0x3077, "pu" },  { 0x307A, "pe" },  { 0x307D, "po" },
        { 0x307E, "ma" },  { 0x307F, "mi" },  { 0x3080, "mu" },  { 0x3081, "me" },  { 0x3082, "mo" },
        { 0x3084, "ya" },  { 0x3086, "yu" },  { 0x3088, "yo" },
        { 0x3089, "ra" },  { 0x308A, "ri" },  { 0x308B, "ru" },  { 0x308C, "re" },  { 0x308D, "ro" },
        { 0x308F, "wa" },  { 0x3092, "o" },   { 0x3093, "n" },   { 0x3094, "vu" },
        { 0x3083, "ya" },  { 0x3085, "yu" },  { 0x3087, "yo" },  { 0x308E, "wa" },
        { 0x3095, "ka" },  { 0x3096, "ke" },
        { 0x3063, "" },    // sokuon consumed via lookahead
    };
    return k_map;
}

[[nodiscard]] bool isSmallYaYuYo(const char32_t u) {
    return u == 0x3083 || u == 0x3085 || u == 0x3087 || u == 0x30E3 || u == 0x30E5 || u == 0x30E7;
}

// Yaon and foreign-sound ligatures: "ki" + small ya -> "kya", "fu" + small a -> "fa", ...
[[nodiscard]] QString mergeSmall(const QString& base, const char32_t small) {
    if (base.isEmpty()) {
        return {};
    }
    if (isSmallYaYuYo(small)) {
        const bool ya = small == 0x3083 || small == 0x30E3;
        const bool yu = small == 0x3085 || small == 0x30E5;
        const char* suffix = ya ? "ya" : (yu ? "yu" : "yo");
        if (base == u"i"_s) {
            return QString::fromUtf8(suffix);
        }
        if (base == u"shi"_s || base == u"chi"_s || base == u"ji"_s) {
            // しゃ -> sha, しゅ -> shu (not shya/shyu)
            return base.chopped(1) + QString::fromUtf8(suffix + 1);
        }
        if (base.size() > 1 && base.back() == u'i') {
            return base.chopped(1) + QString::fromUtf8(suffix);
        }
        return {};
    }

    const bool sa = small == 0x3041;
    const bool si = small == 0x3043;
    const bool se = small == 0x3047;
    const bool so = small == 0x3049;
    if (!sa && !si && !se && !so) {
        return {};
    }
    const QChar vowel = sa ? u'a' : si ? u'i' : se ? u'e' : u'o';

    if (base == u"fu"_s) {
        return u"f"_s + vowel;
    }
    if (base == u"vu"_s) {
        return u"v"_s + vowel;
    }
    if (base == u"tsu"_s) {
        return u"ts"_s + vowel;
    }
    if (base == u"te"_s && si) {
        return u"ti"_s;
    }
    if (base == u"de"_s && si) {
        return u"di"_s;
    }
    if (base == u"u"_s && (si || se)) {
        return si ? u"wi"_s : u"we"_s;
    }
    if (se && (base == u"chi"_s || base == u"shi"_s || base == u"ji"_s)) {
        return base.chopped(1) + u"e"_s;
    }
    return {};
}

// --- Cyrillic / Greek ------------------------------------------------------------

[[nodiscard]] const QHash<char32_t, const char*>& cyrillicTable() {
    static const QHash<char32_t, const char*> k_map = {
        { 0x430, "a" },     { 0x431, "b" },     { 0x432, "v" },     { 0x433, "g" },
        { 0x434, "d" },     { 0x435, "e" },     { 0x451, "yo" },    { 0x436, "zh" },
        { 0x437, "z" },     { 0x438, "i" },     { 0x439, "y" },     { 0x43A, "k" },
        { 0x43B, "l" },     { 0x43C, "m" },     { 0x43D, "n" },     { 0x43E, "o" },
        { 0x43F, "p" },     { 0x440, "r" },     { 0x441, "s" },     { 0x442, "t" },
        { 0x443, "u" },     { 0x444, "f" },     { 0x445, "kh" },    { 0x446, "ts" },
        { 0x447, "ch" },    { 0x448, "sh" },    { 0x449, "shch" },  { 0x44A, "" },
        { 0x44B, "y" },     { 0x44C, "" },      { 0x44D, "e" },     { 0x44E, "yu" },
        { 0x44F, "ya" },    { 0x456, "i" },     { 0x457, "yi" },    { 0x455, "ye" },
        { 0x491, "g" },     { 0x45E, "u" },
    };
    return k_map;
}

[[nodiscard]] const QHash<char32_t, const char*>& greekTable() {
    static const QHash<char32_t, const char*> k_map = {
        { 0x3B1, "a" },  { 0x3B2, "v" },  { 0x3B3, "g" },  { 0x3B4, "d" },  { 0x3B5, "e" },
        { 0x3B6, "z" },  { 0x3B7, "i" },  { 0x3B8, "th" }, { 0x3B9, "i" },  { 0x3BA, "k" },
        { 0x3BB, "l" },  { 0x3BC, "m" },  { 0x3BD, "n" },  { 0x3BE, "x" },  { 0x3BF, "o" },
        { 0x3C0, "p" },  { 0x3C1, "r" },  { 0x3C3, "s" },  { 0x3C2, "s" },  { 0x3C4, "t" },
        { 0x3C5, "y" },  { 0x3C6, "f" },  { 0x3C7, "ch" }, { 0x3C8, "ps" }, { 0x3C9, "o" },
        { 0x3AC, "a" },  { 0x3AD, "e" },  { 0x3AE, "i" },  { 0x3AF, "i" },  { 0x3CC, "o" },
        { 0x3CD, "y" },  { 0x3CE, "o" },  { 0x390, "i" },  { 0x3B0, "y" },
        { 0x3CA, "i" },  { 0x3CB, "y" },
        { 0x391, "a" },  { 0x392, "v" },  { 0x393, "g" },  { 0x394, "d" },  { 0x395, "e" },
        { 0x396, "z" },  { 0x397, "i" },  { 0x398, "th" }, { 0x399, "i" },  { 0x39A, "k" },
        { 0x39B, "l" },  { 0x39C, "m" },  { 0x39D, "n" },  { 0x39E, "x" },  { 0x39F, "o" },
        { 0x3A0, "p" },  { 0x3A1, "r" },  { 0x3A3, "s" },  { 0x3A4, "t" },  { 0x3A5, "y" },
        { 0x3A6, "f" },  { 0x3A7, "ch" }, { 0x3A8, "ps" }, { 0x3A9, "o" },
        { 0x386, "a" },  { 0x388, "e" },  { 0x389, "i" },  { 0x38A, "i" },
        { 0x38C, "o" },  { 0x38E, "y" },  { 0x38F, "o" },
    };
    return k_map;
}

[[nodiscard]] char32_t foldCase(const char32_t u) {
    if (u >= 0x410 && u <= 0x42F) {
        return u + 0x20;
    }
    if (u >= 0x400 && u <= 0x40F) {
        return u + 0x50;
    }
    if (u == 0x490) {
        return 0x491;
    }
    if (u >= 0x391 && u <= 0x3A9) {
        return u + 0x20;
    }
    return u;
}

[[nodiscard]] QVector<char32_t> toCodepoints(const QString& text) {
    QVector<char32_t> out;
    out.reserve(text.size());
    for (qsizetype i = 0; i < text.size(); ++i) {
        const char16_t u1 = text.at(i).unicode();
        if (u1 >= 0xD800 && u1 <= 0xDBFF && i + 1 < text.size()) {
            const char16_t u2 = text.at(i + 1).unicode();
            if (u2 >= 0xDC00 && u2 <= 0xDFFF) {
                out.append(0x10000 + ((static_cast<char32_t>(u1) - 0xD800) << 10) + (u2 - 0xDC00));
                ++i;
                continue;
            }
        }
        if (!(u1 >= 0xDC00 && u1 <= 0xDFFF)) {
            out.append(u1);
        }
    }
    return out;
}

} // namespace

bool isLatinLetter(const char32_t u) {
    return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || (u >= 0xC0 && u <= 0x24F)
        || (u >= 0x1E00 && u <= 0x1EFF) || (u >= 0x2C60 && u <= 0x2C7F) || (u >= 0xA720 && u <= 0xA7FF)
        || (u >= 0xFF21 && u <= 0xFF3A) || (u >= 0xFF41 && u <= 0xFF5A);
}

bool isLatinScript(const QString& text) {
    for (const QChar c : text) {
        if (c.isLetter() && !isLatinLetter(c.unicode())) {
            return false;
        }
    }
    return true;
}

bool isLatinLrc(const QVector<LyricLine>& lines) {
    for (const auto& l : lines) {
        if (!isLatinScript(l.text)) {
            return false;
        }
    }
    return true;
}

QString romanizeText(const QString& text) {
    if (text.isEmpty()) {
        return {};
    }

    const QVector<char32_t> cps = toCodepoints(text);

    bool hangulSeen = false;
    bool kanaSeen = false;
    bool hanSeen = false;
    bool cyrillicSeen = false;
    bool greekSeen = false;
    for (const char32_t u : cps) {
        switch (classify(u)) {
        case Script::Hangul:
            hangulSeen = true;
            break;
        case Script::Kana:
            kanaSeen = true;
            break;
        case Script::Han:
            hanSeen = true;
            break;
        case Script::Cyrillic:
            cyrillicSeen = true;
            break;
        case Script::Greek:
            greekSeen = true;
            break;
        default:
            break;
        }
    }
    if (!hangulSeen && !kanaSeen && !hanSeen && !cyrillicSeen && !greekSeen) {
        return {};
    }

    const bool hanIsJapanese = kanaSeen;
    const auto& kana = kanaTable();
    QString out;
    out.reserve(text.size() * 2);
    QChar lastVowel;
    QString pendingOnset;

    for (qsizetype i = 0; i < cps.size(); ++i) {
        const char32_t u = cps.at(i);
        switch (classify(u)) {
        case Script::Mark:
            continue;
        case Script::Hangul: {
            if (u < 0xAC00 || u > 0xD7A3) {
                appendCp(out, u);
                break;
            }
            if (!pendingOnset.isEmpty()) {
                out += pendingOnset;
                pendingOnset.clear();
            }
            int nextChoseong = -1;
            if (i + 1 < cps.size()) {
                const char32_t n = cps.at(i + 1);
                if (n >= 0xAC00 && n <= 0xD7A3) {
                    nextChoseong = static_cast<int>((n - 0xAC00) / (21 * 28));
                }
            }
            const QString syl = hangulSyllable(u, nextChoseong, &pendingOnset);
            out += syl;
            if (!syl.isEmpty() && isVowelChar(syl.back())) {
                lastVowel = syl.back();
            }
            break;
        }
        case Script::Kana: {
            char32_t k = u;
            if (k >= 0x30A1 && k <= 0x30F6) {
                k -= 0x60; // katakana -> hiragana
            }
            if (k == 0x3063) {
                // Sokuon: double the next consonant
                if (i + 1 < cps.size()) {
                    char32_t n = cps.at(i + 1);
                    if (n >= 0x30A1 && n <= 0x30F6) {
                        n -= 0x60;
                    }
                    const char* base = kana.value(n, nullptr);
                    if (base) {
                        const QString next = QString::fromUtf8(base);
                        // っち -> "t"+"chi", まっちゃ -> "t"+"cha"; other kana double their first letter
                        if (next.startsWith(u"ch"_s)) {
                            out += u"t"_s;
                        } else if (!next.isEmpty() && !isVowelChar(next.front())) {
                            out += next.front();
                        }
                    }
                }
                break;
            }
            if (k == 0x30FC) {
                // Prolonged sound mark: repeat the previous vowel
                out += lastVowel.isNull() ? QChar(u'-') : lastVowel;
                break;
            }
            const char* base = kana.value(k, nullptr);
            if (!base) {
                appendCp(out, u);
                break;
            }
            QString r = QString::fromUtf8(base);
            if (i + 1 < cps.size()) {
                char32_t n = cps.at(i + 1);
                if (n >= 0x30A1 && n <= 0x30F6) {
                    n -= 0x60;
                }
                if (isSmallYaYuYo(n) || n == 0x3041 || n == 0x3043 || n == 0x3047 || n == 0x3049) {
                    const QString merged = mergeSmall(r, n);
                    if (!merged.isEmpty()) {
                        r = merged;
                        ++i;
                    }
                }
            }
            out += r;
            if (!r.isEmpty() && isVowelChar(r.back())) {
                lastVowel = r.back();
            }
            break;
        }
        case Script::Han: {
            if (hanIsJapanese) {
                appendCp(out, u);
                break;
            }
            if (const char* py = pinyinFor(u)) {
                const QString s = QString::fromUtf8(py);
                out += s;
                if (!s.isEmpty() && isVowelChar(s.back())) {
                    lastVowel = s.back();
                }
            } else {
                appendCp(out, u);
            }
            break;
        }
        case Script::Cyrillic: {
            const char* lat = cyrillicTable().value(foldCase(u), nullptr);
            if (lat) {
                const QString s = QString::fromUtf8(lat);
                out += s;
                if (!s.isEmpty() && isVowelChar(s.back())) {
                    lastVowel = s.back();
                }
            } else {
                appendCp(out, u);
            }
            break;
        }
        case Script::Greek: {
            const char* lat = greekTable().value(foldCase(u), nullptr);
            if (lat) {
                const QString s = QString::fromUtf8(lat);
                out += s;
                if (!s.isEmpty() && isVowelChar(s.back())) {
                    lastVowel = s.back();
                }
            } else {
                appendCp(out, u);
            }
            break;
        }
        default:
            appendCp(out, u);
            break;
        }
    }

    if (out == text || !isLatinScript(out)) {
        return {};
    }
    return out;
}

QVector<LyricLine> romanizeLines(const QVector<LyricLine>& lines) {
    QVector<LyricLine> out;
    out.reserve(lines.size());
    bool any = false;
    for (const auto& l : lines) {
        const QString r = romanizeText(l.text);
        if (!r.isEmpty()) {
            any = true;
            out.append(LyricLine{ .time = l.time, .text = r });
        } else {
            out.append(l);
        }
    }
    return any ? out : QVector<LyricLine>{};
}

} // namespace caelestia::services
