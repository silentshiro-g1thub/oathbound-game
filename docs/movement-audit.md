# OATHBOUND movement audit and development report

Date: 18 October 2026. Tested with the installed Godot 4.7.2 build, using Jolt.

## Initial audit

The starting Git working tree was clean. The active player is a CharacterBody3D embedded in `scenes/main.tscn`, using `scenes/player/player.gd`. Its capsule is 1.8 m tall, radius 0.35 m, with its bottom at the player origin. Head height is 1.6 m. The separate `scenes/player/player.tscn` originally had no script, capsule resource, or head height and was not used by the main scene.

The controller already supported yaw/pitch mouse look, normalized keyboard direction, held sprint, acceleration/deceleration, different rising/falling gravity, variable-height jumps, weapon animation, and a short muzzle flash. Input was read during physics processing, velocity was changed directly, and `move_and_slide()` resolved collisions once per tick. Weapon animation selection and continuous sprint debug printing also ran there. There was no explicit movement state system.

Sprint was already correct in two important respects: it used `is_action_pressed()` and its speed affected horizontal velocity. The previous one-frame sprint report did not reproduce in this source. These behaviors were preserved.

Confirmed issues, in priority order:

1. Input reliability: mouse motion rotated the camera even with the cursor released. Shooting was handled before recapture, allowing the recapture click to fire. Focus loss had no explicit handling. Crosshair controls also used their default mouse filtering, allowing UI to intercept clicks before `_unhandled_input`.
2. Movement consistency: independent X/Z acceleration gave diagonal acceleration a larger magnitude. Ground acceleration and braking were applied in the air, rapidly erasing airborne momentum when input was released. The main camera had an additional off-axis rotation, so its view did not exactly follow the movement basis.
3. Jump forgiveness: coyote time and buffered jumping were absent. Existing variable jump height worked and was retained.
4. Scene coupling: hard-required weapon and sibling HUD paths prevented the controller from working in a simple player-only test scene. The standalone player scene was incomplete.
5. Maintenance: continuous per-tick debug output, hardcoded shared ground/air behavior, and mixed physics/presentation responsibilities made extension harder.

Slide, dash, wall-run, wall-jump, double-jump, ability cooldowns, and safe crouch clearance were entirely absent. There was no competing active movement controller. `demo/src/Player.gd` belongs to the bundled Terrain3D demonstration and is not attached to the main player.

Inspected: both player files; the full active controller and main scene; `project.godot`; README and ignore settings; Terrain3D extension/plugin declarations and terrain assets; a sample of the separate demo controller; local editor metadata to locate Godot. Terrain3D is bundled at version 1.0.2. The project uses Jolt and the compatibility renderer, although its feature metadata also names Forward Plus. Renderer metadata and third-party code were left alone.

## Files changed

- `scenes/player/player.gd`: incremental foundation fixes and ability functions; explicit state, timers, and separate presentation updates.
- `scenes/player/player.tscn`: completed reusable player with the existing controller, correct capsule, head height, and active camera.
- `scenes/main.tscn`: aligned the camera mount and made both crosshair controls ignore mouse events. Existing weapon assets, animation tracks, terrain, and player hierarchy remain in place.
- `project.godot`: added Ctrl for `slide` and Q for `dash`; existing mappings and main scene retained.
- `tests/movement_test.gd`: real Godot collision and movement regression suite.
- `scenes/tests/movement_playground.gd` and `.tscn`: a separate practice course with a status overlay and reset control.
- `docs/movement-audit.md`: this report, rules, tuning reference, and manual checklist.

No dependencies, networking, commits, or pushes were added. The active controller was extended in stages, rather than replaced by an unrelated movement framework. Its existing variable-jump calculations and weapon effects remain recognizable.

## Architecture and movement rules

One enum represents Grounded, Sprinting, Airborne, Sliding, Dashing, or Wall-running. Cooldowns, the extra-jump charge, wall airtime budget, and crouched posture are separate data. Crouched posture persists while Ctrl is held or a ceiling prevents standing.

Each physics tick reads input, advances timers, resolves activation priority, and selects one horizontal movement owner. Dash has an early-return branch; all other modes share the final `move_and_slide()`. Collision results determine the next state. `_process()` updates camera height and weapon presentation without changing velocity. Mouse input changes body yaw and head pitch only while captured and enabled.

