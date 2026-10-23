"""生成第三章海神音效：巨浪拍击、水花、激流循环与雷声。全部为程序合成（滤波噪声与正弦），
再叠加项目已有的 CC0 录音（降调的爆炸），固定随机种子，可重复生成。只依赖 numpy
（macOS 系统 Python 没有 numpy 时可用 Blender 自带的 Python 运行）。

用法：/Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 build-tools/poseidon/make_poseidon_sfx.py
输出：assets/audio/recorded/tide_crash_0.wav、water_splash_0.wav、thunder_0.wav、water_jet_loop.wav（44.1 kHz 单声道 16 位）。
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


def save(name, data, peak=0.89):
    data = data / max(1e-9, np.max(np.abs(data))) * peak
    with wave.open(os.path.join(OUT, name), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((data * 32767).astype(np.int16).tobytes())
    print('WROTE', name, round(len(data) / RATE, 2), 's')


def resample(data, factor):
    positions = np.arange(0, len(data) - 1, factor)
    return np.interp(positions, np.arange(len(data)), data)


def lowpass(data, cutoff):
    """一阶低通（可随时间变化的截止频率，cutoff 为标量或与 data 等长的数组）。"""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), data.shape)
    alpha = 1.0 - np.exp(-2.0 * np.pi * cutoff / RATE)
    out = np.empty_like(data)
    acc = 0.0
    for i in range(len(data)):
        acc += alpha[i] * (data[i] - acc)
        out[i] = acc
    return out


def highpass(data, cutoff):
    return data - lowpass(data, cutoff)


def envelope(n, attack, release_curve=3.0):
    t = np.linspace(0, 1, n)
    a = max(1, int(attack * RATE))
    env = np.minimum(1.0, np.arange(n) / a)
    return env * (1 - t) ** release_curve


# 巨浪拍击（2.6 秒）：低沉的水体轰鸣先涌起，拍下时一阵宽频水花，再带着气泡嘶声退去。
def tide_crash():
    n = int(2.6 * RATE)
    t = np.arange(n) / RATE
    noise = rng.standard_normal(n)
    swell = lowpass(noise, 180 + 900 * np.clip(t / 0.5, 0, 1)) * np.clip(t / 0.45, 0, 1) * np.exp(-np.maximum(0, t - 0.6) * 1.6)
    slap_env = np.where(t > 0.42, np.exp(-(t - 0.42) * 3.2), 0.0) * np.clip((t - 0.42) / 0.03, 0, 1)
    slap = highpass(lowpass(rng.standard_normal(n), 5200), 400) * slap_env
    fizz = highpass(rng.standard_normal(n), 2500) * np.where(t > 0.6, np.exp(-(t - 0.6) * 1.4), 0.0) * 0.35
    fizz *= 0.6 + 0.4 * np.abs(np.sin(t * 37.0) * np.sin(t * 13.0))
    boom = resample(load('explosion_0.wav'), 0.45)[:n]
    boom = np.pad(boom, (int(0.4 * RATE), 0))[:n] * 0.35
    return swell * 1.4 + slap * 0.9 + fizz + boom


# 水花（0.9 秒）：短促的宽频冲击加几颗下落的水滴音。
def water_splash():
    n = int(0.9 * RATE)
    t = np.arange(n) / RATE
    burst = highpass(lowpass(rng.standard_normal(n), 6000), 300) * np.exp(-t * 7.0) * np.clip(t / 0.005, 0, 1)
    drops = np.zeros(n)
    for k in range(9):
        start = rng.uniform(0.05, 0.6)
        freq = rng.uniform(700, 1600)
        tt = np.clip(t - start, 0, None)
        drops += np.where(t > start, np.sin(2 * np.pi * (freq * tt + 900 * tt * tt)) * np.exp(-tt * 40), 0.0) * rng.uniform(0.1, 0.25)
    body = lowpass(rng.standard_normal(n), 500) * np.exp(-t * 5.0) * 0.8
    return burst + drops + body


# 雷声（3.2 秒）：一声尖锐的炸裂接长长的低频滚雷。
def thunder():
    n = int(3.2 * RATE)
    t = np.arange(n) / RATE
    crack = highpass(rng.standard_normal(n), 1500) * np.exp(-t * 18.0)
    roll_env = np.clip(t / 0.15, 0, 1) * np.exp(-t * 1.0) * (0.7 + 0.3 * np.sin(t * 9.0 + np.sin(t * 3.1) * 2))
    roll = lowpass(rng.standard_normal(n), 140) * roll_env * 3.0
    boom = resample(load('explosion_1.wav'), 0.5)[:n]
    boom = np.pad(boom, (0, max(0, n - len(boom))))[:n] * 0.5
    return crack * 0.9 + roll + boom


# 激流循环（2.0 秒，可无缝循环）：高压水柱的嘶鸣与翻滚。首尾交叉淡化保证无缝。
def water_jet_loop():
    n = int(2.0 * RATE)
    extra = int(0.2 * RATE)
    t = np.arange(n + extra) / RATE
    hiss = highpass(lowpass(rng.standard_normal(n + extra), 7000), 900) * (0.8 + 0.2 * np.sin(t * 2 * np.pi * 3.0))
    rumble = lowpass(rng.standard_normal(n + extra), 260) * (1.0 + 0.3 * np.sin(t * 2 * np.pi * 1.5)) * 1.6
    data = hiss * 0.6 + rumble
    head, tail = data[:extra], data[n:n + extra]
    fade = np.linspace(0, 1, extra)
    out = data[:n].copy()
    out[:extra] = head * fade + tail * (1 - fade)
    return out


save('tide_crash_0.wav', tide_crash())
save('water_splash_0.wav', water_splash())
save('thunder_0.wav', thunder())
save('water_jet_loop.wav', water_jet_loop(), peak=0.7)
