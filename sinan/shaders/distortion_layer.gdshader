shader_type canvas_item;
// One detail level of a painting layer. Fades out where the shared damage mask
// rises past `threshold`, with a soft, slightly torn edge.

uniform sampler2D mask : filter_linear, repeat_disable;
uniform float threshold = 0.5;   // > 1.0 = never fades (bottom layer)
uniform float softness = 0.06;   // width of the fade, in mask units
uniform float edge_noise = 0.05; // how torn the boundary looks
uniform float noise_scale = 40.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float m = texture(mask, UV).r;
	// Two octaves of noise roughen the boundary; only where there is damage.
	float n = vnoise(UV * noise_scale) * 0.65 + vnoise(UV * noise_scale * 2.7) * 0.35;
	m += (n - 0.5) * edge_noise * step(0.004, m);
	float keep = 1.0 - smoothstep(threshold - softness, threshold + softness, m);
	COLOR.a *= keep;
}
