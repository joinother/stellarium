#include "AetherisAudioNative.h"

#include <hilog/log.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

constexpr unsigned int AETHERIS_LOG_DOMAIN = 0xD003;
constexpr const char* AETHERIS_LOG_TAG = "AetherisNativeDSP";

constexpr int SR = 48000;
constexpr float SR_F = 48000.0f;
constexpr float PI_F = 3.14159265358979323846f;
constexpr float TWO_PI_F = 6.28318530717958647692f;
constexpr int TABLE_SIZE = 2048;

constexpr int MAX_FG_VOICES = 20;
constexpr int MAX_BG_VOICES = 72;
constexpr int MAX_CHOIR_VOICES = 8;
constexpr int MAX_NOISE_VOICES = 14;
constexpr int MAX_EVENTS = 64;
constexpr int MAX_PARTIALS = 6;

enum WaveKind : uint8_t {
    WAVE_SINE = 0,
    WAVE_GLASS = 1,
    WAVE_CELLO = 2,
    WAVE_VOCAL = 3,
    WAVE_TRI = 4
};

struct Biquad {
    float b0 = 1.0f, b1 = 0.0f, b2 = 0.0f, a1 = 0.0f, a2 = 0.0f;
    float x1 = 0.0f, x2 = 0.0f, y1 = 0.0f, y2 = 0.0f;

    void reset() { x1 = x2 = y1 = y2 = 0.0f; }

    void setLowpass(float freq, float Q) {
        freq = std::max(25.0f, std::min(SR_F * 0.44f, freq));
        const float w0 = TWO_PI_F * freq / SR_F;
        const float cw = std::cos(w0);
        const float sw = std::sin(w0);
        const float alpha = sw / (2.0f * std::max(0.25f, Q));
        const float a0 = 1.0f + alpha;
        b0 = ((1.0f - cw) * 0.5f) / a0;
        b1 = (1.0f - cw) / a0;
        b2 = b0;
        a1 = (-2.0f * cw) / a0;
        a2 = (1.0f - alpha) / a0;
    }

    void setHighpass(float freq, float Q) {
        freq = std::max(15.0f, std::min(SR_F * 0.44f, freq));
        const float w0 = TWO_PI_F * freq / SR_F;
        const float cw = std::cos(w0);
        const float sw = std::sin(w0);
        const float alpha = sw / (2.0f * std::max(0.25f, Q));
        const float a0 = 1.0f + alpha;
        b0 = ((1.0f + cw) * 0.5f) / a0;
        b1 = -(1.0f + cw) / a0;
        b2 = b0;
        a1 = (-2.0f * cw) / a0;
        a2 = (1.0f - alpha) / a0;
    }

    void setBandpass(float freq, float Q) {
        freq = std::max(35.0f, std::min(SR_F * 0.44f, freq));
        const float w0 = TWO_PI_F * freq / SR_F;
        const float cw = std::cos(w0);
        const float sw = std::sin(w0);
        const float alpha = sw / (2.0f * std::max(0.35f, Q));
        const float a0 = 1.0f + alpha;
        b0 = alpha / a0;
        b1 = 0.0f;
        b2 = -alpha / a0;
        a1 = (-2.0f * cw) / a0;
        a2 = (1.0f - alpha) / a0;
    }

    void setHighshelf(float freq, float gainDb) {
        const float A = std::pow(10.0f, gainDb / 40.0f);
        const float w0 = TWO_PI_F * std::max(40.0f, std::min(SR_F * 0.44f, freq)) / SR_F;
        const float cw = std::cos(w0);
        const float sw = std::sin(w0);
        const float alpha = sw * 0.5f * 1.41421356f;
        const float sqA = 2.0f * std::sqrt(A) * alpha;
        const float a0 = (A + 1.0f) - (A - 1.0f) * cw + sqA;
        b0 = (A * ((A + 1.0f) + (A - 1.0f) * cw + sqA)) / a0;
        b1 = (-2.0f * A * ((A - 1.0f) + (A + 1.0f) * cw)) / a0;
        b2 = (A * ((A + 1.0f) + (A - 1.0f) * cw - sqA)) / a0;
        a1 = (2.0f * ((A - 1.0f) - (A + 1.0f) * cw)) / a0;
        a2 = ((A + 1.0f) - (A - 1.0f) * cw - sqA) / a0;
    }

    void setLowshelf(float freq, float gainDb) {
        const float A = std::pow(10.0f, gainDb / 40.0f);
        const float w0 = TWO_PI_F * std::max(30.0f, std::min(SR_F * 0.44f, freq)) / SR_F;
        const float cw = std::cos(w0);
        const float sw = std::sin(w0);
        const float alpha = sw * 0.5f * 1.41421356f;
        const float sqA = 2.0f * std::sqrt(A) * alpha;
        const float a0 = (A + 1.0f) + (A - 1.0f) * cw + sqA;
        b0 = (A * ((A + 1.0f) - (A - 1.0f) * cw + sqA)) / a0;
        b1 = (2.0f * A * ((A - 1.0f) - (A + 1.0f) * cw)) / a0;
        b2 = (A * ((A + 1.0f) - (A - 1.0f) * cw - sqA)) / a0;
        a1 = (-2.0f * ((A - 1.0f) + (A + 1.0f) * cw)) / a0;
        a2 = ((A + 1.0f) + (A - 1.0f) * cw - sqA) / a0;
    }

    inline float step(float x) {
        float y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        if (std::fabs(y) < 1e-24f) y = 0.0f;
        x2 = x1; x1 = x;
        y2 = y1; y1 = y;
        return y;
    }
};

struct MoodChordSpec {
    int count;
    int notes[6];
    int bass;
};

struct SkyMoodDef {
    const char* key;
    int numIntervals;
    int intervals[7];
    MoodChordSpec chords[8];
};

static const SkyMoodDef SKY_MOODS[5] = {
    // 0: newmoon (Lydian celestial cathedral)
    {
        "newmoon", 7, {0, 2, 4, 6, 7, 9, 11},
        {
            {4, {7, 12, 14, 19, 0, 0}, 0},
            {4, {5, 12, 16, 21, 0, 0}, 5},
            {5, {7, 12, 14, 18, 19, 0}, 0},
            {4, {9, 12, 16, 19, 0, 0}, 9},
            {2, {12, 14, 0, 0, 0, 0}, 0},
            {5, {5, 12, 16, 19, 21, 0}, 5},
            {6, {0, 7, 12, 14, 16, 19}, 0},
            {4, {7, 12, 14, 19, 0, 0}, 0}
        }
    },
    // 1: fullmoon (Warm amber pentatonic add9)
    {
        "fullmoon", 5, {0, 2, 4, 7, 9, 0, 0},
        {
            {4, {7, 12, 14, 19, 0, 0}, 0},
            {5, {5, 12, 14, 17, 21, 0}, 5},
            {4, {4, 12, 14, 19, 0, 0}, 0},
            {4, {9, 12, 16, 19, 0, 0}, 9},
            {2, {12, 19, 0, 0, 0, 0}, 0},
            {5, {5, 12, 16, 19, 21, 0}, 5},
            {6, {0, 7, 12, 14, 16, 21}, 0},
            {4, {7, 12, 14, 19, 0, 0}, 0}
        }
    },
    // 2: aurora (Nordic Dorian epic)
    {
        "aurora", 6, {0, 2, 3, 5, 7, 9, 0},
        {
            {4, {7, 12, 14, 19, 0, 0}, 0},
            {4, {10, 14, 17, 19, 0, 0}, 10},
            {4, {5, 12, 15, 19, 0, 0}, 5},
            {4, {9, 12, 15, 19, 0, 0}, 9},
            {2, {12, 15, 0, 0, 0, 0}, 0},
            {5, {5, 12, 14, 17, 21, 0}, 5},
            {6, {0, 7, 12, 14, 15, 19}, 0},
            {4, {7, 12, 14, 19, 0, 0}, 0}
        }
    },
    // 3: twilight (Quartal clouds)
    {
        "twilight", 5, {0, 2, 5, 7, 10, 0, 0},
        {
            {4, {5, 12, 14, 19, 0, 0}, 0},
            {4, {10, 12, 17, 19, 0, 0}, 10},
            {4, {5, 10, 14, 19, 0, 0}, 5},
            {4, {7, 10, 14, 17, 0, 0}, 7},
            {2, {12, 17, 0, 0, 0, 0}, 0},
            {5, {5, 12, 14, 17, 22, 0}, 5},
            {6, {0, 5, 12, 14, 19, 22}, 0},
            {4, {7, 12, 14, 19, 0, 0}, 0}
        }
    },
    // 4: oriental (Ancient Star Officials Kumoi)
    {
        "oriental", 5, {0, 2, 3, 7, 9, 0, 0},
        {
            {4, {7, 12, 14, 19, 0, 0}, 0},
            {4, {3, 12, 14, 19, 0, 0}, 3},
            {4, {5, 12, 14, 19, 0, 0}, 5},
            {4, {9, 12, 15, 19, 0, 0}, 9},
            {2, {12, 19, 0, 0, 0, 0}, 0},
            {5, {3, 10, 14, 19, 21, 0}, 3},
            {6, {0, 7, 12, 14, 15, 19}, 0},
            {4, {7, 12, 14, 19, 0, 0}, 0}
        }
    }
};

struct NarrativeScene {
    float gain;
    float tension;
    float choirOpen;
    float shimmer;
    float pulsar;
    float air;
    float cello;
    float organSub;
    float durMul;
    int motifMode; // 0=call,1=answer,2=soar,3=echo,4=whisper,5=crown,6=tail
};

static const NarrativeScene NARRATIVE_ARC[8] = {
    {0.78f, 0.26f, 0.22f, 0.42f, 0.00f, 0.24f, 0.45f, 0.00f, 1.00f, 0},
    {0.96f, 0.52f, 0.56f, 0.65f, 0.00f, 0.45f, 0.62f, 0.00f, 1.04f, 1},
    {1.08f, 0.74f, 0.76f, 0.85f, 0.55f, 0.70f, 0.70f, 0.00f, 1.08f, 2},
    {0.74f, 0.34f, 0.34f, 0.48f, 0.00f, 0.28f, 0.52f, 0.00f, 0.98f, 3},
    {0.44f, 0.12f, 0.00f, 0.30f, 0.00f, 0.18f, 0.00f, 0.00f, 0.88f, 4}, // Eye of Silence!
    {1.10f, 0.82f, 0.82f, 0.90f, 0.78f, 0.80f, 0.80f, 0.68f, 1.06f, 0},
    {1.24f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 0.78f, 1.00f, 1.16f, 5}, // Cathedral Climax!
    {0.66f, 0.22f, 0.20f, 0.40f, 0.00f, 0.24f, 0.30f, 0.00f, 1.02f, 6}
};

struct PartialState {
    float phase = 0.0f;
    float phaseInc = 0.0f;
    float amp = 0.0f;
    float decayMul = 0.9999f;
    float env = 1.0f;
    WaveKind wave = WAVE_SINE;
};

struct ForegroundVoice {
    bool active = false;
    bool stealing = false;
    uint64_t birthOrder = 0;
    float stealGain = 1.0f;
    float stealStep = 0.0f;

    int samplePos = 0;
    int delaySamples = 0;
    int attackSamples = 480;
    float masterGain = 0.0f;
    float drySend = 0.5f;
    float wetSend = 0.6f;
    float shimmerSend = 0.0f;
    float echoSend = 0.0f;
    float panL = 0.707f;
    float panR = 0.707f;
    bool antiphaseR = false;
    bool haasRight = false;
    bool pitchGlide = false;
    float glideStartMul = 1.0f;
    float glideEndMul = 1.0f;
    int glideSamples = 1;

    // Optional FSK modulation for satellites
    bool isFsk = false;
    float fskBaseInc = 0.0f;
    float fskAltInc = 0.0f;
    int fskPeriodSamples = 1200;
    int fskBitSamples = 1344;
    int fskTotalSamples = 10000;
    uint32_t fskBits = 0;

    int numPartials = 0;
    PartialState partials[MAX_PARTIALS];
    Biquad lpf;
};

struct AmbientVoice {
    bool active = false;
    bool isPluck = false; // True for felt piano / harp / celesta / starlight micro-sparkles!
    int samplePos = 0;
    int delaySamples = 0;
    int attackSamples = SR * 4;
    int holdSamples = SR * 12;
    int releaseSamples = SR * 5;
    float amp = 0.0f;
    float pluckEnv = 1.0f;
    float pluckDecayMul = 0.9999f;
    float panL = 0.707f;
    float panR = 0.707f;
    float phase = 0.0f;
    float phase2 = 0.0f; // Optional warm 2nd harmonic / unison layer for piano/harp richness
    float baseInc = 0.0f;
    float harm2Ratio = 2.0f;
    float harm2Amp = 0.0f;
    float harm2DecayMul = 0.9995f;
    float harm2Env = 1.0f;
    float lfoPhase = 0.0f;
    float lfoInc = 0.0f;
    float lfoDepth = 0.002f;
    WaveKind wave = WAVE_CELLO;
    bool useLpf = false;
    float fcStart = 400.0f;
    float fcPeak = 1200.0f;
    float toAmbient = 1.0f;
    float toDry = 0.0f; // Direct intimate presence for felt piano / harp articulation
    float toShimmer = 0.0f;
    float toEcho = 0.0f;
    Biquad lpf;
};

struct ChoirVoice {
    bool active = false;
    int samplePos = 0;
    int delaySamples = 0;
    int attackSamples = SR * 5;
    int holdSamples = SR * 12;
    int releaseSamples = SR * 5;
    float amp = 0.0f;
    float panL = 0.707f;
    float panR = 0.707f;
    float phase = 0.0f;
    float baseInc = 0.0f;
    float vibPhase = 0.0f;
    float vibInc = 0.0f;
    float openAmt = 0.5f;
    Biquad f1, f2;
};

struct NoiseVoice {
    bool active = false;
    int samplePos = 0;
    int delaySamples = 0;
    int attackSamples = 480;
    int totalSamples = SR * 2;
    float amp = 0.0f;
    float panL = 0.707f;
    float panR = 0.707f;
    float fcStart = 600.0f;
    float fcMid = 1800.0f;
    float fcEnd = 600.0f;
    float q = 2.0f;
    float toDry = 0.0f;
    float toReverb = 1.0f;
    float toShimmer = 0.0f;
    bool isPink = true;
    Biquad bp;
};

uint32_t fnv1aHash(const std::string& s) {
    uint32_t h = 0x811c9dc5u;
    for (unsigned char c : s) {
        h ^= static_cast<uint32_t>(c);
        h *= 0x01000193u;
    }
    return h;
}

class AetherisEngine {
public:
    AetherisEngine() {
        buildTables();
        initReverbAndDelays();
        updateMasterFilters();
        applySeedInternal("HarmonyOS-Stargazer-01");
    }

    void setMaster(bool musicOn, bool sfxOn, float vol, bool duck) {
        std::lock_guard<std::mutex> lock(mu_);
        const bool wasMusic = musicEnabled_;
        musicEnabled_ = musicOn;
        sfxEnabled_ = sfxOn;
        masterVolume_ = std::max(0.0f, std::min(1.0f, vol));
        guideDucked_ = duck;
        if (musicOn && !wasMusic) {
            ambientStep_ = 0;
            samplesUntilNextBreath_ = 0; // start immediately!
            lowPowerMode_ = false;
            idleSamples_ = 0;
        }
        if (!sfxOn) {
            for (auto& v : fgVoices_) v.active = false;
        }
    }

