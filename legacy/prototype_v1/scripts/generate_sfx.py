import wave
import math
import struct
import random
import os

OUTPUT_DIR = "assets/audio"
os.makedirs(OUTPUT_DIR, exist_ok=True)

SAMPLE_RATE = 44100

def save_wav(filename, samples):
    filepath = os.path.join(OUTPUT_DIR, filename)
    with wave.open(filepath, "w") as wav_file:
        wav_file.setnchannels(1)  # Mono
        wav_file.setsampwidth(2)  # 16-bit
        wav_file.setframerate(SAMPLE_RATE)
        for s in samples:
            # Clamp to 16-bit signed integer range
            val = max(-32767, min(32767, int(s * 32767.0)))
            wav_file.writeframes(struct.pack('<h', val))
    print(f"Generated {filepath}")

# 1. SFX: Cat Meow (pitch bend up then down with formant harmonics)
def gen_meow():
    duration = 0.55
    total_samples = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(total_samples):
        t = i / SAMPLE_RATE
        env = math.sin(math.pi * (t / duration)) ** 1.5
        # Pitch curve: starts at 520Hz, rises to 780Hz, glides to 440Hz
        norm_t = t / duration
        freq = 520 + 320 * math.sin(norm_t * math.pi) - 100 * norm_t
        phase = 2 * math.pi * freq * t
        # Add rich cat formant harmonics
        sample = 0.6 * math.sin(phase) + 0.3 * math.sin(phase * 2) + 0.15 * math.sin(phase * 3)
        samples.append(sample * env * 0.75)
    save_wav("sfx_meow.wav", samples)

# 2. SFX: Magic Fireball Cast (high sparkle + airy whoosh)
def gen_magic_cast():
    duration = 0.45
    total_samples = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(total_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 6.0)
        freq = 300 + 1200 * (1.0 - t / duration) ** 2
        sine = math.sin(2 * math.pi * freq * t)
        noise = (random.random() * 2.0 - 1.0) * 0.25
        samples.append((sine * 0.7 + noise) * env * 0.8)
    save_wav("sfx_magic_cast.wav", samples)

# 3. SFX: Big Explosion / Destruction Rumble (heavy bass + noise drop)
def gen_explosion():
    duration = 1.0
    total_samples = int(SAMPLE_RATE * duration)
    samples = []
    noise_filter = 0.0
    for i in range(total_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 3.5)
        # Deep bass rumble that sweeps down from 120Hz to 35Hz
        bass_freq = 120 * math.exp(-t * 3.0) + 35
        bass = math.sin(2 * math.pi * bass_freq * t) * 0.8
        # Filtered explosive noise
        raw_noise = random.random() * 2.0 - 1.0
        noise_filter += (raw_noise - noise_filter) * 0.25
        sample = (bass + noise_filter * 0.7) * env
        samples.append(sample * 0.9)
    save_wav("sfx_explosion.wav", samples)

# 4. SFX: Hairball Shot (squishy thump / pop)
def gen_hairball():
    duration = 0.35
    total_samples = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(total_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 12.0)
        # Fast pitch drop like a rubber cork popping
        freq = 450 * math.exp(-t * 18.0) + 80
        sample = math.sin(2 * math.pi * freq * t)
        # Add a little squish/wet noise
        sample += (random.random() * 2.0 - 1.0) * 0.2 * math.exp(-t * 8.0)
        samples.append(sample * env * 0.85)
    save_wav("sfx_hairball.wav", samples)

# 5. SFX: Acid Stream Loop / Sizzle (hissing bubbling stream)
def gen_acid():
    duration = 0.7
    total_samples = int(SAMPLE_RATE * duration)
    samples = []
    filt = 0.0
    for i in range(total_samples):
        t = i / SAMPLE_RATE
        env = min(1.0, t * 10.0) * min(1.0, (duration - t) * 8.0)
        raw_noise = random.random() * 2.0 - 1.0
        filt += (raw_noise - filt) * 0.4
        # Bubble modulations
        bubble = 1.0 + 0.4 * math.sin(2 * math.pi * 32 * t)
        samples.append(filt * bubble * env * 0.6)
    save_wav("sfx_acid_sizzle.wav", samples)

# 6. SFX: Nature Shield (celestial crystal chime)
def gen_nature_shield():
    duration = 0.8
    total_samples = int(SAMPLE_RATE * duration)
    samples = []
    freqs = [880, 1108, 1318, 1760]  # A major chord high
    for i in range(total_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 4.0)
        sample = sum(math.sin(2 * math.pi * f * t) * (1.0 / len(freqs)) for f in freqs)
        samples.append(sample * env * 0.75)
    save_wav("sfx_nature_shield.wav", samples)

# 7. SFX: Glitch / Simulation Beep
def gen_glitch():
    duration = 0.4
    total_samples = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(total_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 5.0)
        # Square wave stepping frequencies
        freq = 800 if (int(t * 40) % 2 == 0) else 1250
        sample = 1.0 if math.sin(2 * math.pi * freq * t) > 0 else -1.0
        samples.append(sample * env * 0.4)
    save_wav("sfx_glitch.wav", samples)

# 8. SFX: Magma Rocket Launch (comic upward slide + boom)
def gen_rocket():
    duration = 1.1
    total_samples = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(total_samples):
        t = i / SAMPLE_RATE
        env = min(1.0, t * 6.0) * math.exp(-t * 1.5)
        # Upward pitch slide (whistle)
        freq = 150 + 1200 * (t / duration) ** 2
        whistle = math.sin(2 * math.pi * freq * t)
        noise = (random.random() * 2.0 - 1.0) * 0.3
        samples.append((whistle * 0.7 + noise) * env * 0.8)
    save_wav("sfx_rocket_launch.wav", samples)

if __name__ == "__main__":
    gen_meow()
    gen_magic_cast()
    gen_explosion()
    gen_hairball()
    gen_acid()
    gen_nature_shield()
    gen_glitch()
    gen_rocket()
    print("All SFX generated!")
