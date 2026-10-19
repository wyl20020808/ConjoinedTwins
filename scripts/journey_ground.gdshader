shader_type spatial;
render_mode cull_disabled;
uniform sampler2D stone : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap, repeat_enable;
// 从三件 Tripo 模型顶视烘焙，颜色与世界 X/Z 法线、粗糙度分开保存。
uniform sampler2D paving_color : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D paving_detail : filter_linear_mipmap_anisotropic;
uniform sampler2D cobbles_color : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D cobbles_detail : filter_linear_mipmap_anisotropic;
uniform sampler2D mud_color : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D mud_detail : filter_linear_mipmap_anisotropic;
uniform int chapter=0;
uniform int road_region=-1;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float noise2(vec2 p){return sin(p.x*.27+sin(p.y*.18))*sin(p.y*.11+p.x*.13)*.5+.5;}
vec2 mirrored(vec2 p){return 1.0-abs(fract(p*.5)*2.0-1.0);}
vec3 surface_color(sampler2D tex,vec2 tile,float weight){
 return mix(texture(tex,mirrored(tile)).rgb,texture(tex,mirrored(tile+vec2(5.731,3.281))).rgb,weight);
}
vec3 surface_detail(sampler2D tex,vec2 tile,float weight){
 vec2 other=tile+vec2(5.731,3.281);
 vec3 a=texture(tex,mirrored(tile)).rgb;
 vec3 b=texture(tex,mirrored(other)).rgb;
 a.rg=(a.rg*2.0-1.0)*(1.0-2.0*mod(floor(tile),2.0));
 b.rg=(b.rg*2.0-1.0)*(1.0-2.0*mod(floor(other),2.0));
 return mix(a,b,weight);
}
void fragment(){
 float meters=-world.z;
 float land=smoothstep(220.0,420.0,meters);
 float village=smoothstep(1020.0,1250.0,meters);
 if(chapter==1){land=1.0;village=.7;}else if(chapter==2){land=.25;village=.05;}
 if(road_region>=0){land=road_region==1?1.0:0.0;village=road_region==2?1.0:0.0;}
 float natural=land*(1.0-village);
 float mottled=noise2(world.xz);
 // 镜像重复使每个接边采到相同边缘；法线分量随镜像同步翻转。
 vec2 tile=world.xz/vec2(2.0,4.0)+vec2(.371,.197);
 float variation=smoothstep(.3,.7,noise2(world.xz*.9));
 vec3 flag=surface_color(paving_color,tile,variation)*vec3(.88,.9,.93);
 vec3 cobble=surface_color(cobbles_color,tile,variation)*vec3(.9,.93,.95);
 vec3 mud=surface_color(mud_color,tile,variation)*vec3(.62,.59,.53);
 flag=mix(flag,vec3(dot(flag,vec3(.299,.587,.114))),.3);
 cobble=mix(cobble,vec3(dot(cobble,vec3(.299,.587,.114))),.25);
 vec3 road=mix(mix(flag,mud,land),cobble,village);
 vec3 detail=mix(mix(surface_detail(paving_detail,tile,variation),surface_detail(mud_detail,tile,variation),land),surface_detail(cobbles_detail,tile,variation),village);
 vec3 leaves=texture(soil,world.xz*.22,1.5).rgb;
 vec3 dirt=mix(mud,leaves*vec3(.54,.50,.39),.35);
 vec3 litter=mix(leaves*vec3(.65,.72,.45),vec3(.16,.20,.095),.25);
 // 连续铺装延伸到路缘；最后两米逐渐混入土壤与落叶，不出现独立方块。
 float verge=smoothstep(12.8+mottled*.6,16.0,abs(world.x));
 vec3 base=mix(road,mix(dirt,litter,natural*.5),verge*.85);
 float tracks=exp(-pow((abs(world.x)-2.4)*2.0,2.0))*natural;
 float damp=smoothstep(.65,.81,noise2(world.xz*2.3))*natural;
 float canopy=(.84+.16*noise2(world.xz*3.2))*natural+(1.0-natural);
 base*=.92+mottled*.14;
 base*=canopy*(1.0-tracks*.18-damp*.1);
 float outside=smoothstep(15.8,16.4,abs(world.x));
 vec3 outside_color=mix(texture(rock,world.xz*.12,1.0).rgb*.6,litter,land);
 ALBEDO=mix(base,outside_color,outside);
 ROUGHNESS=mix(clamp(detail.b,.75,.98),.94,outside);
 AO=1.0-tracks*.08;
 vec2 slopes=detail.rg*.7*(1.0-verge*.6);
 vec3 n=normalize(vec3(slopes.x,sqrt(max(.1,1.0-dot(slopes,slopes))),slopes.y));
 vec3 terrain_detail=mix(texture(stone_normal,world.xz*.22,1.0).rgb,texture(soil_normal,world.xz*.22,1.5).rgb,land);
 vec3 terrain_n=normalize(vec3((terrain_detail.r-.5)*.35,1.0,(terrain_detail.g-.5)*.35));
 NORMAL=normalize((VIEW_MATRIX*vec4(normalize(mix(n,terrain_n,outside)),0.0)).xyz);
}