    void setDNA(const std::string& seed, const std::string& moodStr, int rootPc,
                float jade, float felt, float tape, float bowl, float variation) {
        std::lock_guard<std::mutex> lock(mu_);
        seedStr_ = seed.empty() ? "Aetheris" : seed;
        seedNum_ = fnv1aHash(seedStr_);
        moodIdx_ = findMoodIdx(moodStr);
        rootPc_ = ((rootPc % 12) + 12) % 12;
        wJade_ = std::max(0.0f, std::min(1.0f, jade));
        wFelt_ = std::max(0.0f, std::min(1.0f, felt));
        wTape_ = std::max(0.0f, std::min(1.0f, tape));
        wBowl_ = std::max(0.0f, std::min(1.0f, bowl));
        variation_ = std::max(0.0f, std::min(1.0f, variation));
        deriveMotifFromSeed();
        resetIdleLocked();
    }

    std::string applySeed(const std::string& seed) {
        std::lock_guard<std::mutex> lock(mu_);
        applySeedInternal(seed);
        resetIdleLocked();
        char buf[384];
        std::snprintf(
            buf, sizeof(buf),
            "{\"seed\":\"%s\",\"mood\":\"%s\",\"rootPc\":%d,\"jade\":%.2f,\"felt\":%.2f,\"tape\":%.2f,\"bowl\":%.2f,\"a4Ref\":%.1f}",
            seedStr_.c_str(), SKY_MOODS[moodIdx_].key, rootPc_,
            wJade_, wFelt_, wTape_, wBowl_, a4Ref_);
        return std::string(buf);
    }

    void setOutputMode(bool isSpeaker) {
        std::lock_guard<std::mutex> lock(mu_);
        if (speakerMode_ != isSpeaker) {
            speakerMode_ = isSpeaker;
            updateMasterFilters();
        }
    }

    void setHorizonAltitude(float altDeg) {
        std::lock_guard<std::mutex> lock(mu_);
        horizonAltDeg_ = std::max(-90.0f, std::min(90.0f, altDeg));
        updateMasterFilters();
    }

    void setLowPower(bool enabled) {
        std::lock_guard<std::mutex> lock(mu_);
        lowPowerMode_ = enabled;
        if (!enabled) idleSamples_ = 0;
    }

    void skipNextAct() {
        std::lock_guard<std::mutex> lock(mu_);
        resetIdleLocked();
        if (musicEnabled_) {
            samplesUntilNextBreath_ = 0;
        }
    }

    void resetAll() {
        std::lock_guard<std::mutex> lock(mu_);
        for (auto& v : fgVoices_) v.active = false;
        for (auto& v : bgVoices_) v.active = false;
        for (auto& v : choirVoices_) v.active = false;
        for (auto& v : noiseVoices_) v.active = false;
        for (int k = 0; k < 4; k++) {
            std::fill(fdnL_[k].begin(), fdnL_[k].end(), 0.0f);
            std::fill(fdnR_[k].begin(), fdnR_[k].end(), 0.0f);
            fdnLpL_[k] = fdnLpR_[k] = 0.0f;
            fdnDcXL_[k] = fdnDcYL_[k] = fdnDcXR_[k] = fdnDcYR_[k] = 0.0f;
            std::fill(apL_[k].begin(), apL_[k].end(), 0.0f);
            std::fill(apR_[k].begin(), apR_[k].end(), 0.0f);
        }
        std::fill(chorusBufL_.begin(), chorusBufL_.end(), 0.0f);
        std::fill(chorusBufR_.begin(), chorusBufR_.end(), 0.0f);
        std::fill(echoBufL_.begin(), echoBufL_.end(), 0.0f);
        std::fill(echoBufR_.begin(), echoBufR_.end(), 0.0f);
        std::fill(haasBuf_.begin(), haasBuf_.end(), 0.0f);
        musicGainEnv_ = 0.0f;
        samplesUntilNextBreath_ = 0;
        sidechainDuck_ = 1.0f;
        sidechainHoldSamples_ = 0;
    }

    void triggerStar(float tempK, float mag, float distLy, float pan, float altitude) {
        std::lock_guard<std::mutex> lock(mu_);
        if (!sfxEnabled_) return;
        resetIdleLocked();
        triggerStarUnlocked(tempK > 100.0f ? tempK : 5800.0f,
                            (mag > 40.0f || !std::isfinite(mag)) ? 2.5f : std::max(-1.5f, std::min(6.0f, mag)),
                            distLy > 0.5f ? distLy : 120.0f,
                            pan,
                            std::max(0.0f, std::min(1.0f, altitude)));
    }

    void triggerCue(const std::string& cueId, float pan) {
        std::lock_guard<std::mutex> lock(mu_);
        if (!sfxEnabled_) return;
        resetIdleLocked();
        const float p = std::max(-0.85f, std::min(0.85f, pan));

        // 1. 7 Spectral Stars
        if (cueId == "star_O" || cueId == "star-O") { triggerStarUnlocked(33000.0f, 0.2f, 520.0f, p, 0.9f); return; }
        if (cueId == "star_B" || cueId == "star-B") { triggerStarUnlocked(18500.0f, 0.5f, 420.0f, p, 0.8f); return; }
        if (cueId == "star_A" || cueId == "star-A") { triggerStarUnlocked(9600.0f, 0.1f, 25.0f, p, 0.72f); return; }
        if (cueId == "star_F" || cueId == "star-F") { triggerStarUnlocked(6800.0f, 0.8f, 90.0f, p, 0.62f); return; }
        if (cueId == "star_G" || cueId == "star-G") { triggerStarUnlocked(5778.0f, 1.0f, 45.0f, p, 0.52f); return; }
        if (cueId == "star_K" || cueId == "star-K") { triggerStarUnlocked(4400.0f, 0.7f, 120.0f, p, 0.40f); return; }
        if (cueId == "star_M" || cueId == "star-M") { triggerStarUnlocked(3100.0f, 0.5f, 540.0f, p, 0.28f); return; }

        // 2. Solar System (14+): Sun, Moon, Terrestrial 1..5, GasGiant 1..5, Minor Body, Satellites/Stations
        if (cueId == "sun" || cueId == "solar-sun") { triggerSunLocked(p); return; }
        if (cueId == "moon") { triggerPlanetLocked(false, 4, p); return; }
        if (cueId == "minor_body") { triggerPlanetLocked(false, 5, p); return; }
        if (cueId.rfind("terrestrial_", 0) == 0 || cueId.rfind("terr-", 0) == 0) {
            int tier = cueId.back() - '0';
            triggerPlanetLocked(false, std::max(1, std::min(5, tier)), p);
            return;
        }
        if (cueId.rfind("gas_giant_", 0) == 0 || cueId.rfind("gas-", 0) == 0) {
            int tier = cueId.back() - '0';
            triggerPlanetLocked(true, std::max(1, std::min(5, tier)), p);
            return;
        }
        if (cueId == "station_tiangong") { triggerSatelliteLocked(p, 1); return; }
        if (cueId == "station_iss") { triggerSatelliteLocked(p, 0); return; }
        if (cueId.rfind("satellite_", 0) == 0 || cueId.rfind("sat-", 0) == 0) {
            int v = cueId.back() - '0';
            triggerSatelliteLocked(p, std::max(0, std::min(2, v)));
            return;
        }

        // 3. Deep Sky (20+): Comet, Nebulae, Clusters, Galaxy, Constellations 0..14
        if (cueId == "comet" || cueId == "ds-comet") { triggerCometLocked(p); return; }
        if (cueId == "dso_planetary_nebula" || cueId == "ds-planetary") { triggerNebulaLocked(p, true); return; }
        if (cueId == "dso_diffuse_nebula" || cueId == "dso_dark_nebula" || cueId == "dso_supernova" ||
            cueId == "dso_galaxy" || cueId == "ds-diffuse") {
            triggerNebulaLocked(p, false);
            return;
        }
        if (cueId == "dso_globular_cluster" || cueId == "ds-globular") { triggerClusterLocked(p, true); return; }
        if (cueId == "dso_open_cluster" || cueId == "ds-open") { triggerClusterLocked(p, false); return; }
        if (cueId.rfind("constellation_", 0) == 0 || cueId.rfind("const-", 0) == 0) {
            const size_t sep = cueId.find_last_of("_-");
            int idx = (sep != std::string::npos) ? std::atoi(cueId.c_str() + sep + 1) : 0;
            triggerConstellationPresetLocked(idx, p);
            return;
        }

        // 4. Observation Bands (Microwave / Infrared / X-ray — auto speaker-safe!)
        if (cueId == "band_xray" || cueId == "band-xray" || cueId == "ui-band-xray") { triggerBandLocked(true); return; }
        if (cueId == "band_radio" || cueId == "band_infrared" || cueId == "band-micro" || cueId == "ui-band-ir") { triggerBandLocked(false); return; }

        // 5. Scenarios: Fly-To / Zoom-Out / Audio Logo
        if (cueId == "fly_to") { triggerFlyToLocked(p, false); return; }
        if (cueId == "fly_out") { triggerFlyToLocked(p, true); return; }
        if (cueId == "audio_logo") { triggerAudioLogoLocked(); return; }

        // 6. All 10 UI Interactions
        triggerUiLocked(cueId);
    }

