# Rounds, gates and the siege HUD

A round ends when either keep's gate falls. The winning team's name shows for
five seconds, the current level reloads (ram back to centre, gates at full
health, soldiers cleared and a fresh wave queued), and every player is
re-spawned at their team spawn with full health. Round wins are tracked as
"Blue N - M Orange"; kills, deaths and assists in the scoreboard persist across rounds
and reset only when the session ends.
Spawn-band ownership resets before round respawns. On Fortress2 each team returns
to its active outpost; see [respawns.md](respawns.md) for territory and death waits.

## Gates

`entities/fortress_gate.tscn` (`FortressGate`) is instanced by both level
builders under each keep, at the former ram impact point. It is an Area2D on
physics layer 7 (`gates`, bit 64) with no mask, so players and creeps walk
through the facade as before. Its HealthComponent has 5000 health, no
regeneration and no respawn, and belongs to the server; `current` is replicated
with the same per-peer visibility gating as the ram and creeps.

Two exports size and harden the gate per level. `hitbox_size` (default 48 by 96)
is the timber rect used by arrows, creeps and `hitbox()`; the root always sits
2 pixels outside it, halfway up. `blocks_players` (default off) makes the gate
add a `Barrier` StaticBody2D of the same rect on layer 6 (mask 0), which stops
players from both sides while creeps and arrows ignore it. Fortress2 uses a
24-by-64 gate with the barrier on; Fortress1 keeps the defaults.

Damage sources, all validated on the server in `HealthComponent.take_damage`:

- Arrows: the ray sweep includes the gates layer (arrow mask 91). Enemy arrows
  deal their level damage (no headshots), stick in the gate and click for the
  shooter. Friendly and breached gates are transparent to arrows.
- Creeps: a soldier holding at the enemy marker strikes the gate with its normal
  20/25 damage whenever no enemy soldier is within reach. Enemy soldiers always
  take priority.
- The battering ram: 500 per strike (below).

Client damage requests, unattributed damage and friendly damage are rejected.
A damaged gate draws a small team-coloured bar above the timber.

## Battering ram

The ram moves at 14 px/s. Contact means the route clamp bound: `distance` 0 is
the blue gate nose and the full route length is the orange gate nose. While in
contact with a living gate the ram winds up for eight seconds, shown as a white
bar above it. Leaving the gate resets the wind-up. When the wind-up completes
the ram strikes: it stays locked against the gate for four seconds (orange bar
and lunge), lands 500 damage, then moves normally and needs a fresh eight
seconds of contact before the next strike. Contact counts regardless of which
team is nearby, so an unattended ram at a gate keeps striking; defenders must
push it away. `speed`, `windup_time`, `strike_time` and `strike_damage` are
Inspector options. `attack_state` and `attack_progress` are replicated.

## Round manager

`World/RoundManager` (`scenes/gameplay/round_manager.gd`) is host-authoritative.
Every level load starts a new round and wires each gate's `died` signal. A gate
death during play awards the round to the other team, broadcasts the ENDED
phase, waits `BANNER_SECONDS`, then reloads the current level and re-instances
every player through `PlayerSpawner.replace_player`. A level change from the
pause menu or a session exit cancels the pending restart; level changes keep
round wins, session exit clears them. Late joiners receive the current round
state on connection.
For remote replacements the server first asks the owner to stop its previous
movement synchronizer, then spawns a uniquely named incarnation after acknowledgment.

## HUD

`scenes/gameplay/ui/round_hud.tscn` sits in the UI layer. Along the top its Control nodes show
a blue and an orange gate health bar with numeric values, and beneath them a thin
ram track: the blue gate is the left end,
the orange gate the right end, the fill runs from the centre to the ram's route
progress in the colour of the team that has pushed it, and the marker is tinted
by whichever team is pushing right now. The winner banner appears mid-screen
while a round is ended. The round score still updates but its Label remains
intentionally hidden. The converted respawn strip/countdown also remain hidden
under the root of `respawn_hud.tscn`; no runtime update reveals that root.

## Checks

```sh
Godot --headless --path . tools/check_rounds.tscn
```

The round check covers gate health and walkability, arrow, creep and ram damage
with validation, the ram wind-up, reset, lock and strike, a full round end with
level reload, player respawn and persisting kills, the HUD labels, and session
clearing. `tools/check_creeps.tscn`, `check_fortress.gd` and
`check_fortress2.gd` still apply.
