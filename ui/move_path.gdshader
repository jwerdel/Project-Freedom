shader_type spatial;
// The movement path ribbon (ui/movement_overlay.gd), TW:WH3-style: thick, drawn over everything
// (no depth test against trees, buildings, hills or walls), with chevrons running toward the
// destination. The mesh is the path's centre line: NORMAL holds each vertex's side direction and
// the ribbon is widened here, so the width follows the camera height without rebuilding.
// UV.x = metres along the path, UV.y = 0..1 across; COLOR = the turn colour.
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix, shadows_disabled, depth_draw_never;

uniform float half_width = 0.6;
uniform float spacing = 3.0;     // metres between chevrons (scaled with the width)
uniform float speed = 1.2;       // chevron spacings per second
uniform float chevrons = 1.0;    // 0 for the faint lines of other armies' orders
uniform float opacity = 1.0;

varying float across;

void vertex() {
	VERTEX += NORMAL * half_width;
	across = UV.y;
}

void fragment() {
	float a = abs(across - 0.5) * 2.0; // 0 at the centre, 1 at the edges
	float x = UV.x / spacing - TIME * speed;
	float f = fract(x + a * 0.45);     // a ">" pointing along the path
	float chev = smoothstep(0.0, 0.06, f) * (1.0 - smoothstep(0.26, 0.34, f)) * (1.0 - smoothstep(0.62, 0.74, a));
	float edge = smoothstep(0.72, 0.86, a);
	vec3 col = mix(COLOR.rgb, vec3(0.03, 0.03, 0.02), edge * 0.9);
	col = mix(col, vec3(1.0, 0.98, 0.86), chev * chevrons * 0.7);
	ALBEDO = col;
	ALPHA = COLOR.a * opacity * (1.0 - smoothstep(0.96, 1.0, a));
}
