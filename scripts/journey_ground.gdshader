shader_type spatial;
render_mode cull_disabled;
uniform sampler2D stone : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform int chapter=0;
varying vec3 world;
void vertex(){ world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float noise2(vec2 p){return sin(p.x*.27+sin(p.y*.18))*sin(p.y*.11+p.x*.13)*.5+.5;}
void fragment(){
 float meters=-world.z;
 float land=smoothstep(220.0,420.0,meters);
 float village=smoothstep(1020.0,1250.0,meters);
 if(chapter==1){land=1.0;village=.7;} else if(chapter==2){land=.25;village=.05;}
 float natural=land*(1.0-village);
 float mottled=noise2(world.xz);
 float path=1.0-smoothstep(5.0+mottled,12.0+mottled,abs(world.x));
 // 中央是踩实的泥土，落叶留在路肩；稍偏低分辨率采样减轻远处细纹闪烁。
 vec3 paving=texture(stone,world.xz*.22,1.0).rgb*vec3(.87,.84,.76);
 vec3 leaves=texture(soil,world.xz*.22,1.5).rgb;
 vec3 dirt=mix(vec3(.24,.185,.12),leaves*vec3(.72,.62,.44),.36);
 vec3 litter=mix(leaves*vec3(.65,.72,.45),vec3(.16,.20,.095),.25);
 vec3 woodland=mix(litter,dirt,path);
 vec3 base=mix(paving,woodland,land);
 float verge=smoothstep(9.5,15.8,abs(world.x));
 vec3 village_road=mix(paving*.95,dirt,.22+mottled*.18);
 base=mix(base,mix(village_road,litter,verge*.65),village);
 float outside=smoothstep(15.8,16.4,abs(world.x));
 vec3 outside_color=mix(texture(rock,world.xz*.12,1.0).rgb*.6,litter,land);
 base=mix(base,outside_color,outside);
 float tracks=exp(-pow((abs(world.x)-2.4)*2.0,2.0))*land;
 float damp=smoothstep(.65,.81,noise2(world.xz*2.3))*natural*path;
 vec2 tile=abs(fract(world.xz*vec2(.7,.5))-.5);
 float seam=smoothstep(.46,.495,max(tile.x,tile.y))*(1.0-land*.8);
 // 林下宽缓的斑驳遮光与根部接触暗部配合，不增加全景动态阴影开销。
 float canopy=(.80+.20*noise2(world.xz*3.2))*natural+(1.0-natural);
 ALBEDO=base*(.94+mottled*.12)*(1.0-tracks*.12-damp*.18-seam*.13)*canopy;
 ROUGHNESS=mix(.93,.35,damp);
 AO=1.0-seam*.18-tracks*.08;
 vec3 detail=mix(texture(stone_normal,world.xz*.22,1.0).rgb,texture(soil_normal,world.xz*.22,1.5).rgb,land);
 vec3 n=normalize(vec3((detail.r-.5)*.35,1.0,(detail.g-.5)*.35));
 NORMAL=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
}
