class_name Robot
extends CharacterBody3D
## A blocky robot with six hitboxes (head, torso, 2 arms, 2 legs) and a utility-AI brain
## driven by a Personality. Faces -Z (Godot convention).

signal died(robot: Robot)
signal damaged(robot: Robot, amount: float, source: String, attacker: Robot, hitbox_count: int)
signal threw(robot: Robot)
signal punched(robot: Robot, landed: bool)
signal kicked(robot: Robot, landed: bool)
signal swung(robot: Robot, landed: bool, kind: String)
signal dropped(robot: Robot, item: Weapon)
signal knocked_down(robot: Robot, by: Robot, source: String)

const SPEED := 6.0
const MAX_HP := 200.0
const PUNCH_MAX_FRAC := 0.2         # best punch (PUNCH_FULL_HITBOXES parts) takes 20% of max HP
const PUNCH_FULL_HITBOXES := 3
const PUNCH_KNOCKDOWN_CHANCE := 0.5 # at full quality; scales down with a glancing hit
const PUNCH_KNOCKDOWN_TIME := 1.1
const PUNCH_FLOP_TIME := 0.55       # a landed punch that doesn't floor you still sends you sprawling
const ROCK_KNOCKDOWN_TIME := 1.8    # every rock hit floors you
const DANCE_TIME := 2.0
const TEABAG_PERIOD := 0.55        # one squat
const TEABAG_REPS := 4             # squats per corpse
const TEABAG_DEPTH := 0.62
const PEE_TIME := 2.6              # after the squats, the final insult
const RECOVER_GRACE := 0.4          # can't be floored again right after getting up
const PUNCH_COOLDOWN := 0.6         # 4x faster than a throw
const PUNCH_REACH := 1.7
const PUNCH_WINDUP := 0.22          # seen coming: the wind-up before the fist lands
const KICK_REACH := 2.0             # a boot reaches further than a fist
const KICK_WINDUP := 0.3
const KICK_COOLDOWN := 0.9
const KICK_KNOCKDOWN_CHANCE := 0.6  # a boot to a standing man floors him more often than a fist
const STOMP_FRAC := 0.12            # a kick to a man on the floor: 12% of max HP, and he stays down longer
const STOMP_EXTRA_DOWN := 0.5
const THROW_COOLDOWN := 2.4
const THROW_RANGE := 20.0
const PICKUP_RANGE := 1.5
const ACCURACY := 0.7               # the same hands for everyone: throw error/lead and punch landing
const DECISION_INTERVAL := 0.15
const FOV_COS := -0.09              # cos of the half field of view (~95 degrees each side)
const EYE_HEIGHT := 1.75

const LAYER_WORLD := 1
const LAYER_ROBOTS := 2
const LAYER_HITBOXES := 8

const HAND_POS := Vector3(0.45, 1.5, -0.35)

var team := 0
var team_color := Color.RED
var robot_name := "bot"
var personality: Personality
## What it is, as against how it behaves: five properties adding up to 1 (see robot_type.gd).
## Everything below it is derived in apply_type(); an even type reproduces the old constants.
var robot_type: RobotType
var type_name := ""   # set by the manager; falls back to the closest preset
var max_hp := MAX_HP
var move_speed := SPEED
var accuracy := ACCURACY
var dmg_mult := 1.0
var windup_mult := 1.0      # < 1 is quicker off the mark
var react_mult := 1.0       # < 1 sees it coming sooner
var hp := MAX_HP
var alive := true
var held: Weapon = null
var manager = null
var rng: RandomNumberGenerator

var action := "wander"
var punch_timer := 0.0
var throw_timer := 0.0
var decide_timer := 0.0
var move_dir := Vector3.ZERO
var face_point := Vector3.ZERO
var has_face_point := false
var wander_point := Vector3.ZERO
var wander_timer := 0.0
var stuck_timer := 0.0
var fetch_item: Weapon = null
var _rock_notice := {}  # rock -> did we notice this throw (caution-based reaction)
var _dodge_burst := 0.0
var _detour_timer := 0.0        # unstick: hold a random heading for a while, whatever the brain says
var _detour_dir := Vector3.ZERO
var _prog_anchor := Vector3.ZERO
var _prog_timer := 0.0
var _flee_timer := 0.0          # coward hit-and-run: after a poke, run
var _punch_pending := 0.0       # wind-up left before the current punch lands

# victory celebration (driven by MatchManager.celebration_phase)
var celebrating := false
var formation_spot := Vector3.ZERO
var at_spot := false
var teabag_targets: Array[Robot] = []
var teabag_idx := 0
var teabag_timer := 0.0
var _walk_stuck := 0.0
var _walk_detour := 0.0
var _walk_detour_dir := Vector3.ZERO
var _pee_timer := 0.0
var _stream: CPUParticles3D = null
var _puddle: MeshInstance3D = null

var hitboxes: Array[Area3D] = []
var fist: Area3D
var body_root: Node3D
var arm_r: MeshInstance3D
var arm_l: MeshInstance3D
var leg_l: Node3D
var leg_r: Node3D
var _gait := 0.0
var _kick_pending := 0.0
var _kick_anim := 0.0
var _kick_target: Robot = null
var kick_timer := 0.0
var swing_timer := 0.0
var _swing_pending := 0.0
var _swing_anim := 0.0
var _dark_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var ragdoll: Ragdoll = null
var cheer_timer := 0.0
var _cheer_phase := 0.0
var hide_spot := Vector3.ZERO
var label: Label3D
var _swing := 0.0
var _mat: StandardMaterial3D
var _flash_tween: Tween
var _body_tween: Tween
var down_timer := 0.0
var grace_timer := 0.0
var _bar_fg: MeshInstance3D
var _bar_quad: QuadMesh
var _bar_mat: StandardMaterial3D
const BAR_W := 1.3


func _ready() -> void:
	collision_layer = LAYER_ROBOTS
	collision_mask = LAYER_WORLD | LAYER_ROBOTS
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if personality == null:
		personality = Personality.preset("Balanced")
	if robot_type == null:
		robot_type = RobotType.preset("Even")
	apply_type()
	decide_timer = rng.randf_range(0.0, DECISION_INTERVAL)
	punch_timer = rng.randf_range(0.0, PUNCH_COOLDOWN)
	wander_point = global_position
	_build_body()


## Turn the five properties into the numbers the rest of the file already uses. Each spans a
## range around the original constant, and an even 0.2 share lands exactly on it - so a field
## of Even robots fights precisely the match it always did.
func apply_type() -> void:
	var brawn := robot_type.factor("brawn")
	var spd := robot_type.factor("speed")
	var grit := robot_type.factor("grit")
	var reflex := robot_type.factor("reflex")
	var aim := robot_type.factor("aim")
	# The spans below were levelled by playing each specialist against Even ten matches at a
	# time. The first pass had reflex and speed running away with it (in a game where the man
	# who connects first keeps his weapon, a short wind-up is worth more than a big hit) and
	# brawn and aim worth almost nothing, so their reach was widened and the other two reined in.
	max_hp = MAX_HP * clampf(0.68 + 0.32 * grit, 0.5, 1.9)
	move_speed = SPEED * clampf(0.78 + 0.22 * spd, 0.6, 1.4)
	dmg_mult = clampf(0.5 + 0.5 * brawn, 0.4, 2.0)
	accuracy = clampf(0.38 + 0.32 * aim, 0.3, 0.9)
	windup_mult = clampf(1.2 - 0.2 * reflex, 0.6, 1.4)
	react_mult = clampf(1.22 - 0.22 * reflex, 0.55, 1.45)
	hp = max_hp
	if type_name == "":
		type_name = robot_type.label()


# ---------------------------------------------------------------- body