    // Zero-allocation real-time 48kHz stereo S16LE renderer! Returns peak amplitude [0..1].
    float renderBlock(int16_t* outInterleaved, int frames) {
        std::lock_guard<std::mutex> lock(mu_);
        if (frames <= 0) return 0.0f;

        const bool wantMusic = musicEnabled_ && masterVolume_ > 0.001f;
        const float musicTarget = wantMusic ? (guideDucked_ ? 0.58f : 1.00f) : 0.0f;

        if (wantMusic) {
            idleSamples_ += frames;
            if (!lowPowerMode_ && idleSamples_ >= SR * 30) {
                lowPowerMode_ = true;
            }
            samplesUntilNextBreath_ -= frames;
            if (samplesUntilNextBreath_ <= 0) {
                scheduleAmbientBreathLocked();
            }
        }

        float peakOut = 0.0f;

        for (int i = 0; i < frames; ++i) {
            // Smooth master music fade & foreground auto-ducking
            musicGainEnv_ += (musicTarget - musicGainEnv_) * 0.00016f;
            if (sidechainHoldSamples_ > 0) {
                sidechainHoldSamples_--;
                sidechainDuck_ += (sidechainTarget_ - sidechainDuck_) * 0.0008f;
            } else {
                sidechainDuck_ += (1.0f - sidechainDuck_) * 0.00009f;
            }

            float fgDryL = 0.0f, fgDryR = 0.0f;
            float fgWetL = 0.0f, fgWetR = 0.0f;
            float ambBusL = 0.0f, ambBusR = 0.0f;
            float shimBusL = 0.0f, shimBusR = 0.0f;
            float echoIn = 0.0f;

            // --- A) Foreground 16-Voice Pool ---
            if (sfxEnabled_) {
                for (int vi = 0; vi < MAX_FG_VOICES; ++vi) {
                    ForegroundVoice& v = fgVoices_[vi];
                    if (!v.active) continue;
                    if (v.delaySamples > 0) {
                        v.delaySamples--;
                        continue;
                    }
                    float s = 0.0f;
                    bool anyAlive = false;
                    if (v.isFsk) {
                        if (v.samplePos < v.fskTotalSamples) {
                            anyAlive = true;
                            const int bitIdx = (v.samplePos / v.fskBitSamples) & 31;
                            const bool hiBit = ((v.fskBits >> bitIdx) & 1u) != 0;
                            const float doppler = 1.0f - 0.032f * (static_cast<float>(v.samplePos) / static_cast<float>(v.fskTotalSamples));
                            v.partials[0].phase += (hiBit ? v.fskBaseInc : v.fskAltInc) * doppler;
                            if (v.partials[0].phase >= 1.0f) v.partials[0].phase -= 1.0f;
                            const int inBurst = v.samplePos % v.fskPeriodSamples;
                            float bEnv = (inBurst < v.fskPeriodSamples * 42 / 100) ? 1.0f : 0.0f;
                            if (inBurst < 280) bEnv *= static_cast<float>(inBurst) / 280.0f;
                            const float fade = 1.0f - 0.65f * (static_cast<float>(v.samplePos) / static_cast<float>(v.fskTotalSamples));
                            s = sampleTable(WAVE_SINE, v.partials[0].phase) * bEnv * fade;
                        }
                    } else {
                        float glideMul = 1.0f;
                        if (v.pitchGlide) {
                            const float u = std::min(1.0f, static_cast<float>(v.samplePos) / static_cast<float>(v.glideSamples));
                            glideMul = v.glideStartMul * std::pow(v.glideEndMul / std::max(0.05f, v.glideStartMul), u);
                        }
                        for (int p = 0; p < v.numPartials; ++p) {
                            PartialState& ps = v.partials[p];
                            if (ps.env < 0.00025f) continue;
                            anyAlive = true;
                            ps.phase += ps.phaseInc * glideMul;
                            if (ps.phase >= 1.0f) ps.phase -= 1.0f;
                            s += sampleTable(ps.wave, ps.phase) * ps.amp * ps.env;
                            ps.env *= ps.decayMul;
                        }
                    }
                    if (!anyAlive) {
                        v.active = false;
                        continue;
                    }
                    float atkEnv = (v.samplePos < v.attackSamples)
                        ? (static_cast<float>(v.samplePos) / static_cast<float>(v.attackSamples))
                        : 1.0f;
                    v.samplePos++;

                    if (v.stealing) {
                        v.stealGain -= v.stealStep;
                        if (v.stealGain <= 0.0005f) {
                            v.active = false;
                            continue;
                        }
                    }

                    s = v.lpf.step(s) * atkEnv * v.masterGain * v.stealGain;
                    float sL = s * v.panL;
                    float sR = s * v.panR;
                    if (v.antiphaseR) {
                        sR = -sL * 0.94f;
                    } else if (v.haasRight) {
                        // Mono-safe 11ms Haas spread for phone speaker mode!
                        haasBuf_[haasIdx_] = sL;
                        const int readIdx = (haasIdx_ + 1) % HAAS_LEN;
                        sR = haasBuf_[readIdx] * 0.92f;
                        haasIdx_ = readIdx;
                    }
                    fgDryL += sL * v.drySend;
                    fgDryR += sR * v.drySend;
                    fgWetL += sL * v.wetSend;
                    fgWetR += sR * v.wetSend;
                    if (v.shimmerSend > 0.001f) {
                        shimBusL += sL * v.shimmerSend;
                        shimBusR += sR * v.shimmerSend;
                    }
                    if (v.echoSend > 0.001f) {
                        echoIn += s * v.echoSend;
                    }
                }
            }

            // --- B) Background Cathedral Voices (Acoustic Strings + Liquid Shimmer + Pulsar + Cello + 16ft Sub) ---
            if (musicGainEnv_ > 0.0004f) {
                const float ambScale = musicGainEnv_ * sidechainDuck_;
                for (int bi = 0; bi < MAX_BG_VOICES; ++bi) {
                    AmbientVoice& v = bgVoices_[bi];
                    if (!v.active) continue;
                    if (v.delaySamples > 0) {
                        v.delaySamples--;
                        continue;
                    }
                    float env = 1.0f;
                    const int p = v.samplePos;
                    if (v.isPluck) {
                        if (v.pluckEnv < 0.0003f) {
                            v.active = false;
                            continue;
                        }
                        const float atk = (p < v.attackSamples)
                            ? (static_cast<float>(p) / static_cast<float>(std::max(1, v.attackSamples)))
                            : 1.0f;
                        env = atk * v.pluckEnv;
                        v.pluckEnv *= v.pluckDecayMul;
                    } else {
                        const int total = v.holdSamples + v.releaseSamples;
                        if (p >= total) {
                            v.active = false;
                            continue;
                        }
                        if (p < v.attackSamples) {
                            env = (static_cast<float>(p) / static_cast<float>(v.attackSamples)) * 0.90f;
                        } else if (p < v.holdSamples) {
                            const float u = static_cast<float>(p - v.attackSamples) / static_cast<float>(std::max(1, v.holdSamples - v.attackSamples));
                            env = (u < 0.50f) ? (0.90f + 0.15f * (u * 2.0f)) : (1.05f - 0.30f * ((u - 0.50f) * 2.0f));
                        } else {
                            const float ru = static_cast<float>(p - v.holdSamples) / static_cast<float>(std::max(1, v.releaseSamples));
                            env = 0.75f * std::exp(-4.4f * ru);
                        }
                    }

                    v.lfoPhase += v.lfoInc;
                    if (v.lfoPhase >= 1.0f) v.lfoPhase -= 1.0f;
                    const float lfo = sampleTable(WAVE_SINE, v.lfoPhase);
                    const float curInc = v.baseInc * (1.0f + lfo * v.lfoDepth);
                    v.phase += curInc;
                    if (v.phase >= 1.0f) v.phase -= 1.0f;

                    float x = sampleTable(v.wave, v.phase);
                    if (v.harm2Amp > 0.001f && v.harm2Env > 0.0004f) {
                        v.phase2 += curInc * v.harm2Ratio;
                        if (v.phase2 >= 1.0f) v.phase2 -= 1.0f;
                        x += sampleTable(WAVE_SINE, v.phase2) * v.harm2Amp * v.harm2Env;
                        v.harm2Env *= v.harm2DecayMul;
                    }
                    if (v.useLpf) {
                        if (!v.isPluck && (p & 127) == 0) {
                            const int total = std::max(1, v.holdSamples + v.releaseSamples);
                            const float u = static_cast<float>(p) / static_cast<float>(total);
                            const float fc = (u < 0.54f)
                                ? (v.fcStart + (v.fcPeak - v.fcStart) * (u / 0.54f))
                                : (v.fcPeak + (v.fcStart * 0.92f - v.fcPeak) * ((u - 0.54f) / 0.46f));
                            v.lpf.setLowpass(fc, 0.56f);
                        }
                        x = v.lpf.step(x);
                    }
                    const float sig = x * env * v.amp * ambScale;
                    if (v.toDry > 0.001f) {
                        fgDryL += sig * v.panL * v.toDry;
                        fgDryR += sig * v.panR * v.toDry;
                    }
                    if (v.toAmbient > 0.001f) {
                        ambBusL += sig * v.panL * v.toAmbient;
                        ambBusR += sig * v.panR * v.toAmbient;
                    }
                    if (v.toShimmer > 0.001f) {
                        shimBusL += sig * v.panL * v.toShimmer;
                        shimBusR += sig * v.panR * v.toShimmer;
                    }
                    if (v.toEcho > 0.001f) {
                        echoIn += sig * v.toEcho;
                    }
                    v.samplePos++;
                }

                // --- C) Audible Ethereal Vocal Choir Formants ("Ooh" <-> "Aah") ---
                for (int ci = 0; ci < MAX_CHOIR_VOICES; ++ci) {
                    ChoirVoice& c = choirVoices_[ci];
                    if (!c.active) continue;
                    if (c.delaySamples > 0) {
                        c.delaySamples--;
                        continue;
                    }
                    const int total = c.holdSamples + c.releaseSamples;
                    if (c.samplePos >= total) {
                        c.active = false;
                        continue;
                    }
                    const int p = c.samplePos;
                    float env = (p < c.attackSamples)
                        ? (static_cast<float>(p) / static_cast<float>(c.attackSamples))
                        : (p < c.holdSamples
                            ? (1.0f - 0.20f * static_cast<float>(p - c.attackSamples) / static_cast<float>(std::max(1, c.holdSamples - c.attackSamples)))
                            : 0.80f * std::exp(-4.3f * static_cast<float>(p - c.holdSamples) / static_cast<float>(std::max(1, c.releaseSamples))));
                    c.vibPhase += c.vibInc;
                    if (c.vibPhase >= 1.0f) c.vibPhase -= 1.0f;
                    const float vib = sampleTable(WAVE_SINE, c.vibPhase) * 0.0022f;
                    c.phase += c.baseInc * (1.0f + vib);
                    if (c.phase >= 1.0f) c.phase -= 1.0f;

                    if ((p & 127) == 0) {
                        const float u = static_cast<float>(p) / static_cast<float>(total);
                        const float f1P = 340.0f + c.openAmt * 140.0f;
                        const float f2P = 720.0f + c.openAmt * 180.0f;
                        const float c1 = (u < 0.56f) ? (300.0f + (f1P - 300.0f) * (u / 0.56f)) : (f1P + (295.0f - f1P) * ((u - 0.56f) / 0.44f));
                        const float c2 = (u < 0.56f) ? (650.0f + (f2P - 650.0f) * (u / 0.56f)) : (f2P + (640.0f - f2P) * ((u - 0.56f) / 0.44f));
                        c.f1.setBandpass(c1, 1.15f);
                        c.f2.setBandpass(c2, 1.30f);
                    }
                    const float x = sampleTable(WAVE_VOCAL, c.phase);
                    const float sig = (c.f1.step(x) * 0.78f + c.f2.step(x) * 0.42f) * env * c.amp * ambScale;
                    ambBusL += sig * c.panL;
                    ambBusR += sig * c.panR;
                    c.samplePos++;
                }
            }

            // --- D) Organic Breath Air / Nebulae / Comets / Fly-To / UI Silk Swoosh ---
            const float white = nextNoise();
            pinkB0_ = 0.997f * pinkB0_ + white * 0.030f;
            pinkB1_ = 0.985f * pinkB1_ + white * 0.050f;
            pinkB2_ = 0.950f * pinkB2_ + white * 0.080f;
            const float pink = (pinkB0_ + pinkB1_ + pinkB2_) * 0.45f;

            for (int ni = 0; ni < MAX_NOISE_VOICES; ++ni) {
                NoiseVoice& nv = noiseVoices_[ni];
                if (!nv.active) continue;
                if (nv.delaySamples > 0) {
                    nv.delaySamples--;
                    continue;
                }
                if (nv.samplePos >= nv.totalSamples) {
                    nv.active = false;
                    continue;
                }
                const int p = nv.samplePos;
                const float u = static_cast<float>(p) / static_cast<float>(nv.totalSamples);
                float env = (p < nv.attackSamples)
                    ? (static_cast<float>(p) / static_cast<float>(nv.attackSamples))
                    : std::exp(-4.0f * static_cast<float>(p - nv.attackSamples) / static_cast<float>(std::max(1, nv.totalSamples - nv.attackSamples)));
                if ((p & 63) == 0) {
                    const float fc = (u < 0.5f)
                        ? (nv.fcStart * std::pow(nv.fcMid / std::max(40.0f, nv.fcStart), u * 2.0f))
                        : (nv.fcMid * std::pow(nv.fcEnd / std::max(40.0f, nv.fcMid), (u - 0.5f) * 2.0f));
                    nv.bp.setBandpass(fc, nv.q);
                }
                const float raw = nv.isPink ? pink : white;
                const float sig = nv.bp.step(raw) * env * nv.amp;
                if (nv.toDry > 0.001f) { fgDryL += sig * nv.panL * nv.toDry; fgDryR += sig * nv.panR * nv.toDry; }
                if (nv.toReverb > 0.001f) { fgWetL += sig * nv.panL * nv.toReverb; fgWetR += sig * nv.panR * nv.toReverb; }
                if (nv.toShimmer > 0.001f) {
                    const float sMul = (musicGainEnv_ > 0.001f ? musicGainEnv_ : 1.0f);
                    shimBusL += sig * nv.panL * nv.toShimmer * sMul;
                    shimBusR += sig * nv.panR * nv.toShimmer * sMul;
                }
                nv.samplePos++;
            }

            // --- E) Stereo Ping-Pong Tape Echo ---
            const float eFilt = echoLpf_.step(echoIn);
            const float eOutL = echoBufL_[echoIdxL_];
            const float eOutR = echoBufR_[echoIdxR_];
            echoBufL_[echoIdxL_] = eFilt + eOutR * 0.24f;
            echoBufR_[echoIdxR_] = eOutL * 0.92f;
            if (++echoIdxL_ >= ECHO_LEN_L) echoIdxL_ = 0;
            if (++echoIdxR_ >= ECHO_LEN_R) echoIdxR_ = 0;
            fgWetL += eOutL * 0.34f;
            fgWetR += eOutR * 0.34f;

            // --- F) Dedicated Ambient Warm Bus Filtering ---
            ambBusL = ambHighShelfL_.step(ambLpfL_.step(ambBusL));
            ambBusR = ambHighShelfR_.step(ambLpfR_.step(ambBusR));

            // --- G) 100%-Wet Modulated Shimmer Cloud Chorus Diffuser (Fractional Linear Interpolation — Zero Zipper Noise!) ---
            chorusLfoL_ += 0.17f / SR_F; if (chorusLfoL_ >= 1.0f) chorusLfoL_ -= 1.0f;
            chorusLfoR_ += 0.21f / SR_F; if (chorusLfoR_ >= 1.0f) chorusLfoR_ -= 1.0f;
            const float sFilL = shimLpfL_.step(shimBusL);
            const float sFilR = shimLpfR_.step(shimBusR);
            chorusBufL_[chorusIdx_] = sFilL;
            chorusBufR_[chorusIdx_] = sFilR;
            const float dLf = 1392.0f + sampleTable(WAVE_SINE, chorusLfoL_) * 165.0f;
            const float dRf = 2064.0f + sampleTable(WAVE_SINE, chorusLfoR_) * 190.0f;
            const int dLi = static_cast<int>(dLf);
            const int dRi = static_cast<int>(dRf);
            const float fracL = dLf - static_cast<float>(dLi);
            const float fracR = dRf - static_cast<float>(dRi);
            const int idxL0 = (chorusIdx_ - dLi + CHORUS_LEN) & (CHORUS_LEN - 1);
            const int idxL1 = (idxL0 - 1 + CHORUS_LEN) & (CHORUS_LEN - 1);
            const int idxR0 = (chorusIdx_ - dRi + CHORUS_LEN) & (CHORUS_LEN - 1);
            const int idxR1 = (idxR0 - 1 + CHORUS_LEN) & (CHORUS_LEN - 1);
            const float shDifL = chorusBufL_[idxL0] + (chorusBufL_[idxL1] - chorusBufL_[idxL0]) * fracL;
            const float shDifR = chorusBufR_[idxR0] + (chorusBufR_[idxR1] - chorusBufR_[idxR0]) * fracR;
            if (++chorusIdx_ >= CHORUS_LEN) chorusIdx_ = 0;

            // --- H) Velvet Diffused 4-Allpass + Modulated Householder FDN Cathedral Reverb (Zero Metallic Ringing!) ---
            float diffL = fgWetL * 0.62f + ambBusL * 0.85f + shDifL * 0.78f;
            float diffR = fgWetR * 0.62f + ambBusR * 0.85f + shDifR * 0.78f;
            static constexpr float AP_G[4] = {0.68f, 0.64f, 0.58f, 0.54f};
            for (int a = 0; a < 4; ++a) {
                const float g = AP_G[a];
                const float dlyL = apL_[a][apPosL_[a]];
                const float vL = diffL - g * dlyL;
                apL_[a][apPosL_[a]] = vL;
                diffL = dlyL + g * vL;
                if (++apPosL_[a] >= static_cast<int>(apL_[a].size())) apPosL_[a] = 0;

                const float dlyR = apR_[a][apPosR_[a]];
                const float vR = diffR - g * dlyR;
                apR_[a][apPosR_[a]] = vR;
                diffR = dlyR + g * vR;
                if (++apPosR_[a] >= static_cast<int>(apR_[a].size())) apPosR_[a] = 0;
            }

            // Modulated 4-line Householder Orthogonal FDN (energy-preserving, silky dark damping ~880 Hz)
            fdnLfo_ += 0.14f / SR_F; if (fdnLfo_ >= 1.0f) fdnLfo_ -= 1.0f;
            const float fdnMod = sampleTable(WAVE_SINE, fdnLfo_) * 14.0f;
            float rL[4], rR[4];
            float sumL = 0.0f, sumR = 0.0f;
            for (int k = 0; k < 4; ++k) {
                const int lenL = static_cast<int>(fdnL_[k].size());
                const int lenR = static_cast<int>(fdnR_[k].size());
                const float modOff = (k & 1) ? -fdnMod : fdnMod;
                const float baseOff = 20.0f + modOff;
                const int iOff = static_cast<int>(baseOff);
                const float frac = baseOff - static_cast<float>(iOff);

                const int rpL0 = (fdnPosL_[k] - iOff + lenL) % lenL;
                const int rpL1 = (rpL0 - 1 + lenL) % lenL;
                const float yL = fdnL_[k][rpL0] + (fdnL_[k][rpL1] - fdnL_[k][rpL0]) * frac;

                const int rpR0 = (fdnPosR_[k] - iOff + lenR) % lenR;
                const int rpR1 = (rpR0 - 1 + lenR) % lenR;
                const float yR = fdnR_[k][rpR0] + (fdnR_[k][rpR1] - fdnR_[k][rpR0]) * frac;

                // Dark velvet 1-pole damping (~880 Hz at 48kHz) + gentle DC blocker
                fdnLpL_[k] += 0.115f * (yL - fdnLpL_[k]);
                fdnLpR_[k] += 0.115f * (yR - fdnLpR_[k]);
                const float dcL = fdnLpL_[k] - fdnDcXL_[k] + 0.9982f * fdnDcYL_[k];
                fdnDcXL_[k] = fdnLpL_[k]; fdnDcYL_[k] = dcL;
                const float dcR = fdnLpR_[k] - fdnDcXR_[k] + 0.9982f * fdnDcYR_[k];
                fdnDcXR_[k] = fdnLpR_[k]; fdnDcYR_[k] = dcR;

                rL[k] = dcL;
                rR[k] = dcR;
                sumL += dcL;
                sumR += dcR;
            }
            const float halfSumL = 0.5f * sumL;
            const float halfSumR = 0.5f * sumR;
            float wL = 0.0f, wR = 0.0f;
            for (int k = 0; k < 4; ++k) {
                const float hL = rL[k] - halfSumL;
                const float hR = rR[k] - halfSumR;
                // Gentle stereo cross-bleed + strictly bounded feedback (<0.875)
                fdnL_[k][fdnPosL_[k]] = diffL * 0.28f + hL * 0.835f + hR * 0.042f;
                fdnR_[k][fdnPosR_[k]] = diffR * 0.28f + hR * 0.835f + hL * 0.042f;
                if (++fdnPosL_[k] >= static_cast<int>(fdnL_[k].size())) fdnPosL_[k] = 0;
                if (++fdnPosR_[k] >= static_cast<int>(fdnR_[k].size())) fdnPosR_[k] = 0;
                const float sign = (k & 1) ? -1.0f : 1.0f;
                wL += rL[k] * sign;
                wR += rR[k] * ((k < 2) ? 1.0f : -1.0f);
            }

            // --- I) Master Bus: Balanced Velvet Dry + Cathedral + Horizon + Speaker Warmth + Ear-Comfort LPF ---
            float mL = fgDryL * 0.88f + ambBusL * 0.72f + wL * 0.54f;
            float mR = fgDryR * 0.88f + ambBusR * 0.72f + wR * 0.54f;

            // Horizon underground warmth filter
            mL = subShelfL_.step(horizonLpfL_.step(mL));
            mR = subShelfR_.step(horizonLpfR_.step(mR));

            // Hardware Speaker vs Headphone Adaptation (Clean warm virtual bass, zero squared grit!)
            if (speakerMode_) {
                const float subMono = vbLpf_.step(0.5f * (mL + mR));
                const float sat = std::tanh(subMono * 1.45f) * 0.65f;
                const float vb = vbBpf_.step(sat) * 0.34f;
                mL = speakerHpfL_.step(mL) + vb;
                mR = speakerHpfR_.step(mR) + vb;
            }

            // Ear-Comfort High-Shelf + Silky Anti-Harshness LPF + Soft Velvet Limiter
            mL = masterLpfL_.step(comfortShelfL_.step(mL));
            mR = masterLpfR_.step(comfortShelfR_.step(mR));
            mL = std::tanh(mL * masterVolume_ * 2.15f) * 0.90f;
            mR = std::tanh(mR * masterVolume_ * 2.15f) * 0.90f;

            const float absMax = std::max(std::fabs(mL), std::fabs(mR));
            if (absMax > peakOut) peakOut = absMax;

            outInterleaved[i * 2] = static_cast<int16_t>(std::max(-32767.0f, std::min(32767.0f, mL * 32767.0f)));
            outInterleaved[i * 2 + 1] = static_cast<int16_t>(std::max(-32767.0f, std::min(32767.0f, mR * 32767.0f)));
        }

        return peakOut;
    }

private:
    std::mutex mu_;

