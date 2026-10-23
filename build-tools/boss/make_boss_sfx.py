"""生成 Boss 入场音效：咆哮、地下轰鸣、破土冲击。全部为程序合成，再叠加项目已有的 CC0 木头录音（降调），
固定随机种子，可重复生成。只依赖 numpy。

用法：python build-tools/boss/make_boss_sfx.py
输出：assets/audio/recorded/boss_roar_0.wav、boss_rumble_0.wav、boss_burst_0.wav（44.1 kHz 单声道 16 位）。
"""
import os
import wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(ROOT, 'assets', 'audio', 'recorded')
RATE = 44100
rng = np.random.default_rng(20261022)


def load(name):
    with wave.open(os.path.join(OUT, name)) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
        return data.reshape(-1, w.getnchannels()).mean(axis=1)


def save(name, data):
    data = data / max(1e-9, np.max(np.abs(data))) * 0.89
    with wave.open(os.path.join(OUT, name), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((data * 32767).astype(np.int16).tobytes())
    print('WROTE', name, round(len(data) / RATE, 2), 's')


def resample(data, factor):
    """按 factor 变速变调（<1 变低变长）。"""
    positions = np.arange(0, len(data) - 1, factor)
    return np.interp(positions, np.arange(len(data)), data)


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
    """points: [(秒, 电平)] 分段线性包络。"""
    t = np.arange(n) / RATE
    xs, ys = zip(*points)
    return np.interp(t, xs, ys)


def formants(t, freqs, centers):
    g = np.zeros_like(freqs)
    for center, width, level in centers:
        g += level * np.exp(-0.5 * ((freqs - center) / width) ** 2)
    return g


def roar():
    seconds = 3.0
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    # 基频：起声上扬、中段颤动、尾音下沉；随机游走让音高不机械。
    drift = np.cumsum(rng.normal(0, 0.02, n))
    drift = drift - np.convolve(drift, np.ones(4410) / 4410, mode='same')
    f0 = np.interp(t, [0, 0.35, 1.6, 2.4, 3.0], [52, 78, 70, 58, 44]) * (1 + 0.04 * drift)
    phase = 2 * np.pi * np.cumsum(f0) / RATE
    # 粗糙度：22–31 Hz 的幅度调制，像喉部的嘶哑颤音。
    rough = 1 + 0.55 * np.sin(2 * np.pi * np.cumsum(np.interp(t, [0, 3], [22, 31])) / RATE)
    growl = sum(np.sin(k * phase + rng.uniform(0, 6.28)) / k ** 0.85 for k in range(1, 28)) * rough
    # 喘息噪声按元音共振峰塑形：“啊”→“喔”，越往后越暗。
    breath = rng.normal(0, 1, n)

    def vowel(time, freqs):
        mix = np.clip(time / seconds, 0, 1)
        return formants(time, freqs, [(np.interp(mix, [0, 1], [700, 450]), 160, 1.0),
                                      (np.interp(mix, [0, 1], [1150, 800]), 220, 0.6),
                                      (2500, 400, 0.25), (180, 90, 0.8)])
    breath = spectral(breath, vowel)
    voiced = spectral(growl, lambda time, freqs: 0.3 + vowel(time, freqs))
    wood = resample(load('wood_creak_heavy_0.wav'), 0.45)
    wood = np.pad(wood, (int(0.15 * RATE), 0))[:n]
    wood = np.pad(wood, (0, n - len(wood)))
    mix = voiced * 1.0 + breath * 0.55 + wood * 0.6
    mix = np.tanh(mix / np.max(np.abs(mix)) * 2.6)
    return mix * envelope(n, [(0, 0), (0.08, 0.6), (0.3, 1.0), (2.0, 0.9), (2.6, 0.45), (3.0, 0)])


def rumble():
    seconds = 3.6
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    brown = np.cumsum(rng.normal(0, 1, n))
    brown -= np.convolve(brown, np.ones(2205) / 2205, mode='same')
    low = spectral(brown, lambda time, freqs: np.exp(-freqs / 90.0))
    sub = np.sin(2 * np.pi * np.cumsum(np.interp(t, [0, seconds], [32, 41])) / RATE) * (0.6 + 0.4 * np.sin(2 * np.pi * 3.1 * t))
    mix = low / np.max(np.abs(low)) + sub * 0.7
    # 地下断裂声：降调的倒树录音在中后段裂开。
    crack = resample(load('tree_fall_0.wav'), 0.6)
    start = int(1.6 * RATE)
    crack = crack[:n - start]
    mix[start:start + len(crack)] += crack * 0.9
    mix = np.tanh(mix * 1.4)
    return mix * envelope(n, [(0, 0), (0.9, 0.6), (2.6, 1.0), (3.2, 0.8), (3.6, 0)])


def burst():
    boom = resample(load('explosion_0.wav'), 0.7)
    n = len(boom)
    t = np.arange(n) / RATE
    thump = np.sin(2 * np.pi * np.cumsum(np.interp(t, [0, 0.4], [70, 30])) / RATE) * np.exp(-t * 6)
    debris = spectral(rng.normal(0, 1, n), lambda time, freqs: np.exp(-((freqs - 1800) / 1500) ** 2)) * np.exp(-t * 3.5) * 0.3
    return np.tanh((boom + thump * 1.2 + debris) * 1.3)


save('boss_roar_0.wav', roar())
save('boss_rumble_0.wav', rumble())
save('boss_burst_0.wav', burst())
