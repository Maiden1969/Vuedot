extends Rep
class_name ReadonlyRep

func _setter(_val: Variant) -> void:
	pass

func _to_string() -> String:
	return "ReadonlyRep(%s)" % value
