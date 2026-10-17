extends RefCounted

# Shared by equipment gauges, vulnerable parts and combat feedback.
const RING := Color("60dbde")
const BEAM := Color("f0d77b")
const CONE := Color("ed9966")
const CLOCK := Color("ba9ce9")

static func color_for(tool: StringName) -> Color:
	match tool:
		&"ring": return RING
		&"beam": return BEAM
		&"cone": return CONE
		&"clock": return CLOCK
	return Color.WHITE
