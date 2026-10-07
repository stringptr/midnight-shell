#include "qqlyric.hpp"

#include <algorithm>
#include <cmath>
#include <zlib.h>

#include <qregularexpression.h>

#include "qrc3des.hpp"
#include "romanizer.hpp"

namespace caelestia::services {

using Qt::StringLiterals::operator""_s;

namespace {

[[nodiscard]] QString inflate(const QByteArray& deflated) {
    if (deflated.isEmpty()) {
        return {};
    }

    z_stream stream{};
    stream.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(deflated.constData()));
    stream.avail_in = static_cast<uInt>(deflated.size());
    if (inflateInit(&stream) != Z_OK) {
        return {};
    }

    QByteArray out;
    char buffer[16384];
    int ret = Z_OK;
    do {
        stream.next_out = reinterpret_cast<Bytef*>(buffer);
        stream.avail_out = sizeof(buffer);
        ret = ::inflate(&stream, Z_NO_FLUSH);
        if (ret != Z_OK && ret != Z_STREAM_END) {
            inflateEnd(&stream);
            return {};
        }
        out.append(buffer, static_cast<qsizetype>(sizeof(buffer)) - stream.avail_out);
    } while (ret != Z_STREAM_END);

    inflateEnd(&stream);
    if (ret != Z_STREAM_END) {
        return {};
    }
    return QString::fromUtf8(out);
}

void unescapeXml(QString& text) {
    // Order matters: &amp; expands last
    text.replace(u"&lt;"_s, u"<"_s);
    text.replace(u"&gt;"_s, u">"_s);
    text.replace(u"&quot;"_s, u"\""_s);
    text.replace(u"&apos;"_s, u"'"_s);
    text.replace(u"&amp;"_s, u"&"_s);
}

} // namespace

QString qqDecryptQrc(const QString& hex) {
    static const QRegularExpression k_hex(u"^[0-9a-fA-F]+$"_s);
    if (hex.isEmpty() || hex.size() % 2 != 0 || !k_hex.match(hex).hasMatch()) {
        return {};
    }

    const QByteArray raw = QByteArray::fromHex(hex.toLatin1());
    if (raw.isEmpty() || raw.size() % 8 != 0) {
        return {};
    }
    const QByteArray plain = qrc3desDecrypt(raw);
    if (plain.isEmpty()) {
        return {};
    }
    return inflate(plain);
}

QVector<LyricLine> qqParseQrc(const QString& xml) {
    QVector<LyricLine> result;
    if (xml.isEmpty()) {
        return result;
    }

    static const QRegularExpression k_content(u"LyricContent=\"([\\s\\S]*?)\"\\s*/>"_s);
    const auto contentMatch = k_content.match(xml);
    if (!contentMatch.hasMatch()) {
        return result;
    }
    QString content = contentMatch.captured(1);
    unescapeXml(content);

    static const QRegularExpression k_line(u"^\\[(\\d+),(\\d+)\\](.*)$"_s);
    static const QRegularExpression k_word(u"\\((\\d+),(\\d+)\\)"_s);

    const QStringList rawLines = content.split(u'\n');
    for (const QString& rawLine : rawLines) {
        const auto lineMatch = k_line.match(rawLine.trimmed());
        if (!lineMatch.hasMatch()) {
            continue;
        }
        const qreal time = lineMatch.captured(1).toDouble() / 1000.0;
        const QString body = lineMatch.captured(3);

        // "text(start,dur)text(start,dur)..." - keep the text segments, drop the timings
        QString text;
        qsizetype last = 0;
        auto it = k_word.globalMatch(body);
        while (it.hasNext()) {
            const auto m = it.next();
            text += body.mid(last, m.capturedStart() - last);
            last = m.capturedEnd();
        }
        text += body.mid(last);
        text = text.simplified();

        // Empty entries are structural (no romanization for that line); qqAlignRomanized
        // pairs by index, so they must be kept.
        result.append(LyricLine{ .time = time, .text = text });
    }

    std::ranges::sort(result, [](const LyricLine& a, const LyricLine& b) {
        return a.time < b.time;
    });
    return result;
}

QVector<LyricLine> qqAlignRomanized(const QVector<LyricLine>& original, const QVector<LyricLine>& qrc) {
    QVector<LyricLine> out;
    out.reserve(original.size());
    bool any = false;

    // QRC mirrors the LRC structure line-for-line (empty QRC line = no romanization
    // for that line), so index pairing is exact and collision-free. Times stay the
    // original ones; the UI keys the variant off the original timing anyway.
    if (!original.isEmpty() && original.size() == qrc.size()) {
        for (qsizetype i = 0; i < original.size(); ++i) {
            const QString& roman = qrc[i].text;
            if (!roman.isEmpty() && isLatinScript(roman)) {
                out.append(LyricLine{ .time = original[i].time, .text = roman });
                any = true;
            } else {
                out.append(original[i]);
            }
        }
        return any ? out : QVector<LyricLine>{};
    }

    // Degenerate case (parsed line counts differ): nearest QRC line within 500 ms.
    for (const auto& line : original) {
        const LyricLine* best = nullptr;
        qreal bestDiff = 0.5;
        for (const auto& candidate : qrc) {
            const qreal diff = std::fabs(candidate.time - line.time);
            if (diff <= bestDiff && !candidate.text.isEmpty() && isLatinScript(candidate.text)) {
                best = &candidate;
                bestDiff = diff;
            }
        }
        if (best != nullptr) {
            out.append(LyricLine{ .time = line.time, .text = best->text });
            any = true;
        } else {
            out.append(line);
        }
    }

    return any ? out : QVector<LyricLine>{};
}

} // namespace caelestia::services
