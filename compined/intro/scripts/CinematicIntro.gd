## CinematicIntro.gd
## Orchestrates the 7-scene cinematic backstory for PAINTSCAPES.
## All scene content is defined in _build_scenes() — edit there to change narrative.
## When it ends (or Skip / Esc) the game starts at Painting I.
extends Control

const GameState := preload("res://compined/intro/scripts/GameState.gd")

# ── Node references ──────────────────────────────────────────────────────────
@onready var bg_image      : TextureRect        = $BgImage
@onready var overlay_image : TextureRect        = $OverlayImage
@onready var portrait_image: TextureRect        = $PortraitImage
@onready var narration_box : Control            = $NarrationBox
@onready var speaker_label : Label              = $NarrationBox/VBoxNarration/SpeakerLabel
@onready var text_label    : RichTextLabel      = $NarrationBox/VBoxNarration/TextLabel
@onready var btn_next      : Button             = $NarrationBox/VBoxNarration/HBoxButtons/BtnNext
@onready var btn_back      : Button             = $NarrationBox/VBoxNarration/HBoxButtons/BtnBack
@onready var btn_skip      : Button             = $SkipBtn
@onready var fade_rect     : ColorRect          = $FadeRect
@onready var title_screen  : Control            = $TitleScreen
@onready var title_label   : Label              = $TitleScreen/TitleLabel
@onready var tagline_label : Label              = $TitleScreen/TaglineLabel
@onready var music_player  : AudioStreamPlayer  = $MusicPlayer

# ── State ─────────────────────────────────────────────────────────────────────
var _scenes       : Array[Dictionary] = []
var _scene_idx    : int   = 0
var _line_idx     : int   = 0
var _typing       : bool  = false
var _tween        : Tween
var _cam_tween    : Tween
var _effect_tween : Tween
var _type_timer   : float = 0.0
var _full_text    : String = ""
var _displayed    : int   = 0

const CHAR_DELAY  : float = 0.035   # seconds between typewriter characters
## Extra zoom on every background so the camera pans and zooms never show its
## edges (1.12 = 12% bigger than the screen).
const OVERSCAN    : float = 1.12
const SKIP_DELAY  : float = 0.004   # fast-skip speed when user holds Next

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_scenes()
	btn_next.pressed.connect(_on_next)
	btn_back.pressed.connect(_on_back)
	btn_skip.pressed.connect(_on_skip_intro)
	title_screen.visible = false
	fade_rect.color      = Color(0, 0, 0, 1)
	_load_scene(0)
	_fade_in()

func _process(delta: float) -> void:
	if not _typing:
		return
	_type_timer += delta
	if _type_timer >= CHAR_DELAY:
		_type_timer = 0.0
		_displayed += 1
		text_label.text = _full_text.left(_displayed)
		if _displayed >= _full_text.length():
			_typing = false
			btn_next.text = "NEXT ▶"

