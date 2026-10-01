shader_type spatial;
render_mode blend_mix, cull_back;
// Farmland patchwork. Per vertex: COLOR = crop color (linear) with alpha = open-land mask,
// CUSTOM0/CUSTOM1 = the field's four corners (world xz), CUSTOM2 = furrow dir xy, spacing, strength.
varying vec2 wpos;
varying vec4 c01;
varying vec4 c23;
varying vec4 furrow;
void vertex(){wpos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;c01=CUSTOM0;c23=CUSTOM1;furrow=CUSTOM2;}
float seg(vec2 p,vec2 a,vec2 b){vec2 pa=p-a;vec2 ba=b-a;float h=clamp(dot(pa,ba)/dot(ba,ba),0.0,1.0);return length(pa-ba*h);}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float vnoise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
 float d=min(min(seg(wpos,c01.xy,c01.zw),seg(wpos,c01.zw,c23.xy)),min(seg(wpos,c23.xy,c23.zw),seg(wpos,c23.zw,c01.xy)));
 // Furrows: anti-aliased stripes that fade out once they are finer than a pixel.
 float s=dot(wpos,vec2(-furrow.y,furrow.x))/furrow.z;
 float aa=clamp(1.6-fwidth(s)*2.2,0.0,1.0);
 float stripe=(0.5+0.5*cos(6.28318*s))*aa;
 vec3 col=COLOR.rgb;
 col*=0.88+0.16*vnoise(wpos*0.4)+0.08*vnoise(wpos*1.7);
 col*=1.0-furrow.w*0.30*stripe+furrow.w*0.08;
 // Grassy headland at the field margin, then a soft fade into the terrain.
 col=mix(col*vec3(0.80,0.92,0.72),col,smoothstep(0.0,0.9,d));
 ALBEDO=col;
 ROUGHNESS=0.95;
 ALPHA=smoothstep(0.0,0.5,d)*COLOR.a;
}
