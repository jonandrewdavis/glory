# Respawns and territory

`World/RespawnManager` owns player death deadlines, band ownership and spawn
selection on the server. `HealthComponent` still owns health, but player
auto-respawn is disabled. The manager replaces a dead player when its wait ends;
scoreboard kills/deaths/assists persist; each new life starts with empty damage history. Each incarnation has a unique node path so
late movement packets cannot move its replacement.
Remote owners acknowledge stopping their old movement synchronizer before
replacement. This adds one network round trip after the countdown, without
changing the population-based delay or allowing the client to respawn early.

## Timing

Edit `scenes/gameplay/respawn_settings.tres` in the Inspector:

`delay = 2 + 0.25 * max(connected_teammates - 2, 0)` seconds.

Count living and dead connected players, excluding creeps. There is no cap:
1–2 players wait 2 seconds, 15 wait 5.25, 30 wait 9, and 100 wait 26.5.
The population is sampled at death, so later roster changes do not alter an
existing wait. Spawns are individual, not waves. Joining and new rounds spawn
immediately. Dead players cannot change teams to skip their wait.

## Fortress2 layout and capture

Open `levels/fortress2_spawn_bands.tscn` to edit the six native `SpawnBand`
nodes instanced under `Fortress2/SpawnBands`. The map builder uses this same
scene, so rebuilding terrain preserves the band definitions.

Left to right: Blue fortress, Blue outpost (active), left neutral center,
right neutral center, Orange outpost (active), Orange fortress. Horizontal
boundaries are -1280, -800, -400, 0, 400, 800, 1280. The central bands share
the existing tower and bridge; terrain is unchanged.

| Band | Blue holds while the ram is at or past | Orange holds while the ram is at or past |
| --- | --- | --- |
| 1 Blue fortress | Permanent Blue | Never |
| 2 Blue outpost | x=-608 | Blue gate endpoint |
| 3 Left center | x=608 | x=-800 |
| 4 Right center | x=800 | x=-608 |
| 5 Orange outpost | Orange gate endpoint | x=608 |
| 6 Orange fortress | Never | Permanent Orange |

Ownership is a pure function of the ram's route distance, recomputed by the
server whenever the ram moves during play (`RespawnManager.owners_at`). A band
is claimed the moment the ram reaches its milestone and released the moment the
ram is pushed back over it, returning to neutral; pushing direction does not
matter. With the ram between x=-608 and x=608 the map is in its starting state.
Past x=-608 Blue's outpost is neutral and Blue respawns in its fortress.

Blue always holds a contiguous run of bands from its fortress and Orange a
contiguous run from its own; they can never interleave. Ordered milestones
produce this naturally, and the manager also neutralizes any band cut off from
its fortress, so a misauthored map cannot break it. The most forward owned
band is active: highest order for Blue, lowest for Orange.
Fortresses cannot be captured. Living players stay where they are when a band
changes hands. The destination is selected at respawn, not at death.

For example, Orange must pass **Blue's** outer tower center (x=-608), not its
own tower, to claim band 4. Its next respawn then uses the central-right band.
Node-based world flags track ownership but remain hidden by the existing
SpawnBand root visibility setting. The HUD band strip and respawn
countdown have been converted to Controls but intentionally remain hidden under
`scenes/gameplay/ui/respawn_hud.tscn` (root `visible = false`). Child updates do
not reveal that root; enable it in the scene only when the feature should be shown.

## Map authoring

Duplicate or add a Node2D with `scenes/gameplay/spawn_band.gd`. Set a unique
`band_id` and `order`, initial owner (-1 neutral / 0 Blue / 1 Orange), editable
local `bounds`, and `flag_position`. Keep a permanent fortress at each end.
There is no fixed band count in the manager or HUD.

Under `Points`, add Marker2D children at safe ground or lower-platform spawn
positions. They must be inside the bounds with clearance for a scaled archer.
Band bounds are visible in the editor, not painted across live gameplay.

Non-permanent bands need `BlueCapture` and `OrangeCapture` Marker2D children
placed on the ram's route. Their positions project onto route distance; use
`blue_capture_at_end` or `orange_capture_at_start` for gate endpoints. Order
milestones monotonically in each team's attack direction, and keep each
band's Orange milestone before its Blue milestone along the route. Initial
owners should match what the ram's starting position implies. The editor reports
missing points, missing thresholds and duplicate IDs/orders; runtime validation
also reports unordered milestones, absent fortresses and off-route markers.

The server rejects terrain-obstructed points and prefers the point furthest
from living enemy players, rotating among ties. Players can share a marker
because their bodies do not collide, so large populations do not queue for
spawn slots. If an owned band has no usable points, selection falls back
toward its fortress with a diagnostic. Legacy maps without bands use their
original team markers, with the new timing.

## Lifecycle

Fresh spawns have no damage protection. Creeps retain their existing influence
and spawn behavior.

Round end cancels pending respawns and freezes capture. Level reload resets
ownership before placing players at the initial active bands. Map changes,
disconnects and session exits cancel old waits. Ownership/countdowns synchronize
to level-ready peers, including late joiners. Revision checks and incarnation
IDs reject stale state.

## Checks

```sh
Godot --headless --path . tools/check_respawns.tscn
Godot --headless --path . tools/check_rounds.tscn
Godot --headless --path . --script tools/check_fortress2.gd
```

Run these in separate processes for the multiplayer check:

```sh
Godot --headless --path . tools/check_respawns_network.tscn -- --server
Godot --headless --path . tools/check_respawns_network.tscn -- --client
```

Repeat with `--listen-host` added to the server command. Checks cover late joins
after a capture, countdown replication, capture while dead, authoritative
respawn positions, persistent scores, a reload while dead, live
team switching and a round restart with living players.
For visual QA, run `tools/check_respawns.tscn -- --preview` with a renderer;
it writes initial/captured overview images into `/tmp`.
