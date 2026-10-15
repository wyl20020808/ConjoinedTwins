shader_type spatial;
uniform vec4 wall_color:source_color=vec4(.72,.68,.55,1.0);
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float weather=sin(world.x*1.9+world.z*1.3)*sin(world.y*1.7+world.x*.4)*.04;
 float damp=(1.0-smoothstep(.15,1.7,world.y))*.22;
 ALBEDO=wall_color.rgb*(1.0+weather-damp);
 ROUGHNESS=.94;
}
