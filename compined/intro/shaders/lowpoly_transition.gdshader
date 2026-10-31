// ARTISTE - Low-poly corruption / restoration transition shader
// Simulates pixel-block fragmentation to represent entropy damage
// Uniform 'progress': 0.0 = fully detailed, 1.0 = fully low-poly

shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float block_size : hint_range(2.0, 64.0) = 16.0;
uniform vec4 corruption_tint : source_color = vec4(0.3, 0.15, 0.5, 1.0);

void fragment() {
	vec2 uv = UV;

	// Compute block-quantised UV (simulates low-poly chunking)
	// Scale block size from 1px (no effect) to block_size px as progress increases
	float bs = mix(1.0, block_size, progress);
	// Quantise UV in texture-space by rounding down to nearest block
	vec2 uv_block = floor(uv / (bs * TEXTURE_PIXEL_SIZE)) * (bs * TEXTURE_PIXEL_SIZE);
	uv_block = clamp(uv_block, vec2(0.0), vec2(1.0));

	vec4 original_color = texture(TEXTURE, uv);
	vec4 blocked_color  = texture(TEXTURE, uv_block);

	// Mix toward blocked version as progress increases
	vec4 result = mix(original_color, blocked_color, progress);

	// Add corruption tint at high progress
	result.rgb = mix(result.rgb, result.rgb * corruption_tint.rgb, progress * 0.45);

	// Desaturate slightly as corruption grows
	float luma = dot(result.rgb, vec3(0.299, 0.587, 0.114));
	result.rgb = mix(result.rgb, vec3(luma), progress * 0.3);

	COLOR = result;
}
