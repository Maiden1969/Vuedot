extends ReadonlyRep
class_name ComputedRep

signal stop_called

var dirty := false:
	set(val):
		if val != dirty:
			dirty = val
			if dirty:
				_call_effects()
		pass
	get():
		return dirty

var update_func: Callable = Callable()
var stop_func: StopFunc = null

func bind(... args: Array[Variant]) -> ComputedRep:
	for arg in args:
		if not arg:
			continue
		if arg is Node:
			arg.tree_exiting.connect(stop, CONNECT_ONE_SHOT)
		elif arg is StopFunc:
			arg.stop_called.connect(stop, CONNECT_ONE_SHOT)
		elif arg is ComputedRep:
			arg.stop_called.connect(stop, CONNECT_ONE_SHOT)
	return self

func stop() -> void:
	if stop_func:
		stop_called.emit()
		stop_func.use()
		stop_func = null
	update_func = Callable()
	effects.clear()
	dirty = false
	pass
	
func _getter() -> Variant:
	if dirty:
		var saved = Vue._active_effects.duplicate()
		Vue._active_effects.clear()
		unsafe_set(update_func.call())
		Vue._active_effects = saved
		dirty = false
	Vue.track(self)
	return _value
	
func _to_string() -> String:
	return "ComputedRep(%s)" % value
