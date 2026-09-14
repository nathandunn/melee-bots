class_name Personality
extends RefCounted
## A bag of 0..1 traits that shape a robot's utility scores. (Accuracy is not a trait: every
## robot throws and punches with the same skill, Robot.ACCURACY; only the choices differ.)
## Deliberately flat so it can be swapped for the sim-core schema later.

const TRAITS: Array[String] = ["aggression", "caution", "rock_love", "teamwork", "patience", "survival", "protect"]

const TRAIT_HELP := {
	"aggression": "Chase, punch, throw early",
	"caution": "Dodge rocks, kite when hurt",
	"rock_love": "Prefer rocks over fists",
	"teamwork": "Stick with the pack",
	"patience": "Hold position, wait for shots",
	"survival": "When hurt: back off, grab a rock, throw from range",
	"protect": "Guard mates: go for whoever is on them, stand over the fallen",
}

const PRESETS := {
	"Brawler":   {"aggression": 0.95, "caution": 0.15, "rock_love": 0.15, "teamwork": 0.40, "patience": 0.10, "survival": 0.10, "protect": 0.30},
	"Slinger":   {"aggression": 0.70, "caution": 0.55, "rock_love": 0.95, "teamwork": 0.40, "patience": 0.50, "survival": 0.55, "protect": 0.25},
	"Coward":    {"aggression": 0.20, "caution": 0.95, "rock_love": 0.70, "teamwork": 0.60, "patience": 0.80, "survival": 0.95, "protect": 0.05},
	"Tactician": {"aggression": 0.55, "caution": 0.60, "rock_love": 0.70, "teamwork": 0.90, "patience": 0.70, "survival": 0.70, "protect": 0.70},
	"Guardian":  {"aggression": 0.70, "caution": 0.35, "rock_love": 0.35, "teamwork": 0.85, "patience": 0.40, "survival": 0.25, "protect": 0.95},
	"Balanced":  {"aggression": 0.50, "caution": 0.50, "rock_love": 0.50, "teamwork": 0.50, "patience": 0.50, "survival": 0.50, "protect": 0.50},
}

var traits: Dictionary = {}


func _init(from: Dictionary = {}) -> void:
	for t in TRAITS:
		traits[t] = clampf(float(from.get(t, 0.5)), 0.0, 1.0)


static func preset(preset_name: String) -> Personality:
	if preset_name == "Random":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var d := {}
		for t in TRAITS:
			d[t] = rng.randf()
		return Personality.new(d)
	return Personality.new(PRESETS.get(preset_name, PRESETS["Balanced"]))


func get_trait(t: String) -> float:
	return float(traits.get(t, 0.5))


func set_trait(t: String, v: float) -> void:
	traits[t] = clampf(v, 0.0, 1.0)


func copy() -> Personality:
	return Personality.new(traits)


## Same personality with per-robot noise so a team of five isn't five clones.
func jittered(rng: RandomNumberGenerator, spread: float = 0.1) -> Personality:
	var d := {}
	for t in TRAITS:
		d[t] = clampf(get_trait(t) + rng.randf_range(-spread, spread), 0.0, 1.0)
	return Personality.new(d)


## Name of the closest preset (for labels).
func label() -> String:
	var best := "Custom"
	var best_d := 0.35
	for n in PRESETS:
		var d := 0.0
		for t in TRAITS:
			d += absf(get_trait(t) - float(PRESETS[n][t]))
		d /= TRAITS.size()
		if d < best_d:
			best_d = d
			best = n
	return best


func to_dict() -> Dictionary:
	return traits.duplicate()
