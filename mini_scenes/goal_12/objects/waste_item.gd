extends XRGrabbable
class_name WasteItem

enum WasteType { RECYCLABLE, COMPOSTABLE, LANDFILL }

@export var waste_type: WasteType = WasteType.RECYCLABLE
@export var item_name: String = "Generic Waste"

func _ready() -> void:
	super._ready()

	match waste_type:
		WasteType.RECYCLABLE:
			add_to_group("recyclable")
		WasteType.COMPOSTABLE:
			add_to_group("compostable")
		WasteType.LANDFILL:
			add_to_group("landfill")

func get_waste_type_name() -> String:
	match waste_type:
		WasteType.RECYCLABLE:
			return "recyclable"
		WasteType.COMPOSTABLE:
			return "compostable"
		WasteType.LANDFILL:
			return "landfill"
	return "unknown"
