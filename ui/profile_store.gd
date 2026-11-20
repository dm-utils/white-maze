class_name MazeProfileStore
extends RefCounted
## Local profile file (design 7.4): atomic write, damaged files set aside, newer formats left alone.

const DEFAULT_PATH := "user://profile.json"

var path := DEFAULT_PATH
var data := {}
var writable := true
var notice := "" # "" | "damaged" | "newer"
var memory_only := false # screenshots: never touches the disk


## profile in memory only, never saved
func open_memory(lang: String, now: int) -> void:
	memory_only = true
	writable = false
	data = MazeProfile.create(_new_device(), lang, now)


func open(p: String, now: int) -> void:
	path = p
	notice = ""
	writable = true
	if not FileAccess.file_exists(path):
		data = MazeProfile.create(_new_device(), "nl", now)
		save(now)
		return
	var parsed: Variant = null
	var json := JSON.new()
	var text := FileAccess.get_file_as_string(path)
	if json.parse(text) == OK:
		parsed = json.data
	var res := MazeProfile.sanitize(parsed)
	match res["status"]:
		"newer":
			data = MazeProfile.create(_new_device(), "nl", now)
			writable = false
			notice = "newer"
		"damaged":
			_set_aside(now)
			data = MazeProfile.create(_new_device(), "nl", now)
			save(now)
			notice = "damaged"
		_:
			data = res["profile"]
			if str(data.get("device", "")) == "":
				data["device"] = _new_device()
				save(now)


## false when not writable or on any failure
func save(now: int) -> bool:
	if not writable or memory_only:
		return false
	data["updated"] = now
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("profile: cannot write %s" % tmp)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("profile: cannot rename %s (error %d)" % [tmp, err])
		return false
	return true


func _set_aside(now: int) -> void:
	var dest := path.get_base_dir().path_join("profile.damaged-%d.json" % now)
	if DirAccess.rename_absolute(path, dest) != OK:
		push_warning("profile: cannot move the damaged file aside")


static func _new_device() -> String:
	return Crypto.new().generate_random_bytes(8).hex_encode()
