#include "lyrics.hpp"

#include <qdiriterator.h>
#include <qfileinfo.h>
#include <qjsonarray.h>
#include <qnetworkcookiejar.h>
#include <qsavefile.h>
#include <qurlquery.h>

#include <algorithm>

#include "config/rootnodes.hpp"
#include "config/serviceconfig.hpp"
#include "config/userpaths.hpp"

namespace {

Q_LOGGING_CATEGORY(lcLyrics, "caelestia.lyrics", QtInfoMsg)

} // namespace

namespace caelestia::services {

using Qt::StringLiterals::operator""_s;
using Qt::StringLiterals::operator""_ba;

namespace {

constexpr int k_loadDebounceMs = 50;
constexpr qreal k_indexFudge = 0.1;

[[nodiscard]] const QHash<QByteArray, QByteArray>& netEaseHeaders() {
    static const QHash<QByteArray, QByteArray> k_h = {
        { "User-Agent"_ba, "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0"_ba },
        { "Referer"_ba, "https://music.163.com/"_ba },
    };
    return k_h;
}

[[nodiscard]] const QHash<QByteArray, QByteArray>& lrclibHeaders() {
    static const QHash<QByteArray, QByteArray> k_h = {
        { "User-Agent"_ba, "caelestia-shell (https://github.com/caelestia-dots/shell)"_ba },
    };
    return k_h;
}

[[nodiscard]] QString joinArtists(const QString& s) {
    return s.trimmed();
}

[[nodiscard]] QString sanitizeFilenamePart(const QString& s) {
    QString out;
    out.reserve(s.size());
    for (const QChar c : s) {
        if (c == u'/' || c == u'\0') {
            out.append(u'_');
        } else {
            out.append(c);
        }
    }
    return out;
}

[[nodiscard]] bool containsCi(const QString& haystack, const QString& needle) {
    return haystack.contains(needle, Qt::CaseInsensitive);
}

[[nodiscard]] bool isLatinLetter(const char32_t u) {
    return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || (u >= 0xC0 && u <= 0x24F)
        || (u >= 0x1E00 && u <= 0x1EFF) || (u >= 0x2C60 && u <= 0x2C7F) || (u >= 0xA720 && u <= 0xA7FF)
        || (u >= 0xFF21 && u <= 0xFF3A) || (u >= 0xFF41 && u <= 0xFF5A);
}

// True when the text contains only latin-script letters (punctuation/digits are ignored).
[[nodiscard]] bool isLatinScript(const QString& text) {
    for (const QChar c : text) {
        if (c.isLetter() && !isLatinLetter(c.unicode())) {
            return false;
        }
    }
    return true;
}

[[nodiscard]] bool isLatinLrc(const QVector<LyricLine>& lines) {
    for (const auto& l : lines) {
        if (!isLatinScript(l.text)) {
            return false;
        }
    }
    return true;
}

[[nodiscard]] QStringList toTextList(const QVector<LyricLine>& lines) {
    QStringList list;
    list.reserve(lines.size());
    for (const auto& l : lines) {
        list.append(l.text);
    }
    return list;
}

} // namespace

Lyrics::Lyrics(QObject* parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_loadDebounce(new QTimer(this)) {
    m_loadDebounce->setSingleShot(true);
    m_loadDebounce->setInterval(k_loadDebounceMs);
    QObject::connect(m_loadDebounce, &QTimer::timeout, this, &Lyrics::doLoad);

    const auto* cfg = config::ConfigSingleton::instance();
    const auto* svcCfg = cfg->services();
    const auto* paths = cfg->paths();

    m_preferredBackend = svcCfg->lyricsBackend();
    m_romanized = svcCfg->lyricsRomanized();

    QObject::connect(
        svcCfg, &config::ServiceConfig::lyricsBackendChanged, this, &Lyrics::onPreferredBackendConfigChanged);
    QObject::connect(svcCfg, &config::ServiceConfig::lyricsRomanizedChanged, this, &Lyrics::onRomanizedConfigChanged);
    QObject::connect(paths, &config::UserPaths::lyricsDirChanged, this, &Lyrics::onLyricsDirChanged);

    loadLyricsMap();
}

QStringList Lyrics::lyrics() const {
    return m_lyrics;
}

LyricsBackend Lyrics::backend() const {
    return m_backend;
}

LyricsBackend Lyrics::preferredBackend() const {
    return m_preferredBackend;
}

void Lyrics::setPreferredBackend(LyricsBackend value) {
    if (m_preferredBackend == value) {
        return;
    }
    m_preferredBackend = value;
    emit preferredBackendChanged();

    config::ConfigSingleton::instance()->services()->set_lyricsBackend(value);

    scheduleLoad();
}

bool Lyrics::romanized() const {
    return m_romanized;
}

void Lyrics::setRomanized(bool value) {
    if (m_romanized == value) {
        return;
    }
    m_romanized = value;
    emit romanizedChanged();

    config::ConfigSingleton::instance()->services()->set_lyricsRomanized(value);

    updateActiveLyrics();
    scheduleLoad();
}

bool Lyrics::showRomanized() const {
    return m_showRomanized;
}

void Lyrics::setShowRomanized(bool value) {
    if (m_showRomanized == value || !m_hasRomanized) {
        return;
    }
    m_showRomanized = value;
    emit showRomanizedChanged();

    const QStringList active = value ? m_lyricsRomanized : m_lyricsOriginal;
    if (active != m_lyrics) {
        m_lyrics = active;
    }
    const bool hasLyrics = !m_lyrics.isEmpty();
    if (hasLyrics != m_hasLyrics) {
        m_hasLyrics = hasLyrics;
        emit hasLyricsChanged();
    }
    emit lyricsChanged();
}

bool Lyrics::hasRomanized() const {
    return m_hasRomanized;
}

QList<LyricCandidate> Lyrics::lyricCandidates() const {
    return m_candidates;
}

LyricCandidate Lyrics::selectedCandidate() const {
    return m_selected;
}

void Lyrics::setSelectedCandidate(const LyricCandidate& value) {
    if (m_selected == value) {
        return;
    }
    m_selected = value;
    emit selectedCandidateChanged();

    if (!value.isValid()) {
        return;
    }

    const auto b = value.backend();
    setBackend(b);
    setLoading(true);

    cancelInFlight();
    const int reqId = newRequestId();

    if (b == LyricsBackend::LRCLIB || b == LyricsBackend::NetEase) {
        const QString cached = readCachedLrc(b, value.id());
        if (!cached.isEmpty()) {
            const auto lines = parseLrc(cached);
            if (!lines.isEmpty()) {
                QVector<LyricLine> romanized;
                if (m_romanized && b == LyricsBackend::NetEase) {
                    romanized = parseLrc(readCachedRomanizedLrc(b, value.id()));
                }
                if (!m_romanized || !romanized.isEmpty() || isLatinLrc(lines)) {
                    setLines(lines, b, romanized);
                    setLoading(false);
                    if (!m_settingFromPrefs) {
                        persistTrackPrefs();
                    }
                    return;
                }
                qCDebug(lcLyrics) << "romanized: cached" << b << "lyrics unusable, refetching id" << value.id();
            }
        }
    }

    if (b == LyricsBackend::LRCLIB) {
        fetchLrclibById(value.id(), reqId);
    } else if (b == LyricsBackend::NetEase) {
        fetchNetEaseLyricsById(value.id(), reqId);
    } else if (b == LyricsBackend::Local) {
        // For local, the id is the file path. Read directly.
        QFile f(value.id());
        if (f.open(QIODevice::ReadOnly)) {
            const QString text = QString::fromUtf8(f.readAll());
            const auto lines = parseLrc(text);
            if (acceptRomanized(lines)) {
                setLines(lines, LyricsBackend::Local);
            } else {
                qCDebug(lcLyrics) << "romanized: local candidate not latin-script" << value.id();
            }
            setLoading(false);
        } else {
            qCWarning(lcLyrics) << "selectedCandidate: cannot open local file" << value.id();
            setLoading(false);
        }
    }

    if (!m_settingFromPrefs) {
        persistTrackPrefs();
    }
}

bool Lyrics::loading() const {
    return m_loading;
}

bool Lyrics::hasLyrics() const {
    return m_hasLyrics;
}

qreal Lyrics::offset() const {
    return m_offset;
}

void Lyrics::setOffset(qreal value) {
    if (qFuzzyCompare(m_offset, value)) {
        return;
    }
    m_offset = value;
    emit offsetChanged();

    if (!m_settingFromPrefs) {
        persistTrackPrefs();
    }
}

QString Lyrics::trackArtist() const {
    return m_artist;
}

QString Lyrics::trackTitle() const {
    return m_title;
}

int Lyrics::indexForTime(qreal time) const {
    if (m_lines.isEmpty()) {
        return -1;
    }
    const qreal target = time - m_offset + k_indexFudge;
    qsizetype lo = 0;
    qsizetype hi = m_lines.size();
    while (lo < hi) {
        const qsizetype mid = lo + (hi - lo) / 2;
        if (m_lines.at(mid).time <= target) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return static_cast<int>(lo - 1);
}

qreal Lyrics::timeForIndex(int index) const {
    if (index < 0 || index >= m_lines.size()) {
        return -1.0;
    }
    return m_lines.at(index).time + m_offset;
}

void Lyrics::setTrack(const QString& artist, const QString& title, const QString& album, qreal duration) {
    const QString a = artist.trimmed();
    const QString t = title.trimmed();

    if (a == m_artist && t == m_title && album == m_album && qFuzzyCompare(duration + 1.0, m_duration + 1.0)) {
        return;
    }

    m_artist = a;
    m_title = t;
    m_album = album;
    m_duration = duration;
    emit trackChanged();

    scheduleLoad();
}

void Lyrics::clearTrack() {
    cancelInFlight();
    m_artist.clear();
    m_title.clear();
    m_album.clear();
    m_duration = 0.0;
    emit trackChanged();

    clearCandidates();
    clearLines();
    setLoading(false);
}

void Lyrics::refresh() {
    scheduleLoad();
}

void Lyrics::setBackend(LyricsBackend value) {
    if (m_backend == value) {
        return;
    }
    m_backend = value;
    emit backendChanged();
}

void Lyrics::setLoading(bool value) {
    if (m_loading == value) {
        return;
    }
    m_loading = value;
    emit loadingChanged();
}

void Lyrics::setLines(QVector<LyricLine> lines, LyricsBackend source, QVector<LyricLine> romanized) {
    const auto byTime = [](const LyricLine& a, const LyricLine& b) {
        return a.time < b.time;
    };
    std::ranges::sort(lines, byTime);
    std::ranges::sort(romanized, byTime);

    m_linesOriginal = lines;
    m_linesRomanized = romanized;
    // Timed vector drives indexForTime; variants share timestamps, prefer the original
    m_lines = !lines.isEmpty() ? std::move(lines) : std::move(romanized);
    m_lyricsOriginal = toTextList(m_linesOriginal);
    m_lyricsRomanized = toTextList(m_linesRomanized);

    setBackend(source);
    updateActiveLyrics();
}

void Lyrics::updateActiveLyrics() {
    const bool hasRomanized = m_romanized && !m_lyricsRomanized.isEmpty() && m_lyricsRomanized != m_lyricsOriginal;
    if (hasRomanized != m_hasRomanized) {
        m_hasRomanized = hasRomanized;
        emit hasRomanizedChanged();
    }

    const bool show = m_romanized && m_hasRomanized;
    if (show != m_showRomanized) {
        m_showRomanized = show;
        emit showRomanizedChanged();
    }

    const QStringList active = m_showRomanized ? m_lyricsRomanized : m_lyricsOriginal;
    if (active != m_lyrics) {
        m_lyrics = active;
    }

    const bool hasLyrics = !m_lyrics.isEmpty();
    if (hasLyrics != m_hasLyrics) {
        m_hasLyrics = hasLyrics;
        emit hasLyricsChanged();
    }
    // lyricsChanged is also the NOTIFY for hasLyrics, always emit like setLines did before
    emit lyricsChanged();
}

bool Lyrics::acceptRomanized(const QVector<LyricLine>& lines) const {
    if (!m_romanized) {
        return true;
    }
    // Local/LRCLIB have no romanized variants, only accept latin-script results
    return isLatinLrc(lines);
}

void Lyrics::clearLines() {
    if (!m_hasLyrics) {
        return;
    }

    // Doesn't actually clear lines, set a flag instead so anims can run
    m_hasLyrics = false;
    emit hasLyricsChanged();
    if (m_hasRomanized) {
        m_hasRomanized = false;
        emit hasRomanizedChanged();
    }
}

void Lyrics::appendCandidates(const QList<LyricCandidate>& add) {
    if (add.isEmpty()) {
        return;
    }
    bool changed = false;
    for (const auto& c : add) {
        if (!m_candidates.contains(c)) {
            m_candidates.append(c);
            changed = true;
        }
    }
    if (changed) {
        emit lyricCandidatesChanged();
    }
}

void Lyrics::clearCandidates() {
    if (m_candidates.isEmpty()) {
        return;
    }
    m_candidates.clear();
    emit lyricCandidatesChanged();
}

void Lyrics::scheduleLoad() {
    m_loadDebounce->start();
}

int Lyrics::newRequestId() {
    return ++m_currentRequestId;
}

void Lyrics::cancelInFlight() {
    for (auto it = m_pendingReplies.begin(); it != m_pendingReplies.end(); ++it) {
        const auto& replies = it.value();
        for (const auto& ptr : replies) {
            if (auto* const reply = ptr.data()) {
                reply->abort();
                reply->deleteLater();
            }
        }
    }
    m_pendingReplies.clear();
}

void Lyrics::trackReply(int reqId, QNetworkReply* reply) {
    if (!reply) {
        return;
    }
    m_pendingReplies[reqId].append(QPointer<QNetworkReply>(reply));
}

void Lyrics::doLoad() {
    if (m_artist.isEmpty() && m_title.isEmpty()) {
        clearLines();
        clearCandidates();
        setLoading(false);
        return;
    }

    cancelInFlight();
    const int reqId = newRequestId();

    setLoading(true);
    clearLines();
    clearCandidates();

    // Restore per-track prefs (offset, last-selected backend/id)
    m_settingFromPrefs = true;
    const QJsonObject saved = m_lyricsMap.value(trackKey()).toObject();
    setOffset(saved.value(u"offset"_s).toDouble(0.0));
    LyricCandidate restored;
    const QString savedBackendKey = saved.value(u"backend"_s).toString();
    const QString savedId = saved.value(u"id"_s).toString();
    if (!savedBackendKey.isEmpty() && !savedId.isEmpty()) {
        restored = LyricCandidate(backendFromKey(savedBackendKey), savedId, m_title, m_artist, m_album, m_duration);
    }
    m_settingFromPrefs = false;

    // Local/LRCLIB cannot provide romanized lyrics; fail fast when pinned to either
    if (m_romanized && (m_preferredBackend == LyricsBackend::Local || m_preferredBackend == LyricsBackend::LRCLIB)) {
        qCDebug(lcLyrics) << "romanized: backend" << m_preferredBackend << "cannot provide romanized lyrics";
        setLoading(false);
        return;
    }

    // Always populate online candidates for the picker, regardless of preferred backend
    searchLrclibCandidates(reqId);
    searchNetEaseCandidates(reqId);

    if (restored.isValid()) {
        // Honor saved selection for this track
        m_settingFromPrefs = true;
        setSelectedCandidate(restored);
        m_settingFromPrefs = false;
        return;
    }

    // Primary attempt by preferred backend
    switch (m_preferredBackend) {
    case LyricsBackend::Local:
        tryLocal(reqId);
        break;
    case LyricsBackend::LRCLIB:
        tryLrclib(reqId);
        break;
    case LyricsBackend::NetEase:
        tryNetEase(reqId);
        break;
    case LyricsBackend::Auto:
    default:
        tryLocal(reqId);
        break;
    }
}

void Lyrics::chainNext(LyricsBackend justFailed, int reqId) {
    if (m_preferredBackend != LyricsBackend::Auto) {
        // Non-auto modes don't chain
        setLoading(false);
        return;
    }
    switch (justFailed) {
    case LyricsBackend::Local:
        tryLrclib(reqId);
        return;
    case LyricsBackend::LRCLIB:
        tryNetEase(reqId);
        return;
    case LyricsBackend::NetEase:
    default:
        setLoading(false);
        return;
    }
}

void Lyrics::tryLocal(int reqId) {
    if (reqId != m_currentRequestId) {
        return;
    }

    setBackend(LyricsBackend::Local);

    const QString dir = lyricsDir();
    if (dir.isEmpty()) {
        chainNext(LyricsBackend::Local, reqId);
        return;
    }

    const QString direct = tryReadLocalLrc(dir, m_artist, m_title);
    if (!direct.isEmpty()) {
        QFile f(direct);
        if (f.open(QIODevice::ReadOnly)) {
            const QString text = QString::fromUtf8(f.readAll());
            const auto lines = parseLrc(text);
            if (!lines.isEmpty() && acceptRomanized(lines)) {
                setLines(lines, LyricsBackend::Local);
                appendCandidates(
                    { LyricCandidate(LyricsBackend::Local, direct, m_title, m_artist, m_album, m_duration) });
                m_selected = LyricCandidate(LyricsBackend::Local, direct, m_title, m_artist, m_album, m_duration);
                emit selectedCandidateChanged();
                if (!m_settingFromPrefs) {
                    persistTrackPrefs();
                }
                setLoading(false);
                return;
            }
        }
    }

    const QString recursive = findLocalLrcRecursive(dir, m_artist, m_title);
    if (!recursive.isEmpty()) {
        QFile f(recursive);
        if (f.open(QIODevice::ReadOnly)) {
            const QString text = QString::fromUtf8(f.readAll());
            const auto lines = parseLrc(text);
            if (!lines.isEmpty() && acceptRomanized(lines)) {
                setLines(lines, LyricsBackend::Local);
                appendCandidates(
                    { LyricCandidate(LyricsBackend::Local, recursive, m_title, m_artist, m_album, m_duration) });
                m_selected = LyricCandidate(LyricsBackend::Local, recursive, m_title, m_artist, m_album, m_duration);
                emit selectedCandidateChanged();
                if (!m_settingFromPrefs) {
                    persistTrackPrefs();
                }
                setLoading(false);
                return;
            }
        }
    }

    qCDebug(lcLyrics) << "no local lrc for" << m_artist << "-" << m_title;
    chainNext(LyricsBackend::Local, reqId);
}

void Lyrics::tryLrclib(int reqId) {
    if (reqId != m_currentRequestId) {
        return;
    }

    setBackend(LyricsBackend::LRCLIB);

    QUrl url(u"https://lrclib.net/api/get"_s);
    QUrlQuery q;
    q.addQueryItem(u"track_name"_s, m_title);
    q.addQueryItem(u"artist_name"_s, m_artist);
    if (!m_album.isEmpty()) {
        q.addQueryItem(u"album_name"_s, m_album);
    }

    constexpr qreal k_maxDurationSecs = std::numeric_limits<int>::max();
    if (m_duration > 0 && qIsFinite(m_duration) && m_duration < k_maxDurationSecs) {
        q.addQueryItem(u"duration"_s, QString::number(qRound(m_duration)));
    }
    url.setQuery(q);

    auto* reply = getJson(url, lrclibHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCDebug(lcLyrics) << "lrclib /get error:" << reply->errorString();
            chainNext(LyricsBackend::LRCLIB, reqId);
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonObject obj = doc.object();
        const QString synced = obj.value(u"syncedLyrics"_s).toString();
        const qint64 id = static_cast<qint64>(obj.value(u"id"_s).toDouble());

        if (synced.isEmpty()) {
            qCDebug(lcLyrics) << "lrclib: no syncedLyrics for" << m_artist << "-" << m_title;
            chainNext(LyricsBackend::LRCLIB, reqId);
            return;
        }

        const auto lines = parseLrc(synced);
        if (lines.isEmpty()) {
            chainNext(LyricsBackend::LRCLIB, reqId);
            return;
        }
        if (!acceptRomanized(lines)) {
            qCDebug(lcLyrics) << "romanized: lrclib lyrics not latin-script, skipping";
            chainNext(LyricsBackend::LRCLIB, reqId);
            return;
        }

        writeCachedLrc(LyricsBackend::LRCLIB, QString::number(id), synced);
        setLines(lines, LyricsBackend::LRCLIB);
        const LyricCandidate cand(LyricsBackend::LRCLIB, QString::number(id), obj.value(u"trackName"_s).toString(),
            obj.value(u"artistName"_s).toString(), obj.value(u"albumName"_s).toString(),
            obj.value(u"duration"_s).toDouble());
        appendCandidates({ cand });
        m_selected = cand;
        emit selectedCandidateChanged();
        if (!m_settingFromPrefs) {
            persistTrackPrefs();
        }
        setLoading(false);
    });
}

void Lyrics::tryNetEase(int reqId) {
    if (reqId != m_currentRequestId) {
        return;
    }

    setBackend(LyricsBackend::NetEase);

    // Reset cookies (LyricsBackend::NetEase rejects requests with stale cookies sometimes)
    m_nam->setCookieJar(new QNetworkCookieJar(m_nam));

    QUrl url(u"https://music.163.com/api/search/get"_s);
    QUrlQuery q;
    q.addQueryItem(u"s"_s, u"%1 %2"_s.arg(m_title, m_artist));
    q.addQueryItem(u"type"_s, u"1"_s);
    q.addQueryItem(u"limit"_s, u"5"_s);
    url.setQuery(q);

    auto* reply = getJson(url, netEaseHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCDebug(lcLyrics) << "netease /search error:" << reply->errorString();
            chainNext(LyricsBackend::NetEase, reqId);
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonArray songs = doc.object().value(u"result"_s).toObject().value(u"songs"_s).toArray();

        // Find best match by artist substring
        qint64 bestId = -1;
        for (const auto& v : songs) {
            const QJsonObject s = v.toObject();
            const QJsonArray artists = s.value(u"artists"_s).toArray();
            if (artists.isEmpty()) {
                continue;
            }
            const QString sArtist = artists.first().toObject().value(u"name"_s).toString();
            if (containsCi(m_artist, sArtist) || containsCi(sArtist, m_artist)) {
                bestId = static_cast<qint64>(s.value(u"id"_s).toDouble());
                break;
            }
        }

        if (bestId < 0) {
            qCDebug(lcLyrics) << "netease: no artist match for" << m_artist << "-" << m_title;
            chainNext(LyricsBackend::NetEase, reqId);
            return;
        }

        fetchNetEaseLyricsById(QString::number(bestId), reqId);
    });
}

void Lyrics::searchLrclibCandidates(int reqId) {
    QUrl url(u"https://lrclib.net/api/search"_s);
    QUrlQuery q;
    q.addQueryItem(u"track_name"_s, m_title);
    q.addQueryItem(u"artist_name"_s, m_artist);
    url.setQuery(q);

    auto* reply = getJson(url, lrclibHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCDebug(lcLyrics) << "lrclib /search error:" << reply->errorString();
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonArray arr = doc.array();

        QList<LyricCandidate> add;
        add.reserve(arr.size());
        for (const auto& v : arr) {
            const QJsonObject o = v.toObject();
            if (o.value(u"syncedLyrics"_s).isNull() && o.value(u"plainLyrics"_s).isNull()) {
                continue;
            }
            add.append(
                LyricCandidate(LyricsBackend::LRCLIB, QString::number(static_cast<qint64>(o.value(u"id"_s).toDouble())),
                    o.value(u"trackName"_s).toString(), o.value(u"artistName"_s).toString(),
                    o.value(u"albumName"_s).toString(), o.value(u"duration"_s).toDouble()));
        }
        appendCandidates(add);
    });
}

