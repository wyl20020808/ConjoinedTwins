extends SkeletonModifier3D

# 主角画面层：侧步/后退混合、持枪上半身层与双脚贴地。
# 在 AnimationPlayer 之后执行，修改不写回动画姿势（下一帧从动画结果重新开始），
# 只读 journey_view 每帧写入的参数，不读写模拟、碰撞或联机状态。

# 侧步与后退片段相对 Run 的相位差：Run 第 0 帧右脚着地，Run_Left 第 0 帧左脚着地。
const STRAFE_PHASE := {"Run_Back": 0.0, "Run_Left": 0.5, "Run_Right": 0.0}
const GUN_CLIP := "Idle_Gun_Pointing"
# 持枪层逐骨权重：右臂整链取持枪姿势，左臂与胸口只收一半，保留跑动的摆幅。
const GUN_BONES := {"RightShoulder": 1.0, "RightUpperArm": 1.0, "RightLowerArm": 1.0, "RightHand": 1.0,
	"LeftShoulder": 0.5, "LeftUpperArm": 0.5, "LeftLowerArm": 0.5, "LeftHand": 0.5, "UpperChest": 0.4, "Chest": 0.25}
# 枪械动作层：Blender 制作的上半身片段（收取枪、捡枪、换弹等），按模拟时间采样，覆盖脊柱、头和肩膀；
# 双手随后由战斗画面的手部 IK 精确贴到枪上。
const ACTION_BONES := {"Spine": 0.6, "Chest": 1.0, "UpperChest": 1.0, "Neck": 1.0, "Head": 1.0,
	"RightShoulder": 1.0, "RightUpperArm": 1.0, "RightLowerArm": 1.0, "RightHand": 1.0,
	"LeftShoulder": 1.0, "LeftUpperArm": 1.0, "LeftLowerArm": 1.0, "LeftHand": 1.0}
const ARM_PREFIXES := ["Right", "Left"]
const LEGS := [["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"], ["RightUpperLeg", "RightLowerLeg", "RightFoot"]]
# 单脚最多抬升/下探的世界高度，超过即视为台阶边缘外，不再硬拉腿。
const MAX_FOOT_SHIFT := 0.9

# 以下由画面每帧写入。
var strafe := {"Run_Back": 0.0, "Run_Left": 0.0, "Run_Right": 0.0}
var run_phase := 0.0
var gun_weight := 0.0
var gun_arms := true
var foot_weight := 0.0
var action_clip := ""
var action_time := 0.0
var action_weight := 0.0
var ground_ref := 0.0
var ground := Callable()

var clips := {}
var rotation_tracks := {}
var position_tracks := {}
var hips := -1
# 修改后的最终姿势：手腕供战斗画面挂枪，脚踝供回归测试核对贴地。
var recorded := PackedInt32Array()
var final_poses := {}
var last_foot_shift := [0.0, 0.0]

func setup(player: AnimationPlayer) -> void:
	var skeleton := get_skeleton()
	if skeleton == null: return
	hips = skeleton.find_bone("Hips")
	for name in ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]: recorded.append(skeleton.find_bone(name))
	var names := {}
	for clip in STRAFE_PHASE.keys() + [GUN_CLIP]: names[clip] = "CharacterArmature|" + clip
	for clip in player.get_animation_list():
		if String(clip).begins_with("Gun"): names[String(clip)] = String(clip)
	for clip in names:
		var name: String = names[clip]
		if not player.has_animation(name): continue
		var animation := player.get_animation(name)
		var rotations := {}
		var positions := {}
		for track in range(animation.get_track_count()):
			var bone := skeleton.find_bone(String(animation.track_get_path(track).get_concatenated_subnames()))
			if bone < 0: continue
			match animation.track_get_type(track):
				Animation.TYPE_ROTATION_3D: rotations[bone] = track
				Animation.TYPE_POSITION_3D: positions[bone] = track
		clips[clip] = animation
		rotation_tracks[clip] = rotations
		position_tracks[clip] = positions

func has_pose(bone: int) -> bool:
	return final_poses.has(bone)

func final_pose(bone: int) -> Transform3D:
	return final_poses[bone]

