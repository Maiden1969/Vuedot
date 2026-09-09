extends RefCounted
class_name Reactive

var props: Dictionary = {}

func _init(dict: Dictionary = {}, deep: bool = true) -> void:
	for key in dict:
		props[key] = _wrap(dict[key], deep)
	pass

func _wrap(data: Variant, deep: bool = true) -> Variant:
	return Reactive.new(data) if data is Dictionary and deep else Vue.rep(data)
	
func _get(property: StringName) -> Variant:
	var item = props.get(property, null)
	if item != null:
		if item is Rep:
			return item.value
	return item

func _set(property: StringName, value: Variant) -> bool:
	if props.has(property):
		var item = props[property]
		if item is Rep:
			item.value = value
		else:
			props[property] = _wrap(value)
	else:
		props[property] = _wrap(value)
	return true

func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	for key in props:
		var prop_dict := {
			"name": key,
			"type": TYPE_NIL,
			"usage": PROPERTY_USAGE_DEFAULT,
		}
		properties.append(prop_dict)
	return properties

func rep(property: StringName) -> Rep:
	if props.has(property):
		var item = props[property]
		if item is Rep: 
			return item  
	return null
	
func get(key: StringName) -> Variant:
	return _get(key)

func set(key: StringName, val: Variant) -> void:
	_set(key, val)
	pass

func has(key: StringName) -> bool:
	return props.has(key)

func keys() -> Array[StringName]:
	var arr: Array[StringName] = []
	for k in props:
		arr.append(k)
	return arr
	
func to_dict() -> Dictionary:
	var result := {}
	for key in props:
		var item = props[key]
		if item is Reactive:
			result[key] = item.to_dict()
		elif item is Rep:
			result[key] = item.value
		else:
			result[key] = item
	return result

func _to_string() -> String:
	return "Reactive(%s)" % to_dict()


static func find_keys(script: Script, prop_name: StringName) -> Array[StringName]:
	var const_name := prop_name.to_upper() + "_PROPS"
	var const_map: Dictionary = script.get_script_constant_map()
	if const_map.has(const_name):
		return Array(const_map[const_name], TYPE_STRING_NAME, "", null)
	return []
