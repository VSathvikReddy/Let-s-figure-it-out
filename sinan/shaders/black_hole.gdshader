shader_type canvas_item;
// Glassy black hole: refracts whatever is already drawn behind it, swirling it
// and pulling it toward the centre, with chromatic fringing, a dark core and a
// bright event-horizon rim. Put it on a Sprite2D (any texture; UV 0..1 is used).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 0.0;  // animate 0 -> 1 -> 0
uniform float swirl = 2.5;                            // radians of twist at the core
uniform float pinch = 1.6;                            // how hard the image is pulled in
uniform float core_size : hint_range(0.0, 0.5) = 0.22; // core radius (fraction of the sprite radius)
uniform float aberration = 0.02;                      // colour fringing
uniform vec4 rim_color : source_color = vec4(0.75, 0.55, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.02, 0.0, 0.05, 1.0);

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;  // 0 centre .. 1 edge
	if (r > 1.0) {
		discard;
	}
	// sprite UV -> screen UV scale (assumes the sprite is not rotated)
	vec2 to_screen = vec2(dFdx(SCREEN_UV.x) / dFdx(UV.x), dFdy(SCREEN_UV.y) / dFdy(UV.y));

	float fall = 1.0 - smoothstep(0.0, 1.0, r);
	float pull = strength * fall;
	float ang = swirl * pull * pull;
	float s = sin(ang);
	float co = cos(ang);
	vec2 rc = vec2(c.x * co - c.y * s, c.x * s + c.y * co);
	vec2 src = rc * (1.0 + pinch * pull);  // sample further out = image squeezed toward the centre
	vec2 base = SCREEN_UV + (src - c) * to_screen;

	vec2 fringe = normalize(c + vec2(1e-5)) * aberration * strength * fall * to_screen * 4.0;
	vec3 col = vec3(
		texture(screen_tex, base + fringe).r,
		texture(screen_tex, base).g,
		texture(screen_tex, base - fringe).b);

	// glassy sheen toward the lens edge
	col += vec3(1.0) * pow(r, 8.0) * 0.3 * strength;

	// event horizon
	float core_r = core_size * strength;
	float core = 1.0 - smoothstep(core_r * 0.8, core_r, r);
	float rim = exp(-pow((r - core_r) / 0.035, 2.0)) * strength;
	col = mix(col, core_color.rgb, core);
	col += rim_color.rgb * rim * 1.6;

	float edge = 1.0 - smoothstep(0.82, 1.0, r);
	COLOR = vec4(col, edge);
}
