@tool
extends Node3D

@export var spring_bones: Array
@export var collider_groups: Array

var update_secondary_fixed: bool = false
var update_in_editor: bool = false

# Props
var spring_bones_internal: Array = []
var collider_groups_internal: Array = []
var secondary_gizmo: SecondaryGizmo

# Called when the node enters the scene tree for the first time.
func _ready():
	var gizmo_spring_bone: bool = false
	if get_parent() is VRMTopLevel:
		update_secondary_fixed = get_parent().get("update_secondary_fixed")
		gizmo_spring_bone = get_parent().get("gizmo_spring_bone")

	if secondary_gizmo == null and (Engine.is_editor_hint() or gizmo_spring_bone):
		secondary_gizmo = SecondaryGizmo.new(self)
		add_child(secondary_gizmo)
	collider_groups_internal.clear()
	spring_bones_internal.clear()
	for collider_group in collider_groups:
		var new_collider_group = collider_group.duplicate(true)
		var parent: Node3D = get_node_or_null(new_collider_group.skeleton_or_node)
		if parent != null:
			new_collider_group._ready(parent, parent)
			collider_groups_internal.append(new_collider_group)
	for spring_bone in spring_bones:
		var new_spring_bone = spring_bone.duplicate(true)
		var tmp_colliders: Array = []
		for i in range(collider_groups.size()):
			if new_spring_bone.collider_groups.has(collider_groups[i]):
				tmp_colliders.append_array(collider_groups_internal[i].colliders)
		var skel: Skeleton3D = get_node_or_null(new_spring_bone.skeleton)
		if skel != null:
			new_spring_bone._ready(skel, tmp_colliders)
			spring_bones_internal.append(new_spring_bone)


func check_for_editor_update():
	if not Engine.is_editor_hint():
		return false
	var parent: Node = get_parent()
	if parent is VRMTopLevel:
		if parent.update_in_editor and not update_in_editor:
			update_in_editor = true
			_ready()
		if not parent.update_in_editor and update_in_editor:
			update_in_editor = false
			for spring_bone in spring_bones_internal:
				spring_bone.skel.clear_bones_global_pose_override()
	return update_in_editor


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if not update_secondary_fixed:
		if not Engine.is_editor_hint() or check_for_editor_update():
			# force update skeleton
			for spring_bone in spring_bones_internal:
				if spring_bone.skel != null:
					spring_bone.skel.get_bone_global_pose_no_override(0)
			for collider_group in collider_groups_internal:
				collider_group._process()
			for spring_bone in spring_bones_internal:
				spring_bone._process(delta)
			if secondary_gizmo != null:
				if Engine.is_editor_hint():
					secondary_gizmo.draw_in_editor(true)
				else:
					secondary_gizmo.draw_in_game()
		elif Engine.is_editor_hint():
			if secondary_gizmo != null:
				secondary_gizmo.draw_in_editor()


# All animations to the Node need to be done in the _physics_process.
func _physics_process(delta):
	if update_secondary_fixed:
		if not Engine.is_editor_hint() or check_for_editor_update():
			# force update skeleton
			for spring_bone in spring_bones_internal:
				if spring_bone.skel != null:
					spring_bone.skel.get_bone_global_pose_no_override(0)
			for collider_group in collider_groups_internal:
				collider_group._process()
			for spring_bone in spring_bones_internal:
				spring_bone._process(delta)
			if secondary_gizmo != null:
				if Engine.is_editor_hint():
					secondary_gizmo.draw_in_editor(true)
				else:
					secondary_gizmo.draw_in_game()
		elif Engine.is_editor_hint():
			if secondary_gizmo != null:
				secondary_gizmo.draw_in_editor()


# Remove when Godot 4.x implements support for ImmediateGometry3D
class StubImmediateGeometry3D:
	extends MeshInstance3D

	var verts_array: PackedVector3Array = PackedVector3Array()
	var color_array: PackedColorArray = PackedColorArray()

	func clear():
		if not verts_array.is_empty():
			is_dirty = true
		verts_array = PackedVector3Array()
		color_array = PackedColorArray()

	var line_strip: int = 0
	var cur_color: Color = Color.WHITE
	var last_vert: Vector3 = Vector3.ZERO
	var is_dirty: bool = false

	func begin(mode):
		if mode == Mesh.PRIMITIVE_LINE_STRIP:
			line_strip = 1

	func end():
		is_dirty = true
		line_strip = 0

	func set_color(color: Color):
		cur_color = color

	func add_vertex(v: Vector3):
		if line_strip > 2:
			color_array.append(cur_color)
			verts_array.append(last_vert)
		color_array.append(cur_color)
		verts_array.append(v)
		last_vert = v
		if line_strip > 0:
			line_strip += 1

	func _commit_arraymesh():
		if is_dirty:
			if mesh == null:
				mesh = ArrayMesh.new()
			mesh.clear_surfaces()
			var arrays = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_COLOR] = color_array
			arrays[Mesh.ARRAY_VERTEX] = verts_array
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays, [], {})
			is_dirty = false


