@tool
extends GraphEdit
class_name VuedotGraph

const META_NAME: StringName = &"vuedot_bind_records"
const COL_X := [80.0, 360.0, 640.0]
const ROW_GAP := 50.0
const TOP_MARGIN := 40.0

var dirty: bool = true
var _cached_root_id: int = 0

func refresh() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var current_root_id := root.get_instance_id() if root else 0

	if not dirty and current_root_id == _cached_root_id:
		return

	_clear()
	if root == null:
		_cached_root_id = 0
		dirty = true
		_show_label("请打开一个场景")
		return

	var records := _collect_valid_records(root)
	if records.is_empty():
		_cached_root_id = current_root_id
		dirty = true
		_show_label("当前场景没有绑定数据")
		return

	_build(root, records)
	_cached_root_id = current_root_id
	dirty = false
	
func _clear() -> void:
	clear_connections()
	for child in get_children():
		if child is GraphNode or child is Label:
			remove_child(child)
			child.queue_free()
	pass

func _show_label(text: String) -> void:
	_clear()
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	add_child(label)

func _has_property(node: Node, prop_name: StringName) -> bool:
	for prop in node.get_property_list():
		if prop.name == prop_name:
			return true
	return false

func _has_script_property(node: Node, prop_name: StringName) -> bool:
	var script: Script = node.get_script()
	if script == null:
		return false

	# Reactive sub-properties use dotted names (e.g. "data.hp").
	if "." in prop_name:
		var parts := prop_name.split(".", true, 1)
		var root_name: String = parts[0]
		var sub_key: String = parts[1]
		# Validate root name exists as a Reactive script property
		var found_root := false
		for prop in script.get_script_property_list():
			if prop.name == root_name and prop.class_name == "Reactive":
				found_root = true
				break
		if not found_root:
			return false
		# Validate sub-key exists in the companion const
		var valid_keys := Reactive.find_keys(script, root_name)
		return valid_keys.has(sub_key)
	else:
		for prop in script.get_script_property_list():
			if prop.name == prop_name:
				return prop.class_name == "Rep" or prop.class_name == "ReadonlyRep" or prop.class_name == "ComputedRep" or prop.class_name == "Reactive"
		return false

func _collect_valid_records(root: Node) -> Array:
	if not root.has_meta(META_NAME):
		return []

	var records: Array = root.get_meta(META_NAME)
	var valid: Array = []
	for rec in records:
		var sp: NodePath = rec.source_path
		var tp: NodePath = rec.target_path

		if not root.has_node(sp) or not root.has_node(tp):
			continue

		if not _has_property(root.get_node(sp), rec.source_prop_name):
			continue
		if not _has_script_property(root.get_node(tp), rec.target_prop_name):
			continue

		valid.append(rec)
	return valid


func _build(root: Node, records: Array) -> void:
	# --- Aggregate by node path ---
	var node_map := {}

	for rec in records:
		var sp: NodePath = rec.source_path
		var tp: NodePath = rec.target_path

		# Source node (property owner)
		if not node_map.has(sp):
			var sn := root.get_node(sp)
			node_map[sp] = {"name": sn.name, "class": sn.get_class(), "source_props": [], "target_props": []}
		var src_data = node_map[sp]
		if not src_data.source_props.has(rec.source_prop_name):
			src_data.source_props.append(rec.source_prop_name)

		# Target node (Rep owner)
		if not node_map.has(tp):
			var tn := root.get_node(tp)
			node_map[tp] = {"name": tn.name, "class": tn.get_class(), "source_props": [], "target_props": []}
		var tgt_data = node_map[tp]
		if not tgt_data.target_props.has(rec.target_prop_name):
			tgt_data.target_props.append(rec.target_prop_name)

	# --- Classify into 3 columns ---
	var layers := [[], [], []]

	for path in node_map:
		var d = node_map[path]
		var has_src: bool = not d.source_props.is_empty()
		var has_tgt: bool = not d.target_props.is_empty()
		if has_src and has_tgt:
			layers[1].append(path)
		elif has_tgt:
			layers[0].append(path)
		else:
			layers[2].append(path)

	# Sort each layer by node name
	for layer in layers:
		layer.sort_custom(func(a, b): return node_map[a].name.nocasecmp_to(node_map[b].name) < 0)

	# --- Create GraphNodes ---
	var graph_nodes := {}
	var col_y := [TOP_MARGIN, TOP_MARGIN, TOP_MARGIN]

	for col in range(3):
		for path in layers[col]:
			var d = node_map[path]
			var gn = _create_graph_node(path, d)
			gn.position_offset = Vector2(COL_X[col], col_y[col])
			col_y[col] += gn.size.y + ROW_GAP
			graph_nodes[path] = gn

	# --- Create connections ---
	for rec in records:
		var sp: NodePath = rec.source_path
		var tp: NodePath = rec.target_path

		var src_gn = graph_nodes.get(sp)
		var tgt_gn = graph_nodes.get(tp)
		if src_gn == null or tgt_gn == null:
			continue

		var from_port: int = tgt_gn.output_slots.get(rec.target_prop_name, -1)
		var to_port: int = src_gn.input_slots.get(rec.source_prop_name, -1)
		if from_port < 0 or to_port < 0:
			continue

		# Guard against port index out of bounds (prevents godot engine crash)
		if from_port >= tgt_gn.output_port_count:
			push_warning("VuedotGraph: from_port %d out of bounds for node '%s' (right ports: %d)" % [from_port, tgt_gn.name, tgt_gn.output_port_count])
			continue
		if to_port >= src_gn.input_port_count:
			push_warning("VuedotGraph: to_port %d out of bounds for node '%s' (left ports: %d)" % [to_port, src_gn.name, src_gn.input_port_count])
			continue

		connect_node(tgt_gn.name, from_port, src_gn.name, to_port)

func _create_graph_node(path: NodePath, data: Dictionary):
	var gn := preload("res://addons/vuedot/ui/vuedot_graph_node.tscn").instantiate()
	gn.setup(path, data.source_props, data.target_props)
	gn.name = "gn_" + str(path.hash())
	add_child(gn)
	return gn
	
func _on_connection_request(_from_node: StringName, _from_port: int, _to_node: StringName, _to_port: int) -> void:
	pass

func _on_disconnection_request(_from_node: StringName, _from_port: int, _to_node: StringName, _to_port: int) -> void:
	pass

func _ready() -> void:
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)

	add_theme_color_override("activity", Color(0.4, 0.7, 1.0, 0.5))
	pass