func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or clips.is_empty(): return
	# 前进/后退先合成，再按侧向权重混入侧步；三者权重之和为 1（Run 本身由动画播放器给出）。
	for clip in ["Run_Back", "Run_Left", "Run_Right"]:
		var weight: float = strafe[clip]
		if weight > 0.001 and clips.has(clip):
			var animation: Animation = clips[clip]
			blend_clip(skeleton, clip, fposmod(run_phase + STRAFE_PHASE[clip], 1.0) * animation.length, weight, {})
	if gun_weight > 0.001 and clips.has(GUN_CLIP):
		var weights := {}
		for name in GUN_BONES:
			# 换弹时双臂交给战斗画面的手部 IK，持枪层只保留胸口。
			if not gun_arms and (name.begins_with("Right") or name.begins_with("Left")): continue
			var bone := skeleton.find_bone(name)
			if bone >= 0: weights[bone] = GUN_BONES[name] * gun_weight
		blend_clip(skeleton, GUN_CLIP, 0.0, 1.0, weights)
	if action_weight > 0.001 and clips.has(action_clip):
		var weights := {}
		for name in ACTION_BONES:
			var bone := skeleton.find_bone(name)
			if bone >= 0: weights[bone] = ACTION_BONES[name] * action_weight
		blend_clip(skeleton, action_clip, action_time, 1.0, weights)
	if foot_weight > 0.001 and ground.is_valid(): plant_feet(skeleton)
	else: last_foot_shift = [0.0, 0.0]
	for bone in recorded:
		if bone >= 0: final_poses[bone] = skeleton.get_bone_global_pose(bone)

# weights 为空时整段按 weight 混合；否则只混合列出的骨骼。
func blend_clip(skeleton: Skeleton3D, clip: String, time: float, weight: float, weights: Dictionary) -> void:
	var animation: Animation = clips[clip]
	var rotations: Dictionary = rotation_tracks[clip]
	for bone in (weights.keys() if not weights.is_empty() else rotations.keys()):
		if not rotations.has(bone): continue
		var w: float = weights.get(bone, weight)
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(animation.rotation_track_interpolate(rotations[bone], time), w))
	if weights.is_empty() and position_tracks[clip].has(hips):
		skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips).lerp(animation.position_track_interpolate(position_tracks[clip][hips], time), weight))

# 双脚贴地：按脚下地面与身体所在地面的高度差抬脚或下探；
# 有一只脚需要下探时先压低髋部，再用两段骨骼 IK 把两只脚送到目标高度，脚掌保持动画朝向。
func plant_feet(skeleton: Skeleton3D) -> void:
	var to_world := skeleton.global_transform
	var up := to_world.basis.inverse() * Vector3.UP
	var shifts := [0.0, 0.0]
	var bones := []
	for side in range(2):
		var chain := PackedInt32Array()
		for name in LEGS[side]: chain.append(skeleton.find_bone(name))
		if chain.has(-1): return
		bones.append(chain)
		var foot := to_world * skeleton.get_bone_global_pose(chain[2]).origin
		var height: float = ground.call(foot)
		if not is_nan(height) and absf(height - ground_ref) <= MAX_FOOT_SHIFT:
			shifts[side] = (height - ground_ref) * foot_weight
	last_foot_shift = shifts
	if absf(shifts[0]) < 0.005 and absf(shifts[1]) < 0.005: return
	var pelvis := minf(0.0, minf(shifts[0], shifts[1]))
	if pelvis < 0.0 and hips >= 0:
		var parent := skeleton.get_bone_parent(hips)
		var basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
		skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + basis.inverse() * (up * pelvis))
	for side in range(2):
		var chain: PackedInt32Array = bones[side]
		var target: Vector3 = skeleton.get_bone_global_pose(chain[2]).origin + up * (float(shifts[side]) - pelvis)
		solve_leg(skeleton, chain, target)

func solve_leg(skeleton: Skeleton3D, chain: PackedInt32Array, target: Vector3) -> void:
	var a := skeleton.get_bone_global_pose(chain[0])
	var b := skeleton.get_bone_global_pose(chain[1])
	var c := skeleton.get_bone_global_pose(chain[2])
	if c.origin.distance_to(target) < 0.0005: return
	var foot_basis := c.basis
	var first := a.origin.distance_to(b.origin)
	var second := b.origin.distance_to(c.origin)
	var reach := target - a.origin
	var distance := clampf(reach.length(), absf(first - second) + 0.001, first + second - 0.001)
	var direction := reach.normalized()
	# 保持动画原有的屈膝方向。
	var bend := (b.origin - a.origin) - direction * (b.origin - a.origin).dot(direction)
	if bend.length_squared() < 1e-8: return
	bend = bend.normalized()
	var along := (first * first - second * second + distance * distance) / (2.0 * distance)
	var knee := a.origin + direction * along + bend * sqrt(maxf(0.0, first * first - along * along))
	set_bone_basis(skeleton, chain[0], Basis(Quaternion((b.origin - a.origin).normalized(), (knee - a.origin).normalized())) * a.basis)
	b = skeleton.get_bone_global_pose(chain[1])
	c = skeleton.get_bone_global_pose(chain[2])
	var end := a.origin + direction * distance
	set_bone_basis(skeleton, chain[1], Basis(Quaternion((c.origin - b.origin).normalized(), (end - b.origin).normalized())) * b.basis)
	set_bone_basis(skeleton, chain[2], foot_basis)

func set_bone_basis(skeleton: Skeleton3D, bone: int, basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * basis).get_rotation_quaternion())