void Lyrics::searchNetEaseCandidates(int reqId) {
    m_nam->setCookieJar(new QNetworkCookieJar(m_nam));

    QUrl url(u"https://music.163.com/api/search/get"_s);
    QUrlQuery q;
    q.addQueryItem(u"s"_s, u"%1 %2"_s.arg(m_title, m_artist));
    q.addQueryItem(u"type"_s, u"1"_s);
    q.addQueryItem(u"limit"_s, u"5"_s);
    url.setQuery(q);

    auto* reply = getJson(url, netEaseHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCDebug(lcLyrics) << "netease candidates error:" << reply->errorString();
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonArray songs = doc.object().value(u"result"_s).toObject().value(u"songs"_s).toArray();

        QList<LyricCandidate> add;
        add.reserve(songs.size());
        for (const auto& v : songs) {
            const QJsonObject s = v.toObject();
            QStringList artistNames;
            const QJsonArray artists = s.value(u"artists"_s).toArray();
            artistNames.reserve(artists.size());
            for (const auto& a : artists) {
                artistNames.append(a.toObject().value(u"name"_s).toString());
            }
            add.append(LyricCandidate(LyricsBackend::NetEase,
                QString::number(static_cast<qint64>(s.value(u"id"_s).toDouble())), s.value(u"name"_s).toString(),
                artistNames.join(u", "_s)));
        }
        appendCandidates(add);
    });
}

