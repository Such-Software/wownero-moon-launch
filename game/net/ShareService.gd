extends Node
## ShareService — cross-platform "share your score" helper.
## Autoloaded singleton. All methods safe to call on any platform.
##
## Strategy by platform:
##   Web    — try navigator.share() via JavaScriptBridge; fallback to clipboard.
##   Mobile — copy text to clipboard, open the itch URL in the system browser.
##   Desktop— copy to clipboard, open the itch URL.
##
## In all cases, a toast is emitted via the `share_completed` signal so the
## calling screen can display feedback without binding to a specific UI.

signal share_completed(method: String)  # "native", "clipboard", "failed"

const ITCH_URL := "https://suchsoftware.itch.io/such-moon-launch"
const HASHTAGS := "#suchmoonlaunch #indiegame"


func share_score(level_name: String, stars: int, time_s: float) -> void:
	Telemetry.log_event(Telemetry.EVENT_SHARE_PRESSED, {
		"level": level_name,
		"stars": stars,
	})
	var star_str := "★".repeat(stars) + "☆".repeat(3 - stars)
	var text := "I just landed on %s with %s in %.2fs — beat my time!\n%s\n%s" % [
		level_name, star_str, time_s, ITCH_URL, HASHTAGS,
	]
	if OS.has_feature("web"):
		_share_web(text, level_name)
	else:
		_share_native(text)


func _share_web(text: String, _level_name: String) -> void:
	# Try navigator.share() (mobile browsers); fall back to clipboard.
	if not Engine.has_singleton("JavaScriptBridge"):
		_clipboard_fallback(text)
		return
	# JS-side: invoke navigator.share if present; else copy to clipboard.
	var js := """
		(function() {
			var msg = %s;
			var url = '%s';
			if (navigator.share) {
				navigator.share({title: 'Such Moon Launch', text: msg, url: url})
					.then(function() { return 'native'; })
					.catch(function() { return 'failed'; });
				return 'native_pending';
			}
			if (navigator.clipboard) {
				navigator.clipboard.writeText(msg + ' ' + url);
				return 'clipboard';
			}
			return 'failed';
		})();
	""" % [JSON.stringify(text), ITCH_URL]
	var result = JavaScriptBridge.eval(js, true)
	# We can't reliably await the navigator.share Promise from GDScript, so
	# treat any non-failed return as a soft success and emit a toast.
	if result == "failed":
		_clipboard_fallback(text)
		return
	share_completed.emit("native" if str(result).begins_with("native") else "clipboard")


func _share_native(text: String) -> void:
	# Copy + open itch URL. Future v1.1: use Android Intent.ACTION_SEND for a real share sheet.
	DisplayServer.clipboard_set(text)
	OS.shell_open(ITCH_URL)
	share_completed.emit("clipboard")


func _clipboard_fallback(text: String) -> void:
	DisplayServer.clipboard_set(text)
	share_completed.emit("clipboard")
