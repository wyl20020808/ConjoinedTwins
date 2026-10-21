extends Node

# 音效由 build-tools/bake_sfx.gd 预生成；保留合成公式，便于可重复更新。
# 用固定数量的播放器轮流播放，同一时刻最多叠 POOL 个声音。
const RATE := 22050
const POOL := 10
var streams := {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var noise := RandomNumberGenerator.new()

# 混音总线：音乐、音效、环境、界面分开调节；Master 末端限幅，叠音时不爆音。
const BUSES := ["Music", "SFX", "Ambience", "UI"]
const UI_SOUNDS := ["coin", "coin_land", "prize", "clear", "click"]
# 定位音效：机关、敌人在世界中的位置发声，带距离衰减和左右声像。
const POOL_3D := 8
const MAX_DISTANCE := 90.0
# 每次播放随机变化音高与音量，避免连续同一声音像机器复读；只影响本机听感。
const PITCH_VARY := 0.05
const VOLUME_VARY := 2.0
var players_3d: Array[AudioStreamPlayer3D] = []
var next_player_3d := 0
var vary := RandomNumberGenerator.new()
# 录制音效（Kenney Impact Sounds / RPG Audio，CC0，见 ASSET_SOURCES.md）：同名多条，播放时随机选一条。
# 原 OGG 已解码为单声道 WAV：短音效频繁起停，OGG 播放句柄在退出时可能残留。
const KENNEY := "res://assets/audio/kenney/%s.wav"
const VARIANTS := {
	"step_grass": ["footstep_grass_000", "footstep_grass_001", "footstep_grass_002", "footstep_grass_003", "footstep_grass_004"],
	"step_stone": ["footstep_concrete_000", "footstep_concrete_001", "footstep_concrete_002", "footstep_concrete_003", "footstep_concrete_004"],
	"step_wood": ["footstep_wood_000", "footstep_wood_001", "footstep_wood_002", "footstep_wood_003", "footstep_wood_004"],
	"land_soft": ["impactSoft_heavy_000", "impactSoft_heavy_001", "impactSoft_heavy_002", "impactSoft_heavy_003", "impactSoft_heavy_004"],
	"metal_heavy": ["impactMetal_heavy_000", "impactMetal_heavy_001", "impactMetal_heavy_002", "impactMetal_heavy_003", "impactMetal_heavy_004"],
	"metal_light": ["impactMetal_light_000", "impactMetal_light_001", "impactMetal_light_002", "impactMetal_light_003", "impactMetal_light_004"],
	"rubble": ["impactMining_000", "impactMining_001", "impactMining_002", "impactMining_003", "impactMining_004"],
	"plate_heavy": ["impactPlate_heavy_000", "impactPlate_heavy_001", "impactPlate_heavy_002", "impactPlate_heavy_003", "impactPlate_heavy_004"],
	"punch": ["impactPunch_medium_000", "impactPunch_medium_001", "impactPunch_medium_002", "impactPunch_medium_003", "impactPunch_medium_004"],
	"punch_heavy": ["impactPunch_heavy_000", "impactPunch_heavy_001", "impactPunch_heavy_002", "impactPunch_heavy_003", "impactPunch_heavy_004"],
	"creak": ["creak1", "creak2", "creak3"],
	"metal_click": ["metalClick"],
	"metal_latch": ["metalLatch"],
	"door_open": ["doorOpen_1", "doorOpen_2"],
}
var variants := {}
# 退出场景树后不再新建播放句柄，否则 OGG 播放对象会在退出时残留。
var closing := false
# 每个播放器每帧最多启动一次：同帧重复改播会让被替换的播放句柄来不及释放（例如多排地刺同时弹出）。
var started_frame := {}

func available(player: Node) -> bool:
	var frame := Engine.get_process_frames()
	if started_frame.get(player, -1) == frame: return false
	started_frame[player] = frame
	return true
const SOUND_NAMES := ["coin", "coin_land", "prize", "shield", "shield_break", "jump", "land", "hit", "fall", "warning", "whoosh", "clear", "rope", "buckle", "click", "gunshot"]

func _ready() -> void:
	ensure_buses()
	vary.randomize()
	for n in range(POOL):
		var player := AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	for n in range(POOL_3D):
		var player := AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.unit_size = 8.0
		player.max_distance = MAX_DISTANCE
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.panning_strength = 0.8
		add_child(player)
		players_3d.append(player)
	for key in SOUND_NAMES:
		streams[key] = load("res://assets/audio/%s.wav" % key)
	for key in VARIANTS:
		var list: Array[AudioStream] = []
		for file in VARIANTS[key]: list.append(load(KENNEY % file))
		variants[key] = list

func has_sound(name: String) -> bool:
	return not closing and is_inside_tree() and (streams.has(name) or variants.has(name))

func pick(name: String) -> AudioStream:
	if variants.has(name):
		var list: Array = variants[name]
		return list[vary.randi() % list.size()]
	return streams.get(name)

static func ensure_buses() -> void:
	for name in BUSES:
		if AudioServer.get_bus_index(name) >= 0: continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, name)
		AudioServer.set_bus_send(index, "Master")
	var master := AudioServer.get_bus_index("Master")
	for n in range(AudioServer.get_bus_effect_count(master)):
		if AudioServer.get_bus_effect(master, n) is AudioEffectHardLimiter: return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(master, limiter)

# 按线性 0–1 平滑设置某条总线音量，用于战斗时压低环境声。
static func set_bus_level(name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(name)
	if index >= 0: AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, linear)))

func _exit_tree() -> void:
	closing = true
	started_frame.clear()
	for player in players_3d:
		player.stop()
		player.stream = null
	for player in players:
		player.stop()
		player.stream = null
	streams.clear()
	variants.clear()