void Lyrics::fetchLrclibById(const QString& id, int reqId) {
    const QUrl url(u"https://lrclib.net/api/get/"_s + id);
    auto* reply = getJson(url, lrclibHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId, id] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(lcLyrics) << "lrclib /get/{id} error:" << reply->errorString();
            setLoading(false);
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QString synced = doc.object().value(u"syncedLyrics"_s).toString();
        if (synced.isEmpty()) {
            qCDebug(lcLyrics) << "lrclib /get/{id}: no syncedLyrics";
            setLoading(false);
            return;
        }
        const auto lines = parseLrc(synced);
        if (!acceptRomanized(lines)) {
            qCDebug(lcLyrics) << "romanized: lrclib lyrics not latin-script for id" << id;
            setLoading(false);
            return;
        }
        writeCachedLrc(LyricsBackend::LRCLIB, id, synced);
        setLines(lines, LyricsBackend::LRCLIB);
        setLoading(false);
    });
}

void Lyrics::fetchNetEaseLyricsById(const QString& id, int reqId) {
    QUrl url(u"https://music.163.com/api/song/lyric"_s);
    QUrlQuery q;
    q.addQueryItem(u"id"_s, id);
    q.addQueryItem(u"lv"_s, u"1"_s);
    q.addQueryItem(u"kv"_s, u"1"_s);
    q.addQueryItem(u"tv"_s, u"-1"_s);
    url.setQuery(q);

    auto* reply = getJson(url, netEaseHeaders());
    trackReply(reqId, reply);

    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, reqId, id] {
        reply->deleteLater();
        if (reqId != m_currentRequestId) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(lcLyrics) << "netease /lyric error:" << reply->errorString();
            setLoading(false);
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonObject obj = doc.object();
        const QString lrc = obj.value(u"lrc"_s).toObject().value(u"lyric"_s).toString();
        if (lrc.isEmpty()) {
            qCDebug(lcLyrics) << "netease /lyric: empty for id" << id;
            setLoading(false);
            return;
        }
        // Same response carries the romanized variant; cache it whenever present
        const QString romalrc = obj.value(u"romalrc"_s).toObject().value(u"lyric"_s).toString();

        auto original = parseLrc(lrc);
        QVector<LyricLine> romanized;
        if (m_romanized) {
            romanized = parseLrc(romalrc);
            if (romanized.isEmpty() && !isLatinLrc(original)) {
                qCDebug(lcLyrics) << "netease /lyric: no romalrc and lrc not latin-script for id" << id;
                setLoading(false);
                return;
            }
        }

        writeCachedLrc(LyricsBackend::NetEase, id, lrc);
        if (!romalrc.isEmpty()) {
            writeCachedRomanizedLrc(LyricsBackend::NetEase, id, romalrc);
        }
        setLines(std::move(original), LyricsBackend::NetEase, std::move(romanized));
        setLoading(false);
    });
}

