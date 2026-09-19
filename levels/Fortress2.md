# Fortress2 compact blockout

`Fortress2.tscn` is a 2,560-pixel-wide close-quarters alternative to Fortress1.
It uses the original three-tier footprint: center y=96, middle terraces y=-32,
and outer keep bases y=-160. Blue occupies negative x and orange positive x.

The compact map retains:

- Oak terrain, smooth world-layer ramps, and blue/orange edge tinting.
- A tall, narrow keep tower on each end, set back from the hill crest, with a
  small gate solid to both teams' players and 32-pixel one-way climbing steps.
- A smaller forward outpost per team with a firing shelf and parapet cover.
- One shared server-driven battering ram using the same `fortress_rams` group.
- A neutral central bridge and tower, shallow dips, broken bridge platforms, and offset perches.
- Four safe spawn markers per team: two inside the keep and two at the outpost.

The map is deliberately less dense than Fortress1. It keeps the recognizable
siege and vertical-combat elements while reducing travel time and visual noise.
Each keep is art-only stone spanning absolute x=1088–1272 from the y=-160
plateau up to y=-480, leaving 80 pixels of flat ground between the crest
(x=1008) and the tower, whose front lines up with the front of the gate. Nothing in it is solid and nothing stops arrows: there
are no merlons, lips, lintels or walls, so defense comes from height alone.
Eight `Climb` steps alternate between the front (x=1088–1200) and rear
(x=1176–1272) every 32 pixels: `Climb1` starts on the gate side and `Climb4`
ends against the map edge, then `Climb5`, `6` and `8` are rear and `Climb7` front; a long `Balcony` at y=-352 spans x=984–1272,
and the `Deck` crowns the tower at y=-480 (x=1064–1272).

Each keep carries a `FortressGate` objective (`{Blue,Orange}/Keep/FortressGate`,
5000 health, physics layer 7 `gates` with no mask) inside the tower front:
a 24-by-64 timber rect at x=1088–1112, y=-224 to -160, root at (1086, -192).
The gate has no visual yet. With `blocks_players` on, the gate itself adds the
layer 6 (mask 0) barrier that blocks players from both directions until the
level resets, without changing arrow damage, creep movement, or ram behavior;
there are no separate gate wall, barrier or door nodes. The ram route and
enemy creeps end at the gate root; each team's own creep markers sit at the back
of its keep (x=1192, 1224, 1256), clear of the fighting at the gate. See `docs/rounds.md`.

Defenders climb the interior steps and leave by walking off the balcony, which
projects 104 pixels past the tower front, just beyond the hill crest, and
lands them on the top of the ramp outside the gate. There
is no exterior staircase for attackers, the 64-pixel timber is taller than a
jump, and it cannot be dropped through.

All keep and outpost climbing steps, roof decks, balconies, and firing shelves
use arrow-transparent one-way stone platforms (oak tile alternative 2).
Players jump through from below and stand on top; arrows pass in every direction.
These platforms use physics layer 6 (`arrow_transparent_platforms`, bit 32) and
the `fortress_arrow_transparent_platforms` group. The archer mask is 33; the arrow
mask is 91 (27 plus gates) and the creep mask remains 17. Field bridges and
perches also use alternative 2. Both outpost merlons (`Merlon-64`, `Merlon64`) are ordinary
one-way arrow-transparent steps: they block nothing, but players can still
stand on them. Ground and hills
remain solid and stop arrows.

The absolute ceiling is y=-16384; side and bottom boundaries are unchanged.

To re-apply the platform and outpost-cover conversion to an existing scene
while preserving its custom visual nodes, run the builder with
`-- --upgrade-defenses`. The same bake-time helper is applied by a full rebuild.
A full rebuild discards hand-made visuals (sky shader and so on), so prefer
editing the scene directly.

A neutral bridge (`Center`, group `fortress_center_towers`, meta `team = "neutral"`)
spans the trench at y=-24 from x=-176 to 176 with a climbable tower in the middle.
Each side reaches the deck by three 32-pixel hops: the y=72 shelf, `Step1` at
y=40, `Step2` at y=8, then the deck. Inside the tower two staggered `Climb`
steps at y=-56 and y=-88 lead onto the `Roof` at y=-120. Every platform on the
bridge, roof included, is an arrow-transparent one-way platform and the tower
posts are art only, so the whole structure offers no cover from arrows. The ram
and creeps pass beneath it untouched.

Each fortress also spawns three melee creeps every 30 seconds, starting immediately.
The `CreepBlue1..3` and `CreepOrange1..3` markers under `SpawnPoints` are kept by the
builder. Creeps march to the enemy gate, strike it while holding there, and contribute to
the ram's team count; see `docs/creeps.md` for details.

Rebuild and verify with:

```sh
Godot --headless --path . --script tools/build_fortress2.gd
Godot --headless --path . --script tools/check_fortress2.gd
Godot --path . --script tools/check_fortress2.gd -- --preview
```
