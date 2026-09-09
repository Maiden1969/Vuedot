extends RefCounted
class_name Rep

var effects: Dictionary[Callable, bool] = {}
var _batch: Array[Callable] = []

var _value: Variant = null
var value: get = _getter, set = _setter
		

func add_effect(e: Callable, deferred: bool = true) -> void:
	effects[e] = deferred
	pass
	
func remove_effect(e: Callable) -> void:
	effects.erase(e)
	pass

func unsafe_set(val: Variant) -> void:
	_value = val
	pass
	
func _call_effects() -> void:
	for e in effects:
		if effects[e]:
			_batch.append(e)
		else:
			e.call()
	if not _batch.is_empty():
		Vue.schedule_batch(_batch)
		_batch.clear()
	pass
		
func _setter(val: Variant) -> void:
	if not is_same(val, _value):
		_value = val
		_call_effects()
	pass

func _getter() -> Variant:
	Vue.track(self)
	return _value

func _init(val: Variant) -> void:
	_value = val
	pass
	
func _to_string() -> String:
	return "Rep(%s)" % value
