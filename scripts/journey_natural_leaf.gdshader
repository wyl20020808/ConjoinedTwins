shader_type spatial;
render_mode cull_disabled;
uniform float phase=0.0;
varying vec3 world;
void vertex(){
 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 VERTEX.x+=sin(phase*1.2+world.x*.12+world.z*.16)*min(1.0,VERTEX.y*.07)*.09;
}
void fragment(){
 float tone=.86+.15*sin(world.x*.87+world.z*.59)+.12*clamp(world.y/14.,0.,1.);
 float spine=1.-smoothstep(.012,.042,abs(UV.x-.5));
 float veins=pow(max(0.,cos((UV.y-abs(UV.x-.5)*.6)*65.)),16.)*.12;
 ALBEDO=mix(vec3(.12,.235,.052)*tone,vec3(.27,.35,.09),spine*.28+veins);
 ROUGHNESS=.78;
 BACKLIGHT=vec3(.08,.12,.025);
}
