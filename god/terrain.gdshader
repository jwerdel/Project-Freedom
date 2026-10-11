shader_type spatial;
// Ground of the god-game look test (god/terrain.gd): snow over frozen ground, with bare earth,
// road mud, field soil and paving from the splat image, rock on steep slopes (triplanar), all from
// CC0 Poly Haven PBR sets. Each layer is sampled at two scales with a macro tint so tiling breaks
// up, and layers blend by height (the albedo's brightness) for crisp edges.

uniform sampler2D splat : filter_linear, repeat_disable;
uniform float area_half = 1200.0;
uniform sampler2D snow_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pave_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pave_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable; // tileable noise (R, G)
uniform float snow_amount = 0.82;
uniform vec3 snow_tint : source_color = vec3(0.93, 0.95, 1.0);
uniform vec3 ground_tint : source_color = vec3(0.78, 0.74, 0.66);
uniform float far_blend = 0.0; // 0 near, 1 at the empire view (flat colours, no detail)
uniform bool flat_look = false; // the material pass's "before": flat colours, no textures

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack_n(vec4 t) { vec2 xy = t.xy * 2.0 - 1.0; return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy)))); }

// Two scales of one layer plus a macro brightness wobble.
vec4 layer(sampler2D a, vec2 uv, float s1, float s2, float m) {
	vec4 x = texture(a, uv * s1);
	vec4 y = texture(a, uv * s2 + vec2(0.37, 0.71));
	return mix(x, y, 0.35 + 0.3 * m);
}

vec3 layer_n(sampler2D nt, vec2 uv, float s1, float s2, float m) {
	vec3 x = unpack_n(texture(nt, uv * s1));
	vec3 y = unpack_n(texture(nt, uv * s2 + vec2(0.37, 0.71)));
	return normalize(mix(x, y, 0.35 + 0.3 * m));
}

float hblend(float base_h, float layer_h, float w, float sharp) {
	// Height blend: the layer wins where its height plus the weight beats the base.
	return smoothstep(-sharp, sharp, (layer_h + w * 1.6 - 0.8) - base_h);
}

void fragment() {
	vec2 uv = wpos.xz;
	vec2 suv = (wpos.xz + area_half) / (2.0 * area_half);
	vec4 sp = texture(splat, suv);
	vec4 mac = texture(macro, uv * 0.0021);
	vec4 mac2 = texture(macro, uv * 0.017 + vec2(0.5));
	float m = mac.r;
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);

	// Layers (metres per tile: snow 4, ground 3, mud 2.5, paving 3, rock 6).
	vec4 sn = layer(snow_a, uv, 0.25, 0.061, m);
	vec4 gr = layer(ground_a, uv, 0.33, 0.083, m);
	vec4 md = layer(mud_a, uv, 0.4, 0.11, m);
	vec4 pv = texture(pave_a, uv * 0.33);
	vec3 nsn = layer_n(snow_n, uv, 0.25, 0.061, m);
	vec3 ngr = layer_n(ground_n, uv, 0.33, 0.083, m);
	vec3 nmd = layer_n(mud_n, uv, 0.4, 0.11, m);
	vec3 npv = unpack_n(texture(pave_n, uv * 0.33));

	// Triplanar rock on slopes.
	vec3 bw = pow(abs(wnorm), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec4 rk = texture(rock_a, wpos.zy / 6.0) * bw.x + texture(rock_a, wpos.xz / 6.0) * bw.y + texture(rock_a, wpos.xy / 6.0) * bw.z;
	vec3 nrk = unpack_n(texture(rock_n, wpos.zy / 6.0)) * bw.x + unpack_n(texture(rock_n, wpos.xz / 6.0)) * bw.y + unpack_n(texture(rock_n, wpos.xy / 6.0)) * bw.z;

	float h_sn = dot(sn.rgb, vec3(0.333));
	float h_gr = dot(gr.rgb, vec3(0.333)) + 0.1;
	float h_md = dot(md.rgb, vec3(0.333));

	// Start from frozen ground; snow lies on top except where the splat bares the earth.
	vec3 alb = gr.rgb * ground_tint * (0.85 + 0.3 * mac2.g);
	vec3 nrm = ngr;
	float rough = 0.92;
	// Fields: furrowed soil with snow in the furrows.
	float field = sp.b;
	float furrow = 0.5 + 0.5 * sin(wpos.x * 2.6 + mac2.r * 2.0);
	alb = mix(alb, md.rgb * vec3(0.7, 0.62, 0.55), field * 0.85);
	nrm = normalize(mix(nrm, nmd, field));
	// Snow cover: thinner on bare ground and roads, none on steep rock.
	float bare = max(sp.g, sp.r);
	float snow_w = snow_amount * (1.0 - bare * 0.85) * (1.0 - smoothstep(0.32, 0.55, slope));
	snow_w *= 0.75 + 0.5 * mac.g;
	snow_w = mix(snow_w, snow_w * furrow, field);
	float sw = hblend(h_gr, h_sn, snow_w, 0.12);
	alb = mix(alb, sn.rgb * snow_tint, sw);
	nrm = normalize(mix(nrm, nsn, sw));
	rough = mix(rough, 0.55, sw);
	// Road mud: wet, darker, with slush at the edges.
	float rd = hblend(h_sn * sw + h_gr * (1.0 - sw), h_md, sp.r, 0.1);
	alb = mix(alb, md.rgb * vec3(0.62, 0.55, 0.5), rd);
	nrm = normalize(mix(nrm, nmd, rd));
	rough = mix(rough, 0.45, rd);
	// Paving (the market square, the castle court).
	float pw = smoothstep(0.2, 0.6, sp.a);
	alb = mix(alb, pv.rgb * vec3(0.8, 0.8, 0.82) * mix(1.0, 1.15, sw * 0.5), pw);
	nrm = normalize(mix(nrm, npv, pw));
	// Rock.
	float rw = smoothstep(0.36, 0.58, slope + (rk.r - 0.5) * 0.2);
	alb = mix(alb, rk.rgb * vec3(0.78, 0.8, 0.84), rw);
	nrm = normalize(mix(nrm, nrk, rw));
	rough = mix(rough, 0.85, rw);

	if (flat_look) {
		alb = mix(vec3(0.42, 0.4, 0.33), vec3(0.93, 0.95, 0.98), sw);
		alb = mix(alb, vec3(0.45, 0.35, 0.25), max(rd, field * 0.8));
		alb = mix(alb, vec3(0.55, 0.55, 0.56), max(pw, rw));
		nrm = vec3(0.0, 0.0, 1.0);
		rough = 0.9;
	}
	// Far away the detail averages out: fade toward the layers' mean colours.
	alb = mix(alb, mix(vec3(0.78, 0.8, 0.84), vec3(0.88, 0.9, 0.94), snow_amount), far_blend);
	ALBEDO = alb;
	ROUGHNESS = rough;
	// Tangent frame for a heightfield in world space: x along +X, y along +Z.
	vec3 T = normalize(vec3(1.0, 0.0, 0.0) - wnorm * wnorm.x);
	vec3 B = normalize(cross(wnorm, T));
	vec3 wn = normalize(wnorm + (T * nrm.x - B * nrm.y) * (1.0 - far_blend) * 0.9);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
