shader_type spatial;
uniform vec4 water_color : source_color=vec4(0.075,0.24,0.28,1.);
varying vec3 world;
void vertex(){
 world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
 VERTEX.y+=sin(world.x*0.36+TIME*0.65)*0.06+cos(world.z*0.43+TIME*0.48)*0.045;
}
void fragment(){
 float waves=sin(world.x*0.8+world.z*1.4+TIME*0.7)*sin(world.z*1.9-world.x*0.6+TIME*0.5);
 ALBEDO=water_color.rgb+waves*0.014;
 NORMAL=normalize(NORMAL+vec3(cos(world.x*0.8+TIME)*0.045,0.,sin(world.z*1.4+TIME)*0.04));
 ROUGHNESS=0.24; METALLIC=0.25; SPECULAR=0.65;
}

