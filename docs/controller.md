# Character and camera feel

Normal framing follows the local archer's aim: approximately 65% of the view
ahead and 35% behind, including while retreating. Near vertical aim, facing
retains its previous side until the horizontal aim component exceeds 0.15.
Projectile and shield angles always use the exact aim vector.

Camera direction has a separate, wider grace area. To reverse its forward
bias, aim at least 0.83867 horizontally into the opposite side (within
33 degrees of directly left/right) continuously for 0.50 seconds. Returning
to the neutral region or original side resets that timer. Brief glances never
accumulate. Pause, death, and mouse release cancel pending turns. Once committed,
the existing damping pans smoothly to the new side. Sprite facing and shot aim
remain responsive; moving backward does not reverse the camera. Tune
`reversal_threshold` and `reversal_hold_time` on CameraRig independently of
the positional deadzones below. Respawn seeds camera facing without waiting.

CameraRig's `forward_view_fraction` controls the horizontal offset (0.15).
PlayerPCam uses Framed Follow with a 6% horizontal and 28% vertical deadzone,
and damping of (0.20, 0.15). Vertical aim does not pan the camera. The player
camera's own zoom determines the offset, independent of Shift arrow-follow.
World limits take precedence over the preferred composition. Spawn and
respawn reset camera history and watched arrows.

Movement Feel properties on ArrowPlayer expose acceleration (1700), braking
(2200), reversal acceleration (2400), coyote time (0.10 seconds), jump buffering
(0.12 seconds), and jump cut factor (0.5). Maximum speed and full jump impulse
remain 100 and -290. Releasing jump cuts remaining upward speed once. Jump
cancels arrow preparation and can take off on the same press; the canceled
fire-button release is consumed. Death, relocation, pause, and input loss
clear buffered jumps.

Pressing down while standing on a one-way platform (any TileMapLayer in the
`fortress_one_way_platforms` group) drops the archer through it. The platform
stays passable for 0.25 seconds via a physics collision exception; solid
ground ignores the press. Tune `drop_through_time` on ArrowPlayer. Death,
relocation, and pause clear any active drop.

Run `Godot --headless --path . tools/check_controller.tscn` and the existing
`check_charge_arc.tscn` and `check_trajectory.tscn` checks. For visual tuning,
check Fortress1 and Fortress2: reverse aim while standing and retreating,
jitter near vertical aim, jump between platforms, fall down a shaft, hold and
release Shift, respawn, and resize between 16:9, 16:10, and ultrawide. Check
30/60/144 FPS rendering for jitter and two clients for independent framing.
