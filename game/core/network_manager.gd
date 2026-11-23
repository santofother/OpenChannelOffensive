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
const GAME_VERSION := "0.2.0"
## Bump when the wire protocol changes incompatibly; part of build_id so mismatched builds are refused.
const PROTOCOL := 21
const REGISTER_TIMEOUT := 15.0

## "<GAME_VERSION>-p<PROTOCOL>+<commit>". Host and clients must match exactly; `--build-id=X` overrides (tests).
var build_id := ""
var mode: Mode = Mode.OFFLINE
var local_name := "Player"
var player_names: Dictionary = {} ## peer_id -> name (host-authoritative)
var args: Dictionary = {} ## user args after `--`, e.g. `--host-enet --name=Bob`
var selected_map := "lightwell" ## host-owned; accepted before a client enters its map scene
## Host: bots take every empty team slot (3 per team) and step aside when a person joins. Menu toggle, default on;
## `--bots=0` turns it off. Automated network tests never get bots.
var fill_bots := true
var last_end_reason := "" ## shown by the menu after a session ends (e.g. "Host left the game")

var _register_wait := 0.0
var _connect_wait := 0.0
var enet_address := ""
var enet_port := DEFAULT_PORT


func _ready() -> void:
	args = _parse_args()
	selected_map = String(args.get("map", "demo" if args.has("net-test") else "lightwell"))
	if not MapRegistry.SCENES.has(selected_map):
		selected_map = "lightwell"
	build_id = String(args["build-id"]) if args.has("build-id") else _read_build_id()
	print("[Net] Build ", build_id)
	if args.has("name"):
		local_name = args["name"]
	if args.has("bots"):
		fill_bots = String(args["bots"]) not in ["0", "false", "off"]
	multiplayer.peer_connected.connect(_on_peer_connected)
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
	return ["Offline", "LAN", "Steam"][mode]


func is_in_session() -> bool:
	var p := multiplayer.multiplayer_peer
	return mode != Mode.OFFLINE and p != null and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func host_enet(port: int = DEFAULT_PORT) -> Error:
	enet_port = port
	enet_address = "*"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		connection_failed.emit("Could not host on port %d (%s)" % [port, error_string(err)])
		return err
	start_host_with_peer(peer, Mode.ENET)
	return OK


func join_enet(ip: String, port: int = DEFAULT_PORT) -> Error:
	ip = ip.strip_edges()
	if ip.is_empty():
		connection_failed.emit("Enter the host computer's LAN IP address. The host shows it in Esc settings.")
		return ERR_INVALID_PARAMETER
	enet_address = ip
	enet_port = port
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
	_connect_wait = 30.0 if m == Mode.STEAM else REGISTER_TIMEOUT
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
	_connect_wait = 0.0
	player_names.clear()
	last_end_reason = reason
	print("[Net] Session ended: ", reason)
	status_changed.emit(reason)
	session_ended.emit(reason)
	roster_changed.emit()


func _on_peer_connected(id: int) -> void:
	print("[Net] PEER_CONNECTED ", id)
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer and multiplayer.is_server():
		# Six local peers exposed ENet's RTT-based probabilistic shedding (throttle 10/32,
		# 4/25 voice packets delivered on localhost). Our command/voice streams are bounded;
		# don't add arbitrary loss on top of real network loss. Steam has its own transport.
		# https://docs.godotengine.org/en/stable/classes/class_enetpacketpeer.html#class-enetpacketpeer-method-throttle-configure
		peer.get_peer(id).throttle_configure(5000, 2, 0)


func _on_peer_disconnected(id: int) -> void:
	print("[Net] PEER_DISCONNECTED ", id)
	if multiplayer.is_server():
		player_names.erase(id)
		_sync_names.rpc(player_names)
	peer_left.emit(id)
	roster_changed.emit()


func _on_connected_to_server() -> void:
	_connect_wait = 0.0
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		peer.get_peer(1).throttle_configure(5000, 2, 0)
	print("[Net] CONNECTED my_id=", multiplayer.get_unique_id())
	status_changed.emit("Connected (%s)" % mode_name())
	connected.emit()
	_register_wait = REGISTER_TIMEOUT
	var layouts := MapRegistry.manifests()
	if args.has("map-hash"):
		layouts["lightwell"] = String(args["map-hash"]) # mismatch regression hook
	_register.rpc_id(1, local_name, build_id, layouts)


func lan_addresses() -> PackedStringArray:
	var addresses := PackedStringArray()
	for address in IP.get_local_addresses():
		if ":" not in address and not address.begins_with("127.") and not address.begins_with("169.254.") and address != "0.0.0.0":
			addresses.append(address)
	addresses.sort()
	return addresses


func lan_help() -> String:
	return "Same LAN/Wi-Fi or VPN required. Allow the host app through its firewall (UDP %d). On Mac, allow Open Channel Offensive in System Settings > Privacy & Security > Local Network." % enet_port


func _on_connection_failed() -> void:
	var reason := "Steam connection failed (host unreachable or match full)."
	if mode == Mode.ENET:
		reason = "Could not reach %s:%d. %s" % [enet_address, enet_port, lan_help()]
	leave(reason)
	connection_failed.emit(reason)


# NET: client -> host. Host validates build and capacity.
@rpc("any_peer", "call_remote", "reliable")
func _register(pname: String, build: String = "", layouts: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var why := ""
	if build != build_id:
		why = "Can't join: host build is %s, yours is %s. Both need the same download." \
			% [build_id, build if not build.is_empty() else "unknown"]
	elif layouts.get(selected_map, "") != MapRegistry.identity(selected_map):
		why = "Can't join: %s map layout differs. Both need the same download." % selected_map
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
	_accepted_map.rpc_id(id, selected_map, MapRegistry.identity(selected_map))
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
	if _connect_wait > 0.0:
		_connect_wait -= delta
		if _connect_wait <= 0.0:
			_on_connection_failed()
	if not is_in_session() or multiplayer.is_server():
		return
	if _register_wait > 0.0:
		_register_wait -= delta
		if _register_wait <= 0.0:
			leave("Can't join: the host didn't accept you (different build?). Yours: %s" % build_id)


@rpc("authority", "call_remote", "reliable")
func _accepted_map(map_id: String, signature: String) -> void:
	if not MapRegistry.SCENES.has(map_id) or MapRegistry.identity(map_id) != signature:
		leave("Can't join: map layout differs. Both need the same download.")
		return
	selected_map = map_id
