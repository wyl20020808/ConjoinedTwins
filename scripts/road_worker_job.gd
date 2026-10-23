extends RefCounted
const Task = preload("res://scripts/preparation_task.gd")
const Job = preload("res://scripts/road_generation_job.gd")
var job: Dictionary
var cancellation
var task
var done: bool:
	get: return task.done
var result: Dictionary:
	get: return task.result if task.done else {}
func _init(request: Dictionary, flag) -> void:
	job = request.duplicate(true)
	cancellation = flag
	task = Task.new(verify.bind(job.duplicate(true),flag))
static func verify(request: Dictionary, flag) -> Dictionary:
	var worker = Job.new(request,flag)
	while not worker.done: worker.advance(32)
	var answer: Dictionary=worker.result
	worker.dispose()
	return answer
func advance(_steps: int) -> void:
	var _completed: bool=task.done
func dispose() -> void:
	cancellation.cancel()
	task.dispose()
