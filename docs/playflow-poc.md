# PlayFlow proof of concept

One on-demand Free/small instance, 30 players, automatic balanced teams
(maximum 15 per team), no queue. The dedicated process is not a player.
Existing owner-driven movement and host-judged combat are retained; this is
a transport/hosting proof, not an authoritative movement or CTF rules rewrite.

## Build and run

1. Install Godot 4.7 and its matching Linux export templates.
2. Run `GODOT=/path/to/godot bash tools/prepare_playflow.sh`.
3. Upload `builds/playflow-server.zip` in PlayFlow Builds. Set executable to
   `Server.x86_64` (at the ZIP root). No startup arguments are required.
4. The client's start request includes a `port_configs` override for a port
   named `godot_websocket`, internal port **8080**, protocol **TCP**, **TLS
   enabled**, so no dashboard port setup is required. Godot listens without
   TLS; PlayFlow terminates it. The same port is also set as the project
   default for servers started from the dashboard.
5. Upload the build under the `default` tag. Click **Play** in the client.
   It joins a running instance, waits for an existing launching instance, or
   requests one `small`, `us-east` instance with a 3600-second TTL using the
   client key. The newest ready `default` build is used.
6. The pending overlay shows progress and offers Cancel. The client polls
   every two seconds, allowing 90 seconds overall, then connects using
   `network_ports[].host` and `external_port` for TLS TCP internal port 8080.
   Cancel stops local work, not the shared instance. Manual dashboard startup
   and `tools/start_playflow.sh` remain available.

Free instances expire after one hour. Expiry/disconnection returns players to
the menu; Play can start a new instance. There is no state persistence by default.
An optional, default-off [background networking experiment](background-networking.md)
adds a two-minute session-resume grace. A full
server rejects admission without starting another instance. Each click sends
at most one startup request; ambiguous responses or capacity conflicts trigger
rediscovery. On paid plans this client flow cannot enforce a global one-server
limit across simultaneous clicks; add backend coordination before upgrading.

## Credentials and CI

Add GitHub Actions secret **PLAYFLOW_CLIENT_KEY** using your `pfclient_...`
key. CI bakes it into `networking/playflow_config.tres`, exports the web build,
and uploads `playflow-server` containing the ready-to-upload ZIP. Existing
itch.io deployment remains enabled. The committed client-scoped key enables
local testing; it is public by design and also extractable from the web build.
For native local runs, `PLAYFLOW_CLIENT_KEY` overrides the resource.

The private `pf_...` key is never needed by Godot or the web build. Do not add
it to the client resource, project settings, or ZIP. It lives only in the
GitHub Actions secret **PLAYFLOW_API_KEY**, which `tools/upload_playflow.sh`
uses after the server export to upload the ZIP as the next `default` build and
wait until it is ready. Running instances keep their build; the next server
start uses the new version. CI does not start, restart, or stop live instances.

## Local transport smoke test

Run `godot --headless --path . tools/test_playflow_startup.tscn` for isolated
startup API fixtures, cancellation, timeout, and error cases without cloud writes.

Run the project with `godot --headless --path . -- --playflow-server`.
In a native client select PlayFlow, click Join, and enter
`ws://127.0.0.1:8080`. Browser clients require WSS. For remote troubleshooting
the Join panel also accepts the explicit `wss://host:external_port` copied
from PlayFlow, bypassing discovery.

Validate two clients: both spawn, opposite teams, movement/projectiles and
scores replicate, disconnect removes the player, and reconnect works. Then
test 30 clients and a 31st: the last must receive `Server is full`, with no
extra player or scoreboard entry. Disconnect one and retry the rejected client.
Run `GODOT=/path/to/godot python3 tools/test_playflow.py` to automate the
30-client admission, replicated 15/15 roster, full rejection, and slot-reuse
checks locally (starts a server and up to 31 client processes).
The harness reports existing addon resource-at-exit messages and WebSocket
send/close races during its deliberately abrupt disconnect separately; other
engine/script errors fail the test. These diagnostics do not establish cloud
performance or replace a browser playtest.
Admissions reserve capacity before Godot emits `peer_connected`, preventing
simultaneous joins from exceeding 30. This handshake is capacity/protocol
validation, not account authentication.

Measure CPU, memory, and gameplay responsiveness on the actual small instance
before claiming 30-player performance. WebSockets are ordered/reliable TCP;
loss can delay subsequent movement updates even when RPCs request unreliable
delivery. Tube remains available for existing sessions, but the PlayFlow button
does not use Tube, WebRTC, STUN, or TURN.

References:
- https://docs.playflowcloud.com/quickstart/godot
- https://docs.playflowcloud.com/guides/webgl-deployments
- https://docs.playflowcloud.com/api-reference/servers/list-servers
