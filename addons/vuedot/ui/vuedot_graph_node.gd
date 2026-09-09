@tool
extends GraphNode
class_name VuedotGraphNode

var scene_path: NodePath
var input_slots: Dictionary = {}
var output_slots: Dictionary = {}
var output_port_count: int = 0
var input_port_count: int = 0

const SLOT_HEIGHT := 28.0
const BADGE_COLOR := VuedotUI.COLOR1
const META_NAME: StringName = Vuedot.META_NAME

func setup(path: NodePath, source_props: Array, target_props: Array) -> void:
	scene_path = path
	var root := EditorInterface.get_edited_scene_root()
	var node := root.get_node(path)
	title = node.name
	auto_translate = false

	# Clear previous state to prevent slot accumulation on reuse
	clear_all_slots()
	input_slots.clear()
	output_slots.clear()
	output_port_count = 0
	input_port_count = 0
	for child in get_children():
		child.queue_free()

	var slot_idx := 0
	var left_port_idx := 0
	var right_port_idx := 0

	for prop_name in source_props:
		var row := _make_row()
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(8, SLOT_HEIGHT)
		row.add_child(spacer)

		var label := Label.new()
		label.text = prop_name
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		add_child(row)

		set_slot(slot_idx, true, 0, Color.LIME_GREEN, false, 0, Color(0, 0, 0, 0))
		input_slots[prop_name] = left_port_idx
		input_port_count += 1
		left_port_idx += 1
		slot_idx += 1

	for prop_name in target_props:
		var row := _make_row()
		var label := Label.new()
		label.text = prop_name
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var badge := Label.new()
		badge.text = "Rep"
		badge.add_theme_color_override("font_color", BADGE_COLOR)
		#badge.add_theme_font_size_override("font_size", 10)
		row.add_child(badge)

		add_child(row)
		set_slot(slot_idx, false, 0, Color(0, 0, 0, 0), true, 0, BADGE_COLOR)
		output_slots[prop_name] = right_port_idx
		output_port_count += 1
		right_port_idx += 1
		slot_idx += 1

	var total_rows := max(slot_idx, 1)
	custom_minimum_size = Vector2(200, total_rows * SLOT_HEIGHT)
	size = Vector2(220, total_rows * SLOT_HEIGHT)

func _make_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	return row
