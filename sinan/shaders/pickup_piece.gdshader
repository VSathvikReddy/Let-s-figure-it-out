shader_type canvas_item;
render_mode unshaded;  // ignore the level's darkening and lights so pickups pop
// Coins drawn by PickupField's MultiMeshes, done on the GPU so settled pieces
// never need buffer updates:
//   INSTANCE_CUSTOM.x = 1 -> resting: bob up and down
//   INSTANCE_CUSTOM.y = time (field clock) the piece expires -> blink before it
// Each coin is a real disc with thickness spinning around its vertical axis:
// the face narrows as it turns, and the reeded EDGE (rim band) shows on the
// side turning away - so it reads as a solid coin, not a flat sticker.

uniform float bob_amount = 2.0;
uniform float bob_speed = 4.0;
uniform float now = 0.0;          // field clock, set every frame by PickupField
uniform float blink_time = 4.0;   // seconds of blinking before expiry (0 = off)
uniform float brightness = 1.35;  // colour boost so pickups pop
uniform float saturation = 1.15;
uniform float spin_speed = 0.9;   // turns per second
uniform float thickness = 0.24;   // in coin radii
uniform vec3 rim_color : source_color = vec3(0.72, 0.5, 0.16);

varying float blink;
varying float v_c;      // cos of the spin angle (face width, signed)
varying float v_s;      // sin (which way the edge shows)
varying float v_k;      // half width of the quad, in coin radii
varying vec4 v_color;

void vertex() {
	float id = float(INSTANCE_ID);
	VERTEX.y += sin(TIME * bob_speed + id * 1.7) * bob_amount * INSTANCE_CUSTOM.x;
	// flying: full 3D flip; lying on the floor (custom.x = 1): faces you with
	// just a gentle sway, so every resting coin is clearly visible
	float a = INSTANCE_CUSTOM.x > 0.5 ? sin(TIME * 1.6 + id * 1.3) * 0.35 : TIME * spin_speed * 6.2831 + id * 2.3;
	v_c = cos(a);
	v_s = sin(a);
	v_k = max(abs(v_c) + thickness * abs(v_s) * 0.5, 0.06);
	VERTEX.x *= v_k;
	v_color = COLOR;
	float left = INSTANCE_CUSTOM.y - now;
	blink = 1.0;
	if (blink_time > 0.0 && INSTANCE_CUSTOM.y > 0.0 && left < blink_time) {
		blink = mod(floor(left * 10.0), 2.0) < 0.5 ? 0.25 : 1.0;
	}
}

void fragment() {
	// position on the coin, in radii: x across (squashed by the spin), y down
	vec2 p = vec2((UV.x * 2.0 - 1.0) * v_k, UV.y * 2.0 - 1.0);
	float h = sqrt(max(1.0 - p.y * p.y, 0.0));
	float face_w = max(abs(v_c), 0.001);
	float front_x = thickness * 0.5 * v_s;     // the face we see sits this far over...
	float back_x = -front_x;                   // ...and the hidden face the other way
	vec4 col = vec4(0.0);
	if (abs(p.x - front_x) <= face_w * h) {
		// the face: the coin art, mirrored when the back side turns to us
		float u = (p.x - front_x) / face_w * 0.5 + 0.5;
		if (v_c < 0.0) { u = 1.0 - u; }
		col = texture(TEXTURE, vec2(u, UV.y)) * v_color;
		col.rgb *= mix(0.6, 1.0, abs(v_c));
	} else if (p.x >= min(front_x, back_x) - face_w * h && p.x <= max(front_x, back_x) + face_w * h && abs(p.y) <= 1.0) {
		// the edge: reeded gold band, lit along the top, darker toward the bottom
		float reed = 0.82 + 0.18 * step(0.5, fract(p.y * 9.0));
		float light = mix(1.15, 0.6, (p.y + 1.0) * 0.5);
		col = vec4(rim_color * reed * light, 1.0) * v_color;  // alpha 0 = collected slot
	}
	vec3 c = col.rgb;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(grey), c, saturation) * brightness;
	// a soft diagonal glint sweeps across the face as it turns to you
	float glint = smoothstep(0.8, 1.0, sin(atan(v_s, v_c) + 0.6));
	float band = 1.0 - abs((UV.x + UV.y) - 0.6 - glint * 0.6) * 3.0;
	c += vec3(1.0, 0.92, 0.7) * clamp(band, 0.0, 1.0) * glint * 0.5 * step(0.01, col.a);
	COLOR = vec4(c, col.a * blink);
}
