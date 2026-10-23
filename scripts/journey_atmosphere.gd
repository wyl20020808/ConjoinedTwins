extends RefCounted
# 桌面 Forward+ 画质层：现代色调映射、屏幕空间遮蔽/间接光、体积雾、软阴影，
# 以及跟随镜头的远景地平线（低地环带 + 两层远山剪影），遮住地图边缘。
# 网页与移动端仍走 Compatibility，本层只保留地平线，不开启高开销后期。
const Landscape = preload("res://scripts/journey_landscape.gd")
const SkyShader = preload("res://scripts/journey_sky.gdshader")
const RING_INNER := 118.0
const RING_OUTER := 2400.0
const SEGMENTS := 72
# AgX 压高光更柔，直射光与天空环境光按此倍率补回亮度。
const SUN_SCALE := 1.6
const AMBIENT_SCALE := 1.15
var enabled := false
var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var horizon: Node3D
var ground_material: StandardMaterial3D
var near_ridge: StandardMaterial3D
var far_ridge: StandardMaterial3D
var sky_material: ShaderMaterial
# 每章一个时段：森林清晨逆光（林间光柱）、村庄与河岸黄昏（低角度长影）、矿道与设施夜晚（月光 + 火光）。
# 黄昏主光放在镜头侧后方（顺光）：逆光会让机关朝镜头一面整体落在背光里，与红褐路面糊成一片。
# energy 已包含 AgX 的亮度补偿；pitch/yaw 是主光朝向，yaw≈180 为正对镜头逆光。
# lamp 是路灯/火把与角色随身灯的亮度系数，stars 为夜空星点。
var palettes := [
	{"sun":Color("ffe2b9"),"energy":2.1,"pitch":-24.0,"yaw":152.0,"fill":Color("91b4ca"),"fill_energy":0.58,"fog":Color("b4ae95"),"fog_scale":0.85,"vol_scale":1.45,"anisotropy":0.72,"contrast":1.10,"saturation":1.06,"ambient":0.65,"ambient_color":Color("98a9a6"),
		"sky_zenith":Color("2f5c78"),"sky_low":Color("6f93a6"),"sky_horizon":Color("efd6a6"),"cloud_lit":Color("fff2dc"),"cloud_shadow":Color("6a7378"),"cloud":0.40,"haze":0.45,"sky_saturation":1.0,"cloud_scale":1.1,
		"lamp":0.0,"stars":0.0,"disk":0.99972,"sky_sun":0.85,"hero_light":0.0,"land_tint":Color(1,1,1)},
	{"sun":Color("ffa262"),"energy":2.15,"pitch":-17.0,"yaw":-38.0,"fill":Color("6c7fb8"),"fill_energy":0.38,"fog":Color("c99f84"),"fog_scale":0.85,"vol_scale":1.2,"anisotropy":0.65,"contrast":1.16,"saturation":1.16,"ambient":0.50,"ambient_color":Color("9a8080"),
		"sky_zenith":Color("33507e"),"sky_low":Color("8a95b8"),"sky_horizon":Color("ffb27a"),"cloud_lit":Color("ffcf9e"),"cloud_shadow":Color("7a6274"),"cloud":0.42,"haze":0.40,"sky_saturation":1.08,"cloud_scale":0.9,
		"lamp":0.8,"stars":0.0,"disk":0.99965,"sky_sun":1.0,"hero_light":0.0,"land_tint":Color("e8b8a0")},
	{"sun":Color("a8c0ea"),"energy":0.62,"pitch":-36.0,"yaw":205.0,"fill":Color("39558c"),"fill_energy":0.30,"fog":Color("27324a"),"fog_scale":0.9,"vol_scale":1.4,"anisotropy":0.5,"contrast":1.12,"saturation":1.02,"ambient":0.42,"ambient_color":Color("40527a"),
		"sky_zenith":Color("05080f"),"sky_low":Color("0e1729"),"sky_horizon":Color("2a3654"),"cloud_lit":Color("53627e"),"cloud_shadow":Color("10151f"),"cloud":0.32,"haze":0.30,"sky_saturation":1.0,"cloud_scale":0.8,
		"lamp":1.0,"stars":1.0,"disk":0.99935,"sky_sun":1.6,"hero_light":1.0,"land_tint":Color("27304a")},
]

