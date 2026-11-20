extends Control
## Minimal main scene; level select and game screen follow in phase 1b.

const BG := Color("#1B1F26")


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
