"""巨像的四类独立声线：低吼蓄力、双段怒吼、受创短嚎、濒死长嚎；固定种子，无外部音源。"""
from pathlib import Path
import numpy as np
import wave
OUT=Path(__file__).resolve().parents[2]/'assets/audio/recorded'
RATE=44100
def save(name,data):
    data=np.tanh(data*1.3)
    data=data/max(np.max(np.abs(data)),1e-6)*.82
    with wave.open(str(OUT/(name+'.wav')),'wb') as w:
        w.setparams((1,2,RATE,0,'NONE','not compressed'))
        w.writeframes((data*32767).astype('<i2').tobytes())
def voice(kind,variant,duration,pitch,shape):
    rng=np.random.default_rng(8721+variant+sum(map(ord,kind)))
    t=np.arange(int(duration*RATE))/RATE
    pitch=np.interp(t,np.linspace(0,duration,len(pitch)),pitch)*(1+.035*np.sin(t*(21+variant)))
    phase=2*np.pi*np.cumsum(pitch)/RATE
    vocal=sum(np.sin(phase*k+rng.uniform(-.4,.4))/(k**1.15) for k in range(1,30))
    vocal*=.6+.4*np.sin(2*np.pi*t*(19+variant))**2
    noise=rng.normal(0,1,len(t))
    frequencies=np.fft.rfftfreq(len(t),1/RATE)
    breath=np.fft.irfft(np.fft.rfft(noise)*(np.exp(-((frequencies-650-variant*120)/450)**2)+.3*np.exp(-((frequencies-2100)/650)**2)),n=len(t))
    env=np.interp(t,np.linspace(0,duration,len(shape)),shape)
    signal=(vocal*.6+breath*(.7 if kind=='colossus_hurt' else .4))*env
    # 木质共鸣由衰减脉冲组成；每条声线的脉冲、节奏与基频均独立生成。
    for at in rng.uniform(.1,duration-.15,5):
        u=np.maximum(t-at,0)
        signal+=(t>=at)*np.sin(u*2*np.pi*(140+variant*37))*np.exp(-u*28)*.35*env
    for delay,gain in [(.09,.18),(.19,.1)]:
        shift=int(delay*RATE); signal[shift:]+=signal[:-shift].copy()*gain
    signal*=np.minimum(t/.025,1)*np.minimum((duration-t)/.08,1)
    save(f'{kind}_{variant}',signal)
for i in range(3):
    voice('colossus_charge',i,1.05+i*.08,[35+i*5,43,60+i*7],[0,.6,.7,.85,0])
    voice('colossus_attack',i,1.6+i*.13,[90+i*8,145-i*6,78,54],[0,1,.8,.16,.95,.6,0])
for i in range(2): voice('colossus_hurt',i,.8+i*.2,[170,230+i*35,95],[0,1,.7,0])
voice('colossus_death',0,4.1,[52,125,175,95,40],[0,.8,1,.85,.5,0])
rng=np.random.default_rng(1233)
t=np.arange(int(3.3*RATE))/RATE
burst=np.sin(2*np.pi*(60*t-5*t*t))*np.exp(-t*3)*1.2
for at in [0,.09,.17,.31,.55,.87,1.2,1.7,2.2]:
    u=np.maximum(t-at,0)
    burst+=(t>=at)*rng.normal(0,1,len(t))*np.exp(-u*(15 if at<.6 else 24))*(.6 if at<.6 else .25)
save('colossus_fracture_0',burst)
print('Generated 10 independent vocal and fracture clips')