- **Walk/sprint:** hold Shift with directional input for sprint target speed. Vector acceleration treats all directions equally. Releasing sprint decelerates gradually on the ground. Air steering is weaker; releasing directional input does not brake horizontal velocity. Holding sprint in the air can accelerate toward sprint speed. Existing faster takeoff momentum is retained while steering; it is not continually multiplied.
- **Jump:** Space uses a floor/coyote jump first. An eligible wall-run jump has priority over the extra jump. An airborne press otherwise spends the extra jump. With no eligible jump, input remains buffered briefly for landing. Holding Space never repeats jumps. Releasing it still cuts jump height, including a buffered press released before takeoff.
- **Slide:** press and hold Ctrl while grounded with at least 8 m/s horizontal speed. Sprint is one way to reach that speed; holding Shift itself is not required. Entry adds up to 3 m/s, with a bonus ceiling of sprint speed + 3; faster incoming speed is preserved. Friction removes speed and limited steering changes direction. Release, timeout, low speed, leaving the floor, or jumping ends the slide. Jump preserves horizontal momentum. The capsule shrinks around its original foot position. A full standing-capsule query must clear before expansion; if blocked, movement remains crouched at a reduced target speed. The entry bonus has a 1-second cooldown; sliding itself still requires a fresh press.
- **Dash:** WASD chooses dash direction: A/D strafe horizontally, S retreats horizontally, and W follows camera aim including pitch. Diagonals combine these directions and are normalized. Q with no direction follows aim. The burst locks direction and suspends gravity for 0.08 seconds forward/backward or 0.12 seconds sideways, with diagonals blended between them, then resumes gravity. Dash exit preserves collision-resolved horizontal and vertical velocity. Gravity and ordinary movement resume without dash-specific damping. Launch speed is at least 23 m/s and preserves faster incoming speed. Walls, ceilings, and downward floor impacts stop the burst. One airborne dash is available until landing; cooldown and jump charges remain separate. Crouching blocks activation. Set `dash_follows_aim=false` for the legacy horizontal WASD dash with gravity.
- **Wall-run:** automatic while airborne, standing, moving fast enough, and steering alongside a suitable side wall. Only StaticBody3D colliders in the `wall_runnable` group qualify. Floors, ceilings, strongly slanted walls, unmarked props, head-on approaches, and steering away are rejected. Short side rays check current contact every tick. Reduced gravity and capped falling speed apply; tangential speed approaches its target without reducing faster incoming speed. The total run budget resets only on the floor, never on wall switches, gaps, dash, or wall-jump. Gaps beyond probe reach, release of direction, low speed, sharp blocking corners, ceiling/floor contact, or exhausted budget end the run. Small normal changes can be followed; large corner changes detach instead of snapping around them. A brief re-entry delay prevents immediate reacquisition.
- **Wall-jump:** Space during a valid run gives upward and outward velocity while preserving tangential momentum. A brief air-control lock protects the outward push. The same-facing surface cannot be reused after a wall-jump until landing or jumping off a different-facing surface. The wall airtime budget is retained. An available extra jump is preserved; a spent extra jump stays spent.
- **Double-jump:** one extra airborne Space press raises vertical velocity to at least the extra-jump value and retains horizontal momentum. It resets only on actual floor support. Walking off a ledge also leaves one extra jump available.

Simultaneous input: slide wins slide+dash when slide is eligible; jump can immediately exit that slide. Otherwise dash wins dash+jump. Dash activation clears the pending jump buffer so simultaneous dash+jump cannot produce a delayed surprise jump. A fresh jump press during the burst can still execute afterward. Dash-to-wall-run occurs on the next eligible physics tick after dash ends.

Design alternatives deliberately avoided: requiring a separate wall-run button, spending/refilling the extra jump on wall-jump, unlimited reset-on-wall-contact climbing, and automatic corner snapping. The defaults above are provisional tuning decisions, not claims that competitive balance has been playtested.

## Tuning reference

All values live in exported Inspector groups on the player script. Units are meters, seconds, meters/second, or meters/second squared unless noted.