QNetworkReply* Lyrics::getJson(const QUrl& url, const QHash<QByteArray, QByteArray>& headers) {
    QNetworkRequest req(url);
    req.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    req.setRawHeader("Cache-Control"_ba, "no-cache, no-store"_ba);
    req.setRawHeader("Pragma"_ba, "no-cache"_ba);
    req.setRawHeader("Connection"_ba, "close"_ba);
    req.setRawHeader("Accept"_ba, "application/json"_ba);
    for (auto it = headers.constBegin(); it != headers.constEnd(); ++it) {
        req.setRawHeader(it.key(), it.value());
    }
    return m_nam->get(req);
}

void Lyrics::onPreferredBackendConfigChanged() {
    const LyricsBackend desired = config::ConfigSingleton::instance()->services()->lyricsBackend();
    if (desired == m_preferredBackend) {
        return;
    }
    m_preferredBackend = desired;
    emit preferredBackendChanged();
    scheduleLoad();
}

void Lyrics::onRomanizedConfigChanged() {
    const bool desired = config::ConfigSingleton::instance()->services()->lyricsRomanized();
    if (desired == m_romanized) {
        return;
    }
    m_romanized = desired;
    emit romanizedChanged();
    updateActiveLyrics();
    scheduleLoad();
}

void Lyrics::onLyricsDirChanged() {
    scheduleLoad();
}