func palette_for(chapter:int) -> Dictionary:
	return palettes[clampi(chapter,0,palettes.size()-1)]

# 路灯与随身灯亮度：网页/移动端没有本层调色，也按章节给出同一时段。
func lamp_level(chapter:int) -> float:
	return float(palette_for(chapter).lamp)

static func forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method()=="forward_plus"

func _init(parent:Node3D,environment:Environment,light:DirectionalLight3D,camera:Camera3D) -> void:
	env=environment;sun=light
	enabled=forward_plus()
	build_horizon(parent)
	if not enabled:return
	env.tonemap_mode=Environment.TONE_MAPPER_AGX
	env.tonemap_exposure=1.0
	# 程序化天空只负责背景与太阳；环境光改用每章固定色，章节切换时无需重算辐照度。
	var sky:=Sky.new()
	sky.radiance_size=Sky.RADIANCE_SIZE_32
	sky.process_mode=Sky.PROCESS_MODE_QUALITY
	sky_material=ShaderMaterial.new()
	sky_material.shader=SkyShader
	sky.sky_material=sky_material
	env.sky=sky
	env.sky_rotation=Vector3.ZERO
	# 太阳由天空着色器绘制，主光不再写入天空辐照度。
	sun.sky_mode=DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("7f9496")
	env.ambient_light_energy=0.62
	# 冷色补光只提阴影，不投影、不进入天空辐照度；主光仍然决定画面方向。
	fill=DirectionalLight3D.new()
	fill.name="FillLight"
	fill.rotation_degrees=Vector3(-18,300,0)
	fill.light_color=Color("6f9ec6")
	fill.light_energy=0.30
	fill.shadow_enabled=false
	fill.light_volumetric_fog_energy=0.0
	fill.sky_mode=DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	parent.add_child(fill)
	env.ssao_enabled=true
	env.ssao_radius=1.4;env.ssao_intensity=2.6;env.ssao_power=1.6
	env.ssao_detail=0.6;env.ssao_light_affect=0.25
	# 低档半分辨率 SSAO：1080p 实测省约 2–3 毫秒，近景接触暗部基本不变。
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW,true,0.5,2,50.0,300.0)
	# SSIL 实测森林段约 1 毫秒，只提很轻的间接色；为 60 帧余量关闭，保留 SSAO。
	env.ssil_enabled=false
	# 发光改为 Screen 混合：只有 HDR 超过 1 的灯芯、火焰、能量体会晕开，暗部不被整体抬灰。
	env.glow_enabled=true
	env.glow_intensity=0.75;env.glow_strength=1.0;env.glow_bloom=0.0
	env.glow_hdr_threshold=1.0;env.glow_hdr_scale=2.2
	env.glow_blend_mode=Environment.GLOW_BLEND_MODE_SCREEN
	for level in range(7):env.set_glow_level(level,level in [2,3,4,5])
	# 远处雾色取自同方向天空，地平线与晚霞自然衔接。
	env.fog_enabled=false
	env.fog_aerial_perspective=0.0
	env.volumetric_fog_enabled=false
	env.volumetric_fog_length=96.0
	env.volumetric_fog_anisotropy=0.55
	env.volumetric_fog_ambient_inject=0.15
	env.volumetric_fog_sky_affect=0.0
	env.adjustment_enabled=true
	env.adjustment_contrast=1.18;env.adjustment_saturation=1.16
	# 软化用固定模糊而非 PCSS 角直径，避免影子边缘出现采样颗粒。
	sun.light_volumetric_fog_energy=1.4
	sun.shadow_blur=1.8
	# 远景环带需要更远的裁剪面；区块加载窗口不变，不增加实际模型数量。
	camera.far=2600.0
	# 远景景深（0.05 强度）在 1080p 约占 3 毫秒、画面几乎看不出，改由距离雾与大气透视表现纵深。

