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

Multiplayer uses Epic Online Services lobbies: Host publishes a 6-character join code, Join searches that code, then Start opens an EOS P2P session. Connection failures return to the menu with a message. Local ENet integration coverage is still in tests/network_diagnosis.gd (two Godot processes with user arguments host and client; test port 19999).

