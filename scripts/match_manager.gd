class_name MatchManager
extends Node
## Spawns teams + rocks, runs the clock, tallies stats, decides the winner.

signal match_started(match_index: int)
signal match_ended(result: Dictionary)
signal celebration_finished(match_index: int)
signal dance_started(match_index: int)

const TEAM_SIZE := 5
const MATCH_TIME := 150.0   # only the headless sims are capped (time_limit); a real match runs until a team is gone
const ARENA_HALF := 20.0
const ROCKS_PER_ROBOT := 0.5   # (unused now) ~1 rock per 2 robots
## The armoury, scattered at the start. Counts are editable in the HUD.
var loadout := {"rock": 3, "bat": 2, "knife": 2, "sword": 1, "spear": 2, "bottle": 2, "cat": 1, "baby": 1}
const TEAM_NAMES := ["Red", "Blue"]
const TEAM_COLORS := [Color(0.9, 0.3, 0.25), Color(0.25, 0.5, 0.95)]
## Every kind that can be scattered at the start, in the order the armoury row shows them.
const KIND_ORDER: Array[String] = ["rock", "bat", "knife", "sword", "spear", "bottle", "cat", "baby"]

var world: Node3D
var arena: Arena
var sfx: Sfx = null
var team_personalities: Array[Personality] = [Personality.preset("Slinger"), Personality.preset("Brawler")]
var team_preset_names: Array[String] = ["Slinger", "Brawler"]
## What each team is made of, and the per-robot overrides. An entry of "" in the two override
## arrays means "whatever the team is set to", which is how the whole-team pickers stay
## meaningful after you have fiddled with one robot.
var team_types: Array[RobotType] = [RobotType.preset("Even"), RobotType.preset("Even")]
var team_type_names: Array[String] = ["Even", "Even"]
var player_personality := [["", "", "", "", ""], ["", "", "", "", ""]]
var player_type := [["", "", "", "", ""], ["", "", "", "", ""]]
var robots: Array[Robot] = []
var items: Array[Weapon] = []
var time_left := INF
var time_limit := -1.0  # <= 0: no limit
var elapsed := 0.0
var running := false
var match_index := 0
var stats := {}
var rng := RandomNumberGenerator.new()
var _alive_cache: Array[Robot] = []
var _cache_frame := -1
var robot_stats := {}
var dance_clock := 0.0  # shared beat for the winners' dance
# victory celebration: "" (none) -> gather -> dance -> teabag -> done
const GATHER_CAP := 7.0
const TEABAG_CAP := 40.0
var celebration_phase := ""
var _phase_timer := 0.0
var _celebrants: Array[Robot] = []


