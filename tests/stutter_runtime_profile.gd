extends "res://tests/journey_runtime_budget.gd"

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	node_added.connect(func(node:Node)->void:
		if node.get_script()!=null and node.get_script().resource_path=="res://scripts/journey_view.gd":
			node.play_mode="local"
			node.opening_enabled=false)
	call_deferred("verify")
