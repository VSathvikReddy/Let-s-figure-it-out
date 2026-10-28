shader_type canvas_item;
// Put on one detail-level sprite. It hides the sprite wherever the
// damage mask is bigger than `hide_above`.

uniform sampler2D mask : filter_linear; // damage: 0 = perfect, 1 = broken
uniform float hide_above = 0.5;
uniform float blur = 6.0;       // how far (in mask pixels) the edge is smeared
uniform float softness = 0.15;  // how slowly a sprite fades out around hide_above

void fragment() {
	// Blur: instead of reading the damage at one spot, read a 5x5 grid of
	// spots around it and take the average. Near a shape's edge the grid
	// catches both damaged and clean pixels, so the edge becomes a gradient.
	vec2 step_size = blur / vec2(textureSize(mask, 0)) / 2.0;
	float damage = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			damage += texture(mask, UV + vec2(float(x), float(y)) * step_size).r;
		}
	}
	damage /= 25.0;

	// smoothstep fades the sprite out gradually instead of a hard cut
	COLOR.a *= 1.0 - smoothstep(hide_above - softness, hide_above + softness, damage);
}
