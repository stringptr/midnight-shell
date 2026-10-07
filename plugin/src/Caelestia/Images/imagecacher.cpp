#include "imagecacher.hpp"

#include <qcryptographichash.h>
#include <qdir.h>
#include <qfile.h>
#include <qfileinfo.h>
#include <qimage.h>
#include <qloggingcategory.h>
#include <qmutex.h>
#include <qpainter.h>
#include <qsavefile.h>
#include <qthreadpool.h>

namespace {

Q_LOGGING_CATEGORY(lcCacher, "caelestia.images.cacher", QtInfoMsg)

} // namespace

namespace caelestia::images {

using Qt::StringLiterals::operator""_s;

namespace {

QString sha256sum(const QString& path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qCWarning(lcCacher).noquote() << "sha256sum: failed to open" << path;
        return {};
    }

    QCryptographicHash hash(QCryptographicHash::Sha256);
    hash.addData(&file);
    file.close();

    return QString::fromLatin1(hash.result().toHex());
}

QString fillSuffix(ImageCacher::FillMode fillMode) {
    switch (fillMode) {
    case ImageCacher::FillMode::Crop:
        return u"crop"_s;
    case ImageCacher::FillMode::Fit:
        return u"fit"_s;
    default:
        return u"stretch"_s;
    }
}

QString offsetSuffix(qreal hOffset, qreal vOffset) {
    if (hOffset == 0.0 && vOffset == 0.0)
        return {};
    return u"_h%1_v%2"_s.arg(QString::number(qRound(hOffset * 100)), QString::number(qRound(vOffset * 100)));
}

} // namespace

const QString& ImageCacher::cacheDir() {
    static const QString k_dir = [] {
        QString cache = qEnvironmentVariable("XDG_CACHE_HOME");
        if (cache.isEmpty())
            cache = QDir::homePath() + u"/.cache"_s;
        return cache + u"/caelestia/imagecache"_s;
    }();
    return k_dir;
}

QString ImageCacher::cachePathFor(const QString& sourcePath, const QSize& size, FillMode fillMode, qreal hOffset, qreal vOffset) {
    const QString sha = sha256sum(sourcePath);
    if (sha.isEmpty())
        return {};

    const QString filename = u"%1@%2x%3-%4%5.png"_s.arg(
        sha, QString::number(size.width()), QString::number(size.height()), fillSuffix(fillMode), offsetSuffix(hOffset, vOffset));

    return cacheDir() + u'/' + filename;
}

ImageCacher* ImageCacher::instance() {
    static ImageCacher s_instance;
    return &s_instance;
}

ImageCacher::ImageCacher(QObject* parent)
    : QObject(parent) {}

void ImageCacher::schedule(const QString& sourcePath, const QSize& size, FillMode fillMode, qreal hOffset, qreal vOffset) {
    schedule(sourcePath, cachePathFor(sourcePath, size, fillMode, hOffset, vOffset), size, fillMode, hOffset, vOffset);
}

void ImageCacher::schedule(const QString& sourcePath, const QString& cachePath, const QSize& size, FillMode fillMode, qreal hOffset, qreal vOffset) {
    if (cachePath.isEmpty())
        return;

    {
        const QMutexLocker locker(&m_mutex);
        if (m_inflight.contains(cachePath))
            return;
        m_inflight.insert(cachePath);
    }

    QThreadPool::globalInstance()->start([this, sourcePath, cachePath, size, fillMode, hOffset, vOffset] {
        runJob(sourcePath, cachePath, size, fillMode, hOffset, vOffset);
        const QMutexLocker locker(&m_mutex);
        // NOLINTNEXTLINE(clang-analyzer-core.CallAndMessage) m_inflight is a value member, not a pointer
        m_inflight.remove(cachePath);
    });
}

void ImageCacher::runJob(const QString& sourcePath, const QString& cachePath, const QSize& size, FillMode fillMode, qreal hOffset, qreal vOffset) {
    if (QFile::exists(cachePath)) {
        return;
    }

    QImage image(sourcePath);
    if (image.isNull()) {
        qCWarning(lcCacher).noquote() << "Failed to decode source" << sourcePath;
        return;
    }

    Qt::AspectRatioMode scaleMode;
    switch (fillMode) {
    case FillMode::Crop:
        scaleMode = Qt::KeepAspectRatioByExpanding;
        break;
    case FillMode::Fit:
        scaleMode = Qt::KeepAspectRatio;
        break;
    case FillMode::Stretch:
        scaleMode = Qt::IgnoreAspectRatio;
        break;
    }

    image.convertTo(QImage::Format_ARGB32);
    image = image.scaled(size, scaleMode, Qt::SmoothTransformation);

    if (image.isNull()) {
        qCWarning(lcCacher).noquote() << "Failed to scale" << sourcePath;
        return;
    }

    QImage canvas;
    if (fillMode == FillMode::Stretch) {
        canvas = image;
    } else {
        canvas = QImage(size, QImage::Format_ARGB32);
        canvas.fill(Qt::transparent);

        const qreal maxOffsetX = static_cast<qreal>(size.width() - image.width()) / 2.0;
        const qreal maxOffsetY = static_cast<qreal>(size.height() - image.height()) / 2.0;
        const int x = qRound((size.width() - image.width()) / 2.0 + maxOffsetX * hOffset);
        const int y = qRound((size.height() - image.height()) / 2.0 + maxOffsetY * vOffset);

        QPainter painter(&canvas);
        painter.drawImage(x, y, image);
        painter.end();
    }

    const QString parent = QFileInfo(cachePath).absolutePath();
    if (!QDir().mkpath(parent)) {
        qCWarning(lcCacher).noquote() << "Failed to create cache dir" << parent;
        return;
    }

    QSaveFile saveFile(cachePath);
    if (!saveFile.open(QIODevice::WriteOnly) || !canvas.save(&saveFile, "PNG") || !saveFile.commit()) {
        qCWarning(
            lcCacher, "Failed to save to %s: %s", qUtf8Printable(cachePath), qUtf8Printable(saveFile.errorString()));
        return;
    }

    qCDebug(lcCacher).noquote() << "Saved to" << cachePath;
}

} // namespace caelestia::images
