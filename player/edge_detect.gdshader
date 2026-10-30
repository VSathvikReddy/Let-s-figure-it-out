shader_type canvas_item;

// Screen texture: what has been drawn so far
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

global uniform vec2  veil_center;
global uniform vec2  veil_viewport;
global uniform float veil_reach;
global uniform float veil_amount;

uniform float thickness : hint_range(0.5, 4.0) = 1.5;    // line width in px
uniform float threshold : hint_range(0.0, 1.0) = 0.000001;   // lower = more edges
uniform float softness  : hint_range(0.01, 0.5) = 0.01;   // edge falloff
uniform float strength  : hint_range(0.0, 1.0) = 1.0;
uniform float scene_keep : hint_range(0.0, 1.0) = 0.0;   // 1 = keep scene, 0 = outlines only
uniform vec3  edge_color : source_color = vec3(1.0, 1.0, 1.0);

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float sample_lum(vec2 uv) {
	return lum(texture(screen_tex, uv).rgb);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * thickness;
	vec2 uv = SCREEN_UV;

	// 3x3 neighbourhood
	float tl = sample_lum(uv + vec2(-px.x, -px.y));
	float tc = sample_lum(uv + vec2( 0.0,  -px.y));
	float tr = sample_lum(uv + vec2( px.x, -px.y));
	float ml = sample_lum(uv + vec2(-px.x,  0.0));
	float mr = sample_lum(uv + vec2( px.x,  0.0));
	float bl = sample_lum(uv + vec2(-px.x,  px.y));
	float bc = sample_lum(uv + vec2( 0.0,   px.y));
	float br = sample_lum(uv + vec2( px.x,  px.y));

	// Sobel
	float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
	float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
	float edge = smoothstep(threshold, threshold + softness, length(vec2(gx, gy)));

	// Only inside the veil, same mask as the hide/dim shaders
	vec2  sp   = SCREEN_UV * veil_viewport;
	float mask = (1.0 - smoothstep(veil_reach - 20.0, veil_reach + 20.0, distance(sp, veil_center))) * veil_amount;

	vec3 scene = texture(screen_tex, uv).rgb;
	vec3 base  = mix(scene, scene * scene_keep, mask);
	COLOR = vec4(mix(base, edge_color, edge * strength * mask), 1.0);
}
