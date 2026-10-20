extends RefCounted
# 桌面 Forward+ 画质层：现代色调映射、屏幕空间遮蔽/间接光、体积雾、软阴影，
# 以及跟随镜头的远景地平线（低地环带 + 两层远山剪影），遮住地图边缘。
# 网页与移动端仍走 Compatibility，本层只保留地平线，不开启高开销后期。
const Landscape = preload("res://scripts/journey_landscape.gd")
const RING_INNER := 118.0
const RING_OUTER := 2400.0
const SEGMENTS := 72
# AgX 压高光更柔，直射光与天空环境光按此倍率补回亮度。
const SUN_SCALE := 1.6
const AMBIENT_SCALE := 1.15
var enabled := false
var env: Environment
var sun: DirectionalLight3D
var horizon: Node3D
var ground_material: StandardMaterial3D
var near_ridge: StandardMaterial3D
var far_ridge: StandardMaterial3D

static func forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method()=="forward_plus"

func _init(parent:Node3D,environment:Environment,light:DirectionalLight3D,camera:Camera3D) -> void:
	env=environment;sun=light
	enabled=forward_plus()
	build_horizon(parent)
	if not enabled:return
	env.tonemap_mode=Environment.TONE_MAPPER_AGX
	env.tonemap_exposure=1.0
	# 环境光改由天空提供，阴影面带晚霞色而不是统一灰蓝；保留少量固定色避免森林里发黑。
	env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution=0.7
	env.ssao_enabled=true
	env.ssao_radius=1.4;env.ssao_intensity=2.6;env.ssao_power=1.6
	env.ssao_detail=0.6;env.ssao_light_affect=0.25
	env.ssil_enabled=true
	env.ssil_radius=4.0;env.ssil_intensity=0.7
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
	var attributes:=CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled=true
	attributes.dof_blur_far_distance=95.0
	attributes.dof_blur_far_transition=80.0
	attributes.dof_blur_amount=0.05
	camera.attributes=attributes

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
	env.volumetric_fog_density=lerpf(0.0008,0.0022,forest_weight)
	env.volumetric_fog_albedo=Color("f2dfc4").lerp(Color("e4e8e0"),forest_weight)
