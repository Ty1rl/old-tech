extends RefCounted

# Shared by equipment gauges, vulnerable parts and combat feedback.
const RING := Color("60dbde")
const BEAM := Color("f0d77b")
const CONE := Color("ed9966")
const CLOCK := Color("ba9ce9")
# Gesture instructions stay neutral; green belongs to room exits.
const REPAIR_GUIDE := Color("e5ded0")
const EXIT := Color("83c9a2")

static func color_for(tool: StringName) -> Color:
	match tool:
		&"ring": return RING
		&"beam": return BEAM
		&"cone": return CONE
	return Color.WHITE
