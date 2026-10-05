shader_type spatial;
// Pipeline-map terrain (docs/map-pipeline-design.md §4.3, Addendum A.4). Every chunk shares this
// material and a flat grid mesh: vertices are displaced from the heightfield texture, normals come
// from it too, and the colour is each culture's palette for the terrain class at that cell
// (data/cultures.json). Land conversion: each region's palette texel holds the culture its land is
// turning from, the culture it is turning into and how far (0-1); the two are blended in noise
// patches so the new look spreads unevenly. Shroud and territory tint plug in here later.

uniform sampler2D heights : filter_linear, repeat_disable;      // R32F, metres
uniform sampler2D classes : filter_nearest, repeat_disable;     // R8: data/movement.json class index
uniform sampler2D regions : filter_nearest, repeat_disable;     // RGBA8: region id = R + 256 G (0 = none)
uniform sampler2D palette : filter_nearest, repeat_disable;     // per region (x = id): R from, G to, B value
uniform sampler2D culture_colors : filter_nearest, repeat_disable; // x = class (8), y = culture
uniform vec2 origin;      // world x/z of the grid's corner
uniform vec2 world_size;  // metres covered by the textures
uniform vec2 grid_size;   // cells
uniform float region_count = 1.0;
uniform float culture_count = 1.0;
uniform float sea_level = 0.0;

varying vec2 world_xz;

float h_at(vec2 xz) {
	return textureLod(heights, (xz - origin) / world_size, 0.0).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_xz = w.xz;
	VERTEX.y = h_at(w.xz);
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

// The colour of one grid cell: its class in the cultures its region's land is made of.
vec3 cell_color(ivec2 c, float patch) {
	c = clamp(c, ivec2(0), ivec2(grid_size) - 1);
	int cls = int(texelFetch(classes, c, 0).r * 255.0 + 0.5);
	vec4 r = texelFetch(regions, c, 0);
	int id = int(r.r * 255.0 + 0.5) + 256 * int(r.g * 255.0 + 0.5);
	vec4 pal = texelFetch(palette, ivec2(max(id, 0), 0), 0);
	int from_c = int(pal.r * 255.0 + 0.5);
	int to_c = int(pal.g * 255.0 + 0.5);
	float v = pal.b;
	vec3 a = texelFetch(culture_colors, ivec2(cls, from_c), 0).rgb;
	vec3 b = texelFetch(culture_colors, ivec2(cls, to_c), 0).rgb;
	// Converted where the patch noise is below the conversion value: patches grow as it rises.
	float t = smoothstep(patch - 0.08, patch + 0.08, v);
	return mix(a, b, t);
}

void fragment() {
	vec2 g = (world_xz - origin) / world_size * grid_size - 0.5;
	ivec2 c = ivec2(floor(g));
	vec2 f = fract(g);
	float patch = noise(world_xz * 0.045) * 0.75 + noise(world_xz * 0.21) * 0.25;
	vec3 col = mix(mix(cell_color(c, patch), cell_color(c + ivec2(1, 0), patch), f.x),
		mix(cell_color(c + ivec2(0, 1), patch), cell_color(c + ivec2(1, 1), patch), f.x), f.y);
	// Gentle variation so large plains do not read as flat paint.
	col *= 0.9 + 0.2 * noise(world_xz * 0.12);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
