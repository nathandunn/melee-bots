class_name Weapon
extends RigidBody3D
## Anything a robot can pick up: a rock to throw, a bat, knife, sword or spear to swing
## (knives, spears and bottles can be thrown too), or one of the two live ones - a cat and a
## baby, which are thrown and nothing else. Idle on the ground -> held -> (thrown -> spent) ->
## idle. A knocked-down robot drops whatever he holds, and it lies there for anyone.

enum State { IDLE, HELD, THROWN, SPENT }
enum Kind { ROCK, BAT, KNIFE, SWORD, SPEAR, BOTTLE, CAT, BABY }

## Melee stats: reach (m), wind-up (s), cooldown (s), damage as a fraction of max HP at full
## quality, knockdown chance at full quality. Rocks, cats and babies are thrown only.
##
## Thrown things share one damage model (mass x relative speed, see _on_impact_area) with a
## per-kind multiplier on top, because physics alone would have a 4.5 kg cat outscoring a
## sword: `hit` scales the damage, `floors` overrides the knockdown roll, `shatters` means the
## thing is gone after one good hit, and `live` means it gets up and runs off afterwards.
const DATA := {
	Kind.ROCK:   {"name": "rock",   "melee": false, "throwable": true,  "mass": 2.0},
	Kind.BAT:    {"name": "bat",    "melee": true,  "throwable": false, "mass": 1.2, "reach": 2.3, "windup": 0.35, "cooldown": 1.0,  "dmg": 0.25, "kd": 0.85},
	Kind.KNIFE:  {"name": "knife",  "melee": true,  "throwable": true,  "mass": 0.4, "reach": 1.6, "windup": 0.12, "cooldown": 0.45, "dmg": 0.14, "kd": 0.35},
	Kind.SWORD:  {"name": "sword",  "melee": true,  "throwable": false, "mass": 1.5, "reach": 2.4, "windup": 0.3,  "cooldown": 0.9,  "dmg": 0.32, "kd": 0.6},
	Kind.SPEAR:  {"name": "spear",  "melee": true,  "throwable": true,  "mass": 1.8, "reach": 3.2, "windup": 0.4,  "cooldown": 1.1,  "dmg": 0.22, "kd": 0.55},
	# a pub weapon: quick, nasty once, and then it is a handful of glass
	Kind.BOTTLE: {"name": "bottle", "melee": true,  "throwable": true,  "mass": 0.8, "reach": 1.5, "windup": 0.16, "cooldown": 0.5,  "dmg": 0.18, "kd": 0.5, "hit": 0.8, "shatters": true},
	# all claws and indignation: lands hard, floors anyone, then leaves
	Kind.CAT:    {"name": "cat",    "melee": false, "throwable": true,  "mass": 4.5, "hit": 0.7, "floors": true, "live": true},
	# heavy, bouncy, and entirely unharmed by any of this; knocks a robot flat on comedy alone
	Kind.BABY:   {"name": "baby",   "melee": false, "throwable": true,  "mass": 3.5, "hit": 0.28, "floors": true, "live": true},
}

## What each one is worth to an unarmed robot looking for something to hold, and the line the
## HUD shows beside it in the armoury.
const BLURB := {
	"rock": "Thrown. Three sizes; always floors what it hits",
	"bat": "Reach 2.3 m, slow swing, floors almost every time",
	"knife": "Quickest wind-up in the game; can be thrown",
	"sword": "Hits hardest of anything you can swing",
	"spear": "Longest reach; can be thrown",
	"bottle": "Fast and mean - but it shatters on the first good hit",
	"cat": "Thrown only. Claws, always floors, then runs off to be picked up again",
	"baby": "Thrown only. Barely hurts, floors anyone, bounces, giggles",
}

var kind: Kind = Kind.ROCK
var _scamper := 0.0        # a thrown cat or baby, getting itself clear afterwards
var _scamper_dir := Vector3.ZERO
var broken := false

