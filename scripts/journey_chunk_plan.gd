extends RefCounted
# 纯数据规划：各区块独立随机源，保留原 build_chunk 的抽签和命令顺序。
static func make(number: int, level: int, chapter: Dictionary, edge: float) -> Array:
	var items: Array = []
	if level==0 and chapter.length>20000:
		return preload("res://scripts/journey_landscape.gd").plan(number,level)
	var rng := RandomNumberGenerator.new()
	rng.seed = number*109+level*7919+42
	var start := number*80.0
	var theme: String = chapter.themes[clampi(int(start*20.0/chapter.length*6.0),0,5)]
	var forest := theme in ["forest","broken","edge","meadow"]
	var village := theme in ["village","farm"]
	var dressing:={}
	for side in [-1.0,1.0]:
		items.append(["land",Vector3(side*(edge/20.0+24),-0.65,-start-40),Vector3(48,1,80),theme,forest])
		if theme=="river": items.append(["water",Vector3(side*30,-2.2,-start-40),Vector3(26,0.15,80)])
		for n in range(8):
			var z := -start-n*10-rng.randf_range(0,4)
			var x: float = side*rng.randf_range(18,36)
			if forest or theme in ["farm","river"]:
				items.append(["model","Pine",Vector3(x,0,z),rng.randf_range(8,15),rng.randf()*TAU,12.0,rng.randf()*TAU])
				if n%2==0: items.append(["model","Bush",Vector3(side*rng.randf_range(16.5,22),0,z+3),rng.randf_range(1,2.3),rng.randf()*TAU,0.0])
				if n%2==1: items.append(["model","TallGrass",Vector3(side*rng.randf_range(16,19),0,z),rng.randf_range(0.7,1.6),rng.randf()*TAU,0.0])
			elif theme in ["mine","ruins"]:
				items.append(["rock",n,Vector3(x,-1,z),rng.randf_range(0.8,2)])
				if theme=="ruins" and n%2==0: items.append(["model","Column",Vector3(side*18,0,z),6.5,0.0,0.0])
		if village:
			for n in range(3):
				preload("res://scripts/journey_landscape.gd").add_instance(dressing,"house_%d"%posmod(number+n,3),Vector3(side*24,0,-start-n*27-10),rng.randf_range(.9,1.1),-side*PI/2)
				items.append(["asset","fence",Vector3(side*17.6,0,-start-n*27-18),1.6,PI/2])
				items.append(["asset","cart",Vector3(side*19,0,-start-n*27-3),2.3,side*PI/2])
				preload("res://scripts/journey_landscape.gd").add_villager(dressing,number*3+n,side,Vector3(side*19.8,0,-start-n*27-14))
		if theme=="facility":
			for n in range(3): items.append(["building",Vector3(side*27,0,-start-n*28),side*PI/2])
	if theme=="farm":
		for n in range(12): items.append(["farm",Vector3(25,-0.05,-start-n*6)])
	if theme=="river": items.append(["asset","waterwheel",Vector3(19,-1,-start-40),8.0,PI/2])
	if village:
		preload("res://scripts/journey_landscape.gd").decorate(dressing,number,level,true)
		for kind in dressing:items.append(["landscape_batch",kind,dressing[kind]])
	var zone_length: float = chapter.length/6.0
	for zone in range(6):
		var y: float = zone*zone_length/20.0
		if y>=start and y<start+80:
			items.append(["asset","sign",Vector3(-15,0,-y-6),3.0,0.0])
			items.append(["sign",chapter.zones[zone],Vector3(-12,4,-y-8)])
	return items

static func paths(items: Array) -> Array:
	var result: Array = []
	for item in items:
		if item[0]=="landscape_batch":
			var asset_path:="res://assets/landscape/%s.glb"%item[1]
			if not result.has(asset_path):result.append(asset_path)
			if item[1] in ["natural_oak_7","natural_oak_17","natural_birch"]:result.append("res://assets/landscape/%s_lod.glb"%item[1])
			continue
		var path := ""
		if item[0]=="model": path="res://assets/decor/%s.glb"%item[1]
		elif item[0]=="asset": path="res://assets/journey/%s.glb"%item[1]
		elif item[0]=="building": path="res://assets/industrial/building-k.glb"
		if not path.is_empty() and not result.has(path): result.append(path)
	return result
