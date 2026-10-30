shader_type canvas_item;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec2 viewport_size = vec2(1152.0, 648.0);
uniform vec2 center_px     = vec2(576.0, 324.0);

// Driven by the script (tweened), unchanged
uniform float sweep : hint_range(0.0, 1.0) = 0.0;
uniform float hole_radius = 0.0;
uniform float disk_fade : hint_range(0.0, 1.0) = 1.0;
uniform float veil_radius = 0.0;
uniform float veil_alpha : hint_range(0.0, 1.0) = 0.0;

// Paint look
uniform float disk_width = 70.0;       // average reach of the paint (px)
uniform float flow_speed = 0.04;       // how slowly the paint crawls
uniform float bleed      = 0.6;        // dry-brush breakup amount
uniform float bristle    = 1.0;        // bristle streak density (radial frequency)
uniform float veil_soft  = 60.0;
uniform vec3 paint_light : source_color = vec3(1.0, 0.88, 0.45);
uniform vec3 paint_mid   : source_color = vec3(0.95, 0.68, 0.18);
uniform vec3 paint_dark  : source_color = vec3(0.35, 0.14, 0.03);

float nz(vec2 uv) {
	return texture(noise_tex, uv).r;
}

void fragment() {
	vec2  p   = UV * viewport_size;
	vec2  dir = p - center_px;
	float r   = length(dir);                // true distance: perfect circle fill
	float ang = atan(dir.x, -dir.y);        // 0 at top, clockwise
	float t   = fract(ang / TAU);

	// 1) Sector mask: clips both the fill and the paint
	float swept = (sweep >= 0.999) ? 1.0 : 1.0 - smoothstep(sweep - 0.004, sweep, t);

	// 2) Black shadow: perfect circle, clipped by the sector
	float core = (1.0 - smoothstep(hole_radius - 1.0, hole_radius + 1.0, r))
	           * smoothstep(0.0, 2.0, hole_radius)
	           * swept;

	// 3) PAINT
	float outside = smoothstep(hole_radius - 1.0, hole_radius + 1.0, r);
	float rd = max(r - hole_radius, 0.0);
	float flow = TIME * flow_speed;

	// Wet paint pooling at the brush tip while sweeping
	float lead = (sweep < 0.999) ? exp(-clamp(sweep - t, 0.0, 1.0) * 25.0) : 0.0;

	// Uneven reach around the ring: fingers and gaps
	float reach = disk_width
	            * mix(0.35, 1.3, nz(vec2(t * 4.0 - flow, 0.13)))
	            * (0.7 + 0.6 * nz(vec2(t * 9.0 + flow * 2.0, 0.57)));
	reach *= 1.0 + lead * 0.8;
	float k = rd / max(reach, 1.0);          // 0 at shadow edge, 1 at paint edge

	// Gentle warp so streaks meander instead of being ruler-straight
	float warp = nz(vec2(t * 2.0 + flow, rd * 0.004)) - 0.5;

	// Bristle streaks: low frequency along the stroke (u), high across it (v)
	float b = nz(vec2(t * 6.0 + warp * 0.3 - flow, rd * 0.06 * bristle));

	// Paint density: thick near the shadow, thinning outward, eaten by bristle noise
	float density = (1.0 - k) + (b - 0.5) * bleed * 1.5;

	float paint = smoothstep(0.0, 0.12, density);                         // crisp edge
	float halo  = smoothstep(-0.35, 0.0, density) * (1.0 - paint) * 0.35; // ink bleed

	// Colour: light in the thick middle, dark pooled rim
	vec3 col = mix(paint_dark, paint_mid, smoothstep(0.0, 0.4, density));
	col = mix(col, paint_light, smoothstep(0.5, 1.0, density) * (0.5 + 0.5 * b));
	col = mix(col, paint_light, exp(-rd / 6.0) * 0.6);                    // wet highlight
	col = mix(col, paint_light, lead * 0.5);                              // fresh paint at tip

	float a_disk = max(paint, halo) * outside * swept * disk_fade;

	// 4) Veil: translucent black with soft edge
	float veil = (1.0 - smoothstep(veil_radius - veil_soft, veil_radius, r)) * veil_alpha;

	// 5) Compose: paint over veil, core over everything
	float alpha = a_disk + veil * (1.0 - a_disk);
	alpha = max(alpha, core);
	COLOR = vec4(col * a_disk / max(alpha, 0.0001), alpha);
}