extends XRGrabbable
class_name WasteItem

# Simplified to 2-category system: Recyclable goes to RecyclingBin, Waste goes to WasteBin
enum WasteType { RECYCLABLE, WASTE }

@export var waste_type: WasteType = WasteType.RECYCLABLE
@export var item_name: String = "Generic Waste"

func _ready() -> void:
	# Set large grab distance for XR
	grab_distance = 0.5

	super._ready()

	# Ensure physics are enabled
	freeze = false
	gravity_scale = 1.0

	match waste_type:
		WasteType.RECYCLABLE:
			add_to_group("recyclable")
		WasteType.WASTE:
			add_to_group("waste")
			# Keep backward compatibility with old item scenes
			add_to_group("landfill")
			add_to_group("compostable")

func get_waste_type_name() -> String:
	match waste_type:
		WasteType.RECYCLABLE:
			return "recyclable"
		WasteType.WASTE:
			return "waste"
	return "unknown"