func _build_body() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.9
	cs.shape = cap
	cs.position = Vector3(0, 0.95, 0)
	add_child(cs)

	body_root = Node3D.new()
	add_child(body_root)

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = team_color
	_mat.roughness = 0.6
	_mat.metallic = 0.3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = team_color.darkened(0.45)
	dark.roughness = 0.8
	_dark_mat = dark

	# name, mesh, shape, position, material
	_part("torso", _box(Vector3(0.6, 0.7, 0.35)), _box_shape(Vector3(0.6, 0.7, 0.35)), Vector3(0, 1.15, 0), _mat)
	_part("head", _box(Vector3(0.36, 0.34, 0.36)), _box_shape(Vector3(0.4, 0.38, 0.4)), Vector3(0, 1.75, 0), _mat)
	arm_l = _part("arm_l", _capsule(0.1, 0.62), _capsule_shape(0.12, 0.66), Vector3(-0.42, 1.2, 0), dark)
	arm_r = _part("arm_r", _capsule(0.1, 0.62), _capsule_shape(0.12, 0.66), Vector3(0.42, 1.2, 0), dark)
	leg_l = _leg("leg_l", -0.17, dark)
	leg_r = _leg("leg_r", 0.17, dark)

	# eye so you can see which way it faces
	var eye := MeshInstance3D.new()
	eye.mesh = _box(Vector3(0.22, 0.06, 0.04))
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(0.2, 1.0, 0.9)
	em.emission_enabled = true
	em.emission = Color(0.2, 1.0, 0.9)
	eye.material_override = em
	_eye_mat = em
	eye.position = Vector3(0, 1.78, -0.19)
	body_root.add_child(eye)

	fist = Area3D.new()
	fist.collision_layer = 0
	fist.collision_mask = LAYER_HITBOXES
	fist.monitoring = true
	fist.monitorable = false
	var fcs := CollisionShape3D.new()
	fcs.shape = _box_shape(Vector3(0.45, 0.5, PUNCH_REACH))
	fcs.position = Vector3(0.15, 1.3, -PUNCH_REACH * 0.5)
	fist.add_child(fcs)
	add_child(fist)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 34
	label.pixel_size = 0.009
	label.outline_size = 8
	label.position = Vector3(0, 2.45, 0)
	label.modulate = Color.WHITE
	add_child(label)

	# HP bar: two billboarded quads, the front one shrinks from full to nothing
	var bg := MeshInstance3D.new()
	var bgq := QuadMesh.new()
	bgq.size = Vector2(BAR_W + 0.06, 0.2)
	bg.mesh = bgq
	bg.material_override = _bar_material(Color(0.05, 0.05, 0.06, 0.85), 0)
	bg.position = Vector3(0, 2.15, 0)
	add_child(bg)
	_bar_fg = MeshInstance3D.new()
	_bar_quad = QuadMesh.new()
	_bar_quad.size = Vector2(BAR_W, 0.14)
	_bar_fg.mesh = _bar_quad
	_bar_mat = _bar_material(Color(0.2, 0.9, 0.3, 1.0), 1)
	_bar_fg.material_override = _bar_mat
	_bar_fg.position = Vector3(0, 2.15, 0)
	add_child(_bar_fg)
	_update_label()


func _bar_material(c: Color, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.albedo_color = c
	m.render_priority = prio
	return m


## A leg swings from the hip: a pivot at hip height with the capsule hanging below it.
## The hitbox stays put on the rig (legs are hit where legs are, not where the swing is).
func _leg(part_name: String, x: float, mat: Material) -> Node3D:
	var piv := Node3D.new()
	piv.name = part_name + "_pivot"
	piv.position = Vector3(x, 0.78, 0)
	body_root.add_child(piv)
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = _capsule(0.12, 0.76)
	mi.material_override = mat
	mi.position = Vector3(0, -0.38, 0)
	piv.add_child(mi)
	_hitbox(part_name, _capsule_shape(0.14, 0.8), Vector3(x, 0.4, 0))
	return piv


func _hitbox(part_name: String, shape: Shape3D, pos: Vector3) -> void:
	var hb := Area3D.new()
	hb.name = "hb_" + part_name
	hb.collision_layer = LAYER_HITBOXES
	hb.collision_mask = 0
	hb.monitoring = false
	hb.monitorable = true
	hb.set_meta("robot", self)
	hb.set_meta("part", part_name)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	hb.add_child(cs)
	hb.position = pos
	body_root.add_child(hb)
	hitboxes.append(hb)


func _part(part_name: String, mesh: Mesh, shape: Shape3D, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	body_root.add_child(mi)

	var hb := Area3D.new()
	hb.name = "hb_" + part_name
	hb.collision_layer = LAYER_HITBOXES
	hb.collision_mask = 0
	hb.monitoring = false
	hb.monitorable = true
	hb.set_meta("robot", self)
	hb.set_meta("part", part_name)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	hb.add_child(cs)
	hb.position = pos
	body_root.add_child(hb)
	hitboxes.append(hb)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 3
	return m


func _capsule_shape(r: float, h: float) -> CapsuleShape3D:
	var s := CapsuleShape3D.new()
	s.radius = r
	s.height = h
	return s


func _update_label() -> void:
	if label == null:
		return
	var f := clampf(hp / max_hp, 0.0, 1.0)
	if alive:
		label.text = "%s %s" % [robot_name, personality.label()]
		label.modulate = Color.WHITE
	else:
		label.text = robot_name + " X"
		label.modulate = Color(0.5, 0.5, 0.5)
	if _bar_quad != null:
		_bar_quad.size.x = maxf(BAR_W * f, 0.001)
		_bar_quad.center_offset.x = -(BAR_W - BAR_W * f) * 0.5
		_bar_mat.albedo_color = Color(0.95, 0.25, 0.2).lerp(Color(0.2, 0.9, 0.3), f)
		_bar_fg.visible = alive and f > 0.0


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if not alive:
		return
	punch_timer -= delta
	throw_timer -= delta
	kick_timer -= delta
	swing_timer -= delta
	_flee_timer -= delta
	if _swing_anim > 0.0:
		_swing_anim -= delta
	if _swing_pending > 0.0:
		_swing_pending -= delta
		if _swing_pending <= 0.0 and down_timer <= 0.0 and (manager == null or manager.running):
			_weapon_land()
	if _punch_pending > 0.0:
		_punch_pending -= delta
		if _punch_pending <= 0.0 and down_timer <= 0.0 and (manager == null or manager.running):
			_melee_land("punch")
	if _kick_pending > 0.0:
		_kick_pending -= delta
		if _kick_pending <= 0.0 and down_timer <= 0.0 and (manager == null or manager.running):
			_melee_land("kick")
	decide_timer -= delta
	wander_timer -= delta
	grace_timer -= delta
	if manager != null and not manager.running:
		# match over: stand still; winners cheer for a couple of seconds
		velocity = Vector3.ZERO
		move_dir = Vector3.ZERO
		if down_timer > 0.0:
			_follow_ragdoll()
			if celebrating:
				down_timer -= delta
				if down_timer <= 0.0:
					_get_up()
			return
		if not celebrating:
			return
		match manager.celebration_phase:
			"gather":
				if _walk_to(formation_spot, delta, 0.5):
					at_spot = true
					look_at(global_position + Vector3(0, 0, 1), Vector3.UP)
					_reset_pose()
					arm_l.rotation.x = -PI + sin(manager.dance_clock * 6.0) * 0.2  # arms up, waiting for the others
					arm_r.rotation.x = -PI - sin(manager.dance_clock * 6.0) * 0.2
			"dance":
				_dance(manager.dance_clock)
			"teabag":
				_teabag(delta)
			_:
				_reset_pose()
				arm_l.rotation.x = -PI
				arm_r.rotation.x = -PI
		return
	if down_timer > 0.0:
		down_timer -= delta
		velocity = Vector3.ZERO
		_follow_ragdoll()
		if held != null:
			held.global_position = global_position + Vector3(0.6, 0.3, 0.2)
		if down_timer <= 0.0:
			_get_up()
		return
	if decide_timer <= 0.0:
		decide_timer = DECISION_INTERVAL
		_decide()

	# movement
	var mv := move_dir
	mv.y = 0.0
	if _detour_timer > 0.0:
		# stuck against a block or a body: hold a random heading until it clears, ignoring the brain
		_detour_timer -= delta
		mv = _detour_dir
	if mv.length_squared() > 0.001:
		mv = mv.normalized()
	var speed_mult := 0.92 + 0.16 * personality.get_trait("aggression")
	if _dodge_burst > 0.0:
		_dodge_burst -= delta
		speed_mult *= 1.25  # a jolt of adrenaline: the dodge is a sprint, whichever way you face
	elif has_face_point and mv.length_squared() > 0.001:
		# backpedalling (moving away from what you're facing) is slower - chasers catch fleers
		var facing := face_point - global_position
		facing.y = 0.0
		if facing.length_squared() > 0.01 and mv.dot(facing.normalized()) < -0.3:
			speed_mult *= 0.78
	velocity = mv * move_speed * speed_mult
	velocity.y = 0.0
	var before := global_position
	move_and_slide()
	global_position.y = 0.0
	# unstick, two ways. (a) pressed against something: barely moving while trying to.
	# (b) inching back and forth behind a block: wanted to move for a second and a half and got nowhere.
	# Either way pick a random heading (60-150 degrees off) and hold it for a random while.
	var wanted := move_dir.length_squared() > 0.001
	if wanted and _detour_timer <= 0.0 and before.distance_to(global_position) < move_speed * delta * 0.3:
		stuck_timer += delta
		if stuck_timer > 0.3:
			_start_detour(mv)
	else:
		stuck_timer = 0.0
	if wanted:
		_prog_timer += delta
		if _prog_timer >= 1.5:
			if _prog_anchor.distance_to(global_position) < 1.2 and _detour_timer <= 0.0 and action != "punch" and action != "throw":
				_start_detour(mv)
			_prog_anchor = global_position
			_prog_timer = 0.0
	else:
		_prog_anchor = global_position
		_prog_timer = 0.0

	# facing
	var fp := face_point if has_face_point else global_position + mv
	fp.y = global_position.y
	if fp.distance_squared_to(global_position) > 0.01:
		look_at(fp, Vector3.UP)

	# arm swing anim
	if _swing > 0.0:
		_swing -= delta
		# wind back during the wind-up, then snap forward
		arm_r.rotation.x = (0.9 * (1.0 - (_swing - 0.2) / PUNCH_WINDUP)) if _swing > 0.2 else -1.6 * (_swing / 0.2)
	else:
		arm_r.rotation.x = 0.0
	# feet: legs swing from the hip in time with the ground covered; a kick overrides the right leg
	var spd := velocity.length()
	if _kick_anim > 0.0:
		_kick_anim -= delta
		var k := 1.0 - _kick_anim / (KICK_WINDUP + 0.25)  # 0..1 over the whole kick
		leg_r.rotation.x = (0.5 * k / 0.55) if k < 0.55 else -1.35 * sin((k - 0.55) / 0.45 * PI)  # wind back, then boot
		leg_l.rotation.x = 0.0
	elif spd > 0.4:
		_gait += delta * spd * 1.7
		leg_l.rotation.x = sin(_gait) * 0.6
		leg_r.rotation.x = -sin(_gait) * 0.6
		if _swing <= 0.0:
			arm_l.rotation.x = -sin(_gait) * 0.35
			arm_r.rotation.x = sin(_gait) * 0.35
	else:
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, minf(delta * 10.0, 1.0))
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, minf(delta * 10.0, 1.0))
		if _swing <= 0.0:
			arm_l.rotation.x = lerpf(arm_l.rotation.x, 0.0, minf(delta * 10.0, 1.0))

	if held != null:
		held.global_position = to_global(HAND_POS)
		if held.is_melee():
			# blade forward and a little up; a swing sweeps it across
			var tilt := -PI * 0.3 - (1.2 * sin(clampf(1.0 - _swing_anim / 0.35, 0.0, 1.0) * PI) if _swing_anim > 0.0 else 0.0)
			held.global_transform.basis = global_transform.basis * Basis(Vector3.RIGHT, tilt)

	# opportunistic boot: an enemy on the floor within reach gets stomped, whoever you are
	if manager != null and kick_timer <= 0.0 and _kick_pending <= 0.0 and _punch_pending <= 0.0:
		var dn := _nearest_downed_enemy(KICK_REACH)
		if dn != null and _facing(dn.corpse_position()):
			_kick(dn)
	# opportunistic swing: a weapon in hand and an enemy within its reach - unless this robot
	# doesn't box (cowards poke and run, as with fists)
	if manager != null and held != null and held.is_melee() and swing_timer <= 0.0 and _swing_pending <= 0.0 and _punch_pending <= 0.0 and _kick_pending <= 0.0:
		var e2 := _nearest_enemy()
		if e2 != null:
			var ed2 := _flat_dist(e2.global_position)
			if ed2 <= held.stat("reach") + 0.1 and _facing(e2.global_position) and _will_box(ed2):
				_weapon_swing(e2)
	# opportunistic punch (or, a third of the time, a kick): anyone in reach and fist ready -
	# unless this robot doesn't box, or has a weapon to swing instead
	if manager != null and punch_timer <= 0.0 and _kick_pending <= 0.0 and _swing_pending <= 0.0 and (held == null or not held.is_melee()):
		var e := _nearest_enemy()
		if e != null:
			var ed := _flat_dist(e.global_position)
			if ed <= PUNCH_REACH + 0.2 and _will_box(ed):
				if kick_timer <= 0.0 and rng.randf() < 0.3:
					_kick(e)
				else:
					_punch()
	# opportunistic throw: arm ready and a standing enemy in range with a clear line - fling it
	if manager != null and held != null and _wants_to_throw() and throw_timer <= 0.0 and action != "dodge":
		var tgt := _throw_target()
		if tgt != null:
			_throw_at(tgt)


