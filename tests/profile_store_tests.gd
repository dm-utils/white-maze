extends RefCounted
## P4: the profile file store. Files live under user:// with the prefix white_maze_test_ and are deleted afterwards.

const PATH := "user://white_maze_test_profile.json"
const TMP := PATH + ".tmp"
const DAMAGED := "user://profile.damaged-777.json"

var _check: Callable


func run(check: Callable, _node: Node) -> void:
	_check = check
	_clean()
	_missing_and_round_trip()
	_damaged()
	_newer()
	_empty_device()
	_unwritable()
	_memory()
	_clean()


func _clean() -> void:
	for p in [PATH, TMP, DAMAGED, "user://white_maze_test_dir/profile.json"]:
		DirAccess.remove_absolute(p)
	DirAccess.remove_absolute("user://white_maze_test_dir")


func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _missing_and_round_trip() -> void:
	var s := MazeProfileStore.new()
	s.open(PATH, 100)
	_check.call(FileAccess.file_exists(PATH), "a missing file is created")
	_check.call(s.notice == "" and s.writable, "a missing file gives no notice")
	var d: String = s.data["device"]
	_check.call(d.length() == 16 and d.is_valid_hex_number(false), "the new profile has a 16-hex device id")
	MazeProfile.record_start(s.data, "l001", 200)
	MazeProfile.record_finish(s.data, "l001", 300, 1, "R10", 210)
	_check.call(s.save(250) and s.data["updated"] == 250, "save writes and sets updated")
	_check.call(not FileAccess.file_exists(TMP), "no temp file is left behind")
	var t := MazeProfileStore.new()
	t.open(PATH, 300)
	_check.call(t.data == s.data, "a write and a fresh open round-trip the data")
	_check.call(MazeProfile.is_finished(t.data, "l001"), "the finish survives the round trip")


func _damaged() -> void:
	_write("not json")
	var s := MazeProfileStore.new()
	s.open(PATH, 777)
	_check.call(s.notice == "damaged", "a file with 'not json' sets the damaged notice")
	_check.call(FileAccess.file_exists(DAMAGED), "the damaged file is renamed to profile.damaged-<now>.json")
	_check.call(FileAccess.get_file_as_string(DAMAGED) == "not json", "the damaged file keeps its content")
	var fresh := MazeProfileStore.new()
	fresh.open(PATH, 800)
	_check.call(fresh.notice == "" and fresh.data["levels"] == {}, "a fresh profile was written after the damage")
	DirAccess.remove_absolute(DAMAGED)
	_write('{"format": 0}')
	var z := MazeProfileStore.new()
	z.open(PATH, 777)
	_check.call(z.notice == "damaged", "format 0 counts as damaged")
	DirAccess.remove_absolute(DAMAGED)


func _newer() -> void:
	var text := '{"format": 3, "future": true}'
	_write(text)
	var s := MazeProfileStore.new()
	s.open(PATH, 900)
	_check.call(s.notice == "newer" and not s.writable, "a format-3 file sets the newer notice and is not writable")
	_check.call(not s.save(901), "save returns false for a newer file")
	_check.call(FileAccess.get_file_as_string(PATH) == text, "a format-3 file is left byte-identical")
	_check.call(s.data["format"] == 2, "the session still has a working profile in memory")


func _empty_device() -> void:
	var p := MazeProfile.create("", "en", 5)
	_write(JSON.stringify(p))
	var s := MazeProfileStore.new()
	s.open(PATH, 6)
	var d: String = s.data["device"]
	_check.call(d.length() == 16, "an empty device id is replaced")
	var t := MazeProfileStore.new()
	t.open(PATH, 7)
	_check.call(t.data["device"] == d and t.data["lang"] == "en", "the new device id is saved, other fields kept")


func _unwritable() -> void:
	var s := MazeProfileStore.new()
	s.path = "user://white_maze_test_dir/profile.json"
	s.data = MazeProfile.create("0123456789abcdef", "nl", 1)
	_check.call(not s.save(2), "save fails without crashing when the folder is missing")


func _memory() -> void:
	var s := MazeProfileStore.new()
	s.open_memory("en", 1)
	_check.call(s.data["lang"] == "en" and not s.save(2), "a memory profile is never saved")