void Lyrics::loadLyricsMap() {
    m_lyricsMap = {};
    m_lyricsMapLoaded = false;

    QFile f(lyricsMapPath());
    if (!f.open(QIODevice::ReadOnly)) {
        m_lyricsMapLoaded = true;
        return;
    }
    const QByteArray bytes = f.readAll();
    f.close();

    QJsonParseError err{};
    const QJsonDocument doc = QJsonDocument::fromJson(bytes, &err);
    if (err.error != QJsonParseError::NoError) {
        qCWarning(lcLyrics) << "lyrics_map.json parse error:" << err.errorString();
        m_lyricsMapLoaded = true;
        return;
    }
    m_lyricsMap = doc.object();
    m_lyricsMapLoaded = true;
}

void Lyrics::persistTrackPrefs() {
    if (!m_lyricsMapLoaded || trackKey().isEmpty()) {
        return;
    }
    const QString key = trackKey();
    QJsonObject entry = m_lyricsMap.value(key).toObject();
    entry.insert(u"offset"_s, m_offset);
    if (m_selected.isValid()) {
        entry.insert(u"backend"_s, backendKey(m_selected.backend()));
        entry.insert(u"id"_s, m_selected.id());
    }
    m_lyricsMap.insert(key, entry);

    QDir().mkpath(stateDir());

    QSaveFile out(lyricsMapPath());
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qCWarning(lcLyrics) << "cannot open" << lyricsMapPath() << "for write:" << out.errorString();
        return;
    }
    const QByteArray bytes = QJsonDocument(m_lyricsMap).toJson(QJsonDocument::Compact);
    if (out.write(bytes) != bytes.size()) {
        qCWarning(lcLyrics) << "short write to" << lyricsMapPath();
        out.cancelWriting();
        return;
    }
    if (!out.commit()) {
        qCWarning(lcLyrics) << "commit failed for" << lyricsMapPath() << ":" << out.errorString();
    }
}

