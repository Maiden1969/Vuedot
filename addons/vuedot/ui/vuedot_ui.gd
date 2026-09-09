@tool
extends EditorPlugin
class_name VuedotUI

# theme color
const COLOR1 := Color(0.392, 0.584, 0.929, 1.0)
const COLOR2 := Color.SEA_GREEN

# global states
var selected_nodes: Array[Node] = []
var selected_node: Node = null
var selected_node_path: NodePath = NodePath()
var selection: EditorSelection = null
var cur_source_path: NodePath = NodePath()
var cur_source_prop_name: StringName = &""
var cur_target_path: NodePath = NodePath()
var cur_target_prop_name: StringName = &""
var is_trigger_deferred: bool = true

# dock, dialog window and trees
var dock: EditorDock = null
var property_tree: Tree = null
var bind_tree: Tree = null
var btn: Button = null
var category_item: TreeItem = null
var group_item: TreeItem = null
var sub_group_item: TreeItem = null
var btn_icon: Texture2D = null
var unlinked_icon: Texture2D = null
var dialog_window: ConfirmationDialog = null
var scene_tree: Tree = null
var rep_tree: Tree = null
var config_deferred_btn: CheckButton = null

# dependency graph
var tab_container: TabContainer = null
var vue_graph: VuedotGraph = null  

const META_NAME := Vuedot.META_NAME

func _remove_record(path: NodePath, source: StringName) -> void:
	var root := EditorInterface.get_edited_scene_root()

	if root == null or not root.has_meta(META_NAME):
		return

	print("Vuedot: 移除属性的绑定记录")
	
	var records: Array = root.get_meta(META_NAME)
	records = records.filter(
		func(rec): return not (
			rec.source_path == path and
			rec.source_prop_name == source)
	)

	if records.is_empty():
		root.remove_meta(META_NAME)
	else:
		root.set_meta(META_NAME, records)
	if vue_graph:
		vue_graph.dirty = true
	pass

func _add_record(source_path: NodePath, target_path: NodePath, source: StringName, target: StringName, config: Dictionary = {}) -> void:
	var root := EditorInterface.get_edited_scene_root()

	if root == null:
		return
	var records: Array = []
	if root.has_meta(META_NAME):
		records = root.get_meta(META_NAME)

	records.append({
		"source_path" : source_path,
		"source_prop_name" : source,
		"target_path" : target_path,
		"target_prop_name": target,
		"config": config
	})

	if records.is_empty():
		root.remove_meta(META_NAME)
	else:
		root.set_meta(META_NAME, records)
	if vue_graph:
		vue_graph.dirty = true
	pass

func _in_records(path: NodePath, prop_name: StringName) -> bool:
	var root := EditorInterface.get_edited_scene_root()

	if root == null or not root.has_meta(META_NAME):
		return false
	var records: Array = root.get_meta(META_NAME)
	var result := records.filter(
		func(rec): return rec.source_path == path and rec.source_prop_name == prop_name
	)
	return not result.is_empty()

func _in_records_with_root(prop_name: StringName) -> bool:
	var node := selected_node

	if node == null or not node.has_meta(META_NAME):
		return false
	var records: Array = node.get_meta(META_NAME)
	var result := records.filter(
		func(rec): return rec.source_path == NodePath(".") and rec.source_prop_name == prop_name
	)
	return not result.is_empty()

func _get_records_by_source(path: NodePath) -> Array:
	var root := EditorInterface.get_edited_scene_root()

	if root == null or not root.has_meta(META_NAME):
		return []
	var records: Array = root.get_meta(META_NAME)
	var result := records.filter(
		func(rec): return rec.source_path == path
	)
	return result

func _check_update() -> void:
	var root := EditorInterface.get_edited_scene_root()

	if root == null or not root.has_meta(META_NAME):
		return

	var records: Array = root.get_meta(META_NAME)
	var old_count := records.size()
	records = records.filter(
		func(rec): return root.has_node(rec.source_path) and root.has_node(rec.target_path)
	)
	if records.is_empty():
		root.remove_meta(META_NAME)
		if vue_graph:
			vue_graph.dirty = true
	else:
		root.set_meta(META_NAME, records)
		if records.size() != old_count and vue_graph:
			vue_graph.dirty = true
	pass

