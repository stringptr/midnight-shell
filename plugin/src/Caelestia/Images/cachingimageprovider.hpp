#pragma once

#include <qquickimageprovider.h>

#include "imagecacher.hpp"

namespace caelestia::images {

class CachingImageProvider : public QQuickAsyncImageProvider {
public:
    using FillMode = ImageCacher::FillMode;

    explicit CachingImageProvider(FillMode fillMode);

    QQuickImageResponse* requestImageResponse(const QString& id, const QSize& requestedSize) override;

private:
    static QPair<qreal, qreal> parseOffsets(const QString& id);

    FillMode m_fillMode;
};

} // namespace caelestia::images
