#include "cachingimageprovider.hpp"

#include <qfileinfo.h>
#include <qimage.h>
#include <qimagereader.h>
#include <qloggingcategory.h>
#include <qrunnable.h>
#include <qthreadpool.h>

#include <utility>

#include "imagecacher.hpp"

namespace {

Q_LOGGING_CATEGORY(lcCProv, "caelestia.images.cacheprovider", QtInfoMsg)

} // namespace

namespace caelestia::images {

using Qt::StringLiterals::operator""_s;

namespace {

class CachingImageResponse final : public QQuickImageResponse, public QRunnable {
public:
    CachingImageResponse(QString id, const QSize& requestedSize, ImageCacher::FillMode fillMode, qreal hOffset, qreal vOffset);

    [[nodiscard]] QQuickTextureFactory* textureFactory() const override;

    [[nodiscard]] QString errorString() const override;

    void run() override;

private:
    void process();

    QString m_id;
    QSize m_requestedSize;
    ImageCacher::FillMode m_fillMode;
    qreal m_hOffset;
    qreal m_vOffset;
    QImage m_image;
    QString m_error;
};

CachingImageResponse::CachingImageResponse(QString id, const QSize& requestedSize, ImageCacher::FillMode fillMode, qreal hOffset, qreal vOffset)
    : m_id(std::move(id))
    , m_requestedSize(requestedSize)
    , m_fillMode(fillMode)
    , m_hOffset(hOffset)
    , m_vOffset(vOffset) {
    setAutoDelete(false);
}

QQuickTextureFactory* CachingImageResponse::textureFactory() const {
    return QQuickTextureFactory::textureFactoryForImage(m_image);
}

QString CachingImageResponse::errorString() const {
    return m_error;
}

void CachingImageResponse::run() {
    process();
    emit finished();
}

void CachingImageResponse::process() {
    QString path = QString::fromUtf8(m_id.toUtf8().percentDecoded());
    const int qIdx = path.indexOf(u'?');
    if (qIdx >= 0)
        path = path.left(qIdx);
    if (!path.startsWith(u'/'))
        path.prepend(u'/');

    if (!QFileInfo::exists(path)) {
        m_error = u"Source file does not exist: "_s + path;
        qCWarning(lcCProv).noquote() << m_error;
        return;
    }

    QSize size = m_requestedSize;
    const bool needsW = size.width() <= 0;
    const bool needsH = size.height() <= 0;

    // If both dimensions are missing, return the original directly
    if (needsW && needsH) {
        qCDebug(lcCProv).noquote() << "Given source size is invalid, returning original:" << path;
        m_image = QImage(path);
        if (m_image.isNull()) {
            m_error = u"Failed to decode source: "_s + path;
            qCWarning(lcCProv).noquote() << m_error;
        }
        return;
    }

    // If one dimension is missing, derive it from the source aspect ratio
    if (needsW || needsH) {
        const QImageReader sourceReader(path);
        const QSize sourceSize = sourceReader.size();
        if (!sourceSize.isValid() || sourceSize.isEmpty()) {
            m_error = u"Could not determine source size for: "_s + path;
            qCWarning(lcCProv).noquote() << m_error;
            return;
        }

        if (needsW)
            size.setWidth(qRound(size.height() * sourceSize.width() / static_cast<qreal>(sourceSize.height())));
        else
            size.setHeight(qRound(size.width() * sourceSize.height() / static_cast<qreal>(sourceSize.width())));
    }

    // Try to use cached image
    const auto cachePath = ImageCacher::cachePathFor(path, size, m_fillMode, m_hOffset, m_vOffset);
    if (!cachePath.isEmpty()) {
        QImageReader cacheReader(cachePath);
        if (cacheReader.canRead()) {
            m_image = cacheReader.read();
            if (!m_image.isNull())
                return;
        }
    }

    // Schedule cache job (this call will return the original image, but later ones will use cache)
    ImageCacher::instance()->schedule(path, cachePath, size, m_fillMode, m_hOffset, m_vOffset);

    m_image = QImage(path);
    if (m_image.isNull()) {
        m_error = u"Failed to decode source: "_s + path;
        qCWarning(lcCProv).noquote() << m_error;
    }
}

} // namespace

CachingImageProvider::CachingImageProvider(FillMode fillMode)
    : m_fillMode(fillMode) {}

QPair<qreal, qreal> CachingImageProvider::parseOffsets(const QString& id) {
    qreal hOffset = 0.0;
    qreal vOffset = 0.0;

    const int qIdx = id.indexOf(u'?');
    if (qIdx >= 0) {
        const QString query = id.mid(qIdx + 1);
        const auto params = query.split(u'&');
        for (const auto& param : params) {
            const auto kv = param.split(u'=');
            if (kv.size() == 2) {
                if (kv[0] == u"ho")
                    hOffset = kv[1].toDouble();
                else if (kv[0] == u"vo")
                    vOffset = kv[1].toDouble();
            }
        }
    }

    return {hOffset, vOffset};
}

QQuickImageResponse* CachingImageProvider::requestImageResponse(const QString& id, const QSize& requestedSize) {
    const auto [hOffset, vOffset] = parseOffsets(id);
    auto* const response = new CachingImageResponse(id, requestedSize, m_fillMode, hOffset, vOffset);
    QThreadPool::globalInstance()->start(response);
    return response;
}

} // namespace caelestia::images