func _remove_meta_data_by_path(scene_path: String) -> void:
	var file := FileAccess.open(scene_path, FileAccess.READ)
	if file == null:
		printerr("Vuedot: 无法打开场景文件: ", scene_path)
		return

	var lines: Array[String] = []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()

	# 找到根节点 section 的范围（第一个不带 parent 属性的 [node ...]）
	var root_start := -1
	var root_end := lines.size()

	for i in lines.size():
		var line: String = lines[i]
		if line.begins_with("[node ") and not "parent=" in line:
			root_start = i
		elif root_start != -1 and (line.begins_with("[node ") or line.begins_with("[ext_resource")):
			root_end = i
			break

	if root_start == -1:
		printerr("Vuedot: 场景文件中没有找到根节点: ", scene_path)
		return

	# 在根节点范围内移除 metadata/vuedot_bind_records 及其续行
	var meta_key := "metadata/" + META_NAME
	var i := root_start + 1
	while i < root_end:
		var line: String = lines[i]
		if line.strip_edges().begins_with(meta_key):
			lines.remove_at(i)
			root_end -= 1
			# 移除后续的缩进续行（数组/字典多行值）
			while i < root_end and (lines[i].begins_with("\t") or lines[i].begins_with(" ")):
				lines.remove_at(i)
				root_end -= 1
		else:
			i += 1

	# 写回文件
	file = FileAccess.open(scene_path, FileAccess.WRITE)
	if file == null:
		printerr("Vuedot: 无法写入场景文件: ", scene_path)
		return

	for line in lines:
		file.store_line(line)
	file.close()
	print("Vuedot: 已移除场景元数据: ", scene_path)

func _get_dialog_window() -> ConfirmationDialog:
	if not dialog_window:
		dialog_window = preload("res://addons/vuedot/ui/vue_dialog.tscn").instantiate()
		dialog_window.confirmed.connect(_on_confirmed)
		dialog_window.hide()
		EditorInterface.get_base_control().add_child(dialog_window)
		scene_tree = dialog_window.get_node("VBoxContainer/SceneTreeContainer/Panel/SceneTree")
		scene_tree.item_selected.connect(_on_node_selected)
		rep_tree = dialog_window.get_node("VBoxContainer/RepTreeContainer/Panel/RepTree")
		rep_tree.item_selected.connect(_on_property_selected)
		config_deferred_btn = dialog_window.get_node("VBoxContainer/ConfigContainer/HBoxContainer/ConfigDeferred")
		config_deferred_btn.toggled.connect(func(state): is_trigger_deferred = state)
	return dialog_window

func _on_selection_changed() -> void:
	var root := EditorInterface.get_edited_scene_root()
	selected_nodes = selection.get_selected_nodes()
	if selected_nodes.size() != 1:
		selected_node = null
		selected_node_path = NodePath()
		property_tree.clear()
		bind_tree.clear()
		btn.disabled = true
	else:
		selected_node = selected_nodes[0]
		selected_node_path = root.get_path_to(selected_node)
		if selected_node == root:
			_check_update()
		_build_property_and_bind_tree()
	pass

func _has_property(node: Node, prop_name: StringName) -> bool:
	var prop_list := node.get_property_list()
	for prop in prop_list:
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
		# Validate root name exists as a script property
		var found_root := false
		for prop in script.get_script_property_list():
			if prop.name == root_name:
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
				return true
		return false

func _build_property_and_bind_tree() -> void:
	var root := EditorInterface.get_edited_scene_root()

	if selected_node == null or root == null:
		return

	var node = selected_node
	var path = selected_node_path

	btn.disabled = true
	property_tree.clear()
	property_tree.set_column_title(0, "属性")
	property_tree.set_column_title(1, "类型")
	property_tree.create_item()

	var records := _get_records_by_source(path)
	var props := node.get_property_list()

	# 预构建源节点属性名集合，避免下面 records 循环中重复扫描
	var source_prop_names := {}
	for prop in props:
		source_prop_names[prop.name] = true

	for prop in props:
		var usage = prop.usage
		var is_script = prop.name == "script"
		var is_meta_data = prop.name.begins_with("metadata/")
		var is_category = usage & PROPERTY_USAGE_CATEGORY
		var is_group = usage & PROPERTY_USAGE_GROUP
		var is_sub_group = usage & PROPERTY_USAGE_SUBGROUP

		var item: TreeItem = null

		if is_script or is_meta_data:
			continue

		if is_category:
			item = property_tree.create_item()
			item.set_text(1, "")
			item.collapsed = true
			category_item = item
			group_item = null
			sub_group_item = null
		elif is_group:
			item = property_tree.create_item(category_item)
			item.set_text(1, "")
			item.collapsed = true
			group_item = item
			sub_group_item = null
		elif is_sub_group:
			item = property_tree.create_item(group_item)
			item.set_text(1, "")
			item.collapsed = true
			sub_group_item = item
		else:
			var parent_item = sub_group_item if sub_group_item else (group_item if group_item else category_item)
			item = property_tree.create_item(parent_item)
			item.set_text(1, prop.class_name if prop.type == TYPE_OBJECT else type_string(prop.type))
			if _in_records(root.get_path_to(node), prop.name):
				item.set_custom_color(0, COLOR2)
				item.set_custom_color(1, COLOR2)
				item.set_selectable(0, false)
				item.set_selectable(1, false)
				item.add_button(1, unlinked_icon, 0, false, "解绑")
				item.set_button_color(1, 0, COLOR1)
			if _in_records_with_root(prop.name):
				item.set_custom_color(0, COLOR2)
				item.set_custom_color(1, COLOR2)
				item.set_selectable(0, false)
				item.set_selectable(1, false)

		item.set_text(0, prop.name)
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)

	group_item = null
	sub_group_item = null
	category_item = null

	bind_tree.clear()
	bind_tree.set_column_title(0, "属性")
	bind_tree.set_column_title(1, "绑定")
	bind_tree.create_item()

	for rec in records:
		var target_node := root.get_node(rec.target_path)

		# 检查记录是否已过期（节点属性列表发生了变化）
		if target_node == null \
			or (not source_prop_names.has(rec.source_prop_name)) \
			or (not _has_script_property(target_node, rec.target_prop_name)):
			_remove_record(path, rec.source_prop_name)
			continue
		var item = bind_tree.create_item()
		item.set_text(0, rec.source_prop_name)
		item.set_text(1, target_node.name + "." + rec.target_prop_name)
		item.set_text_alignment(0, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)
		item.add_button(1, btn_icon, -1, false, "解绑")
		item.set_button_color(1, 0, COLOR1)

	pass