## Slingers don't box and cowards don't close in - unless there's no other choice
## (no rock in hand, none to fetch, enemy right on top of them).
func _will_box(edist: float) -> bool:
	var rock_love := personality.get_trait("rock_love")
	var caution := personality.get_trait("caution")
	if held != null and held.is_melee() and caution < 0.8:
		return true  # a bat in hand settles the question
	if rock_love < 0.75 and caution < 0.8:
		return true
	var cornered := held == null and _nearest_free_item() == null and edist < 3.0
	if cornered or rock_love >= 0.75:
		return cornered
	# a coward never goes looking for fists, but with an enemy already in reach he swings:
	# trapped (wall or block at his back) means fight it out; with an open escape it's one
	# poke and then run (see _punch)
	return edist <= PUNCH_REACH + 0.3


## Is there room to run straight away from the nearest enemy - inside the arena and not into cover?
func _escape_open() -> bool:
	var e := _nearest_enemy()
	if e == null:
		return true
	var away := global_position - e.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		return true
	away = away.normalized()
	var h: float = manager.ARENA_HALF - 1.5
	var p := global_position + away * 3.0
	if absf(p.x) > h or absf(p.z) > h:
		return false
	return _clear_line(global_position + Vector3(0, 0.9, 0), p + Vector3(0, 0.9, 0))


## How close this robot likes to be before it lets fly: the aggressive walk in for a sure
## shot, the cautious throw from as far as the arm allows.
func _throw_dist() -> float:
	var aggression := personality.get_trait("aggression")
	var caution := personality.get_trait("caution")
	return clampf(7.0 + 8.0 * (1.0 - aggression) + 6.0 * caution, 7.0, THROW_RANGE)


## Is one of ours standing in the way of a throw at this point? A mate within a margin of the
## flight line (bigger for wild throwers, who know their rocks wander) between the hand and the target.
func _lane_blocked(target_pos: Vector3) -> bool:
	var origin := global_position
	var line := target_pos - origin
	line.y = 0.0
	var len := line.length()
	if len < 0.5:
		return false
	var dirv := line / len
	var margin := 0.9 + 0.8 * (1.0 - accuracy)
	var speed := held.throw_speed() if held != null else 18.0
	for m: Robot in manager.alive_robots():
		if m.team != team or m == self:
			continue
		# where the mate will be when the rock gets there, not where he is now
		var rel := m.global_position - origin
		rel.y = 0.0
		var t := clampf(rel.dot(dirv), 0.0, len) / speed
		rel += m.velocity * t
		rel.y = 0.0
		if rel.length() < 1.7:
			return true  # a mate at your elbow: the rock leaves the hand straight into him
		var along := rel.dot(dirv)
		# a miss carries on past the target: mind the mates behind him too
		if along < -0.5 or along > len + 12.0:
			continue
		var lateral := (rel - dirv * along).length()
		# a cone, not a tube: the further the rock flies the more it wanders
		var mg := maxf(margin, 0.9 + minf(along, len) * 0.21) if along <= len else margin * 1.3
		if along < 3.0:
			mg += 0.6  # splash radius plus a body, right in front of the hand
		if m.velocity.length() > 2.0:
			mg += 0.8  # he's on the move and may well run into it
		if m.down_timer > 0.0:
			mg *= 0.7
		if lateral < mg:
			return true
	return false


## Would this robot throw what it holds? Rocks always; a knife or spear only if it loves
## throwing more than stabbing; bats and swords never.
func _wants_to_throw() -> bool:
	if held == null or not held.is_throwable():
		return false
	if held.kind == Weapon.Kind.ROCK:
		return true
	return personality.get_trait("rock_love") >= 0.6


## Who to throw at: the nearest enemy that is on its feet and not behind cover.
## Falls back to a floored enemy (aimed low) only if nobody is standing.
func _throw_target() -> Robot:
	var best: Robot = null
	var best_cost := INF
	var origin := to_global(HAND_POS)
	for r: Robot in manager.alive_robots():
		if r.team == team or r == self:
			continue
		var d := _flat_dist(r.global_position)
		if d > THROW_RANGE:
			continue
		if d > _throw_dist() + 2.0:
			# too far for a good shot - walk in first, unless he's running off (throw before he's gone)
			var away_v: Vector3 = r.velocity
			away_v.y = 0.0
			var to_me := global_position - r.global_position
			to_me.y = 0.0
			var fleeing := away_v.length() > 2.0 and to_me.length_squared() > 0.01 and away_v.normalized().dot(to_me.normalized()) < -0.5
			if not fleeing:
				continue
		var aim_y := 0.35 if r.down_timer > 0.0 else 1.1
		if not _can_see(r.global_position + Vector3(0, aim_y, 0)):
			continue  # can't aim at what you aren't looking at
		if not _clear_line(origin, r.global_position + Vector3(0, aim_y, 0)):
			continue
		if _lane_blocked(r.global_position):
			continue  # one of ours is in the way - not through him
		var cost := d + (12.0 if r.down_timer > 0.0 else 0.0)
		# the protective aim first at an enemy who is on one of ours
		var protect := personality.get_trait("protect")
		if protect > 0.05:
			for m: Robot in manager.alive_robots():
				if m.team == team and m != self and m._flat_dist(r.global_position) < 4.5:
					cost -= 10.0 * protect
					break
		if cost < best_cost:
			best_cost = cost
			best = r
	return best