const SPEED := 18.0          # 3x robot speed
const MAX_DAMAGE_FRAC := 0.5   # a direct hit (FULL_HITBOXES parts struck) takes half of max HP
const FULL_HITBOXES := 4
const BASE_RADIUS := 0.3       # for a 2 kg rock; radius scales with the cube root of mass
const KE_REF := 324.0           # kinetic energy of a 2 kg rock at 18 m/s - a 'full' hit
const FLIGHT_GRAVITY := 0.35 # lofted throw so 18 m/s reaches ~20 m
const MAX_AIRTIME := 3.0
const SPLASH_RADIUS := 0.78  # hitbox centres within this of the rock centre count as struck

var mass_kg := 2.0
var radius := BASE_RADIUS

const LAYER_WORLD := 1
const LAYER_ROBOTS := 2
const LAYER_ITEMS := 4
const LAYER_HITBOXES := 8

var state: State = State.IDLE
var thrower: Robot = null
var claimed_by: Robot = null
var manager = null
var impact: Area3D
var airtime := 0.0
var _pending := false
var _pending_origin := Vector3.ZERO
var _pending_vel := Vector3.ZERO
var _mesh: MeshInstance3D


func _ready() -> void:
	if kind != Kind.ROCK:
		mass_kg = float(DATA[kind]["mass"])
	mass = mass_kg
	if kind == Kind.ROCK:
		radius = BASE_RADIUS * pow(mass_kg / 2.0, 1.0 / 3.0)
	elif kind == Kind.CAT:
		radius = 0.3
	elif kind == Kind.BABY:
		radius = 0.28
	elif kind == Kind.BOTTLE:
		radius = 0.14
	else:
		radius = 0.25
	collision_layer = LAYER_ITEMS
	collision_mask = LAYER_WORLD | LAYER_ROBOTS
	contact_monitor = true
	max_contacts_reported = 4
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	can_sleep = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.9
	physics_material_override = pm

	_mesh = MeshInstance3D.new()
	var cs := CollisionShape3D.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	match kind:
		Kind.ROCK:
			var sm := SphereMesh.new()
			sm.radius = radius
			sm.height = radius * 2.0
			sm.radial_segments = 10
			sm.rings = 6
			_mesh.mesh = sm
			mat.albedo_color = Color(0.55, 0.53, 0.5)
			_mesh.scale = Vector3(1.0, 0.85, 1.1)
			var sh := SphereShape3D.new()
			sh.radius = radius
			cs.shape = sh
		Kind.BAT:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.07
			cm.bottom_radius = 0.045
			cm.height = 0.9
			_mesh.mesh = cm
			mat.albedo_color = Color(0.6, 0.42, 0.22)
			var sh := CapsuleShape3D.new()
			sh.radius = 0.07
			sh.height = 0.9
			cs.shape = sh
		Kind.KNIFE:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.05, 0.42, 0.015)
			_mesh.mesh = bm
			mat.albedo_color = Color(0.8, 0.82, 0.85)
			mat.metallic = 0.8
			mat.roughness = 0.3
			var sh := BoxShape3D.new()
			sh.size = Vector3(0.06, 0.42, 0.04)
			cs.shape = sh
		Kind.SWORD:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.07, 1.1, 0.02)
			_mesh.mesh = bm
			mat.albedo_color = Color(0.85, 0.87, 0.9)
			mat.metallic = 0.9
			mat.roughness = 0.25
			var guard := MeshInstance3D.new()
			var gm := BoxMesh.new()
			gm.size = Vector3(0.3, 0.04, 0.06)
			guard.mesh = gm
			var gmat := StandardMaterial3D.new()
			gmat.albedo_color = Color(0.5, 0.4, 0.2)
			guard.material_override = gmat
			guard.position = Vector3(0, -0.4, 0)
			_mesh.add_child(guard)
			var sh := BoxShape3D.new()
			sh.size = Vector3(0.1, 1.1, 0.06)
			cs.shape = sh
		Kind.SPEAR:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.025
			cm.bottom_radius = 0.025
			cm.height = 2.0
			_mesh.mesh = cm
			mat.albedo_color = Color(0.55, 0.4, 0.25)
			var tip := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.0
			tm.bottom_radius = 0.05
			tm.height = 0.25
			tip.mesh = tm
			var tmat := StandardMaterial3D.new()
			tmat.albedo_color = Color(0.85, 0.85, 0.9)
			tmat.metallic = 0.9
			tip.material_override = tmat
			tip.position = Vector3(0, 1.1, 0)
			_mesh.add_child(tip)
			var sh := CapsuleShape3D.new()
			sh.radius = 0.04
			sh.height = 2.2
			cs.shape = sh
		Kind.BOTTLE:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.035
			cm.bottom_radius = 0.075
			cm.height = 0.34
			_mesh.mesh = cm
			mat.albedo_color = Color(0.25, 0.55, 0.32, 0.72)   # brown-green glass
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.15
			mat.metallic_specular = 0.9
			var neck := MeshInstance3D.new()
			var nm := CylinderMesh.new()
			nm.top_radius = 0.032
			nm.bottom_radius = 0.032
			nm.height = 0.16
			neck.mesh = nm
			neck.material_override = mat
			neck.position = Vector3(0, 0.24, 0)
			_mesh.add_child(neck)
			var sh := CapsuleShape3D.new()
			sh.radius = 0.08
			sh.height = 0.46
			cs.shape = sh
		Kind.CAT:
			# a ginger loaf with ears and a tail. Cartoon all the way down: this is a game
			# where robots pee on each other, and nothing here is meant to look real.
			var bm := SphereMesh.new()
			bm.radius = 0.2
			bm.height = 0.4
			bm.radial_segments = 12
			bm.rings = 7
			_mesh.mesh = bm
			_mesh.scale = Vector3(1.0, 0.82, 1.45)
			mat.albedo_color = Color(0.86, 0.55, 0.24)
			var head := MeshInstance3D.new()
			var hm := SphereMesh.new()
			hm.radius = 0.135
			hm.height = 0.27
			hm.radial_segments = 10
			hm.rings = 6
			head.mesh = hm
			head.material_override = mat
			head.position = Vector3(0, 0.05, -0.3)
			_mesh.add_child(head)
			for side in [-1.0, 1.0]:
				var ear := MeshInstance3D.new()
				var em := CylinderMesh.new()
				em.top_radius = 0.0
				em.bottom_radius = 0.06
				em.height = 0.13
				ear.mesh = em
				ear.material_override = mat
				ear.position = Vector3(side * 0.08, 0.16, -0.3)
				_mesh.add_child(ear)
			var tail := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.025
			tm.bottom_radius = 0.035
			tm.height = 0.34
			tail.mesh = tm
			tail.material_override = mat
			tail.position = Vector3(0, 0.12, 0.3)
			tail.rotation = Vector3(deg_to_rad(52.0), 0, 0)
			_mesh.add_child(tail)
			var sh := SphereShape3D.new()
			sh.radius = 0.22
			cs.shape = sh
		Kind.BABY:
			# a swaddled bundle with a bobble hat - a doll, drawn the way the robots are
			var bm := CapsuleMesh.new()
			bm.radius = 0.15
			bm.height = 0.46
			bm.radial_segments = 12
			bm.rings = 5
			_mesh.mesh = bm
			mat.albedo_color = Color(0.95, 0.85, 0.42)         # a yellow blanket
			var head := MeshInstance3D.new()
			var hm := SphereMesh.new()
			hm.radius = 0.125
			hm.height = 0.25
			hm.radial_segments = 10
			hm.rings = 6
			head.mesh = hm
			var skin := StandardMaterial3D.new()
			skin.albedo_color = Color(0.98, 0.82, 0.68)
			skin.roughness = 1.0
			head.material_override = skin
			head.position = Vector3(0, 0.25, 0)
			_mesh.add_child(head)
			var hat := MeshInstance3D.new()
			var htm := SphereMesh.new()
			htm.radius = 0.07
			htm.height = 0.14
			htm.radial_segments = 8
			htm.rings = 5
			hat.mesh = htm
			var hatmat := StandardMaterial3D.new()
			hatmat.albedo_color = Color(0.85, 0.35, 0.45)
			hatmat.roughness = 1.0
			hat.material_override = hatmat
			hat.position = Vector3(0, 0.37, 0)
			_mesh.add_child(hat)
			var sh := CapsuleShape3D.new()
			sh.radius = 0.16
			sh.height = 0.62
			cs.shape = sh
	_mesh.material_override = mat
	add_child(_mesh)
	add_child(cs)
	if kind == Kind.BABY:
		# a baby bounces; that is the joke and the whole of its physics
		var pmb := PhysicsMaterial.new()
		pmb.bounce = 0.72
		pmb.friction = 0.5
		physics_material_override = pmb
	if kind != Kind.ROCK and not _stands_upright():
		# lie flat on the ground when idle
		rotation.x = PI * 0.5

	impact = Area3D.new()
	impact.collision_layer = 0
	impact.collision_mask = LAYER_HITBOXES
	impact.monitoring = true
	impact.monitorable = false
	var ics := CollisionShape3D.new()
	var ish := SphereShape3D.new()
	ish.radius = radius + 0.4
	ics.shape = ish
	impact.add_child(ics)
	add_child(impact)
	impact.area_entered.connect(_on_impact_area)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if state == State.THROWN:
		airtime += delta
		if airtime > MAX_AIRTIME:
			_spend()
	if _scamper > 0.0:
		# a cat or a baby that has been thrown does not simply lie there: it scrabbles a few
		# metres off under its own steam, so the thing is somewhere new next time anyone wants it
		_scamper -= delta
		if not freeze:
			var v := linear_velocity
			v.x = _scamper_dir.x * 4.2
			v.z = _scamper_dir.z * 4.2
			linear_velocity = v
			angular_velocity = Vector3(0, 6.0 * signf(_scamper_dir.x + 0.01), 0)
		if _scamper <= 0.0:
			linear_velocity = Vector3(0, linear_velocity.y, 0)
	if state == State.THROWN or state == State.SPENT:
		if _scamper <= 0.0 and linear_velocity.length() < 2.5 and global_position.y < radius + 0.4:
			_settle()
	if global_position.y < -5.0:
		# fell through something; put it back
		global_position = Vector3(0, 1, 0)
		_settle()


