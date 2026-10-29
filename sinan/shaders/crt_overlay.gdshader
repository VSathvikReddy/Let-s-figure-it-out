shader_type canvas_item;
// Old-monitor look laid over a UI: dark scanlines, a soft vignette and a faint
// flicker. It only darkens, so whatever is underneath shows through.

uniform float line_strength = 0.16;  // how dark the scanlines are
uniform float line_spacing = 3.0;    // screen pixels per scanline
uniform float vignette = 0.6;        // how dark the corners get
uniform float flicker = 0.02;

void fragment() {
	float scan = 0.5 + 0.5 * sin(FRAGCOORD.y / line_spacing * 6.2832);
	float a = scan * line_strength;
	vec2 d = (UV - 0.5) * vec2(1.0, 0.85);
	a += smoothstep(0.3, 0.8, length(d)) * vignette;
	a += flicker * (0.5 + 0.5 * sin(TIME * 47.0));
	COLOR = vec4(0.0, 0.0, 0.0, clamp(a, 0.0, 1.0));
}
