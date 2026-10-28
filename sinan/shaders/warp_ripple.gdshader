shader_type canvas_item;
// Subtle distortion ripple: a single ring wave that bends whatever is behind it
// as it travels outward. Put it on a Sprite2D (any texture; UV 0..1 is used).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float progress : hint_range(0.0, 1.0) = 0.0;  // ring position, 0 centre .. 1 edge
uniform float amplitude = 0.04;                       // how far the image bends (fraction of the sprite)
uniform float ring_width = 0.22;                      // thickness of the wave
uniform float aberration = 0.25;                      // slight colour split inside the wave

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float band = (r - progress) / ring_width;
	if (r > 1.0 || abs(band) > 1.0) {
		discard;
	}
	vec2 to_screen = vec2(dFdx(SCREEN_UV.x) / dFdx(UV.x), dFdy(SCREEN_UV.y) / dFdy(UV.y));
	vec2 dir = normalize(c + vec2(1e-5));
	float wave = sin(band * 3.14159) * (1.0 - abs(band));  // smooth bump across the band
	float fade = 1.0 - progress;
	vec2 offset = dir * wave * amplitude * fade * to_screen;
	vec3 col = vec3(
		texture(screen_tex, SCREEN_UV - offset * (1.0 + aberration)).r,
		texture(screen_tex, SCREEN_UV - offset).g,
		texture(screen_tex, SCREEN_UV - offset * (1.0 - aberration)).b);
	COLOR = vec4(col, (1.0 - abs(band)) * smoothstep(1.0, 0.85, r));
}
