class_name PlayerSnapshot
extends RefCounted
## Fixed-width absolute state. No Variant decoding or dependent delta baselines.
const VERSION := 1
const HEADER := 30
const RECORD := 38
const MAX_BYTES := 1200
const PER_CHUNK := (MAX_BYTES - HEADER) / RECORD

static func encode(epoch: int, revision: int, sequence: int, tick: int, stamp: float, records: Array) -> Array[PackedByteArray]:
	var chunks: Array[PackedByteArray] = []
	for start in range(0, records.size(), PER_CHUNK):
		var count := mini(PER_CHUNK, records.size() - start)
		var bytes := PackedByteArray()
		bytes.resize(HEADER + count * RECORD)
		bytes.encode_u16(0, VERSION)
		bytes.encode_u32(2, epoch)
		bytes.encode_u32(6, revision)
		bytes.encode_u32(10, sequence)
		bytes.encode_u32(14, tick)
		bytes.encode_double(18, stamp)
		bytes.encode_u16(26, start / PER_CHUNK)
		bytes.encode_u16(28, count)
		for i in count:
			var r: Dictionary = records[start + i]
			var at := HEADER + i * RECORD
			bytes.encode_u32(at, r.peer)
			bytes.encode_u32(at + 4, r.serial)
			bytes.encode_u32(at + 8, r.sequence)
			bytes.encode_float(at + 12, r.position.x)
			bytes.encode_float(at + 16, r.position.y)
			bytes.encode_float(at + 20, r.velocity.x)
			bytes.encode_float(at + 24, r.velocity.y)
			bytes.encode_u16(at + 28, roundi(fposmod(r.aim, TAU) / TAU * 65535.0))
			bytes.encode_u16(at + 30, r.flags)
			bytes.encode_u16(at + 32, r.level)
			bytes.encode_float(at + 34, r.age)
		chunks.append(bytes)
	return chunks

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER or bytes.size() > MAX_BYTES or bytes.decode_u16(0) != VERSION:
		return {}
	var count := bytes.decode_u16(28)
	if count > PER_CHUNK or bytes.size() != HEADER + count * RECORD:
		return {}
	var stamp := bytes.decode_double(18)
	if not is_finite(stamp):
		return {}
	var records: Array[Dictionary] = []
	for i in count:
		var at := HEADER + i * RECORD
		var pos := Vector2(bytes.decode_float(at + 12), bytes.decode_float(at + 16))
		var vel := Vector2(bytes.decode_float(at + 20), bytes.decode_float(at + 24))
		var age := bytes.decode_float(at + 34)
		if not pos.is_finite() or not vel.is_finite() or not is_finite(age) or bytes.decode_u16(at + 32) >= 3:
			return {}
		records.append({"peer": bytes.decode_u32(at), "serial": bytes.decode_u32(at + 4),
			"sequence": bytes.decode_u32(at + 8), "position": pos, "velocity": vel,
			"aim": bytes.decode_u16(at + 28) / 65535.0 * TAU, "flags": bytes.decode_u16(at + 30),
			"level": bytes.decode_u16(at + 32), "age": age, "time": stamp})
	return {"epoch": bytes.decode_u32(2), "revision": bytes.decode_u32(6),
		"sequence": bytes.decode_u32(10), "tick": bytes.decode_u32(14), "time": stamp,
		"chunk": bytes.decode_u16(26), "records": records}
