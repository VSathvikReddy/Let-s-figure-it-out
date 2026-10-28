# sinan_new - painting level (learning version)

Fully independent: nothing here uses files from `sinan/` or the project's
input map. Copy this folder anywhere under `res://` (then fix the one
`preload` path in `painting_layer.gd`).

## Setup in the scene
1. `Painting` node (Node2D) -> script `painting/painting.gd`
2. Each layer (Parallax2D: sky, hill, village) -> script `painting/painting_layer.gd`
3. Inside each layer: Sprite2Ds from most broken to full painting
   (e.g. 20, 40, 60, 80, 100). A layer with one sprite can't be damaged.

## Using it from any attack
Give the attack an Area2D with a CollisionShape2D (circle or rectangle), then:

```gdscript
Painting.paint($MyArea, 1.0)          # break under the area
Painting.paint($MyArea, -1.0)         # repair
Painting.paint($MyArea, 1.0, point)   # same, with the area moved to `point`
```

## How it works (4 files)
- `painting.gd`: finds the front layer with paint at the spot, passes it each shape.
- `painting_layer.gd`: keeps a "mask" image (0 = perfect, 1 = broken) and
  changes the mask pixels that are inside the shape.
- `painting_layer.gdshader`: hides a detail sprite where the mask is too high.
- `demo/demo_player.gd`: WASD / arrows in every direction (up and down too), stays inside
  its `play_area`, paints with its `Brush` Area2D at the mouse.
- `painting/fit_camera.gd` (on the player's Camera2D): the camera sits on the middle of the
  body, with no limits and no smoothing, so the player is always in the centre. The sky layer
  has `scroll_scale = (0, 0)`; this script scales it to cover the whole screen, and zooms in
  just enough that the hill and village strips are always wider than the view. Result: the
  screen never shows anything outside the painting, in any window shape.
