shader_type spatial;
// Buildings and debris of the god-game look test (god/mesh_kit.gd chunks): a CC0 PBR texture set
// (albedo, OpenGL normal, AO-roughness-metal) on the chunk's planar UVs, tinted by the kit colour
// (COLOR.rgb), with grime and damp rising from the ground (COLOR.a = height above the base), snow
// settling on upward faces (Frosthold) and soot where fire has touched (scorch).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool textured = true;
uniform vec3 base_color : source_color = vec3(0.6);
uniform float roughness_scale = 1.0;
uniform float normal_strength = 1.0;
uniform float snow = 0.85;
uniform float grime = 0.55;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float leaves = 0.0; // the Hearthtree's crown: tint the texture red and shade it softly
uniform vec3 tint = vec3(1.0); // per material: grades the texture toward the Frosthold board (cool grey stone, dark timber)
uniform float saturation = 1.0; // per material: grimdark keeps colours muted

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Normal maps import as two-channel (RGTC): rebuild z, back in 0..1 for NORMAL_MAP.
vec3 rg_normal(vec2 t) { vec2 xy = t * 2.0 - 1.0; return vec3(t, sqrt(max(0.0, 1.0 - dot(xy, xy))) * 0.5 + 0.5); }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec3 alb = base_color;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float ao = 1.0;
	float rough = 0.85;
	float metal = 0.0;
	if (textured) {
		alb = texture(albedo_tex, UV).rgb;
		nm = rg_normal(texture(normal_tex, UV).xy);
		vec3 arm = texture(arm_tex, UV).rgb;
		ao = arm.r;
		rough = arm.g;
		metal = arm.b;
	}
	alb *= COLOR.rgb * tint;
	alb = mix(vec3(dot(alb, vec3(0.299, 0.587, 0.114))), alb, saturation);
	if (leaves > 0.0) {
		alb = mix(alb, vec3(dot(alb, vec3(0.33))) * vec3(1.6, 0.25, 0.22), leaves);
	}
	// Grime and damp near the ground, broken up by noise.
	float n1 = vnoise(wpos.xz * 0.7 + wpos.y * 0.3);
	float n2 = vnoise(wpos.xz * 3.1 - wpos.y * 1.7);
	float g = (1.0 - smoothstep(0.0, 0.32 + 0.25 * n1, COLOR.a)) * grime;
	alb = mix(alb, alb * vec3(0.45, 0.42, 0.38), g);
	rough = mix(rough, rough * 0.8, g);
	// Streaks of weathering down walls.
	float streak = vnoise(vec2(wpos.x * 4.0 + wpos.z * 4.0, wpos.y * 0.25));
	alb *= mix(1.0, 0.82 + 0.18 * streak, 0.6 * (1.0 - abs(wnrm.y)));
	// Snow on upward faces (sharper on roofs), thinner where the surface is steep.
	float up = wnrm.y;
	float s = smoothstep(0.35, 0.75, up + (n2 - 0.5) * 0.35) * snow;
	s *= smoothstep(0.15, 0.5, n1 + 0.35);
	vec3 sn = texture(snow_tex, wpos.xz * 0.3).rgb * vec3(0.95, 0.97, 1.0);
	vec3 snn = rg_normal(texture(snow_n, wpos.xz * 0.3).xy);
	alb = mix(alb, sn, s);
	nm = mix(nm, snn, s);
	rough = mix(rough, 0.6, s);
	ALBEDO = alb;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = clamp(rough * roughness_scale, 0.05, 1.0);
	METALLIC = metal;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = normal_strength;
	EMISSION = emission_color * emission_energy;
	if (leaves > 0.0) {
		BACKLIGHT = vec3(0.35, 0.05, 0.04) * leaves;
	}
}
