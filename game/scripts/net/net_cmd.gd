class_name NetCmd
extends RefCounted
## One fixed-tick (60 Hz) player input. The same command drives Player.simulate() and Loadout.apply_cmd()
## offline, on the host (authoritative) and on the owning client (prediction + replay).
## All buttons are absolute states, so a lost packet never loses an edge: edges are derived when applied.

const SIZE := 23 ## encoded bytes

var seq := 0 ## per-player sequence; host processes each seq at most once, in order
var round_id := 0
var view_tick := 0 ## server tick of the remote players this client was looking at (lag compensation)
var move := Vector2.ZERO ## x = right, y = back (Input.get_vector convention)
var yaw := 0.0
var pitch := 0.0
var crouch := false
var vault := false
var slow_walk := false
var lean := 0 ## -1 left, +1 right; opposing keys cancel
var fire := false
var aim := false
var reload := false
var interact := false
var drop_bomb := false
var gadgets := 0
var tool := 0 ## Loadout.Tool the player wants selected


func encode(buf: StreamPeerBuffer) -> void:
	buf.put_u32(seq)
	buf.put_u16(round_id & 0xFFFF)
	buf.put_u32(view_tick)
	buf.put_8(int(roundf(clampf(move.x, -1.0, 1.0) * 127.0)))
	buf.put_8(int(roundf(clampf(move.y, -1.0, 1.0) * 127.0)))
	buf.put_float(yaw)
	buf.put_float(pitch)
	var b := int(crouch) | int(slow_walk) << 1 | int(fire) << 2 | int(aim) << 3 | int(reload) << 4 | (tool & 3) << 5 | int(interact) << 7 | int(drop_bomb) << 8 | ((tool >> 2) & 3) << 9 | (gadgets & 7) << 11 | int(lean < 0) << 14 | int(lean > 0) << 15
	buf.put_u16(b)
	buf.put_u8(int(vault))


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
	c.slow_walk = b & 2 != 0
	c.fire = b & 4 != 0
	c.aim = b & 8 != 0
	c.reload = b & 16 != 0
	c.interact = b & 128 != 0
	c.drop_bomb = b & 256 != 0
	c.tool = ((b >> 5) & 3) | (((b >> 9) & 3) << 2)
	c.gadgets = (b >> 11) & 7
	c.lean = int(b & 32768 != 0) - int(b & 16384 != 0)
	c.vault = buf.get_u8() != 0
	return c


## Wire round-trip (quantises move) so local prediction uses exactly what the host will see.
func quantised() -> NetCmd:
	var buf := StreamPeerBuffer.new()
	encode(buf)
	buf.seek(0)
	return NetCmd.decode(buf)
