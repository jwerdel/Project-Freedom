shader_type canvas_item;
// The strategic map's territory in one pass (ui/strategic_map.gd): the terrain base, each region's
// fill on the current layer and the borders, all looked up from a region-ID texture (one texel per
// raster cell, the index in RG) and a small palette (one column per region index):
//   row 0: fill colour (alpha = strength, 0 = none);  row 1: owner colour (alpha 1 = owned).
// Inside a region (the common case) it costs five ID lookups and one palette lookup.

uniform sampler2D ids : filter_nearest;
uniform sampler2D palette : filter_nearest;
uniform vec4 id_xform = vec4(1.0, 1.0, 0.0, 0.0); // map uv -> id uv: uv * xy + zw
uniform vec4 thin_color : source_color = vec4(0.2, 0.15, 0.1, 0.55);
uniform float owner_width = 2.0; // screen pixels

float id_at(vec2 uv) {
	vec2 q = uv * id_xform.xy + id_xform.zw;
	if (q.x < 0.0 || q.y < 0.0 || q.x >= 1.0 || q.y >= 1.0) return 0.0;
	vec4 t = texture(ids, q);
	return floor(t.r * 255.0 + 0.5) + floor(t.g * 255.0 + 0.5) * 256.0;
}

vec4 pal(float id, int row) {
	return texelFetch(palette, ivec2(int(id), row), 0);
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	vec2 px = vec2(abs(dFdx(UV.x)), abs(dFdy(UV.y))); // one screen pixel in uv
	float id = id_at(UV);
	vec4 f = pal(id, 0);
	col.rgb = mix(col.rgb, f.rgb, f.a);
	// Neighbours owner_width pixels away: any different region means a border is near.
	vec2 d = px * owner_width;
	float n0 = id_at(UV + vec2(d.x, 0.0));
	float n1 = id_at(UV - vec2(d.x, 0.0));
	float n2 = id_at(UV + vec2(0.0, d.y));
	float n3 = id_at(UV - vec2(0.0, d.y));
	if (n0 != id || n1 != id || n2 != id || n3 != id) {
		// Thin outline of every region (one pixel, where the right or lower neighbour differs).
		if (id_at(UV + vec2(px.x, 0.0)) != id || id_at(UV + vec2(0.0, px.y)) != id) {
			col.rgb = mix(col.rgb, thin_color.rgb, thin_color.a);
		}
		// Owned regions: a strong border in the owner's colour along any edge with another owner.
		vec4 own = pal(id, 1);
		if (own.a > 0.5 && (pal(n0, 1) != own || pal(n1, 1) != own || pal(n2, 1) != own || pal(n3, 1) != own)) {
			col.rgb = own.rgb;
		}
	}
	COLOR = col;
}
