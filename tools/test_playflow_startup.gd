extends Node
## Deterministic API fixtures: no requests reach PlayFlow and no servers are started.
class FakeBackend extends PlayFlowBackend:
	var sent: Array = []
	var urls: Array[String] = []
	var failures: Array[String] = []
	var polls := 0
	var real_poll := false
	func _ready() -> void:
		join_lobby_failed.connect(func(reason: String) -> void: failures.append(reason))
	func _send_request(path: String, method: int, body: String, kind: RequestKind) -> void:
		sent.append({"path": path, "method": method, "body": body, "kind": kind})
	func _connect_url(url: String) -> void:
		urls.append(url)
	func _poll_later() -> void:
		if real_poll:
			super._poll_later()
		else:
			polls += 1
	func _close_peer() -> void:
		pass
	func reply(kind: RequestKind, data: Variant, code := 200, result := HTTPRequest.RESULT_SUCCESS, token := -1) -> void:
		_on_response(result, code, JSON.stringify(data).to_utf8_buffer(), kind, attempt if token < 0 else token)

var checks := 0
var failed := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failed += 1
	checks += 1

func backend() -> FakeBackend:
	var value := FakeBackend.new()
	add_child(value)
	value.join_game("auto")
	return value

func server(state := "running") -> Dictionary:
	return {"instance_id": "test-instance", "status": state, "network_ports": [{
		"internal_port": 8080, "external_port": 12345, "host": "example.test",
		"protocol": "tcp", "tls_enabled": true
	}]}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var running := backend()
	check(running.sent[0].path == "?include_launching=true", "Discovery includes launching servers")
	running.reply(PlayFlowBackend.RequestKind.LIST, {"servers": [server("launching"), server()]})
	check(running.urls == ["wss://example.test:12345"] and running.sent.size() == 1, "Running server wins without POST")
	running.leave_game()

	var launch := backend()
	launch.reply(PlayFlowBackend.RequestKind.LIST, {"servers": [server("launching")]})
	check(launch.polls == 1 and launch.selected_id == "test-instance", "Wait for existing startup")
	launch._poll_server()
	check(launch.sent[-1].path == "/test-instance", "Poll selected instance")
	launch.reply(PlayFlowBackend.RequestKind.DETAILS, server())
	check(launch.urls.size() == 1 and not launch.start_requested, "Connect after existing startup")
	launch.leave_game()

	var empty := backend()
	empty.reply(PlayFlowBackend.RequestKind.LIST, {"servers": []})
	var post: Dictionary = empty.sent[-1]
	check(post.path == "/start" and post.method == HTTPClient.METHOD_POST, "Start absent instance")
	check(JSON.parse_string(post.body) == {"name": "glory-poc", "region": "us-east", "compute_size": "small", "ttl": 3600.0, "version_tag": "default"}, "Free tier startup parameters")
	check(empty.client_key.begins_with("pfclient_"), "Use public client key")
	empty.reply(PlayFlowBackend.RequestKind.START, server("launching"), 201)
	empty.reply(PlayFlowBackend.RequestKind.DETAILS, server())
	check(empty.urls.size() == 1, "Connect after own startup")
	empty.leave_game()

	for response in [409, 403, 500, 429, 0]:
		var race := backend()
		race.reply(PlayFlowBackend.RequestKind.LIST, {"servers": []})
		race.reply(PlayFlowBackend.RequestKind.START, {"error": "Active server limit reached"}, response,
			HTTPRequest.RESULT_TIMEOUT if response == 0 else HTTPRequest.RESULT_SUCCESS)
		check(race.joining and race.polls == 1, "Rediscover ambiguous or conflicting start")
		race.reply(PlayFlowBackend.RequestKind.LIST, {"servers": []})
		check(race.sent.size() == 2, "Never send a second POST")
		race.reply(PlayFlowBackend.RequestKind.LIST, {"servers": [server()]})
		check(race.urls.size() == 1, "Join instance started by another player")
		race.leave_game()

	for response in [401, 403, 422]:
		var failure := backend()
		failure.reply(PlayFlowBackend.RequestKind.LIST, {"servers": []})
		failure.reply(PlayFlowBackend.RequestKind.START, {"error": "Rejected"}, response)
		check(failure.failures.size() == 1 and not failure.joining, "Credential/build errors terminate")

	var invalid := backend()
	var bad_port := server()
	bad_port.network_ports[0].tls_enabled = false
	invalid.reply(PlayFlowBackend.RequestKind.LIST, {"servers": [bad_port]})
	check(invalid.failures.size() == 1 and invalid.sent.size() == 1, "Invalid port must not start another instance")
	var stopped := backend()
	stopped.reply(PlayFlowBackend.RequestKind.DETAILS, server("stopped"))
	check(stopped.failures.size() == 1, "Stopped startup fails clearly")
	var timeout := backend()
	timeout.deadline = 0
	timeout._process(0.0)
	check(timeout.failures.size() == 1 and not timeout.joining, "Enforce entire-operation deadline")

	var cancel := backend()
	var old_token := cancel.attempt
	cancel.real_poll = true
	cancel.reply(PlayFlowBackend.RequestKind.LIST, {"servers": [server("launching")]})
	cancel.leave_game()
	cancel.join_game("auto")
	cancel.reply(PlayFlowBackend.RequestKind.LIST, {"servers": []}, 200, HTTPRequest.RESULT_SUCCESS, old_token)
	await get_tree().create_timer(2.1).timeout
	check(cancel.sent.size() == 2 and cancel.urls.is_empty(), "Cancelled callbacks and polls cannot affect retry")
	cancel.leave_game()
	cancel.join_game("ws://127.0.0.1:8080")
	check(cancel.sent.size() == 2 and cancel.urls.size() == 1, "Explicit URLs bypass provisioning")
	cancel.leave_game()
	var menu: Node = load("res://scenes/menu/menu.tscn").instantiate()
	check(menu.get_node("MainContainer/Control/VBoxContainer/PlayFlowButton").text == "Play", "Button label")
	menu.free()
	if failed == 0:
		print("PASS: ", checks, " PlayFlow startup checks (no live provisioning)")
	get_tree().quit(0 if failed == 0 else 1)