func build_horizon(parent:Node3D) -> void:
	horizon=Node3D.new();horizon.name="Horizon"
	parent.add_child(horizon)
	ground_material=StandardMaterial3D.new()
	ground_material.roughness=1.0
	# 远处原野：世界坐标三平面采样一张大尺度噪声色块，像田块与林斑；环带随镜头平移时纹理不跟着走。
	var noise:=FastNoiseLite.new();noise.noise_type=FastNoiseLite.TYPE_CELLULAR;noise.frequency=0.02;noise.seed=7
	var ramp:=Gradient.new()
	ramp.set_color(0,Color(0.72,0.74,0.62));ramp.set_color(1,Color(1.12,1.08,0.92))
	ramp.add_point(0.5,Color(0.9,0.95,0.82))
	var fields:=NoiseTexture2D.new();fields.width=512;fields.height=512;fields.seamless=true
	fields.noise=noise;fields.color_ramp=ramp
	ground_material.albedo_texture=fields
	ground_material.uv1_world_triplanar=true;ground_material.uv1_triplanar=true
	ground_material.uv1_scale=Vector3.ONE*0.004
	var ground:=MeshInstance3D.new();ground.name="HorizonGround"
	ground.mesh=ring_mesh();ground.material_override=ground_material
	ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	horizon.add_child(ground)
	near_ridge=ridge_material()
	far_ridge=ridge_material()
	horizon.add_child(ridge("NearRidge",640.0,90.0,near_ridge,3))
	horizon.add_child(ridge("FarRidge",1150.0,170.0,far_ridge,7))
	horizon.add_child(ridge("Foothills",370.0,38.0,near_ridge,11))

func ring_mesh() -> ArrayMesh:
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for i in range(SEGMENTS):
		var a:=TAU*i/SEGMENTS;var b:=TAU*(i+1)/SEGMENTS
		var p0:=Vector3(cos(a),0,sin(a));var p1:=Vector3(cos(b),0,sin(b))
		for v in [p0*RING_INNER,p0*RING_OUTER,p1*RING_OUTER,p0*RING_INNER,p1*RING_OUTER,p1*RING_INNER]:
			tool.add_vertex(v)
	return tool.commit()

func ridge_material() -> StandardMaterial3D:
	# 远山不受距离雾吞没：自带大气透视色，底部融进地平线。
	var mat:=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo=true
	mat.disable_fog=true
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	return mat

func ridge(node_name:String,radius:float,peak:float,mat:Material,seed:int) -> MeshInstance3D:
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps:=360
	for i in range(steps):
		var a:=TAU*i/steps;var b:=TAU*(i+1)/steps
		var ha:=ridge_height(a,peak,seed);var hb:=ridge_height(b,peak,seed)
		var pa:=Vector3(cos(a),0,sin(a))*radius;var pb:=Vector3(cos(b),0,sin(b))*radius
		# 分成山脚、山腰与峰顶三层，用斜坡和冷暖明暗表现体积，避免纸片地平线。
		var foot_a:=pa*.78+Vector3(0,-20,0);var foot_b:=pb*.78+Vector3(0,-20,0)
		var mid_a:=pa*.90+Vector3(0,ha*.35,0);var mid_b:=pb*.90+Vector3(0,hb*.35,0)
		var top_a:=pa+Vector3(0,ha,0);var top_b:=pb+Vector3(0,hb,0)
		var shade:=.82+.06*sin(a*5.0+seed)+.025*cos(a*13.0)
		for band in [[foot_a,foot_b,mid_b,mid_a,Color(1.08,1.08,1.04),Color(.9,.94,.92)], [mid_a,mid_b,top_b,top_a,Color(.9,.94,.92),Color(shade,shade*1.04,shade*1.08)]]:
			for index in [0,1,2,0,2,3]:
				tool.set_color(band[4] if index<2 else band[5])
				tool.add_vertex(band[index])
	var view:=MeshInstance3D.new();view.name=node_name
	view.mesh=tool.commit();view.material_override=mat
	view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return view

