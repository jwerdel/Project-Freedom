shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// The look test's shockwave and sonic-boom rings (god/vfx.gd): a band that bends what is behind it
// (screen-space refraction) with a pale dusty rim, fading as it expands.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
instance uniform float fade = 1.0;
instance uniform float strength = 1.0;

void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	vec2 off = NORMAL.xy * 0.06 * strength * fade * (0.4 + rim);
	vec3 bent = textureLod(screen_tex, SCREEN_UV + off, 1.5).rgb;
	ALBEDO = bent + vec3(0.9, 0.88, 0.82) * rim * 0.35 * fade * strength;
	ALPHA = clamp((0.35 + rim) * fade, 0.0, 1.0);
}
