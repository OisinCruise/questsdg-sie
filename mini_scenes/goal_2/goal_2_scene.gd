extends MiniScene

var intro_sequence: IntroSequence = null

func setup_scene() -> void:
	goal_number = 2

	if has_node("IntroSequence"):
		intro_sequence = $IntroSequence
		intro_sequence.sustainabot = sustainabot
