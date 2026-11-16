extends Node
## Steam init, lobbies, SteamMultiplayerPeer. Adapted from LastMage. Uses test app 480 (Spacewar) with a
## unique lobby filter; replace APP_ID when a dedicated app exists. Never share LastMage's key.

signal lobby_list_updated(lobbies: Array) ## [{id, name, members, build}]
signal status_changed(text: String)

const APP_ID := 480
const GAME_KEY := "openchanneloffensive_m0"

var available := false
var init_message := "Not initialized"
var steam_id := 0
var persona_name := ""
var lobby_id := 0


func _ready() -> void:
	if NetworkManager.args.has("no-steam"):
		init_message = "Steam disabled (--no-steam)"
		return
	if not ClassDB.class_exists("Steam") and not Engine.has_singleton("Steam"):
		init_message = "Steam library not loaded (GodotSteam missing for this platform/build)"
		return
	OS.set_environment("SteamAppId", str(APP_ID))
	OS.set_environment("SteamGameId", str(APP_ID))
	var steam: Object = Engine.get_singleton("Steam")
	var res: Dictionary = steam.steamInitEx(APP_ID, true)
	print("[Steam] init: ", res)
	if int(res.get("status", 1)) != 0:
		init_message = "Steam not available: %s (is Steam running and logged in?)" % res.get("verbal", "?")
		return
	available = true
	steam_id = steam.getSteamID()
	persona_name = steam.getPersonaName()
	init_message = "Steam: logged in as %s" % persona_name
	steam.lobby_created.connect(_on_lobby_created)
	steam.lobby_joined.connect(_on_lobby_joined)
	steam.lobby_match_list.connect(_on_lobby_match_list)
	steam.join_requested.connect(func(id: int, _f: int) -> void: join_lobby(id))


func _steam() -> Object:
	return Engine.get_singleton("Steam")


func host_lobby() -> void:
	if not available:
		NetworkManager.connection_failed.emit(init_message)
		return
	status_changed.emit("Creating Steam lobby...")
	_steam().createLobby(_steam().LOBBY_TYPE_PUBLIC, NetworkManager.MAX_PLAYERS)


func request_lobby_list() -> void:
	if not available:
		status_changed.emit(init_message)
		return
	var s := _steam()
	s.addRequestLobbyListDistanceFilter(s.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	s.addRequestLobbyListStringFilter("game", GAME_KEY, s.LOBBY_COMPARISON_EQUAL)
	s.requestLobbyList()
	status_changed.emit("Searching lobbies...")


func join_lobby(id: int) -> void:
	if not available:
		NetworkManager.connection_failed.emit(init_message)
		return
	if NetworkManager.mode != NetworkManager.Mode.OFFLINE:
		NetworkManager.leave("Switching lobby")
	status_changed.emit("Joining lobby %d ..." % id)
	_steam().joinLobby(id)


func leave_lobby() -> void:
	if available and lobby_id != 0:
		_steam().leaveLobby(lobby_id)
	lobby_id = 0


func _on_lobby_created(result: int, id: int) -> void:
	if result != 1:
		NetworkManager.connection_failed.emit("Steam lobby creation failed (result %d)" % result)
		return
	lobby_id = id
	var s := _steam()
	s.setLobbyJoinable(id, true)
	s.setLobbyData(id, "game", GAME_KEY)
	s.setLobbyData(id, "name", "%s's match" % persona_name)
	s.setLobbyData(id, "build", NetworkManager.build_id)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_host(0)
	if err != OK:
		NetworkManager.connection_failed.emit("SteamMultiplayerPeer.create_host failed (%d)" % err)
		return
	print("[Steam] Lobby created ", id)
	NetworkManager.start_host_with_peer(peer, NetworkManager.Mode.STEAM)


func _on_lobby_joined(id: int, _perm: int, _locked: bool, response: int) -> void:
	if response != 1:
		var reasons := {2: "lobby no longer exists", 3: "not allowed", 4: "the lobby is full", 5: "Steam error"}
		NetworkManager.connection_failed.emit("Could not join lobby: %s (code %d)" % [reasons.get(response, "unknown"), response])
		return
	lobby_id = id
	var s := _steam()
	var owner_id: int = s.getLobbyOwner(id)
	if owner_id == steam_id:
		return
	var host_build: String = s.getLobbyData(id, "build")
	if host_build != NetworkManager.build_id:
		s.leaveLobby(id)
		lobby_id = 0
		NetworkManager.connection_failed.emit("Can't join: host build is %s, yours is %s. Both need the same download." % [host_build, NetworkManager.build_id])
		return
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_client(owner_id, 0)
	if err != OK:
		NetworkManager.connection_failed.emit("SteamMultiplayerPeer.create_client failed (%d)" % err)
		return
	status_changed.emit("Connecting to host via Steam...")
	NetworkManager.start_client_with_peer(peer, NetworkManager.Mode.STEAM)


func _on_lobby_match_list(lobbies: Array) -> void:
	var out := []
	var s := _steam()
	for id in lobbies:
		out.append({"id": id, "name": s.getLobbyData(id, "name"),
			"members": s.getNumLobbyMembers(id), "build": s.getLobbyData(id, "build")})
	status_changed.emit("Found %d lobbies" % out.size())
	lobby_list_updated.emit(out)
