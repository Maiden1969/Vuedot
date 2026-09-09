@tool
extends EditorPlugin
class_name Vuedot

const META_NAME: StringName = &"vuedot_bind_records"
const PLUGIN_NAME: StringName = &"vuedot"

func _enable_plugin() -> void:
	EditorInterface.set_plugin_enabled(PLUGIN_NAME + "/ui", true)
	add_autoload_singleton("Vue", "res://addons/vuedot/core/vue.gd")
	pass
	
func _disable_plugin() -> void:
	EditorInterface.set_plugin_enabled(PLUGIN_NAME + "/ui", false)
	remove_autoload_singleton("Vue")
	pass