func _build_scene_tree(root_node: Node, root_item: TreeItem = null) -> void:
	var root := EditorInterface.get_edited_scene_root()

	if root_node == null:
		return
	var children: Array[Node] = root_node.get_children(false)
	var item = scene_tree.create_item(root_item)
	item.set_text(0, root_node.name)
	item.set_icon(0, EditorInterface.get_base_control().get_theme_icon(root_node.get_class(), "EditorIcons"))
	item.set_metadata(0, root.get_path_to(root_node))
	for child in children:
		_build_scene_tree(child, item)
	pass

func _build_rep_tree() -> void:
	var root := EditorInterface.get_edited_scene_root()

	var node := root.get_node(cur_target_path)
	if node == null:
		return

	var root_item := rep_tree.create_item()
	root_item.set_selectable(0, false)

	if node == null:
		root_item.set_text(0, "选择一个节点")
		return

	var script: Script = node.get_script()
	if script == null:
		root_item.set_text(0, "选中的节点上没有脚本")
		return

	var props := script.get_script_property_list()
	for prop in props:
		if prop.class_name == "Rep" or prop.class_name == "ReadonlyRep" or prop.class_name == "ComputedRep":
			var item := rep_tree.create_item()
			item.set_text(0, prop.name)
		elif prop.class_name == "Reactive":
			var item := rep_tree.create_item()
			item.set_text(0, prop.name)
			item.set_selectable(0, false)
			item.collapsed = true
			for key in Reactive.find_keys(script, prop.name):
				var recursive_item: TreeItem = item
				var parts := key.split(".")
				for i in range(parts.size()):
					recursive_item = rep_tree.create_item(recursive_item)
					recursive_item.set_text(0, parts[i])
					recursive_item.set_selectable(0, false)
					recursive_item.collapsed = true
				recursive_item.set_selectable(0, true)
				
	if root_item.get_child_count() == 0:
		root_item.set_text(0, "脚本中没有定义响应式数据")
	else:
		root_item.set_text(0, "选择要绑定的响应式数据")
	pass


# for property tree
func _on_item_selected() -> void:
	var item: TreeItem = property_tree.get_selected()
	if item == null:
		return
	if item.get_child_count() == 0:
		cur_source_prop_name = item.get_text(0)
		btn.disabled = false
	else:
		btn.disabled = true
	pass

# for scene tree
func _on_node_selected() -> void:
	var item: TreeItem = scene_tree.get_selected()
	if item == null:
		return
	cur_target_path = item.get_metadata(0)
	rep_tree.clear()
	_build_rep_tree()
	pass

# for rep tree
func _on_property_selected() -> void:
	var item: TreeItem = rep_tree.get_selected()
	if item == null:
		return
	if item.get_child_count() == 0:
		dialog_window.get_ok_button().disabled = false
		cur_target_prop_name = item.get_text(0)
		while true:
			item = item.get_parent()
			if not item or not item.get_parent():
				break
			cur_target_prop_name = item.get_text(0) + "." + cur_target_prop_name
	else:
		dialog_window.get_ok_button().disabled = true
	pass

# for vue dock
func _on_btn_pressed() -> void:
	var root := EditorInterface.get_edited_scene_root()

	cur_source_path = selected_node_path
	var dialog := _get_dialog_window()
	dialog.popup_centered()
	dialog.get_ok_button().disabled = true
	scene_tree.clear()
	rep_tree.clear()
	_build_scene_tree(root)
	pass

