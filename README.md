# oathbound-game
Development repository for Oathbound - multiplayer ritual-combat game built with Godot.

## Where things belong

- `scenes/` — Oathbound game scenes; `main.tscn` is the arena.
  - `weapons/revolver.gd` — revolver firing, recoil/idle/movement animations, muzzle flash, audio, and crosshair setup. Attached to a separate `RevolverController` child so the existing gun script stays intact.
  - `player/` — the actual player controller, player scene, and developer overlay.
  - `tests/` — the playable movement practice course.
- `assets/` — game art and sound.
  - `audio/` — sound files.
  - `weapon_models/` — weapon models.
  - `prototype_textures/` — temporary crosshairs, muzzle flash, and terrain textures.
- `terrain_data/` — saved terrain regions used by the game; keep these files together.
- `terrain3d_examples/` — Terrain3D sample project, separate from Oathbound gameplay.
  - `scripts/` — example scripts, including the example player (not our controller).
  - `scenes/` — reusable example scenes.
  - `terrain_data/` — example terrain and navigation resources.
  - `assets/` — example models, materials, and textures.
- `tests/` — automated checks, including `movement_test.gd`.
- `docs/` — movement notes and developer overlay instructions.
- `addons/` — installed plugins; preserve their folder names for updates.
- `.godot/` — generated Godot cache; do not use this for source assets.

`project.godot` contains project settings. `new_terrain_3d_assets.tres` defines the game's terrain assets.

Use lowercase names with underscores for new folders. Move assets through Godot's FileSystem dock so their references update together. When updating Terrain3D, avoid importing another copy of its optional demo into the project root.

The player forwards valid shooting input to `active_weapon.try_fire()`. Its `active_weapon_path` selects the initial weapon component. Future inventory code can switch `active_weapon`; each weapon can implement its own `try_fire()` without adding weapon effects to the movement controller. This is a separation point, not a complete inventory system.

Multiplayer is room-code only, in the style of a lobby code. Host creates a 6-character code and it stays on screen. Join types that code. Nobody types an IP address and nobody opens a router page.

Connections go out to a relay, so the host does not need an open UDP port for the old direct join. `res://multiplayer/relay.cfg` chooses the relay (override it with `user://relay.cfg`). The default starts the relay inside the host's game. Same-network friends are found from the code. For friends on other networks, the host's game opens its own router port automatically through `multiplayer/port_forwarder.gd`: UPnP is tried first and NAT-PMP second. The lease is renewed while the room is open and released when the game exits, so the port stays open for the whole session. If the router answers to neither, or the network sits behind a second router (double NAT), same-network play still works and the menu message says why. For play that does not depend on any router, run `multiplayer/run_relay.gd` on a public machine and point both games at `ws://that-machine:9050`.

Connection failures return to the menu with a message. `tests/room_code_test.gd` covers the relay, codes, and gameplay packets. `tests/port_forwarder_test.gd` drives a fake router over loopback to check opening, renewal, refusal, and release. `tests/network_diagnosis.gd` still runs as two Godot processes (`host` and `client`) and now joins room `TESTAB` on port 19999.

