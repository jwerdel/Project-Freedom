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
uniform sampler2D owners : filter_nearest, repeat_disable;      // per region (x = id): owner colour, alpha 1 = owned
uniform float border_width = 1.4; // metres (kept for older materials)
// Territory look (map/map_view.gd set_zoom_look): widths in metres at border_scale 1.
uniform float region_line = 0.6;
uniform float faction_line = 1.4;
uniform float player_line = 2.4;
uniform float border_scale = 1.0;
uniform float wash = 0.0;          // 0 close .. 1 at the farthest 3D zoom
uniform float wash_other = 0.24;   // wash strength at wash 1
uniform float wash_player = 0.34;
uniform vec4 player_color : source_color = vec4(1.0);
uniform sampler2D culture_colors : source_color, filter_nearest, repeat_disable; // x = ground layer, y = culture (sRGB)
uniform sampler2D culture_params : filter_nearest, repeat_disable; // x = culture: R snow line / 100 m
uniform sampler2D rivers : filter_linear, repeat_disable;       // R8 river strength
uniform sampler2D roads : filter_linear, repeat_disable;        // R8 road cells (0 or 1/255)
// Climate looks (map/pipeline.gd CLIMATE_LOOK, blurred): R snow cover, G frost, B dryness, A wetness.
uniform sampler2D climate : filter_linear, repeat_disable;
uniform bool has_climate = false;
// Winter (Part B, core/seasons.gd): 0 in summer, rising to 1 as the winter deepens; snow spreads from the
// north edge (north_band of the map) and dry lands get a dry season instead.
uniform float winter_snow = 0.0;
uniform float north_band = 0.45;
uniform vec2 climate_scale = vec2(1.0); // grid uv -> climate uv (its texels cover a few cells each)
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

// Region index at a world point (0 = none).
int region_id(vec2 xz) {
	ivec2 c = clamp(ivec2(floor((xz - origin) / world_size * grid_size)), ivec2(0), ivec2(grid_size) - 1);
	vec4 r = texelFetch(regions, c, 0);
	return int(r.r * 255.0 + 0.5) + 256 * int(r.g * 255.0 + 0.5);
}

// The owner of a region as an index (0 = none) and its flags (1 the player's, 2 highlighted).
float owner_id(int rid) {
	vec4 t = texelFetch(owners, ivec2(rid, 1), 0);
	return floor(t.r * 255.0 + 0.5) + 256.0 * floor(t.g * 255.0 + 0.5);
}
int owner_flags(int rid) {
	return int(texelFetch(owners, ivec2(rid, 1), 0).b * 255.0 + 0.5);
}
// Another owner within w metres (eight directions).
bool other_owner_within(vec2 xz, float oid, float w) {
	for (int k = 0; k < 8; k++) {
		vec2 d = vec2(cos(float(k) * 0.785398), sin(float(k) * 0.785398)) * w;
		int r = region_id(xz + d);
		if (r > 0 && owner_id(r) != oid) return true; // the sea (region 0) is not a border
	}
	return false;
}
// Another region within w metres (four directions).
bool region_within(vec2 xz, int rid, float w) {
	return region_id(xz + vec2(w, 0.0)) != rid || region_id(xz - vec2(w, 0.0)) != rid || region_id(xz + vec2(0.0, w)) != rid || region_id(xz - vec2(0.0, w)) != rid;
}

float h_at(vec2 xz) {
	return textureLod(heights, (xz - origin) / world_size, 0.0).r;
}

// Canopy depth (TW:WH3): beyond the 3D trees (map/map_view.gd TREE_RANGE) forest cells rise into a lumpy
// canopy carpet, so distant forests have volume instead of being flat paint.
uniform float canopy_height = 5.5;
uniform float canopy_fade_begin = 230.0;
uniform float canopy_fade_end = 320.0;

float vhash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(vhash(i), vhash(i + vec2(1, 0)), f.x), mix(vhash(i + vec2(0, 1)), vhash(i + vec2(1, 1)), f.x), f.y);
}

