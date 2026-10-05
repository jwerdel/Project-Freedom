shader_type spatial;
// Pipeline-map terrain (docs/map-pipeline-design.md §4.3, Addendum A.4), TW:WH3 campaign look
// (owner, 2026-10-04): every chunk shares this material and a flat grid mesh displaced from the
// heightfield. The colour is layered by slope and height in the culture's biome palette
// (data/cultures.json "ground", targets docs/reference/biomes/): grass and dry patches on open land,
// rock on steep slopes, scree at the feet of the ranges, snow above the snow line, dirt on passes and
// roads, sand on beaches, a lumpy canopy carpet on forest cells, and water in the rivers. Procedural
// detail (mottling, rock strata, cavity shading, per-pixel normals) keeps it from reading as paint.
// Land conversion: each region's palette texel holds the culture its land is turning from, the one
// it is turning into and how far (0-1); the two biomes blend in noise patches.

uniform sampler2D heights : filter_linear, repeat_disable;      // R32F, metres
uniform sampler2D classes : filter_nearest, repeat_disable;     // R8: data/movement.json class index
uniform sampler2D regions : filter_nearest, repeat_disable;     // RGBA8: region id = R + 256 G (0 = none)
uniform sampler2D palette : filter_nearest, repeat_disable;     // per region (x = id): R from, G to, B value
uniform sampler2D culture_colors : source_color, filter_nearest, repeat_disable; // x = ground layer, y = culture (sRGB)
uniform sampler2D culture_params : filter_nearest, repeat_disable; // x = culture: R snow line / 100 m
uniform sampler2D rivers : filter_linear, repeat_disable;       // R8 river strength
uniform sampler2D roads : filter_linear, repeat_disable;        // R8 road cells (0 or 1/255)
uniform vec2 origin;      // world x/z of the grid's corner
uniform vec2 world_size;  // metres covered by the textures
uniform vec2 grid_size;   // cells
uniform float region_count = 1.0;
uniform float culture_count = 1.0;
uniform float sea_level = 0.0;
// Class indices (data/movement.json order).
uniform int class_forest = 1;
uniform int class_hills = 2;
uniform int class_pass = 3;
uniform int class_settlement = 4;
uniform int class_mountain = 5;
uniform int class_water = 6;

varying vec2 world_xz;
varying float world_h;

// Ground layers (columns of culture_colors).
const int GRASS = 0;
const int DRY = 1;
const int FLOOR = 2;
const int CANOPY = 3;
const int ROCK = 4;
const int SCREE = 5;
const int SNOW = 6;
const int DIRT = 7;
const int SAND = 8;
const int WATER = 9;

float h_at(vec2 xz) {
	return textureLod(heights, (xz - origin) / world_size, 0.0).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_xz = w.xz;
	VERTEX.y = h_at(w.xz);
	world_h = VERTEX.y;
	float e = world_size.x / grid_size.x;
	float hx = h_at(w.xz + vec2(e, 0.0)) - h_at(w.xz - vec2(e, 0.0));
	float hz = h_at(w.xz + vec2(0.0, e)) - h_at(w.xz - vec2(0.0, e));
	NORMAL = normalize(vec3(-hx, 2.0 * e, -hz));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

// Tree crowns as seen from above: bumps on a jittered grid (about 4 m apart).
float crowns(vec2 p) {
	vec2 c = floor(p);
	float best = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = c + vec2(float(x), float(y));
			vec2 o = vec2(hash(g), hash(g + 31.7)) * 0.8 + 0.1;
			best = min(best, length(p - g - o));
		}
	}
	return 1.0 - smoothstep(0.0, 0.75, best);
}

vec3 layer(int l, int cult) {
	return texelFetch(culture_colors, ivec2(l, cult), 0).rgb;
}

int class_at(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(grid_size) - 1);
	return int(texelFetch(classes, c, 0).r * 255.0 + 0.5);
}

