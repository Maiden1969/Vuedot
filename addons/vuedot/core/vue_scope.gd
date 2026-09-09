extends RefCounted
class_name VueScope

var _target: WeakRef = null

static func is_supported(target: Variant) -> bool:
	return target != null and (target is Node or target is StopFunc or target is ComputedRep)

func _is_valid() -> bool:
	return is_instance_valid(_target.get_ref())

func _init(target: Variant) -> void:
	if not is_supported(target):
		return
	_target = weakref(target)
	pass
	
func rep(val: Variant) -> Rep:
	return Vue.rep(val)
	
func readonly(val: Variant) -> ReadonlyRep:
	return Vue.readonly(val)
	
func reactive(data: Variant, deep: bool = true) -> Reactive:
	return Vue.reactive(data, deep)

func computed(f: Callable) -> ComputedRep:
	if _is_valid():
		return Vue.computed(f).bind(_target.get_ref())
	return null

func watch_effect(e: Callable, deferred: bool = true) -> StopFunc:
	if _is_valid():
		return Vue.watch_effect(e, deferred).bind(_target.get_ref())
	return null

func watch(v: Variant, e: Callable, call_instantly: bool = false, deferred: bool = true) -> StopFunc:
	if _is_valid():
		return Vue.watch(v, e, call_instantly, deferred).bind(_target.get_ref())
	return null

func bind(node: Node, prop: StringName, arg: Variant, deferred: bool = true) -> StopFunc:
	if _is_valid():
		return Vue.bind(node, prop, arg, deferred).bind(_target.get_ref())
	return null
