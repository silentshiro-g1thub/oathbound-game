extends SceneTree


func _initialize() -> void:
	var code: String = Online.make_join_code()
	assert(code.length() == 6)
	for i in code.length():
		assert(Online.CODE_CHARS.contains(code[i]))
	print("PASS: join codes are 6 characters from the lobby alphabet")
	quit()
