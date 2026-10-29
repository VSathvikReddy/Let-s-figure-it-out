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
Give the attack an Area2D with a CollisionShape2D (circle or rectangle) or a
CollisionPolygon2D (any shape), then:

```gdscript
Painting.paint($MyArea, 1.0)          # break under the area
Painting.paint($MyArea, -1.0)         # repair
Painting.paint($MyArea, 1.0, point)   # same, with the area moved to `point`
```
`1.0` = one detail level (e.g. 60 -> 40). Small amounts like `2.0 * delta` work too.

## How it works (4 files)
- `painting.gd`: passes each shape of the area to every layer (sky, hill, village).
- `painting_layer.gd`: keeps a "mask" image (0 = perfect, 1 = broken) and
  changes the mask pixels that are inside the shape.
- `painting_layer.gdshader`: on the full-painting sprite only (the other sprites just lend
  their pictures). Per pixel it blurs the mask, finds the two detail levels the damage falls
  between and mixes them - so one layer is one draw, with smooth fades between levels.
- `demo/wand.gd` (right mouse): hold to grow an arc towards the mouse (wider = reaches
  further), release to swing; the fan shape repairs one level, using a CollisionPolygon2D.
- `demo/demo_player.gd`: WASD / arrows in every direction (up and down too), can walk right
  up to the edge of the painting, repairs with its `Brush` Area2D at the mouse (left mouse).
- `painting/fit_camera.gd` (on the player's Camera2D): the camera follows the player while the
  middle of the screen is inside its `camera_area`; there it stops (Camera2D limits) and the
  player walks on to the edge of the screen. The sky layer
  has `scroll_scale = (0, 0)`; this script scales it to cover the whole screen, and zooms in
  just enough that the hill and village strips are always wider than the view. Result: the
  screen never shows anything outside the painting, in any window shape.
