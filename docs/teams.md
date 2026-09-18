# Teams and shared ram

Edit `scenes/gameplay/team_settings.tres` in the Inspector to rename each team's
friendly and enemy labels. Gameplay uses only `Teams.Team.BLUE` / `ORANGE`.

The pause menu offers team switching. The server rejects joining an existing
majority and enforces 60 seconds between successful switches. Equal team sizes
permit switching. Initial assignment has no cooldown. Switching replaces the
player at a new team's spawn, removes their arrows, and preserves kills/deaths/assists.
Cooldowns last for the current connection and clear on disconnect or session exit.

Player health belongs to the server. Only opposing players can cause damage;
client damage RPCs, friendly fire, self damage, and unattributed damage are rejected.
Respawn waits scale with team population; the ram captures forward spawn bands.
See [respawns.md](respawns.md) for timing, capture milestones and map authoring.

The shared ram has no collision objects. Living players and creeps inside the
circular radius determine its direction: Blue pushes right, Orange pushes left,
ties stop. Speed is constant (14 px/s). Its editable route follows terrain and
stops with the nose at either gate, where it winds up and strikes; gate health,
rounds and the siege HUD are described in `docs/rounds.md`.

The server synchronizes route distance and direction; clients smooth the drawing.
The level builder preserves the root ram instance while rebuilding scenery.

## Player scoring

The always-visible scoreboard groups players by Blue/Orange and shows individual
kills, deaths and assists; there are no team kill totals. Only player deaths count.
Within each team, rows sort by kills, assists, fewer deaths, then peer ID.

Each victim remembers the three most recent distinct opposing player IDs for the
whole life, with no timeout. A repeated attacker moves to the front; a fourth
evicts the oldest. Healing retains history. The lethal attacker gets the kill and
the other two get one assist each, even if those attackers have since died.
Disconnects/team switches remove that attacker from outstanding histories.
Death, respawn and player replacement clear the victim's history.

Only the server awards stats, recording the accepted damage before health reaches
zero. K/D/A updates replicate together. Late joiners receive current totals.
The kill feed shows only "X killed Y", colored by the killer's team at death,
with five newest entries lasting eight seconds and fading during the final second.
Names are snapshots, assists are never shown, and round/session resets clear the feed.

Checks: `tools/check_kda.tscn` and `tools/check_kda_network.tscn` (run separate
processes with `-- --server` and `-- --client`).