QString Lyrics::lyricsDir() {
    QString dir = config::ConfigSingleton::instance()->paths()->lyricsDir();
    if (dir.isEmpty()) {
        return {};
    }
    if (dir == u"~"_s) {
        dir = QDir::homePath();
    } else if (dir.startsWith(u"~/"_s)) {
        dir.replace(0, 1, QDir::homePath());
    }
    while (dir.endsWith(u'/') && dir.size() > 1) {
        dir.chop(1);
    }
    return dir;
}

QString Lyrics::lyricsMapPath() {
    return stateDir() + u"/lyrics_map.json"_s;
}

QString Lyrics::trackKey() const {
    if (m_artist.isEmpty() && m_title.isEmpty()) {
        return {};
    }
    return u"%1 - %2"_s.arg(joinArtists(m_artist), m_title);
}

QString Lyrics::backendKey(LyricsBackend value) {
    switch (value) {
    case LyricsBackend::Local:
        return u"Local"_s;
    case LyricsBackend::LRCLIB:
        return u"LRCLIB"_s;
    case LyricsBackend::NetEase:
        return u"NetEase"_s;
    case LyricsBackend::Auto:
    default:
        return u"Auto"_s;
    }
}

LyricsBackend Lyrics::backendFromKey(const QString& key) {
    if (key.compare(u"Local"_s, Qt::CaseInsensitive) == 0) {
        return LyricsBackend::Local;
    }
    if (key.compare(u"LRCLIB"_s, Qt::CaseInsensitive) == 0) {
        return LyricsBackend::LRCLIB;
    }
    if (key.compare(u"NetEase"_s, Qt::CaseInsensitive) == 0) {
        return LyricsBackend::NetEase;
    }
    return LyricsBackend::Auto;
}

