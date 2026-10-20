extends SceneTree
# 生成 Godot 人形骨骼映射，供 GLB 导入时重定向：
# - bonemap_quaternius.tres：Quaternius Adventurer 及救援动作（动画来源）
# - bonemap_mixamo.tres：Tripo 绑定输出的 Mixamo 骨架（新主角）
# 两者映射到同一 SkeletonProfileHumanoid，导入后骨骼统一改名并规范静止姿态，动画可互用。
# 运行：Godot --headless --path <项目> --script res://build-tools/journey/make_humanoid_bonemaps.gd

# Quaternius 的骨盆动画全部在 Body（Hips 的父骨骼）上，Hips 本身不带关键帧，因此人形 Hips 映射到 Body。
const QUATERNIUS := {
	"Root":"Root","Hips":"Body","Spine":"Abdomen","Chest":"Torso","UpperChest":"Chest","Neck":"Neck","Head":"Head",
	"LeftShoulder":"Shoulder.L","LeftUpperArm":"UpperArm.L","LeftLowerArm":"LowerArm.L","LeftHand":"Wrist.L",
	"RightShoulder":"Shoulder.R","RightUpperArm":"UpperArm.R","RightLowerArm":"LowerArm.R","RightHand":"Wrist.R",
	"LeftUpperLeg":"UpperLeg.L","LeftLowerLeg":"LowerLeg.L","LeftFoot":"Foot.L",
	"RightUpperLeg":"UpperLeg.R","RightLowerLeg":"LowerLeg.R","RightFoot":"Foot.R",
}
const MIXAMO := {
	"Hips":"Hips","Spine":"Spine","Chest":"Spine1","UpperChest":"Spine2","Neck":"Neck","Head":"Head",
	"LeftShoulder":"LeftShoulder","LeftUpperArm":"LeftArm","LeftLowerArm":"LeftForeArm","LeftHand":"LeftHand",
	"RightShoulder":"RightShoulder","RightUpperArm":"RightArm","RightLowerArm":"RightForeArm","RightHand":"RightHand",
	"LeftUpperLeg":"LeftUpLeg","LeftLowerLeg":"LeftLeg","LeftFoot":"LeftFoot","LeftToes":"LeftToeBase",
	"RightUpperLeg":"RightUpLeg","RightLowerLeg":"RightLeg","RightFoot":"RightFoot","RightToes":"RightToeBase",
}
const FINGERS := [["Thumb","Metacarpal","Proximal","Distal"],["Index","Proximal","Intermediate","Distal"],["Middle","Proximal","Intermediate","Distal"],["Ring","Proximal","Intermediate","Distal"],["Little","Proximal","Intermediate","Distal"]]

func build(table:Dictionary,finger:Callable,path:String)->void:
	var map:=BoneMap.new()
	map.profile=SkeletonProfileHumanoid.new()
	for profile_bone in table:map.set_skeleton_bone_name(profile_bone,table[profile_bone])
	for side in ["Left","Right"]:
		for f in FINGERS:
			for joint in range(3):
				map.set_skeleton_bone_name(side+f[0]+f[joint+1],finger.call(side,f[0],joint+1))
	var error:=ResourceSaver.save(map,path)
	print(path," ",error_string(error))

func _init()->void:
	# Quaternius 手指：Thumb1-3、Index1-3（4 为指尖不映射），小指叫 Pinky。
	build(QUATERNIUS,func(side,f,n):return ("Pinky" if f=="Little" else f)+str(n)+(".L" if side=="Left" else ".R"),"res://assets/humans/bonemap_quaternius.tres")
	# Mixamo 名称在 Godot 中的冒号被替换为下划线。
	var prefixed:={}
	for k in MIXAMO:prefixed[k]="mixamorig_"+MIXAMO[k]
	build(prefixed,func(side,f,n):return "mixamorig_"+side+"Hand"+("Pinky" if f=="Little" else f)+str(n),"res://assets/humans/bonemap_mixamo.tres")
	quit()
