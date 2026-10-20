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
# 每章一套主光/补光/雾色/调色；森林冷绿、村庄暖金、矿道冷蓝。
# sun_energy 已包含 AgX 的亮度补偿，直接作为 DirectionalLight3D 能量使用。
var palettes := [
	{"sun":Color("ffe0b8"),"energy":2.05,"fill":Color("6f9ec6"),"fill_energy":0.30,"fog":Color("a4ab97"),"fog_scale":0.85,"contrast":1.20,"saturation":1.16,"ambient":0.52,"ambient_color":Color("7f9496"),
		"sky_zenith":Color("2b5a72"),"sky_low":Color("4f7f96"),"sky_horizon":Color("c9c3a6"),"cloud_lit":Color("faf6ea"),"cloud_shadow":Color("5f6f74"),"cloud":0.42,"haze":0.35,"sky_saturation":1.0,"cloud_scale":1.1},
	{"sun":Color("ffd09a"),"energy":1.95,"fill":Color("7f95b4"),"fill_energy":0.30,"fog":Color("c9b08c"),"fog_scale":0.80,"contrast":1.16,"saturation":1.14,"ambient":0.58,"ambient_color":Color("a08d7c"),
		"sky_zenith":Color("4a6f96"),"sky_low":Color("7a9dbb"),"sky_horizon":Color("f2cf98"),"cloud_lit":Color("ffeed2"),"cloud_shadow":Color("8d7c72"),"cloud":0.40,"haze":0.30,"sky_saturation":1.05,"cloud_scale":0.9},
	{"sun":Color("cbd9e8"),"energy":1.45,"fill":Color("5f7fa4"),"fill_energy":0.42,"fog":Color("8b98a3"),"fog_scale":0.75,"contrast":1.24,"saturation":0.90,"ambient":0.50,"ambient_color":Color("61717f"),
		"sky_zenith":Color("2b3a46"),"sky_low":Color("4a5b69"),"sky_horizon":Color("9aa6ad"),"cloud_lit":Color("d7dee3"),"cloud_shadow":Color("4f5b64"),"cloud":0.58,"haze":0.40,"sky_saturation":0.90,"cloud_scale":0.8},
]

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
	env.glow_enabled=true
	env.glow_intensity=0.55;env.glow_strength=0.9;env.glow_bloom=0.04
	env.glow_hdr_threshold=1.1
	env.glow_blend_mode=Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# 远处雾色取自同方向天空，地平线与晚霞自然衔接。
	env.fog_aerial_perspective=0.6
	env.volumetric_fog_enabled=true
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
	var ground:=MeshInstance3D.new();ground.name="HorizonGround"
	ground.mesh=ring_mesh();ground.material_override=ground_material
	ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	horizon.add_child(ground)
	near_ridge=ridge_material()
	far_ridge=ridge_material()
	horizon.add_child(ridge("NearRidge",640.0,34.0,near_ridge,3))
	horizon.add_child(ridge("FarRidge",1150.0,78.0,far_ridge,7))

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
	var steps:=180
	for i in range(steps):
		var a:=TAU*i/steps;var b:=TAU*(i+1)/steps
		var ha:=ridge_height(a,peak,seed);var hb:=ridge_height(b,peak,seed)
		var pa:=Vector3(cos(a),0,sin(a))*radius;var pb:=Vector3(cos(b),0,sin(b))*radius
		# 山脚贴近地平线更亮（雾更厚），山脊略深，形成剪影。
		var base:=Color.WHITE;var top:=Color(0.86,0.86,0.86)
		for item in [[pa,base,-20.0],[pb,base,-20.0],[pb,top,hb],[pa,base,-20.0],[pb,top,hb],[pa,top,ha]]:
			tool.set_color(item[1])
			tool.add_vertex(item[0]+Vector3(0,item[2],0))
	var view:=MeshInstance3D.new();view.name=node_name
	view.mesh=tool.commit();view.material_override=mat
	view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return view

static func ridge_height(a:float,peak:float,seed:int) -> float:
	var s:=float(seed)
	var h:=sin(a*3.0+s)*0.45+sin(a*7.0+s*1.7)*0.3+sin(a*17.0+s*2.3)*0.15+sin(a*41.0+s)*0.06
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
	near_ridge.albedo_color=Color("6f6f82").lerp(Color("8a8299"),cliff).lerp(haze,forest_weight*0.8)
	far_ridge.albedo_color=Color("9b95ad").lerp(Color("b3a9bb"),cliff).lerp(haze,forest_weight*0.9)
	if not enabled:return
	var palette:Dictionary=palettes[clampi(chapter,0,palettes.size()-1)]
	sun.light_color=palette.sun
	sun.light_energy=float(palette.energy)*(1.0-forest_weight*0.08)
	fill.light_color=palette.fill
	fill.light_energy=float(palette.fill_energy)
	env.ambient_light_energy=palette.ambient
	env.ambient_light_color=palette.ambient_color
	# 自定义天空已带地平线雾带；不要让引擎雾再整体覆盖天空。
	env.fog_sky_affect=0.0
	env.fog_light_color=palette.fog.lerp(Color("b9c4bd"),forest_weight*0.35)
	env.fog_density=float(palette.fog_scale)*lerpf(0.0021,0.0042,forest_weight)
	env.volumetric_fog_density=float(palette.fog_scale)*lerpf(0.0008,0.0022,forest_weight)
	env.adjustment_contrast=palette.contrast
	env.adjustment_saturation=palette.saturation
	env.volumetric_fog_albedo=Color("f2dfc4").lerp(Color("e4e8e0"),forest_weight)
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
	sky_material.set_shader_parameter("sun_energy",float(palette.energy)*0.85)
	sky_material.set_shader_parameter("sun_dir",sun.global_transform.basis.z.normalized())
