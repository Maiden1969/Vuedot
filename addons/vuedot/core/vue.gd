extends Node
# Auto-Load
# class_name Vue

var _active_effects: Array[Callable] = []
var _dependencies: Array[Dictionary] = []
var _handles: Dictionary[WatchHandle, StopFunc] = {}
var _pending_effects: Dictionary[Callable, bool] = {}
var _execute_request: bool = false

func _enter_tree() -> void:
	var tree := get_tree()
	tree.node_added.connect(
		func(node: Node): 
			if node.has_meta(Vuedot.META_NAME):
				node.ready.connect(_auto_bind.bind(node), CONNECT_ONE_SHOT))
	pass
	
func _exit_tree() -> void:
	dispose()
	pass
	
func _auto_bind(root: Node) -> void:
	var records = root.get_meta(Vuedot.META_NAME)
	for record in records:
		var source := root.get_node(record.source_path)
		var target := root.get_node(record.target_path)
		var source_prop_name: StringName = record.source_prop_name
		var target_prop_name: StringName = record.target_prop_name
		var data = null
		
		if "." in target_prop_name:
			var parts := target_prop_name.split(".")
			var size := parts.size()
			var reactive = target
			for i in range(size - 1):
				if not reactive:
					return
				reactive = reactive.get(parts[i])
			if reactive and reactive is Reactive:
				data = reactive.rep(parts[size - 1])
		else:
			data = target.get(target_prop_name)
		
		if data and data is Rep:
			bind(source, record.source_prop_name, data, record.config.deferred).bind(target)
	
	root.remove_meta(Vuedot.META_NAME)
	pass
	

func schedule_batch(es: Array[Callable]) -> void:
	for e in es:
		_pending_effects[e] = true
	if not _execute_request:
		_execute_request = true
		execute.call_deferred()

func execute() -> void:
	_execute_request = false
	var _effects = _pending_effects.keys()
	_pending_effects.clear()
	for e in _effects:
		e.call()
	pass

func track(data: Rep) -> void:
	if not _active_effects.is_empty():
		_dependencies.back()[data] = true
	pass

func collect_deps(e: Callable) -> Dictionary:
	_active_effects.push_back(e)
	_dependencies.push_back({})
	e.call()
	_active_effects.pop_back()
	return _dependencies.pop_back()

func watch(v: Variant, e: Callable, call_instantly: bool = false, deferred: bool = true) -> StopFunc:
	var arg_count := e.get_argument_count()

	var sources: Array = v if v is Array else [v]
	var reps: Array[Rep] = []
	var computed_reps: Array[ComputedRep] = []

	for src in sources:
		if src is Rep:
			reps.append(src)
		elif src is Callable:
			var cr := computed(src)
			reps.append(cr)
			computed_reps.append(cr)

	var old_vals := reps.map(func(r): return r.value)
	var effect: Callable = func():
		var new_vals = reps.map(func(r): return r.value)
		var changed := false
		for i in new_vals.size():
			if not is_same(new_vals[i], old_vals[i]):
				changed = true
				break

		if changed:
			if arg_count == 0:
				e.call()
			elif arg_count == 2:
				if new_vals.size() == 1:
					e.call(new_vals[0], old_vals[0])
				else:
					e.call(new_vals.duplicate(), old_vals)
		old_vals = new_vals

	for dep in reps:
		dep.add_effect(effect, deferred)
	var unique_reps: Dictionary = {}
	for dep in reps:
		unique_reps[dep] = true

	var handle := WatchHandle.new(effect, unique_reps)
	var stop_func := StopFunc.new(handle)
	_handles[handle] = stop_func
	for cr in computed_reps:
		cr.bind(stop_func)

	if call_instantly:
		if reps.size() == 1:
			e.call(old_vals[0], old_vals[0])
		else:
			var old_vals_copy := old_vals.duplicate()
			e.call(old_vals_copy, old_vals_copy)

	return stop_func
	
	
func remove_handle(handle: WatchHandle) -> void:
	_handles.erase(handle)
	pass

func watch_effect(e: Callable, deferred: bool = true) -> StopFunc:
	var deps := collect_deps(e)
	for dep in deps:
		dep.add_effect(e, deferred)

	var handle := WatchHandle.new(e, deps)
	var stop_func := StopFunc.new(handle)
	_handles[handle] = stop_func

	return stop_func

func rep(val: Variant) -> Rep:
	return val as Rep if val is Rep else Rep.new(val)

func unrep(data: Variant) -> Variant:
	return data.value if data is Rep else data

func readonly(val: Variant) -> ReadonlyRep:
	return val as ReadonlyRep if val is ReadonlyRep else ReadonlyRep.new(unrep(val))

func reactive(data: Variant, deep: bool = true) -> Reactive:
	if data is Dictionary:
		return Reactive.new(data, deep)
	elif data is Object:
		var data_script: Script = data.get_script()
		if data_script:
			var dict := {}
			var dict_list: Array[Dictionary] = data_script.get_script_property_list()
			var first := true
			for prop_dict in dict_list:
				if first:
					first = false
					continue
				var prop_name := StringName(prop_dict.name)
				dict[prop_name] = data.get(prop_name)
			return Reactive.new(dict, deep) 
	return Reactive.new()
	
func shallow_reactive(data: Variant) -> Reactive:
	return reactive(data, false)
	
func computed(f: Callable) -> ComputedRep:
	var res: ComputedRep = ComputedRep.new(null)

	var first := [true]
	var e := func():
		if first[0]:
			res.unsafe_set(f.call())
			res.dirty = false
			first[0] = false
		else:
			res.dirty = true
		pass

	res.stop_func = watch_effect(e, false)
	res.update_func = f

	return res
	
func bind(node: Node, prop: StringName, arg: Variant, deferred: bool = true) -> StopFunc:
	if node == null or arg == null:
		return null
	
	if arg is Callable:
		return watch_effect(func(): if node: node.set(prop, arg.call()), true).bind(node)
	elif arg is Rep:
		return watch_effect(func(): if node: node.set(prop, arg.value), true).bind(node)
		
	return null
	
func scope(node: Node) -> VueScope:
	return VueScope.new(node)

func dispose() -> void:
	for handle in _handles:
		for data in handle.dependencies:
			if data is ComputedRep:
				data.stop()
			else:
				data.remove_effect(handle.effect)
	_active_effects.clear()
	_dependencies.clear()
	_handles.clear()
	_pending_effects.clear()
	_execute_request = false
	pass
