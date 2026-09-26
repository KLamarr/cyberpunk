extends Node
## Autoload "Sfx": riproduzione effetti 2D/3D e loop ambientali.
## I nomi corrispondono ai file in assets/sounds (senza estensione). Se esistono
## varianti numerate (step_metal0, step_metal1) basta chiamare "step_metal".

const SOUNDS := [
	"alarm", "ambient_drone", "body_fall", "cam_alert", "cam_beep", "clatter0", "clatter1",
	"datapad", "denied", "door_locked", "door_open", "elevator", "empty", "glass_break",
	"granted", "grate_break", "grate_pry", "guard_gun", "hack_fail", "hack_ok", "hack_win",
	"heartbeat", "hiss", "hit_flesh", "hit_metal", "hurt", "impact", "keypad", "land", "medpatch",
	"objective", "pickup", "pistol", "radio", "reload", "server_hum", "servo", "spark", "splash",
	"step_carpet0", "step_carpet1", "step_concrete0", "step_concrete1", "step_glass0", "step_glass1",
	"step_grate0", "step_grate1", "step_metal0", "step_metal1", "step_water0", "step_water1",
	"swing", "turret_alert", "turret_fire", "ui_click", "ui_open", "upgrade", "whisper", "zap",
]
const LOOPS := ["alarm", "ambient_drone", "server_hum", "elevator"]

var streams := {}
var variants := {}
var ambient: AudioStreamPlayer
var alarm_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n: String in SOUNDS:
		var path := "res://assets/sounds/%s.wav" % n
		if not ResourceLoader.exists(path):
			continue
		var s: AudioStream = load(path)
		if n in LOOPS and s is AudioStreamWAV:
			s = s.duplicate()
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		streams[n] = s
		var base: String = n.rstrip("0123456789")
		if base != n:
			if not variants.has(base):
				variants[base] = []
			variants[base].append(n)
	ambient = AudioStreamPlayer.new()
	ambient.volume_db = -14.0
	add_child(ambient)
	alarm_player = AudioStreamPlayer.new()
	alarm_player.volume_db = -9.0
	add_child(alarm_player)
	set_master_volume(float(Game.settings.volume))   # impostazione salvata dal giocatore


func set_master_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(max(v, 0.001)))


func get_stream(n: String) -> AudioStream:
	if variants.has(n):
		var list: Array = variants[n]
		return streams[list[randi() % list.size()]]
	return streams.get(n)


func play_ui(n: String, vol_db := 0.0, pitch := 1.0) -> void:
	var s := get_stream(n)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Suono posizionale nel mondo 3D. max_dist in metri.
func play_3d(n: String, pos: Vector3, vol_db := 0.0, pitch_var := 0.08, max_dist := 30.0) -> AudioStreamPlayer3D:
	var s := get_stream(n)
	if s == null:
		return null
	var world: Node = Game.level
	if world == null or not is_instance_valid(world):
		play_ui(n, vol_db - 6.0)
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = vol_db
	p.unit_size = 4.0
	p.max_distance = max_dist
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	world.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p


## Loop 3D permanente (ronzio server ecc.) attaccato a un nodo.
func attach_loop(n: String, parent: Node3D, vol_db := -6.0, max_dist := 12.0) -> AudioStreamPlayer3D:
	var s := get_stream(n)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = vol_db
	p.unit_size = 2.5
	p.max_distance = max_dist
	p.autoplay = true
	parent.add_child(p)
	return p


func start_ambient() -> void:
	ambient.stream = streams.get("ambient_drone")
	if ambient.stream and not ambient.playing:
		ambient.play()


func stop_all_loops() -> void:
	ambient.stop()
	alarm_player.stop()


func set_alarm(on: bool) -> void:
	if on:
		alarm_player.stream = streams.get("alarm")
		if alarm_player.stream:
			alarm_player.play()
	else:
		alarm_player.stop()
