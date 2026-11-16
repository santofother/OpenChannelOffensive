extends Node
## Session layer (ENet for local tests, Steam for human play). Adapted from LastMage's NetworkManager.
## Host refuses clients whose build_id differs; the client gets a clear reason via `session_ended`.

signal hosting_started
signal connected
signal connection_failed(reason: String)
signal player_registered(peer_id: int, player_name: String) ## server only
signal peer_left(peer_id: int)
signal session_ended(reason: String)
signal status_changed(text: String)
signal roster_changed

enum Mode { OFFLINE, ENET, STEAM }

const DEFAULT_PORT := 24690
const MAX_PLAYERS := 6 ## 3v3
const GAME_VERSION := "0.1.0"
## Bump when the wire protocol changes incompatibly; part of build_id so mismatched builds are refused.
const PROTOCOL := 1
const REGISTER_TIMEOUT := 15.0

## "<GAME_VERSION>-p<PROTOCOL>+<commit>". Host and clients must match exactly; `--build-id=X` overrides (tests).
var build_id := ""
var mode: Mode = Mode.OFFLINE
var local_name := "Player"
var player_names: Dictionary = {} ## peer_id -> name (host-authoritative)
var args: Dictionary = {} ## user args after `--`, e.g. `--host-enet --name=Bob`

var _register_wait := 0.0


func _ready() -> void:
	args = _parse_args()
	build_id = String(args["build-id"]) if args.has("build-id") else _read_build_id()
	print("[Net] Build ", build_id)
	if args.has("name"):
		local_name = args["name"]
	multiplayer.peer_connected.connect(func(id: int) -> void: print("[Net] PEER_CONNECTED ", id))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(func() -> void: leave("Host left the game"))


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out


func _read_build_id() -> String:
	var commit := ""
	if FileAccess.file_exists("res://build_commit.txt"):
		commit = FileAccess.get_file_as_string("res://build_commit.txt").strip_edges()
	elif OS.has_feature("editor"):
		var out: Array = []
		if OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "--short", "HEAD"], out) == 0 \
				and not out.is_empty():
			commit = String(out[0]).strip_edges()
	return "%s-p%d%s" % [GAME_VERSION, PROTOCOL, "+" + commit if not commit.is_empty() else ""]


func mode_name() -> String:
	return ["Offline", "ENet (local test)", "Steam"][mode]


func is_in_session() -> bool:
	var p := multiplayer.multiplayer_peer
	return mode != Mode.OFFLINE and p != null and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func host_enet(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		connection_failed.emit("Could not host on port %d (%s)" % [port, error_string(err)])
		return err
	start_host_with_peer(peer, Mode.ENET)
	return OK


func join_enet(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		connection_failed.emit("Could not connect to %s:%d (%s)" % [ip, port, error_string(err)])
		return err
	start_client_with_peer(peer, Mode.ENET)
	status_changed.emit("Connecting to %s:%d ..." % [ip, port])
	return OK


func start_host_with_peer(peer: MultiplayerPeer, m: Mode) -> void:
	mode = m
	multiplayer.multiplayer_peer = peer
	player_names = {1: local_name}
	print("[Net] Hosting (%s) as '%s'" % [mode_name(), local_name])
	status_changed.emit("Hosting (%s)" % mode_name())
	hosting_started.emit()
	player_registered.emit(1, local_name)
	roster_changed.emit()


func start_client_with_peer(peer: MultiplayerPeer, m: Mode) -> void:
	mode = m
	multiplayer.multiplayer_peer = peer


func leave(reason: String = "Left game") -> void:
	if mode == Mode.OFFLINE:
		return
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	if mode == Mode.STEAM:
		SteamManager.leave_lobby()
	mode = Mode.OFFLINE
	_register_wait = 0.0
	player_names.clear()
	print("[Net] Session ended: ", reason)
	status_changed.emit(reason)
	session_ended.emit(reason)
	roster_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	print("[Net] PEER_DISCONNECTED ", id)
	if multiplayer.is_server():
		player_names.erase(id)
		_sync_names.rpc(player_names)
	peer_left.emit(id)
	roster_changed.emit()


func _on_connected_to_server() -> void:
	print("[Net] CONNECTED my_id=", multiplayer.get_unique_id())
	status_changed.emit("Connected (%s)" % mode_name())
	connected.emit()
	_register_wait = REGISTER_TIMEOUT
	_register.rpc_id(1, local_name, build_id)


func _on_connection_failed() -> void:
	leave("Connection failed")
	connection_failed.emit("Connection failed (host unreachable or full)")


# NET: client -> host. Host validates build and capacity.
@rpc("any_peer", "call_remote", "reliable")
func _register(pname: String, build: String = "") -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var why := ""
	if build != build_id:
		why = "Can't join: host build is %s, yours is %s. Both need the same download." \
			% [build_id, build if not build.is_empty() else "unknown"]
	elif player_names.size() >= MAX_PLAYERS:
		why = "Can't join: the match is full (%d/%d)." % [player_names.size(), MAX_PLAYERS]
	if not why.is_empty():
		print("[Net] REJECTED ", id, ": ", why)
		_rejected.rpc_id(id, why)
		# Give the reliable message time to arrive before cutting the connection.
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer and id in multiplayer.get_peers():
				multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	pname = pname.strip_edges().left(20)
	if pname.is_empty():
		pname = "Player%d" % (player_names.size() + 1)
	player_names[id] = pname
	print("[Net] REGISTERED ", id, " ", pname)
	_sync_names.rpc(player_names)
	player_registered.emit(id, pname)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_names(names: Dictionary) -> void:
	player_names = names
	if names.has(multiplayer.get_unique_id()):
		_register_wait = 0.0
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	print("[Net] Rejected by host: ", reason)
	leave(reason)
	connection_failed.emit(reason)


func _process(delta: float) -> void:
	if not is_in_session() or multiplayer.is_server():
		return
	if _register_wait > 0.0:
		_register_wait -= delta
		if _register_wait <= 0.0:
			leave("Can't join: the host didn't accept you (different build?). Yours: %s" % build_id)