- **Locomotion:** `move_speed=7`, `sprint_speed=11.5`; `ground_acceleration=25`, `ground_deceleration=20`; `ground_momentum_drag=2` decays excess forward speed; `air_acceleration=7`. `jump_velocity=4.5`, `coyote_time=0.10`, `jump_buffer_time=0.12`. `mouse_sensitivity=0.002` radians per mouse-motion unit; pitch remains limited to ±89 degrees.
- **Variable Jump:** `short_hop_velocity=2.5` caps early releases; `early_release_window=0.12`; `jump_gravity=12`, `fall_gravity=18`; `jump_cut_multiplier=0.4` scales upward speed on later release.
- **Slide:** `slide_min_speed=8` activates; `slide_entry_boost=3`, `slide_boost_cooldown=1.0`; `slide_duration=0.85` limits time; `slide_friction=4` removes speed; `slide_stop_speed=3.5` ends slow slides; `slide_steering=2` limits turning. `crouch_height=1.0`, `crouch_speed=3.5`, `camera_height_speed=8`. Height is constrained to the capsule diameter/standing height. Camera lowers immediately for clearance and rises gradually. Standing checks include a conservative 2 cm upward offset.
- **Dash:** `dash_speed=23`, `dash_duration=0.08`, `sideways_dash_duration=0.12`, `dash_cooldown=0.8` measured from activation, `dash_follows_aim=true` selects 3D camera aim; exit velocity is preserved on every axis; no recovery timer or vertical reset remains.
- **Wall Run:** `wall_min_speed=7`, `wall_run_speed=11.5`, `wall_acceleration=12`; `wall_run_duration=1.2` is the total budget per airtime; `wall_gravity=3`, `wall_max_fall_speed=2`; `wall_probe_distance=0.65`, `wall_max_normal_y=0.2`, `wall_reentry_delay=0.2`. Direction thresholds in the contact helper reject head-on/away input and sharp corner changes; these are geometry eligibility checks rather than speed controls.
- **Wall Jump:** `wall_jump_up_speed=5.5`, `wall_jump_push_speed=7`, `wall_jump_control_lock=0.15`.
- **Double Jump:** `double_jump_velocity=4.95` (about 21% more full-height rise than 4.5); one charge by design.

## Validation

Implementation stages were validated before advancing: foundation/sprint 13 passing checks; slide 23; dash 32; wall-run 39; wall-jump 43; double-jump 51. The expanded suite then added simultaneous inputs, ceilings, invalid wall surfaces, corners, slopes, multiple physics rates, and main-scene weapon/HUD checks.

The suite creates real StaticBody3D geometry, loads the actual player scene, injects input actions, and runs movement on physics-frame signals. It checks velocity, position, posture, state, resource accounting, and actual collision outcomes. It does not merely search source strings.

Original restoration result: **73 checks, 0 failures**. See the momentum update below for subsequent validation. The practice scene also launched for 120 headless iterations without script/runtime errors. The headless editor completed its project scan, extension verification, script registration, and scene load without parser errors; its attempt to save global editor settings outside the repository was blocked by workspace permissions. That editor run is therefore a successful load check with a settings-save limitation, not a completely clean exit log. `git diff --check` was also run.

Headless validation cannot capture a mouse on this machine. The suite verifies focus-loss handling and non-firing recapture handling, then invokes the original weapon-effect function directly to check animation and flash. A real captured-mouse click sequence remains a manual check. No visual gameplay or subjective feel validation is claimed.

At 30/60/120 physics ticks per second, walk target speed is identical. The observed one-second travel difference was about 13 cm and jump-peak difference about 5.5 cm. The checks allow less than one 30 Hz movement step of distance and 8 cm of jump-height variation. Discrete integration and collision timing are not perfectly invariant across physics rates; use a fixed physics rate for competition.

The baseline, before changes, already reported `Failed to read the root certificate store` and `instance_reset_physics_interpolation() is deprecated`. They also occur during main-scene validation. They are separate environment/engine/dependency diagnostics, not newly introduced movement-script errors.

The physics API choices follow Godot's [CharacterBody3D documentation](https://docs.godotengine.org/en/latest/classes/class_characterbody3d.html) and [direct space-query documentation](https://docs.godotengine.org/en/4.5/classes/class_physicsdirectspacestate3d.html); the installed engine tests above are the compatibility check for this project.

Run the suite from the repository in PowerShell:

```powershell
& 'H:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'H:\oathbound-game' --script res://tests/movement_test.gd
```

Check both the final `MOVEMENT TESTS` line and errors above it; a process exit status alone is insufficient for Godot parser failures. Local run logs are in `.godot/movement-validation/`, which is ignored by Git.

