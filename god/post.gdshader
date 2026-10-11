shader_type canvas_item;
// Full-screen pass of the god-game look test (god/hud.gd): a grimdark grade (cool shadows, warm
// highlights, gentle desaturation, vignette), speed lines streaming from the centre in fast flight,
// the charge-up's tunnel squeeze, and white impact flashes.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float speed_lines = 0.0;
uniform float charge = 0.0;
uniform float flash = 0.0;
uniform float vignette = 0.32;
uniform vec3 shadow_tint : source_color = vec3(0.86, 0.92, 1.04);
uniform vec3 high_tint : source_color = vec3(1.04, 1.0, 0.94);
uniform float grade = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r = length(c * vec2(1.6, 1.0));
	// Charge: a slight squeeze toward the centre.
	vec2 suv = uv - c * charge * 0.015 * r;
	vec3 col = textureLod(screen_tex, suv, 0.0).rgb;
	// Grade.
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 tint = mix(shadow_tint, high_tint, smoothstep(0.15, 0.75, l));
	col = mix(col, col * tint, grade);
	col = mix(vec3(l), col, mix(1.0, 0.92, grade));
	// Speed lines: thin streaks in polar coordinates rushing outward.
	if (speed_lines > 0.001) {
		float a = atan(c.y, c.x);
		float lane = floor(a * 70.0);
		float h = hash(vec2(lane, 3.1));
		float flow = fract(r * 2.2 - TIME * (2.0 + h * 2.5) + h * 7.0);
		float streak = smoothstep(0.0, 0.08, flow) * smoothstep(0.42, 0.12, flow);
		float thin = smoothstep(0.42, 0.5, fract(a * 70.0)) * smoothstep(0.58, 0.5, fract(a * 70.0));
		float mask = smoothstep(0.22, 0.75, r) * step(0.55, h);
		col = mix(col, vec3(0.94, 0.96, 1.0), streak * thin * mask * speed_lines * 0.65);
	}
	// Vignette (deeper while charging).
	float v = smoothstep(0.45, 1.05, r) * (vignette + charge * 0.35);
	col *= 1.0 - v;
	col = mix(col, vec3(1.0, 0.97, 0.9), flash);
	COLOR = vec4(col, 1.0);
}
