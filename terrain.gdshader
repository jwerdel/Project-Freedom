shader_type spatial;
uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
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
 ALBEDO=mix(base,vec3(0.77,0.80,0.78),snow);
 ROUGHNESS=0.94;
 NORMAL_MAP=texture(grass_normal,world.xz*0.11).rgb;
 NORMAL_MAP_DEPTH=0.16;
}