    // Precomputed Wavetables (zero runtime sin/cos in hot oscillator loops!)
    std::array<float, TABLE_SIZE + 1> tblSine_{};
    std::array<float, TABLE_SIZE + 1> tblGlass_{};
    std::array<float, TABLE_SIZE + 1> tblCello_{};
    std::array<float, TABLE_SIZE + 1> tblVocal_{};
    std::array<float, TABLE_SIZE + 1> tblTri_{};

    // Master & DNA State
    bool musicEnabled_ = false;
    bool sfxEnabled_ = true;
    float masterVolume_ = 0.7f;
    bool guideDucked_ = false;
    bool speakerMode_ = false;
    bool lowPowerMode_ = false;
    float horizonAltDeg_ = 45.0f;

    std::string seedStr_ = "HarmonyOS-Stargazer-01";
    uint32_t seedNum_ = 1;
    int moodIdx_ = 0;
    int rootPc_ = 3; // Eb
    float a4Ref_ = 443.0f;
    float breathSec_ = 12.2f;
    float variation_ = 0.65f;
    int motifDegs_[4] = {1, 4, 2, 0};
    float wJade_ = 0.55f, wFelt_ = 0.45f, wTape_ = 0.25f, wBowl_ = 0.30f;

    // Conductor & Co-Composer State
    int ambientStep_ = 0;
    int samplesUntilNextBreath_ = 0;
    int idleSamples_ = 0;
    int recentUserMidi_ = 63;
    bool hasRecentUserMidi_ = false;
    float musicGainEnv_ = 0.0f;
    float sidechainDuck_ = 1.0f;
    float sidechainTarget_ = 1.0f;
    int sidechainHoldSamples_ = 0;
    uint64_t fgBirthSeq_ = 0;

    // Voice Pools
    std::array<ForegroundVoice, MAX_FG_VOICES> fgVoices_{};
    std::array<AmbientVoice, MAX_BG_VOICES> bgVoices_{};
    std::array<ChoirVoice, MAX_CHOIR_VOICES> choirVoices_{};
    std::array<NoiseVoice, MAX_NOISE_VOICES> noiseVoices_{};

    // RNG & Pink Noise Filter State
    uint32_t rng_ = 0x5A17C39Du;
    float pinkB0_ = 0.0f, pinkB1_ = 0.0f, pinkB2_ = 0.0f;

    // Velvet Diffused 4-Allpass + Modulated 4-Line Householder FDN Cathedral Reverb
    std::vector<float> apL_[4];
    std::vector<float> apR_[4];
    int apPosL_[4] = {};
    int apPosR_[4] = {};
    std::vector<float> fdnL_[4];
    std::vector<float> fdnR_[4];
    int fdnPosL_[4] = {};
    int fdnPosR_[4] = {};
    float fdnLpL_[4] = {};
    float fdnLpR_[4] = {};
    float fdnDcXL_[4] = {};
    float fdnDcYL_[4] = {};
    float fdnDcXR_[4] = {};
    float fdnDcYR_[4] = {};
    float fdnLfo_ = 0.0f;

    // Shimmer Stereo Chorus Diffuser
    static constexpr int CHORUS_LEN = 4096;
    std::vector<float> chorusBufL_;
    std::vector<float> chorusBufR_;
    int chorusIdx_ = 0;
    float chorusLfoL_ = 0.0f, chorusLfoR_ = 0.33f;

    // Stereo Ping-Pong Tape Echo
    static constexpr int ECHO_LEN_L = 12480; // 260ms @ 48kHz
    static constexpr int ECHO_LEN_R = 24960; // 520ms @ 48kHz
    std::vector<float> echoBufL_;
    std::vector<float> echoBufR_;
    int echoIdxL_ = 0, echoIdxR_ = 0;

    // Speaker Mono-Safe 11ms Haas Buffer
    static constexpr int HAAS_LEN = 528; // 11ms @ 48kHz
    std::vector<float> haasBuf_;
    int haasIdx_ = 0;

    // Master & Bus Biquads
    Biquad ambLpfL_, ambLpfR_, ambHighShelfL_, ambHighShelfR_;
    Biquad shimLpfL_, shimLpfR_, echoLpf_;
    Biquad horizonLpfL_, horizonLpfR_, subShelfL_, subShelfR_;
    Biquad speakerHpfL_, speakerHpfR_, vbLpf_, vbBpf_;
    Biquad comfortShelfL_, comfortShelfR_, masterLpfL_, masterLpfR_;

    void buildTables() {
        for (int i = 0; i <= TABLE_SIZE; ++i) {
            const float p = static_cast<float>(i) / static_cast<float>(TABLE_SIZE);
            const float w = TWO_PI_F * p;
            tblSine_[i] = std::sin(w);
            tblTri_[i] = (p < 0.5f) ? (4.0f * p - 1.0f) : (3.0f - 4.0f * p);
            // Silky warm acoustic partials (zero harsh upper metallic harmonics!)
            tblGlass_[i] = (std::sin(w) + 0.11f * std::sin(2.0f * w) + 0.025f * std::sin(3.0f * w)) * 0.88f;
            tblCello_[i] = (std::sin(w) + 0.42f * std::sin(2.0f * w) + 0.22f * std::sin(3.0f * w) +
                            0.08f * std::sin(4.0f * w) + 0.03f * std::sin(5.0f * w)) * 0.62f;
            tblVocal_[i] = (std::sin(w) + 0.48f * std::sin(2.0f * w) + 0.26f * std::sin(3.0f * w) +
                            0.12f * std::sin(4.0f * w) + 0.04f * std::sin(5.0f * w)) * 0.58f;
        }
    }

    void initReverbAndDelays() {
        constexpr int apLenL[4] = {149, 211, 383, 541};
        constexpr int apLenR[4] = {163, 229, 401, 563};
        constexpr int fdnLenL[4] = {3109, 3917, 4871, 5953};
        constexpr int fdnLenR[4] = {3163, 3967, 4931, 6011};
        for (int k = 0; k < 4; ++k) {
            apL_[k].assign(apLenL[k], 0.0f);
            apR_[k].assign(apLenR[k], 0.0f);
            fdnL_[k].assign(fdnLenL[k], 0.0f);
            fdnR_[k].assign(fdnLenR[k], 0.0f);
        }
        chorusBufL_.assign(CHORUS_LEN, 0.0f);
        chorusBufR_.assign(CHORUS_LEN, 0.0f);
        echoBufL_.assign(ECHO_LEN_L, 0.0f);
        echoBufR_.assign(ECHO_LEN_R, 0.0f);
        haasBuf_.assign(HAAS_LEN, 0.0f);

        ambLpfL_.setLowpass(1850.0f, 0.52f);
        ambLpfR_.setLowpass(1850.0f, 0.52f);
        ambHighShelfL_.setHighshelf(1250.0f, -3.2f);
        ambHighShelfR_.setHighshelf(1250.0f, -3.2f);
        shimLpfL_.setLowpass(1850.0f, 0.52f);
        shimLpfR_.setLowpass(1850.0f, 0.52f);
        echoLpf_.setLowpass(1650.0f, 0.56f);
        vbLpf_.setLowpass(145.0f, 0.70f);
        vbBpf_.setBandpass(210.0f, 0.85f);
    }

    void updateMasterFilters() {
        // Horizon underground warmth filter
        float cutoff = 16000.0f;
        float subGain = speakerMode_ ? 1.6f : 0.6f; // Subtle warm low-mid body
        if (horizonAltDeg_ < 0.0f) {
            const float u = (horizonAltDeg_ + 90.0f) / 90.0f;
            cutoff = 520.0f * std::pow(2100.0f / 520.0f, u);
            subGain += (1.0f - u) * 2.2f;
        } else if (horizonAltDeg_ < 25.0f) {
            const float u = horizonAltDeg_ / 25.0f;
            cutoff = 2100.0f * std::pow(14000.0f / 2100.0f, u);
        }
        horizonLpfL_.setLowpass(cutoff, 0.60f);
        horizonLpfR_.setLowpass(cutoff, 0.60f);
        subShelfL_.setLowshelf(210.0f, subGain);
        subShelfR_.setLowshelf(210.0f, subGain);

        // Speaker vs Headphone Comfort & Clarity Balance (silky highs without mud!)
        speakerHpfL_.setHighpass(speakerMode_ ? 75.0f : 22.0f, 0.68f);
        speakerHpfR_.setHighpass(speakerMode_ ? 75.0f : 22.0f, 0.68f);
        comfortShelfL_.setHighshelf(speakerMode_ ? 2100.0f : 2400.0f, speakerMode_ ? -4.5f : -2.6f);
        comfortShelfR_.setHighshelf(speakerMode_ ? 2100.0f : 2400.0f, speakerMode_ ? -4.5f : -2.6f);
        masterLpfL_.setLowpass(speakerMode_ ? 5400.0f : 7800.0f, 0.56f);
        masterLpfR_.setLowpass(speakerMode_ ? 5400.0f : 7800.0f, 0.56f);
    }

    inline float sampleTable(WaveKind w, float phase01) const {
        const float fidx = phase01 * static_cast<float>(TABLE_SIZE);
        const int i0 = static_cast<int>(fidx) & (TABLE_SIZE - 1);
        const float frac = fidx - static_cast<float>(static_cast<int>(fidx));
        const auto& tbl = (w == WAVE_SINE) ? tblSine_
                        : (w == WAVE_GLASS) ? tblGlass_
                        : (w == WAVE_CELLO) ? tblCello_
                        : (w == WAVE_VOCAL) ? tblVocal_
                        : tblTri_;
        return tbl[i0] + (tbl[i0 + 1] - tbl[i0]) * frac;
    }

    inline float nextRand01() {
        rng_ = rng_ * 1664525u + 1013904223u;
        return static_cast<float>(rng_ >> 8) / 16777216.0f;
    }

    inline float nextNoise() { return nextRand01() * 2.0f - 1.0f; }

    inline float jit(float scale) { return nextNoise() * variation_ * scale; }

    inline float midiHz(float midi, float a4, float cents) const {
        return a4 * std::pow(2.0f, (midi - 69.0f + cents / 100.0f) / 12.0f);
    }

    int findMoodIdx(const std::string& key) const {
        for (int i = 0; i < 5; ++i) {
            if (key == SKY_MOODS[i].key) return i;
        }
        return 0;
    }

    void resetIdleLocked() {
        idleSamples_ = 0;
        if (lowPowerMode_) {
            lowPowerMode_ = false;
        }
    }

    void triggerDuckLocked(float db) {
        if (!musicEnabled_) return;
        sidechainTarget_ = std::pow(10.0f, db / 20.0f);
        sidechainHoldSamples_ = SR * 36 / 100; // 360ms hold before smooth release
    }

    void applySeedInternal(const std::string& seed) {
        seedStr_ = seed.empty() ? "Aetheris" : seed;
        seedNum_ = fnv1aHash(seedStr_);
        uint32_t s = seedNum_;
        auto sr = [&s]() -> float {
            s = s * 1664525u + 1013904223u;
            return static_cast<float>(s >> 8) / 16777216.0f;
        };
        rootPc_ = static_cast<int>(sr() * 12.0f) % 12;
        moodIdx_ = static_cast<int>(sr() * 5.0f) % 5;
        a4Ref_ = 437.0f + sr() * 8.0f;
        breathSec_ = 9.0f + sr() * 2.0f;

        float raw[4] = {0.15f + sr() * sr(), 0.15f + sr() * sr(), 0.15f + sr() * sr(), 0.15f + sr() * sr()};
        int dom = static_cast<int>(sr() * 4.0f) % 4;
        raw[dom] += 0.65f;
        float mx = std::max(0.2f, std::max(std::max(raw[0], raw[1]), std::max(raw[2], raw[3])));
        wJade_ = std::min(1.0f, raw[0] / mx * 0.94f);
        wFelt_ = std::min(1.0f, raw[1] / mx * 0.94f);
        wTape_ = std::min(1.0f, raw[2] / mx * 0.90f);
        wBowl_ = std::min(1.0f, raw[3] / mx * 0.90f);
        deriveMotifFromSeed();
    }

    void deriveMotifFromSeed() {
        const int nDeg = SKY_MOODS[moodIdx_].numIntervals;
        uint32_t s = seedNum_ ^ 0x5A17C3u;
        auto sr = [&s]() -> float {
            s = s * 1664525u + 1013904223u;
            return static_cast<float>(s >> 8) / 16777216.0f;
        };
        const int shapes[5][4] = {
            {1, 0, std::min(nDeg - 1, 3), 2},
            {0, 2, std::min(nDeg - 1, 4), 1},
            {std::min(nDeg - 1, 4), 2, 1, 0},
            {2, std::min(nDeg - 1, 4), 1, 0},
            {0, std::min(nDeg - 1, 3), 2, std::min(nDeg - 1, 4)}
        };
        int si = static_cast<int>(sr() * 5.0f) % 5;
        for (int i = 0; i < 4; ++i) motifDegs_[i] = shapes[si][i];
        if (sr() > 0.45f) motifDegs_[2] = (motifDegs_[2] + 1) % nDeg;
    }

    void normMaterials(float& j, float& f, float& t, float& b) const {
        const float sum = wJade_ + wFelt_ + wTape_ + wBowl_;
        if (sum < 0.05f) { j = 0.4f; f = 0.4f; t = 0.1f; b = 0.1f; return; }
        j = wJade_ / sum; f = wFelt_ / sum; t = wTape_ / sum; b = wBowl_ / sum;
    }

    int scaleMidi(float norm01, int baseOctave, float spanOctaves) const {
        const SkyMoodDef& m = SKY_MOODS[moodIdx_];
        const int totalSteps = std::max(1, static_cast<int>(std::round(m.numIntervals * spanOctaves)));
        const int idx = std::max(0, std::min(totalSteps - 1, static_cast<int>(std::round(norm01 * (totalSteps - 1)))));
        const int oct = idx / m.numIntervals;
        const int deg = idx % m.numIntervals;
        return (baseOctave + 1) * 12 + rootPc_ + oct * 12 + m.intervals[deg];
    }