# ── Scene building ─────────────────────────────────────────────────────────────
func _build_scenes() -> void:
	_scenes = [
		# Scene 1 — The Restorer
		{
			"bg":      "res://compined/intro/art/studio_scene.png",
			"overlay": "",
			"lines":   [
				"My name is Leonardo.",
				"To the world, I was an art restorer.",
				"I dedicated my life to preserving the beauty of what others had created."
			],
			"speaker": "LEONARDO",
			"cam_start_offset": Vector2(40, 0),
			"cam_end_offset":   Vector2(-40, 0),
			"cam_start_zoom":   1.08,
			"cam_end_zoom":     1.0,
			"cam_duration":     8.0,
			"effect":           "dust",
			"effect_duration":  8.0,
		},
		# Scene 2 — The Gamma-Wave Blast
		{
			"bg":      "res://compined/intro/art/gamma blast.jpg",
			"overlay": "",
			"lines":   [
				"But one day, everything changed.",
				"A wave of unimaginable energy tore through my world.",
				"What followed defied every law of science."
			],
			"speaker": "GOD",
			"cam_start_offset": Vector2(0, 0),
			"cam_end_offset":   Vector2(0, 0),
			"cam_start_zoom":   1.0,
			"cam_end_zoom":     1.06,
			"cam_duration":     5.0,
			"effect":           "gamma_wave",
			"effect_duration":  3.5,
		},
		# Scene 3 — Entropy Unbound (painting transformation)
		{
			"bg":      "res://compined/intro/art/painting_original.jpg",
			"overlay": "res://compined/intro/art/painting_distorted.png",
			"lines":   [
				"The balance of the universe had been broken.",
				"Entropy no longer obeyed the rules of nature.",
				"Beauty, complexity, and detail began to disappear."
			],
			"speaker": "GOD",
			"cam_start_offset": Vector2(-20, 10),
			"cam_end_offset":   Vector2(20, -10),
			"cam_start_zoom":   1.05,
			"cam_end_zoom":     1.0,
			"cam_duration":     9.0,
			"effect":           "lowpoly_corrupt",
			"effect_duration":  9.0,
		},
		# Scene 4 — Entropy Awakens
		{
			"bg":      "res://compined/intro/art/enemies_entering.png",
			"overlay": "",
			"lines":   [
				"But the wave had awakened something far more terrifying.",
				"Entropy itself had taken on life.",
				"The objects within the paintings were no longer lifeless.",
				"And they were no longer friendly."
			],
			"speaker": "GOD",
			"cam_start_offset": Vector2(0, 30),
			"cam_end_offset":   Vector2(0, -10),
			"cam_start_zoom":   1.1,
			"cam_end_zoom":     1.0,
			"cam_duration":     10.0,
			"effect":           "dust",
			"effect_duration":  10.0,
		},
		# Scene 5 — Trapped Inside Art
		{
			"bg":      "res://compined/intro/art/Portal Painting in the Grand Hall.png",
			"overlay": "",
			"lines":   [
				"I was pulled into the very paintings I had sworn to restore.",
				"My greatest works had become my prison.",
				"Every world was broken.  Every creation had turned against me."
			],
			"speaker": "LEONARDO",
			"cam_start_offset": Vector2(0, -20),
			"cam_end_offset":   Vector2(0, 20),
			"cam_start_zoom":   0.95,
			"cam_end_zoom":     1.05,
			"cam_duration":     8.0,
			"effect":           "gamma_wave",
			"effect_duration":  2.5,
		},
		# Scene 6 — The Only Way Out
		{
			"bg":      "res://compined/intro/art/painting_distorted.png",
			"overlay": "res://compined/intro/art/painting_original.jpg",
			"lines":   [
				"Yet there was still hope.",
				"If the paintings could be restored, perhaps reality could be restored with them.",
				"To return home, I would have to bring every masterpiece back to life."
			],
			"speaker": "GOD",
			"cam_start_offset": Vector2(30, 0),
			"cam_end_offset":   Vector2(-30, 0),
			"cam_start_zoom":   1.0,
			"cam_end_zoom":     1.05,
			"cam_duration":     9.0,
			"effect":           "lowpoly_restore",
			"effect_duration":  9.0,
		},
		# Scene 7 — The Journey Begins
		{
			"bg":      "res://compined/intro/art/character_entering.jpg",
			"overlay": "",
			"lines":   [
				"And so, my journey began.",
				"Through worlds of broken art...",
				"Against the very force that had brought them to life...",
				"Until every last painting was restored."
			],
			"speaker": "GOD",
			"cam_start_offset": Vector2(50, 0),
			"cam_end_offset":   Vector2(0, 0),
			"cam_start_zoom":   1.15,
			"cam_end_zoom":     1.0,
			"cam_duration":     12.0,
			"effect":           "dust",
			"effect_duration":  12.0,
		},
	]

