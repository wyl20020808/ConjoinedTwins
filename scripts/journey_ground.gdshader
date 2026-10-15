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
 float path=1.0-smoothstep(4.0+mottled*1.3,9.5+mottled*2.0,abs(world.x));
 vec3 paving=texture(stone,world.xz*.25).rgb*vec3(.78,.75,.69);
 vec3 leaves=texture(soil,world.xz*.3).rgb;
 vec3 dirt=leaves*vec3(.83,.67,.48);
 vec3 woodland=mix(leaves*vec3(.66,.76,.53),dirt,path*.84);
 vec3 base=mix(paving,woodland,land);
 float worn=smoothstep(.25,.72,mottled)*smoothstep(8.0,17.0,abs(world.x));
 base=mix(base,mix(paving*.9,leaves,.35),village*(1.0-worn*.6));
 // 山脊石板在林缘被落叶逐渐覆盖；林中与两侧土地使用同一世界坐标贴图。
 float outside=smoothstep(15.8,16.4,abs(world.x));
 vec3 outside_color=mix(texture(rock,world.xz*.12).rgb*.6,leaves*vec3(.72,.84,.62),land);
 base=mix(base,outside_color,outside);
 // 车辙、潮湿土斑与细碎铺石缝提供近景材质层次，远处仍保持低对比。
 float tracks=exp(-pow((abs(world.x)-2.4)*2.5,2.0))*land;
 float damp=smoothstep(.57,.82,noise2(world.xz*2.8))*natural*path;
 vec2 tile=abs(fract(world.xz*vec2(.7,.5))-.5);
 float seam=smoothstep(.46,.495,max(tile.x,tile.y))*(1.0-land*.8);
 ALBEDO=base*(.95+mottled*.16)*(1.0-tracks*.16-damp*.12-seam*.18);
 ROUGHNESS=mix(.93,.62,damp);
 AO=1.0-seam*.24-tracks*.12;
 vec3 detail=mix(texture(stone_normal,world.xz*.25).rgb,texture(soil_normal,world.xz*.3).rgb,land);
 // 地面法线以世界 X/Z 为切线，避免不同区块三角形的 UV 切线不一致。
 vec3 n=normalize(vec3((detail.r-.5)*.5,1.0,(detail.g-.5)*.5));
 NORMAL=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
}
