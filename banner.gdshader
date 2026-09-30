shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color=vec4(0.09,0.26,0.27,1.);
void vertex(){VERTEX.z+=sin(UV.x*5.0+TIME*2.2+VERTEX.y)*0.15*UV.x;}
void fragment(){ALBEDO=tint.rgb*(0.9+sin(UV.x*60.)*0.025);ROUGHNESS=0.95;}

