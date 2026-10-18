# Developer movement checks

Run the game with F5, or the practice scene with F6, then click the game to give it keyboard focus.

- **F3:** show/hide the panel in the top-right corner.
- **F4:** print one full snapshot to Godot's **Output** panel (or the terminal when launched from a console).
- **Shift+F3:** toggle compact live console logging, once per second. This works independently of panel visibility; hiding the panel does not stop an enabled console log. Press Shift+F3 again to stop it.

The panel is available in the editor and debug exports. Release exports do not create it. It starts hidden, with logging off, and remains usable while the mouse is released. It does not pause the game or change player velocity. Respawning/reloading creates a fresh panel with logging off.

It displays horizontal speed, vertical speed, velocity XYZ, real velocity, world position, movement state, crouch state, FPS, physics tick rate, floor/wall/ceiling contact, slope angle, collision count, wall contact normal, extra jump charge, jump cut, coyote/jump buffer, slide/dash duration, dash cooldown, wall budget/re-entry delay, wall-jump steering lock, controls, mouse capture, and held movement inputs.

`Velocity XYZ` is the controller's velocity after the most recent move. `Real velocity` comes from actual movement, which is useful when checking slopes or platform movement. Speed is horizontal magnitude, not the total 3D magnitude. Floor angle and wall contact normal show zero without current contact. Inactive slide/dash duration shows zero; a ready dash cooldown does not override other restrictions such as crouching. Held inputs are raw input states; `Controls` shows whether gameplay currently accepts them.

The readout refreshes ten times per second and scales to fit smaller windows. F4 captures fresh values immediately and includes the physics-frame number. Fast transitions shorter than a refresh interval may not be visible; this is a live diagnostic display rather than a recorded history. Console logging is intentionally limited to avoid flooding Output. Neither display nor logging runs each frame when both are disabled.

Implementation: `scenes/player/developer_overlay.gd` is a separate read-only CanvasLayer created by the existing player controller. It follows the player in the main arena and standalone practice scene. Its UI ignores mouse input so it cannot block aiming, firing, or recapture. Function keys are handled separately from movement input and key-repeat events are ignored.

Validation: headless checks exercised the function keys through Godot input dispatch, snapshot values, repeat-key rejection, independent logging/visibility, idle processing, operation with released controls, unchanged player velocity, and fitting into 400×300 and 640×360 viewports. The main scene also loaded without new script errors. Actual windowed appearance and keyboard focus still need a visual check.

Total speed includes vertical movement, making upward dashes visible even when horizontal speed is low. Air dash shows the charge independently from cooldown.
