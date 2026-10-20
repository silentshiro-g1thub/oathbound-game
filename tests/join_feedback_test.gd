extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.code_entry.text = "ZZZZZZ"
	main._on_button_2_pressed()
	assert(main.joining and main.main_menu.visible)
	assert(main.connection_status.text.begins_with("Connecting"))
	main.join_elapsed = main.JOIN_TIMEOUT
	main._process(0)
	assert(not main.joining and main.main_menu.visible)
	assert(main.connection_status.text.contains("timed out"))
	assert(not main.get_node("CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/Button2").disabled)
	print("PASS: pending join remains visible; timeout returns to retryable menu")
	quit()
