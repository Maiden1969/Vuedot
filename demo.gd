extends Node2D

var data: Rep = Vue.rep(0);

func _ready() -> void:
	$Button.pressed.connect(func(): data.value += 1)
	pass
