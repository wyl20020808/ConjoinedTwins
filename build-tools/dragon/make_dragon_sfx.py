"""生成第二章魔龙音效：龙吼与振翅。全部为程序合成，再叠加项目已有的 CC0 录音（降调的爆炸与火焰），
固定随机种子，可重复生成。只依赖 numpy（macOS 系统 Python 没有 numpy 时可用 Blender 自带的 Python 运行）。

用法：python build-tools/dragon/make_dragon_sfx.py
     /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 build-tools/dragon/make_dragon_sfx.py
输出：assets/audio/recorded/dragon_roar_0.wav、wing_flap_0.wav（44.1 kHz 单声道 16 位）。
"""
import os
import wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(ROOT, 'assets', 'audio', 'recorded')
RATE = 44100
rng = np.random.default_rng(20261023)


def load(name):
    with wave.open(os.path.join(OUT, name)) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
        data = data.reshape(-1, w.getnchannels()).mean(axis=1)
        if w.getframerate() != RATE:
            data = np.interp(np.arange(0, len(data), w.getframerate() / RATE), np.arange(len(data)), data)
        return data


def save(name, data):
    data = data / max(1e-9, np.max(np.abs(data))) * 0.89
    with wave.open(os.path.join(OUT, name), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((data * 32767).astype(np.int16).tobytes())
    print('WROTE', name, round(len(data) / RATE, 2), 's')


def resample(data, factor):
    positions = np.arange(0, len(data) - 1, factor)
    return np.interp(positions, np.arange(len(data)), data)


def fit(data, n, offset=0):
    data = np.pad(data, (offset, 0))[:n]
    return np.pad(data, (0, n - len(data)))


def spectral(data, gain):
    """STFT 逐帧滤波：gain(frame_time, freqs) 返回该帧各频率增益。"""
    size, hop = 2048, 512
    window = np.hanning(size)
    padded = np.concatenate([np.zeros(size), data, np.zeros(size)])
    out = np.zeros(len(padded))
    norm = np.zeros(len(padded))
    freqs = np.fft.rfftfreq(size, 1 / RATE)
    for start in range(0, len(padded) - size, hop):
        frame = padded[start:start + size] * window
        t = (start - size + size / 2) / RATE
        spectrum = np.fft.rfft(frame) * gain(t, freqs)
        out[start:start + size] += np.fft.irfft(spectrum) * window
        norm[start:start + size] += window ** 2
    out /= np.maximum(norm, 1e-6)
    return out[size:size + len(data)]


def envelope(n, points):
    t = np.arange(n) / RATE
    xs, ys = zip(*points)
    return np.interp(t, xs, ys)


def formants(freqs, centers):
    g = np.zeros_like(freqs)
    for center, width, level in centers:
        g += level * np.exp(-0.5 * ((freqs - center) / width) ** 2)
    return g


def voice(t, f0, partials, rough_rate, rough_depth):
    drift = np.cumsum(rng.normal(0, 0.02, len(t)))
    drift = drift - np.convolve(drift, np.ones(4410) / 4410, mode='same')
    phase = 2 * np.pi * np.cumsum(f0 * (1 + 0.035 * drift)) / RATE
    rough = 1 + rough_depth * np.sin(2 * np.pi * np.cumsum(rough_rate) / RATE)
    return sum(np.sin(k * phase + rng.uniform(0, 6.28)) / k ** 0.8 for k in range(1, partials)) * rough


def roar():
    """龙吼（2.8 秒）：低沉的胸腔吼声打底，上面叠一层撕裂的尖啸，尾段带喉部喷火般的嘶嘶气声。"""
    seconds = 2.8
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    low = voice(t, np.interp(t, [0, 0.3, 1.4, 2.2, 2.8], [58, 84, 76, 62, 46]), 26,
                np.interp(t, [0, 2.8], [24, 33]), 0.6)
    scream = voice(t, np.interp(t, [0, 0.25, 0.9, 1.8, 2.8], [170, 290, 260, 210, 150]), 14,
                   np.interp(t, [0, 2.8], [38, 52]), 0.75)

    def mouth(time, freqs):
        mix = np.clip(time / seconds, 0, 1)
        return formants(freqs, [(np.interp(mix, [0, 1], [820, 520]), 200, 1.0),
                                (np.interp(mix, [0, 1], [1400, 950]), 260, 0.7),
                                (2900, 500, 0.35), (200, 100, 0.7)])
    low = spectral(low, lambda time, freqs: 0.3 + mouth(time, freqs))
    scream = spectral(scream, lambda time, freqs: 0.15 + mouth(time, freqs) * np.exp(-freqs / 6000.0))
    breath = spectral(rng.normal(0, 1, n), lambda time, freqs: mouth(time, freqs) + 0.3 * np.exp(-((freqs - 3500) / 2500) ** 2))
    fire = fit(resample(load('flame_loop.wav'), 0.7), n, int(1.2 * RATE)) * envelope(n, [(0, 0), (1.2, 0), (1.6, 0.8), (2.8, 0)])
    boom = fit(resample(load('explosion_1.wav'), 0.5), n) * 0.5
    mix = low * 1.0 + scream * 0.55 * envelope(n, [(0, 0), (0.15, 1), (2.0, 0.8), (2.8, 0.2)]) + breath * 0.5 + fire * 0.5 + boom
    mix = np.tanh(mix / np.max(np.abs(mix)) * 2.8)
    return mix * envelope(n, [(0, 0), (0.06, 0.7), (0.25, 1.0), (1.9, 0.9), (2.4, 0.45), (2.8, 0)])


def flap():
    """振翅（0.75 秒）：巨大皮膜下拍时的一股低沉风压，带皮膜抖动的颤音和收翼时的轻响。"""
    seconds = 0.75
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    gust = spectral(rng.normal(0, 1, n), lambda time, freqs: np.exp(-freqs / 260.0) + 0.25 * np.exp(-((freqs - 700) / 400) ** 2))
    flutter = 1 + 0.45 * np.sin(2 * np.pi * np.interp(t, [0, seconds], [34, 22]) * t)
    thump = np.sin(2 * np.pi * np.cumsum(np.interp(t, [0, 0.3], [62, 38])) / RATE) * np.exp(-((t - 0.16) / 0.09) ** 2)
    snap = spectral(rng.normal(0, 1, n), lambda time, freqs: np.exp(-((freqs - 1600) / 900) ** 2)) * np.exp(-((t - 0.62) / 0.03) ** 2) * 0.25
    mix = gust / np.max(np.abs(gust)) * flutter * envelope(n, [(0, 0), (0.12, 1.0), (0.32, 0.8), (0.55, 0.25), (0.75, 0)]) + thump * 0.9 + snap
    return np.tanh(mix * 1.6)


save('dragon_roar_0.wav', roar())
save('wing_flap_0.wav', flap())
