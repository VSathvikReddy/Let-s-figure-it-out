shader_type canvas_item;
// Put on the FULL painting sprite of a layer (painting_layer.gd does that).
// Only this one sprite is drawn. At every pixel it reads the damage mask,
// finds the two detail levels the damage falls between, and mixes them.

uniform sampler2D mask : filter_linear, repeat_disable; // damage: 0 = perfect, 1 = broken
uniform sampler2D lvl0 : filter_linear;  // most broken
uniform sampler2D lvl1 : filter_linear;
uniform sampler2D lvl2 : filter_linear;
uniform sampler2D lvl3 : filter_linear;
uniform sampler2D lvl4 : filter_linear;
uniform sampler2D lvl5 : filter_linear;
uniform sampler2D lvl6 : filter_linear;
uniform sampler2D lvl7 : filter_linear;  // up to 8 levels; the last one used = full painting
uniform float max_level = 4.0;           // number of levels - 1
uniform float blur = 6.0;                // how far (in mask pixels) the edges are smeared

vec4 pick(int i, vec2 uv) {
	if (i <= 0) return texture(lvl0, uv);
	if (i == 1) return texture(lvl1, uv);
	if (i == 2) return texture(lvl2, uv);
	if (i == 3) return texture(lvl3, uv);
	if (i == 4) return texture(lvl4, uv);
	if (i == 5) return texture(lvl5, uv);
	if (i == 6) return texture(lvl6, uv);
	return texture(lvl7, uv);
}

void fragment() {
	// 1. Blur: instead of reading the damage at one spot, read a 5x5 grid of
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

	// 2. damage -> position on the ladder (0 = most broken, max_level = full)
	float q = max_level * (1.0 - clamp(damage, 0.0, 1.0));

	// 3. only the two neighbouring levels are read and mixed
	int i = int(floor(q));
	int j = min(i + 1, int(max_level));
	float f = q - float(i);
	vec4 a = pick(i, UV);
	vec4 c = pick(j, UV);
	// mix with premultiplied alpha, so see-through edges don't turn dark
	a.rgb *= a.a;
	c.rgb *= c.a;
	vec4 m = mix(a, c, f);
	COLOR = vec4(m.a > 0.0 ? m.rgb / m.a : vec3(0.0), m.a);
}
