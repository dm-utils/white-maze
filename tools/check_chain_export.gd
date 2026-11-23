extends SceneTree
## Share card with a real renderer: renders l004, checks the PNG and saves it like the Share button does.
## xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/check_chain_export.gd
## Optional user argument --save=<file.png> keeps a copy of the image.
## Exit 0 when the image is a 1200 x 675 PNG with the card on it, else 1.

const TIMEOUT_S := 20.0


func _initialize() -> void:
	MazeStrings.register()
	var lv := MazeLevels.load_level("l004")
	var res := MazeChain.from_run(lv, str(WhitePuzzleStore.load_json("res://tests/solutions.json")["l004"]))
	var text := MazeChain.encode(res["links"])
	var info := {
		"level": lv, "links": res["links"], "world": MazeWorlds.for_number(4), "clasp": res["rings"] <= lv.par,
		"number": 4, "name": "Eén kraal", "ticks": res["ticks"], "rings": res["rings"], "par": lv.par,
		"code": MazeChain.code(lv.id, res["rings"], lv.par, res["ticks"], text),
	}
	var export := MazeChainExport.new()
	root.add_child(export)
	var done := [false]
	export.ready_png.connect(func() -> void: done[0] = true)
	export.render(info)
	var waited := 0.0
	while not done[0] and waited < TIMEOUT_S:
		await create_timer(0.1).timeout
		waited += 0.1
	var errors := PackedStringArray()
	if export.png.is_empty():
		errors.append("no image after %.1f s" % waited)
	else:
		var img := Image.new()
		if img.load_png_from_buffer(export.png) != OK:
			errors.append("the bytes are not a PNG")
		elif img.get_size() != Vector2i(MazeChainExport.SIZE):
			errors.append("size is %s" % img.get_size())
		else:
			var corner := img.get_pixel(2, 2)
			var lit := 0
			for x in range(40, 1160, 4):
				for y in range(124, 612, 4):
					if img.get_pixel(x, y).get_luminance() > 0.8:
						lit += 1
			if lit < 20:
				errors.append("the beads and the text are not on the image (%d bright pixels)" % lit)
			if corner.a < 1.0:
				errors.append("the background is transparent")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--save=") and not export.png.is_empty():
			var f := FileAccess.open(a.substr(7), FileAccess.WRITE)
			f.store_buffer(export.png)
			f.close()
	var path := MazeChainShare.save_local(export.png, "white-maze-check.png")
	if path == "" or FileAccess.get_file_as_bytes(path).is_empty():
		errors.append("save_local wrote nothing")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(MazeChainShare.DIR)
	for e in errors:
		printerr("FAIL: " + e)
	print("chain export: %d bytes, %s" % [export.png.size(), "ok" if errors.is_empty() else "FAILED"])
	quit(0 if errors.is_empty() else 1)
