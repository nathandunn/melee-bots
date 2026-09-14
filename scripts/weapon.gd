class_name Weapon
extends RigidBody3D
## Anything a robot can pick up: a rock to throw, or a bat, knife, sword or spear to swing
## (knives and spears can be thrown too). Idle on the ground -> held -> (thrown -> spent) -> idle.
## A knocked-down robot drops whatever he holds, and it lies there for anyone.

enum State { IDLE, HELD, THROWN, SPENT }
enum Kind { ROCK, BAT, KNIFE, SWORD, SPEAR }

## Melee stats: reach (m), wind-up (s), cooldown (s), damage as a fraction of max HP at full
## quality, knockdown chance at full quality. Rocks are thrown only.
const DATA := {
	Kind.ROCK:  {"name": "rock",  "melee": false, "throwable": true,  "mass": 2.0},
	Kind.BAT:   {"name": "bat",   "melee": true,  "throwable": false, "mass": 1.2, "reach": 2.3, "windup": 0.35, "cooldown": 1.0,  "dmg": 0.25, "kd": 0.85},
	Kind.KNIFE: {"name": "knife", "melee": true,  "throwable": true,  "mass": 0.4, "reach": 1.6, "windup": 0.12, "cooldown": 0.45, "dmg": 0.14, "kd": 0.35},
	Kind.SWORD: {"name": "sword", "melee": true,  "throwable": false, "mass": 1.5, "reach": 2.4, "windup": 0.3,  "cooldown": 0.9,  "dmg": 0.32, "kd": 0.6},
	Kind.SPEAR: {"name": "spear", "melee": true,  "throwable": true,  "mass": 1.8, "reach": 3.2, "windup": 0.4,  "cooldown": 1.1,  "dmg": 0.22, "kd": 0.55},
}

var kind: Kind = Kind.ROCK

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
	radius = BASE_RADIUS * pow(mass_kg / 2.0, 1.0 / 3.0) if kind == Kind.ROCK else 0.25
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
	_mesh.material_override = mat
	add_child(_mesh)
	add_child(cs)
	if kind != Kind.ROCK:
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
	if state == State.THROWN or state == State.SPENT:
		if linear_velocity.length() < 2.5 and global_position.y < radius + 0.4:
			_settle()
	if global_position.y < -5.0:
		# fell through something; put it back
		global_position = Vector3(0, 1, 0)
		_settle()


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


func launch(origin: Vector3, vel: Vector3, r: Robot) -> void:
	global_position = origin
	state = State.THROWN
	thrower = r
	airtime = 0.0
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
	if kind != Kind.ROCK:
		rotation = Vector3(PI * 0.5, randf_range(0.0, TAU), 0.0)
	_pending = true
	_pending_origin = global_position + Vector3(0, 0.3, 0)
	_pending_vel = Vector3(randf_range(-2.5, 2.5), 2.5, randf_range(-2.5, 2.5)) + shove


func _spend() -> void:
	if state == State.THROWN:
		state = State.SPENT
		impact.set_deferred("monitoring", false)


func _settle() -> void:
	state = State.IDLE
	thrower = null
	gravity_scale = 1.0
	impact.set_deferred("monitoring", false)
	if kind != Kind.ROCK:
		rotation.x = PI * 0.5
		rotation.z = 0.0


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
	var dmg := Robot.MAX_HP * MAX_DAMAGE_FRAC * quality * punch
	if dmg < 1.0:
		return  # a rock rolling over your foot is not a hit
	robot.take_damage(dmg, "rock", thrower, count)  # every thrown thing counts as a "rock" hit in the stats
	var impulse := rel_v * mass_kg * 1.4 + Vector3(0, 6.0 + 6.0 * punch, 0)
	robot.knock_down(0.7 + 1.3 * clampf(punch, 0.0, 1.0), thrower, "rock", impulse)
	linear_velocity *= 0.3
	_spend()
