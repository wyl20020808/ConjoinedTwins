shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
varying vec2 footprint;
void vertex(){ footprint=UV*2.0-1.0; }
void fragment(){
 float fade=1.0-smoothstep(.18,1.0,length(footprint));
 ALBEDO=vec3(.055,.067,.048);
 ALPHA=fade*.27;
}