## Eyes, not radar: a point is seen only if it lies inside the field of view
## (about 190 degrees, so a little past the shoulders) AND nothing solid blocks the eye line.
func _can_see(point: Vector3) -> bool:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() > 0.04 and forward.length_squared() > 0.001:
		if forward.normalized().dot(to.normalized()) < FOV_COS:
			return false
	return _clear_line(global_position + Vector3(0, EYE_HEIGHT, 0), point)


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	q.exclude = [get_rid()]
	return space.intersect_ray(q).is_empty()


func _follow_ragdoll() -> void:
	if ragdoll == null:
		return
	var p := ragdoll.torso_position()
	var h: float = manager.ARENA_HALF - 1.0 if manager != null else 19.0
	global_position = Vector3(clampf(p.x, -h, h), 0.0, clampf(p.z, -h, h))


func _nearest_armed_enemy() -> Robot:
	var best: Robot = null
	var bd := INF
	for r: Robot in manager.alive_robots():
		if r.team == team or r == self or r.held == null or not r.held.is_throwable():
			continue
		var d := _flat_dist(r.global_position)
		if d < bd:
			bd = d
			best = r
	return best


# ---------------------------------------------------------------- perception helpers

func _flat_dist(p: Vector3) -> float:
	var d := p - global_position
	d.y = 0.0
	return d.length()


func _nearest_enemy() -> Robot:
	var best: Robot = null
	var bd := INF
	for r: Robot in manager.alive_robots():
		if r.team == team or r == self or not r.alive:
			continue
		var d := _flat_dist(r.global_position)
		if d < bd:
			bd = d
			best = r
	return best


## The nearest living enemy who is on the floor (ragdolled) within reach_m of us.
func _nearest_downed_enemy(reach_m: float) -> Robot:
	var best: Robot = null
	var bd := reach_m
	for r: Robot in manager.alive_robots():
		if r.team == team or r == self or r.down_timer <= 0.0:
			continue
		var d := _flat_dist(r.corpse_position())
		if d < bd:
			bd = d
			best = r
	return best


func _facing(point: Vector3) -> bool:
	var f := -global_transform.basis.z
	f.y = 0.0
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 0.04 or f.length_squared() < 0.001:
		return true
	return f.normalized().dot(to.normalized()) > 0.45


## A mate in trouble: floored, or with an enemy at his throat. Returns {mate, enemy, urgency} or {}.
## Urgency grows as the mate's HP falls and when he is down; nothing if he is far away.
func _mate_in_trouble() -> Dictionary:
	var best := {}
	var best_u := 0.0
	for m: Robot in manager.alive_robots():
		if m.team != team or m == self:
			continue
		var md := _flat_dist(m.global_position)
		if md > 24.0:
			continue
		var foe: Robot = null
		var fd := INF
		for e: Robot in manager.alive_robots():
			if e.team == team or e.down_timer > 0.0:
				continue
			var d := m._flat_dist(e.global_position)
			if d < fd:
				fd = d
				foe = e
		if foe == null:
			continue
		var reach := 6.5 if m.down_timer > 0.0 else 4.0
		if fd > reach:
			continue
		var u := (1.0 - fd / reach) * 0.6 + 0.4
		u *= 0.7 + 0.6 * (1.0 - m.hp / m.max_hp)
		if m.down_timer > 0.0:
			u *= 1.4
		u *= clampf(1.3 - md / 24.0, 0.3, 1.0)
		if u > best_u:
			best_u = u
			best = {"mate": m, "enemy": foe, "urgency": u}
	return best


## The most tempting free item: weapons are worth the walk, rocks mostly to rock-lovers;
## everything discounted by distance.
func _nearest_free_item() -> Weapon:
	var best: Weapon = null
	var bs := -INF
	var rock_love := personality.get_trait("rock_love")
	for rk: Weapon in manager.items:
		if not rk.is_free(self):
			continue
		var d := _flat_dist(rk.global_position)
		var v := _item_value(rk, rock_love)
		var sc := v / (1.0 + d / 8.0)
		if sc > bs:
			bs = sc
			best = rk
	return best


func _item_value(w: Weapon, rock_love: float) -> float:
	match w.kind:
		Weapon.Kind.SWORD: return 1.0
		Weapon.Kind.SPEAR: return 0.9 + 0.2 * rock_love
		Weapon.Kind.BAT: return 0.85
		Weapon.Kind.KNIFE: return 0.6 + 0.2 * rock_love
		Weapon.Kind.BOTTLE: return 0.55 + 0.15 * rock_love
		Weapon.Kind.CAT: return 0.5 + 0.8 * rock_love     # a thrower's dream; useless to a boxer
		Weapon.Kind.BABY: return 0.34 + 0.6 * rock_love   # it barely hurts, but it never misses a laugh
		_: return 0.45 + 0.7 * rock_love


## Returns {rock, time, perp} for the most urgent incoming enemy rock, or empty dict.
func _incoming_threat() -> Dictionary:
	var best := {}
	var best_t := INF
	var caution := personality.get_trait("caution")
	for rk: Weapon in manager.items:
		if rk.state != Weapon.State.THROWN or rk.thrower == null or rk.thrower == self:
			_rock_notice.erase(rk)  # friendly rocks hurt just the same - mind them too
			continue
		# Seeing it is everything: a rock you are looking at (in the field of view, not behind
		# cover) is spotted almost every time and dodged after a short reaction; one coming
		# from behind or over a block is simply not seen. Not spotted yet? Look again each tick.
		if not _rock_notice.has(rk) or _rock_notice[rk] < 0.0:
			if _can_see(rk.global_position):
				var first := not _rock_notice.has(rk)
				var notice_p := 0.92 if first else 0.6
				var reaction := (0.08 + (1.0 - caution) * 0.2) * react_mult
				_rock_notice[rk] = (manager.elapsed + reaction) if rng.randf() < notice_p else -1.0
			else:
				_rock_notice[rk] = -1.0
		if _rock_notice[rk] < 0.0 or manager.elapsed < _rock_notice[rk]:
			continue
		var v: Vector3 = rk.linear_velocity
		v.y = 0.0
		var speed := v.length()
		if speed < 4.0:
			continue
		var dirv := v / speed
		var rel := global_position - rk.global_position
		rel.y = 0.0
		var along := rel.dot(dirv)
		if along < -1.0 or along > 24.0:
			continue
		var lateral := (rel - dirv * along).length()
		if lateral > 2.2:
			continue
		var t := along / speed
		if t < best_t:
			best_t = t
			var perp := dirv.cross(Vector3.UP)
			if rel.dot(perp) < 0.0:
				perp = -perp
			best = {"rock": rk, "time": t, "perp": perp}
	return best


func _team_centroid() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for r: Robot in manager.alive_robots():
		if r.team == team and r != self:
			c += r.global_position
			n += 1
	return c / n if n > 0 else global_position


# ---------------------------------------------------------------- brain

