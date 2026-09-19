class_name PresentationBuffer
extends RefCounted
const CAPACITY := 32
var samples: Array[Dictionary] = []
var last_sequence := -1

func clear() -> void:
	samples.clear()
	last_sequence = -1

func push(sample: Dictionary, sequence: int) -> void:
	if sequence <= last_sequence:
		return
	last_sequence = sequence
	if not samples.is_empty() and sample.time <= samples[-1].time:
		return
	samples.append(sample)
	if samples.size() > CAPACITY:
		samples.pop_front()

func sample_at(time: float) -> Dictionary:
	if samples.is_empty():
		return {}
	while samples.size() > 2 and samples[1].time <= time:
		samples.pop_front()
	if time <= samples[0].time:
		return samples[0]
	if time >= samples[-1].time:
		return samples[-1]
	for i in range(1, samples.size()):
		var b := samples[i]
		if b.time >= time:
			var a := samples[i - 1]
			var alpha: float = (time - a.time) / (b.time - a.time)
			var result := a.duplicate()
			result.position = a.position.lerp(b.position, alpha)
			result.aim = lerp_angle(a.aim, b.aim, alpha)
			return result
	return samples[-1]
