class_name MazeChainExport
extends Node
## Renders the share card (design 22.11) into a PNG when the result opens, so Share can use the browser's user
## activation for the share call alone.

signal ready_png

const SIZE := Vector2i(1200, 675)

var png := PackedByteArray()

var _viewport: SubViewport
var _view: MazeChainView
var _serial := 0


## info: level, links, world, clasp, number, name, ticks, rings, par, code
func render(info: Dictionary) -> void:
	_serial += 1
	var mine := _serial
	png = PackedByteArray()
	if _viewport != null:
		remove_child(_viewport)
		_viewport.queue_free()
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_view = MazeChainView.new()
	_view.style = MazeChainShapes.Style.EXPORT
	_view.export_info = info
	_view.size = Vector2(SIZE)
	_view.setup(info["level"], info["links"], info["world"], info["clasp"], MazeChainShapes.FINAL_T, true)
	_viewport.add_child(_view)
	add_child(_viewport)
	var vp := _viewport
	await RenderingServer.frame_post_draw
	if mine != _serial or not is_instance_valid(vp):
		return
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		png = img.save_png_to_buffer()
		if not png.is_empty():
			ready_png.emit()


func view() -> MazeChainView:
	return _view
