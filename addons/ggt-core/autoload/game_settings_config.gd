## GGT_GameConfig autoload
extends Node

const CONFIG_FILE_PATH = &"user://settings.cfg"

var config = ConfigFile.new()
## Test clients never read or overwrite the user's settings file.
var _ephemeral := "--isolated-settings" in OS.get_cmdline_user_args()

signal ui_scale_changed(value: float)
signal aim_sensitivity_changed(value: float)
signal username_changed(value: String)

const MAX_USERNAME_LENGTH := 20

const DEFAULT_AIM_SENSITIVITY := 0.05
const MIN_AIM_SENSITIVITY := 0.01
const MAX_AIM_SENSITIVITY := 0.09
## The settings menu shows sensitivity as 0-100 across the min-max range.
const AIM_SENSITIVITY_LEVELS := 100.0
const AIM_SENSITIVITY_STEP := (MAX_AIM_SENSITIVITY - MIN_AIM_SENSITIVITY) / AIM_SENSITIVITY_LEVELS

const DEFAULT_UI_SCALE := 1.25
const MIN_UI_SCALE := 0.75
const MAX_UI_SCALE := 2.0
const UI_SCALE_STEP := 0.05

const SUPPORTED_LOCALES = {
	"en": "English",
	"it": "Italiano",
	#"ja": "日本語",
	#"zh": "简体中文",
	#"ar": "العربية",
	#"ru": "Русский",
}

enum AudioBus {
	MASTER,
	SFX,
	BGM
}

const FPS_MAX_HARD_CAP = 400

func _ready() -> void:
	if _ephemeral:
		initialize_default_file()
		_apply_settings()
		return
	if FileAccess.file_exists(CONFIG_FILE_PATH):
		var err = config.load(CONFIG_FILE_PATH)
		if err != OK:
			reset()
			return
	else:
		reset()

	if get_username().is_empty():
		set_username("Player%04d" % (randi() % 10000))
		persist()
	_apply_settings()


func reset() -> void:
	initialize_default_file()
	if not _ephemeral:
		config.save(CONFIG_FILE_PATH)
	_apply_settings()


func persist() -> void:
	if not _ephemeral:
		config.save(CONFIG_FILE_PATH)


func revert_to(cfg: ConfigFile) -> void:
	config.parse(cfg.encode_to_text())
	_apply_settings()


func initialize_default_file() -> void:
	config.set_value("audio", "master", 0.0)
	config.set_value("audio", "sfx", 0.0)
	config.set_value("audio", "music", 0.0)
	config.set_value("gfx", "ui_scale", DEFAULT_UI_SCALE)
	config.set_value("gfx", "fps_limit", 60)
	config.set_value("controls", "aim_sensitivity", DEFAULT_AIM_SENSITIVITY)
	if not OS.has_feature('web'):
		config.set_value("gfx", "fullscreen", true)
		config.set_value("gfx", "vsync", true)

	var os_locale = OS.get_locale_language()
	if os_locale in SUPPORTED_LOCALES:
		config.set_value("game", "locale", os_locale)
	else:
		config.set_value("game", "locale", "en")


func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(AudioBus.MASTER, config.get_value("audio", "master", AudioServer.get_bus_volume_db(AudioBus.MASTER)))
	AudioServer.set_bus_volume_db(AudioBus.SFX, config.get_value("audio", "sfx", AudioServer.get_bus_volume_db(AudioBus.SFX)))
	AudioServer.set_bus_volume_db(AudioBus.BGM, config.get_value("audio", "music", AudioServer.get_bus_volume_db(AudioBus.BGM)))

	ui_scale_changed.emit(get_ui_scale())

	var fps_limit: int = config.get_value("gfx", "fps_limit", 60)
	Engine.max_fps = fps_limit if fps_limit > 0 else FPS_MAX_HARD_CAP

	TranslationServer.set_locale(config.get_value("game", "locale", "en"))
	aim_sensitivity_changed.emit(get_aim_sensitivity())
	username_changed.emit(get_username())

	if not OS.has_feature('web'):
		var window_id = get_window().get_window_id()
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if config.get_value("gfx", "vsync", true) else DisplayServer.VSYNC_DISABLED,
			window_id
		)
		get_window().mode = Window.MODE_FULLSCREEN if config.get_value("gfx", "fullscreen", true) else Window.MODE_WINDOWED


