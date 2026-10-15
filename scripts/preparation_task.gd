extends RefCounted
# 工作函数拥有独立输入和输出。主线程只在完成后取结果并回收任务。
var task_id := -1
var result
var done: bool:
	get:
		if task_id < 0: return true
		if not WorkerThreadPool.is_task_completed(task_id): return false
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
		return true
func _init(work: Callable) -> void:
	task_id = WorkerThreadPool.add_task(execute.bind(work),false,"地图预计算")
func execute(work: Callable) -> void:
	result = work.call()
func dispose() -> void:
	# 仅销毁/切关时收尾；运行中的轮询从不等待活跃任务。
	if task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
