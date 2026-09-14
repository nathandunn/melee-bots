class_name Arena
extends Node3D
## Flat 40x40 arena with walls and a handful of cover blocks. Built in code.

const HALF := 20.0
const WALL_H := 2.5
# x, z, size_x, size_z
const COVER: Array = [
	[0.0, 0.0, 3.0, 1.2],
	[-7.0, 7.0, 1.4, 3.5],
	[7.0, -7.0, 1.4, 3.5],
	[-7.0, -8.0, 2.5, 1.2],
	[7.0, 8.0, 2.5, 1.2],
	[0.0, 13.0, 3.0, 1.2],
	[0.0, -13.0, 3.0, 1.2],
]

var cover_rects: Array[Rect2] = []


func _ready() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.28, 0.3, 0.27)
	floor_mat.roughness = 1.0
	_static_box(Vector3(0, -0.5, 0), Vector3(HALF * 2 + 2, 1.0, HALF * 2 + 2), floor_mat)

	# grid-ish accent lines so motion reads on a flat floor
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.36, 0.38, 0.35)
	for i in range(-3, 4):
		var m := MeshInstance3D.new()
		m.mesh = _box_mesh(Vector3(HALF * 2, 0.02, 0.08))
		m.material_override = line_mat
		m.position = Vector3(0, 0.005, i * 5.0)
		add_child(m)
		var m2 := MeshInstance3D.new()
		m2.mesh = _box_mesh(Vector3(0.08, 0.02, HALF * 2))
		m2.material_override = line_mat
		m2.position = Vector3(i * 5.0, 0.005, 0)
		add_child(m2)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.18, 0.2, 0.24)
	var t := 0.5
	_static_box(Vector3(0, WALL_H * 0.5, -HALF - t * 0.5), Vector3(HALF * 2 + t * 2, WALL_H, t), wall_mat)
	_static_box(Vector3(0, WALL_H * 0.5, HALF + t * 0.5), Vector3(HALF * 2 + t * 2, WALL_H, t), wall_mat)
	_static_box(Vector3(-HALF - t * 0.5, WALL_H * 0.5, 0), Vector3(t, WALL_H, HALF * 2), wall_mat)
	_static_box(Vector3(HALF + t * 0.5, WALL_H * 0.5, 0), Vector3(t, WALL_H, HALF * 2), wall_mat)

	var cover_mat := StandardMaterial3D.new()
	cover_mat.albedo_color = Color(0.5, 0.42, 0.3)
	for c in COVER:
		var size := Vector3(c[2], 1.6, c[3])
		_static_box(Vector3(c[0], 0.8, c[1]), size, cover_mat)
		cover_rects.append(Rect2(c[0] - c[2] * 0.5 - 0.8, c[1] - c[3] * 0.5 - 0.8, c[2] + 1.6, c[3] + 1.6))


## Where to stand so that this cover block sits between you and the threat: the block's
## centre pushed away from the threat by its radius plus a body's width.
func hide_spot(from: Vector3, threat: Vector3) -> Vector3:
	var best := from
	var best_cost := INF
	for c in COVER:
		var centre := Vector3(c[0], 0.0, c[1])
		var radius := maxf(c[2], c[3]) * 0.5 + 1.0
		var away := centre - threat
		away.y = 0.0
		if away.length_squared() < 0.01:
			continue
		var spot := centre + away.normalized() * radius
		# don't pick a block that means running through the threat to reach it
		var cost := from.distance_to(spot) + (8.0 if spot.distance_to(threat) < from.distance_to(threat) - 2.0 else 0.0)
		if cost < best_cost:
			best_cost = cost
			best = spot
	best.x = clampf(best.x, -HALF + 1.5, HALF - 1.5)
	best.z = clampf(best.z, -HALF + 1.5, HALF - 1.5)
	return best


func is_clear(x: float, z: float) -> bool:
	for r in cover_rects:
		if r.has_point(Vector2(x, z)):
			return false
	return true


func _static_box(pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)
	return sb


func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