static func ridge_height(a:float,peak:float,seed:int) -> float:
	var s:=float(seed)
	var h:=sin(a*3.0+s)*0.45+sin(a*7.0+s*1.7)*0.3+absf(sin(a*17.0+s*2.3))*.28+sin(a*41.0+s)*0.10
	return peak*(0.55+h*0.5)

# 每帧随镜头平移（不旋转），高度与色调跟随当前地貌：悬崖段是云海，林地/村庄是远方原野。
func sync(camera:Camera3D,meters:float,chapter:int,forest_weight:float) -> void:
	var p:=Landscape.profile(meters,chapter)
	var cliff:=p.x
	horizon.position=Vector3(camera.global_position.x,lerpf(0.4,-42.0,cliff),camera.global_position.z)
	var field:=Color("6d7448").lerp(Color("4f5e3d"),forest_weight)
	ground_material.albedo_color=field.lerp(Color("d9d2dc"),cliff)
	# 林中雾浓，远山同步淡入雾色，不在雾墙上方露出清晰剪影。
	var haze:=Color("c8bfb8")
	near_ridge.albedo_color=Color("667e7b").lerp(Color("70898c"),cliff).lerp(haze,forest_weight*0.8)
	far_ridge.albedo_color=Color("a0b0b9").lerp(Color("aab9c2"),cliff).lerp(haze,forest_weight*0.9)
	if not enabled:return
	var palette:Dictionary=palettes[clampi(chapter,0,palettes.size()-1)]
	# 远景环带与山脊是不受光的展示层，需要按时段直接压色，否则夜里会像一圈雪地。
	var tint:Color=palette.land_tint
	ground_material.albedo_color*=tint
	near_ridge.albedo_color*=tint
	far_ridge.albedo_color*=tint.lerp(Color.WHITE,0.15)
	sun.light_color=palette.sun
	sun.light_energy=float(palette.energy)*(1.0-forest_weight*0.08)
	sun.rotation_degrees=Vector3(palette.pitch,palette.yaw,0)
	env.volumetric_fog_anisotropy=palette.anisotropy
	fill.light_color=palette.fill
	fill.light_energy=float(palette.fill_energy)
	env.ambient_light_energy=palette.ambient
	env.ambient_light_color=palette.ambient_color
	# 自定义天空已带地平线雾带；不要让引擎雾再整体覆盖天空。
	env.fog_sky_affect=0.0
	env.fog_light_color=palette.fog.lerp(Color("b9c4bd"),forest_weight*0.35)
	env.fog_density=float(palette.fog_scale)*lerpf(0.0021,0.0042,forest_weight)
	# 低角度逆光穿过林冠阴影，在体积雾里形成光柱；林中雾更厚，光柱更明显。
	env.volumetric_fog_density=float(palette.fog_scale)*float(palette.vol_scale)*lerpf(0.0008,0.0022,forest_weight)
	env.adjustment_contrast=palette.contrast
	env.adjustment_saturation=palette.saturation
	env.volumetric_fog_albedo=Color("f2dfc4").lerp(Color("e4e8e0"),forest_weight) if chapter<2 else Color("b8c4dc")
	sky_material.set_shader_parameter("horizon_color",palette.sky_horizon)
	sky_material.set_shader_parameter("sky_color",palette.sky_low)
	sky_material.set_shader_parameter("zenith_color",palette.sky_zenith)
	sky_material.set_shader_parameter("cloud_lit",palette.cloud_lit)
	sky_material.set_shader_parameter("cloud_shadow",palette.cloud_shadow)
	sky_material.set_shader_parameter("cloud_coverage",palette.cloud)
	sky_material.set_shader_parameter("cloud_scale",palette.cloud_scale)
	sky_material.set_shader_parameter("haze",palette.haze)
	sky_material.set_shader_parameter("saturation",palette.sky_saturation)
	sky_material.set_shader_parameter("sun_color",palette.sun)
	sky_material.set_shader_parameter("sun_energy",float(palette.energy)*float(palette.sky_sun))
	sky_material.set_shader_parameter("star_amount",palette.stars)
	sky_material.set_shader_parameter("disk_size",palette.disk)
	sky_material.set_shader_parameter("sun_dir",sun.global_transform.basis.z.normalized())