func _decide() -> void:
	if manager == null:
		return
	var P := personality
	var aggression := P.get_trait("aggression")
	var caution := P.get_trait("caution")
	var rock_love := P.get_trait("rock_love")
	var teamwork := P.get_trait("teamwork")
	var patience := P.get_trait("patience")
	var survival := P.get_trait("survival")
	var protect := P.get_trait("protect")

	var enemy := _nearest_enemy()
	var edist := _flat_dist(enemy.global_position) if enemy != null else INF
	var threat := _incoming_threat()
	var rock := _nearest_free_item() if held == null else null
	var rdist := _flat_dist(rock.global_position) if rock != null else INF
	var hpf := hp / max_hp
	var centroid := _team_centroid()
	var cdist := _flat_dist(centroid)
	var low_threshold := 0.2 + 0.4 * survival
	var low := hpf < low_threshold

	# how much sense running makes right now: none if they're far away, little if they're
	# worse off than you, and less and less as the clock runs down
	var flee_sense := 1.0
	if enemy != null:
		flee_sense = clampf(1.0 - (edist - 12.0) / 10.0, 0.1, 1.0) \
			* clampf(0.5 + enemy.hp / enemy.max_hp - hpf, 0.15, 1.0) \
			* clampf(manager.time_left / manager.MATCH_TIME + 0.35, 0.35, 1.0)

	var scores := {}
	# hurt: back off, pick up a rock on the way, throw from range
	if low and enemy != null:
		var s4 := 0.3 + survival * 1.5 * (1.0 - hpf / low_threshold)
		if held != null:
			s4 *= 0.55  # armed - let throw/kite take over
		scores["retreat"] = s4 * flee_sense
	# dodge an incoming rock
	if not threat.is_empty():
		# a rock you have seen coming at you beats everything else: get out of its way
		scores["dodge"] = 2.0 + caution * 0.5 + clampf(1.5 - threat["time"], 0.0, 1.0)
	# go get a rock
	if rock != null:
		var want := rock_love if rock.kind == Weapon.Kind.ROCK else maxf(0.75, aggression)
		scores["fetch"] = 0.12 + want * clampf(1.0 - rdist / 30.0, 0.15, 1.0) * (1.2 if enemy == null or edist > 6.0 else 0.5)
		if rock_love >= 0.75:
			scores["fetch"] += 0.5 * rock_love  # a slinger's whole game: throw, then run for the next rock
		if rdist < 3.5:
			scores["fetch"] += 0.35 * (rock_love if rock.kind == Weapon.Kind.ROCK else 1.0)  # it's right there, grab it
		if low:
			scores["fetch"] += 0.4 * survival * (1.0 - hpf)  # hurt and unarmed: a rock is the way back in
	# throw the rock we hold
	if held != null and enemy != null and _wants_to_throw():
		var in_range := edist <= THROW_RANGE
		var s := 0.45 + 0.45 * aggression + 0.2 * rock_love
		if not in_range:
			s *= 0.7  # approach to range
		if edist < 4.0:
			s *= 0.4 + 0.6 * rock_love  # close: brawlers would rather punch
		scores["throw"] = s
	# close the gap and punch
	if enemy != null:
		var s2 := aggression * (1.0 - rock_love * 0.55) * (1.0 - caution * 0.6) * clampf(1.0 - edist / 40.0, 0.25, 1.0) + 0.1
		if edist < 3.5:
			s2 += 0.35
		if held == null and rock == null:
			s2 += 0.25  # nothing else to do
		if held != null and held.is_melee() and not _wants_to_throw():
			s2 = maxf(s2, 0.55 + aggression * 0.6)  # armed: go and use it
		if not _will_box(edist):
			s2 = 0.05  # slingers and cowards keep their fists to themselves
		scores["punch"] = s2
	# hide behind cover from an enemy who is holding a rock (cowards, mostly)
	var armed := _nearest_armed_enemy() if caution > 0.5 else null
	if armed != null and manager.arena != null:
		var ad := _flat_dist(armed.global_position)
		if ad < 26.0:
			var sh := caution * 1.1 * clampf(1.0 - ad / 30.0, 0.3, 1.0)
			if held != null and ad > 10.0:
				sh *= 0.5  # armed and far: throwing is the better answer
			scores["hide"] = sh
	# run away
	if enemy != null:
		var s3 := caution * (1.0 - hpf) * 1.3
		if held != null and edist < 5.0 and rock_love > 0.5 and throw_timer > 0.0:
			s3 += 0.4  # kite while the arm recharges
		if held == null and rock == null and edist < 6.0:
			s3 += caution * 0.4
		# someone is coming at us: the cautious back off before it gets to fists
		var closing := enemy.velocity.length() > 1.0 and enemy.velocity.normalized().dot((global_position - enemy.global_position).normalized()) > 0.5
		if closing and edist < 9.0:
			s3 += caution * clampf(1.0 - edist / 9.0, 0.0, 1.0) * 1.2
		if caution > 0.8 and edist < 5.0 and not _will_box(edist):
			s3 += 0.5  # never get close
		scores["kite"] = s3 * flee_sense
		if _flee_timer > 0.0:
			scores["kite"] = 2.5  # just poked someone: run
	# an enemy on the floor nearby: go and put the boot in (slingers would rather throw, cowards
	# only when nobody standing is close)
	var downed := _nearest_downed_enemy(8.0)
	if downed != null:
		var ss := 0.45 + aggression * 0.9 + (0.25 if held == null else 0.0)
		if rock_love >= 0.75:
			ss *= 0.5
		if caution >= 0.8:
			ss *= 0.6 if edist > 6.0 else 0.0
		scores["stomp"] = ss * clampf(1.2 - _flat_dist(downed.corpse_position()) / 8.0, 0.3, 1.0)
	# guard a mate who has someone on him: get between them and deal with the attacker
	var trouble := _mate_in_trouble() if protect > 0.05 else {}
	if not trouble.is_empty():
		var sg: float = 0.15 + protect * 1.5 * trouble["urgency"]
		if hpf < 0.25:
			sg *= 0.5  # not much use to anyone half dead
		if not _will_box(edist):
			sg *= 0.45 if held != null else 0.2  # the non-boxers guard with rocks, not fists
		scores["guard"] = sg
	# regroup with the pack
	scores["regroup"] = teamwork * clampf(cdist / 14.0, 0.0, 1.0) * 0.85
	# idle / hold position
	scores["wander"] = 0.06 + patience * 0.15

	# hysteresis so they don't twitch between actions
	if scores.has(action):
		scores[action] += 0.08

	var best := "wander"
	var bs := -INF
	for k in scores:
		if scores[k] > bs:
			bs = scores[k]
			best = k
	if best != "fetch" and best != "retreat" and fetch_item != null:
		if fetch_item.claimed_by == self:
			fetch_item.claimed_by = null
		fetch_item = null
	action = best
	has_face_point = false

	match action:
		"dodge":
			# sprint sideways out of the rock's path (a cornered robot veers off the wall);
			# with a lot of time in hand the cautious also fall back a step
			var esc: Vector3 = threat["perp"]
			if threat["time"] > 0.8 and caution > 0.5:
				var rk: Weapon = threat["rock"]
				var away := global_position - rk.global_position
				away.y = 0.0
				esc = (esc + away.normalized() * 0.5).normalized()
			move_dir = _keep_in_arena(esc)
			_dodge_burst = 0.45
			var rk2: Weapon = threat["rock"]
			face_point = rk2.global_position  # eyes on the rock
			has_face_point = true
		"fetch":
			fetch_item = rock
			rock.claimed_by = self
			var to := rock.global_position - global_position
			to.y = 0.0
			if to.length() <= PICKUP_RANGE:
				_pickup(rock)
				move_dir = Vector3.ZERO
			else:
				move_dir = to.normalized()
		"throw":
			face_point = enemy.global_position
			has_face_point = true
			var tgt := _throw_target()
			if tgt != null and throw_timer <= 0.0:
				_throw_at(tgt)
			# positioning: get into range, keep some distance, slight strafe for patience-low bots
			var to := enemy.global_position - global_position
			to.y = 0.0
			to = to.normalized()
			if tgt == null and edist <= THROW_RANGE and _lane_blocked(enemy.global_position):
				# a mate is in the lane: sidestep to open it (away from the mate's side)
				var side := to.cross(Vector3.UP)
				var mate_side := 0.0
				for m: Robot in manager.alive_robots():
					if m.team == team and m != self and _flat_dist(m.global_position) < edist:
						mate_side += (m.global_position - global_position).dot(side)
				move_dir = _keep_in_arena(side * (-1.0 if mate_side > 0.0 else 1.0))
			elif edist > _throw_dist():
				move_dir = to  # closer for a better shot
			elif edist < 5.0 + 6.0 * maxf(caution, survival if low else 0.0):
				move_dir = _keep_in_arena(-to)
			else:
				var strafe := to.cross(Vector3.UP) * (1.0 if int(get_instance_id()) % 2 == 0 else -1.0)
				move_dir = strafe * (1.0 - patience) * 0.8
		"punch":
			face_point = enemy.global_position
			has_face_point = true
			var to := enemy.global_position - global_position
			to.y = 0.0
			var reach := held.stat("reach") if (held != null and held.is_melee()) else PUNCH_REACH
			move_dir = to.normalized() if edist > reach * 0.7 else Vector3.ZERO
			if held != null and held.is_melee():
				if edist <= reach and swing_timer <= 0.0 and _swing_pending <= 0.0:
					_weapon_swing(enemy)
			elif edist <= PUNCH_REACH and punch_timer <= 0.0:
				_punch()
		"kite":
			var away := global_position - enemy.global_position
			away.y = 0.0
			away = away.normalized()
			# bias toward teammates
			var to_c := centroid - global_position
			to_c.y = 0.0
			if to_c.length() > 3.0:
				away = (away + to_c.normalized() * 0.6 * teamwork).normalized()
			move_dir = _keep_in_arena(away)  # run properly - face the way you're going
		"retreat":
			var away := global_position - enemy.global_position
			away.y = 0.0
			away = away.normalized()
			var to_rock := Vector3.ZERO
			if held == null and rock != null and rdist < 18.0:
				to_rock = rock.global_position - global_position
				to_rock.y = 0.0
			if to_rock.length_squared() > 0.001 and to_rock.normalized().dot(away) > -0.35:
				# the rock is not behind the enemy - go get it
				fetch_item = rock
				rock.claimed_by = self
				if to_rock.length() <= PICKUP_RANGE:
					_pickup(rock)
					move_dir = Vector3.ZERO
				else:
					move_dir = to_rock.normalized()
			else:
				var to_c := centroid - global_position
				to_c.y = 0.0
				if to_c.length() > 3.0:
					away = (away + to_c.normalized() * 0.5 * teamwork).normalized()
				move_dir = _keep_in_arena(away)
		"hide":
			var armed_e := _nearest_armed_enemy()
			if armed_e != null:
				hide_spot = manager.arena.hide_spot(global_position, armed_e.global_position)
				face_point = armed_e.global_position
				has_face_point = true
			var to := hide_spot - global_position
			to.y = 0.0
			move_dir = to.normalized() if to.length() > 0.8 else Vector3.ZERO
		"stomp":
			var spot := downed.corpse_position()
			face_point = spot
			has_face_point = true
			var to := spot - global_position
			to.y = 0.0
			move_dir = to.normalized() if to.length() > KICK_REACH * 0.7 else Vector3.ZERO
			if to.length() <= KICK_REACH and kick_timer <= 0.0 and _kick_pending <= 0.0:
				_kick(downed)
		"guard":
			var mate: Robot = trouble["mate"]
			var foe: Robot = trouble["enemy"]
			face_point = foe.global_position
			has_face_point = true
			var fd := _flat_dist(foe.global_position)
			if held != null and throw_timer <= 0.0 and fd > 3.0 and fd <= THROW_RANGE and _can_see(foe.global_position + Vector3(0, 1.1, 0)) and not _lane_blocked(foe.global_position):
				_throw_at(foe)  # the attacker gets the rock, whoever is nearer - unless the mate is in the way
			if _will_box(fd):
				# stand between the attacker and the mate, then close and hit
				var between: Vector3 = mate.global_position + (foe.global_position - mate.global_position).normalized() * 1.3
				between.y = 0.0
				var target: Vector3 = foe.global_position if fd < 4.0 else between
				var to := target - global_position
				to.y = 0.0
				move_dir = to.normalized() if to.length() > 0.6 else Vector3.ZERO
				if fd <= PUNCH_REACH and punch_timer <= 0.0:
					_punch()
			else:
				# keep at throwing distance from the attacker, on the mate's side
				var to := foe.global_position - global_position
				to.y = 0.0
				to = to.normalized()
				if fd > _throw_dist():
					move_dir = to
				elif fd < 6.0:
					move_dir = _keep_in_arena(-to)
				else:
					move_dir = Vector3.ZERO
		"regroup":
			var to := centroid - global_position
			to.y = 0.0
			move_dir = to.normalized()
		_:
			if wander_timer <= 0.0 or _flat_dist(wander_point) < 1.5:
				wander_timer = rng.randf_range(1.5, 4.0)
				var h: float = manager.ARENA_HALF - 2.0
				wander_point = global_position + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
				wander_point.x = clampf(wander_point.x, -h, h)
				wander_point.z = clampf(wander_point.z, -h, h)
			var to := wander_point - global_position
			to.y = 0.0
			move_dir = to.normalized() * (0.6 - patience * 0.4) if to.length() > 0.5 else Vector3.ZERO
			if enemy != null:
				face_point = enemy.global_position
				has_face_point = true


