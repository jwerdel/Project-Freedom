shader_type canvas_item;
// The strategic map's territory in one pass (ui/strategic_map.gd): a painted parchment map (look
// after docs/reference/world/varos_map.jpg) with each region's fill on the current layer and the
// borders, looked up from a region-ID texture (one texel per raster cell, the index in RG) and a
// small palette (one column per region index):
//   row 0: fill colour (alpha = strength, 0 = none);  row 1: owner colour (alpha 1 = owned).
// Painting (ui/strategic_paint.gd): relief shading from heights, ground colours washed into the
// parchment, blue rivers, an inked coastline, a teal sea with ripple contour lines along the coast,
// paper grain. painted = false shows the plain class texture instead (debug: movement classes).

uniform sampler2D ids : filter_nearest;
uniform sampler2D palette : filter_nearest;
uniform vec4 id_xform = vec4(1.0, 1.0, 0.0, 0.0); // map uv -> id uv: uv * xy + zw
uniform vec4 thin_color : source_color = vec4(0.2, 0.15, 0.1, 0.45);
uniform float owner_width = 2.0; // screen pixels

uniform bool painted = true;
uniform float wash = 0.5; // how much of the ground colour shows through the parchment
uniform sampler2D heights : filter_linear;
uniform sampler2D biome : source_color, filter_linear;
uniform sampler2D rivers : filter_linear;
uniform sampler2D coast : filter_linear; // signed distance to the coast in cells, + land
uniform vec4 paint_xform = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 coast_xform = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 texel = vec2(0.004);
uniform float relief = 1.0;
uniform vec2 coast_texel = vec2(0.004);
uniform float coast_px = 0.3; // coast cells per screen pixel (set with the zoom)

const vec3 PARCHMENT = vec3(0.91, 0.84, 0.67);
const vec3 INK = vec3(0.20, 0.15, 0.11);
const vec3 SEA_DEEP = vec3(0.16, 0.30, 0.36);
const vec3 SEA_SHALLOW = vec3(0.40, 0.56, 0.56);
const vec3 RIVER = vec3(0.27, 0.46, 0.56);
const vec3 SNOW = vec3(0.95, 0.94, 0.90);

float id_at(vec2 uv) {
	vec2 q = uv * id_xform.xy + id_xform.zw;
	if (q.x < 0.0 || q.y < 0.0 || q.x >= 1.0 || q.y >= 1.0) return 0.0;
	vec4 t = texture(ids, q);
	return floor(t.r * 255.0 + 0.5) + floor(t.g * 255.0 + 0.5) * 256.0;
}

vec4 pal(float id, int row) {
	return texelFetch(palette, ivec2(int(id), row), 0);
}

