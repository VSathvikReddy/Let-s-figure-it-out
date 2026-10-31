// ARTISTE - Gamma wave distortion / shockwave shader
shader_type canvas_item;

uniform float wave_progress : hint_range(0.0, 1.0) = 0.0;
uniform float wave_strength : hint_range(0.0, 0.1) = 0.04;
uniform vec4 flash_color : source_color = vec4(0.8, 0.9, 1.0, 1.0);

void fragment() {
	vec2 uv = UV;
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(uv, center);
	
	// Expanding ring
	float ring_radius = wave_progress;
	float ring_width  = 0.08;
	float ring_factor = smoothstep(ring_radius - ring_width, ring_radius, dist)
	                  * (1.0 - smoothstep(ring_radius, ring_radius + ring_width, dist));
	
	// Distort UVs near ring
	vec2 dir = normalize(uv - center + vec2(0.0001));
	vec2 distorted_uv = uv + dir * ring_factor * wave_strength * sin(dist * 30.0 - wave_progress * 20.0);
	distorted_uv = clamp(distorted_uv, vec2(0.0), vec2(1.0));
	
	vec4 tex_color = texture(TEXTURE, distorted_uv);
	
	// White flash at impact centre
	float flash = (1.0 - wave_progress) * smoothstep(0.3, 0.0, dist) * 2.0;
	tex_color = mix(tex_color, flash_color, clamp(flash, 0.0, 1.0));
	
	COLOR = tex_color;
}