const QString& Lyrics::stateDir() {
    static const QString k_dir = [] {
        QString state = qEnvironmentVariable("XDG_STATE_HOME");
        if (state.isEmpty()) {
            state = QDir::homePath() + u"/.local/state"_s;
        }
        return state + u"/caelestia/lyrics"_s;
    }();
    return k_dir;
}

const QString& Lyrics::cacheDir() {
    static const QString k_dir = [] {
        QString cache = qEnvironmentVariable("XDG_CACHE_HOME");
        if (cache.isEmpty()) {
            cache = QDir::homePath() + u"/.cache"_s;
        }
        return cache + u"/caelestia/lyrics"_s;
    }();
    return k_dir;
}

QString Lyrics::cachePathFor(LyricsBackend backend, const QString& id) {
    if (id.isEmpty() || backend == LyricsBackend::Auto || backend == LyricsBackend::Local) {
        return {};
    }
    return u"%1/%2/%3.lrc"_s.arg(cacheDir(), backendKey(backend), sanitizeFilenamePart(id));
}

QString Lyrics::romanizedCachePathFor(LyricsBackend backend, const QString& id) {
    const QString path = cachePathFor(backend, id);
    if (path.isEmpty() || !path.endsWith(u".lrc"_s)) {
        return {};
    }
    QString out = path;
    out.chop(4);
    out += u".romalrc"_s;
    return out;
}

