extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 var main: Node = load("res://scenes/main.tscn").instantiate()
 root.add_child(main)
 main.address_entry.text = "127.0.0.1:19998"
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