    ForegroundVoice& allocFgVoice() {
        for (auto& v : fgVoices_) {
            if (!v.active) {
                v = ForegroundVoice{};
                v.active = true;
                v.birthOrder = ++fgBirthSeq_;
                return v;
            }
        }
        // Smooth 40ms voice stealing of the oldest non-stealing voice!
        int oldestIdx = 0;
        uint64_t bestOrder = UINT64_MAX;
        for (int i = 0; i < MAX_FG_VOICES; ++i) {
            if (fgVoices_[i].birthOrder < bestOrder) {
                bestOrder = fgVoices_[i].birthOrder;
                oldestIdx = i;
            }
        }
        ForegroundVoice& stolen = fgVoices_[oldestIdx];
        stolen = ForegroundVoice{};
        stolen.active = true;
        stolen.birthOrder = ++fgBirthSeq_;
        return stolen;
    }

    AmbientVoice* allocBgVoice() {
        for (auto& v : bgVoices_) {
            if (!v.active) { v = AmbientVoice{}; v.active = true; return &v; }
        }
        return nullptr;
    }

    ChoirVoice* allocChoirVoice() {
        for (auto& v : choirVoices_) {
            if (!v.active) { v = ChoirVoice{}; v.active = true; return &v; }
        }
        return nullptr;
    }

    NoiseVoice* allocNoiseVoice() {
        for (auto& v : noiseVoices_) {
            if (!v.active) { v = NoiseVoice{}; v.active = true; return &v; }
        }
        return nullptr;
    }

    // =========================================================================
    // 4-MATERIAL MORPHING FOREGROUND VOICE (Jade + Felt + Tape + Bowl)
    // =========================================================================
    float spawnMorphedFgVoice(int delaySamples, int midi, float vel, float decaySec, float attackSec,
                              float brightHz, float wetSend, float pan, float shimmerBoost) {
        float wJ, wF, wT, wB;
        normMaterials(wJ, wF, wT, wB);
        // Sweet crystal-celesta register (cap <= MIDI 84 / C6 = 1046 Hz): crisp & luminous, never ear-piercing!
        int safeMidi = midi;
        while (safeMidi > 84) safeMidi -= 12;
        const float f0 = midiHz(static_cast<float>(safeMidi), a4Ref_, 6.0f + jit(4.0f));
        const float eqComp = (f0 > 660.0f) ? std::max(0.54f, std::pow(660.0f / f0, 0.45f)) : 1.0f;
        const float dec = std::max(0.24f, decaySec * (1.0f + jit(0.10f)));
        // Crisp 4–7ms celesta/dewdrop attack so stars feel jewel-like & clear (never muddy or sluggish!)
        const float atk = std::max(0.0045f, attackSec * (1.0f + jit(0.10f)));
        const float clampedPan = std::max(-0.85f, std::min(0.85f, pan + jit(0.06f)));

        ForegroundVoice& v = allocFgVoice();
        v.delaySamples = std::max(0, delaySamples);
        v.attackSamples = std::max(192, static_cast<int>(atk * SR_F));
        v.masterGain = vel * eqComp;
        v.drySend = (1.0f - wetSend * 0.46f) * 0.92f;
        v.wetSend = wetSend * 0.85f;
        v.shimmerSend = shimmerBoost * 0.34f;
        v.echoSend = (wT > 0.08f) ? (wT * 0.36f) : 0.14f;
        v.panL = std::cos((clampedPan + 1.0f) * 0.25f * PI_F);
        v.panR = std::sin((clampedPan + 1.0f) * 0.25f * PI_F);
        // Open silky clarity filter (up to 3200 Hz) so the brief attack sparkle shines clearly without mud!
        v.lpf.setLowpass(std::min(3200.0f, std::max(f0 * 2.6f, std::min(brightHz, 3200.0f))), 0.54f);

        int np = 0;
        auto addP = [&](float freq, float amp, float dSec, WaveKind wk) {
            if (np >= MAX_PARTIALS || freq > 3800.0f || amp < 0.01f) return;
            PartialState& ps = v.partials[np++];
            ps.phase = 0.0f;
            ps.phaseInc = freq / SR_F;
            ps.amp = amp;
            ps.env = 1.0f;
            ps.decayMul = std::exp(-4.6f / std::max(280.0f, dSec * SR_F));
            ps.wave = wk;
        };

        // Crisp-yet-silky physical modeling: pure luminous body + SHORT-DECAYING crystal sparkle transient!
        // Because the upper harmonics decay in 0.10-0.28s instead of sustaining, the strike is crisp & jewel-like
        // while the ring-out stays 100% warm velvet — ZERO ear fatigue!
        const float beatHz = (wB > 0.2f) ? (1.8f + nextRand01() * 1.4f) : 0.32f;
        const float detuneMul = std::pow(2.0f, (wT * 5.0f + 1.6f) / 1200.0f);
        WaveKind bodyWave = (wT > 0.45f) ? WAVE_CELLO : WAVE_GLASS;
        addP(f0, 0.72f, dec * 1.12f, bodyWave);
        addP(f0 * detuneMul + beatHz * wB, 0.30f, dec * 0.95f, WAVE_SINE);
        // Crisp bell/celesta octave kiss (fast 0.16-0.38s decay = sparkle on impact, warmth on sustain!)
        if (f0 * 2.0f <= 3100.0f) {
            addP(f0 * 2.0f, 0.26f + 0.10f * wF, std::min(0.45f, dec * 0.22f), WAVE_SINE);
        }
        // Subtle 3rd harmonic / Jade 2.312x dewdrop attack shimmer (ultra-short 0.09-0.16s kiss!)
        if (wJ > 0.10f && f0 * 2.312f <= 3200.0f) {
            addP(f0 * 2.312f, 0.16f * wJ, std::min(0.18f, dec * 0.10f), WAVE_SINE);
        } else if (f0 * 3.0f <= 3300.0f) {
            addP(f0 * 3.0f, 0.11f, std::min(0.13f, dec * 0.08f), WAVE_SINE);
        }
        // Gentle sub-octave warmth only for brighter notes so they never feel thin
        if (f0 > 460.0f) {
            addP(f0 * 0.5f, 0.14f, dec * 0.85f, WAVE_SINE);
        }
        if (wB > 0.18f && shimmerBoost > 0.05f && f0 * 2.0f <= 2400.0f) {
            addP(f0 * 2.004f, 0.12f * wB * shimmerBoost, dec * 0.85f, WAVE_SINE);
        }
        v.numPartials = np;
        return f0;
    }

    // =========================================================================
    // CELESTIAL & SCENARIO TRIGGERS (100% 53-Slot + 5-Scenario Parity!)
    // =========================================================================
    void triggerStarUnlocked(float tempK, float mag, float distLy, float pan, float altitude) {
        triggerDuckLocked(-1.8f);
        const float tk = std::max(2600.0f, std::min(36000.0f, tempK));
        const float tNorm = (std::log(tk) - std::log(2600.0f)) / (std::log(36000.0f) - std::log(2600.0f));
        // Jewel-like celesta register: Red M-stars warm G3-C4 (200-260Hz), Blue O/B-stars crisp G5-C6 (784-1046Hz)!
        const int midi = scaleMidi(tNorm, 4, 1.75f);
        const float mNorm = std::max(0.0f, std::min(1.0f, (6.0f - mag) / 7.5f));
        const float vel = 0.15f + mNorm * 0.17f;
        // Crisp 4.5-18ms starlight attack (bright stars = crisp crystal dewdrop, faint stars = soft glimmer)
        const float atk = 0.0045f + (1.0f - mNorm) * 0.022f;
        const float dNorm = (std::log(std::max(4.0f, distLy)) - std::log(4.0f)) / (std::log(3000.0f) - std::log(4.0f));
        recentUserMidi_ = midi;
        hasRecentUserMidi_ = true;
        spawnMorphedFgVoice(0, midi, vel, 2.4f + dNorm * 2.2f, atk, 1850.0f + tNorm * 1150.0f + altitude * 250.0f,
                            0.44f + dNorm * 0.38f, pan, 0.28f + dNorm * 0.34f);
    }

    void triggerPlanetLocked(bool isGas, int tier, float pan) {
        triggerDuckLocked(-2.2f);
        const float norm = (1.0f - static_cast<float>(tier - 1) / 4.2f) * 0.68f + 0.10f;
        const int midi = scaleMidi(norm, isGas ? 2 : 3, 1.3f);
        recentUserMidi_ = midi;
        hasRecentUserMidi_ = true;

        // 1) Warm planetary core strike
        const float f0 = spawnMorphedFgVoice(0, midi, isGas ? 0.24f : 0.20f, isGas ? 3.8f : 2.5f,
                                             isGas ? 0.032f : 0.016f, isGas ? 1050.0f : 1450.0f,
                                             isGas ? 0.68f : 0.56f, pan, 0.0f);
        // 2) Sub-octave planetary gravity anchor
        spawnMorphedFgVoice(0, midi - 12, isGas ? 0.20f : 0.12f, isGas ? 3.6f : 1.8f,
                            isGas ? 0.042f : 0.020f, 680.0f, 0.50f, pan * 0.45f, 0.0f);
        // 3) Soft delayed velvet shimmer blooms (+210ms & +430ms -> Shimmer Cloud!)
        const float tapDelays[2] = {0.21f, 0.43f};
        const float tapMults[2]  = {2.006f, isGas ? 1.498f : 1.995f};
        const float tapPans[2]   = {-0.35f, +0.38f};
        for (int t = 0; t < 2; ++t) {
            const float freq = f0 * tapMults[t];
            if (freq > 1350.0f) continue;
            ForegroundVoice& sv = allocFgVoice();
            sv.delaySamples = static_cast<int>(tapDelays[t] * SR_F);
            sv.attackSamples = static_cast<int>(0.34f * SR_F);
            sv.masterGain = isGas ? 0.095f : 0.072f;
            sv.drySend = 0.06f;
            sv.wetSend = 0.28f;
            sv.shimmerSend = 0.85f;
            const float sp = std::max(-0.85f, std::min(0.85f, pan + tapPans[t]));
            sv.panL = std::cos((sp + 1.0f) * 0.25f * PI_F);
            sv.panR = std::sin((sp + 1.0f) * 0.25f * PI_F);
            sv.lpf.setLowpass(1350.0f, 0.55f);
            sv.numPartials = 1;
            sv.partials[0] = {0.0f, freq / SR_F, 1.0f, std::exp(-4.6f / ((isGas ? 4.2f : 2.9f) * SR_F)), 1.0f, WAVE_SINE};
        }
    }

    void triggerSunLocked(float pan) {
        triggerDuckLocked(-2.8f);
        const int rootM = 48 + rootPc_;
        const int chord[5] = {rootM - 12, rootM, rootM + 7, rootM + 12, rootM + 19};
        recentUserMidi_ = rootM + 12;
        hasRecentUserMidi_ = true;
        for (int i = 0; i < 5; ++i) {
            spawnMorphedFgVoice(static_cast<int>(i * 0.032f * SR_F), chord[i],
                                i == 0 ? 0.22f : (0.19f - i * 0.015f), 4.8f + i * 0.25f,
                                0.14f + i * 0.04f, 1850.0f, 0.78f,
                                std::max(-0.75f, std::min(0.75f, pan + (i - 2) * 0.22f)), 0.65f);
        }
        if (auto* nv = allocNoiseVoice()) {
            nv->attackSamples = static_cast<int>(0.65f * SR_F);
            nv->totalSamples = static_cast<int>(4.0f * SR_F);
            nv->amp = 0.095f;
            nv->fcStart = 340.0f; nv->fcMid = 860.0f; nv->fcEnd = 420.0f; nv->q = 1.6f;
            nv->toReverb = 1.0f; nv->isPink = true;
        }
    }

    void triggerConstellationPresetLocked(int idx, float pan) {
        triggerDuckLocked(-2.2f);
        const SkyMoodDef& m = SKY_MOODS[moodIdx_];
        const int base = 60 + rootPc_;
        struct CP { int len; int degs[4]; int octs[4]; float step; float atk; };
        static const CP presets[15] = {
            {2, {0,0,0,0}, {0,1,0,0}, 0.04f, 0.04f},
            {3, {0,3,0,0}, {0,0,1,0}, 0.06f, 0.05f},
            {3, {0,2,0,0}, {0,0,1,0}, 0.08f, 0.14f},
            {4, {0,2,4,0}, {0,0,0,1}, 0.09f, 0.04f},
            {4, {0,3,0,1}, {0,0,1,1}, 0.07f, 0.03f},
            {4, {3,0,2,0}, {-1,0,0,1}, 0.15f, 0.05f},
            {4, {3,0,2,0}, {-1,0,0,1}, 0.03f, 0.03f},
            {4, {0,2,4,4}, {0,0,0,1}, 0.08f, 0.04f},
            {4, {0,2,3,0}, {0,0,0,1}, 0.09f, 0.08f},
            {4, {0,3,0,1}, {0,0,1,1}, 0.13f, 0.09f},
            {4, {3,0,2,3}, {-1,0,0,0}, 0.06f, 0.04f},
            {4, {3,0,2,0}, {-1,0,0,1}, 0.11f, 0.07f},
            {4, {3,0,1,3}, {-1,0,0,0}, 0.13f, 0.05f},
            {3, {0,2,4,0}, {0,0,0,0}, 0.05f, 0.04f},
            {4, {0,3,0,1}, {0,0,1,1}, 0.05f, 0.02f}
        };
        const CP& p = presets[((idx % 15) + 15) % 15];
        for (int i = 0; i < p.len; ++i) {
            const int midi = base + m.intervals[p.degs[i] % m.numIntervals] + p.octs[i] * 12;
            if (i == 0) { recentUserMidi_ = midi; hasRecentUserMidi_ = true; }
            const float nPan = std::max(-0.85f, std::min(0.85f, pan + (static_cast<float>(i) / std::max(1, p.len - 1) - 0.5f) * 0.85f));
            spawnMorphedFgVoice(static_cast<int>(i * p.step * SR_F), midi,
                                0.21f / std::sqrt(static_cast<float>(p.len) * 0.52f),
                                4.4f + i * 0.22f, p.atk, 2150.0f, 0.80f, nPan, 0.55f);
        }
    }

    void triggerNebulaLocked(float pan, bool isPlanetary) {
        triggerDuckLocked(-1.5f);
        const int midi = scaleMidi(isPlanetary ? 0.35f : 0.10f, 3, 1.0f);
        const float f0 = spawnMorphedFgVoice(0, midi, 0.26f, 4.8f, 0.45f, 1100.0f, 0.88f, pan, 0.35f);
        if (auto* nv = allocNoiseVoice()) {
            nv->attackSamples = static_cast<int>(0.70f * SR_F);
            nv->totalSamples = static_cast<int>(4.3f * SR_F);
            nv->amp = 0.11f;
            nv->fcStart = isPlanetary ? f0 * 2.0f : 950.0f;
            nv->fcMid   = isPlanetary ? f0 * 2.05f : 1250.0f;
            nv->fcEnd   = isPlanetary ? f0 * 1.95f : 880.0f;
            nv->q = isPlanetary ? 4.0f : 2.0f;
            nv->panL = std::cos((pan + 1.0f) * 0.25f * PI_F);
            nv->panR = std::sin((pan + 1.0f) * 0.25f * PI_F);
            nv->toReverb = 1.0f; nv->isPink = true;
        }
    }

    void triggerClusterLocked(float pan, bool isGlobular) {
        triggerDuckLocked(-1.8f);
        constexpr int count = 10;
        for (int i = 0; i < count; ++i) {
            const float dt = isGlobular
                ? (nextRand01() * 0.34f)
                : (std::pow(static_cast<float>(i) / count, 1.25f) * 1.35f + nextRand01() * 0.06f);
            const int midi = scaleMidi(0.25f + nextRand01() * 0.65f, isGlobular ? 3 : 4, 1.4f);
            const float nPan = std::max(-0.85f, std::min(0.85f, pan + (nextRand01() - 0.5f) * 1.2f));
            spawnMorphedFgVoice(static_cast<int>(dt * SR_F), midi, isGlobular ? 0.082f : 0.070f,
                                (isGlobular ? 2.2f : 1.4f) + nextRand01() * 0.5f,
                                isGlobular ? 0.022f : 0.015f, 1450.0f, 0.84f, nPan, isGlobular ? 0.28f : 0.0f);
        }
    }

