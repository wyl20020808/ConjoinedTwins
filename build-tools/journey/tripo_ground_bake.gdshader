shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform sampler2D base_texture : source_color;
uniform sampler2D normal_texture : hint_normal;
uniform sampler2D rough_texture;
uniform float roughness_factor=1.0;
uniform bool packed_normal=false;
vec3 linear_from_srgb(vec3 c){
 return mix(c/12.92,pow((c+.055)/1.055,vec3(2.4)),step(vec3(.04045),c));
}
void fragment(){
 if(!packed_normal){ALBEDO=texture(base_texture,UV).rgb;}
 else{
  vec3 detail=texture(normal_texture,UV).xyz*2.0-1.0;
  vec3 view_normal=normalize(TANGENT*detail.x+BINORMAL*detail.y+NORMAL*detail.z);
  vec3 world_normal=normalize((INV_VIEW_MATRIX*vec4(view_normal,0.0)).xyz);
  float rough=max(.75,texture(rough_texture,UV).g*roughness_factor);
  ALBEDO=linear_from_srgb(vec3(world_normal.xz*.5+.5,rough));
 }
}