func synthesize() -> void:
	noise.seed = 7
	streams.coin = render(0.16, func(t): return blip(t, 0.0, 0.06, 988.0) + blip(t, 0.05, 0.11, 1319.0))
	streams.coin_land = render(0.06, func(t): return 0.35 * sin(TAU * 1760.0 * t) * exp(-t * 60.0))
	streams.prize = render(0.5, prize_wave)
	streams.shield = render(0.3, func(t): return 0.5 * triangle(t * lerpf(380.0, 980.0, t / 0.3)) * envelope(t, 0.3, 0.02))
	streams.shield_break = render(0.35, func(t): return (0.4 * square(t * lerpf(900.0, 260.0, t / 0.35)) * 0.4 + 0.35 * (noise.randf() * 2.0 - 1.0)) * envelope(t, 0.35, 0.005))
	streams.jump = render(0.14, func(t): return 0.32 * square(t * lerpf(280.0, 620.0, t / 0.14)) * envelope(t, 0.14, 0.005))
	streams.land = render(0.1, func(t): return (0.5 * sin(TAU * lerpf(140.0, 60.0, t / 0.1) * t) + 0.25 * (noise.randf() * 2.0 - 1.0)) * exp(-t * 35.0))
	streams.hit = render(0.6, func(t): return (0.45 * saw(t * lerpf(320.0, 70.0, t / 0.6)) + 0.3 * (noise.randf() * 2.0 - 1.0) * exp(-t * 8.0)) * envelope(t, 0.6, 0.004))
	streams.fall = render(1.0, func(t): return 0.4 * sin(TAU * t * lerpf(1100.0, 180.0, pow(t, 0.7))) * envelope(t, 1.0, 0.02))
	streams.warning = render(0.3, func(t): return blip(t, 0.0, 0.1, 880.0) * 0.6 + blip(t, 0.15, 0.25, 880.0) * 0.6)
	streams.whoosh = render(0.45, whoosh_wave)
	streams.clear = render(0.9, clear_wave)
	streams.rope = render(0.23, func(t): return (0.2*triangle(t*(145.0+sin(t*35)*20)) + 0.15*(noise.randf()*2-1))*envelope(t,0.23,0.03))
	streams.buckle = render(0.08, func(t): return (0.3*sin(t*TAU*1700)+0.2*sin(t*TAU*2300))*exp(-t*65))
	streams.click = render(0.05, func(t): return 0.4 * square(t * 660.0) * exp(-t * 70.0))
	streams.gunshot = render(0.09, func(t): return (0.45*(noise.randf()*2-1)+0.3*sin(TAU*110*t))*exp(-t*55))

func prize_wave(t: float) -> float:
	var value := 0.0
	for n in range(4): value += blip(t, n * 0.08, n * 0.08 + 0.18, [523.25, 659.25, 783.99, 1046.5][n])
	return value * 0.8

func whoosh_wave(t: float) -> float:
	var swell := sin(PI * t / 0.45)
	return 0.5 * (noise.randf() * 2.0 - 1.0) * swell * swell

func clear_wave(t: float) -> float:
	var value := 0.0
	for n in range(5): value += blip(t, n * 0.11, n * 0.11 + (0.5 if n == 4 else 0.16), [392.0, 523.25, 659.25, 783.99, 1046.5][n])
	return value * 0.7

# 在 [start, stop) 内响一个带包络的正弦音。
static func blip(t: float, start: float, stop: float, frequency: float) -> float:
	if t < start or t >= stop: return 0.0
	return 0.5 * sin(TAU * frequency * (t - start)) * envelope(t - start, stop - start, 0.004)

static func envelope(t: float, length: float, attack: float) -> float:
	return clampf(t / attack, 0.0, 1.0) * clampf((length - t) / (length * 0.6), 0.0, 1.0)

static func square(phase: float) -> float:
	return 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0

static func saw(phase: float) -> float:
	return fposmod(phase, 1.0) * 2.0 - 1.0

static func triangle(phase: float) -> float:
	return 1.0 - 4.0 * absf(fposmod(phase, 1.0) - 0.5)

# 用相位累加的频率扫描会更准，这里频率变化慢、时长短，直接按 t·f(t) 近似即可。
func render(length: float, wave: Callable) -> AudioStreamWAV:
	var count := int(length * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for n in range(count):
		var value: float = clampf(wave.call(float(n) / RATE), -1.0, 1.0)
		data.encode_s16(n * 2, int(value * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream

func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not has_sound(name): return
	var player := players[next_player]
	if not available(player): return
	next_player = (next_player + 1) % players.size()
	player.stream = pick(name)
	player.bus = "UI" if name in UI_SOUNDS else "SFX"
	player.volume_db = volume_db + vary.randf_range(-VOLUME_VARY, VOLUME_VARY)
	player.pitch_scale = pitch * (1.0 + vary.randf_range(-PITCH_VARY, PITCH_VARY))
	player.play()

# 在世界坐标发声，带距离衰减；调用方不必判断远近。
func play_at(name: String, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not has_sound(name) or players_3d.is_empty(): return
	# 超出听距的不播放：既听不到，也不占用播放器（远处播放的句柄停止时可能不被音频服务器回收）。
	var listener := get_viewport().get_camera_3d() if get_viewport() != null else null
	if listener != null and listener.global_position.distance_to(position) > MAX_DISTANCE: return
	var player := players_3d[next_player_3d]
	if not available(player): return
	next_player_3d = (next_player_3d + 1) % players_3d.size()
	player.stream = pick(name)
	player.global_position = position
	player.volume_db = volume_db + vary.randf_range(-VOLUME_VARY, VOLUME_VARY)
	player.pitch_scale = pitch * (1.0 + vary.randf_range(-PITCH_VARY, PITCH_VARY))
	player.play()