    void triggerCometLocked(float pan) {
        const int midi = scaleMidi(0.55f + nextRand01() * 0.25f, 3, 1.4f);
        if (auto* nv = allocNoiseVoice()) {
            nv->attackSamples = static_cast<int>(0.18f * SR_F);
            nv->totalSamples = static_cast<int>(1.9f * SR_F);
            nv->amp = 0.085f;
            nv->fcStart = 420.0f; nv->fcMid = 1250.0f; nv->fcEnd = 520.0f; nv->q = 1.4f;
            nv->toReverb = 1.0f; nv->isPink = true;
        }
        const float dts[4] = {0.0f, 0.11f, 0.26f, 0.48f};
        for (int i = 0; i < 4; ++i) {
            spawnMorphedFgVoice(static_cast<int>(dts[i] * SR_F), midi + (i == 2 ? 12 : 0),
                                0.15f * std::pow(0.75f, static_cast<float>(i)), 1.6f + i * 0.45f,
                                0.018f, 1450.0f, 0.78f,
                                std::max(-0.85f, std::min(0.85f, pan + (i - 1.5f) * 0.3f)), 0.42f);
        }
    }

    // Original Orbital Spacecraft / Space Station Acoustic Signature ("轨镜微澜 · Optical Downlink & Solar-Wing Glide")
    // Completely original & distinct from legacy FSK radio beeps — crystal-clear, airy, futuristic, zero mud!
    // variant 0 = ISS (Spatial glass-radar orbital transponder + sunlit fly-by)
    // variant 1 = Tiangong (Pentatonic Celestial-Palace optical laser lock + orbital hull fifth)
    // variant 2 = Satellite (4-pulse accelerating optical inter-satellite laser glimmer panning across sky)
    void triggerSatelliteLocked(float pan, int variant) {
        triggerDuckLocked(-1.8f);
        const int vType = ((variant % 3) + 3) % 3;
        const int rootM = 60 + rootPc_; // C4..B4 warm reference

        // 1) Silky Sunlit Solar-Wing Orbital Glide Whoosh (clean airy pass-by, never muddy!)
        if (auto* nv = allocNoiseVoice()) {
            nv->attackSamples = static_cast<int>(0.22f * SR_F);
            nv->totalSamples = static_cast<int>((vType == 2 ? 0.72f : 1.15f) * SR_F);
            nv->amp = (vType == 2) ? 0.065f : 0.085f;
            nv->fcStart = 540.0f;
            nv->fcMid   = (vType == 1) ? 1650.0f : 1900.0f;
            nv->fcEnd   = 680.0f;
            nv->q = 1.6f;
            const float np = std::max(-0.8f, std::min(0.8f, pan));
            nv->panL = std::cos((np + 1.0f) * 0.25f * PI_F);
            nv->panR = std::sin((np + 1.0f) * 0.25f * PI_F);
            nv->toDry = 0.45f;
            nv->toReverb = 0.65f;
            nv->isPink = true;
        }

        auto spawnCrystalPulse = [&](float delaySec, float freqHz, float glideEndRatio, float glideDurSec,
                                     float gain, float decaySec, float pulsePan, float echoSend) {
            ForegroundVoice& v = allocFgVoice();
            v.delaySamples = static_cast<int>(delaySec * SR_F);
            v.attackSamples = static_cast<int>(0.007f * SR_F); // Crisp 7ms optical-crystal articulation
            v.masterGain = gain;
            v.drySend = 0.72f;
            v.wetSend = 0.48f;
            v.shimmerSend = 0.28f;
            v.echoSend = echoSend;
            const float cp = std::max(-0.85f, std::min(0.85f, pulsePan));
            v.panL = std::cos((cp + 1.0f) * 0.25f * PI_F);
            v.panR = std::sin((cp + 1.0f) * 0.25f * PI_F);
            v.pitchGlide = (std::fabs(glideEndRatio - 1.0f) > 0.001f);
            v.glideStartMul = 1.0f;
            v.glideEndMul = glideEndRatio;
            v.glideSamples = std::max(480, static_cast<int>(glideDurSec * SR_F));
            // Open, transparent filter (2800-3400 Hz) so satellites sound bright & crystal-clear, never muffled!
            v.lpf.setLowpass(3200.0f, 0.55f);
            v.numPartials = 3;
            // Clean crystal fundamental + delicate octave glint + subtle sub-harmonic warmth
            v.partials[0] = {0.0f, freqHz / SR_F, 0.78f, std::exp(-4.6f / (decaySec * SR_F)), 1.0f, WAVE_GLASS};
            v.partials[1] = {0.0f, std::min(3400.0f, freqHz * 2.0f) / SR_F, 0.22f, std::exp(-4.6f / (decaySec * 0.35f * SR_F)), 1.0f, WAVE_SINE};
            v.partials[2] = {0.0f, (freqHz * 0.5f) / SR_F, 0.18f, std::exp(-4.6f / (decaySec * 0.85f * SR_F)), 1.0f, WAVE_SINE};
        };

        if (vType == 1) {
            // === TIANGONG SPACE STATION (天宫空间站): Pentatonic Celestial-Palace Optical Lock ===
            // Warm orbital hull 5th bed + translucent 3-note optical laser chord (G5 -> D6 -> A5) with subtle Doppler drift
            const float fHull = midiHz(static_cast<float>(rootM - 5), a4Ref_, 0.0f);
            spawnCrystalPulse(0.0f, fHull, 0.992f, 1.4f, 0.14f, 1.8f, pan * 0.4f, 0.15f);
            const int degs[3] = {7, 14, 9}; // Perfect 5th -> Major 9th -> Major 6th (oriental sky-palace harmony)
            const float dts[3] = {0.02f, 0.135f, 0.285f};
            const float pans[3] = {-0.45f, 0.05f, +0.48f};
            for (int i = 0; i < 3; ++i) {
                const float f = std::min(1580.0f, midiHz(static_cast<float>(rootM + degs[i] + 5), a4Ref_, 0.0f));
                spawnCrystalPulse(dts[i], f, 0.986f, 0.75f, i == 1 ? 0.19f : 0.15f,
                                  i == 2 ? 1.55f : 0.65f, pan * 0.4f + pans[i], 0.55f);
            }
        } else if (vType == 0) {
            // === ISS (国际空间站): Modern Avionics Optical Transponder + Stereo Orbital Arc ===
            // Crisp ascending harmonic 4th/octave lock + Doppler gliding harmonic tail
            const float f1 = std::min(1150.0f, midiHz(static_cast<float>(rootM + 7), a4Ref_, 0.0f));
            const float f2 = std::min(1540.0f, midiHz(static_cast<float>(rootM + 12), a4Ref_, 0.0f));
            const float f3 = std::min(1400.0f, midiHz(static_cast<float>(rootM + 14), a4Ref_, 0.0f));
            spawnCrystalPulse(0.00f, f1, 1.015f, 0.18f, 0.16f, 0.42f, pan - 0.38f, 0.45f);
            spawnCrystalPulse(0.14f, f2, 0.985f, 0.65f, 0.19f, 0.85f, pan + 0.08f, 0.62f);
            spawnCrystalPulse(0.32f, f3, 0.978f, 0.90f, 0.14f, 1.35f, pan + 0.44f, 0.58f);
        } else {
            // === ORBITAL SATELLITE (人造卫星): 4-Pulse Optical Laser Inter-Satellite Glimmer ===
            // Accelerating crystalline telemetry sparkles panning across the stereo sky with subtle Doppler drop!
            const int semi[4] = {12, 16, 19, 14};
            const float dts[4] = {0.00f, 0.115f, 0.215f, 0.305f};
            const float gns[4] = {0.15f, 0.17f, 0.18f, 0.13f};
            const float dcs[4] = {0.26f, 0.24f, 0.48f, 0.95f};
            for (int i = 0; i < 4; ++i) {
                const float f = std::min(1680.0f, midiHz(static_cast<float>(rootM + semi[i]), a4Ref_, 0.0f));
                const float flyPan = std::max(-0.82f, std::min(0.82f, pan + (-0.52f + i * 0.36f)));
                spawnCrystalPulse(dts[i], f, 0.980f, 0.35f, gns[i], dcs[i], flyPan, 0.60f);
            }
        }
    }

    void triggerBandLocked(bool isXray) {
        const float spd = isXray ? 1.75f : 1.0f;
        const float f0 = std::min(920.0f, midiHz(static_cast<float>(scaleMidi(isXray ? 0.78f : 0.38f, 4, 0.9f)), a4Ref_, 0.0f));
        for (int pulse = 0; pulse < 2; ++pulse) {
            ForegroundVoice& v = allocFgVoice();
            v.delaySamples = static_cast<int>((pulse == 0 ? 0.0f : (0.12f / spd)) * SR_F);
            v.attackSamples = static_cast<int>((0.024f / spd) * SR_F);
            v.masterGain = (pulse == 0 ? 0.12f : 0.068f);
            v.drySend = 0.75f; v.wetSend = 0.30f;
            v.panL = 1.0f; v.panR = 1.0f;
            v.antiphaseR = !speakerMode_;
            v.haasRight = speakerMode_;
            v.lpf.setLowpass(1600.0f, 0.6f);
            v.numPartials = 1;
            v.partials[0] = {0.0f, f0 / SR_F, 1.0f, std::exp(-4.6f / ((0.18f / spd) * SR_F)), 1.0f, WAVE_SINE};
        }
    }

    void triggerFlyToLocked(float pan, bool isZoomOut) {
        triggerDuckLocked(-2.6f);
        if (auto* nv = allocNoiseVoice()) {
            nv->attackSamples = static_cast<int>(0.68f * SR_F);
            nv->totalSamples = static_cast<int>(1.82f * SR_F);
            nv->amp = 0.11f;
            nv->fcStart = isZoomOut ? 880.0f : 220.0f;
            nv->fcMid   = isZoomOut ? 480.0f : 940.0f;
            nv->fcEnd   = isZoomOut ? 220.0f : 360.0f;
            nv->q = 1.5f;
            nv->toReverb = 1.0f; nv->isPink = true;
        }
        const float norms[3] = {isZoomOut ? 0.62f : 0.15f, 0.42f, isZoomOut ? 0.10f : 0.72f};
        for (int i = 0; i < 3; ++i) {
            const int m = scaleMidi(norms[i], 3, 1.5f);
            spawnMorphedFgVoice(static_cast<int>((0.92f + i * 0.085f) * SR_F), m, 0.17f, 3.8f, 0.045f,
                                1450.0f, 0.82f, std::max(-0.8f, std::min(0.8f, pan + (i - 1) * 0.35f)), 0.55f);
        }
    }

    void triggerAudioLogoLocked() {
        triggerDuckLocked(-2.2f);
        const SkyMoodDef& m = SKY_MOODS[moodIdx_];
        const float times[4] = {0.0f, 0.26f, 0.54f, 0.86f};
        const int octs[4] = {3, 3, 3, 4};
        const float pans[4] = {-0.42f, -0.14f, +0.18f, +0.44f};
        for (int i = 0; i < 4; ++i) {
            const int midi = (octs[i] + 1) * 12 + rootPc_ + m.intervals[motifDegs_[i] % m.numIntervals];
            spawnMorphedFgVoice(static_cast<int>(times[i] * SR_F), midi, i == 3 ? 0.21f : 0.17f,
                                i == 3 ? 4.8f : 3.0f, 0.022f, 1500.0f, 0.78f, pans[i], i == 3 ? 0.65f : 0.30f);
        }
        spawnMorphedFgVoice(static_cast<int>(0.86f * SR_F), 36 + rootPc_, 0.16f, 4.5f, 0.085f, 820.0f, 0.75f, 0.0f, 0.0f);
    }

    void triggerUiLocked(const std::string& cue) {
        if (cue == "wheel_tick" || cue == "loupe_blip" || cue == "ui-loupe-blip" || cue == "ui-dial") {
            ForegroundVoice& v = allocFgVoice();
            v.attackSamples = 180;
            v.masterGain = 0.095f;
            v.drySend = 0.82f; v.wetSend = 0.18f;
            v.pitchGlide = true; v.glideStartMul = 1.0f; v.glideEndMul = 0.38f; v.glideSamples = static_cast<int>(0.026f * SR_F);
            v.lpf.setLowpass(1400.0f, 0.6f);
            v.numPartials = 1;
            const float f0 = 680.0f * (1.0f + jit(0.05f));
            v.partials[0] = {0.0f, f0 / SR_F, 0.90f, std::exp(-4.6f / (0.042f * SR_F)), 1.0f, WAVE_SINE};
            return;
        }
        if (cue == "panel_open" || cue == "ui-info-open" || cue == "panel_close" || cue == "ui-info-close") {
            const bool isOpen = (cue == "panel_open" || cue == "ui-info-open");
            if (auto* nv = allocNoiseVoice()) {
                nv->attackSamples = static_cast<int>((isOpen ? 0.14f : 0.06f) * SR_F);
                nv->totalSamples = static_cast<int>(0.26f * SR_F);
                nv->amp = 0.11f;
                nv->fcStart = isOpen ? 380.0f : 1450.0f;
                nv->fcMid   = 880.0f;
                nv->fcEnd   = isOpen ? 1450.0f : 380.0f;
                nv->q = 1.4f; nv->toDry = 0.65f; nv->toReverb = 0.40f; nv->isPink = true;
            }
            return;
        }
        if (cue == "loupe_open" || cue == "ui-loupe-open") {
            const float fEnd = midiHz(static_cast<float>(55 + rootPc_), a4Ref_, 0.0f);
            ForegroundVoice& v = allocFgVoice();
            v.attackSamples = static_cast<int>(0.08f * SR_F);
            v.masterGain = 0.14f; v.drySend = 0.68f; v.wetSend = 0.50f;
            v.pitchGlide = true; v.glideStartMul = 0.42f; v.glideEndMul = 1.0f; v.glideSamples = static_cast<int>(0.22f * SR_F);
            v.lpf.setLowpass(1450.0f, 0.6f);
            v.numPartials = 1;
            v.partials[0] = {0.0f, fEnd / SR_F, 1.0f, std::exp(-4.6f / (0.50f * SR_F)), 1.0f, WAVE_SINE};
            return;
        }
        if (cue == "loupe_close" || cue == "ui-loupe-close") {
            const float fStart = midiHz(static_cast<float>(60 + rootPc_), a4Ref_, 0.0f);
            ForegroundVoice& v = allocFgVoice();
            v.attackSamples = static_cast<int>(0.035f * SR_F);
            v.masterGain = 0.12f; v.drySend = 0.70f; v.wetSend = 0.35f;
            v.pitchGlide = true; v.glideStartMul = 1.0f; v.glideEndMul = 0.48f; v.glideSamples = static_cast<int>(0.28f * SR_F);
            v.lpf.setLowpass(1400.0f, 0.6f);
            v.numPartials = 1;
            v.partials[0] = {0.0f, fStart / SR_F, 1.0f, std::exp(-4.6f / (0.36f * SR_F)), 1.0f, WAVE_SINE};
            return;
        }
        if (cue == "loupe_fullscreen" || cue == "ui-loupe-full") {
            if (auto* nv = allocNoiseVoice()) {
                nv->attackSamples = static_cast<int>(0.26f * SR_F);
                nv->totalSamples = static_cast<int>(0.34f * SR_F);
                nv->amp = 0.12f; nv->fcStart = 340.0f; nv->fcMid = 960.0f; nv->fcEnd = 1450.0f;
                nv->q = 1.5f; nv->toDry = 0.65f; nv->toReverb = 0.45f; nv->isPink = true;
            }
            const SkyMoodDef& m = SKY_MOODS[moodIdx_];
            const int degs[3] = {0, 2, 3};
            for (int i = 0; i < 3; ++i) {
                const int midi = 60 + rootPc_ + m.intervals[degs[i] % m.numIntervals];
                spawnMorphedFgVoice(static_cast<int>((0.29f + i * 0.025f) * SR_F), midi, 0.13f, 1.5f, 0.018f,
                                    1450.0f, 0.68f, (i - 1) * 0.35f, 0.35f);
            }
            return;
        }
        if (cue == "shatter" || cue == "ui-shatter") {
            triggerDuckLocked(-2.4f);
            const SkyMoodDef& m = SKY_MOODS[moodIdx_];
            for (int i = 0; i < 4; ++i) {
                const int midi = 52 + rootPc_ + m.intervals[i % m.numIntervals] + (i == 3 ? 12 : 0);
                spawnMorphedFgVoice(static_cast<int>((0.05f + i * 0.04f) * SR_F), midi, 0.13f, 4.6f, 0.08f,
                                    1400.0f, 0.88f, (i - 1.5f) * 0.35f, 0.55f);
            }
            return;
        }
        if (cue == "multiselect" || cue == "ui-multiselect") {
            if (auto* nv = allocNoiseVoice()) {
                nv->attackSamples = 480; nv->totalSamples = static_cast<int>(0.09f * SR_F);
                nv->amp = 0.075f; nv->fcStart = 1800.0f; nv->fcMid = 2200.0f; nv->fcEnd = 2400.0f;
                nv->q = 3.2f; nv->toDry = 0.70f; nv->toReverb = 0.30f; nv->isPink = true;
            }
            return;
        }
        // target_lock / confirm / toggle / deselect — warm soft felt-marimba drop, ZERO sharp beep!
        const bool isRelease = (cue == "deselect" || cue == "ui-check-off" || cue == "ui-release");
        const int midi = scaleMidi(isRelease ? 0.22f : (cue == "toggle" ? 0.45f : 0.65f), 3, 1.0f);
        spawnMorphedFgVoice(0, midi, isRelease ? 0.10f : 0.14f, isRelease ? 0.32f : 0.40f, 0.014f,
                            isRelease ? 980.0f : 1220.0f, 0.42f, 0.0f, 0.0f);
    }