## Rocks roll, blades lie flat - but a cat and a baby sit the right way up.
func _stands_upright() -> bool:
	return kind == Kind.CAT or kind == Kind.BABY


func is_live() -> bool:
	return bool(DATA[kind].get("live", false))


func shatters() -> bool:
	return bool(DATA[kind].get("shatters", false))


func hit_mult() -> float:
	return float(DATA[kind].get("hit", 1.0))


func always_floors() -> bool:
	return bool(DATA[kind].get("floors", false))


func _sfx(cue: String, pitch := 1.0, vol_db := 0.0) -> void:
	if manager != null and manager.sfx != null:
		manager.sfx.play(cue, global_position, pitch, vol_db)


## The bottle's whole career ends here: a burst of glass, and it is off the field. Whoever was
## holding it is left with nothing, which is exactly what a bottle is worth in a brawl.
func shatter() -> void:
	if broken:
		return
	broken = true
	_sfx("smash", randf_range(0.92, 1.12))
	if thrower != null and thrower.held == self:
		thrower.held = null
	state = State.SPENT
	if manager != null:
		manager.items.erase(self)
	var burst := CPUParticles3D.new()
	burst.emitting = true
	burst.one_shot = true
	burst.amount = 22
	burst.lifetime = 0.8
	burst.explosiveness = 1.0
	burst.direction = Vector3(0, 1, 0)
	burst.spread = 80.0
	burst.initial_velocity_min = 2.5
	burst.initial_velocity_max = 6.5
	burst.gravity = Vector3(0, -9.8, 0)
	burst.scale_amount_min = 0.35
	burst.scale_amount_max = 0.8
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.55, 0.85, 0.6, 0.85)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.emission_enabled = true
	pm.emission = Color(0.4, 0.8, 0.5)
	pm.emission_energy_multiplier = 0.4
	burst.material_override = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 0.02)
	burst.mesh = bm
	if manager != null and manager.world != null:
		manager.world.add_child(burst)
		burst.global_position = global_position + Vector3(0, 0.4, 0)
		burst.get_tree().create_timer(1.6).timeout.connect(burst.queue_free)
	queue_free()


