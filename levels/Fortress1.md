# Fortress blockout

The scene is baked, editable Godot geometry; it has no runtime generator dependency.
Blue owns negative x; orange owns positive x. Bounds are x ±2560, y -800 to 320.
The 5,120-pixel width is double the original blockout. At the current maximum
100 px/s, the full width represents 51.2 seconds of flat running before ramps,
obstacles and combat. The map remains mostly mirrored, with small local variations.

| Area | Floor y | Distance from center |
| --- | --- | --- |
| Center | 96 | 0–544, with low berms at 320–432 |
| Middle terraces | -32 | 832–1552, with a trench at 1008–1216 |
| Outer bases | -160 | 1840–2560, with a dry moat at 1904–2080 |
| Forward outpost roofs | -160 | centered at ±912 |
| Gatehouse roofs | -416 | centered at ±2240 |
| Great keep roofs | -544 | centered at ±2432 |

Two gentle ramps per side connect the three terrain tiers. Ramp bends, broken
bridge stones, and leaning lookout positions vary slightly between sides.
Oak stone platforms, muted team tints, and an edge band identify ownership;
the band fades at x=0. Each side has a low berm shelter, a smaller defended
outpost, a broken bridge over a shallow trench, a crooked lookout perch, and
a dry moat with a refuge shelf. Both sides of each pit can be walked out of.

## Keeps and siege placeholders

Each keep combines a 256-pixel gatehouse, a 384-pixel great tower, and a curtain
wall walk at y=-352. Balconies at y=-288 and -448 provide additional firing
positions. The lower balcony has an opening through the front wall, allowing
defenders to exit above the gate facade. Multiple parapets provide solid cover.

The main gate is a noncolliding 48×96 wooden facade at |x|=2160–2208.
One shared, collision-free battering ram follows an editable terrain route from
the center toward either gate. The server moves it at 24 px/s when one team has
more living players and creeps within 160 px; ties stop it. Both values are Inspector options.
The ground route through the gate is currently open.

Each fortress spawns three melee creeps every 30 seconds, starting immediately.
Dedicated creep markers live under `SpawnPoints`. See `docs/creeps.md` for combat,
networking, Inspector tuning, and checks.

Gate health, breach effects and objective scoring are **deferred**. Named nodes and persistent groups
provide integration points:

- `Blockout/{Blue,Orange}/Keep/MainGate`: group `fortress_gates`, team and
  placeholder metadata and the noncolliding `GateTimber` facade.
- `MainGate/RamImpactPoint`: marker immediately outside the gate.
- `BatteringRam`: group `fortress_rams`; server-replicated route distance.
- Keep and outpost roots use `fortress_keeps` and `fortress_outposts`.

The checker verifies that players can pass through the facade into the keep.

## Traversal and collision

- Tower ledges rise 32 pixels per jump, below the current archer's approximately
  43-pixel uncharged jump height. Four jumps reach each outpost roof, eight reach
  each gatehouse, and twelve reach each great tower roof.
- The tower facades, gate facade and lookout supports are noncolliding backgrounds.
  The front wall is solid, with a 32-pixel doorway onto the lower balcony.
- One-way ledges allow jumping through from below. Descend via their open edges.
  Ladders and a down-to-drop input are deferred; no player controller edits are needed.
- Parapets and low cover lips are solid, so they block arrows. All keep and
  outpost steps, roof decks, balconies, firing shelves, and curtain walks let
  arrows pass in every direction while supporting players from above.
  These platforms retain their stone art and team tint; field platforms are unchanged.
- Tower platforms use physics layer 6 (`arrow_transparent_platforms`, bit 32).
  The archer mask is 33 (world plus platforms); arrows retain mask 27 and creeps
  retain mask 17, so neither collides with these platforms. Converted nodes also
  belong to `fortress_arrow_transparent_platforms`.
- Terrain, solid cover and field platforms use world layer 1. Ground art has
  tile collisions disabled; continuous polygons provide smooth ramp collisions.
  Player/projectile/shield layers remain the responsibility of their own scenes.
- Four existing spawn markers per team retain their names and groups: two inside
  the keep and two at the forward outpost. Markers sit 16 pixels above the floor.

The oak tileset texture reference is repaired. Stone tiles (8,0), (9,0), (10,0)
have alternative 1 for world-layer thin one-way ledges, alternative 2 for
arrow-transparent one-way tower ledges, and alternative 0 for solid collision.

## Rebuild and check

Use your Godot executable in place of `Godot`:

```sh
Godot --headless --path . --script tools/build_fortress.gd
Godot --headless --path . --script tools/check_fortress.gd
Godot --path . --script tools/check_fortress.gd -- --preview
Godot --path . --script tools/check_fortress.gd -- --preview --keep-preview
```

Rebuilding replaces `Blockout` and updates bounds/spawn positions in
`Fortress1.tscn`, preserving the level UID and other scene nodes. Edit the builder
before rebuilding if you want to retain manual changes within `Blockout`.
The physics check uses a player-sized capsule with the current movement values;
it checks spawn landings, ramp traversal, all tower/perch ascents, balconies,
keep exits, pit escapes, open gate traversal, width,
integration groups, and a world ray against cover. It is not a multiplayer
integration test. Previews write `/tmp/fortress-overview.png` and
`/tmp/fortress-keep.png`.
