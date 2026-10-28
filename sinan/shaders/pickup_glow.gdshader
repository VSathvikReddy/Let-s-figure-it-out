shader_type canvas_item;
render_mode blend_add, unshaded;  // ignore the level's darkening so the glow stays bright
// Additive glow behind ammo pieces (same per-instance data as pickup_piece).

uniform float bob_amount = 2.0;
uniform float bob_speed = 4.0;
uniform float now = 0.0;
uniform float blink_time = 4.0;
uniform float brightness = 1.25;
uniform float saturation = 1.35;

varying float blink;

void vertex() {
	VERTEX.y += sin(TIME * bob_speed + float(INSTANCE_ID) * 1.7) * bob_amount * INSTANCE_CUSTOM.x;
	float left = INSTANCE_CUSTOM.y - now;
	blink = 1.0;
	if (blink_time > 0.0 && INSTANCE_CUSTOM.y > 0.0 && left < blink_time) {
		blink = mod(floor(left * 10.0), 2.0) < 0.5 ? 0.25 : 1.0;
	}
}

void fragment() {
	COLOR.a *= blink;
}
