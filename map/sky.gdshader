shader_type sky;
// Campaign sky (TW:WH3 look, owner 2026-10-05): a deep blue zenith fading to a pale hazy horizon,
// a warm sun glow, and soft drifting fair-weather clouds (fbm on the sky dome, lit from the sun).
// The haze colour of the map's fog (data/campaign_view.json "atmosphere") matches the horizon.

uniform vec3 zenith : source_color = vec3(0.24, 0.42, 0.68);
uniform vec3 horizon : source_color = vec3(0.77, 0.83, 0.89);
uniform vec3 ground_tint : source_color = vec3(0.55, 0.6, 0.64);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.68, 0.76);
uniform float cloud_cover = 0.48;
uniform float cloud_speed = 0.004;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.02 + vec2(5.3, 1.7); a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(max(up, 0.0), 0.55));
	if (up < 0.0) col = mix(horizon, ground_tint, clamp(-up * 3.0, 0.0, 1.0));
	// The sun: a soft warm glow around it.
	vec3 sd = LIGHT0_DIRECTION;
	float s = max(dot(d, sd), 0.0);
	col += vec3(1.0, 0.86, 0.62) * (pow(s, 8.0) * 0.25 + pow(s, 600.0) * 2.0) * LIGHT0_ENERGY;
	// Clouds on a plane above: fbm coverage, lit on the sun side, thinned toward the horizon.
	if (up > 0.02) {
		vec2 uv = d.xz / (up + 0.12) * 1.6 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float c = fbm(uv);
		float cover = smoothstep(cloud_cover, cloud_cover + 0.25, c);
		float lit = smoothstep(cloud_cover - 0.1, cloud_cover + 0.45, fbm(uv + sd.xz * 0.06));
		vec3 cc = mix(cloud_shade, cloud_light, lit);
		col = mix(col, cc, cover * smoothstep(0.02, 0.25, up) * 0.9);
	}
	COLOR = col;
}
