shader_type spatial;
// Edric Varn's body in the look test. The model came without its texture, so it is shaded as a god
// in dark blued steel: brushed metal broken up by noise, a gilded belt and collar, worn bright edges
// at grazing angles, and thin veins of golden light that flare while a punch charges (`power`).

uniform float height = 0.007; // model units, head top above the feet
uniform float foot = 0.0035;
uniform float power = 0.0;
uniform vec3 steel : source_color = vec3(0.16, 0.17, 0.2);
uniform vec3 gold : source_color = vec3(0.78, 0.58, 0.28);
uniform vec3 glow_color : source_color = vec3(1.0, 0.72, 0.35);

varying vec3 mpos;

void vertex() {
	mpos = VERTEX;
}

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 p = mpos / height; // about 0..1 over the body
	float hn = (mpos.y + foot) / height;
	float n = vnoise(p * 18.0) * 0.6 + vnoise(p * 55.0) * 0.4;
	float brushed = vnoise(vec3(p.x * 4.0, p.y * 140.0, p.z * 4.0));
	vec3 alb = steel * (0.75 + 0.5 * n);
	float rough = 0.32 + 0.25 * n + 0.1 * brushed;
	float metal = 0.92;
	// Gilded bands: belt and collar.
	float band = smoothstep(0.012, 0.0, abs(hn - 0.54)) + smoothstep(0.01, 0.0, abs(hn - 0.80));
	alb = mix(alb, gold * (0.8 + 0.3 * n), clamp(band, 0.0, 1.0));
	rough = mix(rough, 0.28, clamp(band, 0.0, 1.0));
	// Worn bright edges at grazing angles.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	alb += vec3(0.12, 0.13, 0.15) * rim * n;
	// Veins of light.
	float v = abs(vnoise(p * 9.0) - 0.5);
	float vein = smoothstep(0.018, 0.0, v) * (0.04 + power * 3.0);
	ALBEDO = alb;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = glow_color * vein * (0.6 + 0.4 * sin(TIME * 6.0 + hn * 20.0) * power);
}
