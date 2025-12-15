extends MiniScene

var intro_sequence: IntroSequence = null

func setup_scene() -> void:
	goal_number = 1

	if has_node("IntroSequence"):
		intro_sequence = $IntroSequence
		intro_sequence.sustainabot = sustainabot
