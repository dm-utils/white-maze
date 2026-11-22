class_name MazeStaticBake
extends Node2D
## Static world drawn once into one texture per chunk (back wall and tiles together), then one sprite per chunk.
## Replaces thousands of cached canvas commands per frame by a few quads (design 18.10, ADR 0010).

const SCALE := 2.0 # texels per world px; camera zoom is 2.0
const BYTES_PER_PX := 4

var baked_bytes := 0 # texture memory of the current level
var chunk_total := 0

var _back := MazeStaticLayer.new()
var _tiles := MazeStaticLayer.new()


func build(lv: MazeLevel, world_id: int) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_back.build(lv, world_id, MazeStaticLayer.Kind.BACK)
	_tiles.build(lv, world_id, MazeStaticLayer.Kind.TILES)
	baked_bytes = 0
	var void_node := _back.make_void()
	void_node.z_index = -3
	add_child(void_node)
	var n := _back.chunks()
	chunk_total = n.x * n.y
	var cell := MazeStaticLayer.CHUNK
	for cy in n.y:
		for cx in n.x:
			var origin := Vector2(cx, cy) * cell * MazeStaticLayer.T
			var extent := Vector2(
				mini(cell, lv.width - cx * cell), mini(cell, lv.height - cy * cell)
			) * MazeStaticLayer.T
			add_child(_bake_chunk(cx, cy, origin, extent))


## chunks of both layers, as the layers count them
func chunk_count() -> int:
	return _back.chunk_count() + _tiles.chunk_count()


## canvas draws of both layers so far
func draws() -> int:
	return _back.draws + _tiles.draws


func _bake_chunk(cx: int, cy: int, origin: Vector2, extent: Vector2) -> Sprite2D:
	var vp := SubViewport.new()
	vp.size = Vector2i((extent * SCALE).ceil())
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var root := Node2D.new()
	root.position = -origin * SCALE
	root.scale = Vector2.ONE * SCALE
	root.add_child(_back.make_chunk(cx, cy))
	root.add_child(_tiles.make_chunk(cx, cy))
	vp.add_child(root)
	var sprite := Sprite2D.new()
	sprite.z_index = -2
	sprite.centered = false
	sprite.position = origin
	sprite.scale = Vector2.ONE / SCALE
	sprite.texture = vp.get_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.add_child(vp)
	baked_bytes += vp.size.x * vp.size.y * BYTES_PER_PX
	return sprite