## Exact manual checks in Godot

Developer diagnostics are now available in both scenes: **F3** cycles basic, advanced, and hidden readouts, **F4** prints a snapshot, and **Shift+F3** toggles a compact console log once per second. See [developer-overlay.md](developer-overlay.md) for field definitions and controls. The read-only overlay lives in `scenes/player/developer_overlay.gd` and is created only in debug builds.

1. Open `scenes/tests/movement_playground.tscn` and press F6. Use R to reset between trials. The overlay shows state, speed, extra-jump charge, dash cooldown, wall time, and crouch status.
2. Hold W: speed approaches 7. Hold Shift: speed approaches 11.5. Release Shift: speed reduces smoothly. Compare W with W+D; diagonal speed must stay capped. Turn the mouse 90 degrees and verify W follows the view. Look almost straight up/down and verify movement stays horizontal.
3. Tap Space and then try holding Space on a separate attempt; the held jump should be higher. Sprint-jump, release W/Shift in the air, and confirm forward momentum remains. Walk off the edge and press Space immediately to exercise coyote time. After spending the extra jump, press Space just before landing to exercise the landing buffer.
4. At the initial spawn, sprint straight toward the amber overhead tunnel. Press and hold Ctrl just before reaching it. Pass under it without standing through the roof. Release Ctrl under the roof; remain crouched until clear. Reset, then sprint-slide and press Space in the open: jump should retain slide speed. Hold Ctrl at a standstill to crouch; move while holding it to crouch-walk. Release to stand when clearance permits.
5. Look up 45 degrees and press Q: launch up and forward. Look almost straight up and repeat after landing. Aim downward while airborne: collide with the floor. Dash into the thin red wall or a ceiling: stop without tunneling. After an upward dash, verify lift continues under gravity without a speed reset; Space still triggers the extra jump. Try another dash after cooldown but before landing: it must be blocked. Set dash_follows_aim=false in the Inspector to test legacy directional movement.
6. Reset. Move right to approximately x=5.3, close to the inner face of the long teal wall. Face along it toward negative Z. Hold W+Shift, then jump. The overlay should show WALL_RUNNING and slower falling. Release W or steer away to detach. Space during the run should push away. Press Space again after releasing it: one extra jump should remain available.
7. Use the left teal wall, whose segments have a gap around z=-3.5. Run along it and cross the gap: detach instead of hanging in space. Hold a run until its budget expires: contact must not reset it. Try reapproaching the same-facing wall after a wall-jump without landing: it must not provide another run/jump. Confirm floor landing restores the wall budget.
8. Ground jump, release Space, press it again: one extra jump. Release and press a third time before landing: no third jump. Repeat with wall-jump before and after spending the extra charge; wall-jump must never refill it.
9. Try slide+Space, slide+Q, and Q+Space together. Confirm the documented priorities, no conflicting states, and no unexpected late jump. Walk over the purple slope and jump into the amber roof from below; verify grounding and head collision.
10. Press Escape, move the mouse, and confirm the view stays still. Click once to recapture. Alt-Tab out/back while moving and confirm no stuck movement or camera spin; click to resume. Repeat in the main scene with F5: recapture must not fire, the next click must play the weapon shot, and the flash must end quickly. Resize the game window and check the crosshair stays centered.

To enable a custom level wall, select its StaticBody3D collider in Godot and add it to the `wall_runnable` group. The current main terrain has no authored wall-run surfaces; use the practice scene or mark suitable level geometry.

## Remaining limitations

- Real mouse capture, focus transitions, visual camera/weapon behavior, and competitive feel need the manual tests above. No GUI playtest was performed.
- Headless collision coverage uses simple shapes and a modest slope. Complex terrain seams, mesh corners, moving platforms, very high speeds, and extreme Inspector values need additional level-specific testing.
- Wall-running supports upright, static, explicitly marked surfaces. Nearby gaps within probe reach can still count as contact. Sharp corner wrapping, moving-wall support, stair-step assistance, and wall camera banking are not implemented.
- The player expects an upright, uniformly scaled CharacterBody3D with the named capsule and Head/Camera3D nodes. Weapon and HUD nodes are optional. Inspector values should stay positive and sensible.
- There is no networking, prediction, reconciliation, or multiplayer input routing. Physics and presentation are separated to make later integration clearer; network compatibility has not been tested.

