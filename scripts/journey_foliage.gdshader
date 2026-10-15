shader_type spatial;
render_mode cull_disabled;
uniform float phase=0.0;
uniform vec4 tint:source_color=vec4(.22,.34,.12,1.0);
varying vec3 world;
void vertex(){
 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 VERTEX.x+=sin(phase*1.2+world.x*.12+world.z*.16)*min(1.0,VERTEX.y*.07)*.14;
}
void fragment(){
 float variation=.78+.12*sin(world.x*.31+world.z*.47+world.y*.6)+.14*clamp(world.y/14.0,0.0,1.0);
 ALBEDO=tint.rgb*variation;
 ROUGHNESS=.87;
 BACKLIGHT=tint.rgb*.22;
}
