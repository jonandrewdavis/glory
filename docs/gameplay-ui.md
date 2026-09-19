# Gameplay UI scenes

Reusable `scenes/gameplay/ui/radial_progress.tscn` uses a TextureProgressBar with
a radial GradientTexture2D whose alpha forms a ring. Each instance owns its gradient;
the stroke width stays constant in local pixels as the Control resizes.
Readiness uses a 180-degree fill, an owner-only display_state snapshot (never replicated),
a dim track and a Label for the selected level. Ram radius and active
spawn flags use the same ring resource at full progress.

`indicator_bar.tscn` supplies shared ProgressBar styling for gate, creep, ram and
local-player health. World indicators preserve their original positions and
visibility rules. HUD gate health and local-player health respond to health
signals; local health rebinds when the player incarnation changes. Route and charge
progress continue updating from their existing gameplay state.

The siege readout uses Containers, Labels and Controls for its gate bars, ram
track, fill and marker. The scoreboard and short kill feed occupy the upper right.
HUD scaling remains controlled by the existing settings. Decorative Controls ignore
mouse input; the roster can scroll when the mouse is released in the pause menu.

The respawn HUD root, spawn-band world flags and round-score Label are intentionally hidden. Respawn
gameplay and ownership replication remain active. Winner announcements retain their
existing behavior. Trajectory dots and editor-only spawn bounds retain procedural
drawing; third-party UI add-ons are unchanged.

Run `tools/check_kda.tscn` for attribution/feed/hidden-state checks. Add
`-- --preview` in a graphical run to write `/tmp/glory-ui-preview.png`, or
`-- --preview --large-ui` for the maximum UI scale preview.