## Momentum and aimed-dash update

Walk/sprint speeds now limit ordinary acceleration rather than clipping earned speed. Holding forward on the ground sheds excess speed at 2 m/s per second; releasing or reversing input still brakes normally. Crouched clearance movement remains slow. Slide friction and collisions still remove speed, and turning can dissipate momentum. Wall-running and wall-jumping retain faster tangential momentum. Jump lift is a minimum, so a double jump cannot overwrite a faster upward launch, and jump release cannot shorten inherited faster jump lift. Dash-generated lift is preserved on burst exit.

Use F3 to watch horizontal and total speed while sprinting into a slide, jumping out of it, and dashing upward. A slide from sprint should briefly reach about 14.5 m/s before friction. The aimed dash uses normalized camera-relative directional input and keeps its launch direction even if the camera turns during the burst. Gameplay feel still requires windowed testing.
Updated validation: 87 automated checks passed with zero failures, including upward/angled/downward dash, ceiling and floor collisions, momentum carryover, boost re-entry, inherited lift, and airborne charge reset.


## Directional dash and crouch update

A/D + Q strafes horizontally without changing aim; S + Q retreats horizontally. W + Q and Q without directional input use the camera pitch for upward/angled dashes. W+A/D combines pitch and strafe with normalized speed. The existing dash_follows_aim=false option keeps all directions horizontal.

Hold Ctrl at low speed to crouch and crouch-walk at 3.5 m/s. At sufficient speed, a fresh Ctrl press starts a slide. Holding Ctrl after the slide expires keeps the capsule crouched; release stands only with safe clearance. Slide-to-jump still works. The Ctrl and Q mappings now accept any keyboard device.

Directional dash/crouch validation: 100 automated checks passed, zero failures. New coverage includes strafing under pitched aim, unchanged camera orientation, normalized upward diagonals, stationary crouch, crouch speed, ceiling clearance, and held crouch after slide expiry. Windowed feel remains a manual check.

## Shorter dash and exit control

Forward/backward dash duration is 0.08 seconds instead of 0.16. Sideways dashes use 0.12 seconds for a more useful strafe, with diagonal durations blended by sideways input. On exit, horizontal speed is preserved and then blends into walking/sprinting input or rest over 1.0 second, including neutral opposing keys. This applies on the ground and in the air, including collision exits. Pre-dash vertical velocity resumes under gravity without keeping dash-generated lift; slide and ordinary jump momentum remain unchanged. Dash activation consumes any pending jump request to prevent simultaneous dash+jump from triggering a delayed jump after the shorter burst.

Validation: 104 automated checks passed, zero failures, including measured half-distance, no idle ground/air drift, sprint handoff, opposing inputs, and existing movement/collision regressions. Windowed gameplay feel still needs a manual playtest.

Follow-up tuning: sideways bursts now last 0.12 seconds; forward/backward remain 0.08, and diagonals blend the durations. Fixed launch speed prevents incoming speed from stretching the burst. Aim-based dash exits resume pre-dash vertical velocity instead of retaining dash lift, with collision guards. Extra-jump launch speed is now 4.95 m/s, giving about 21% more full-height rise. Validation: 112 automated checks passed, including measured extra-jump height gain within 15–25%, directional durations, no rocket-like upward exit, and collision regressions. The physics-rate jump comparison now waits for grounded contact before jumping at every rate. Gameplay feel remains a manual playtest.


## Longer dash momentum recovery

Dash speed is now 23 m/s, increasing the burst distance by 15% in every direction without changing its durations. Horizontal momentum eases into current movement input or rest over 1.0 second instead of 0.12 seconds. This deliberately increases post-burst travel as well. Slide and wall-run take over momentum without retaining a stale dash recovery timer. Vertical exit behavior and extra-jump height remain unchanged.


## Momentum preservation revision (current)

Removed the forced horizontal recovery and pre-dash vertical velocity reset. Forward, sideways, upward, and angled dash exits retain collision-resolved velocity. Dash activation also preserves incoming speed above 23 m/s. Ordinary ground friction, steering, gravity, and collisions still apply. This supersedes the recovery and fixed-speed tuning described in earlier revision notes; total travel is no longer constrained to the burst distance. Extra-jump tuning is unchanged.