func start_match(seed_value: int = -1) -> void:
	clear()
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	match_index += 1
	time_left = time_limit if time_limit > 0.0 else INF
	elapsed = 0.0
	stats = _fresh_stats()
	robot_stats = {}

	# interleave + shuffle spawn order so neither team gets first-strike from tree order
	var slots := []
	for t in 2:
		for i in TEAM_SIZE:
			slots.append([t, i])
	for k in range(slots.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp = slots[k]
		slots[k] = slots[j]
		slots[j] = tmp
	for slot in slots:
		var t: int = slot[0]
		var i: int = slot[1]
		if true:
			var r := Robot.new()
			r.team = t
			r.team_color = TEAM_COLORS[t]
			r.robot_name = "%s%d" % [TEAM_NAMES[t][0], i + 1]
			# a robot follows its team unless it has been given its own personality or type
			var pname: String = String(player_personality[t][i])
			if pname == "":
				r.personality = team_personalities[t].jittered(rng, 0.08)
			else:
				r.personality = Personality.preset(pname).jittered(rng, 0.05)
			var tname: String = String(player_type[t][i])
			if tname == "":
				r.robot_type = team_types[t].jittered(rng, 0.02)
				r.type_name = team_type_names[t]
			else:
				r.robot_type = RobotType.preset(tname).jittered(rng, 0.02)
				r.type_name = tname
			r.manager = self
			r.rng = RandomNumberGenerator.new()
			r.rng.seed = rng.randi()
			var x := -15.0 if t == 0 else 15.0
			var z := lerpf(-8.0, 8.0, float(i) / float(maxi(TEAM_SIZE - 1, 1)))
			r.position = Vector3(x + rng.randf_range(-1.5, 1.5), 0.0, z)
			r.rotation.y = PI * 0.5 if t == 0 else -PI * 0.5
			r.damaged.connect(_on_damaged)
			r.died.connect(_on_died)
			r.threw.connect(_on_threw)
			r.punched.connect(_on_punched)
			r.kicked.connect(_on_kicked)
			r.swung.connect(_on_swung)
			r.dropped.connect(_on_dropped)
			r.knocked_down.connect(_on_knocked_down)
			world.add_child(r)
			robots.append(r)
			robot_stats[r.robot_name] = {"name": r.robot_name, "team": t, "preset": (pname if pname != "" else team_preset_names[t]), "type": r.type_name,
				"dmg_rock": 0.0, "dmg_punch": 0.0, "dmg_kick": 0.0, "dmg_melee": 0.0, "dmg_taken": 0.0, "throws": 0, "rock_hits": 0,
				"punches": 0, "punch_hits": 0, "kicks": 0, "kick_hits": 0, "swings": 0, "swing_hits": 0, "drops": 0, "knockdowns": 0, "kills": 0, "hp": r.hp, "alive": true}

	var wanted: Array = []
	var kinds := {"rock": Weapon.Kind.ROCK, "bat": Weapon.Kind.BAT, "knife": Weapon.Kind.KNIFE, "sword": Weapon.Kind.SWORD,
		"spear": Weapon.Kind.SPEAR, "bottle": Weapon.Kind.BOTTLE, "cat": Weapon.Kind.CAT, "baby": Weapon.Kind.BABY}
	for k in KIND_ORDER:
		for i in int(loadout.get(k, 0)):
			wanted.append(kinds[k])
	var tries := 0
	while wanted.size() > 0 and tries < 400:
		tries += 1
		var x := rng.randf_range(-11.0, 11.0)
		var z := rng.randf_range(-16.0, 16.0)
		if arena != null and not arena.is_clear(x, z):
			continue
		var rk := Weapon.new()
		rk.manager = self
		rk.kind = wanted.pop_back()
		if rk.kind == Weapon.Kind.ROCK:
			rk.mass_kg = [1.2, 2.0, 2.0, 3.2][rng.randi_range(0, 3)]  # pebbles, stones and a lump
		rk.position = Vector3(x, 0.6, z)
		world.add_child(rk)
		items.append(rk)

	running = true
	dance_clock = 0.0
	celebration_phase = ""
	_celebrants.clear()
	match_started.emit(match_index)


func clear() -> void:
	running = false
	celebration_phase = ""
	_celebrants.clear()
	for r in robots:
		r.cleanup()
		r.queue_free()
	for rk in items:
		rk.queue_free()
	robots.clear()
	items.clear()
	_cache_frame = -1


func _fresh_stats() -> Dictionary:
	return {
		"damage": [{"rock": 0.0, "punch": 0.0, "kick": 0.0, "melee": 0.0}, {"rock": 0.0, "punch": 0.0, "kick": 0.0, "melee": 0.0}],
		"swings": [0, 0],
		"swing_hits": [0, 0],
		"drops": [0, 0],
		"kicks": [0, 0],
		"kick_hits": [0, 0],
		"throws": [0, 0],
		"rock_hits": [0, 0],
		"punches": [0, 0],
		"punch_hits": [0, 0],
		"kills": [0, 0],
		"friendly_fire": [0.0, 0.0],
		"own_goals": [0, 0],
		"knockdowns": [0, 0],
		"hitbox_hist": {},   # hitboxes struck per rock hit -> count
	}


func alive_robots() -> Array[Robot]:
	var f := Engine.get_physics_frames()
	if f != _cache_frame:
		_cache_frame = f
		_alive_cache = []
		for r in robots:
			if r.alive:
				_alive_cache.append(r)
	return _alive_cache


func alive_count(team: int) -> int:
	var n := 0
	for r in robots:
		if r.alive and r.team == team:
			n += 1
	return n


func team_hp(team: int) -> float:
	var s := 0.0
	for r in robots:
		if r.team == team:
			s += r.hp
	return s


## Types change how big a robot's HP pool is, so "team HP left" needs the team's own total
## rather than five times the reference constant.
func team_max_hp(team: int) -> float:
	var s := 0.0
	for r in robots:
		if r.team == team:
			s += r.max_hp
	return maxf(s, 1.0)


func _physics_process(delta: float) -> void:
	if not running:
		dance_clock += delta
		_run_celebration(delta)
		return
	elapsed += delta
	time_left -= delta
	if alive_count(0) == 0 or alive_count(1) == 0:
		end_match("elimination")
	elif time_left <= 0.0:
		time_left = 0.0
		end_match("time")


func end_match(reason: String) -> void:
	if not running:
		return
	running = false
	_cache_frame = -1
	var a0 := alive_count(0)
	var a1 := alive_count(1)
	var hp0 := team_hp(0)
	var hp1 := team_hp(1)
	var winner := -1
	if a0 > 0 and a1 == 0:
		winner = 0
	elif a1 > 0 and a0 == 0:
		winner = 1
	elif hp0 != hp1:
		winner = 0 if hp0 > hp1 else 1
	if OS.has_environment("RBDBG"):
		for r in robots:
			if r.alive:
				var e := r._nearest_enemy()
				print("    %s hp=%d act=%s rock=%s edist=%.1f pos=%s" % [r.robot_name, int(r.hp), r.action, r.held != null, r._flat_dist(e.global_position) if e else -1.0, r.global_position])
	var per_robot := []
	for r in robots:
		var rs: Dictionary = robot_stats[r.robot_name]
		rs["hp"] = r.hp
		rs["max_hp"] = r.max_hp
		rs["alive"] = r.alive
		per_robot.append(rs.duplicate())
	per_robot.sort_custom(func(a, b): return a["team"] < b["team"] if a["team"] != b["team"] else a["name"] < b["name"])
	var result := {
		"robots": per_robot,
		"match": match_index,
		"winner": winner,
		"winner_name": TEAM_NAMES[winner] if winner >= 0 else "Draw",
		"reason": reason,
		"duration": elapsed,
		"alive": [a0, a1],
		"hp": [hp0, hp1],
		"max_hp": [team_max_hp(0), team_max_hp(1)],
		"presets": team_preset_names.duplicate(),
		"types": team_type_names.duplicate(),
		"stats": stats.duplicate(true),
	}
	if winner >= 0:
		_begin_celebration(winner)
	else:
		celebration_phase = "done"
		_phase_timer = 0.0
	match_ended.emit(result)


## Winners jog to a line in front of the centre block, dance together, then the fallen
## enemies are shared out between them and each winner goes and squats over his share,
## then pees on it (every corpse gets it at least once). Then the celebration is done.
func _begin_celebration(winner: int) -> void:
	_celebrants.clear()
	for r in robots:
		if r.alive and r.team == winner:
			_celebrants.append(r)
	var corpses: Array[Robot] = []
	for r in robots:
		if not r.alive and r.team != winner:
			corpses.append(r)
	# ... nearest to the formation first, so the walk is short
	corpses.sort_custom(func(a: Robot, b: Robot): return a.global_position.length_squared() < b.global_position.length_squared())
	var n := _celebrants.size()
	var shares: Array = []
	for i in n:
		var order: Array[Robot] = []
		shares.append(order)
	var m := maxi(n, corpses.size())
	for k in m:
		if corpses.is_empty():
			break
		shares[k % n].append(corpses[k % corpses.size()])
	for i in n:
		var spot := Vector3((float(i) - float(n - 1) * 0.5) * 1.8, 0.0, 4.0)
		_celebrants[i].cheer(spot, shares[i])
	celebration_phase = "gather"
	_phase_timer = 0.0
	dance_clock = 0.0


func _run_celebration(delta: float) -> void:
	if celebration_phase == "" or celebration_phase == "done":
		return
	_phase_timer += delta
	var before := celebration_phase
	match celebration_phase:
		"gather":
			var all_there := true
			for r in _celebrants:
				if r.alive and not r.at_spot:
					all_there = false
					break
			if all_there or _phase_timer >= GATHER_CAP:
				celebration_phase = "dance"
				_phase_timer = 0.0
				dance_clock = 0.0
				dance_started.emit(match_index)
		"dance":
			if _phase_timer >= Robot.DANCE_TIME:
				celebration_phase = "teabag"
				_phase_timer = 0.0
		"teabag":
			var finished := true
			for r in _celebrants:
				if r.alive and not r.teabag_done():
					finished = false
					break
			if finished or _phase_timer >= TEABAG_CAP:
				celebration_phase = "done"
				_phase_timer = 0.0
				celebration_finished.emit(match_index)
	if celebration_phase != before and OS.has_environment("RBCELEB"):
		print("celebration: %s -> %s at t=%.1f" % [before, celebration_phase, dance_clock])


# ---------------------------------------------------------------- stat hooks

func _on_damaged(robot: Robot, amount: float, source: String, attacker: Robot, hitbox_count: int) -> void:
	if attacker == null:
		return
	var t := attacker.team
	if robot.team == t:
		stats["friendly_fire"][t] += amount
		robot_stats[robot.robot_name]["dmg_taken"] += amount
		if robot.hp <= 0.0 and robot.alive:
			stats["own_goals"][t] += 1  # killed by a teammate's rock
		return  # own goal: not credited as damage dealt
	stats["damage"][t][source] += amount
	robot_stats[robot.robot_name]["dmg_taken"] += amount
	var a: Dictionary = robot_stats[attacker.robot_name]
	if source == "rock":
		stats["rock_hits"][t] += 1
		a["rock_hits"] += 1
		a["dmg_rock"] += amount
		var h: Dictionary = stats["hitbox_hist"]
		h[hitbox_count] = int(h.get(hitbox_count, 0)) + 1
	elif source == "kick":
		a["dmg_kick"] += amount
	elif source == "melee":
		a["dmg_melee"] += amount
	else:
		a["dmg_punch"] += amount
	if robot.hp <= 0.0 and robot.alive:  # hp is already reduced; _die() follows this signal
		a["kills"] += 1


func _on_died(robot: Robot) -> void:
	stats["kills"][1 - robot.team] += 1


func _on_threw(robot: Robot) -> void:
	stats["throws"][robot.team] += 1
	robot_stats[robot.robot_name]["throws"] += 1


func _on_punched(robot: Robot, landed: bool) -> void:
	stats["punches"][robot.team] += 1
	robot_stats[robot.robot_name]["punches"] += 1
	if landed:
		stats["punch_hits"][robot.team] += 1
		robot_stats[robot.robot_name]["punch_hits"] += 1


func _on_kicked(robot: Robot, landed: bool) -> void:
	stats["kicks"][robot.team] += 1
	robot_stats[robot.robot_name]["kicks"] += 1
	if landed:
		stats["kick_hits"][robot.team] += 1
		robot_stats[robot.robot_name]["kick_hits"] += 1


func _on_swung(robot: Robot, landed: bool, _kind: String) -> void:
	stats["swings"][robot.team] += 1
	robot_stats[robot.robot_name]["swings"] += 1
	if landed:
		stats["swing_hits"][robot.team] += 1
		robot_stats[robot.robot_name]["swing_hits"] += 1


func _on_dropped(robot: Robot, _item: Weapon) -> void:
	stats["drops"][robot.team] += 1
	robot_stats[robot.robot_name]["drops"] += 1


func _on_knocked_down(_robot: Robot, by: Robot, _source: String) -> void:
	if by == null:
		return
	stats["knockdowns"][by.team] += 1
	robot_stats[by.robot_name]["knockdowns"] += 1
