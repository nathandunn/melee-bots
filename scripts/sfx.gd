class_name Sfx
extends Node
## Every sound in the game, synthesised in code at startup - no audio files anywhere, which
## keeps the web export small and the repo free of binary blobs (the same reason the meshes
## are all built in code). Each cue is a little PCM recipe: an envelope over some mix of
## sines, sweeps and noise, rendered once into an AudioStreamWAV and then played from a
## round-robin pool of 3D players so a ten-robot brawl doesn't run out of voices.

const RATE := 22050
const VOICES := 20          # positional one-shots in flight at once
const REPEAT_GAP := 0.045   # the same cue twice inside this window is a duplicate, not a sound

static var _mute := false

var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _last := {}
var _clock := 0.0
var _enabled := true


func _ready() -> void:
	# headless has no audio device and no ears to care: build nothing, play nothing
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	_build_streams()
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 14.0
		p.max_distance = 70.0
		p.max_db = 2.0
		p.panning_strength = 0.6
		add_child(p)
		_pool.append(p)


func _process(delta: float) -> void:
	_clock += delta


static func set_muted(m: bool) -> void:
	_mute = m
	AudioServer.set_bus_mute(0, m)


static func is_muted() -> bool:
	return _mute


## One-shot at a point in the world. `pitch` is a multiplier; `vol_db` trims the loudest cues.
func play(cue: String, at: Vector3, pitch := 1.0, vol_db := 0.0) -> void:
	if not _enabled or _mute or not _streams.has(cue):
		return
	var last := float(_last.get(cue, -99.0))
	if _clock - last < REPEAT_GAP:
		return
	_last[cue] = _clock
	var p: AudioStreamPlayer3D = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[cue]
	p.global_position = at
	p.pitch_scale = clampf(pitch, 0.3, 3.0)
	p.volume_db = vol_db
	p.play()


# ---------------------------------------------------------------- the recipes

func _build_streams() -> void:
	_streams["swing"] = _swing()
	_streams["thud"] = _thud()
	_streams["clang"] = _clang()
	_streams["bonk"] = _bonk()
	_streams["smash"] = _smash()
	_streams["meow"] = _meow()
	_streams["screech"] = _screech()
	_streams["giggle"] = _giggle()
	_streams["boing"] = _boing()
	_streams["clatter"] = _clatter()
	_streams["death"] = _death()
	_streams["cheer"] = _cheer()
	_streams["pickup"] = _pickup()


static func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	b.fill(0.0)
	return b


## Attack/decay envelope, exponential tail. `attack` is a fraction of the whole.
static func _env(i: int, n: int, attack: float, curve: float) -> float:
	var t := float(i) / float(maxi(n, 1))
	if t < attack:
		return t / maxf(attack, 0.0001)
	return pow(1.0 - (t - attack) / maxf(1.0 - attack, 0.0001), curve)


## A one-pole low pass, applied in place - takes the fizz off raw noise so it reads as air
## or a body rather than a hiss.
static func _lowpass(b: PackedFloat32Array, alpha: float) -> void:
	var y := 0.0
	for i in b.size():
		y += alpha * (b[i] - y)
		b[i] = y


## The air a bat or a fist moves: noise, filtered down, swelling and gone in a third of a second.
static func _swing() -> AudioStreamWAV:
	var n := int(0.26 * RATE)
	var b := _buf(0.26)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		b[i] = rng.randf_range(-1.0, 1.0)
	_lowpass(b, 0.12)
	for i in n:
		var t := float(i) / float(n)
		var swell: float = sin(PI * pow(t, 0.7))   # fastest through the middle of the arc
		b[i] *= swell * swell * 0.55
	return _wav(b)


