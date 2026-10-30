// Mixes the painting's pictures using the mask from painting.gd.
// Mask black = crudest picture (the last one), mask white = most detailed (lvl0).
shader_type canvas_item;

uniform sampler2D mask : filter_linear, repeat_disable;
uniform sampler2D lvl0 : filter_linear;  // most detailed picture
uniform sampler2D lvl1 : filter_linear;
uniform sampler2D lvl2 : filter_linear;
uniform sampler2D lvl3 : filter_linear;
uniform sampler2D lvl4 : filter_linear;
uniform sampler2D lvl5 : filter_linear;
uniform sampler2D lvl6 : filter_linear;
uniform sampler2D lvl7 : filter_linear;  // up to 8 pictures
uniform float max_level = 4.0;           // number of pictures - 1
uniform float step_value = 0.25;         // how much one hit adds to the mask (0..1)
uniform float blur = 1.5;                // in mask squares

vec4 picture(int i, vec2 uv) {
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
	// 1. read the mask with a small blur (this pixel + its 4 neighbours)
	vec2 offset = blur / vec2(textureSize(mask, 0));
	float brightness = texture(mask, UV).r;
	brightness += texture(mask, UV + vec2(offset.x, 0.0)).r;
	brightness += texture(mask, UV - vec2(offset.x, 0.0)).r;
	brightness += texture(mask, UV + vec2(0.0, offset.y)).r;
	brightness += texture(mask, UV - vec2(0.0, offset.y)).r;
	brightness /= 5.0;

	// 2. brightness -> which picture (max_level = crudest, 0 = most detailed)
	float level = max_level - clamp(brightness / step_value, 0.0, max_level);

	// 3. mix the two pictures next to that level
	int lower = int(floor(level));
	int upper = min(lower + 1, int(max_level));
	float amount = level - float(lower);
	vec4 a = picture(lower, UV);
	vec4 b = picture(upper, UV);
	a.rgb *= a.a;   // premultiply so transparent edges mix cleanly
	b.rgb *= b.a;
	vec4 mixed = mix(a, b, amount);
	COLOR = vec4(mixed.a > 0.0 ? mixed.rgb / mixed.a : vec3(0.0), mixed.a);
}
