extends "res://scripts/journey_view.gd"
var timings:Dictionary={}
func record(key:String,begin:int)->void:
	timings[key]=timings.get(key,0)+Time.get_ticks_usec()-begin
func sync_world()->void:
	var t:=Time.get_ticks_usec();super();record("world",t)
func sync_events()->void:
	var t:=Time.get_ticks_usec();super();record("events",t)
func sync_static_hazards()->void:
	var t:=Time.get_ticks_usec();super();record("hazards",t)
func sync_gates()->void:
	var t:=Time.get_ticks_usec();super();record("gates",t)
func sync_journey_character(i:int)->void:
	var t:=Time.get_ticks_usec();super(i);record("characters",t)
func update_journey_ui()->void:
	var t:=Time.get_ticks_usec();super();record("ui",t)
func sync_view()->void:
	var t:=Time.get_ticks_usec();super();record("view_total",t)
func install_chunk_item(chunk:Node3D,item:Array)->void:
	var t:=Time.get_ticks_usec();super(chunk,item);record("install",t)
func rebuild_floor(chunk:Node3D,number:int)->void:
	var t:=Time.get_ticks_usec();super(chunk,number);record("floor",t)
func build_event(event:Dictionary)->Node3D:
	var t:=Time.get_ticks_usec();var result:Node3D=super(event);record("build_event",t);return result