QString Lyrics::readTextFile(const QString& path) {
    if (path.isEmpty()) {
        return {};
    }
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QString::fromUtf8(f.readAll());
}

void Lyrics::writeTextFile(const QString& path, const QString& text) {
    if (path.isEmpty() || text.isEmpty()) {
        return;
    }
    QDir().mkpath(QFileInfo(path).absolutePath());

    QSaveFile out(path);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qCWarning(lcLyrics) << "cannot open" << path << "for write:" << out.errorString();
        return;
    }
    const QByteArray bytes = text.toUtf8();
    if (out.write(bytes) != bytes.size()) {
        qCWarning(lcLyrics) << "short write to" << path;
        out.cancelWriting();
        return;
    }
    if (!out.commit()) {
        qCWarning(lcLyrics) << "commit failed for" << path << ":" << out.errorString();
    }
}

QString Lyrics::readCachedLrc(LyricsBackend backend, const QString& id) {
    return readTextFile(cachePathFor(backend, id));
}

void Lyrics::writeCachedLrc(LyricsBackend backend, const QString& id, const QString& text) {
    writeTextFile(cachePathFor(backend, id), text);
}

QString Lyrics::readCachedRomanizedLrc(LyricsBackend backend, const QString& id) {
    return readTextFile(romanizedCachePathFor(backend, id));
}

void Lyrics::writeCachedRomanizedLrc(LyricsBackend backend, const QString& id, const QString& text) {
    writeTextFile(romanizedCachePathFor(backend, id), text);
}

QString Lyrics::tryReadLocalLrc(const QString& dir, const QString& artist, const QString& title) {
    if (artist.isEmpty() && title.isEmpty()) {
        return {};
    }
    const QString flat = u"%1/%2 - %3.lrc"_s.arg(dir, sanitizeFilenamePart(artist), sanitizeFilenamePart(title));
    return QFile::exists(flat) ? flat : QString();
}

QString Lyrics::findLocalLrcRecursive(const QString& dir, const QString& artist, const QString& title) {
    if (dir.isEmpty()) {
        return {};
    }
    if (artist.isEmpty() && title.isEmpty()) {
        return {};
    }

    QDirIterator it(dir, QStringList{ u"*.lrc"_s }, QDir::Files | QDir::NoDotAndDotDot,
        QDirIterator::Subdirectories | QDirIterator::FollowSymlinks);

    while (it.hasNext()) {
        const QString path = it.next();
        const QString name = it.fileName();
        if ((artist.isEmpty() || containsCi(name, artist)) && (title.isEmpty() || containsCi(name, title))) {
            return path;
        }
    }
    return {};
}

QVector<LyricLine> Lyrics::parseLrc(const QString& text) {
    QVector<LyricLine> result;
    if (text.isEmpty()) {
        return result;
    }

    static const QRegularExpression k_timeRegex(u"\\[(\\d+):(\\d+(?:\\.\\d+)?)\\]"_s);
    static const QStringList k_creditKeywords = {
        u"作词"_s,
        u"作曲"_s,
        u"编曲"_s,
        u"制作"_s,
        u"收录"_s,
        u"演奏"_s,
        u"词："_s,
        u"曲："_s,
        u"Lyricist"_s,
        u"Composer"_s,
        u"Arranger"_s,
        u"Producer"_s,
        u"Mixing"_s,
        u"Mastering"_s,
    };

    const QStringList lines = text.split(u'\n');
    for (const QString& line : lines) {
        QList<QRegularExpressionMatch> matches;
        auto it = k_timeRegex.globalMatch(line);
        while (it.hasNext()) {
            matches.append(it.next());
        }
        if (matches.isEmpty()) {
            continue;
        }

        QString lyric = line;
        lyric.replace(k_timeRegex, QString());
        lyric = lyric.trimmed();

        const qreal firstTime = matches.first().captured(1).toInt() * 60.0 + matches.first().captured(2).toDouble();

        if (firstTime < 20.0) {
            bool isCredit = false;
            for (const QString& k : k_creditKeywords) {
                if (lyric.contains(k, Qt::CaseInsensitive)) {
                    isCredit = true;
                    break;
                }
            }
            if (isCredit && (lyric.contains(u':') || lyric.contains(QChar(0xFF1A)) || lyric.size() < 25)) {
                continue;
            }
        }

        for (const auto& m : matches) {
            const qreal t = m.captured(1).toInt() * 60.0 + m.captured(2).toDouble();
            result.append(LyricLine{ .time = t, .text = lyric });
        }
    }

    std::ranges::sort(result, [](const LyricLine& a, const LyricLine& b) {
        return a.time < b.time;
    });

    return result;
}

} // namespace caelestia::services
