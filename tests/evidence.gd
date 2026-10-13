extends SceneTree

func _initialize() -> void:
	# Repository began with only INITIAL_DEVELOPMENT_PLAN.md; all listed sources are additions.
	var paths := ["project.godot", ".gitignore", "scenes/main.tscn", "scripts/game.gd", "scripts/twin.gd", "scripts/link_motion.gd", "scripts/partner_ai.gd", "scripts/levels.gd", "scripts/mechanisms.gd", "tests/headless.gd", "tests/decision_review.gd", "tests/evidence.gd", "启动白盒.cmd", "验证白盒.cmd", "README.md", "docs/TEST_REPORT.md", "docs/DECISION_REVIEW.md", "docs/PLAYTEST_CHECKLIST.md"]
	var diff := FileAccess.open("res://docs/IMPLEMENTATION.diff", FileAccess.WRITE)
	var manifest := {}
	for path: String in paths:
		var text := FileAccess.get_file_as_string("res://" + path)
		var lines := text.trim_suffix("\n").split("\n")
		diff.store_string("diff --git a/%s b/%s\nnew file mode 100644\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1,%d @@\n" % [path, path, path, lines.size()])
		for line: String in lines:
			diff.store_string("+" + line + "\n")
		manifest[path] = FileAccess.get_sha256("res://" + path)
	manifest["docs/INITIAL_DEVELOPMENT_PLAN.md"] = FileAccess.get_sha256("res://docs/INITIAL_DEVELOPMENT_PLAN.md")
	diff.close()
	var output := FileAccess.open("res://tests/source_hashes.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(manifest, "\t", true))
	output.close()
	print("Evidence: additions diff and SHA-256 manifest written; original plan retained.")
	quit(0)
