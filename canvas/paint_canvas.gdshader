shader_type canvas_item;

uniform sampler2D mask : filter_linear, repeat_disable;
uniform sampler2D lvl0 : filter_linear;  // most broken
uniform sampler2D lvl1 : filter_linear;
uniform sampler2D lvl2 : filter_linear;
uniform sampler2D lvl3 : filter_linear;
uniform sampler2D lvl4 : filter_linear;
uniform sampler2D lvl5 : filter_linear;
uniform sampler2D lvl6 : filter_linear;
uniform sampler2D lvl7 : filter_linear;  // up to 8 levels; last used one = full painting
uniform float max_level = 4.0;           // number of levels - 1
uniform float step_value = 0.25;         // brightness added per hit, 0..1
uniform float blur = 1.5;                // in mask pixels

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
	// 1. little blur, done ONCE per pixel
	vec2 o = blur / vec2(textureSize(mask, 0));
	float b = texture(mask, UV).r;
	b += texture(mask, UV + vec2(o.x, 0.0)).r;
	b += texture(mask, UV - vec2(o.x, 0.0)).r;
	b += texture(mask, UV + vec2(0.0, o.y)).r;
	b += texture(mask, UV - vec2(0.0, o.y)).r;
	b /= 5.0;

	// 2. brightness -> position on the ladder (0 = most broken, max_level = full)
	float q = max_level - clamp(b / step_value, 0.0, max_level);

	// 3. only the two neighbouring levels are read and mixed
	int i = int(floor(q));
	int j = min(i + 1, int(max_level));
	float f = q - float(i);
	vec4 a = pick(i, UV);
	vec4 c = pick(j, UV);
	a.rgb *= a.a;
	c.rgb *= c.a;
	vec4 m = mix(a, c, f);
	COLOR = vec4(m.a > 0.0 ? m.rgb / m.a : vec3(0.0), m.a);
}