#region setters
func set_master_volume(v: float) -> void:
	config.set_value("audio", "master", v)
	AudioServer.set_bus_volume_db(AudioBus.MASTER, v)


func set_sfx_volume(v: float) -> void:
	config.set_value("audio", "sfx", v)
	AudioServer.set_bus_volume_db(AudioBus.SFX, v)


func set_music_volume(v: float) -> void:
	config.set_value("audio", "music", v)
	AudioServer.set_bus_volume_db(AudioBus.BGM, v)


func set_ui_scale(v: float) -> void:
	v = clampf(snappedf(v, UI_SCALE_STEP), MIN_UI_SCALE, MAX_UI_SCALE)
	config.set_value("gfx", "ui_scale", v)
	ui_scale_changed.emit(v)


func set_vsync(v: bool) -> void:
	config.set_value("gfx", "vsync", v)
	var window_id = get_window().get_window_id()
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED,
		window_id
	)


func set_fps_limit(v: int) -> void:
	config.set_value("gfx", "fps_limit", v)
	Engine.max_fps = v if v > 0 else FPS_MAX_HARD_CAP


func set_fullscreen(v: bool) -> void:
	config.set_value("gfx", "fullscreen", v)
	get_window().mode = Window.MODE_FULLSCREEN if v else Window.MODE_WINDOWED


func set_locale(locale: String) -> void:
	config.set_value("game", "locale", locale)
	TranslationServer.set_locale(locale)


func set_aim_sensitivity(v: float) -> void:
	v = aim_level_to_sensitivity(aim_sensitivity_to_level(v))
	config.set_value("controls", "aim_sensitivity", v)
	aim_sensitivity_changed.emit(v)


func set_username(v: String) -> void:
	v = sanitize_username(v)
	if v.is_empty() or v == get_username():
		return
	config.set_value("game", "username", v)
	username_changed.emit(v)
#endregion


#region getters
func get_ui_scale(cfg: ConfigFile = config) -> float:
	var value := float(cfg.get_value("gfx", "ui_scale", DEFAULT_UI_SCALE))
	return clampf(snappedf(value, UI_SCALE_STEP), MIN_UI_SCALE, MAX_UI_SCALE)


func get_locale() -> String:
	return config.get_value("game", "locale", "en")


func get_username(cfg: ConfigFile = config) -> String:
	return sanitize_username(str(cfg.get_value("game", "username", "")))


## Strips whitespace and control characters, then caps the length.
static func sanitize_username(value: String) -> String:
	var cleaned := ""
	for c in value:
		if c.unicode_at(0) >= 32 and c.unicode_at(0) != 127:
			cleaned += c
	return cleaned.strip_edges().left(MAX_USERNAME_LENGTH).strip_edges()


func get_aim_sensitivity(cfg: ConfigFile = config) -> float:
	var value := float(cfg.get_value("controls", "aim_sensitivity", DEFAULT_AIM_SENSITIVITY))
	# Values above the range were saved under an older, faster scale (defaults 0.5, 0.25, 0.1).
	if value > MAX_AIM_SENSITIVITY + AIM_SENSITIVITY_STEP * 0.5:
		value = DEFAULT_AIM_SENSITIVITY
	return aim_level_to_sensitivity(aim_sensitivity_to_level(value))


func aim_sensitivity_to_level(value: float) -> float:
	return clampf(roundf((value - MIN_AIM_SENSITIVITY) / AIM_SENSITIVITY_STEP), 0.0, AIM_SENSITIVITY_LEVELS)


func aim_level_to_sensitivity(level: float) -> float:
	return MIN_AIM_SENSITIVITY + clampf(level, 0.0, AIM_SENSITIVITY_LEVELS) * AIM_SENSITIVITY_STEP
#endregion
