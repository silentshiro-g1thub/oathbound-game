extends Node
## Revolver controller. Owns revolver animations, recoil check, gunshot audio,
## muzzle flash, and viewmodel visibility.

@export_node_path("CharacterBody3D") var player_path: NodePath

@onready var player: CharacterBody3D = get_node(player_path)
@onready var model_root: Node3D = get_parent() as Node3D
@onready var animation_play: AnimationPlayer = get_node_or_null("../AnimationPlayer")
@onready var muzzle_flash: Node3D = get_node_or_null("../Node3D")
@onready var revolver_sfx: AudioStreamPlayer3D = get_node_or_null("../GunshotAudio")
@onready var aim_ray: RayCast3D = player.get_node_or_null("Head/Camera3D/RayCast3D")
@onready var crosshair: Control = player.get_node_or_null("../Node2D/TextureRect")
@onready var crosshair_hit: Control = player.get_node_or_null("../Node2D/TextureRect2")


## Prepare weapon visuals and keep the crosshairs centered as the window changes.
func _ready() -> void:
	if muzzle_flash:
		muzzle_flash.visible = false

	_center_crosshairs()
	get_viewport().size_changed.connect(_center_crosshairs)


## Show or hide the revolver model when equipped or holstered.
func set_equipped(equipped: bool) -> void:
	if model_root:
		model_root.visible = equipped
	if not equipped and muzzle_flash:
		muzzle_flash.visible = false
	if equipped and player:
		player.viewmodel_follow = 1.0


## True while the non-looping Shot animation is actively playing.
func is_recoiling() -> bool:
	return animation_play != null and animation_play.is_playing() and animation_play.current_animation == "Shot"


## Animate the held revolver from player movement without interrupting recoil.
func _process(_delta: float) -> void:
	if not player or not player.multiplayer.has_multiplayer_peer():
		return
	if player.active_weapon != self or not animation_play or is_recoiling():
		return

	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var animation := "move" if player.is_on_floor() and horizontal_speed > 0.1 else "Idle"

	if animation_play.current_animation != animation:
		animation_play.play(animation)


## Keep the weapon crosshairs centered when the viewport changes size.
func _center_crosshairs() -> void:
	for marker in [crosshair, crosshair_hit]:
		if marker and player.is_multiplayer_authority():
			marker.position = (get_viewport().get_visible_rect().size - marker.size * marker.scale) * 0.5


## Play animation, flash, and audio together for an accepted shot; ignore repeat requests during recoil.
func try_fire() -> bool:
	if not player or player.active_weapon != self or not animation_play or is_recoiling():
		return false
	animation_play.stop()
	animation_play.play("Shot")
	if revolver_sfx and revolver_sfx.stream:
		revolver_sfx.play()
	show_muzzle_flash()
	return true


## Alias used by player RPCs so every weapon shares the same fire entry point.
func play_fire_effects() -> bool:
	return try_fire()


## Show a briefly rotated muzzle flash, then hide it after the effect duration.
func show_muzzle_flash() -> void:
	if not muzzle_flash:
		return
	muzzle_flash.visible = true
	muzzle_flash.rotation.z = randf_range(0.0, TAU)
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(muzzle_flash):
		muzzle_flash.visible = false
