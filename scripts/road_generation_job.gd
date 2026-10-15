extends RefCounted
# 无线程平台分帧执行与 verification_worker 相同的候选顺序、验证及散布复证。
const Templates = preload("res://scripts/road_templates.gd")
var job: Dictionary
var verifier = Templates.new()
var validation
var candidate_index := 0
var block: Dictionary = {}
var extras: Array = []
var dressed: Dictionary = {}
var phase := "base"
var done := false
var result: Dictionary = {}
var started := Time.get_ticks_usec()

func _init(request: Dictionary, cancellation, completed_block = null) -> void:
	job = request.duplicate(true)
	verifier.source_override = "runtime"
	verifier.cancellation = cancellation
	if completed_block is Dictionary:
		done = true
		result = {"epoch": job.epoch, "number": job.number, "block": completed_block.duplicate(true),
			"canceled": false, "reason": "", "source": "checkpoint_history", "elapsed_usec": 0}
	else: _begin_candidate()

func _begin_candidate() -> void:
	if candidate_index >= job.candidates.size() or verifier.canceled():
		_finish({})
		return
	block = job.candidates[candidate_index].duplicate(true)
	phase = "base"
	validation = verifier.begin_validation(block, job.difficulty, job.level, {}, 0.0, true)

func _finish(value: Dictionary) -> void:
	done = true
	result = {"epoch": job.epoch, "number": job.number, "block": value,
		"canceled": verifier.canceled(), "reason": verifier.last_evidence.get("reason", ""),
		"elapsed_usec": Time.get_ticks_usec() - started}

func advance(steps: int) -> void:
	for index in range(steps):
		if done: return
		if verifier.canceled():
			dispose()
			_finish({})
			return
		validation.advance(1)
		if not validation.done: continue
		var accepted: bool = validation.accepted
		validation = null
		if phase == "base":
			if not accepted:
				candidate_index += 1
				_begin_candidate()
				continue
			var picker := RandomNumberGenerator.new()
			picker.seed = block.get("extra_seed", 1)
			extras = Templates.extra_hazards(block, verifier.last_evidence.get("corridor", []), picker, job.difficulty, job.level)
		elif accepted:
			_finish(dressed)
			return
		else:
			extras.resize(extras.size() / 2)
		if extras.is_empty():
			_finish(block)
			return
		dressed = block.duplicate(true)
		dressed.hazards.append_array(extras)
		phase = "extras"
		validation = verifier.begin_validation(dressed, job.difficulty, job.level, {}, 0.0, false)

func dispose() -> void:
	if validation != null:
		validation.dispose()
		validation = null
	done = true
