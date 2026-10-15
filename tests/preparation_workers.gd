extends SceneTree
const Run = preload("res://scripts/road_run.gd")
const Task = preload("res://scripts/preparation_task.gd")
const Worker = preload("res://scripts/road_worker_job.gd")
var failures: Array = []
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("verify")
static func delayed(value: int, delay: int) -> int:
	OS.delay_msec(delay)
	return value
func verify() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/loading_baseline.json"))
	# 完成顺序不同，结果仍属于提交时的任务，不能写入其他区块。
	var slow=Task.new(delayed.bind(1,15))
	var fast=Task.new(delayed.bind(2,0))
	for frame in range(1000):
		if fast.done: break
		await process_frame
	check(fast.done and fast.result==2,"后提交的任务可先完成，结果不串号")
	slow.dispose()
	fast.dispose()
	check(slow.result==1,"慢任务保持自己的结果")
	var hashes: Array=[]
	for limit in [1,2]:
		var run=Run.new(true,true)
		run.generation_worker_limit=limit
		run.charge_tutorial=true
		run.seed_value=4242
		run.retry()
		var state: int=run.sync_hash()
		var random_state: int=run.generator.rng.state
		for poll in range(10000):
			if run.prepare_frame(): break
			await process_frame
		var blocks: Dictionary={}
		for job in run.async_preload_tasks.values(): blocks[str(job.job.number)]=var_to_str(job.result.block).sha256_text()
		check(blocks==reference.startup_blocks,"并发 %d 完整布局与原始 test 相同"%limit)
		check(run.sync_hash()==state and run.generator.rng.state==random_state,"预计算不消费生产随机源和物理状态")
		check(run.parallel_peak<=limit and run.parallel_tasks_started>=4,"实际并发有界且四段都使用线程池")
		hashes.append(blocks)
		run.dispose()
	check(hashes[0]==hashes[1],"并发数不影响地图")
	var pending=Run.new(true,true)
	pending.charge_tutorial=true
	pending.retry()
	pending.prepare_frame()
	var old: Array=pending.async_preload_tasks.values()
	var epoch: int=pending.async_epoch
	pending.retry()
	check(pending.async_epoch>epoch and pending.async_preload_tasks.is_empty() and pending.block_history.is_empty(),"重试废弃旧结果和队列")
	check(old.all(func(job):return job.done and job.cancellation.is_canceled()),"取消后回收所有线程池任务")
	pending.dispose()
	var adaptive=Run.new(true,true)
	adaptive.retry()
	adaptive.measured_generation_usec=100000000
	adaptive.prepare_frame()
	adaptive.prepare_frame()
	check(adaptive.preload_segments==8 and adaptive.async_preload_requests.size()<=8 and adaptive.parallel_peak<=2,"慢生成扩大预读窗口且仍保持八段、两任务上限")
	adaptive.dispose()
	print("PREPARATION_WORKERS failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
