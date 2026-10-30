shader_type canvas_item;
global uniform vec2  veil_center;
global uniform vec2  veil_viewport;
global uniform float veil_reach;
global uniform float veil_amount;
uniform float dim_strength : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec2  sp     = SCREEN_UV * veil_viewport;
	float inside = 1.0 - smoothstep(veil_reach - 20.0, veil_reach + 20.0, distance(sp, veil_center));
	COLOR.rgb *= 1.0 - inside * veil_amount * dim_strength;
}