float forest_weight(vec2 xz) {
	vec2 g = (xz - origin) / world_size * grid_size - 0.5;
	ivec2 c = ivec2(floor(g));
	vec2 f = fract(g);
	float w = 0.0;
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k & 1, k >> 1);
		ivec2 cc = clamp(c + o, ivec2(0), ivec2(grid_size) - 1);
		int cl = int(texelFetch(classes, cc, 0).r * 255.0 + 0.5);
		w += (cl == class_forest ? 1.0 : 0.0) * (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
	}
	return w;
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
	float far = smoothstep(canopy_fade_begin, canopy_fade_end, distance(w, CAMERA_POSITION_WORLD));
	if (far > 0.0) {
		float fw = forest_weight(w.xz);
		VERTEX.y += canopy_height * fw * far * (0.7 + 0.6 * vnoise(w.xz * 0.11));
	}
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

	vec4 cl = has_climate ? texture(climate, uv * climate_scale) : vec4(0.0);
	if (winter_snow > 0.001) {
		float lat = clamp(uv.y, 0.0, 1.0);
		float wn = winter_snow * (1.0 - smoothstep(north_band * 0.7, north_band * 1.9, lat)) * (1.0 - clamp(cl.b * 1.4, 0.0, 1.0));
		cl.r = max(cl.r, wn * 0.95);
		cl.g = max(cl.g, wn);
		cl.b = clamp(cl.b * (1.0 + winter_snow * 0.6), 0.0, 1.0);
	}
	vec3 cols[2];
	cols[1] = vec3(0.0);
	// The second culture only where the land is converting (most regions are not).
	int passes = (to_c != from_c && conv > 0.001) ? 2 : 1;
	if (conv > 0.999) { from_c = to_c; passes = 1; conv = 0.0; }
	for (int s = 0; s < passes; s++) {
		int cu = s == 0 ? from_c : to_c;
		vec3 ground = mix(layer(GRASS, cu), layer(DRY, cu), clamp(w_dry + cl.b * 0.8, 0.0, 1.0));
		ground = mix(ground, layer(DIRT, cu), w_dirt);
		// Forest: the floor between crowns, the canopy on them (a carpet from afar).
		vec3 canopy = layer(CANOPY, cu) * (0.62 + 0.55 * cr) * (0.85 + 0.3 * n2);
		canopy = mix(canopy, layer(SNOW, cu) * 0.92, clamp(cl.r * 0.75 * (0.35 + 0.65 * cr), 0.0, 0.8)); // snow on the crowns
		ground = mix(ground, mix(layer(FLOOR, cu), canopy, 0.35 + 0.65 * cr), wf);
		ground = mix(ground, layer(SCREE, cu) * (0.85 + 0.3 * n3), w_scree);
		vec3 rock = layer(ROCK, cu) * (0.68 + 0.45 * strata) * (0.85 + 0.3 * n3) * (0.8 + 0.4 * clamp(cavity + 0.5, 0.0, 1.0));
		ground = mix(ground, rock, w_rock);
		float snow_line = texelFetch(culture_params, ivec2(cu, 0), 0).r * 100.0 - cl.g * 60.0; // frost brings the snow line down
		float w_snow = smoothstep(snow_line - 2.0, snow_line + 2.0, h + (n2 - 0.5) * 12.0 + cavity * 6.0) * (1.0 - smoothstep(0.7, 1.2, slope) * 0.8);
		ground = mix(ground, layer(SNOW, cu), w_snow);
		// Climate: frost greys and cools the ground; snow lies on open land, thinning on slopes and in
		// hollows in noisy drifts; wet land darkens.
		if (has_climate || winter_snow > 0.001) {
			float lum = dot(ground, vec3(0.333));
			ground = mix(ground, mix(vec3(lum), vec3(0.80, 0.87, 0.93), 0.4), cl.g * 0.45);
			float cover = smoothstep(0.22, 0.72, cl.r + (n2 - 0.5) * 0.45 + (n1 - 0.5) * 0.25 + max(cavity, 0.0) * 0.25 - max(slope - 0.55, 0.0) * 0.9) * (1.0 - wf * 0.55);
			// Snow keeps the land's relief: blue-grey in hollows and on shaded folds, drifts by noise.
			vec3 snow = layer(SNOW, cu) * (0.8 + 0.12 * n2 + 0.08 * n3) * clamp(1.0 + cavity * 0.55, 0.72, 1.06);
			snow = mix(snow, snow * vec3(0.86, 0.9, 1.0), clamp(-cavity * 1.5 + (1.0 - n1) * 0.3, 0.0, 1.0));
			ground = mix(ground, snow, cover * 0.92);
			ground *= 1.0 - cl.a * 0.16;
			ground = mix(ground, ground * vec3(0.92, 1.0, 0.86), cl.a * 0.4);
		}
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
	// Sculpted rock: a screen-space bump from a two-scale rock noise, so cliffs read as carved masses.
	float rn = fbm(world_xz * 0.16 + vec2(h * 0.08)) + 0.5 * noise(world_xz * 0.7 + vec2(h * 0.3));
	vec2 rg = vec2(dFdx(rn), dFdy(rn)) / max(vec2(length(dFdx(world_xz)), length(dFdy(world_xz))), vec2(0.01));
	n = normalize(n - vec3(rg.x, 0.0, rg.y) * 2.2 * w_rock);
	col *= mix(1.0, 0.82 + 0.36 * rn, w_rock * 0.6);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// Territory (TW:WH3; owner 2026-10-06: "painfully obvious which land is mine at every zoom"):
	//  - a faction-colour wash over owned land, none up close, rising with the zoom (wash 0-1), the
	//    player's own land stronger and a highlighted faction (hovered settlement or army) stronger still;
	//  - a thin line between regions, a thicker line in the owner's colour between factions, and the
	//    player's realm border thickest in the player's colour with a soft glow band inside it.
	// Widths are metres times border_scale, which grows with the camera distance (map/map_view.gd).
	int rid = region_id(world_xz);
	if (rid > 0 && ww < 0.5) {
		vec4 own = texelFetch(owners, ivec2(rid, 0), 0);
		float oid = owner_id(rid);
		int flags = owner_flags(rid);
		bool mine = (flags & 1) != 0;
		bool lit = (flags & 2) != 0;
		if (own.a > 0.5) {
			float wa = wash * (mine ? wash_player : wash_other) + (lit ? 0.22 + 0.12 * wash : 0.0);
			col = mix(col, own.rgb, clamp(wa, 0.0, 0.6));
		}
		float bs = border_scale;
		float wr = region_line * bs;
		float wf = faction_line * bs;
		float wp = player_line * bs;
		float reach = mine ? wp * 4.0 : wf;
		// Cheap test first: nothing different within reach -> no border work.
		if (region_id(world_xz + vec2(reach, 0.0)) != rid || region_id(world_xz - vec2(reach, 0.0)) != rid || region_id(world_xz + vec2(0.0, reach)) != rid || region_id(world_xz - vec2(0.0, reach)) != rid
			|| region_id(world_xz + vec2(reach, reach) * 0.7) != rid || region_id(world_xz - vec2(reach, reach) * 0.7) != rid) {
			if (mine && other_owner_within(world_xz, oid, wp * 4.0)) {
				col = mix(col, player_color.rgb, 0.3); // the glow band inside the realm
				if (other_owner_within(world_xz, oid, wp)) col = mix(col, player_color.rgb * 1.25 + 0.06, 0.95);
			} else if (own.a > 0.5 && other_owner_within(world_xz, oid, wf)) {
				col = mix(col, own.rgb * 1.2, 0.85);
			} else if (region_within(world_xz, rid, wr)) {
				col *= 0.78;
			}
		}
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.18, riv);
	SPECULAR = mix(0.3, 0.6, riv);
}