void fragment() {
	vec2 uv = (world_xz - origin) / world_size;
	vec2 g = uv * grid_size - 0.5;
	ivec2 c = ivec2(floor(g));
	vec2 f = fract(g);
	// Class weights, bilinear over the four cells around the pixel.
	float wf = 0.0; float wm = 0.0; float wh = 0.0; float wp = 0.0; float ww = 0.0;
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k & 1, k >> 1);
		float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
		int cl = class_at(c + o);
		wf += cl == class_forest ? w : 0.0;
		wm += cl == class_mountain ? w : 0.0;
		wh += cl == class_hills ? w : 0.0;
		wp += (cl == class_pass || cl == class_settlement) ? w : 0.0;
		ww += cl == class_water ? w : 0.0;
	}
	// The region's land: which cultures, and how far converted.
	// Looked up a noisy few metres away, so the border between two cultures' land frays organically
	// instead of following the region polygon's straight edges.
	vec2 fray = vec2(noise(world_xz * 0.035), noise(world_xz * 0.035 + 41.0)) - 0.5;
	fray += (vec2(noise(world_xz * 0.13 + 7.0), noise(world_xz * 0.13 + 19.0)) - 0.5) * 0.4;
	ivec2 cc = clamp(ivec2(floor(g + 0.5 + fray * 14.0)), ivec2(0), ivec2(grid_size) - 1);
	vec4 r = texelFetch(regions, cc, 0);
	int id = int(r.r * 255.0 + 0.5) + 256 * int(r.g * 255.0 + 0.5);
	vec4 pal = texelFetch(palette, ivec2(max(id, 0), 0), 0);
	int from_c = int(pal.r * 255.0 + 0.5);
	int to_c = int(pal.g * 255.0 + 0.5);
	float patch = noise(world_xz * 0.045) * 0.75 + noise(world_xz * 0.21) * 0.25;
	float conv = smoothstep(patch - 0.08, patch + 0.08, pal.b);

	// Per-pixel normal from the heightfield (finer than the mesh at a distance), slope and cavity.
	// Four samples 2.5 m away give both the normal and the cavity (height above its surroundings).
	float e = 2.5;
	float h = world_h;
	float hxp = h_at(world_xz + vec2(e, 0.0));
	float hxm = h_at(world_xz - vec2(e, 0.0));
	float hzp = h_at(world_xz + vec2(0.0, e));
	float hzm = h_at(world_xz - vec2(0.0, e));
	float hx = hxp - hxm;
	float hz = hzp - hzm;
	vec3 n = normalize(vec3(-hx, 2.0 * e, -hz));
	float slope = length(vec2(hx, hz)) / (2.0 * e); // rise per metre
	float cavity = clamp((h - (hxp + hxm + hzp + hzm) * 0.25) * 0.3, -1.0, 1.0);
	// Larger folds (12 m): ridges and gullies of the massifs read as lumpy rock.
	float macro = h - (h_at(world_xz + vec2(12.0, 0.0)) + h_at(world_xz - vec2(12.0, 0.0)) + h_at(world_xz + vec2(0.0, 12.0)) + h_at(world_xz - vec2(0.0, 12.0))) * 0.25;
	cavity = clamp(cavity + macro * 0.12, -1.0, 1.0);

	float n1 = noise(world_xz * 0.012) * 0.65 + noise(world_xz * 0.031) * 0.35; // large patches
	float n2 = fbm(world_xz * 0.09);    // medium mottling
	float n3 = noise(world_xz * 0.55);  // fine grain
	float strata = noise(vec2(world_xz.x * 0.04 + world_xz.y * 0.03, h * 0.9));
	float cr = wf > 0.0 ? crowns(world_xz * 0.26) : 0.0;

	// Layer weights (independent of culture).
	// Rock: steep ground, and most of the massifs above the hills (TW: ranges are rock with forest
	// in the valleys), broken up by noise and kept off the gullies.
	float high = smoothstep(16.0, 34.0, h + (n2 - 0.5) * 14.0);
	float w_rock = clamp(smoothstep(0.5, 0.95, slope + (n2 - 0.5) * 0.3) + wm * 0.55 + high * (0.55 + 0.4 * n3) - max(-cavity, 0.0) * 0.25, 0.0, 1.0) * (1.0 - wf * 0.7);
	float w_scree = smoothstep(0.22, 0.5, slope) * (1.0 - w_rock) * clamp(wh + wm, 0.0, 1.0);
	float w_dry = smoothstep(0.45, 0.72, n1 + (n2 - 0.5) * 0.25);
	float w_dirt = wp * (0.55 + 0.3 * n2);
	float riv = smoothstep(0.32, 0.52, texture(rivers, uv).r) * (1.0 - ww);
	float bank = smoothstep(0.12, 0.32, texture(rivers, uv).r) * (1.0 - riv);
	float road = smoothstep(0.35, 0.65, texture(roads, uv).r * 255.0) * (1.0 - ww);
	float beach = (1.0 - smoothstep(0.4, 1.6, h - sea_level)) * (1.0 - wm);

	vec3 cols[2];
	cols[1] = vec3(0.0);
	// The second culture only where the land is converting (most regions are not).
	int passes = (to_c != from_c && conv > 0.001) ? 2 : 1;
	if (conv > 0.999) { from_c = to_c; passes = 1; conv = 0.0; }
	for (int s = 0; s < passes; s++) {
		int cu = s == 0 ? from_c : to_c;
		vec3 ground = mix(layer(GRASS, cu), layer(DRY, cu), w_dry);
		ground = mix(ground, layer(DIRT, cu), w_dirt);
		// Forest: the floor between crowns, the canopy on them (a carpet from afar).
		vec3 canopy = layer(CANOPY, cu) * (0.62 + 0.55 * cr) * (0.85 + 0.3 * n2);
		ground = mix(ground, mix(layer(FLOOR, cu), canopy, 0.35 + 0.65 * cr), wf);
		ground = mix(ground, layer(SCREE, cu) * (0.85 + 0.3 * n3), w_scree);
		vec3 rock = layer(ROCK, cu) * (0.68 + 0.45 * strata) * (0.85 + 0.3 * n3) * (0.8 + 0.4 * clamp(cavity + 0.5, 0.0, 1.0));
		ground = mix(ground, rock, w_rock);
		float snow_line = texelFetch(culture_params, ivec2(cu, 0), 0).r * 100.0;
		float w_snow = smoothstep(snow_line - 2.0, snow_line + 2.0, h + (n2 - 0.5) * 12.0 + cavity * 6.0) * (1.0 - smoothstep(0.7, 1.2, slope) * 0.8);
		ground = mix(ground, layer(SNOW, cu), w_snow);
		ground = mix(ground, layer(SAND, cu), beach * (1.0 - w_rock));
		ground = mix(ground, layer(DIRT, cu) * 0.9, road);
		ground = mix(ground, ground * 0.72, bank);
		ground = mix(ground, layer(WATER, cu), riv);
		cols[s] = ground;
	}
	vec3 col = passes == 2 ? mix(cols[0], cols[1], conv) : cols[0];
	// Mottling and cavity light: ridges catch light, hollows darken.
	col *= (0.88 + 0.24 * n2) * (0.96 + 0.08 * n3);
	col *= clamp(1.0 + cavity * 0.22, 0.72, 1.22);
	// Canopy relief: the crowns bulge (a tilt from the crown pattern's gradient).
	vec2 cg = vec2(dFdx(cr), dFdy(cr)) / max(vec2(length(dFdx(world_xz)), length(dFdy(world_xz))), vec2(0.01));
	n = normalize(n - vec3(cg.x, 0.0, cg.y) * 0.9 * wf * (1.0 - riv));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.18, riv);
	SPECULAR = mix(0.3, 0.6, riv);
}