func _start_detour(tried: Vector3) -> void:
	var base := tried if tried.length_squared() > 0.001 else Vector3.FORWARD
	var ang := rng.randf_range(1.05, 2.6) * (1.0 if rng.randf() < 0.5 else -1.0)
	_detour_dir = _keep_in_arena(base.rotated(Vector3.UP, ang))
	_detour_timer = rng.randf_range(0.5, 1.1)
	stuck_timer = 0.0
	_prog_anchor = global_position
	_prog_timer = 0.0


func _keep_in_arena(dir: Vector3) -> Vector3:
	var h: float = manager.ARENA_HALF - 2.5
	var p := global_position + dir * 3.0
	if absf(p.x) > h:
		dir.x = -signf(global_position.x) * 0.8
	if absf(p.z) > h:
		dir.z = -signf(global_position.z) * 0.8
	return dir.normalized() if dir.length_squared() > 0.001 else Vector3.ZERO


# ---------------------------------------------------------------- actions

func _pickup(rock: Weapon) -> void:
	if held != null or not rock.is_free(self):
		return
	held = rock
	rock.hold(self)
	fetch_item = null
	action = "wander"


func _throw_at(target: Robot) -> void:
	if held == null:
		return
	var origin := to_global(HAND_POS)
	var speed := held.throw_speed()
	var tpos := target.global_position + Vector3(0, 0.35 if target.down_timer > 0.0 else 1.1, 0)
	var dist := origin.distance_to(tpos)
	var t := dist / speed
	var aim := tpos + target.velocity * t * (0.4 + 0.6 * accuracy)
	var dir := (aim - origin).normalized()
	# loft to counter the reduced flight gravity: v_y = 0.5 * g * t
	dir.y += 0.5 * 9.8 * Weapon.FLIGHT_GRAVITY * t / speed
	var err := (1.0 - accuracy) * 0.22
	dir = dir.rotated(Vector3.UP, rng.randf_range(-err, err))
	var side := dir.cross(Vector3.UP)
	if side.length_squared() > 0.001:
		dir = dir.rotated(side.normalized(), rng.randf_range(-err, err) * 0.5)
	dir = dir.normalized()
	var rock := held
	held = null
	rock.launch(origin, dir * speed, self)
	throw_timer = THROW_COOLDOWN
	_swing = 0.2
	decide_timer = 0.0
	threw.emit(self)


## A punch is two moments: the wind-up (the target can see it coming and try to get out of
## the box) and the landing, when whatever is still in the fist box - and a roll against the
## puncher's accuracy - decides whether it connects.
func _punch() -> void:
	punch_timer = PUNCH_COOLDOWN
	_sfx("swing", 1.25, -10.0)
	var wu := PUNCH_WINDUP * windup_mult
	_swing = 0.2 + wu
	_punch_pending = wu
	for r in _in_fist():
		r.notice_punch(self)


func _in_fist() -> Dictionary:
	var hits := {}
	for a in fist.get_overlapping_areas():
		if not a.has_meta("robot"):
			continue
		var r: Robot = a.get_meta("robot")
		if r == null or r == self or r.team == team or not r.alive:
			continue
		hits[r] = int(hits.get(r, 0)) + 1
	return hits


## A swing of whatever is in hand: wind-up (seen, dodgeable), then everything in front within
## the weapon's reach is struck; a landed blow always sends the target sprawling (and he drops
## his own weapon). Land first and you keep yours.
func _weapon_swing(target: Robot) -> void:
	if held == null or not held.is_melee():
		return
	swing_timer = held.stat("cooldown")
	_sfx("swing", 0.8 if held.stat("reach") > 2.2 else 1.15, -5.0)
	var wu := held.stat("windup") * windup_mult
	_swing_pending = wu
	_swing_anim = wu + 0.25
	_swing = 0.2 + wu
	if target != null:
		target.notice_punch(self)
		face_point = target.global_position
		has_face_point = true


func _weapon_land() -> void:
	if held == null or not held.is_melee():
		return
	var w := held
	var reach := w.stat("reach")
	var frac := w.stat("dmg")
	var kd := w.stat("kd")
	var landed := false
	# everyone in front within reach - the fist box catches the close ones with hitbox counts,
	# distance and facing catch the rest of the arc
	var hits := _in_fist()
	for r: Robot in manager.alive_robots():
		if r.team == team or r == self or hits.has(r):
			continue
		var d := _flat_dist(r.global_position if r.down_timer <= 0.0 else r.corpse_position())
		if d <= reach and _facing(r.global_position if r.down_timer <= 0.0 else r.corpse_position()):
			hits[r] = 2
	for r in hits:
		if rng.randf() > 0.55 + 0.45 * accuracy:
			continue  # swung and missed
		landed = true
		var victim: Robot = r
		var quality := minf(float(hits[r]), float(PUNCH_FULL_HITBOXES)) / float(PUNCH_FULL_HITBOXES)
		if victim.down_timer > 0.0:
			# a blow to a man on the floor: reduced, but he stays down longer
			victim.take_damage(MAX_HP * frac * 0.6 * dmg_mult, "melee", self, hits[r])
			victim.down_timer += STOMP_EXTRA_DOWN
			if victim.ragdoll != null and is_instance_valid(victim.ragdoll):
				victim.ragdoll.shove(Vector3(0, 6.0, 0))
			continue
		victim.take_damage(MAX_HP * frac * quality * dmg_mult, "melee", self, hits[r])
		var floored := rng.randf() < kd * quality
		var away: Vector3 = victim.global_position - global_position
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.01 else -global_transform.basis.z
		var impulse: Vector3 = away * (12.0 + 30.0 * quality) + Vector3(0, 4.0 + 5.0 * quality, 0)
		victim.knock_down(PUNCH_KNOCKDOWN_TIME if floored else PUNCH_FLOP_TIME, self, "melee", impulse)
	if landed:
		_sfx("clang" if w.kind != Weapon.Kind.BOTTLE else "smash", randf_range(0.92, 1.12))
	swung.emit(self, landed, w.kind_name())
	# a bottle is a one-blow weapon: land it and you are holding the neck and nothing else
	if landed and w.shatters():
		w.shatter()
	if personality.get_trait("caution") >= 0.8 and _escape_open():
		_flee_timer = 1.6
		decide_timer = 0.0


## A kick: same idea as a punch (wind-up, can be seen and dodged, can miss) but from the
## hip - longer reach, slower, and the only way to hurt a man who is already on the floor.
func _kick(target: Robot) -> void:
	kick_timer = KICK_COOLDOWN
	_sfx("swing", 1.05, -9.0)
	var wu := KICK_WINDUP * windup_mult
	_kick_pending = wu
	_kick_anim = wu + 0.25
	_kick_target = target
	if target != null and target.down_timer <= 0.0:
		target.notice_punch(self)
	face_point = target.global_position if target != null else face_point
	has_face_point = target != null