// Palette rows 2 and 3 (ui/strategic_map.gd _write_palette): the owner's index and the marks.
uniform bool political = false;
uniform vec4 player_color : source_color = vec4(1.0);
float owner_of(float id) {
	vec4 t = pal(id, 2);
	return floor(t.r * 255.0 + 0.5) + 256.0 * floor(t.g * 255.0 + 0.5);
}
int marks_of(float id) {
	return int(pal(id, 2).b * 255.0 + 0.5);
}
// Land of another owner within d (uv) in eight directions (the sea does not count).
bool other_owner(vec2 uv, float oid, vec2 d) {
	for (int k = 0; k < 8; k++) {
		vec2 o = vec2(cos(float(k) * 0.785398), sin(float(k) * 0.785398)) * d;
		float n = id_at(uv + o);
		if (n > 0.0 && owner_of(n) != oid) return true;
	}
	return false;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float h_at(vec2 q) {
	return texture(heights, q).r;
}

vec3 paint(vec2 uv, out float land) {
	vec2 q = uv * paint_xform.xy + paint_xform.zw;
	vec2 cq = uv * coast_xform.xy + coast_xform.zw;
	// Nine taps soften the chamfer field's cell corners so coasts and contours run smooth.
	float sd = texture(coast, cq).r * 0.2;
	for (int k = 0; k < 8; k++) {
		vec2 o = vec2(cos(float(k) * 0.785), sin(float(k) * 0.785)) * coast_texel * 1.6;
		sd += texture(coast, cq + o).r * 0.1;
	}
	float px = max(coast_px, 1e-4); // cells per screen pixel (uniform: no derivative noise)
	float sdp = sd / px; // signed distance in screen pixels
	land = step(0.0, sd);
	// Paper: fine grain and broad, uneven tea stains.
	float grain = vnoise(uv * 900.0) * 0.5 + vnoise(uv * 2200.0) * 0.5;
	float stain = vnoise(uv * 7.0) * 0.6 + vnoise(uv * 19.0) * 0.4;
	vec3 col;
	if (sd >= 0.0) {
		vec3 ground = texture(biome, q).rgb;
		float g = dot(ground, vec3(0.333));
		ground = mix(vec3(g), ground, 0.75); // painted, not photographic
		col = mix(PARCHMENT, ground, wash);
		// Relief: light from the north-west.
		float h = h_at(q);
		float hx = h_at(q + vec2(texel.x, 0.0)) - h_at(q - vec2(texel.x, 0.0));
		float hz = h_at(q + vec2(0.0, texel.y)) - h_at(q - vec2(0.0, texel.y));
		float shade = clamp(0.5 - (hx + hz) * 9.0 * relief, 0.0, 1.0);
		col *= mix(0.72, 1.14, shade);
		col = mix(col, SNOW, smoothstep(0.84, 0.97, h) * 0.6);
		// Rivers: blue with a darker bank.
		float r = texture(rivers, q).r * 0.2;
		for (int k = 0; k < 8; k++) r += texture(rivers, q + vec2(cos(float(k) * 0.785), sin(float(k) * 0.785)) * texel * 1.3).r * 0.1;
		col = mix(col, RIVER * 0.7, smoothstep(0.22, 0.34, r) * 0.85);
		col = mix(col, RIVER, smoothstep(0.36, 0.5, r));
		// A pale beach band inside the coast.
		col = mix(col, vec3(0.93, 0.87, 0.70), (1.0 - smoothstep(1.0, 4.0, sdp)) * 0.55);
	} else {
		float d = -sdp;
		col = mix(SEA_DEEP, SEA_SHALLOW, exp(-d / 34.0));
		// Ripple contours following the coast (classic hand-drawn map).
		for (int k = 1; k <= 3; k++) {
			float at = float(k) * 6.5 + float(k * k) * 1.5;
			float line = 1.0 - smoothstep(0.35, 1.05, abs(d - at));
			col = mix(col, vec3(0.80, 0.86, 0.82), line * (0.55 - float(k) * 0.12));
		}
	}
	// The inked coastline.
	col = mix(col, INK, 1.0 - smoothstep(0.6, 1.5, abs(sdp)));
	col *= 0.95 + grain * 0.07;
	col *= 0.93 + stain * 0.1;
	return col;
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float land = 1.0;
	if (painted) col.rgb = paint(UV, land);
	vec2 px = vec2(abs(dFdx(UV.x)), abs(dFdy(UV.y))); // one screen pixel in uv
	float id = id_at(UV);
	vec4 f = pal(id, 0);
	// Watercolour fills on land only.
	col.rgb = mix(col.rgb, f.rgb, f.a * mix(1.0, 0.55, float(painted)) * land);
	vec4 own = pal(id, 1);
	float oid = owner_of(id);
	int marks = marks_of(id);
	vec4 pat = pal(id, 3);
	vec2 spx = UV / max(px, vec2(1e-6)); // screen pixels
	// Political marks: vassals striped in the liege's colour, occupied or besieged land hatched in the
	// occupier's colour, Caeloth stippled gold (its own neutral style).
	if (political && land > 0.5) {
		if ((marks & 2) != 0 && pat.a > 0.5 && fract((spx.x - spx.y) / 14.0) < 0.38) col.rgb = mix(col.rgb, pat.rgb, 0.62);
		if ((marks & 4) != 0 && pat.a > 0.5) {
			float hx = min(fract((spx.x + spx.y) / 7.0), fract((spx.x - spx.y) / 7.0));
			if (hx < 0.22) col.rgb = mix(col.rgb, pat.rgb * 0.85, 0.8);
		}
		if ((marks & 8) != 0 && fract(spx.x / 5.0) < 0.3 && fract(spx.y / 5.0) < 0.3) col.rgb = mix(col.rgb, vec3(0.78, 0.62, 0.24), 0.45);
	}
	// Neighbours owner_width pixels away: any different region means a border is near.
	vec2 d = px * owner_width;
	float n0 = id_at(UV + vec2(d.x, 0.0));
	float n1 = id_at(UV - vec2(d.x, 0.0));
	float n2 = id_at(UV + vec2(0.0, d.y));
	float n3 = id_at(UV - vec2(0.0, d.y));
	bool mine = (marks & 1) != 0;
	// The player's realm (political mode): a thick border in the player's colour and a glow band.
	if (political && mine && land > 0.5) {
		vec2 g = px * owner_width * 6.0;
		if (other_owner(UV, oid, g)) {
			col.rgb = mix(col.rgb, player_color.rgb, 0.35);
			if (other_owner(UV, oid, px * owner_width * 2.2)) col.rgb = mix(col.rgb, player_color.rgb * 0.8, 1.0);
		}
	}
	// Painted maps: a soft band of the owner's colour inside its border (TW-style glow).
	if (painted && own.a > 0.5 && !(political && mine)) {
		vec2 g = px * owner_width * 4.0;
		if (other_owner(UV, oid, g)) col.rgb = mix(col.rgb, own.rgb, 0.28 * land);
	}
	if (n0 != id || n1 != id || n2 != id || n3 != id) {
		// Thin outline of every region (one pixel, where the right or lower neighbour differs).
		if (id_at(UV + vec2(px.x, 0.0)) != id || id_at(UV + vec2(0.0, px.y)) != id) {
			col.rgb = mix(col.rgb, thin_color.rgb, thin_color.a * land);
		}
		// Owned regions: a strong border in the owner's colour along any edge with another owner.
		if (own.a > 0.5 && !(political && mine) && (owner_of(n0) != oid || owner_of(n1) != oid || owner_of(n2) != oid || owner_of(n3) != oid)) {
			col.rgb = mix(col.rgb, own.rgb, land);
		}
	}
	COLOR = col;
}
