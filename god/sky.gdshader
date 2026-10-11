shader_type sky;
// The look test's winter sky over Frosthold: a cold scattering gradient (deep blue-grey above,
// pale haze at the horizon, warm glow around a low sun), a sun disc, and two drifting layers of fbm
// cloud lit from the sun side (bright rims, grey bellies). Also lights the scene (ambient and
// reflections come from it).

uniform vec3 zenith : source_color = vec3(0.26, 0.35, 0.5);
uniform vec3 horizon : source_color = vec3(0.74, 0.79, 0.84);
uniform vec3 ground_col : source_color = vec3(0.32, 0.33, 0.35);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.78, 0.55);
uniform float cloud_cover = 0.52;
uniform float cloud_speed = 0.004;
uniform float exposure = 1.0;

// Value noise from a tiling noise texture (hash noise breaks into blocks at large coordinates).
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
float noise(vec2 p) { return texture(noise_tex, p * (1.0 / 32.0)).r; }
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sd = LIGHT0_DIRECTION;
	float sun_dot = max(dot(d, sd), 0.0);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		float t = pow(1.0 - h, 4.0);
		col = mix(zenith, horizon, t);
		col += sun_glow * (pow(sun_dot, 8.0) * 0.35 + pow(sun_dot, 64.0) * 0.6) * (0.5 + 0.5 * t);
		// Clouds on a plane above: two layers, the near one denser.
		{
			vec2 uv = d.xz / (h + 0.08);
			float tm = TIME * cloud_speed;
			float c1 = fbm(uv * 0.9 + vec2(tm, tm * 0.4));
			float c2 = fbm(uv * 2.6 - vec2(tm * 1.6, 0.0));
			float dens = smoothstep(1.0 - cloud_cover, 1.05 - cloud_cover * 0.4, c1 * 0.75 + c2 * 0.35);
			// Light from the sun side: sample toward the sun for self-shadowing.
			float toward = fbm(uv * 0.9 + vec2(tm, tm * 0.4) + sd.xz * 0.08);
			float lit = clamp(1.0 - (toward - c1) * 3.5, 0.35, 1.25);
			vec3 cc = mix(vec3(0.42, 0.45, 0.5), vec3(0.95, 0.94, 0.92), lit * 0.75);
			cc += sun_glow * pow(sun_dot, 6.0) * 0.5 * (1.0 - dens * 0.5);
			float fade = smoothstep(0.0, 0.18, h);
			col = mix(col, cc, dens * fade * 0.92);
		}
		// Sun disc.
		col += vec3(1.0, 0.92, 0.8) * smoothstep(0.9993, 0.9997, sun_dot) * 18.0;
	} else {
		col = mix(horizon * 0.8, ground_col, smoothstep(0.0, 0.3, -h));
	}
	COLOR = col * exposure;
}