    // =========================================================================
    // AETHERIS v4 LIQUID-CATHEDRAL AMBIENT CONDUCTOR
    // =========================================================================
    void scheduleAmbientBreathLocked() {
        const SkyMoodDef& mood = SKY_MOODS[moodIdx_];
        const int step = ambientStep_++;
        const NarrativeScene& arc = NARRATIVE_ARC[step % 8];
        const MoodChordSpec& spec = mood.chords[step % 8];

        const float dur = lowPowerMode_ ? (breathSec_ * 1.35f) : (breathSec_ * arc.durMul);
        const int atkS = static_cast<int>(4.4f * SR_F);
        const int holdS = static_cast<int>(dur * SR_F);
        const int relS = static_cast<int>(5.4f * SR_F);

        const int baseMidi = 48 + rootPc_ - (rootPc_ > 7 ? 12 : 0);
        int chord[7];
        int chordLen = spec.count;
        for (int i = 0; i < chordLen; ++i) chord[i] = baseMidi + spec.notes[i];

        // Adaptive Co-Composer: adopt user's recently selected star into upper halo if consonant!
        if (!lowPowerMode_ && hasRecentUserMidi_ && chordLen >= 3 && chordLen < 7) {
            const int pc = ((recentUserMidi_ % 12) + 12) % 12;
            const int cand = 72 + pc;
            bool clash = false;
            for (int i = 0; i < chordLen; ++i) {
                const int d = std::abs(cand - chord[i]) % 12;
                if (d == 0 || d == 1 || d == 11) { clash = true; break; }
            }
            if (!clash) chord[chordLen++] = cand;
        }

        // Low-Power Meditation Mode: only 2 pure warm voices (~75% less CPU!)
        if (lowPowerMode_) {
            for (int i = 0; i < std::min(2, chordLen); ++i) {
                if (auto* v = allocBgVoice()) {
                    const float f = midiHz(static_cast<float>(chord[i]), a4Ref_ - 1.5f, -4.0f);
                    v->attackSamples = atkS; v->holdSamples = holdS; v->releaseSamples = relS;
                    v->amp = 0.085f;
                    const float pan = (i == 0 ? -0.35f : 0.35f);
                    v->panL = std::cos((pan + 1.0f) * 0.25f * PI_F);
                    v->panR = std::sin((pan + 1.0f) * 0.25f * PI_F);
                    v->baseInc = f / SR_F; v->lfoInc = 0.12f / SR_F; v->lfoDepth = 0.0015f;
                    v->wave = WAVE_GLASS; v->toAmbient = 1.0f; v->toShimmer = 0.25f;
                }
            }
            samplesUntilNextBreath_ = std::max(SR * 5, static_cast<int>((dur - 4.4f) * SR_F));
            return;
        }

        float wJ, wF, wT, wB;
        normMaterials(wJ, wF, wT, wB);

        // 1) Acoustic Chamber Strings Ensemble (dramatic contrast: sparse in Act 0/4, lush cathedral in Act 2/5/6!)
        const int actIdx = step % 8;
        const float stringPresence = (actIdx == 4) ? 0.22f : ((actIdx == 0 || actIdx == 7) ? 0.58f : 1.0f);
        const float padNorm = (0.165f * arc.gain * stringPresence) / std::sqrt(static_cast<float>(chordLen));
        const float spreadCents = 9.0f + wT * 6.0f;
        const float dets[3] = {-spreadCents, 0.0f, spreadCents + 1.2f};
        const int maxChordVoices = (actIdx == 4) ? std::min(2, chordLen) : chordLen;
        for (int i = 0; i < maxChordVoices; ++i) {
            const float f = midiHz(static_cast<float>(chord[i]), a4Ref_ - 1.5f, -4.0f);
            for (int d = 0; d < 3; ++d) {
                if (auto* v = allocBgVoice()) {
                    const float df = f * std::pow(2.0f, dets[d] / 1200.0f);
                    v->attackSamples = static_cast<int>(3.4f * SR_F);
                    v->holdSamples = holdS;
                    v->releaseSamples = static_cast<int>(4.2f * SR_F);
                    v->amp = padNorm * (d == 1 ? 0.52f : 0.30f);
                    const float pan = std::max(-0.85f, std::min(0.85f, (d - 1) * 0.56f + (i % 2 ? 0.14f : -0.14f)));
                    v->panL = std::cos((pan + 1.0f) * 0.25f * PI_F);
                    v->panR = std::sin((pan + 1.0f) * 0.25f * PI_F);
                    v->phase = nextRand01(); v->lfoPhase = nextRand01();
                    v->baseInc = df / SR_F;
                    v->lfoInc = (0.14f + i * 0.032f + d * 0.02f) / SR_F;
                    v->lfoDepth = 0.0018f + wT * 0.0012f;
                    v->wave = (d == 1) ? WAVE_GLASS : WAVE_CELLO;
                    v->useLpf = true;
                    v->fcStart = std::max(220.0f, df * 1.45f);
                    v->fcPeak  = std::min(1550.0f, df * (1.85f + arc.tension * 1.25f));
                    v->lpf.setLowpass(v->fcStart, 0.54f);
                    v->toAmbient = 1.0f;
                }
            }
        }

        // Helper for acoustic plucked/felt-piano/celesta/harp micro-detail notes inside BGM!
        auto spawnBgPluck = [&](float delaySec, int midiNote, float amp, float decaySec, float atkSec,
                                float pan, float harm2Amp, float harm2Ratio, float toDry, float toEcho, float toShim) {
            int sm = midiNote;
            while (sm > 85) sm -= 12;
            const float f = midiHz(static_cast<float>(sm), a4Ref_ - 1.5f, jit(4.5f));
            if (f > 1420.0f || f < 95.0f) return;
            if (auto* v = allocBgVoice()) {
                v->isPluck = true;
                v->delaySamples = std::max(0, static_cast<int>(delaySec * SR_F));
                v->attackSamples = std::max(240, static_cast<int>(atkSec * SR_F));
                v->pluckEnv = 1.0f;
                v->pluckDecayMul = std::exp(-4.6f / std::max(0.35f, decaySec) / SR_F);
                const float eq = (f > 720.0f) ? std::pow(720.0f / f, 0.55f) : 1.0f;
                v->amp = amp * eq;
                const float cp = std::max(-0.82f, std::min(0.82f, pan));
                v->panL = std::cos((cp + 1.0f) * 0.25f * PI_F);
                v->panR = std::sin((cp + 1.0f) * 0.25f * PI_F);
                v->baseInc = f / SR_F;
                v->lfoInc = 0.22f / SR_F;
                v->lfoDepth = 0.0012f;
                v->wave = WAVE_GLASS;
                v->harm2Amp = harm2Amp;
                v->harm2Ratio = harm2Ratio;
                v->harm2Env = 1.0f;
                v->harm2DecayMul = std::exp(-4.6f / std::max(0.10f, decaySec * 0.22f) / SR_F);
                v->useLpf = true;
                v->lpf.setLowpass(std::min(2650.0f, std::max(1150.0f, f * 2.5f)), 0.54f);
                v->toDry = toDry;
                v->toAmbient = 0.58f;
                v->toEcho = toEcho;
                v->toShimmer = toShim;
            }
        };

        // 2) Intimate Felt Piano / Celesta Lyrical Storytelling & Broken-Chord Arpeggios (ALIVE in every act!)
        const int nDeg = mood.numIntervals;
        const int pianoBase = 60 + rootPc_; // C4..B4 expressive piano sweet spot
        if (actIdx == 0) {
            // Act 0 (初幕·微光独白): Intimate 5-note lyrical felt piano solo phrase
            const int degs[5] = {motifDegs_[0], motifDegs_[1], motifDegs_[2], motifDegs_[3], motifDegs_[1]};
            const int octs[5] = {0, 0, 0, 0, 1};
            const float ts[5] = {0.45f, 1.85f, 3.35f, 5.10f, 6.75f};
            const float vs[5] = {0.115f, 0.135f, 0.120f, 0.105f, 0.125f};
            for (int k = 0; k < 5; ++k) {
                const int m = pianoBase + mood.intervals[degs[k] % nDeg] + octs[k] * 12;
                spawnBgPluck(ts[k], m, vs[k], 3.4f, 0.012f, -0.32f + k * 0.16f, 0.24f, 2.0f, 0.28f, 0.36f, 0.32f);
            }
        } else if (actIdx == 1) {
            // Act 1 (星流·竖琴涟漪): Flowing 6-note rising & cresting harp/celesta broken-chord arpeggio
            for (int k = 0; k < 6; ++k) {
                const int ci = (k < 4) ? (k % chordLen) : ((6 - k) % chordLen);
                const int m = chord[ci] + (k >= 3 ? 12 : 0);
                const float t = 0.40f + k * (dur * 0.115f);
                const float vel = 0.095f + 0.040f * std::sin((k + 0.5f) / 6.0f * PI_F);
                spawnBgPluck(t, m, vel, 3.0f, 0.009f, -0.50f + k * 0.20f, 0.28f, 2.0f, 0.26f, 0.42f, 0.36f);
            }
        } else if (actIdx == 2 || actIdx == 5 || actIdx == 6) {
            // Acts 2 / 5 / 6 (极光 / 潮汐 / 穹顶高潮): Lyrical soaring piano melody + warm stereo dialogue!
            const int degs[6] = {motifDegs_[1], motifDegs_[2], motifDegs_[0], motifDegs_[3], motifDegs_[2], motifDegs_[1]};
            const int octs[6] = {0, 1, 1, 0, 1, 1};
            for (int k = 0; k < 6; ++k) {
                const int m = pianoBase + mood.intervals[degs[k] % nDeg] + octs[k] * 12;
                const float t = 0.55f + k * (dur * 0.135f);
                const float vel = (actIdx == 6 ? 0.135f : 0.110f) * (0.85f + 0.25f * std::sin(k * 0.9f));
                spawnBgPluck(t, m, vel, 3.6f, 0.011f, (k % 2 ? 0.38f : -0.38f), 0.22f, wJ > 0.35f ? 2.312f : 2.0f, 0.24f, 0.38f, 0.48f);
            }
        } else if (actIdx == 3) {
            // Act 3 (深空·大提琴咏叹): Sparse answering upper celesta raindrops over expressive cello
            for (int k = 0; k < 3; ++k) {
                const int m = pianoBase + 12 + mood.intervals[motifDegs_[(k + 1) % 4] % nDeg];
                spawnBgPluck(1.4f + k * 2.4f, m, 0.095f, 3.8f, 0.014f, (k == 1 ? 0.45f : -0.42f), 0.24f, 2.0f, 0.22f, 0.45f, 0.42f);
            }
        } else if (actIdx == 4) {
            // Act 4 (静谧之眼·留白): Dramatic stillness — only 2 whisper-soft distant felt piano droplets!
            const int m1 = pianoBase + mood.intervals[motifDegs_[0] % nDeg];
            const int m2 = pianoBase + 12 + mood.intervals[motifDegs_[3] % nDeg];
            spawnBgPluck(1.1f, m1, 0.115f, 4.4f, 0.016f, -0.25f, 0.20f, 2.0f, 0.30f, 0.48f, 0.35f);
            spawnBgPluck(4.6f, m2, 0.090f, 4.8f, 0.020f, +0.32f, 0.18f, 2.0f, 0.25f, 0.52f, 0.42f);
        } else {
            // Act 7 (余晖·归于星尘): Descending rubato cadence dissolving into cathedral mist
            const int degs[4] = {motifDegs_[2], motifDegs_[1], motifDegs_[3], 0};
            for (int k = 0; k < 4; ++k) {
                const int m = pianoBase + mood.intervals[degs[k] % nDeg] + (k == 0 ? 12 : 0);
                spawnBgPluck(0.7f + k * 1.95f, m, 0.115f * (1.0f - k * 0.14f), 4.2f, 0.015f, 0.30f - k * 0.20f, 0.20f, 2.0f, 0.26f, 0.44f, 0.36f);
            }
        }

        // 3) Breathing Polyrhythmic Starlight / Harp Pulse Ostinato (Acts 1, 2, 5, 6 — gives hypnotic Sky-Guide motion!)
        if (actIdx == 1 || actIdx == 2 || actIdx == 5 || actIdx == 6) {
            const float pulseStep = (actIdx == 6) ? 0.56f : 0.68f;
            const int nPulses = std::min(11, static_cast<int>((dur - 1.2f) / pulseStep));
            const int pool[4] = {chord[0] + 12, chord[std::min(1, chordLen - 1)] + 12, chord[chordLen - 1] + 7, chord[std::min(2, chordLen - 1)] + 12};
            for (int p = 0; p < nPulses; ++p) {
                const float arch = std::sin((static_cast<float>(p) + 0.5f) / static_cast<float>(std::max(1, nPulses)) * PI_F);
                const float vel = (0.055f + 0.032f * arc.tension) * arch;
                const float pan = std::sin(p * 1.25f) * 0.62f;
                spawnBgPluck(0.85f + p * pulseStep, pool[p % 4], vel, 1.55f, 0.010f, pan, 0.18f, 2.0f, 0.16f, 0.36f, 0.52f);
            }
        }

        // 4) Whisper-Soft Stereo Starlight Micro-Sparkles (sparse crystalline dewdrop glints across the night sky!)
        if (actIdx != 4) {
            const int nGlints = (actIdx == 6 || actIdx == 2) ? 4 : 2;
            for (int gi = 0; gi < nGlints; ++gi) {
                const int mGlint = pianoBase + 12 + mood.intervals[(motifDegs_[gi % 4] + step + gi) % nDeg];
                const float tGlint = 1.2f + nextRand01() * std::max(2.0f, dur - 2.6f);
                const float gPan = (gi % 2 ? 1.0f : -1.0f) * (0.48f + nextRand01() * 0.30f);
                spawnBgPluck(tGlint, mGlint, 0.044f * arc.gain, 2.2f, 0.006f, gPan, 0.25f, 2.0f, 0.14f, 0.55f, 0.65f);
            }
        }

        // 5) 100%-Wet Velvet Liquid Shimmer Halo (warm register <= 1250 Hz)
        if (arc.shimmer > 0.05f && actIdx != 4) {
            const float shBase = 0.034f * arc.shimmer * arc.gain * (0.85f + wB * 0.30f);
            int shMidis[3] = {chord[0] + 12, chord[std::min(1, chordLen - 1)] + 7, chord[chordLen - 1] + 12};
            const int shN = (arc.tension > 0.65f) ? 3 : 2;
            for (int si = 0; si < shN; ++si) {
                int sm = shMidis[si];
                while (sm > 81) sm -= 12;
                const float sf = midiHz(static_cast<float>(sm), a4Ref_ - 1.5f, si % 2 ? +5.0f : -4.0f);
                if (sf > 1250.0f) continue;
                const float eq = (sf > 680.0f) ? std::pow(680.0f / sf, 0.78f) : 1.0f;
                if (auto* v = allocBgVoice()) {
                    v->delaySamples = static_cast<int>((0.9f + si * 0.45f) * SR_F);
                    v->attackSamples = static_cast<int>(3.2f * SR_F);
                    v->holdSamples = holdS;
                    v->releaseSamples = relS;
                    v->amp = shBase * eq;
                    const float pan = (si % 2 ? 1.0f : -1.0f) * (0.35f + si * 0.14f);
                    v->panL = std::cos((pan + 1.0f) * 0.25f * PI_F);
                    v->panR = std::sin((pan + 1.0f) * 0.25f * PI_F);
                    v->baseInc = sf / SR_F; v->lfoInc = 0.16f / SR_F; v->lfoDepth = 0.0018f;
                    v->wave = WAVE_SINE; v->toAmbient = 0.0f; v->toShimmer = 1.0f;
                }
            }
        }

        // 6) Organic Pink Breath Air Layer (warm low-mid velvet air)
        if (arc.tension > 0.10f) {
            if (auto* nv = allocNoiseVoice()) {
                nv->delaySamples = static_cast<int>(0.4f * SR_F);
                nv->attackSamples = static_cast<int>(3.2f * SR_F);
                nv->totalSamples = holdS + relS;
                nv->amp = (0.028f + arc.tension * 0.032f) * arc.gain;
                nv->fcStart = 500.0f; nv->fcMid = 680.0f + arc.tension * 280.0f; nv->fcEnd = 460.0f;
                nv->q = 1.15f; nv->toDry = 0.0f; nv->toReverb = 0.0f; nv->toShimmer = 1.0f; nv->isPink = true;
            }
        }

        // 7) Soft Cathedral Choir Humming ("Mmm / Ooh" — warm & velvety)
        if (arc.choirOpen > 0.06f && chordLen >= 2) {
            const float cAmp = 0.082f * arc.gain * arc.choirOpen * (0.85f + wB * 0.25f);
            for (int ci = 0; ci < 2; ++ci) {
                if (auto* c = allocChoirVoice()) {
                    const int cm = chord[chordLen - 2 + ci];
                    const float cf = midiHz(static_cast<float>(cm), a4Ref_ - 1.5f, ci == 0 ? -4.0f : +5.0f);
                    c->delaySamples = static_cast<int>(0.8f * SR_F);
                    c->attackSamples = static_cast<int>(3.6f * SR_F);
                    c->holdSamples = holdS;
                    c->releaseSamples = relS;
                    c->amp = cAmp;
                    const float pan = (ci == 0 ? -0.44f : +0.44f);
                    c->panL = std::cos((pan + 1.0f) * 0.25f * PI_F);
                    c->panR = std::sin((pan + 1.0f) * 0.25f * PI_F);
                    c->baseInc = cf / SR_F;
                    c->vibInc = (4.4f + ci * 0.25f) / SR_F;
                    c->openAmt = arc.choirOpen;
                }
            }
        }

        // 8) Expressive 2–3 Note Moving Bowed Cello Counter-Melody (living orchestral counterpoint!)
        if (arc.cello > 0.05f) {
            int celloBase = 36 + ((rootPc_ + spec.bass) % 12);
            if (celloBase > 47) celloBase -= 12;
            const int nCelloSteps = (actIdx == 3 || actIdx == 6) ? 3 : 2;
            const int offsets[3] = {0, (actIdx == 3 ? 7 : 5), (actIdx == 3 ? 9 : 0)};
            const float segDur = dur / static_cast<float>(nCelloSteps);
            for (int ci = 0; ci < nCelloSteps; ++ci) {
                const int cm = celloBase + offsets[ci] + (actIdx == 3 ? 12 : 0); // Tenor cello solo in Act 3!
                const float fCello = midiHz(static_cast<float>(cm), a4Ref_ - 1.5f, -4.0f);
                if (auto* v = allocBgVoice()) {
                    v->delaySamples = static_cast<int>((0.25f + ci * segDur * 0.88f) * SR_F);
                    v->attackSamples = static_cast<int>(1.45f * SR_F);
                    v->holdSamples = static_cast<int>(segDur * 0.92f * SR_F);
                    v->releaseSamples = static_cast<int>(2.4f * SR_F);
                    v->amp = (actIdx == 3 ? 0.24f : 0.20f) * arc.cello * arc.gain;
                    const float pan = (actIdx == 3) ? -0.18f : 0.0f;
                    v->panL = std::cos((pan + 1.0f) * 0.25f * PI_F);
                    v->panR = std::sin((pan + 1.0f) * 0.25f * PI_F);
                    v->baseInc = fCello / SR_F;
                    v->lfoInc = (actIdx == 3 ? 4.2f : 0.14f) / SR_F;
                    v->lfoDepth = (actIdx == 3) ? 0.0024f : 0.0012f;
                    v->wave = WAVE_CELLO;
                    v->useLpf = true;
                    v->fcStart = (actIdx == 3) ? 380.0f : 290.0f;
                    v->fcPeak  = (actIdx == 3) ? 720.0f : 360.0f;
                    v->lpf.setLowpass(v->fcStart, 0.58f);
                    v->toAmbient = 1.0f;
                }
            }
        }

        // 9) 16ft Pipe Organ Sub-Bass in Tidal & Climax Acts
        if (arc.organSub > 0.05f) {
            int subMidi = 36 + rootPc_;
            if (subMidi > 43) subMidi -= 12;
            const float fSub = midiHz(static_cast<float>(subMidi), a4Ref_ - 1.5f, -7.0f);
            for (int mi = 0; mi < 2; ++mi) {
                if (auto* v = allocBgVoice()) {
                    v->delaySamples = static_cast<int>(0.4f * SR_F);
                    v->attackSamples = static_cast<int>(3.4f * SR_F);
                    v->holdSamples = holdS; v->releaseSamples = relS;
                    v->amp = (mi == 0 ? 0.26f : 0.10f) * arc.organSub * arc.gain;
                    v->panL = 0.707f; v->panR = 0.707f;
                    v->baseInc = (fSub * (mi == 0 ? 1.0f : 2.0f)) / SR_F;
                    v->lfoInc = 0.08f / SR_F; v->lfoDepth = 0.0008f;
                    v->wave = WAVE_SINE; v->toAmbient = 1.0f;
                }
            }
        }

        // 10) Material-Driven Signature Accent (Jade chime mist / Bowl harmonic drone)
        if (chordLen >= 3 && wB > 0.28f && actIdx != 4) {
            const float fBowl = midiHz(static_cast<float>(chord[1]), a4Ref_ - 1.5f, 0.0f);
            for (int bi = 0; bi < 2; ++bi) {
                if (auto* v = allocBgVoice()) {
                    v->delaySamples = static_cast<int>(0.9f * SR_F);
                    v->attackSamples = static_cast<int>(3.0f * SR_F);
                    v->holdSamples = holdS; v->releaseSamples = relS;
                    v->amp = 0.040f * wB * arc.gain;
                    const float pan = (bi == 0 ? -0.48f : 0.48f);
                    v->panL = std::cos((pan + 1.0f) * 0.25f * PI_F);
                    v->panR = std::sin((pan + 1.0f) * 0.25f * PI_F);
                    v->baseInc = (fBowl + (bi == 0 ? -1.0f : +1.0f)) / SR_F;
                    v->wave = WAVE_SINE; v->toAmbient = 1.0f;
                }
            }
        }

        // Smooth 3.4-second liquid crossfade overlap so acts evolve briskly and seamlessly!
        samplesUntilNextBreath_ = std::max(SR * 4, static_cast<int>((dur - 3.4f) * SR_F));
    }
};

