extends Node3D
## Plays the refined hunter clips on this body. The owning player calls play_clip
## for the current action. Remote peers play the same clip from the replicated id.

const LOOPING: PackedStringArray = [
	"Idle",
	"ADS",
	"Sprint",
	"Crouch_Walk",
	"Walk_Forward",
	"Walk_Back",
	"Walk_Left",
	"Walk_Right",
	"Walk_ForwardLeft",
	"Walk_ForwardRight",
	"Walk_BackLeft",
	"Walk_BackRight",
]

var _player: CharacterBody3D
var _animation: AnimationPlayer
var _seen_clip := -1
var _seen_token := -1


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_animation = _find_animation_player(self)
	if _animation == null:
		push_error("Hunter body is missing an AnimationPlayer.")
		return
	_apply_loop_modes()
	if _player and _player.is_multiplayer_authority():
		_assign_layer(self, 2)
	play_clip("Idle", true)


## Play a refined clip now. Loops keep running; restart snaps a one-shot back to its first frame.
func play_clip(clip_name: String, restart: bool) -> void:
	if _animation == null:
		return
	if not _animation.has_animation(clip_name):
		clip_name = "Idle"
	if not _animation.has_animation(clip_name):
		return
	if not restart and str(_animation.current_animation) == clip_name:
		return
	_animation.play(clip_name, 0.08)
	if restart:
		_animation.seek(0.0, true)


func _process(_delta: float) -> void:
	if _player == null or _animation == null:
		return
	if not _player.has_method("clip_from_id"):
		return
	if _player.body_clip == _seen_clip and _player.body_token == _seen_token:
		return
	var restart: bool = _player.body_token != _seen_token
	_seen_clip = _player.body_clip
	_seen_token = _player.body_token
	play_clip(_player.clip_from_id(_seen_clip), restart)


func _apply_loop_modes() -> void:
	for lib_name in _animation.get_animation_library_list():
		var library := _animation.get_animation_library(lib_name)
		var names := library.get_animation_list()
		for anim_name in names:
			var source := library.get_animation(anim_name)
			if source == null:
				continue
			var copy := source.duplicate()
			copy.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(anim_name) else Animation.LOOP_NONE
			library.remove_animation(anim_name)
			library.add_animation(anim_name, copy)


func _assign_layer(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		node.layers = layers
	for child in node.get_children():
		_assign_layer(child, layers)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
