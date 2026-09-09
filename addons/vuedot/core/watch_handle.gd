extends RefCounted
class_name WatchHandle 

var effect: Callable
var dependencies: Dictionary
func _init(e: Callable, d: Dictionary):
	effect = e
	dependencies = d
	pass
