#include "blobmaterial.hpp"

#include <cstring>

namespace caelestia::blobs {

using Qt::StringLiterals::operator""_s;

static_assert(sizeof(decltype(BlobRectData::excludeMask)) == sizeof(float),
    "BlobMaterial packs excludeMask into a float slot via memcpy");

QSGMaterialType* BlobMaterial::type() const {
    static QSGMaterialType s_type;
    return &s_type;
}

QSGMaterialShader* BlobMaterial::createShader(QSGRendererInterface::RenderMode mode) const {
    Q_UNUSED(mode);
    return new BlobMaterialShader;
}

int BlobMaterial::compare(const QSGMaterial* other) const {
    if (this < other)
        return -1;
    if (this > other)
        return 1;
    return 0;
}

BlobMaterialShader::BlobMaterialShader() {
    setShaderFileName(VertexStage, u":/shaders/blob.vert.qsb"_s);
    setShaderFileName(FragmentStage, u":/shaders/blob.frag.qsb"_s);
}

bool BlobMaterialShader::updateUniformData(RenderState& state, QSGMaterial* newMaterial, QSGMaterial* oldMaterial) {
    Q_UNUSED(oldMaterial);
    auto* mat = static_cast<BlobMaterial*>(newMaterial);
    QByteArray* buf = state.uniformData();
    Q_ASSERT(buf->size() >= 1440);

    bool changed = false;

    if (state.isMatrixDirty()) {
        const QMatrix4x4 m = state.combinedMatrix();
        memcpy(buf->data(), m.constData(), 64);
        changed = true;
    }
    if (state.isOpacityDirty()) {
        const float opacity = state.opacity();
        memcpy(buf->data() + 64, &opacity, 4);
        changed = true;
    }

    // The uniform buffer is persistent per material: only upload the fields that
    // actually differ from what is already there (everything on the first upload).
    const bool primed = mat->m_uniformsPrimed;
    const auto sync = [&changed, buf, primed](const void* src, qsizetype offset, qsizetype size) {
        if (primed && memcmp(buf->data() + offset, src, size) == 0)
            return;
        memcpy(buf->data() + offset, src, size);
        changed = true;
    };

    // Padded rect (offset 68)
    sync(&mat->m_paddedX, 68, 16);

    // Smooth factor (offset 84)
    sync(&mat->m_smoothFactor, 84, 4);

    // Rect count (offset 88)
    sync(&mat->m_rectCount, 88, 4);

    // My index (offset 92)
    sync(&mat->m_myIndex, 92, 4);

    // Color as vec4 (offset 96, 16 bytes)
    const float color[4] = {
        mat->m_color.redF(),
        mat->m_color.greenF(),
        mat->m_color.blueF(),
        mat->m_color.alphaF(),
    };
    sync(color, 96, 16);

    // Has inverted (offset 112)
    sync(&mat->m_hasInverted, 112, 4);

    // Inverted radius (offset 116)
    sync(&mat->m_invertedRadius, 116, 4);

    // Padding at 120-127 (skip)

    // Inverted outer (offset 128, 16 bytes)
    sync(mat->m_invertedOuter, 128, 16);

    // Inverted inner (offset 144, 16 bytes)
    sync(mat->m_invertedInner, 144, 16);

    // Rect data (offset 160, each rect = 5 vec4s = 80 bytes)
    const int count = qMin(mat->m_rectCount, k_maxRects);
    for (int i = 0; i < count; ++i) {
        const auto& r = mat->m_rects[i];
        const int base = 160 + i * 80;
        // Pack excludeMask into props.x via bit-cast (read in shader with floatBitsToInt)
        float maskAsFloat;
        memcpy(&maskAsFloat, &r.excludeMask, sizeof(float));
        const float d0[4] = { r.cx, r.cy, r.hw, r.hh };
        const float d1[4] = { maskAsFloat, r.offsetX, r.offsetY, r.minEig };
        const float d3[4] = { r.screenHalfX, r.screenHalfY, 0.0f, 0.0f };
        sync(d0, base, 16);
        sync(d1, base + 16, 16);
        sync(r.invDeform, base + 32, 16);
        sync(d3, base + 48, 16);
        sync(r.radius, base + 64, 16);
    }

    mat->m_uniformsPrimed = true;
    return changed;
}

} // namespace caelestia::blobs
