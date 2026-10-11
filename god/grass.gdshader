shader_type spatial;
render_mode cull_disabled;
// Dry winter grass tufts poking out of the snow (god/foliage.gd): straw at the tips, darker at the
// root, frost on the tips, swaying in the wind.

uniform vec3 root_color : source_color = vec3(0.24, 0.22, 0.15);
uniform vec3 tip_color : source_color = vec3(0.55, 0.5, 0.38);
uniform vec3 frost : source_color = vec3(0.86, 0.88, 0.92);

varying float t;
varying vec3 wpos;

void vertex() {
	t = COLOR.a;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * 1.6 + wpos.x * 0.35 + wpos.z * 0.27) * 0.5 + sin(TIME * 3.7 + wpos.x * 1.3) * 0.15;
	VERTEX.x += w * t * t * 0.12;
	VERTEX.z += w * t * t * 0.07;
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + (MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz * 0.0);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	float v = hash(floor(wpos.xz * 1.3));
	vec3 c = mix(root_color, tip_color * (0.8 + 0.4 * v), smoothstep(0.0, 0.8, t));
	c = mix(c, frost, smoothstep(0.75, 1.0, t) * 0.5);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.25, 0.22, 0.12) * t;
	AO = mix(0.4, 1.0, t);
}
