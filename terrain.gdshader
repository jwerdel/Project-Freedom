shader_type spatial;
uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
// Territory overlay (visuals/terrain/territory_overlay.gd): faction tint and glowing borders.
uniform sampler2D territory_tint : source_color, filter_linear, repeat_disable;
uniform sampler2D territory_border : filter_linear, repeat_disable;
uniform vec4 territory_rect = vec4(-140.0,-140.0,280.0,280.0);
uniform float territory_on = 0.0;
varying vec3 world;
varying float slope;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;slope=1.0-NORMAL.y;}
void fragment(){
 vec3 g=texture(grass,world.xz*0.11).rgb;
 vec3 r=texture(rock,world.xz*0.14).rgb;
 vec3 s=texture(sand,world.xz*0.09).rgb;
 float high=smoothstep(10.0,25.0,world.y);
 float stony=clamp(slope*2.5+high*0.9,0.,1.);
 vec3 base=mix(g*vec3(0.40,0.68,0.39),r*vec3(0.70,0.79,0.84),stony);
 base=mix(s*0.86,base,smoothstep(0.5,3.0,world.y));
 float snow=smoothstep(30.,38.,world.y)*(1.-smoothstep(0.15,0.55,slope));
 vec3 albedo=mix(base,vec3(0.77,0.80,0.78),snow);
 vec2 tuv=(world.xz-territory_rect.xy)/territory_rect.zw;
 vec4 tint=texture(territory_tint,tuv);
 vec3 b=texture(territory_border,tuv).rgb;
 float land=smoothstep(-0.3,0.8,world.y)*territory_on;
 float glow=clamp(b.r+b.g*0.5+b.b*0.22,0.0,1.0)*land;
 albedo=mix(albedo,tint.rgb,tint.a*land);
 ALBEDO=mix(albedo,tint.rgb,glow*0.65);
 EMISSION=tint.rgb*glow*glow*1.4;
 ROUGHNESS=0.94;
 NORMAL_MAP=texture(grass_normal,world.xz*0.11).rgb;
 NORMAL_MAP_DEPTH=0.16;
}
