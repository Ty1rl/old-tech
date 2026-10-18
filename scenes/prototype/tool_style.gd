extends RefCounted

# Shared by equipment gauges, vulnerable parts and combat feedback.
const RING := Color("60dbde")
const BEAM := Color("f0d77b")
const CONE := Color("ed9966")

static func color_for(tool: StringName) -> Color:
	match tool:
		&"ring": return RING
		&"beam": return BEAM
		&"cone": return CONE
	return Color.WHITE
