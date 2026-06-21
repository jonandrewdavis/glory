@tool
extends Theme
## Palette-driven dark UI with dedicated control states and original SVG artwork.

@export var accent_color: Color = Color("55c8f0"):
	set(value):
		accent_color = value
		rebuild()
@export var gradient_color: Color = Color("9385f5"):
	set(value):
		gradient_color = value
		rebuild()
@export var success_color: Color = Color("53d6a3"):
	set(value):
		success_color = value
		rebuild()
@export var warning_color: Color = Color("f5c36b"):
	set(value):
		warning_color = value
		rebuild()
@export var danger_color: Color = Color("f47f99"):
	set(value):
		danger_color = value
		rebuild()
@export var surface_color: Color = Color("252f3f"):
	set(value):
		surface_color = value
		rebuild()
@export_range(4, 24, 1) var corner_radius: int = 8:
	set(value):
		corner_radius = value
		rebuild()
@export_range(0, 8, 1) var elevation: int = 2:
	set(value):
		elevation = value
		rebuild()
@export_range(0.0, 1.0, 0.05) var gradient_strength: float = 0.55:
	set(value):
		gradient_strength = value
		rebuild()

const INK = Color("142032")
const PAPER = Color("f1f5fc")
const REGULAR = preload("res://assets/fonts/Lato-Regular.ttf")
const BOLD = preload("res://assets/fonts/Lato-Bold.ttf")
const BLACK = preload("res://assets/fonts/Lato-Black.ttf")

func _init() -> void:
	rebuild()

func _margins(box: StyleBox, padding: Vector2) -> StyleBox:
	box.content_margin_left = padding.x
	box.content_margin_right = padding.x
	box.content_margin_top = padding.y
	box.content_margin_bottom = padding.y
	return box