class SecondaryGizmo:
	#extends ImmediateGeometry3D
	# https://github.com/godotengine/godot/issues/39451
	# We implement an umperformant line-only version of ImmediateGeometry3D for now.
	extends StubImmediateGeometry3D
	
	var secondary_node
	var m: StandardMaterial3D = StandardMaterial3D.new()


	func _init(parent):
		secondary_node = parent
		set_material()


	func set_material():
		m.no_depth_test = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


	func draw_in_editor(do_draw_spring_bones: bool = false):
		clear()
		if secondary_node.get_parent() is VRMTopLevel && secondary_node.get_parent().gizmo_spring_bone:
			draw_spring_bones(secondary_node.get_parent().gizmo_spring_bone_color)
			draw_collider_groups()
		_commit_arraymesh() # Remove when we can use the real ImmediateGometry3D


	func draw_in_game():
		clear()
		if secondary_node.get_parent() is VRMTopLevel && secondary_node.get_parent().gizmo_spring_bone:
			draw_spring_bones(secondary_node.get_parent().gizmo_spring_bone_color)
			draw_collider_groups()
		_commit_arraymesh() # Remove when we can use the real ImmediateGometry3D


	func draw_spring_bones(color: Color):
		set_material_override(m)
		# Spring bones
		for spring_bone in secondary_node.spring_bones_internal:
			for v in spring_bone.verlets:
				var s_tr: Transform3D = Transform3D.IDENTITY
				var s_sk: Skeleton3D = spring_bone.skel
				if Engine.is_editor_hint():
					s_sk = secondary_node.get_node_or_null(spring_bone.skeleton)
					s_tr = s_sk.get_bone_global_pose(v.bone_idx)
				else:
					s_tr = spring_bone.skel.get_bone_global_pose_no_override(v.bone_idx)
				draw_line(
					s_tr.origin,
					VRMTopLevel.VRMUtil.inv_transform_point(s_sk.global_transform, v.current_tail),
					color
				)
				draw_sphere(
					s_tr.basis,
					VRMTopLevel.VRMUtil.inv_transform_point(s_sk.global_transform, v.current_tail),
					spring_bone.hit_radius,
					color
				)


	func draw_collider_groups():
		set_material_override(m)
		for collider_group in (secondary_node.collider_groups if Engine.is_editor_hint() else secondary_node.collider_groups_internal):
			var c_tr = Transform3D.IDENTITY
			if Engine.is_editor_hint():
				var c_sk: Node = secondary_node.get_node_or_null(collider_group.skeleton_or_node)
				if c_sk is Skeleton3D:
					c_tr = c_sk.get_bone_global_pose(c_sk.find_bone(collider_group.bone))
			elif collider_group.parent is Skeleton3D:
				c_tr = collider_group.skel.get_bone_global_pose_no_override(collider_group.parent.find_bone(collider_group.bone))
			for collider in collider_group.sphere_colliders:
				var c_ps: Vector3 = VRMTopLevel.VRMUtil.coordinate_u2g(collider.normal)
				draw_sphere(c_tr.basis, VRMTopLevel.VRMUtil.transform_point(c_tr, c_ps), collider.d, collider_group.gizmo_color)


	func draw_line(begin_pos: Vector3, end_pos: Vector3, color: Color):
		begin(Mesh.PRIMITIVE_LINES)
		set_color(color)
		add_vertex(begin_pos)
		add_vertex(end_pos)
		end()


	func draw_sphere(bas: Basis, center: Vector3, radius: float, color: Color):
		var step: int = 16
		var sppi: float = 2 * PI / step
		begin(Mesh.PRIMITIVE_LINE_STRIP)
		set_color(color)
		for i in range(step + 1):
			add_vertex(center + (bas * Vector3.UP * radius).rotated(bas * Vector3.RIGHT, sppi * (i % step)))
		end()
		begin(Mesh.PRIMITIVE_LINE_STRIP)
		set_color(color)
		for i in range(step + 1):
			add_vertex(center + (bas * Vector3.RIGHT * radius).rotated(bas * Vector3.FORWARD, sppi * (i % step)))
		end()
		begin(Mesh.PRIMITIVE_LINE_STRIP)
		set_color(color)
		for i in range(step + 1):
			add_vertex(center + (bas * Vector3.FORWARD * radius).rotated(bas * Vector3.UP, sppi * (i % step)))
		end()
