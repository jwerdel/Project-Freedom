shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// The cloud deck of the look test's rise (god/empire.gd): a broad layer of drifting fbm cloud with
// sunlit tops and grey bellies, soft where it meets the ground or the camera, thinning with `fade`.

uniform float density = 1.0;
uniform float fade = 1.0;
uniform vec2 offset = vec2(0.0);
uniform vec3 lit : source_color = vec3(0.96, 0.95, 0.93);
uniform vec3 shade : source_color = vec3(0.56, 0.6, 0.66);
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Value noise from a tiling noise texture (hash noise breaks into blocks at large coordinates).
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
float noise(vec2 p) { return texture(noise_tex, p * (1.0 / 32.0)).r; }
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec2(3.1, 7.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = wpos.xz * 0.0011 + offset + vec2(TIME * 0.004, TIME * 0.0015);
	float c = fbm(uv);
	float c2 = fbm(uv * 3.1 + 5.0);
	float dens = smoothstep(0.42, 0.72, c * 0.8 + c2 * 0.3) * density;
	// Over the area the deck closes up (the swap between the worlds happens inside it).
	float r = length(wpos.xz);
	dens = max(dens, smoothstep(3200.0, 900.0, r) * smoothstep(0.3, 0.62, c * 0.7 + c2 * 0.4) * density);
	float top = clamp((c2 - 0.35) * 2.0, 0.0, 1.0);
	vec3 col = mix(shade, lit, top * 0.7 + 0.3);
	// Soft where the deck cuts through the camera's view of nearer things, and near the camera.
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_d = -vp.z / vp.w;
	float soft = clamp((scene_d + VERTEX.z) / 60.0, 0.0, 1.0);
	float near = smoothstep(0.0, 120.0, -VERTEX.z);
	ALBEDO = col;
	ALPHA = clamp(dens * soft * near * fade, 0.0, 0.97);
}