func _melee_land(source: String) -> void:
	if source == "kick":
		_stomp_or_kick_land()
	else:
		_punch_land()


## The boot comes down. A man on the floor within reach takes a stomp (flat damage, stays down
## longer, ragdoll shoved); a standing one is treated like a hard punch from further out.
func _stomp_or_kick_land() -> void:
	var t := _kick_target
	_kick_target = null
	var landed := false
	if t != null and is_instance_valid(t) and t.alive and t.down_timer > 0.0:
		if _flat_dist(t.corpse_position()) <= KICK_REACH + 0.3 and rng.randf() < 0.55 + 0.45 * accuracy:
			landed = true
			t.take_damage(MAX_HP * STOMP_FRAC * dmg_mult, "kick", self, 1)
			t.down_timer += STOMP_EXTRA_DOWN
			if t.ragdoll != null and is_instance_valid(t.ragdoll):
				var away: Vector3 = t.corpse_position() - global_position
				away.y = 0.0
				away = away.normalized() if away.length_squared() > 0.01 else -global_transform.basis.z
				t.ragdoll.shove(away * 9.0 + Vector3(0, 7.0, 0))
	else:
		# standing target: whoever is in the boot's arc (the fist box, stretched)
		var hits := _in_fist()
		if t != null and is_instance_valid(t) and t.alive and not hits.has(t) and _flat_dist(t.global_position) <= KICK_REACH and _facing(t.global_position):
			hits[t] = 2
		for r in hits:
			if rng.randf() > 0.5 + 0.45 * accuracy:
				continue  # swung a leg at air
			landed = true
			var quality := minf(float(hits[r]), float(PUNCH_FULL_HITBOXES)) / float(PUNCH_FULL_HITBOXES)
			r.take_damage(MAX_HP * PUNCH_MAX_FRAC * quality * dmg_mult, "kick", self, hits[r])
			var floored := rng.randf() < KICK_KNOCKDOWN_CHANCE * quality
			var victim: Robot = r
			var away: Vector3 = victim.global_position - global_position
			away.y = 0.0
			away = away.normalized() if away.length_squared() > 0.01 else -global_transform.basis.z
			var impulse: Vector3 = away * (14.0 + 28.0 * quality) + Vector3(0, 4.0 + 5.0 * quality, 0)
			victim.knock_down(PUNCH_KNOCKDOWN_TIME if floored else PUNCH_FLOP_TIME, self, "kick", impulse)
	if landed:
		_sfx("thud", randf_range(0.85, 1.0))
	kicked.emit(self, landed)
	if personality.get_trait("caution") >= 0.8 and _escape_open():
		_flee_timer = 1.6
		decide_timer = 0.0


func _punch_land() -> void:
	var landed := false
	var hits := _in_fist()
	for r in hits:
		if rng.randf() > 0.55 + 0.45 * accuracy:
			continue  # swung and missed
		landed = true
		var quality := minf(float(hits[r]), float(PUNCH_FULL_HITBOXES)) / float(PUNCH_FULL_HITBOXES)
		r.take_damage(MAX_HP * PUNCH_MAX_FRAC * quality * dmg_mult, "punch", self, hits[r])
		# every landed punch sends them sprawling; the roll decides whether it's a flop or a proper floor
		var floored := rng.randf() < PUNCH_KNOCKDOWN_CHANCE * quality
		var victim: Robot = r
		var away: Vector3 = victim.global_position - global_position
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.01 else -global_transform.basis.z
		var impulse: Vector3 = away * (10.0 + 26.0 * quality) + Vector3(0, 4.0 + 5.0 * quality, 0)
		victim.knock_down(PUNCH_KNOCKDOWN_TIME if floored else PUNCH_FLOP_TIME, self, "punch", impulse)
	if landed:
		_sfx("thud", randf_range(1.0, 1.2), -2.0)
	punched.emit(self, landed)
	if personality.get_trait("caution") >= 0.8 and _escape_open():
		_flee_timer = 1.6  # hit and run (a trapped coward stays and fights)
		decide_timer = 0.0


## Someone in front of me has started a swing. If I can see him and my nerves are quick
## enough (caution), I skip sideways out of the fist box before it lands.
func notice_punch(attacker: Robot) -> void:
	if not alive or down_timer > 0.0 or attacker == null:
		return
	if not _can_see(attacker.global_position + Vector3(0, 1.2, 0)):
		return
	var caution := personality.get_trait("caution")
	# quick reflexes spot a wind-up that a slow robot walks straight into
	if rng.randf() > clampf((0.15 + 0.6 * caution) / react_mult, 0.05, 0.97):
		return
	var from := global_position - attacker.global_position
	from.y = 0.0
	if from.length_squared() < 0.01:
		return
	var side := from.normalized().cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
	move_dir = _keep_in_arena((side * 1.0 + from.normalized() * 0.35).normalized())
	_dodge_burst = PUNCH_WINDUP + 0.15
	decide_timer = PUNCH_WINDUP + 0.15  # hold the sidestep until the swing has gone by
	action = "dodge"
	has_face_point = true
	face_point = attacker.global_position


## Everything audible goes through here so a headless sim stays silent and the null checks
## live in one place.
func _sfx(cue: String, pitch := 1.0, vol_db := 0.0) -> void:
	if manager != null and manager.sfx != null:
		manager.sfx.play(cue, global_position, pitch, vol_db)


func take_damage(amount: float, source: String, attacker: Robot, hitbox_count: int) -> void:
	if not alive:
		return
	hp -= amount
	damaged.emit(self, amount, source, attacker, hitbox_count)
	_flash()
	if hp <= 0.0:
		hp = 0.0
		_die()
	_update_label()


func knock_down(duration: float, by: Robot, source: String, impulse: Vector3 = Vector3.ZERO) -> void:
	if not alive or grace_timer > 0.0:
		return
	var was_up := down_timer <= 0.0
	# whatever you were about to do, you aren't now: he who connects first wins the exchange
	_punch_pending = 0.0
	_kick_pending = 0.0
	_swing_pending = 0.0
	_kick_anim = 0.0
	_swing_anim = 0.0
	if held != null:
		var w := held
		held = null
		var away := impulse
		away.y = 0.0
		w.drop(away.normalized() * 1.5 if away.length_squared() > 0.01 else Vector3.ZERO)
		dropped.emit(self, w)
	down_timer = maxf(down_timer, duration)
	action = "down"
	move_dir = Vector3.ZERO
	var shove := impulse
	if shove.length_squared() < 0.01:
		shove = Vector3(0, 1, 0) * 8.0
		if by != null:
			var away := global_position - by.global_position
			away.y = 0.0
			if away.length_squared() > 0.01:
				shove += away.normalized() * (45.0 if source == "rock" else 22.0)
	if was_up:
		_sfx("thud", randf_range(0.7, 0.85), -3.0)   # the body hitting the floor
		_spawn_ragdoll()
		# hitboxes ride the (now invisible) rig so a floored robot is still below the fist box
		if _body_tween != null and _body_tween.is_valid():
			_body_tween.kill()
		body_root.rotation.x = -PI * 0.5
		body_root.position.y = 0.35
		knocked_down.emit(self, by, source)
	if ragdoll != null:
		ragdoll.shove(shove)


func _spawn_ragdoll() -> void:
	if ragdoll != null or manager == null or manager.world == null:
		return
	ragdoll = Ragdoll.new()
	manager.world.add_child(ragdoll)
	var pose := global_transform
	pose.origin.y = 0.0
	ragdoll.build(pose, _mat, _dark_mat, _eye_mat)
	body_root.visible = false


func _get_up() -> void:
	down_timer = 0.0
	grace_timer = RECOVER_GRACE
	action = "wander"
	decide_timer = 0.1
	if ragdoll != null:
		_follow_ragdoll()
		ragdoll.queue_free()
		ragdoll = null
	body_root.visible = true
	if _body_tween != null and _body_tween.is_valid():
		_body_tween.kill()
	body_root.rotation.x = -PI * 0.5
	body_root.position.y = 0.35
	_body_tween = create_tween().set_parallel(true)
	_body_tween.tween_property(body_root, "rotation:x", 0.0, 0.3)
	_body_tween.tween_property(body_root, "position:y", 0.0, 0.3)


## The victory dance. Every winner reads the same clock, so the team moves as one:
## hips swinging side to side, arms rolling overhead, a hop on the beat, and a slow
## full turn every few bars.
func _dance(t: float) -> void:
	var beat := t * TAU * 1.6  # ~96 bpm
	body_root.rotation.z = sin(beat) * 0.28              # hip sway
	body_root.rotation.x = -absf(sin(beat * 0.5)) * 0.12  # a little forward lean on the downbeat
	body_root.rotation.y = fmod(t * 0.5, 1.0) * TAU if fmod(t, 4.0) < 2.0 else 0.0  # slow turn every other bar
	body_root.position.y = maxf(sin(beat * 2.0), 0.0) * 0.18  # hop
	arm_l.rotation.x = -PI + sin(beat) * 0.6
	arm_l.rotation.z = -0.5 + sin(beat + 0.7) * 0.4
	arm_r.rotation.x = -PI - sin(beat) * 0.6
	arm_r.rotation.z = 0.5 - sin(beat + 0.7) * 0.4


