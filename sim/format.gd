class_name MazeFormat
extends RefCounted
## Time display.


## m:ss.cc from ticks (60 per second), hundredths rounded down
static func time(ticks: int) -> String:
	var cs := maxi(ticks, 0) * 100 / 60
	return "%d:%02d.%02d" % [cs / 6000, (cs / 100) % 60, cs % 100]
