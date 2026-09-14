class_name Ragdoll
extends Node3D
## Six rigid bodies pinned together, spawned in the robot's pose when it goes down.
## Shares the robot's materials so hit-flashes and team colours carry over.

const LAYER_WORLD := 1
const LAYER_RAGDOLL := 16

# name, shape kind, size, local position, joint anchor (local), mass
const PARTS := [
	["torso", "box", Vector3(0.6, 0.7, 0.35), Vector3(0, 1.15, 0), Vector3.ZERO, 10.0],
	["head", "box", Vector3(0.36, 0.34, 0.36), Vector3(0, 1.75, 0), Vector3(0, 1.52, 0), 3.0],
	["arm_l", "capsule", Vector3(0.1, 0.62, 0), Vector3(-0.42, 1.2, 0), Vector3(-0.42, 1.5, 0), 2.0],
	["arm_r", "capsule", Vector3(0.1, 0.62, 0), Vector3(0.42, 1.2, 0), Vector3(0.42, 1.5, 0), 2.0],
	["leg_l", "capsule", Vector3(0.12, 0.76, 0), Vector3(-0.17, 0.4, 0), Vector3(-0.17, 0.78, 0), 2.5],
	["leg_r", "capsule", Vector3(0.12, 0.76, 0), Vector3(0.17, 0.4, 0), Vector3(0.17, 0.78, 0), 2.5],
]

var bodies := {}
var torso: RigidBody3D


func build(pose: Transform3D, main_mat: Material, dark_mat: Material, eye_mat: Material) -> void:
	global_transform = Transform3D.IDENTITY
	for p in PARTS:
		var rb := RigidBody3D.new()
		rb.name = p[0]
		rb.mass = p[5]
		rb.collision_layer = LAYER_RAGDOLL
		rb.collision_mask = LAYER_WORLD | LAYER_RAGDOLL
		rb.linear_damp = 0.6
		rb.angular_damp = 1.2
		rb.can_sleep = true
		var cs := CollisionShape3D.new()
		var mi := MeshInstance3D.new()
		if p[1] == "box":
			var sh := BoxShape3D.new()
			sh.size = p[2]
			cs.shape = sh
			var m := BoxMesh.new()
			m.size = p[2]
			mi.mesh = m
		else:
			var sh := CapsuleShape3D.new()
			sh.radius = p[2].x + 0.02
			sh.height = p[2].y + 0.04
			cs.shape = sh
			var m := CapsuleMesh.new()
			m.radius = p[2].x
			m.height = p[2].y
			m.radial_segments = 8
			m.rings = 3
			mi.mesh = m
		mi.material_override = main_mat if (p[0] == "torso" or p[0] == "head") else dark_mat
		rb.add_child(cs)
		rb.add_child(mi)
		if p[0] == "head":
			var eye := MeshInstance3D.new()
			var em := BoxMesh.new()
			em.size = Vector3(0.22, 0.06, 0.04)
			eye.mesh = em
			eye.material_override = eye_mat
			eye.position = Vector3(0, 0.03, -0.19)
			rb.add_child(eye)
		add_child(rb)
		rb.global_transform = pose * Transform3D(Basis.IDENTITY, p[3])
		bodies[p[0]] = rb
	torso = bodies["torso"]
	for p in PARTS:
		if p[0] == "torso":
			continue
		var j := PinJoint3D.new()
		add_child(j)
		j.global_transform = pose * Transform3D(Basis.IDENTITY, p[4])
		j.node_a = j.get_path_to(torso)
		j.node_b = j.get_path_to(bodies[p[0]])
		j.exclude_nodes_from_collision = true


func shove(impulse: Vector3) -> void:
	if torso == null:
		return
	torso.apply_central_impulse(impulse)
	# a little spin so it tumbles rather than slides
	torso.apply_torque_impulse(Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4)))
	if bodies.has("head"):
		bodies["head"].apply_central_impulse(impulse * 0.25)


func torso_position() -> Vector3:
	return torso.global_position if torso != null else global_position


func head_position() -> Vector3:
	return bodies["head"].global_position if bodies.has("head") else torso_position()
