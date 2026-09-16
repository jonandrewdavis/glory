# Teams and shared ram

Edit `scenes/gameplay/team_settings.tres` in the Inspector to rename each team's
friendly and enemy labels. Gameplay uses only `Teams.Team.BLUE` / `ORANGE`.

The pause menu offers team switching. The server rejects joining an existing
majority and enforces 60 seconds between successful switches. Equal team sizes
permit switching. Initial assignment has no cooldown. Switching replaces the
player at a new team's spawn, removes their arrows, and preserves kills/deaths.
Cooldowns last for the current connection and clear on disconnect or session exit.

Player health belongs to the server. Only opposing players can cause damage;
client damage RPCs, friendly fire, self damage, and unattributed damage are rejected.

The Fortress1 ram has no collision objects. Living players inside the circular
radius determine its direction: Blue pushes right, Orange pushes left, ties stop.
Speed is constant. Its editable route follows terrain and stops with the nose at
either gate. Gate damage and victory logic are not implemented.

The server synchronizes route distance and direction; clients smooth the drawing.
The level builder preserves the root ram instance while rebuilding scenery.
