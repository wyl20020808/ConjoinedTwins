extends RefCounted
# 局部随机流不消费全局随机数；同种子、章节和通道始终生成同一布局。
# 洗牌袋允许短期波动，每袋耗尽后恢复既定配比，避免无限独立抽样的长连串。
var rng := RandomNumberGenerator.new()
var bags := {}

func _init(seed_value:int, chapter:int=0, channel:int=0)->void:
	rng.seed=(seed_value*1664525+chapter*1013904223+channel*69069)&0x7fffffff

func shuffled(values:Array)->Array:
	var result:=values.duplicate()
	for i in range(result.size()-1,0,-1):
		var j:=rng.randi_range(0,i)
		var value=result[i];result[i]=result[j];result[j]=value
	return result

func draw(key:String, values:Array):
	if not bags.has(key) or bags[key].is_empty():bags[key]=shuffled(values)
	return bags[key].pop_back()
