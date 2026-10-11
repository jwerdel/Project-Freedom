shader_type spatial;
render_mode cull_disabled;
// Tree foliage of the god-game look test (god/fir_builder.gd needle cards, the Poly Haven sapling):
// alpha cut-out that holds up at a distance (coverage boosted as the texture shrinks on screen), a
// slow sway growing toward the top, snow on the upper side of the branches, light through the needles.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool use_normal_map = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform float snow = 0.6;
uniform float sway = 0.25;
uniform vec2 tex_size = vec2(512.0, 256.0);

varying vec3 wnrm;
varying float hgt;

void vertex() {
	hgt = VERTEX.y;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 0.9 + w.x * 0.05 + w.z * 0.04;
	float bend = VERTEX.y * VERTEX.y * 0.004;
	VERTEX.x += sin(t) * sway * bend;
	VERTEX.z += cos(t * 0.8) * sway * bend * 0.7;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * tint;
	vec2 px = UV * tex_size;
	float m = max(length(dFdx(px)), length(dFdy(px)));
	float cover = a.a * (1.0 + max(0.0, log2(max(m, 1.0))) * 0.55);
	if (cover < 0.5) discard;
	vec3 alb = a.rgb * COLOR.rgb;
	float up = wnrm.y;
	float s = smoothstep(0.35, 0.85, up) * snow;
	alb = mix(alb, vec3(0.86, 0.89, 0.95), s * 0.9);
	ALBEDO = alb;
	ROUGHNESS = mix(0.9, 0.65, s);
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.6;
	}
	BACKLIGHT = vec3(0.1, 0.14, 0.08) * (1.0 - s);
	AO = 0.55 + 0.45 * clamp(hgt * 0.08, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.4;
}
