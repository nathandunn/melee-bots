class_name RobotType
extends RefCounted
## What a robot *is*, as against a Personality, which is how it behaves. Five properties that
## always add up to 1, so every type costs the same and picking a strength means paying for it
## somewhere else - the same budget idea as the builds in Dodgeball Bots.
##
## An even split (0.2 in everything) reproduces the original numbers exactly: 200 HP, 6 m/s,
## 0.7 accuracy, damage and wind-ups as designed. Everything else trades against that.

const PROPS: Array[String] = ["brawn", "speed", "grit", "reflex", "aim"]

const PROP_HELP := {
	"brawn": "Damage: punches, kicks, weapon blows, and how hard a throw leaves the hand",
	"speed": "How fast it moves around the arena",
	"grit": "Hit points, and how quickly it gets back up",
	"reflex": "Shorter wind-ups, faster reactions, spots and dodges more",
	"aim": "Throwing accuracy and how well it leads a moving target",
}

## The five presets, plus Even. Each adds up to 1.
const PRESETS := {
	"Even":    {"brawn": 0.20, "speed": 0.20, "grit": 0.20, "reflex": 0.20, "aim": 0.20},
	"Bruiser": {"brawn": 0.38, "speed": 0.15, "grit": 0.26, "reflex": 0.13, "aim": 0.08},
	"Runner":  {"brawn": 0.14, "speed": 0.40, "grit": 0.18, "reflex": 0.22, "aim": 0.06},
	"Tank":    {"brawn": 0.22, "speed": 0.09, "grit": 0.46, "reflex": 0.13, "aim": 0.10},
	"Sniper":  {"brawn": 0.14, "speed": 0.14, "grit": 0.18, "reflex": 0.14, "aim": 0.40},
	"Ghost":   {"brawn": 0.10, "speed": 0.26, "grit": 0.10, "reflex": 0.44, "aim": 0.10},
}

const TYPE_HELP := {
	"Even":    "No strengths, no holes - the reference build",
	"Bruiser": "Hits like a truck and can take one; slow and can't throw",
	"Runner":  "First to every weapon on the floor, glass jaw",
	"Tank":    "Soaks punishment and keeps coming; ponderous",
	"Sniper":  "Lands thrown things from across the arena; folds up close",
	"Ghost":   "Sees it coming and isn't there; no weight behind anything",
}

## Below an even share a property falls away gently rather than off a cliff, so a 0.1 is
## weak but not useless. Above it the return is linear.
const CURVE := 0.8
const EVEN := 0.2

var props: Dictionary = {}


func _init(from: Dictionary = {}) -> void:
	for p in PROPS:
		props[p] = maxf(float(from.get(p, EVEN)), 0.0)
	normalize()


static func preset(preset_name: String) -> RobotType:
	if preset_name == "Random":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var d := {}
		for p in PROPS:
			d[p] = rng.randf_range(0.04, 1.0)
		return RobotType.new(d)
	return RobotType.new(PRESETS.get(preset_name, PRESETS["Even"]))


func get_prop(p: String) -> float:
	return float(props.get(p, EVEN))


func set_prop(p: String, v: float) -> void:
	props[p] = clampf(v, 0.0, 1.0)


## Keep the budget honest: the five always add up to 1.
func normalize() -> void:
	var total := 0.0
	for p in PROPS:
		total += float(props[p])
	if total <= 0.0001:
		for p in PROPS:
			props[p] = EVEN
		return
	for p in PROPS:
		props[p] = float(props[p]) / total


## Set one property and take the difference out of (or give it back to) the others in
## proportion, so dragging one slider visibly moves the rest - the budget made obvious.
func set_and_rebalance(p: String, v: float) -> void:
	v = clampf(v, 0.0, 0.8)
	var rest := 1.0 - v
	var others_total := 0.0
	for q in PROPS:
		if q != p:
			others_total += float(props[q])
	if others_total <= 0.0001:
		for q in PROPS:
			props[q] = rest / float(PROPS.size() - 1)
	else:
		for q in PROPS:
			if q != p:
				props[q] = float(props[q]) / others_total * rest
	props[p] = v


## 0.2 (an even share) scores 1.0; more is better, less falls away on a curve.
func factor(p: String) -> float:
	var v := get_prop(p)
	if v >= EVEN:
		return 1.0 + (v - EVEN) / EVEN
	return pow(v / EVEN, CURVE)


func copy() -> RobotType:
	return RobotType.new(props)


## Per-robot noise so five of a type aren't five clones (personalities already do this).
func jittered(rng: RandomNumberGenerator, spread: float = 0.03) -> RobotType:
	var d := {}
	for p in PROPS:
		d[p] = maxf(get_prop(p) + rng.randf_range(-spread, spread), 0.02)
	return RobotType.new(d)


## Name of the closest preset, for labels.
func label() -> String:
	var best := "Custom"
	var best_d := 0.06
	for n in PRESETS:
		var d := 0.0
		for p in PROPS:
			d += absf(get_prop(p) - float(PRESETS[n][p]))
		d /= float(PROPS.size())
		if d < best_d:
			best_d = d
			best = n
	return best


func to_dict() -> Dictionary:
	return props.duplicate()
