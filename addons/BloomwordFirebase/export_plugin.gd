@tool
extends EditorPlugin

const PLUGIN_NAME := "BloomwordFirebase"
const ANDROID_ANALYTICS := "com.google.firebase:firebase-analytics:23.2.0"
const ANDROID_CRASHLYTICS := "com.google.firebase:firebase-crashlytics:20.0.6"
const ANDROID_COMMON := "com.google.firebase:firebase-common:22.1.0"

var _android_export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	_android_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_android_export_plugin)

func _exit_tree() -> void:
	if _android_export_plugin:
		remove_export_plugin(_android_export_plugin)
	_android_export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
	var _plugin_name := PLUGIN_NAME

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_name() -> String:
		return _plugin_name

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var kind := "debug" if debug else "release"
		var suffix := "debug" if debug else "release"
		return PackedStringArray(["%s/bin/%s/%s-%s.aar" % [_plugin_name, kind, _plugin_name, suffix]])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		# Godot's Android export hook passes plain Maven coordinates, so pin the Firebase modules explicitly
		# instead of relying on Gradle platform()/BoM syntax.
		return PackedStringArray([ANDROID_ANALYTICS, ANDROID_CRASHLYTICS, ANDROID_COMMON])
