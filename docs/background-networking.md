# Background networking experiment (PlayFlow / desktop Chrome)

## Feature flag (OFF by default)

`networking/background_resume/enabled=false` in `project.godot` gates the entire
experiment: JS pump, extra buffer headroom, away state, progress watchdog,
retained sessions, reconnect/resync, and replacement-ack timeout. With it off,
clients use ordinary disconnect behavior and do not acquire resume credentials.

Enable the project setting in matching client/server builds, or opt in per run:

- Native/server: add `-- --background-networking` to the command line.
- Web client: add `?background_networking=1` to the **game iframe** URL.
- The server must also enable the flag. An opted-in client receives an explicit
  admission error if the server has it disabled. An enabled server still accepts
  ordinary, non-opted-in clients without changing their disconnect behavior.
- The integration harness enables the flag explicitly; the ordinary PlayFlow
  capacity test continues to test the default-off behavior.

The flag is read at startup; do not toggle it during a live session.

The web export remains single-threaded. `MultiplayerService/WebPresence` installs
a retained JavaScriptBridge callback. While the document is hidden, it disables
SceneTree automatic multiplayer polling and requests a JS timer every 250 ms.
The callback polls the **MultiplayerAPI**, not just the WebSocketPeer, and sends
an application heartbeat after draining messages. Visible tabs return polling
ownership to SceneTree. Timer frequency is a request, not a browser guarantee.
The experiment applies to PlayFlow only; Tube/ENet behavior is unchanged.

## Bounds and recovery

- Requested hidden timer: 250 ms; application heartbeat: 1 second.
- Server closes an established connection after 8 seconds without application
  progress. TCP being open is not considered progress.
- After 30 seconds hidden, a running callback parks the client transport even
  if polling still works. Polling cannot flush all frame-dependent/deferred
  SceneTree work, so the experiment must not accumulate that work indefinitely.
- Hidden/disconnected actors are AFK: their sprite fades to 20% opacity over
  0.3 seconds, their overhead name gains ` (AFK)`, and enemy arrows pass through
  both their body and shield. The server owns this replicated state. World
  collision stays intact; this is arrow immunity, not immunity to all damage.
  Returning restores the normal team opacity, name and arrow collision after
  resynchronization. This remains behind the default-off feature flag.
  Immediate AFK arrow immunity can be used to dodge attacks by tabbing out;
  there is currently no combat delay or return-at-spawn restriction.
- A disconnected actor remains motionless for 120 seconds.
  Shield, charge, movement and firing are disabled. Ordinary deaths, respawns,
  rounds and protection expiration still occur on the server during this grace.
- Return always reconnects to the same server, resetting transport and Godot
  replication caches. A server-issued random 256-bit bearer token maps the new
  peer ID to the existing session. It is held only in memory and never logged.
  Reloading the page or restarting the server does not preserve that token/state.
- The player retains team, K/D/A, current health, position, remaining protection,
  pending respawn and team-switch cooldown. Reconnection itself grants no heal
  or protection. Existing attack attribution is migrated to the new peer ID.
- Input stays disabled behind “Resuming session...” until the new level and
  local actor exist and a current-revision snapshot has been applied. The
  snapshot supplies scoreboard, names, rounds, respawn state and projectile
  clocks; normal fresh-peer scene replication rebuilds players/creeps/map state.
- Recovery retries for up to 30 visible seconds. An expired credential fails
  explicitly and returns to the menu. It does not silently create a fresh actor.
- Explicit Leave sends a release request and waits up to 500 ms for acknowledgment
  before closing. Lost releases fall back to grace expiry. Kicks revoke tokens.
- Replacement acknowledgments have a 5-second deadline; a stalled owner is
  disconnected before its server actor is replaced.

Incoming WebSocket capacity is initially 2 MiB / 16,384 packets per connection,
configured **before** create_client/create_server. This is provisional burst
headroom, not a measured 30-player sizing result or an indefinite buffering fix.
Old events are never blindly discarded out of Godot's replication stream.