## Fist or boot on a chassis: a low body dropping in pitch, with a click of contact on top.
static func _thud() -> AudioStreamWAV:
	var n := int(0.20 * RATE)
	var b := _buf(0.20)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var ph := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f: float = lerpf(105.0, 52.0, pow(t, 0.4))
		ph += TAU * f / float(RATE)
		var body: float = sin(ph) * _env(i, n, 0.004, 3.0)
		var click: float = rng.randf_range(-1.0, 1.0) * _env(i, n, 0.001, 26.0) * 0.38
		b[i] = body * 0.68 + click
	return _wav(b)


## Steel on steel: three inharmonic partials that ring and die - a sword, a bat, a spear.
static func _clang() -> AudioStreamWAV:
	var n := int(0.42 * RATE)
	var b := _buf(0.42)
	var parts := [[523.0, 1.0, 3.2], [1187.0, 0.55, 4.6], [1873.0, 0.32, 6.5], [2971.0, 0.16, 9.0]]
	for p in parts:
		var f: float = p[0]
		var amp: float = p[1]
		var decay: float = p[2]
		var ph := 0.0
		for i in n:
			ph += TAU * f / float(RATE)
			b[i] += sin(ph) * amp * _env(i, n, 0.0015, decay) * 0.3
	# a scrape of contact at the front
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in int(0.03 * RATE):
		b[i] += rng.randf_range(-1.0, 1.0) * _env(i, int(0.03 * RATE), 0.001, 8.0) * 0.35
	return _wav(b)


## A stone finding a robot: heavier and duller than a blade, with grit in it.
static func _bonk() -> AudioStreamWAV:
	var n := int(0.26 * RATE)
	var b := _buf(0.26)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	var ph := 0.0
	var ph2 := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f: float = lerpf(196.0, 88.0, pow(t, 0.5))
		ph += TAU * f / float(RATE)
		ph2 += TAU * f * 2.51 / float(RATE)
		var e: float = _env(i, n, 0.002, 4.0)
		b[i] = ((sin(ph) * 0.75 + sin(ph2) * 0.25) * e + rng.randf_range(-1.0, 1.0) * _env(i, n, 0.001, 18.0) * 0.4) * 0.78
	return _wav(b)


