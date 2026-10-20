extends SkeletonModifier3D
# 主角头部抬平：Adventurer 动作重定向到 Tripo/Mixamo 骨架后，颈、头的静止朝向有约 25° 的仰角，
# 近景看两人都像在仰头看天。动画求值后在骨骼局部 X 轴上把颈、头各往下压一点；只改表现。
@export var neck_pitch := -0.15
@export var head_pitch := -0.32

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for entry in [["Neck", neck_pitch], ["Head", head_pitch]]:
		var bone := skeleton.find_bone(entry[0])
		if bone >= 0:
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion(Vector3.RIGHT, entry[1]))