## Diagnostics and Chrome experiment

Console lines start with `[background-net]`. While polling, reports appear every
five seconds (subject to throttling), plus visibility/recovery transitions.
`window.gloryNetworkDiagnostics` in the **game iframe** holds the latest report:

- `polls`, `poll_errors`: cumulative background poll calls/results.
- `max_poll_gap_ms`: largest observed gap within hidden polling periods.
- `max_queue_packets`: largest raw WebSocket queue sampled before polling.
  Native sockets normally fill their queue during poll, so zero in native tests
  does not establish web behavior. This counter is packets, not bytes or drops.
- `max_poll_us`: largest dispatch duration, including RPC work.
- `recoveries`, `hidden`, `recovering`, `reason`, `time_ms`.

Reports contain no resume credential. Counters are session-process cumulative;
reload between A/B runs. `?background_poll=0` on the game iframe URL disables the
JS timer pump but keeps visibility/away handling, allowing a controlled baseline
when combined with `background_networking=1`.
Do not add the query only to the outer itch page and assume it reaches the iframe.

Validate with two actual Chrome players, preferably with DevTools closed during
each timed interval (instrumentation may affect scheduling):

1. Keep one player visible. Hide the other for 1, 5, 15 and 45 seconds.
2. Observe that its shield lowers, it remains hittable and cannot fire.
3. Kill it, let it respawn, and change the map/finish a round while it is hidden.
4. Return: input remains blocked during recovery, team/score persist, the world
   is current, and no duplicate actors or permanently missing entities remain.
5. Suspend longer than the grace, sleep/wake the machine, and disconnect the
   network. Recovery must either restore state or return an explicit error.
6. Compare default vs disabled pump: queue peak, poll gaps/duration, console
   overflow messages, process memory, and time from return to resumed input.
7. Repeat at realistic player/projectile counts. Raise buffer limits only using
   measured traffic and memory budgets; do not infer success from no log spam.

Acceptance: bounded queues/work during the experiment, no stuck shield/respawn,
no reconnect heal, correct current world, clean timeout handling. A Chromium
browser playtest is still required; native tests do not model browser suspension.

## Local checks

```sh
GODOT=/path/to/godot python3 tools/test_background_network.py
node tools/test_background_bridge.mjs
```

The integration harness runs a real local WebSocket server, a visible observer,
and a client driving the production hide/poll/resume entry points. It covers
damaged/dead restoration, map changes, stalled polling, bounded parking, explicit
leave, expired credentials, duplicate actor prevention, and observer replication.
The JS test evaluates the actual embedded bridge with fake timers/events to
check timer ownership, visibility, freeze, A/B disabling and listener cleanup.
Neither test represents an actual Chrome throttling measurement.

For local browser testing, export a **debug** Web build, serve it over localhost,
and join `ws://127.0.0.1:8080` through the Join panel (start the server with
`godot --headless --path . -- --playflow-server`). Only debug web exports show
Join and permit this loopback exception; release exports hide it and require WSS.

A debug export was smoke-tested this way in Chrome with a **simulated**
`document.hidden` (automation cannot truly background a tab, so rendering and
timers were unthrottled): with SceneTree polling off, the JS pump alone kept the
session alive for 15 s (41 polls, 267 ms max gap, 21 packets peak queue, no poll
errors, no server stall) and return recovered once. This validates the bridge in
a browser, not Chrome's throttling; the two-player checklist above is still owed.

## Rollout

The admission protocol is now `glory-playflow-2`. Deploy matching server and web
builds together and replace running v1 server instances; an existing PlayFlow
instance keeps its old build. This implementation does not publish, restart or
provision anything. Existing scene RPC changes also require matching clients.
Thread support and itch SharedArrayBuffer settings do not need to change.

The 30-client capacity harness (`tools/test_playflow.py`) uses the default-off
mode and verifies immediate slot reuse. In the opted-in integration harness,
reserved actors count toward capacity and team population until grace expiry.
