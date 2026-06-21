extends Label


func _ready():
	var ver = ProjectSettings.get_setting("application/config/version")
	var mode = "debug" if OS.is_debug_build() else "release"
	text =  "%s (%s)" % [ver, mode]