## A bottle going: the crack, then the shower of bits. Grains of noise thrown out over a
## third of a second do the tinkle better than any tone.
static func _smash() -> AudioStreamWAV:
	var n := int(0.5 * RATE)
	var b := _buf(0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 59
	for i in n:
		b[i] = rng.randf_range(-1.0, 1.0) * _env(i, n, 0.0008, 14.0) * 0.8
	# glass shards: short high pings scattered through the tail
	for k in 26:
		var start := int(rng.randf_range(0.01, 0.42) * RATE)
		var len_s := int(rng.randf_range(0.015, 0.05) * RATE)
		var f := rng.randf_range(2400.0, 6200.0)
		var amp := rng.randf_range(0.06, 0.2)
		var ph := 0.0
		for j in len_s:
			var i2 := start + j
			if i2 >= n:
				break
			ph += TAU * f / float(RATE)
			b[i2] += sin(ph) * amp * _env(j, len_s, 0.002, 4.0)
	return _wav(b)


## An indignant cat, leaving the hand. Rises, wobbles, falls away.
static func _meow() -> AudioStreamWAV:
	var n := int(0.5 * RATE)
	var b := _buf(0.5)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f: float = 540.0 + 380.0 * sin(PI * pow(t, 0.8)) + 26.0 * sin(TAU * 5.5 * t)
		ph += TAU * f / float(RATE)
		var e: float = _env(i, n, 0.06, 1.6)
		# a couple of harmonics give it a throat instead of a whistle
		b[i] = (sin(ph) * 0.6 + sin(ph * 2.0) * 0.26 + sin(ph * 3.0) * 0.1) * e * 0.62
	return _wav(b)


## The same cat, arriving. All claws.
static func _screech() -> AudioStreamWAV:
	var n := int(0.42 * RATE)
	var b := _buf(0.42)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var ph := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f: float = lerpf(1150.0, 1760.0, sqrt(t)) + 90.0 * sin(TAU * 17.0 * t)
		ph += TAU * f / float(RATE)
		var saw: float = fmod(ph / TAU, 1.0) * 2.0 - 1.0   # rougher than a sine
		var e: float = _env(i, n, 0.01, 2.2)
		b[i] = (saw * 0.5 + rng.randf_range(-1.0, 1.0) * 0.22) * e * 0.55
	return _wav(b)


## A baby, delighted to be airborne. Four rising chirps.
static func _giggle() -> AudioStreamWAV:
	var n := int(0.62 * RATE)
	var b := _buf(0.62)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(n)
		var chirp: float = fmod(t * 4.0, 1.0)
		var f: float = (700.0 + 300.0 * t) * (1.0 + 0.35 * chirp)
		ph += TAU * f / float(RATE)
		var pulse: float = pow(1.0 - chirp, 1.8)
		var e: float = _env(i, n, 0.02, 1.2)
		b[i] = (sin(ph) * 0.7 + sin(ph * 2.0) * 0.2) * pulse * e * 0.5
	return _wav(b)


## ...and landing. Rubber, not bone: this is a game about robots.
static func _boing() -> AudioStreamWAV:
	var n := int(0.4 * RATE)
	var b := _buf(0.4)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f: float = lerpf(760.0, 165.0, pow(t, 0.55)) * (1.0 + 0.14 * sin(TAU * 12.0 * t))
		ph += TAU * f / float(RATE)
		b[i] = sin(ph) * _env(i, n, 0.006, 2.4) * 0.6
	return _wav(b)


## Something dropped hits the dirt.
static func _clatter() -> AudioStreamWAV:
	var n := int(0.18 * RATE)
	var b := _buf(0.18)
	var rng := RandomNumberGenerator.new()
	rng.seed = 83
	var ph := 0.0
	for i in n:
		ph += TAU * 320.0 / float(RATE)
		b[i] = (rng.randf_range(-1.0, 1.0) * 0.6 + sin(ph) * 0.4) * _env(i, n, 0.002, 9.0) * 0.45
	_lowpass(b, 0.45)
	return _wav(b)


## A robot going down for good: the power falling out of it.
static func _death() -> AudioStreamWAV:
	var n := int(0.8 * RATE)
	var b := _buf(0.8)
	var ph := 0.0
	var ph2 := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f: float = lerpf(430.0, 62.0, pow(t, 0.75))
		ph += TAU * f / float(RATE)
		ph2 += TAU * f * 1.48 / float(RATE)
		var e: float = _env(i, n, 0.01, 1.5)
		b[i] = (sin(ph) * 0.6 + sin(ph2) * 0.25) * e * 0.55
	# it hits the floor at the end
	var tail := int(0.18 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 97
	for j in tail:
		var i2 := n - tail + j
		b[i2] += rng.randf_range(-1.0, 1.0) * _env(j, tail, 0.01, 6.0) * 0.3
	return _wav(b)


## The winners, pleased with themselves. A swell of filtered noise reads as a crowd.
static func _cheer() -> AudioStreamWAV:
	var n := int(1.4 * RATE)
	var b := _buf(1.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	for i in n:
		b[i] = rng.randf_range(-1.0, 1.0)
	_lowpass(b, 0.22)
	for i in n:
		var t := float(i) / float(n)
		var swell: float = pow(sin(PI * clampf(t * 1.15, 0.0, 1.0)), 1.3)
		b[i] *= swell * 0.5 * (1.0 + 0.2 * sin(TAU * 7.0 * t))
	return _wav(b)


## Picking something up.
static func _pickup() -> AudioStreamWAV:
	var n := int(0.1 * RATE)
	var b := _buf(0.1)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(n)
		ph += TAU * lerpf(620.0, 940.0, t) / float(RATE)
		b[i] = sin(ph) * _env(i, n, 0.01, 3.0) * 0.32
	return _wav(b)
