class_name MazeInput
extends RefCounted
## Input of one tick.

var move := 0 # -1, 0, 1
var jump_held := false
var jump_pressed := false # press since the previous tick, latched by the controls
var throw_dir := -1 # aim index 0..143 or -1
var undo := false


static func idle() -> MazeInput:
	return MazeInput.new()


func equals(other: MazeInput) -> bool:
	return (
		move == other.move
		and jump_held == other.jump_held
		and jump_pressed == other.jump_pressed
		and throw_dir == other.throw_dir
		and undo == other.undo
	)
