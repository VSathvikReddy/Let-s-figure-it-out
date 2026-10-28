shader_type canvas_item;
render_mode unshaded;  // ignore the level's darkening so the shadow stays inky
// Living-shadow look for the Forger's body parts: a void-black fill whose
// border is soft and blurry, wobbles like smoke and fades out into a faint dark
// haze. No outline.

uniform vec4 fill_color : source_color = vec4(0.012, 0.012, 0.018, 1.0);
uniform float edge_blur = 9.0;      // softness of the border (texture px; parts are drawn small)
uniform float edge_wobble = 3.0;    // how much the border wavers like smoke (texture px)
uniform float haze = 0.45;          // strength of the dark haze just outside the body
uniform float ink_swirl = 0.02;     // faint moving texture inside the body

float a_at(sampler2D tex, vec2 uv) {
	return texture(tex, uv).a;
}

void fragment() {
	// wobble the lookup a little so the border shifts like smoke
	vec2 wob = vec2(sin(UV.y * 90.0 + TIME * 3.1), cos(UV.x * 80.0 - TIME * 2.7)) * edge_wobble * TEXTURE_PIXEL_SIZE;
	vec2 uv = UV + wob;
	vec2 r1 = TEXTURE_PIXEL_SIZE * edge_blur;
	float sum = a_at(TEXTURE, uv);
	float outer = 0.0;
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * 0.785398 + 0.39;
		vec2 d = vec2(cos(ang), sin(ang));
		sum += a_at(TEXTURE, uv + d * r1);
		outer = max(outer, a_at(TEXTURE, uv + d * r1 * 2.2));
	}
	float body = sum / 9.0;                       // blurred silhouette
	body = smoothstep(0.08, 0.85, body);
	float halo = outer * (1.0 - body) * haze;     // faint dark smoke around it
	float swirl = sin(UV.x * 140.0 + TIME * 2.0) * sin(UV.y * 120.0 - TIME * 1.6) * ink_swirl;
	vec3 col = fill_color.rgb + vec3(swirl * 0.5, swirl * 0.5, swirl * 0.8);
	// COLOR.a carries the node's modulate alpha (appear / vanish fades)
	COLOR = vec4(col, max(body, halo) * COLOR.a);
}