func _box(color: Color, padding := Vector2(18, 10), border := Color.TRANSPARENT, depth := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(corner_radius)
	box.corner_detail = 12
	box.set_border_width_all(1 if border.a > 0.0 else 0)
	box.border_color = border
	box.shadow_color = Color(0.015, 0.022, 0.04, 0.25)
	box.shadow_size = depth * 2
	box.shadow_offset = Vector2(0, depth)
	_margins(box, padding)
	return box

func _empty(padding := Vector2.ZERO) -> StyleBoxEmpty:
	return _margins(StyleBoxEmpty.new(), padding) as StyleBoxEmpty

func _hex(color: Color) -> String:
	return "#" + color.to_html(false)

func _svg(body: String, width: int, height: int) -> DPITexture:
	var source := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % [width, height, width, height, body]
	# Store SVG source rather than raw pixels. Godot rasterizes at the active UI
	# scale while preserving logical dimensions, including on high-DPI displays.
	return DPITexture.create_from_string(source)

func _gradient_box(color: Color, end: Color, padding := Vector2(20, 11), pressed := false, radius := -1) -> StyleBoxTexture:
	# Nine-slicing keeps corners crisp; a tiny lower edge replaces chunky extrusion.
	var r := corner_radius if radius < 0 else radius
	var edge := mini(elevation, 2) if not pressed else 0
	var body := '<defs><linearGradient id="fill" x2="1" y2="0.4"><stop stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient><linearGradient id="light" x2="0" y2="1"><stop stop-color="white" stop-opacity="0.09"/><stop offset="1" stop-color="white" stop-opacity="0"/></linearGradient></defs>' % [_hex(color), _hex(end)]
	body += '<rect y="%d" width="160" height="%d" rx="%d" fill="%s"/>' % [edge, 64-edge, r, _hex(color.darkened(0.30))]
	body += '<rect width="160" height="%d" rx="%d" fill="url(#fill)"/><rect x="0.5" y="0.5" width="159" height="%d" rx="%d" fill="url(#light)" stroke="white" stroke-opacity="0.09"/>' % [64-edge, r, 63-edge, r]
	var box := StyleBoxTexture.new()
	box.texture = _svg(body, 160, 64)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_texture_margin(side, r + 2)
	_margins(box, padding)
	return box

func _ink_on(color: Color) -> Color:
	var luminance := color.srgb_to_linear().get_luminance()
	var dark_luminance := INK.srgb_to_linear().get_luminance()
	return INK if (luminance + 0.05) / (dark_luminance + 0.05) > 1.05 / (luminance + 0.05) else Color.WHITE

func _text_colors(type: StringName, normal: Color, hover: Color) -> void:
	for key in ["font_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		set_color(key, type, normal)
	set_color("font_hover_color", type, hover)
	set_color("font_disabled_color", type, surface_color.lerp(PAPER, 0.38))
	set_font("font", type, REGULAR)
	set_constant("h_separation", type, 10)
	set_constant("outline_size", type, 0)

func _focus() -> StyleBoxFlat:
	var box := _box(Color.TRANSPARENT, Vector2.ZERO, accent_color.lightened(0.18))
	box.draw_center = false
	box.set_border_width_all(2)
	box.set_expand_margin_all(2)
	return box

func _button(type: StringName, color: Color, colored := false, outlined := false) -> void:
	var end := color.lerp(gradient_color if color == accent_color else color.lightened(0.20), gradient_strength)
	var ink := _ink_on(color.lerp(end, 0.5)) if colored else PAPER
	_text_colors(type, ink, ink)
	set_font("font", type, BOLD)
	var padding := Vector2(20, 11)
	if colored:
		set_stylebox("normal", type, _gradient_box(color, end))
		set_stylebox("hover", type, _gradient_box(color.lightened(0.10), end.lightened(0.10)))
		set_stylebox("pressed", type, _gradient_box(color.darkened(0.12), end.darkened(0.12), padding, true))
	else:
		var face := Color(color, 0.04) if outlined else surface_color.lightened(0.09)
		var line := Color(color, 0.72) if outlined else surface_color.lightened(0.23)
		if outlined:
			_text_colors(type, color, color.lightened(0.15))
		set_stylebox("normal", type, _box(face, padding, line, elevation))
		set_stylebox("hover", type, _box(surface_color.lerp(color if outlined else PAPER, 0.15), padding, color if outlined else surface_color.lightened(0.36), elevation))
		set_stylebox("pressed", type, _box(surface_color.darkened(0.12), padding, Color(accent_color, 0.65)))
	set_stylebox("hover_pressed", type, get_stylebox("pressed", type))
	set_stylebox("disabled", type, _box(surface_color.lightened(0.025), padding, surface_color.lightened(0.09)))
	set_stylebox("focus", type, _focus())
	set_constant("align_to_largest_stylebox", type, 1)

func _glyph(shape: String, color: Color, size := 20) -> Texture2D:
	var paths := {"down": "M6 9l4 4 4-4", "right": "M8 5l5 5-5 5", "left": "M12 5l-5 5 5 5", "close": "M6 6l8 8M14 6l-8 8", "menu": "M4 6h12M4 10h12M4 14h12"}
	return _svg('<g transform="scale(%s)"><path d="%s" fill="none" stroke="%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></g>' % [float(size)/20.0, paths[shape], _hex(color)], size, size)

func _check_icon(on: bool, disabled := false, radio := false) -> Texture2D:
	var fill := accent_color if on else surface_color.lightened(0.07)
	var stroke := accent_color if on else surface_color.lightened(0.38)
	if disabled:
		fill = surface_color.lightened(0.08)
		stroke = surface_color.lightened(0.17)
	var foreground := surface_color.lerp(PAPER, 0.35) if disabled else _ink_on(accent_color)
	var body: String
	if radio:
		body = '<circle cx="14" cy="14" r="10" fill="%s" stroke="%s" stroke-width="1.5"/>' % [_hex(fill), _hex(stroke)]
		if on:
			body += '<circle cx="14" cy="14" r="4" fill="%s"/>' % _hex(foreground)
	else:
		body = '<rect x="4" y="4" width="20" height="20" rx="5" fill="%s" stroke="%s" stroke-width="1.5"/>' % [_hex(fill), _hex(stroke)]
		if on:
			body += '<path d="M9 14l3.5 3.5 6.5-7" fill="none" stroke="%s" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>' % _hex(foreground)
	return _svg(body, 28, 28)

func _switch_icon(on: bool, disabled := false, mirrored := false) -> Texture2D:
	var track := accent_color if on else surface_color.lightened(0.22)
	var thumb := PAPER
	if disabled:
		track = surface_color.lightened(0.08)
		thumb = surface_color.lerp(PAPER, 0.32)
	var x := 39 if on != mirrored else 17
	return _svg('<rect x="3" y="3" width="50" height="28" rx="14" fill="%s"/><circle cx="%d" cy="18" r="10" fill="#000" opacity="0.16"/><circle cx="%d" cy="17" r="10" fill="%s"/>' % [_hex(track), x, x, _hex(thumb)], 56, 34)

func _selection_controls() -> void:
	for type in [&"CheckBox", &"CheckButton"]:
		_text_colors(type, PAPER, PAPER)
		for state in ["normal", "pressed", "disabled"]:
			set_stylebox(state, type, _empty(Vector2(4, 5)))
		for state in ["hover", "hover_pressed"]:
			set_stylebox(state, type, _box(Color(PAPER, 0.035), Vector2(4, 5)))
		set_stylebox("focus", type, _focus())
		set_constant("check_v_offset", type, 0)
	for key in ["checkbox_checked_color", "checkbox_unchecked_color"]:
		set_color(key, &"CheckBox", Color.WHITE)
	for key in ["button_checked_color", "button_unchecked_color"]:
		set_color(key, &"CheckButton", Color.WHITE)
	for on in [false, true]:
		for disabled in [false, true]:
			var key := ("checked" if on else "unchecked") + ("_disabled" if disabled else "")
			for type in [&"CheckBox", &"PopupMenu"]:
				set_icon(key, type, _check_icon(on, disabled))
				set_icon("radio_" + key, type, _check_icon(on, disabled, true))
			set_icon(key, &"CheckButton", _switch_icon(on, disabled))
			set_icon(key + "_mirrored", &"CheckButton", _switch_icon(on, disabled, true))

func _menus() -> void:
	var field := surface_color.lightened(0.06)
	var border := surface_color.lightened(0.22)
	_text_colors(&"OptionButton", PAPER, PAPER)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := _box(field, Vector2(14, 11), border)
		box.content_margin_right = 36
		if state == "hover":
			box.bg_color = field.lightened(0.06)
			box.border_color = accent_color.darkened(0.25)
		elif state in ["pressed", "hover_pressed"]:
			box.bg_color = surface_color.darkened(0.08)
			box.border_color = accent_color
		elif state == "disabled":
			box.bg_color = surface_color
		set_stylebox(state, &"OptionButton", box)
		var mirrored := box.duplicate() as StyleBoxFlat
		mirrored.content_margin_left = 36
		mirrored.content_margin_right = 14
		set_stylebox(state + "_mirrored", &"OptionButton", mirrored)
	set_stylebox("focus", &"OptionButton", _focus())
	set_icon("arrow", &"OptionButton", _glyph("down", Color.WHITE))
	set_constant("arrow_margin", &"OptionButton", 12)
	set_constant("modulate_arrow", &"OptionButton", 1)
	_text_colors(&"MenuButton", surface_color.lerp(PAPER, 0.80), PAPER)
	set_stylebox("normal", &"MenuButton", _empty(Vector2(14, 11)))
	set_stylebox("disabled", &"MenuButton", _empty(Vector2(14, 11)))
	set_stylebox("hover", &"MenuButton", _box(surface_color.lightened(0.08), Vector2(14, 11)))
	set_stylebox("pressed", &"MenuButton", _box(Color(accent_color, 0.12), Vector2(14, 11)))
	set_stylebox("hover_pressed", &"MenuButton", get_stylebox("pressed", &"MenuButton"))
	set_stylebox("focus", &"MenuButton", _focus())
	set_stylebox("panel", &"PopupMenu", _box(surface_color.lightened(0.025), Vector2(8, 8), border, elevation + 2))
	set_stylebox("hover", &"PopupMenu", _box(Color(accent_color, 0.15), Vector2(8, 8)))
	for key in ["font_color", "font_hover_color"]:
		set_color(key, &"PopupMenu", PAPER if key == "font_color" else accent_color.lightened(0.2))
	for key in ["font_disabled_color", "font_accelerator_color", "font_separator_color"]:
		set_color(key, &"PopupMenu", surface_color.lerp(PAPER, 0.45))
	set_font_size("font_size", &"PopupMenu", 20)
	set_font_size("font_separator_size", &"PopupMenu", 16)
	set_constant("v_separation", &"PopupMenu", 14)
	set_constant("h_separation", &"PopupMenu", 10)
	set_constant("item_start_padding", &"PopupMenu", 8)
	set_constant("item_end_padding", &"PopupMenu", 8)
	set_icon("submenu", &"PopupMenu", _glyph("right", PAPER))
	set_icon("submenu_mirrored", &"PopupMenu", _glyph("left", PAPER))

func _inputs() -> void:
	for type in [&"LineEdit", &"TextEdit"]:
		set_stylebox("normal", type, _box(surface_color.darkened(0.20), Vector2(14, 12), surface_color.lightened(0.19)))
		set_stylebox("read_only", type, _box(surface_color.darkened(0.08), Vector2(14, 12), surface_color.lightened(0.09)))
		set_stylebox("focus", type, _focus())
		set_color("font_color", type, PAPER)
		set_color("font_placeholder_color", type, surface_color.lerp(PAPER, 0.52))
		set_color("font_selected_color", type, PAPER)
		set_color("caret_color", type, accent_color)
		set_color("selection_color", type, Color(accent_color, 0.25))
		set_constant("caret_width", type, 2)
	set_color("font_uneditable_color", &"LineEdit", surface_color.lerp(PAPER, 0.52))
	set_color("font_readonly_color", &"TextEdit", surface_color.lerp(PAPER, 0.52))
	set_color("current_line_color", &"TextEdit", Color(PAPER, 0.025))
	set_color("background_color", &"TextEdit", Color.TRANSPARENT)
	set_color("search_result_color", &"TextEdit", Color(warning_color, 0.20))
	set_color("search_result_border_color", &"TextEdit", warning_color)
	set_constant("line_spacing", &"TextEdit", 6)
	set_icon("clear", &"LineEdit", _glyph("close", Color.WHITE))
	set_color("clear_button_color", &"LineEdit", surface_color.lerp(PAPER, 0.60))
	set_color("clear_button_color_pressed", &"LineEdit", accent_color)

func _tabs() -> void:
	for type in [&"TabBar", &"TabContainer"]:
		var normal := _box(Color.TRANSPARENT, Vector2(22, 13))
		var selected := _box(Color(accent_color, 0.10), Vector2(22, 13))
		selected.border_width_bottom = 3
		selected.border_color = accent_color
		selected.corner_radius_bottom_left = 0
		selected.corner_radius_bottom_right = 0
		set_stylebox("tab_unselected", type, normal)
		set_stylebox("tab_selected", type, selected)
		set_stylebox("tab_hovered", type, _box(Color(PAPER, 0.045), Vector2(22, 13)))
		set_stylebox("tab_disabled", type, normal)
		set_stylebox("tab_focus", type, _focus())
		set_color("font_selected_color", type, accent_color.lightened(0.15))
		set_color("font_unselected_color", type, surface_color.lerp(PAPER, 0.63))
		set_color("font_hovered_color", type, PAPER)
		set_color("font_disabled_color", type, surface_color.lerp(PAPER, 0.30))
		set_font("font", type, BOLD)
		set_constant("tab_separation", type, 4)
		for key in ["decrement", "decrement_highlight", "increment", "increment_highlight"]:
			set_icon(key, type, _glyph("left" if key.begins_with("decrement") else "right", PAPER))
	set_stylebox("panel", &"TabContainer", _box(surface_color.darkened(0.07), Vector2(20, 20)))
	set_stylebox("tabbar_background", &"TabContainer", _empty())
	set_constant("side_margin", &"TabContainer", 0)
	set_icon("menu", &"TabContainer", _glyph("down", PAPER))
	set_icon("menu_highlight", &"TabContainer", _glyph("down", accent_color))
	set_icon("close", &"TabBar", _glyph("close", PAPER, 16))
	set_stylebox("button_highlight", &"TabBar", _box(Color(PAPER, 0.10), Vector2.ZERO))
	set_stylebox("button_pressed", &"TabBar", _box(Color(accent_color, 0.15), Vector2.ZERO))

func _ranges() -> void:
	var thumb := _svg('<circle cx="14" cy="16" r="9" fill="#000" opacity="0.2"/><circle cx="14" cy="14" r="9" fill="%s"/><circle cx="14" cy="14" r="4" fill="%s"/>' % [_hex(PAPER), _hex(accent_color)], 28, 28)
	var active_thumb := _svg('<circle cx="14" cy="14" r="13" fill="%s" opacity="0.18"/><circle cx="14" cy="14" r="9" fill="%s"/><circle cx="14" cy="14" r="4" fill="%s"/>' % [_hex(accent_color), _hex(PAPER), _hex(accent_color)], 28, 28)
	var disabled_thumb := _svg('<circle cx="14" cy="14" r="8" fill="%s"/>' % _hex(surface_color.lightened(0.34)), 28, 28)
	for type in [&"HSlider", &"VSlider"]:
		var padding := Vector2(0, 3) if type == &"HSlider" else Vector2(3, 0)
		var _track := _box(surface_color.lightened(0.12), padding)
		_track.set_corner_radius_all(3)
		var fill := _box(accent_color, padding)
		fill.set_corner_radius_all(3)
		set_stylebox("slider", type, _track)
		set_stylebox("grabber_area", type, fill)
		set_stylebox("grabber_area_highlight", type, _box(accent_color.lightened(0.12), padding))
		set_icon("grabber", type, thumb)
		set_icon("grabber_highlight", type, active_thumb)
		set_icon("grabber_disabled", type, disabled_thumb)
		set_icon("tick", type, _svg('<circle cx="2" cy="2" r="1.5" fill="%s"/>' % _hex(surface_color.lerp(PAPER, 0.40)), 4, 4))
		set_constant("center_grabber", type, 0)
		set_constant("grabber_offset", type, 0)
	var track := _box(surface_color.lightened(0.10), Vector2(4, 4))
	track.set_corner_radius_all(4)
	set_stylebox("background", &"ProgressBar", track)
	set_stylebox("fill", &"ProgressBar", _gradient_box(accent_color, accent_color.lerp(gradient_color, gradient_strength), Vector2(4, 4), true, 4))
	set_color("font_color", &"ProgressBar", PAPER)
	set_color("font_outline_color", &"ProgressBar", INK)
	set_constant("outline_size", &"ProgressBar", 2)
	set_font_size("font_size", &"ProgressBar", 14)
	# Scrollbars also cover TextEdit and popup overflow.
	for type in [&"HScrollBar", &"VScrollBar"]:
		var padding := Vector2(0, 4) if type == &"HScrollBar" else Vector2(4, 0)
		set_stylebox("scroll", type, _box(Color.TRANSPARENT, padding))
		set_stylebox("scroll_focus", type, _box(Color(accent_color, 0.06), padding))
		for key in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var box := _box(surface_color.lightened(0.25) if key == "grabber" else accent_color, padding)
			box.set_corner_radius_all(4)
			set_stylebox(key, type, box)
		for key in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
			set_icon(key, type, _svg("", 1, 1))

func rebuild() -> void:
	default_font = REGULAR
	default_font_size = 20
	_button(&"Button", surface_color)
	var variations := {"PrimaryButton": accent_color, "SuccessButton": success_color, "WarningButton": warning_color, "DangerButton": danger_color}
	for type in variations:
		set_type_variation(type, &"Button")
		_button(type, variations[type], true)
	set_type_variation(&"OutlineButton", &"Button")
	_button(&"OutlineButton", accent_color, false, true)
	var panel := _box(surface_color, Vector2(24, 24), surface_color.lightened(0.13), elevation + 1)
	panel.set_corner_radius_all(corner_radius + 4)
	for type in [&"Panel", &"PanelContainer", &"PopupPanel", &"TooltipPanel"]:
		set_stylebox("panel", type, panel)
	set_type_variation(&"AccentPanel", &"PanelContainer")
	var accented := panel.duplicate() as StyleBoxFlat
	accented.border_width_top = 2
	accented.border_color = accent_color.darkened(0.30)
	set_stylebox("panel", &"AccentPanel", accented)
	set_color("font_color", &"Label", PAPER)
	set_type_variation(&"TitleLabel", &"Label")
	set_font("font", &"TitleLabel", BLACK)
	set_font_size("font_size", &"TitleLabel", 36)
	set_type_variation(&"LabelSmall", &"Label")
	set_font_size("font_size", &"LabelSmall", 16)
	set_color("font_color", &"LabelSmall", surface_color.lerp(PAPER, 0.60))
	set_type_variation(&"BadgeLabel", &"Label")
	set_font("font", &"BadgeLabel", BOLD)
	set_font_size("font_size", &"BadgeLabel", 14)
	set_color("font_color", &"BadgeLabel", accent_color)
	var badge := _box(Color(accent_color, 0.10), Vector2(12, 5))
	badge.set_corner_radius_all(16)
	set_stylebox("normal", &"BadgeLabel", badge)
	set_color("default_color", &"RichTextLabel", PAPER)
	set_font("bold_font", &"RichTextLabel", BOLD)
	set_color("font_color", &"TooltipLabel", PAPER)
	_selection_controls()
	_menus()
	_inputs()
	_tabs()
	_ranges()
	for type in [&"HBoxContainer", &"VBoxContainer"]:
		set_constant("separation", type, 12)
	for key in ["h_separation", "v_separation"]:
		set_constant(key, &"GridContainer", 12)
	var separator := StyleBoxLine.new()
	separator.color = surface_color.lightened(0.15)
	for type in [&"HSeparator", &"PopupMenu"]:
		set_stylebox("separator", type, separator)
	set_stylebox("labeled_separator_left", &"PopupMenu", separator)
	set_stylebox("labeled_separator_right", &"PopupMenu", separator)
	set_constant("separation", &"HSeparator", 12)
	emit_changed()