func kind_name() -> String:
	return String(DATA[kind]["name"])


func is_melee() -> bool:
	return bool(DATA[kind]["melee"])


func is_throwable() -> bool:
	return bool(DATA[kind]["throwable"])


func stat(key: String) -> float:
	return float(DATA[kind].get(key, 0.0))


## Heavier rocks leave the hand slower; momentum is what they bring.
func throw_speed() -> float:
	return SPEED * clampf(sqrt(2.0 / mass_kg), 0.7, 1.2)


func is_free(for_robot: Robot = null) -> bool:
	if state != State.IDLE:
		return false
	return claimed_by == null or claimed_by == for_robot or not claimed_by.alive


func hold(r: Robot) -> void:
	state = State.HELD
	thrower = r
	claimed_by = null
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	impact.monitoring = false
	sleeping = false
	_scamper = 0.0
	_sfx("pickup", randf_range(0.9, 1.15), -6.0)


func launch(origin: Vector3, vel: Vector3, r: Robot) -> void:
	global_position = origin
	state = State.THROWN
	thrower = r
	airtime = 0.0
	_scamper = 0.0
	match kind:
		Kind.CAT:
			_sfx("meow", randf_range(0.9, 1.15))
		Kind.BABY:
			_sfx("giggle", randf_range(0.92, 1.1))
		_:
			_sfx("swing", randf_range(0.85, 1.2), -4.0)
	gravity_scale = FLIGHT_GRAVITY
	collision_layer = LAYER_ITEMS
	collision_mask = LAYER_WORLD | LAYER_ROBOTS
	freeze = false
	sleeping = false
	# velocity set inside _integrate_forces: setting it directly on a just-unfrozen body gets lost
	_pending = true
	_pending_origin = origin
	_pending_vel = vel
	impact.set_deferred("monitoring", true)


