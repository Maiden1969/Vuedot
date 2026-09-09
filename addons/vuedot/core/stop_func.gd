extends RefCounted
class_name StopFunc

var _stopped := false
var _handle: WatchHandle = null

signal stop_called

func bind(... args: Array[Variant]) -> StopFunc:
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

func use() -> void:
	if _stopped or not _handle:
		return
	_stopped = true
	stop_called.emit()
	for dep in _handle.dependencies:
		dep.remove_effect(_handle.effect)
	Vue.remove_handle(_handle)
	_handle = null  
	pass

func stop() -> void:
	use()
	pass

func _init(handle: WatchHandle) -> void:
	_handle = handle
	pass
