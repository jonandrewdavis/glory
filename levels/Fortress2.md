# Fortress2 compact blockout

`Fortress2.tscn` is a 2,560-pixel-wide close-quarters alternative to Fortress1.
It uses the original three-tier footprint: center y=96, middle terraces y=-32,
and outer keep bases y=-160. Blue occupies negative x and orange positive x.

The compact map retains:

- Oak terrain, smooth world-layer ramps, and blue/orange edge tinting.
- A short keep on each end with an open, noncolliding wooden gate facade,
  two balconies, battlements, and 32-pixel one-way climbing steps.
- A smaller forward outpost per team with a firing shelf and parapet cover.
- One shared server-driven battering ram using the same `fortress_rams` group.
- A neutral central bridge and tower, shallow dips, broken bridge platforms, and offset perches.
- Four safe spawn markers per team: two near the keep and two at the outpost.

The map is deliberately less dense than Fortress1. It keeps the recognizable
siege and vertical-combat elements while reducing travel time and visual noise.
Each keep carries a `FortressGate` objective (`{Blue,Orange}/Keep/FortressGate`,
5000 health, physics layer 7 `gates` with no mask) behind its facade; both
ground entrances stay open. See `docs/rounds.md`.

All keep and outpost climbing steps, roof decks, balconies, and firing shelves
use arrow-transparent one-way stone platforms (oak tile alternative 2).
Players jump through from below and stand on top; arrows pass in every direction.
These platforms use physics layer 6 (`arrow_transparent_platforms`, bit 32) and
the `fortress_arrow_transparent_platforms` group. The archer mask is 33; the arrow
mask is 91 (27 plus gates) and the creep mask remains 17. Field bridges and
perches also use alternative 2. Outpost merlons and barricades use a level-local
tileset on layer 6: solid for players, transparent to arrows. Ground and hills
remain solid and stop arrows.

Both lower keep balconies project over the gate approach at y=-288, spanning
absolute x=920–1176. An open grating supports players while passing arrows in
both directions. The front wall has a doorway from y=-320 to -256; a solid
16-by-32 outer parapet provides cover while defenders fire through the floor.
Upper keep cover and gate objectives retain their arrow collisions.
The absolute ceiling is y=-16384; side and bottom boundaries are unchanged.

To apply these defenses to an existing scene while preserving its custom visual
nodes, run the builder with `-- --upgrade-defenses`. The same bake-time helper
is applied by a full rebuild.

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
