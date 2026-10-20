from pathlib import Path
import numpy as np
import wave, zipfile, json

ROOT = Path(__file__).resolve().parent
SR = 48000
rng = np.random.default_rng(2198)

def noise(n, smooth=1):
    x = rng.normal(0, 1, n)
    if smooth > 1:
        x = np.convolve(x, np.ones(smooth)/smooth, mode="same")
    return x

def metal(t, freq, decay):
    return sum(np.sin(2*np.pi*freq*r*t + .2*i)*np.exp(-t/decay/(1+i*.3))/(1+i)
               for i, r in enumerate([1, 1.437, 2.173, 3.79]))

def click(x, at, pitch=1400, strength=.4):
    start=int(at*SR)
    n=min(int(.12*SR),len(x)-start)
    if n<=0:return
    t=np.arange(n)/SR
    x[start:start+n] += strength*(noise(n)*np.exp(-t/.006)+metal(t,pitch,.025)*.3)

def save(path,x):
    x=np.nan_to_num(x)
    x-=np.mean(x)
    x=np.tanh(x*1.15)
    fade=min(480,len(x)//4)
    x[:48]*=np.linspace(0,1,48)
    x[-fade:]*=np.linspace(1,0,fade)
    x*=.84/max(np.max(np.abs(x)),.001)
    path.parent.mkdir(parents=True,exist_ok=True)
    with wave.open(str(path),"wb") as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(SR)
        w.writeframes((x*32767).astype("<i2").tobytes())
    return x

guns={"bagyo":(110,.14,780), "baga":(83,.20,510),
      "tanod":(145,.25,1100), "hatol":(57,.34,330)}
blades={"daluyong":(.34,210,.23), "silakbo":(.43,420,.35),
        "salin":(.52,130,.17), "tinig":(.38,690,.65)}
preview=[]; manifest=[]
for name,(bass,tail,res) in guns.items():
    for event,duration in [("fire",1.35),("reload",1.8),("dry_fire",.35)]:
        t=np.arange(int(duration*SR))/SR
        x=np.zeros(len(t))
        if event=="fire":
            x += noise(len(t))*np.exp(-t/.014)*1.5
            x += noise(len(t),8)*np.exp(-t/tail)*1.4
            phase=2*np.pi*(bass*t+40*.025*(1-np.exp(-t/.025)))
            x += np.sin(phase)*np.exp(-t/(tail*.75))*.9
            x += metal(t,res,.065)*.12
            click(x,.075,res,.25)
            if name=="hatol": x+=metal(t,47,.31)*.16
            if name=="baga": x+=noise(len(t),3)*np.exp(-t/.35)*.09
        elif event=="reload":
            for at,power in [(.04,.5),(.27,.28),(.81,.6),(1.18,.8),(1.43,.35)]:
                click(x,at,res,power)
            x+=noise(len(t),16)*np.exp(-((t-.62)/.19)**2)*.1
        else: click(x,.015,res,.65)
        audio=save(ROOT/name/(event+".wav"),x)
        manifest.append({"weapon":name,"event":event,"seconds":duration})
        if event=="fire": preview.append((name,audio))

for name,(length,res,ring) in blades.items():
    for event,duration in [("swing",1.2),("impact",1.4),("draw",1.3)]:
        t=np.arange(int(duration*SR))/SR
        x=np.zeros(len(t))
        if event=="swing":
            envelope=np.exp(-((t-length*.65)/(length*.24))**2)
            x+=noise(len(t),12)*envelope*2.4
            x+=noise(len(t),2)*envelope*.11
            x+=np.sin(2*np.pi*(95*t-22*t*t))*envelope*.13
            onset=np.maximum(t-length*.5,0)
            x+=metal(onset,res,ring)*np.exp(-onset/.35)*(t>length*.5)*.035
        elif event=="impact":
            x+=noise(len(t),5)*np.exp(-t/.026)*1.6
            x+=np.sin(2*np.pi*73*t)*np.exp(-t/.055)*.8
            x+=metal(t,res,ring)*.36
            click(x,.035,res*2,.15)
        else:
            env=np.exp(-((t-.3)/.16)**2)
            x+=noise(len(t),4)*env*.25
            x+=metal(t,res,.5)*env*.16
            click(x,.07,res,.16)
        if name=="tinig":
            x+=metal(t,183,.55)*np.exp(-((t-.22)/.22)**2)*.07
        audio=save(ROOT/name/(event+".wav"),x)
        manifest.append({"weapon":name,"event":event,"seconds":duration})
        if event=="swing": preview.append((name,audio))

reel=[]; timeline=[]; elapsed=0
for name,x in preview:
    timeline.append(f"{elapsed:05.2f}s — {name.upper()}")
    reel.extend([x,np.zeros(int(.65*SR))])
    elapsed+=len(x)/SR+.65
save(ROOT/"preview.wav",np.concatenate(reel))
(ROOT/"manifest.json").write_text(json.dumps(manifest,indent=2))
(ROOT/"README.md").write_text(
    "# Oathbound — Cursed Salvage SFX v1\n\n"
    "24 original procedurally synthesized prototype effects. No external samples.\n"
    "48 kHz, mono, 16-bit PCM WAV. Peaks below -1.5 dBFS. Dry sounds for positional playback.\n"
    "Firearms: fire, reload (stylized full sequence), dry_fire.\n"
    "Blades: swing, impact (hard metallic target), draw.\n\n"
    "Preview order:\n\n"+"\n".join(timeline)+"\n\n"
    "Bagyo: sharp rattling report. Baga: rough heavy crack. Tanod: bright long report. "
    "Hatol: low booming report. Daluyong: dense cutting rush. Silakbo: brighter ringing slash. "
    "Salin: broad heavy sweep. Tinig: thin eerie resonance.\n\n"
    "Import individual WAVs into Godot and trigger with AudioStreamPlayer3D. "
    "Fire is a single shot; schedule repeated shots at the weapon fire rate. "
    "Trigger blade swing and impact separately. Reload timing needs alignment with animation. "
    "No gameplay integration performed. Technical signal checks do not replace listening and in-game mixing.\n",
    encoding="utf-8")
for path in ROOT.rglob("*.wav"):
    with wave.open(str(path),"rb") as w:
        a=np.frombuffer(w.readframes(w.getnframes()),dtype="<i2")
        assert w.getframerate()==SR and w.getnchannels()==1
        assert np.max(np.abs(a.astype(float)))<32767 and np.any(a)
archive=ROOT.parent/"oathbound-cursed-salvage-sfx-v1.zip"
with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED) as z:
    for p in ROOT.rglob("*"):
        if p.is_file():z.write(p,p.relative_to(ROOT))
print(f"Validated 25 WAV files (24 effects + preview). Pack: {archive}")
