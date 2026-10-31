// ARTISTE - Ambient dust / entropy particle shader for background panels
shader_type canvas_item;

uniform float time_offset : hint_range(0.0, 100.0) = 0.0;
uniform vec4 particle_color : source_color = vec4(0.7, 0.6, 0.9, 0.6);

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME + time_offset;

	// Sample underlying texture
	vec4 base = texture(TEXTURE, uv);

	// Generate drifting dust motes
	float glow = 0.0;
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		vec2 seed = vec2(fi * 0.3791, fi * 0.6173);
		// Random base position
		vec2 pos = vec2(hash21(seed), hash21(seed + vec2(1.0, 0.0)));
		// Drift upward, wiggle sideways
		float speed  = 0.018 + hash21(seed + vec2(2.0, 0.0)) * 0.025;
		float wiggle = sin(t * 0.8 + fi * 1.3) * 0.018;
		pos.y = fract(pos.y - t * speed);
		pos.x = fract(pos.x + wiggle);
		float d    = distance(uv, pos);
		float size = 0.004 + hash21(seed + vec2(3.0, 0.0)) * 0.006;
		glow += smoothstep(size, 0.0, d);
	}

	vec4 result = base + particle_color * clamp(glow, 0.0, 1.0) * 0.45;
	COLOR = result;
}
