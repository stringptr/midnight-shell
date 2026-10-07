#include "qrc3des.hpp"

#include <cstring>

namespace caelestia::services {
namespace {

// Port of DESHelper.cs from WXRIW/QQMusicDecoder (MIT), cross-checked against
// qqmusic_api/algorithms/tripledes.py from luren-dc/QQMusicApi (GPL-3.0).
// This is DES as QQ Music's QRC layer expects it: the key schedule masks the low
// nibble of every rotated half ("& 0xfffffff0") and two S-box entries deviate from
// published DES, so stock 3DES libraries cannot decrypt these payloads.

constexpr quint32 kEncrypt = 1;
constexpr quint32 kDecrypt = 0;

[[nodiscard]] quint32 bitNum(const quint8* a, const int b, const int c) {
    const quint32 bit = (a[b / 32 * 4 + 3 - b % 32 / 8] >> (7 - (b % 8))) & 0x01;
    return bit << c;
}

[[nodiscard]] quint8 bitNumIntr(const quint32 a, const int b, const int c) {
    return static_cast<quint8>((((a) >> (31 - (b))) & 0x00000001U) << (c));
}

[[nodiscard]] quint32 bitNumIntl(const quint32 a, const int b, const int c) {
    return ((a << (b)) & 0x80000000U) >> (c);
}

[[nodiscard]] quint32 sboxBit(const quint8 a) {
    return static_cast<quint32>(((a) & 0x20) | (((a) & 0x1f) >> 1) | (((a) & 0x01) << 4));
}

constexpr quint8 kSbox1[64] = {
    14,  4, 13,  1,  2, 15, 11,  8,  3, 10,  6, 12,  5,  9,  0,  7,
     0, 15,  7,  4, 14,  2, 13,  1, 10,  6, 12, 11,  9,  5,  3,  8,
     4,  1, 14,  8, 13,  6,  2, 11, 15, 12,  9,  7,  3, 10,  5,  0,
    15, 12,  8,  2,  4,  9,  1,  7,  5, 11,  3, 14, 10,  0,  6, 13,
};

constexpr quint8 kSbox2[64] = {
    15,  1,  8, 14,  6, 11,  3,  4,  9,  7,  2, 13, 12,  0,  5, 10,
     3, 13,  4,  7, 15,  2,  8, 15, 12,  0,  1, 10,  6,  9, 11,  5,
     0, 14,  7, 11, 10,  4, 13,  1,  5,  8, 12,  6,  9,  3,  2, 15,
    13,  8, 10,  1,  3, 15,  4,  2, 11,  6,  7, 12,  0,  5, 14,  9,
};

constexpr quint8 kSbox3[64] = {
    10,  0,  9, 14,  6,  3, 15,  5,  1, 13, 12,  7, 11,  4,  2,  8,
    13,  7,  0,  9,  3,  4,  6, 10,  2,  8,  5, 14, 12, 11, 15,  1,
    13,  6,  4,  9,  8, 15,  3,  0, 11,  1,  2, 12,  5, 10, 14,  7,
     1, 10, 13,  0,  6,  9,  8,  7,  4, 15, 14,  3, 11,  5,  2, 12,
};

constexpr quint8 kSbox4[64] = {
     7, 13, 14,  3,  0,  6,  9, 10,  1,  2,  8,  5, 11, 12,  4, 15,
    13,  8, 11,  5,  6, 15,  0,  3,  4,  7,  2, 12,  1, 10, 14,  9,
    10,  6,  9,  0, 12, 11,  7, 13, 15,  1,  3, 14,  5,  2,  8,  4,
     3, 15,  0,  6, 10, 10, 13,  8,  9,  4,  5, 11, 12,  7,  2, 14,
};

constexpr quint8 kSbox5[64] = {
     2, 12,  4,  1,  7, 10, 11,  6,  8,  5,  3, 15, 13,  0, 14,  9,
    14, 11,  2, 12,  4,  7, 13,  1,  5,  0, 15, 10,  3,  9,  8,  6,
     4,  2,  1, 11, 10, 13,  7,  8, 15,  9, 12,  5,  6,  3,  0, 14,
    11,  8, 12,  7,  1, 14,  2, 13,  6, 15,  0,  9, 10,  4,  5,  3,
};

constexpr quint8 kSbox6[64] = {
    12,  1, 10, 15,  9,  2,  6,  8,  0, 13,  3,  4, 14,  7,  5, 11,
    10, 15,  4,  2,  7, 12,  9,  5,  6,  1, 13, 14,  0, 11,  3,  8,
     9, 14, 15,  5,  2,  8, 12,  3,  7,  0,  4, 10,  1, 13, 11,  6,
     4,  3,  2, 12,  9,  5, 15, 10, 11, 14,  1,  7,  6,  0,  8, 13,
};

constexpr quint8 kSbox7[64] = {
     4, 11,  2, 14, 15,  0,  8, 13,  3, 12,  9,  7,  5, 10,  6,  1,
    13,  0, 11,  7,  4,  9,  1, 10, 14,  3,  5, 12,  2, 15,  8,  6,
     1,  4, 11, 13, 12,  3,  7, 14, 10, 15,  6,  8,  0,  5,  9,  2,
     6, 11, 13,  8,  1,  4, 10,  7,  9,  5,  0, 15, 14,  2,  3, 12,
};

constexpr quint8 kSbox8[64] = {
    13,  2,  8,  4,  6, 15, 11,  1, 10,  9,  3, 14,  5,  0, 12,  7,
     1, 15, 13,  8, 10,  3,  7,  4, 12,  5,  6, 11,  0, 14,  9,  2,
     7, 11,  4,  1,  9, 12, 14,  2,  0,  6, 10, 13, 15,  3,  5,  8,
     2,  1, 14,  7,  4, 10,  8, 13, 15, 12,  9,  0,  3,  5,  6, 11,
};

void keySchedule(const quint8* key, quint8 schedule[16][6], const quint32 mode) {
    static constexpr quint32 kKeyRndShift[16] = { 1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1 };
    static constexpr quint32 kKeyPermC[28] = { 56, 48, 40, 32, 24, 16, 8,  0,  57, 49, 41, 33, 25, 17,
        9,  1, 58, 50, 42, 34, 26, 18, 10,  2,  59, 51, 43, 35 };
    static constexpr quint32 kKeyPermD[28] = { 62, 54, 46, 38, 30, 22, 14, 6,  61, 53, 45, 37, 29, 21,
        13, 5, 60, 52, 44, 36, 28, 20, 12,  4,  27, 19, 11,  3 };
    static constexpr quint32 kKeyCompression[48] = { 13, 16, 10, 23, 0,  4,  2,  27, 14, 5,  20, 9,
        22, 18, 11, 3,  25, 7,  15, 6,  26, 19, 12, 1,  40, 51, 30, 36, 46, 54, 29, 39, 50, 44, 32,
        47, 43, 48, 38, 55, 33, 52, 45, 41, 49, 35, 28, 31 };

    quint32 C = 0;
    quint32 D = 0;
    quint32 j = 31;
    for (quint32 i = 0; i < 28; ++i, --j) {
        C |= bitNum(key, static_cast<int>(kKeyPermC[i]), static_cast<int>(j));
    }
    j = 31;
    for (quint32 i = 0; i < 28; ++i, --j) {
        D |= bitNum(key, static_cast<int>(kKeyPermD[i]), static_cast<int>(j));
    }

    for (quint32 i = 0; i < 16; ++i) {
        C = ((C << kKeyRndShift[i]) | (C >> (28 - kKeyRndShift[i]))) & 0xfffffff0U;
        D = ((D << kKeyRndShift[i]) | (D >> (28 - kKeyRndShift[i]))) & 0xfffffff0U;

        const quint32 toGen = (mode == kDecrypt) ? 15 - i : i;
        for (j = 0; j < 6; ++j) {
            schedule[toGen][j] = 0;
        }
        for (j = 0; j < 24; ++j) {
            schedule[toGen][j / 8] |=
                bitNumIntr(C, static_cast<int>(kKeyCompression[j]), static_cast<int>(7 - (j % 8)));
        }
        for (; j < 48; ++j) {
            schedule[toGen][j / 8] |= bitNumIntr(
                D, static_cast<int>(kKeyCompression[j]) - 27, static_cast<int>(7 - (j % 8)));
        }
    }
}

void ip(quint32 state[2], const quint8* input) {
    state[0] = bitNum(input, 57, 31) | bitNum(input, 49, 30) | bitNum(input, 41, 29) | bitNum(input, 33, 28)
        | bitNum(input, 25, 27) | bitNum(input, 17, 26) | bitNum(input, 9, 25) | bitNum(input, 1, 24)
        | bitNum(input, 59, 23) | bitNum(input, 51, 22) | bitNum(input, 43, 21) | bitNum(input, 35, 20)
        | bitNum(input, 27, 19) | bitNum(input, 19, 18) | bitNum(input, 11, 17) | bitNum(input, 3, 16)
        | bitNum(input, 61, 15) | bitNum(input, 53, 14) | bitNum(input, 45, 13) | bitNum(input, 37, 12)
        | bitNum(input, 29, 11) | bitNum(input, 21, 10) | bitNum(input, 13, 9) | bitNum(input, 5, 8)
        | bitNum(input, 63, 7) | bitNum(input, 55, 6) | bitNum(input, 47, 5) | bitNum(input, 39, 4)
        | bitNum(input, 31, 3) | bitNum(input, 23, 2) | bitNum(input, 15, 1) | bitNum(input, 7, 0);

    state[1] = bitNum(input, 56, 31) | bitNum(input, 48, 30) | bitNum(input, 40, 29) | bitNum(input, 32, 28)
        | bitNum(input, 24, 27) | bitNum(input, 16, 26) | bitNum(input, 8, 25) | bitNum(input, 0, 24)
        | bitNum(input, 58, 23) | bitNum(input, 50, 22) | bitNum(input, 42, 21) | bitNum(input, 34, 20)
        | bitNum(input, 26, 19) | bitNum(input, 18, 18) | bitNum(input, 10, 17) | bitNum(input, 2, 16)
        | bitNum(input, 60, 15) | bitNum(input, 52, 14) | bitNum(input, 44, 13) | bitNum(input, 36, 12)
        | bitNum(input, 28, 11) | bitNum(input, 20, 10) | bitNum(input, 12, 9) | bitNum(input, 4, 8)
        | bitNum(input, 62, 7) | bitNum(input, 54, 6) | bitNum(input, 46, 5) | bitNum(input, 38, 4)
        | bitNum(input, 30, 3) | bitNum(input, 22, 2) | bitNum(input, 14, 1) | bitNum(input, 6, 0);
}

void invIp(const quint32 state[2], quint8* input) {
    input[3] = static_cast<quint8>(bitNumIntr(state[1], 7, 7) | bitNumIntr(state[0], 7, 6)
        | bitNumIntr(state[1], 15, 5) | bitNumIntr(state[0], 15, 4) | bitNumIntr(state[1], 23, 3)
        | bitNumIntr(state[0], 23, 2) | bitNumIntr(state[1], 31, 1) | bitNumIntr(state[0], 31, 0));

    input[2] = static_cast<quint8>(bitNumIntr(state[1], 6, 7) | bitNumIntr(state[0], 6, 6)
        | bitNumIntr(state[1], 14, 5) | bitNumIntr(state[0], 14, 4) | bitNumIntr(state[1], 22, 3)
        | bitNumIntr(state[0], 22, 2) | bitNumIntr(state[1], 30, 1) | bitNumIntr(state[0], 30, 0));

    input[1] = static_cast<quint8>(bitNumIntr(state[1], 5, 7) | bitNumIntr(state[0], 5, 6)
        | bitNumIntr(state[1], 13, 5) | bitNumIntr(state[0], 13, 4) | bitNumIntr(state[1], 21, 3)
        | bitNumIntr(state[0], 21, 2) | bitNumIntr(state[1], 29, 1) | bitNumIntr(state[0], 29, 0));

    input[0] = static_cast<quint8>(bitNumIntr(state[1], 4, 7) | bitNumIntr(state[0], 4, 6)
        | bitNumIntr(state[1], 12, 5) | bitNumIntr(state[0], 12, 4) | bitNumIntr(state[1], 20, 3)
        | bitNumIntr(state[0], 20, 2) | bitNumIntr(state[1], 28, 1) | bitNumIntr(state[0], 28, 0));

    input[7] = static_cast<quint8>(bitNumIntr(state[1], 3, 7) | bitNumIntr(state[0], 3, 6)
        | bitNumIntr(state[1], 11, 5) | bitNumIntr(state[0], 11, 4) | bitNumIntr(state[1], 19, 3)
        | bitNumIntr(state[0], 19, 2) | bitNumIntr(state[1], 27, 1) | bitNumIntr(state[0], 27, 0));

    input[6] = static_cast<quint8>(bitNumIntr(state[1], 2, 7) | bitNumIntr(state[0], 2, 6)
        | bitNumIntr(state[1], 10, 5) | bitNumIntr(state[0], 10, 4) | bitNumIntr(state[1], 18, 3)
        | bitNumIntr(state[0], 18, 2) | bitNumIntr(state[1], 26, 1) | bitNumIntr(state[0], 26, 0));

    input[5] = static_cast<quint8>(bitNumIntr(state[1], 1, 7) | bitNumIntr(state[0], 1, 6)
        | bitNumIntr(state[1], 9, 5) | bitNumIntr(state[0], 9, 4) | bitNumIntr(state[1], 17, 3)
        | bitNumIntr(state[0], 17, 2) | bitNumIntr(state[1], 25, 1) | bitNumIntr(state[0], 25, 0));

    input[4] = static_cast<quint8>(bitNumIntr(state[1], 0, 7) | bitNumIntr(state[0], 0, 6)
        | bitNumIntr(state[1], 8, 5) | bitNumIntr(state[0], 8, 4) | bitNumIntr(state[1], 16, 3)
        | bitNumIntr(state[0], 16, 2) | bitNumIntr(state[1], 24, 1) | bitNumIntr(state[0], 24, 0));
}

[[nodiscard]] quint32 f(quint32 state, const quint8* key) {
    quint8 lrgstate[6];

    quint32 t1 = bitNumIntl(state, 31, 0) | ((state & 0xf0000000U) >> 1) | bitNumIntl(state, 4, 5)
        | bitNumIntl(state, 3, 6) | ((state & 0x0f000000U) >> 3) | bitNumIntl(state, 8, 11)
        | bitNumIntl(state, 7, 12) | ((state & 0x00f00000U) >> 5) | bitNumIntl(state, 12, 17)
        | bitNumIntl(state, 11, 18) | ((state & 0x000f0000U) >> 7) | bitNumIntl(state, 16, 23);

    quint32 t2 = bitNumIntl(state, 15, 0) | ((state & 0x0000f000U) << 15) | bitNumIntl(state, 20, 5)
        | bitNumIntl(state, 19, 6) | ((state & 0x00000f00U) << 13) | bitNumIntl(state, 24, 11)
        | bitNumIntl(state, 23, 12) | ((state & 0x000000f0U) << 11) | bitNumIntl(state, 28, 17)
        | bitNumIntl(state, 27, 18) | ((state & 0x0000000fU) << 9) | bitNumIntl(state, 0, 23);

    lrgstate[0] = static_cast<quint8>((t1 >> 24) & 0x000000ffU);
    lrgstate[1] = static_cast<quint8>((t1 >> 16) & 0x000000ffU);
    lrgstate[2] = static_cast<quint8>((t1 >> 8) & 0x000000ffU);
    lrgstate[3] = static_cast<quint8>((t2 >> 24) & 0x000000ffU);
    lrgstate[4] = static_cast<quint8>((t2 >> 16) & 0x000000ffU);
    lrgstate[5] = static_cast<quint8>((t2 >> 8) & 0x000000ffU);

    lrgstate[0] ^= key[0];
    lrgstate[1] ^= key[1];
    lrgstate[2] ^= key[2];
    lrgstate[3] ^= key[3];
    lrgstate[4] ^= key[4];
    lrgstate[5] ^= key[5];

    const quint8 in0 = static_cast<quint8>(lrgstate[0] >> 2);
    const quint8 in1 = static_cast<quint8>(((lrgstate[0] & 0x03) << 4) | (lrgstate[1] >> 4));
    const quint8 in2 = static_cast<quint8>(((lrgstate[1] & 0x0f) << 2) | (lrgstate[2] >> 6));
    const quint8 in3 = static_cast<quint8>(lrgstate[2] & 0x3f);
    const quint8 in4 = static_cast<quint8>(lrgstate[3] >> 2);
    const quint8 in5 = static_cast<quint8>(((lrgstate[3] & 0x03) << 4) | (lrgstate[4] >> 4));
    const quint8 in6 = static_cast<quint8>(((lrgstate[4] & 0x0f) << 2) | (lrgstate[5] >> 6));
    const quint8 in7 = static_cast<quint8>(lrgstate[5] & 0x3f);

    state = (static_cast<quint32>(kSbox1[sboxBit(in0)]) << 28)
        | (static_cast<quint32>(kSbox2[sboxBit(in1)]) << 24)
        | (static_cast<quint32>(kSbox3[sboxBit(in2)]) << 20)
        | (static_cast<quint32>(kSbox4[sboxBit(in3)]) << 16)
        | (static_cast<quint32>(kSbox5[sboxBit(in4)]) << 12)
        | (static_cast<quint32>(kSbox6[sboxBit(in5)]) << 8)
        | (static_cast<quint32>(kSbox7[sboxBit(in6)]) << 4)
        | static_cast<quint32>(kSbox8[sboxBit(in7)]);

    state = bitNumIntl(state, 15, 0) | bitNumIntl(state, 6, 1) | bitNumIntl(state, 19, 2)
        | bitNumIntl(state, 20, 3) | bitNumIntl(state, 28, 4) | bitNumIntl(state, 11, 5)
        | bitNumIntl(state, 27, 6) | bitNumIntl(state, 16, 7) | bitNumIntl(state, 0, 8)
        | bitNumIntl(state, 14, 9) | bitNumIntl(state, 22, 10) | bitNumIntl(state, 25, 11)
        | bitNumIntl(state, 4, 12) | bitNumIntl(state, 17, 13) | bitNumIntl(state, 30, 14)
        | bitNumIntl(state, 9, 15) | bitNumIntl(state, 1, 16) | bitNumIntl(state, 7, 17)
        | bitNumIntl(state, 23, 18) | bitNumIntl(state, 13, 19) | bitNumIntl(state, 31, 20)
        | bitNumIntl(state, 26, 21) | bitNumIntl(state, 2, 22) | bitNumIntl(state, 8, 23)
        | bitNumIntl(state, 18, 24) | bitNumIntl(state, 12, 25) | bitNumIntl(state, 29, 26)
        | bitNumIntl(state, 5, 27) | bitNumIntl(state, 21, 28) | bitNumIntl(state, 10, 29)
        | bitNumIntl(state, 3, 30) | bitNumIntl(state, 24, 31);

    return state;
}

void crypt(const quint8* input, quint8* output, const quint8 key[16][6]) {
    quint32 state[2];
    ip(state, input);

    for (quint32 idx = 0; idx < 15; ++idx) {
        const quint32 t = state[1];
        state[1] = f(state[1], key[idx]) ^ state[0];
        state[0] = t;
    }
    state[0] = f(state[1], key[15]) ^ state[0];

    invIp(state, output);
}

void tripleDesKeySetup(const quint8* key, quint8 schedule[3][16][6], const quint32 mode) {
    if (mode == kEncrypt) {
        keySchedule(key, schedule[0], mode);
        keySchedule(key + 8, schedule[1], kDecrypt);
        keySchedule(key + 16, schedule[2], mode);
    } else {
        keySchedule(key, schedule[2], mode);
        keySchedule(key + 8, schedule[1], kEncrypt);
        keySchedule(key + 16, schedule[0], mode);
    }
}

void tripleDesCrypt(const quint8* input, quint8* output, const quint8 schedule[3][16][6]) {
    quint8 step1[8];
    quint8 step2[8];
    crypt(input, step1, schedule[0]);
    crypt(step1, step2, schedule[1]);
    crypt(step2, output, schedule[2]);
}

struct TripleDesSchedule {
    quint8 rounds[3][16][6];
};

[[nodiscard]] const TripleDesSchedule& decryptSchedule() {
    static const TripleDesSchedule kSchedule = [] {
        TripleDesSchedule s{};
        constexpr quint8 kKey[24] = { '!', '@', '#', ')', '(', '*', '$', '%', '1', '2', '3', 'Z',
            'X', 'C', '!', '@', '!', '@', '#', ')', '(', 'N', 'H', 'L' };
        tripleDesKeySetup(kKey, s.rounds, kDecrypt);
        return s;
    }();
    return kSchedule;
}

} // namespace

QByteArray qrc3desDecrypt(const QByteArray& cipher) {
    if (cipher.isEmpty() || cipher.size() % 8 != 0) {
        return {};
    }

    QByteArray out(cipher.size(), '\0');
    const TripleDesSchedule& sched = decryptSchedule();
    for (qsizetype i = 0; i < cipher.size(); i += 8) {
        quint8 block[8];
        tripleDesCrypt(reinterpret_cast<const quint8*>(cipher.constData() + i), block, sched.rounds);
        std::memcpy(out.data() + i, block, 8);
    }
    return out;
}

} // namespace caelestia::services
