#pragma once

#include <cstring>

#include <qcolor.h>
#include <qsgmaterial.h>
#include <qsgmaterialshader.h>

namespace caelestia::blobs {

// Max rects the shader smins over; must match the loop bounds in blob.frag
inline constexpr int k_maxRects = 16;

struct BlobRectData {
    float cx = 0, cy = 0, hw = 0, hh = 0;
    float offsetX = 0, offsetY = 0;
    float minEig = 1.0f;
    // Inverse of 2x2 deformation matrix, column-major for GLSL
    float invDeform[4] = { 1, 0, 0, 1 };
    // Screen-space AABB half-extents of the deformed rect
    float screenHalfX = 0, screenHalfY = 0;
    // Effective per-corner radii (tr, br, bl, tl), pre-computed on CPU
    float radius[4] = { 0, 0, 0, 0 };
    // Bitmask of indices in this rect's m_cachedRects that mutually exclude (or are excluded by) this rect.
    // Used by the shader to skip smin between excluded pairs.
    int excludeMask = 0;
};

inline bool operator==(const BlobRectData& a, const BlobRectData& b) {
    return a.cx == b.cx && a.cy == b.cy && a.hw == b.hw && a.hh == b.hh && a.offsetX == b.offsetX
        && a.offsetY == b.offsetY && a.minEig == b.minEig
        && std::memcmp(a.invDeform, b.invDeform, sizeof(a.invDeform)) == 0 && a.screenHalfX == b.screenHalfX
        && a.screenHalfY == b.screenHalfY && std::memcmp(a.radius, b.radius, sizeof(a.radius)) == 0
        && a.excludeMask == b.excludeMask;
}

class BlobMaterial : public QSGMaterial {
public:
    [[nodiscard]] QSGMaterialType* type() const override;
    [[nodiscard]] QSGMaterialShader* createShader(QSGRendererInterface::RenderMode mode) const override;
    int compare(const QSGMaterial* other) const override;

    float m_paddedX = 0;
    float m_paddedY = 0;
    float m_paddedW = 0;
    float m_paddedH = 0;
    float m_smoothFactor = 32.0f;
    int m_rectCount = 0;
    int m_myIndex = -2;
    QColor m_color{ 0x44, 0x88, 0xff };
    int m_hasInverted = 0;
    float m_invertedRadius = 0;
    float m_invertedOuter[4] = {};
    float m_invertedInner[4] = {};
    BlobRectData m_rects[k_maxRects] = {};
    // False until the first uniform upload; the persistent uniform buffer may hold
    // undefined bytes before that, so every field must be written at least once.
    bool m_uniformsPrimed = false;
};

class BlobMaterialShader : public QSGMaterialShader {
public:
    BlobMaterialShader();
    bool updateUniformData(RenderState& state, QSGMaterial* newMaterial, QSGMaterial* oldMaterial) override;
};

} // namespace caelestia::blobs
