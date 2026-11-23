class_name MazeChainShare
extends RefCounted
## Hands the share card to the system share sheet (web) or a file (design 22.11.4). No network, no external script.

const DIR := "user://chains"
const TITLE := "White Maze"
const SHARE_JS := """window.whiteMazeShare = window.whiteMazeShare || function (b64, name, title, text) {
  var bin = atob(b64);
  var bytes = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  var blob = new Blob([bytes], {type: 'image/png'});
  var download = function () {
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url; a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 10000);
  };
  try {
    var file = new File([blob], name, {type: 'image/png'});
    if (navigator.canShare && navigator.canShare({files: [file]})) {
      navigator.share({files: [file], title: title, text: text}).catch(function (e) {
        if (!e || e.name !== 'AbortError') download();
      });
      return 'share';
    }
  } catch (e) {}
  download();
  return 'download';
};"""


## "share" when the share sheet was opened, "download" when the image was saved by the browser
static func share(png: PackedByteArray, file_name: String, title: String, text: String) -> String:
	JavaScriptBridge.eval(SHARE_JS, true)
	var expr := "window.whiteMazeShare(%s, %s, %s, %s)" % [
		JSON.stringify(Marshalls.raw_to_base64(png)), JSON.stringify(file_name), JSON.stringify(title),
		JSON.stringify(text),
	]
	return str(JavaScriptBridge.eval(expr, true))


## user:// path of the saved file, "" on failure
static func save_local(png: PackedByteArray, file_name: String) -> String:
	if png.is_empty() or DirAccess.make_dir_recursive_absolute(DIR) != OK:
		return ""
	var path := DIR.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(png)
	f.close()
	return path


static func file_name(level_id: String, rings: int, ticks: int) -> String:
	return "white-maze-%s-%d-%d.png" % [level_id, rings, ticks]


## text that goes with the image: line, the share code when there is one, the play address
static func share_text(info: Dictionary) -> String:
	var lines := PackedStringArray([
		MazeStrings.s("share_text") % [info["number"], info["name"], info["rings"], info["par"],
				MazeFormat.time(info["ticks"])],
	])
	if str(info.get("code", "")) != "":
		lines.append(str(info["code"]))
	lines.append("https://" + MazeChainView.PLAY_ADDRESS)
	return "\n".join(lines)