# for property tree and bind tree
func _on_tree_btn_pressed(item: TreeItem, _column: int, _id: int, _mouse_button_index: int) -> void:
	var root := EditorInterface.get_edited_scene_root()

	if item == null or selected_node == null or root == null or not root.has_meta(META_NAME):
		return

	var source_prop_name: StringName = item.get_text(0)

	_remove_record(selected_node_path, source_prop_name)
	_build_property_and_bind_tree()
	pass


func _get_config() -> Dictionary:
	var config := {}
	config["deferred"] = is_trigger_deferred
	return config

# for vue dialog
func _on_confirmed() -> void:
	var root := EditorInterface.get_edited_scene_root()

	if root == null:
		return
	_add_record(cur_source_path, cur_target_path, cur_source_prop_name, cur_target_prop_name, _get_config())
	_build_property_and_bind_tree()
	pass


func _enter_tree() -> void:
	# --- instantiate the existing property / bind dock ---
	var dock_scene := preload("res://addons/vuedot/ui/vue_dock.tscn").instantiate()

	btn = dock_scene.get_node("MarginContainer/VBoxContainer/HBoxContainer/Button")
	btn.pressed.connect(_on_btn_pressed)

	btn_icon = EditorInterface.get_base_control().get_theme_icon("Close", "EditorIcons")
	unlinked_icon = EditorInterface.get_base_control().get_theme_icon("Unlinked", "EditorIcons")

	property_tree = dock_scene.get_node("MarginContainer/VBoxContainer/PropTree")
	property_tree.item_selected.connect(_on_item_selected)
	property_tree.button_clicked.connect(_on_tree_btn_pressed)

	bind_tree = dock_scene.get_node("MarginContainer/VBoxContainer/BindTree")
	bind_tree.button_clicked.connect(_on_tree_btn_pressed)

	vue_graph = preload("res://addons/vuedot/ui/vuedot_graph.tscn").instantiate()
	vue_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vue_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vue_graph.minimap_enabled = true
	vue_graph.show_grid = true
	vue_graph.right_disconnects = false
	vue_graph.zoom_max = 5.0
	vue_graph.zoom_min = 0.2
	vue_graph.node_selected.connect(_on_graph_node_selected)

	var graph_tab := Control.new()
	graph_tab.name = "依赖图"
	graph_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vue_graph.anchor_left = 0.0
	vue_graph.anchor_top = 0.0
	vue_graph.anchor_right = 1.0
	vue_graph.anchor_bottom = 1.0
	graph_tab.add_child(vue_graph)

	tab_container = TabContainer.new()
	tab_container.name = "VuedotTabs"
	tab_container.anchor_left = 0.0
	tab_container.anchor_top = 0.0
	tab_container.anchor_right = 1.0
	tab_container.anchor_bottom = 1.0

	var props_tab := Control.new()
	props_tab.name = "属性绑定"
	props_tab.anchor_left = 0.0
	props_tab.anchor_top = 0.0
	props_tab.anchor_right = 1.0
	props_tab.anchor_bottom = 1.0
	props_tab.add_child(dock_scene)
	tab_container.add_child(props_tab)

	graph_tab.anchor_left = 0.0
	graph_tab.anchor_top = 0.0
	graph_tab.anchor_right = 1.0
	graph_tab.anchor_bottom = 1.0
	tab_container.add_child(graph_tab)
	tab_container.tab_changed.connect(_on_tab_changed)

	selection = EditorInterface.get_selection()
	selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()

	dock = EditorDock.new()
	dock.add_child(tab_container)
	dock.title = "Vuedot"
	dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	add_dock(dock)

	pass

func _exit_tree() -> void:
	btn.pressed.disconnect(_on_btn_pressed)
	bind_tree.button_clicked.disconnect(_on_tree_btn_pressed)
	property_tree.item_selected.disconnect(_on_item_selected)
	property_tree.button_clicked.disconnect(_on_tree_btn_pressed)
	selection.selection_changed.disconnect(_on_selection_changed)
	selected_node = null
	selected_nodes = []

	if tab_container:
		tab_container.tab_changed.disconnect(_on_tab_changed)

	remove_dock(dock)
	dock.queue_free()
	if dialog_window:
		if dialog_window.get_parent():
			dialog_window.get_parent().remove_child(dialog_window)
		if dialog_window.confirmed.is_connected(_on_confirmed):
			dialog_window.confirmed.disconnect(_on_confirmed)
		dialog_window.queue_free()
	vue_graph = null
	tab_container = null
	pass

func _on_tab_changed(tab_index: int) -> void:
	if tab_index == 1 and vue_graph:  # Graph tab
		vue_graph.refresh()


func _on_graph_node_selected(node: GraphNode) -> void:
	if not "scene_path" in node:
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null or selection == null:
		return
	var target := root.get_node(node.scene_path)
	if target:
		selection.clear()
		selection.add_node(target)
		EditorInterface.edit_node(target)
