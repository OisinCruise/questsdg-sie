extends XRGrabbable
class_name WasteItem
## What: Grabbable waste with 2-category sorting system
## Who: XRGrabbable parent, goal_12_scene bin detection
## Why: Goal 12 responsible consumption - sort waste correctly

enum WasteType { RECYCLABLE, WASTE }

@export var waste_type: WasteType = WasteType.RECYCLABLE
@export var item_name: String = "Generic Waste"

func _ready() -> void:
	grab_distance = 0.5
	super._ready()
	freeze = false
	gravity_scale = 1.0
	
	match waste_type:
		WasteType.RECYCLABLE:
			add_to_group("recyclable")
		WasteType.WASTE:
			add_to_group("waste")
			add_to_group("landfill")  # legacy compat
			add_to_group("compostable")

func get_waste_type_name() -> String:
	match waste_type:
		WasteType.RECYCLABLE:
			return "recyclable"
		WasteType.WASTE:
			return "waste"
	return "unknown"