func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	if _pending:
		_pending = false
		st.transform = Transform3D(st.transform.basis if kind != Kind.ROCK and state == State.IDLE else Basis.IDENTITY, _pending_origin)
		st.linear_velocity = _pending_vel
		st.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8)) if state == State.THROWN else Vector3(0, randf_range(-3, 3), 0)


## Dropped - by a dying robot, or one knocked off his feet. It skitters a little way off.
func drop(shove: Vector3 = Vector3.ZERO) -> void:
	state = State.IDLE
	thrower = null
	claimed_by = null
	gravity_scale = 1.0
	collision_layer = LAYER_ITEMS
	collision_mask = LAYER_WORLD | LAYER_ROBOTS
	freeze = false
	sleeping = false
	impact.monitoring = false
	if kind != Kind.ROCK and not _stands_upright():
		rotation = Vector3(PI * 0.5, randf_range(0.0, TAU), 0.0)
	_sfx("clatter", randf_range(0.85, 1.2), -5.0)
	if kind == Kind.CAT:
		_sfx("meow", randf_range(1.05, 1.25), -3.0)   # put down, and unimpressed
	_pending = true
	_pending_origin = global_position + Vector3(0, 0.3, 0)
	_pending_vel = Vector3(randf_range(-2.5, 2.5), 2.5, randf_range(-2.5, 2.5)) + shove


func _spend() -> void:
	if state == State.THROWN:
		state = State.SPENT
		impact.set_deferred("monitoring", false)