## Join the victory celebration: run to the formation spot, dance with the team, then
## visit the fallen. A winner still on the floor gets up first and hurries along.
func cheer(spot: Vector3, corpses: Array[Robot]) -> void:
	_sfx("cheer", randf_range(0.95, 1.05), -4.0)
	if not alive:
		return
	celebrating = true
	formation_spot = spot
	at_spot = false
	teabag_targets = corpses
	teabag_idx = 0
	teabag_timer = 0.0
	_pee_timer = 0.0
	_cheer_phase = rng.randf_range(0.0, TAU)
	if held != null:
		held.drop()
		held = null


func teabag_done() -> bool:
	return teabag_idx >= teabag_targets.size()


## Where the body lies (the ragdoll's torso once it has settled).
func corpse_position() -> Vector3:
	var p := global_position
	if ragdoll != null and is_instance_valid(ragdoll):
		p = ragdoll.torso_position()
	p.y = 0.0
	return p


func _reset_pose() -> void:
	body_root.position.y = 0.0
	body_root.rotation = Vector3.ZERO
	arm_l.rotation = Vector3.ZERO
	arm_r.rotation = Vector3.ZERO
	leg_l.rotation = Vector3.ZERO
	leg_r.rotation = Vector3.ZERO


## Post-match locomotion (the utility brain is off): jog straight at a point.
## Returns true once within stop_dist.
func _walk_to(target: Vector3, _delta: float, stop_dist: float) -> bool:
	var to := target - global_position
	to.y = 0.0
	if to.length() <= stop_dist:
		velocity = Vector3.ZERO
		return true
	var dir := to.normalized()
	if _walk_detour > 0.0:
		_walk_detour -= _delta
		dir = (dir * 0.3 + _walk_detour_dir).normalized()  # skirting a block or a teammate
	velocity = dir * move_speed * 0.9
	var before := global_position
	move_and_slide()
	global_position.y = 0.0
	if before.distance_to(global_position) < move_speed * 0.9 * _delta * 0.35:
		_walk_stuck += _delta
		if _walk_stuck > 0.25 and _walk_detour <= 0.0:
			_walk_detour = 0.7
			_walk_detour_dir = dir.rotated(Vector3.UP, PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0))
			_walk_stuck = 0.0
	else:
		_walk_stuck = 0.0
	var fp := global_position + to
	fp.y = global_position.y
	look_at(fp, Vector3.UP)
	# a light jog: bob and swing
	var t := Time.get_ticks_msec() * 0.001 + _cheer_phase
	body_root.position.y = absf(sin(t * 9.0)) * 0.08
	arm_l.rotation.x = sin(t * 9.0) * 0.6
	arm_r.rotation.x = -sin(t * 9.0) * 0.6
	leg_l.rotation.x = -sin(t * 9.0) * 0.6
	leg_r.rotation.x = sin(t * 9.0) * 0.6
	return false


## Stand astride a fallen foe and squat over him, four times, then move to the next.
func _teabag(delta: float) -> void:
	if teabag_done():
		_reset_pose()
		arm_l.rotation.x = -PI
		arm_r.rotation.x = -PI
		return
	var victim: Robot = teabag_targets[teabag_idx]
	if victim == null or not is_instance_valid(victim):
		teabag_idx += 1
		return
	if _pee_timer > 0.0:
		_pee(delta, victim)
		return
	var spot := victim.corpse_position()
	if not _walk_to(spot, delta, 0.3):
		return
	if teabag_timer == 0.0:
		# face along the body, so the squat lands on the chest
		var head := spot + Vector3(0, 0, 1)
		if victim.ragdoll != null and is_instance_valid(victim.ragdoll):
			head = victim.ragdoll.head_position()
		head.y = 0.0
		if head.distance_squared_to(global_position) > 0.01:
			look_at(head, Vector3.UP)
	teabag_timer += delta
	var s := 0.5 - 0.5 * cos(teabag_timer / TEABAG_PERIOD * TAU)  # 0 standing .. 1 deep squat
	body_root.position.y = -TEABAG_DEPTH * s
	body_root.rotation.x = 0.3 * s      # knees forward, a little lean back
	body_root.rotation.z = 0.0
	arm_l.rotation.x = -0.9 * s          # arms come forward for balance
	arm_r.rotation.x = -0.9 * s
	arm_l.rotation.z = -0.3 * s
	arm_r.rotation.z = 0.3 * s
	if teabag_timer >= TEABAG_PERIOD * TEABAG_REPS:
		teabag_timer = 0.0
		_reset_pose()
		_pee_timer = PEE_TIME  # squats done - now the final insult


## Stand back a pace from the body, hand at the hip, and relieve oneself upon it; a puddle
## spreads under the corpse and stays there. Then on to the next.
func _pee(delta: float, victim: Robot) -> void:
	var spot := victim.corpse_position()
	var away := global_position - spot
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.01 else Vector3(0, 0, 1)
	var stand := spot + away * 1.1
	if _pee_timer == PEE_TIME:
		if not _walk_to(stand, delta, 0.25):
			return
		var fp := spot
		fp.y = 0.0
		look_at(fp, Vector3.UP)
		_reset_pose()
		_start_stream(victim)
	_pee_timer -= delta
	# the pose: a little lean back, hips forward, one hand down in front, the other on the hip
	body_root.rotation.x = -0.12
	body_root.position.y = 0.0
	arm_r.rotation.x = -0.55
	arm_r.rotation.z = 0.25
	arm_l.rotation.z = -0.7
	arm_l.rotation.x = 0.3
	if _puddle != null and is_instance_valid(_puddle):
		var f := 1.0 - _pee_timer / PEE_TIME
		_puddle.scale = Vector3(0.15 + 0.85 * f, 1.0, 0.15 + 0.85 * f)
	if _pee_timer <= 0.0:
		_pee_timer = 0.0
		_stop_stream()
		_reset_pose()
		teabag_idx += 1


func _start_stream(victim: Robot) -> void:
	_stop_stream()
	_stream = CPUParticles3D.new()
	_stream.amount = 90
	_stream.lifetime = 0.7
	_stream.explosiveness = 0.0
	_stream.local_coords = true  # aimed in the robot's own frame: forward (-Z) and a little up
	_stream.direction = Vector3(0, 0.3, -1)
	_stream.spread = 3.0
	_stream.initial_velocity_min = 2.8
	_stream.initial_velocity_max = 3.1
	_stream.gravity = Vector3(0, -9.8, 0)
	_stream.scale_amount_min = 0.06
	_stream.scale_amount_max = 0.09
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	_stream.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.85, 0.2, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.5, 0.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stream.material_override = mat
	_stream.position = Vector3(0.05, 0.85, -0.25)
	add_child(_stream)
	_stream.emitting = true
	# the puddle, under the body, kept by the corpse so it goes when the arena is cleared
	_puddle = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.75
	pm.bottom_radius = 0.75
	pm.height = 0.02
	pm.radial_segments = 14
	_puddle.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.9, 0.8, 0.15, 0.55)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.roughness = 0.2
	_puddle.material_override = pmat
	victim.add_child(_puddle)
	var pp := victim.corpse_position()
	pp.y = 0.015
	_puddle.global_position = pp
	_puddle.scale = Vector3(0.15, 1.0, 0.15)


func _stop_stream() -> void:
	if _stream != null and is_instance_valid(_stream):
		_stream.emitting = false
		var st := _stream
		get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(st): st.queue_free())
	_stream = null
	_puddle = null


func cleanup() -> void:
	_stop_stream()
	if ragdoll != null and is_instance_valid(ragdoll):
		ragdoll.queue_free()
		ragdoll = null


func _flash() -> void:
	if _mat == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_mat.albedo_color = Color.WHITE
	_flash_tween = create_tween()
	_flash_tween.tween_property(_mat, "albedo_color", team_color, 0.25)


func _die() -> void:
	alive = false
	_sfx("death", randf_range(0.9, 1.1))
	action = "dead"
	move_dir = Vector3.ZERO
	velocity = Vector3.ZERO
	if held != null:
		held.drop()
		held = null
	if fetch_item != null and fetch_item.claimed_by == self:
		fetch_item.claimed_by = null
	collision_layer = 0
	collision_mask = 0
	for hb in hitboxes:
		hb.collision_layer = 0
	fist.monitoring = false
	if _body_tween != null and _body_tween.is_valid():
		_body_tween.kill()
	body_root.rotation.x = -PI * 0.5
	body_root.position.y = 0.35
	_spawn_ragdoll()
	if ragdoll != null:
		ragdoll.shove(Vector3(rng.randf_range(-6, 6), 10.0, rng.randf_range(-6, 6)))
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_mat.albedo_color = team_color.darkened(0.6)
	set_physics_process(false)
	_update_label()
	died.emit(self)


func _process(_delta: float) -> void:
	# dead: keep the name tag over the corpse while it settles
	if not alive and ragdoll != null and is_instance_valid(ragdoll):
		_follow_ragdoll()