# ── Scene loading ──────────────────────────────────────────────────────────────
func _load_scene(idx: int) -> void:
	if idx < 0 or idx >= _scenes.size():
		return
	_scene_idx = idx
	_line_idx  = 0
	var s: Dictionary = _scenes[idx]

	# Background
	_set_texture(bg_image, s.get("bg", ""))

	# Overlay (used for transition effects)
	var ov_path: String = s.get("overlay", "")
	if ov_path != "":
		_set_texture(overlay_image, ov_path)
		overlay_image.visible = true
		overlay_image.modulate.a = 0.0
	else:
		overlay_image.visible = false

	# Speaker + portrait
	var sp: String = s.get("speaker", "")
	speaker_label.text    = sp
	speaker_label.visible = sp != ""
	_update_portrait(sp)
	# Camera pan/zoom
	_start_camera_animation(s)

	# Effect
	_start_effect(s)

	# First narration line
	_show_line()

func _set_texture(rect: TextureRect, path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		rect.texture = null
		return
	rect.texture = load(path)

## Maps speaker name → portrait image path
## GOD      → god.png (shown on the right when God narrates)
## LEONARDO → main character.png (shown when Leonardo speaks)
func _update_portrait(speaker: String) -> void:
	match speaker.to_upper():
		"GOD":
			_set_texture(portrait_image, "res://compined/intro/art/god_nobg.png")
		"LEONARDO":
			# Crop to just the hooded face (passport-style)
			var atlas := AtlasTexture.new()
			atlas.atlas  = load("res://compined/intro/art/main character.png")
			atlas.region = Rect2(525, 185, 440, 440)
			portrait_image.texture = atlas
		_:
			portrait_image.texture = null

# ── Camera animation (pan + zoom via pivot/scale on bg_image) ─────────────────
func _start_camera_animation(s: Dictionary) -> void:
	if _cam_tween:
		_cam_tween.kill()
	var start_offset : Vector2 = s.get("cam_start_offset", Vector2.ZERO)
	var end_offset   : Vector2 = s.get("cam_end_offset",   Vector2.ZERO)
	var start_zoom   : float   = s.get("cam_start_zoom",   1.0) * OVERSCAN
	var end_zoom     : float   = s.get("cam_end_zoom",     1.0) * OVERSCAN
	var duration     : float   = s.get("cam_duration",     6.0)

	bg_image.pivot_offset = bg_image.size * 0.5
	bg_image.position     = start_offset
	bg_image.scale        = Vector2(start_zoom, start_zoom)

	_cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.set_parallel(true)
	_cam_tween.tween_property(bg_image, "position", end_offset,           duration)
	_cam_tween.tween_property(bg_image, "scale",    Vector2(end_zoom, end_zoom), duration)

# ── Visual effects ─────────────────────────────────────────────────────────────
func _start_effect(s: Dictionary) -> void:
	if _effect_tween:
		_effect_tween.kill()
	var effect   : String = s.get("effect",          "none")
	var duration : float  = s.get("effect_duration", 3.0)

	match effect:
		"gamma_wave":
			_play_gamma_wave(duration)
		"lowpoly_corrupt":
			_play_lowpoly_transition(true, duration)
		"lowpoly_restore":
			_play_lowpoly_transition(false, duration)
		"dust":
			_play_dust(duration)

func _play_gamma_wave(duration: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://compined/intro/shaders/gamma_wave.gdshader")
	mat.set_shader_parameter("wave_progress", 0.0)
	bg_image.material = mat

	_effect_tween = create_tween()
	# Flash in then wave expands
	_effect_tween.tween_property(mat, "shader_parameter/wave_progress", 1.0, duration).set_trans(Tween.TRANS_EXPO)
	_effect_tween.tween_callback(func(): bg_image.material = null)

func _play_lowpoly_transition(corrupt: bool, duration: float) -> void:
	# overlay_image blends in (corrupt) or out (restore)
	if not overlay_image.visible:
		overlay_image.visible = true
		overlay_image.modulate.a = 0.0

	# Apply corruption shader to base image
	var mat := ShaderMaterial.new()
	mat.shader = load("res://compined/intro/shaders/lowpoly_transition.gdshader")
	mat.set_shader_parameter("progress", 0.0)
	bg_image.material = mat

	_effect_tween = create_tween().set_parallel(true)
	if corrupt:
		# 0→1 = detail fades to low-poly, overlay (distorted) fades in
		_effect_tween.tween_property(mat, "shader_parameter/progress", 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_effect_tween.tween_property(overlay_image, "modulate:a", 1.0, duration * 0.8).set_delay(duration * 0.2)
	else:
		# Restore: start already distorted, fade to original
		mat.set_shader_parameter("progress", 1.0)
		overlay_image.modulate.a = 0.0
		_effect_tween.tween_property(mat, "shader_parameter/progress", 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_effect_tween.tween_property(overlay_image, "modulate:a", 0.8, duration * 0.5).set_delay(duration * 0.1)

func _play_dust(duration: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://compined/intro/shaders/dust_particles.gdshader")
	bg_image.material = mat
	# Shader is time-driven — just let it run

# ── Narration / typewriter ─────────────────────────────────────────────────────
func _show_line() -> void:
	var s     : Dictionary = _scenes[_scene_idx]
	var lines : Array      = s.get("lines", [])
	if lines.is_empty():
		return

	_full_text  = lines[_line_idx]
	_displayed  = 0
	_typing     = true
	text_label.text = ""
	btn_next.text   = "▶"   # indicates still typing
	btn_back.disabled = (_scene_idx == 0 and _line_idx == 0)

func _on_next() -> void:
	if _typing:
		# Skip typing — show full text instantly
		_typing = false
		text_label.text = _full_text
		btn_next.text   = "NEXT ▶"
		return
	_advance_line()

func _on_back() -> void:
	if _line_idx > 0:
		_line_idx -= 1
		_show_line()
	elif _scene_idx > 0:
		_transition_to_scene(_scene_idx - 1)

func _advance_line() -> void:
	var s     : Dictionary = _scenes[_scene_idx]
	var lines : Array      = s.get("lines", [])
	if _line_idx < lines.size() - 1:
		_line_idx += 1
		_show_line()
	else:
		_next_scene()

func _next_scene() -> void:
	if _scene_idx < _scenes.size() - 1:
		_transition_to_scene(_scene_idx + 1)
	else:
		_show_title_screen()

func _transition_to_scene(idx: int) -> void:
	# Short fade to black, swap scene, fade in
	_typing = false
	var t := create_tween()
	t.tween_property(fade_rect, "color:a", 1.0, 0.5)
	t.tween_callback(func():
		_load_scene(idx)
		_fade_in()
	)

func _fade_in() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(fade_rect, "color:a", 0.0, 0.7)

func _on_skip_intro() -> void:
	_typing = false
	_transition_to_game()

func _transition_to_game() -> void:
	var t := create_tween()
	t.tween_property(fade_rect, "color:a", 1.0, 0.8)
	t.tween_callback(func() -> void: GameState.go_to_level1())

# ── Title screen (shown after scene 7) ────────────────────────────────────────
func _show_title_screen() -> void:
	var fade := create_tween()
	fade.tween_property(fade_rect, "color:a", 1.0, 1.0)
	fade.tween_callback(_display_title)

func _display_title() -> void:
	title_screen.visible  = true
	narration_box.visible = false
	btn_skip.visible      = false
	title_label.modulate.a    = 0.0
	tagline_label.modulate.a  = 0.0
	# Ensure fade is black at start
	fade_rect.color = Color(0, 0, 0, 1)

	var t := create_tween()
	# Fade from black into the title screen
	t.tween_property(fade_rect, "color:a", 0.0, 0.8)
	# Reveal PAINTSCAPES title
	t.tween_property(title_label,   "modulate:a", 1.0, 1.5)
	# Reveal tagline
	t.tween_property(tagline_label, "modulate:a", 1.0, 1.2)
	# Hold 3 seconds
	t.tween_interval(3.0)
	# Fade to black and load level
	t.tween_property(fade_rect, "color:a", 1.0, 1.2)
	t.tween_callback(func() -> void: GameState.go_to_level1())

# ── Input shortcuts ────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		_on_next()
	if event.is_action_pressed("ui_cancel"):
		_on_skip_intro()
