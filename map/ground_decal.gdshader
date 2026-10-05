shader_type spatial;
// Fields and roads draped over the terrain (map/sprawl_node.gd): vertex colour (linear) with furrows
// across fields (UV.x counts metres across the field; UV.y = 1 marks a road) and a little mottling.

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec3 c = COLOR.rgb;
	float road = step(0.5, UV2.y);
	float furrow = 0.86 + 0.14 * sin(UV2.x * 6.2831 * 1.6);
	c *= mix(furrow, 1.0, road) * (0.9 + 0.2 * noise(world_pos.xz * 0.7));
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
