class_name NetCmd
extends RefCounted
## One fixed-tick (60 Hz) player input. The same command drives Player.simulate() and Loadout.apply_cmd()
## offline, on the host (authoritative) and on the owning client (prediction + replay).
## All buttons are absolute states, so a lost packet never loses an edge: edges are derived when applied.

const SIZE := 22 ## encoded bytes

var seq := 0 ## per-player sequence; host processes each seq at most once, in order
var round_id := 0
var view_tick := 0 ## server tick of the remote players this client was looking at (lag compensation)
var move := Vector2.ZERO ## x = right, y = back (Input.get_vector convention)
var yaw := 0.0
var pitch := 0.0
var crouch := false
var sprint := false
var fire := false
var aim := false
var reload := false
var tool := 0 ## Loadout.Tool the player wants selected


func encode(buf: StreamPeerBuffer) -> void:
	buf.put_u32(seq)
	buf.put_u16(round_id & 0xFFFF)
	buf.put_u32(view_tick)
	buf.put_8(int(roundf(clampf(move.x, -1.0, 1.0) * 127.0)))
	buf.put_8(int(roundf(clampf(move.y, -1.0, 1.0) * 127.0)))
	buf.put_float(yaw)
	buf.put_float(pitch)
	var b := int(crouch) | int(sprint) << 1 | int(fire) << 2 | int(aim) << 3 | int(reload) << 4 | (tool & 3) << 5
	buf.put_u16(b)


static func decode(buf: StreamPeerBuffer) -> NetCmd:
	var c := NetCmd.new()
	c.seq = buf.get_u32()
	c.round_id = buf.get_u16()
	c.view_tick = buf.get_u32()
	c.move = Vector2(buf.get_8() / 127.0, buf.get_8() / 127.0)
	c.yaw = buf.get_float()
	c.pitch = buf.get_float()
	var b := buf.get_u16()
	c.crouch = b & 1 != 0
	c.sprint = b & 2 != 0
	c.fire = b & 4 != 0
	c.aim = b & 8 != 0
	c.reload = b & 16 != 0
	c.tool = clampi((b >> 5) & 3, 0, 2)
	return c


## Wire round-trip (quantises move) so local prediction uses exactly what the host will see.
func quantised() -> NetCmd:
	var buf := StreamPeerBuffer.new()
	encode(buf)
	buf.seek(0)
	return NetCmd.decode(buf)
