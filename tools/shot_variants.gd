extends SceneTree
## Greyscale and half size copies of screenshots, so the lip can be judged without colour and at small size
## (design 21.15). godot --headless -s res://tools/shot_variants.gd -- a.png b.png; writes a-grey.png, a-half.png.

const LUT_STEPS := 4096


func _init() -> void:
	var lin := PackedFloat32Array()
	for v in 256:
		lin.append(MazeArt._lin(v / 255.0))
	var inv := PackedByteArray()
	for i in LUT_STEPS:
		var l := i / float(LUT_STEPS - 1)
		var s := l * 12.92 if l <= 0.0031308 else 1.055 * pow(l, 1.0 / 2.4) - 0.055
		inv.append(clampi(roundi(s * 255.0), 0, 255))
	var failed := false
	for path in OS.get_cmdline_user_args():
		var img := Image.load_from_file(path)
		if img == null or img.is_empty():
			printerr("cannot read ", path)
			failed = true
			continue
		img.convert(Image.FORMAT_RGBA8)
		var base := path.get_basename()
		var half := img.duplicate() as Image
		half.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
		half.save_png(base + "-half.png")
		var data := img.get_data()
		for i in range(0, data.size(), 4):
			var l := 0.2126 * lin[data[i]] + 0.7152 * lin[data[i + 1]] + 0.0722 * lin[data[i + 2]]
			var g := inv[roundi(l * (LUT_STEPS - 1))]
			data[i] = g
			data[i + 1] = g
			data[i + 2] = g
		var grey := Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
		grey.save_png(base + "-grey.png")
	quit(1 if failed else 0)