AetherisEngine& getEngine() {
    static AetherisEngine inst;
    return inst;
}

std::string getNapiString(napi_env env, napi_value val) {
    size_t len = 0;
    if (napi_get_value_string_utf8(env, val, nullptr, 0, &len) != napi_ok || len == 0) return "";
    std::string out(len, '\0');
    napi_get_value_string_utf8(env, val, &out[0], len + 1, &len);
    return out;
}

napi_value NapiRender(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    double peak = 0.0;
    if (argc >= 1) {
        void* data = nullptr;
        size_t byteLen = 0;
        if (napi_get_arraybuffer_info(env, args[0], &data, &byteLen) == napi_ok && data != nullptr && byteLen >= 4) {
            const int frames = static_cast<int>(byteLen / 4);
            peak = static_cast<double>(getEngine().renderBlock(static_cast<int16_t*>(data), frames));
        }
    }
    napi_value ret;
    napi_create_double(env, peak, &ret);
    return ret;
}

napi_value NapiSetMaster(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool m = false, s = true, d = false;
    double vol = 0.7;
    if (argc >= 1) napi_get_value_bool(env, args[0], &m);
    if (argc >= 2) napi_get_value_bool(env, args[1], &s);
    if (argc >= 3) napi_get_value_double(env, args[2], &vol);
    if (argc >= 4) napi_get_value_bool(env, args[3], &d);
    getEngine().setMaster(m, s, static_cast<float>(vol), d);
    napi_value undef; napi_get_undefined(env, &undef); return undef;
}

napi_value NapiSetDNA(napi_env env, napi_callback_info info) {
    size_t argc = 8;
    napi_value args[8] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string seed = (argc >= 1) ? getNapiString(env, args[0]) : "Aetheris";
    std::string mood = (argc >= 2) ? getNapiString(env, args[1]) : "newmoon";
    int32_t rootPc = 3;
    double jade = 0.55, felt = 0.45, tape = 0.25, bowl = 0.30, var = 0.65;
    if (argc >= 3) napi_get_value_int32(env, args[2], &rootPc);
    if (argc >= 4) napi_get_value_double(env, args[3], &jade);
    if (argc >= 5) napi_get_value_double(env, args[4], &felt);
    if (argc >= 6) napi_get_value_double(env, args[5], &tape);
    if (argc >= 7) napi_get_value_double(env, args[6], &bowl);
    if (argc >= 8) napi_get_value_double(env, args[7], &var);
    getEngine().setDNA(seed, mood, rootPc, static_cast<float>(jade), static_cast<float>(felt),
                       static_cast<float>(tape), static_cast<float>(bowl), static_cast<float>(var));
    napi_value undef; napi_get_undefined(env, &undef); return undef;
}

napi_value NapiApplySeed(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string seed = (argc >= 1) ? getNapiString(env, args[0]) : "Aetheris";
    std::string json = getEngine().applySeed(seed);
    napi_value res;
    napi_create_string_utf8(env, json.c_str(), json.size(), &res);
    return res;
}

napi_value NapiSetOutputMode(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool isSpk = false;
    if (argc >= 1) napi_get_value_bool(env, args[0], &isSpk);
    getEngine().setOutputMode(isSpk);
    napi_value undef; napi_get_undefined(env, &undef); return undef;
}

napi_value NapiSetHorizonAltitude(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    double deg = 45.0;
    if (argc >= 1) napi_get_value_double(env, args[0], &deg);
    getEngine().setHorizonAltitude(static_cast<float>(deg));
    napi_value undef; napi_get_undefined(env, &undef); return undef;
}

napi_value NapiSetLowPower(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    bool lp = false;
    if (argc >= 1) napi_get_value_bool(env, args[0], &lp);
    getEngine().setLowPower(lp);
    napi_value undef; napi_get_undefined(env, &undef); return undef;
}

napi_value NapiSkipNextAct(napi_env env, napi_callback_info) {
    getEngine().skipNextAct();
    napi_value undef; napi_get_undefined(env, &undef); return undef;
}

napi_value NapiTriggerStar(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value args[5] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    double tempK = 5800.0, mag = 1.5, distLy = 85.0, pan = 0.0, alt = 0.5;
    if (argc >= 1) napi_get_value_double(env, args[0], &tempK);
    if (argc >= 2) napi_get_value_double(env, args[1], &mag);
    if (argc >= 3) napi_get_value_double(env, args[2], &distLy);
    if (argc >= 4) napi_get_value_double(env, args[3], &pan);
    if (argc >= 5) napi_get_value_double(env, args[4], &alt);
    getEngine().triggerStar(static_cast<float>(tempK), static_cast<float>(mag),
                            static_cast<float>(distLy), static_cast<float>(pan), static_cast<float>(alt));
    napi_value undef; napi_get_undefined(env, &undef); return undef;
}

napi_value NapiTriggerCue(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string cueId = (argc >= 1) ? getNapiString(env, args[0]) : "toggle";
    double pan = 0.0;
    if (argc >= 2) napi_get_value_double(env, args[1], &pan);
    getEngine().triggerCue(cueId, static_cast<float>(pan));
    napi_value undef; napi_get_undefined(env, &undef); return undef;
}

napi_value NapiReset(napi_env env, napi_callback_info) {
    getEngine().resetAll();
    napi_value undef; napi_get_undefined(env, &undef); return undef;
}

} // namespace

void registerAetherisAudioNapi(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "aetherisRender", nullptr, NapiRender, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "aetherisSetMaster", nullptr, NapiSetMaster, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "aetherisSetDNA", nullptr, NapiSetDNA, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "aetherisApplySeed", nullptr, NapiApplySeed, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "aetherisSetOutputMode", nullptr, NapiSetOutputMode, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "aetherisSetHorizonAltitude", nullptr, NapiSetHorizonAltitude, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "aetherisSetLowPower", nullptr, NapiSetLowPower, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "aetherisSkipNextAct", nullptr, NapiSkipNextAct, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "aetherisTriggerStar", nullptr, NapiTriggerStar, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "aetherisTriggerCue", nullptr, NapiTriggerCue, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "aetherisReset", nullptr, NapiReset, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    OH_LOG_Print(LOG_APP, LOG_INFO, AETHERIS_LOG_DOMAIN, AETHERIS_LOG_TAG,
                 "Aetheris v4 Liquid-Cathedral C++ DSP N-API registered (48kHz Stereo, 9.5s Shimmer Cathedral)");
}
