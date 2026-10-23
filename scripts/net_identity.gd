extends RefCounted
# 所有运行脚本统一校验，覆盖输入解释、关卡和模拟依赖；贴图、模型和音频不影响指纹。
# 源码运行直接计算，避免忘记生成清单；导出后的二进制脚本用打包入口生成的清单。
const Manifest = preload("res://scripts/net_manifest.gd")
static var cached := ""

static func fingerprint() -> String:
	if not cached.is_empty(): return cached
	var digest := Manifest.FINGERPRINT
	if FileAccess.file_exists("res://scripts/journey_run.gd"):
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		var names := DirAccess.get_files_at("res://scripts")
		names.sort()
		var hashed := 0
		for name in names:
			if not name.ends_with(".gd") or name == "net_manifest.gd": continue
			var path := "scripts/" + name
			context.update((path + "\n").to_utf8_buffer())
			context.update(FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").to_utf8_buffer())
			context.update("\n".to_utf8_buffer())
			hashed += 1
		# 导出包的脚本目录只列出 .gdc / .remap：读不到源码时沿用清单，否则所有导出包都是同一个空内容哈希。
		if hashed > 0: digest = context.finish().hex_encode()
	# 确定性模拟也要求引擎版本一致，但不区分 Windows/Mac 的平台名称。
	cached = digest + ":" + str(Engine.get_version_info().hash)
	return cached
