# Creeps

Each fortress creates three soldiers when its level is ready, then three every
30 seconds. Fortress1 and Fortress2 both have dedicated `CreepBlue1..3` and
`CreepOrange1..3` markers under `SpawnPoints`; their builders preserve them.
Soldiers march through center and hold at the opposing team's first creep
marker, immediately outside its gate. While holding there they strike the enemy
gate with their normal melee damage whenever no enemy soldier is in reach; see
`docs/rounds.md` for gate health and rounds.

## Behavior and tuning

- `entities/creep.tscn`: 200 health, no regeneration and no respawn.
- `entities/creep.gd`: 60 px/s, 48-pixel melee radius, independent uniform
  0.8–1.4-second swing delays, equal odds of 20 or 25 damage.
- `networking/creep_spawner.gd`: wave size 3, interval 30 seconds.
- All these defaults are editable in the Inspector.

The simple state machine uses `MARCH`, `ATTACK`, `HOLD`, and `DEAD`. Attacks hit
one opposing creep at frame 3 of the six-frame attack animation, after checking
radial reach again. Creep melee ignores terrain between opponents so soldiers
can fight across ramp edges and small obstacles. Soldiers use gravity and small
terrain hops; horizontal space reservations prevent passing or climbing over
nearby soldiers, but ignore soldiers more than 48 pixels vertically away.
Occupied spawn positions retain pending soldiers, including when a soldier is
airborne above the slot. Waves have no population cap or timeout.

Creeps occupy physics layer 5 (`creeps`, bit 16), with mask 17 (world + creeps).
Players pass through them. Enemy arrows hit them; friendly arrows pass through.
Enemy arrows that hit a creep stick in it until the creep dies and its corpse is
removed.
Arrows that land in the top 5-pixel band of a soldier's or player's body
(`HeadHitbox/HeadShape`, an editor-visible rect with no physics layers) are
headshots and deal `headshot_damage_multiplier` times damage (1.5 on
`ArrowPlayer`, editable in the Inspector). The shooter alone hears
`headshot_ping.mp3` for a headshot and `click.mp3` for any other damaging arrow
hit; creep melee plays no sound.
Player shields do not damage creeps, and creeps never target players. Creep
kills award one scoreboard kill to the player who deals the killing blow. Earlier
damage grants no credit, and creep-on-creep kills add no player kills or deaths.

A living creep contributes one member to its team inside the ram's existing
160-pixel detection radius. Death immediately removes collision, combat, and
ram participation. The corpse lingers 3 seconds (holding the last death frame) before permanent removal.

## Multiplayer lifecycle

The server alone spawns, moves, attacks, rolls randomness, and removes creeps.
Clients receive position snapshots at 20 Hz and changed health, state, facing,
animation, and hit feedback. The sprite position is interpolated locally.
HealthComponent rejects client-requested creep damage.

`World/CreepSpawner` replicates children of `World/Creeps`. LevelLoader assigns
a revision to each load and accepts peer readiness acknowledgments only for
that revision. Creep and ram synchronizers stay hidden from a peer until its
level is ready. Late joiners receive current state, including wounded or dying
soldiers. Level replacement clears soldiers and pending waves, then starts a
fresh timer; session exit also clears them.

## Checks

Replace `Godot` with the local executable:

```sh
Godot --headless --path . tools/check_creeps.tscn
Godot --headless --path . tools/check_rounds.tscn
Godot --headless --path . --script tools/check_fortress.gd
Godot --headless --path . --script tools/check_fortress2.gd
Godot --path . tools/check_creeps.tscn -- --preview
```

The preview writes `/tmp/creeps-preview.png`. The creep check exercises real
terrain traversal with full squads, blocked spawning, timing, combat, arrow
damage, headshots and hit sounds, player pass-through, ram counts, and cleanup.

Run the network check in two terminals (localhost UDP port 19736):

```sh
Godot --headless --path . tools/check_creeps_network.tscn -- --server
Godot --headless --path . tools/check_creeps_network.tscn -- --client
```

Repeat with `--server --listen-host` to include a host player. Both checks use
the real gameplay replication and verify late joining, rejected client damage,
death removal, and level replacement. The server exits successfully after the
client confirms all stages, or fails after a 20-second timeout.