func _settle() -> void:
	var was_flying := state == State.THROWN or state == State.SPENT
	state = State.IDLE
	thrower = null
	gravity_scale = 1.0
	impact.set_deferred("monitoring", false)
	if kind != Kind.ROCK and not _stands_upright():
		rotation.x = PI * 0.5
		rotation.z = 0.0
	elif _stands_upright():
		rotation = Vector3(0.0, rotation.y, 0.0)
	if was_flying and is_live():
		_start_scamper()


## A thrown cat lands, swears at everyone, and bolts. A thrown baby crawls off after it.
func _start_scamper() -> void:
	var away := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if away.length_squared() < 0.04:
		away = Vector3(1, 0, 0)
	_scamper_dir = away.normalized()
	_scamper = randf_range(0.5, 1.1) if kind == Kind.CAT else randf_range(0.25, 0.5)
	_sfx("meow" if kind == Kind.CAT else "giggle", randf_range(1.0, 1.2), -4.0)


func _on_body_entered(body: Node) -> void:
	if state != State.THROWN:
		return
	# Hitting the floor/walls/cover ends the dangerous phase. Hitting a robot body
	# without any hitbox overlap (edge case) also ends it.
	if body is StaticBody3D:
		_spend()


func _on_impact_area(area: Area3D) -> void:
	if state != State.THROWN or thrower == null:
		return
	if not area.has_meta("robot"):
		return
	var robot: Robot = area.get_meta("robot")
	if robot == null or robot == thrower or not robot.alive:
		return  # friendly fire is on: a rock does not care whose it is
	# Count every hitbox of this robot within the rock's splash radius; more parts struck = more damage.
	var count := 0
	for hb in robot.hitboxes:
		if hb.global_position.distance_to(global_position) < SPLASH_RADIUS:
			count += 1
	count = maxi(count, 1)
	var quality := minf(float(count), float(FULL_HITBOXES)) / float(FULL_HITBOXES)
	# physics decides the rest: the rock's mass and its speed RELATIVE to the robot.
	# Walking into a rock hurts more than being clipped while running with it.
	var rel_v := linear_velocity - robot.velocity
	var ke := 0.5 * mass_kg * rel_v.length_squared()
	var punch := clampf(ke / KE_REF, 0.0, 1.3)
	var dmg := Robot.MAX_HP * MAX_DAMAGE_FRAC * quality * punch * hit_mult() * thrower.dmg_mult
	if dmg < 1.0 and not always_floors():
		return  # a rock rolling over your foot is not a hit
	robot.take_damage(dmg, "rock", thrower, count)  # every thrown thing counts as a "rock" hit in the stats
	var impulse := rel_v * mass_kg * 1.4 + Vector3(0, 6.0 + 6.0 * punch, 0)
	var down := 0.7 + 1.3 * clampf(punch, 0.0, 1.0)
	if always_floors():
		# a cat to the face or a baby to the chest puts anyone on the floor, whatever the sums say
		down = maxf(down, 1.6)
		impulse += Vector3(0, 5.0, 0)
	robot.knock_down(down, thrower, "rock", impulse)
	match kind:
		Kind.CAT:
			_sfx("screech", randf_range(0.92, 1.1))
			linear_velocity = Vector3(-rel_v.x * 0.35, 5.0, -rel_v.z * 0.35)   # off it goes
			_spend()
			_start_scamper()
			return
		Kind.BABY:
			_sfx("boing", randf_range(0.9, 1.15))
			_sfx("giggle", randf_range(1.05, 1.2), -3.0)
			linear_velocity = Vector3(-rel_v.x * 0.55, 6.5, -rel_v.z * 0.55)   # and away it bounces
			_spend()
			return
		Kind.BOTTLE:
			shatter()
			return
		Kind.KNIFE, Kind.SPEAR:
			_sfx("clang", randf_range(0.95, 1.15))
		_:
			_sfx("bonk", randf_range(0.88, 1.15))
	linear_velocity *= 0.3
	_spend()
