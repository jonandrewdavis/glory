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
- Central shelters, shallow dips, broken bridge platforms, and offset perches.
- Four safe spawn markers per team: two near the keep and two at the outpost.

The map is deliberately less dense than Fortress1. It keeps the recognizable
siege and vertical-combat elements while reducing travel time and visual noise.
Gate damage and breach effects remain deferred; both ground entrances are open.

All keep and outpost climbing steps, roof decks, balconies, and firing shelves
use arrow-transparent one-way stone platforms (oak tile alternative 2).
Players jump through from below and stand on top; arrows pass in every direction.
These platforms use physics layer 6 (`arrow_transparent_platforms`, bit 32) and
the `fortress_arrow_transparent_platforms` group. The archer mask is 33; arrow
and creep masks remain 27 and 17. Walls, merlons, cover lips, bridges, and field
perches retain their existing collision and appearance.

Each fortress also spawns three melee creeps every 30 seconds, starting immediately.
The `CreepBlue1..3` and `CreepOrange1..3` markers under `SpawnPoints` are kept by the
builder. Creeps march to the enemy gate and contribute to the ram's team count;
see `docs/creeps.md` for details.

Rebuild and verify with:

```sh
Godot --headless --path . --script tools/build_fortress2.gd
Godot --headless --path . --script tools/check_fortress2.gd
Godot --path . --script tools/check_fortress2.gd -- --preview
```
