## SceneData.gd
## Data-driven resource for a single cinematic scene.
## Edit the exported fields in the Godot Inspector — no scripting required.
class_name SceneData
extends Resource

## Path to the main background image (full-screen)
@export_file("*.png","*.jpg","*.webp") var background_image: String = ""

## Optional second image used for layered / transition effects
@export_file("*.png","*.jpg","*.webp") var overlay_image: String = ""

## Narration lines shown one at a time in the text panel
@export var narration_lines: Array[String] = []

## Optional speaker name shown above text (leave empty for narrator voice)
@export var speaker_name: String = ""

## How many seconds to linger on this scene after all lines are shown
## Set to 0 for manual progression only
@export var auto_advance_delay: float = 0.0

## Camera pan / zoom animation data
@export var camera_start_offset: Vector2 = Vector2.ZERO
@export var camera_end_offset: Vector2  = Vector2.ZERO
@export var camera_start_zoom: float    = 1.0
@export var camera_end_zoom: float      = 1.0
@export var camera_duration: float      = 6.0

## Special effect to play on this scene
## Options: "none", "gamma_wave", "lowpoly_corrupt", "lowpoly_restore", "dust"
@export var effect_type: String = "none"

## How long the effect animation runs (seconds)
@export var effect_duration: float = 3.0

## Music / audio file path (leave empty to keep previous track)
@export_file("*.ogg","*.wav","*.mp3") var music_path: String = ""
