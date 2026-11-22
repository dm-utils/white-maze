class_name MazePoseBlend
extends RefCounted
## Blends Lilith's rig over BLEND_TICKS of render time when the pose key changes (design 20.3.3). Pure.

const BLEND_TICKS := 6.0

var enabled := true

var _has := false
var _key := Vector2i.ZERO
var _from := {} # empty: no blend running
var _start := 0.0
var _last := {}


## next apply() switches at once
func reset() -> void:
	_has = false
	_from = {}


## key = Vector2i(body, arm); t in ticks of render time
func apply(key: Vector2i, target: Dictionary, t: float) -> Dictionary:
	var dead := int(MazeLilith.Body.DEAD)
	if not enabled:
		_from = {}
	elif _has and key != _key and key.x != dead and _key.x != dead:
		_from = _last
		_start = t
	elif key != _key:
		_from = {}
	_key = key
	_has = true
	var out := target
	if not _from.is_empty():
		var k := smoothstep(0.0, 1.0, (t - _start) / BLEND_TICKS)
		out = MazeLilith.blend_rig(_from, target, k)
		if t - _start >= BLEND_TICKS:
			_from = {}
	_last = out
	return out
