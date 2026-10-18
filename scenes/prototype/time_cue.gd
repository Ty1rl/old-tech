extends CanvasLayer

# Screen tint distinguishes responsive slow time from frozen clock inspection.
# This is presentation only; it never changes either simulation clock.
var amount := 0.0
var target_amount := 0.0
var frozen := false
var panel: ColorRect
var caption: Label
var material: ShaderMaterial

func _ready() -> void:
	layer = 0 # Below the existing HUD layer.
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = ColorRect.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.18,0.35,0.65,1.0);
void fragment() {
	float edge = smoothstep(0.12,0.68,length(UV-vec2(0.5)));
	COLOR = vec4(tint.rgb, amount*(0.35+0.65*edge));
}
"""
	material = ShaderMaterial.new()
	material.shader = shader
	panel.material = material
	caption = Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",14)
	add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	caption.offset_top = 9
	caption.offset_bottom = 31
	caption.visible = false

func update_state(world_scale: float, inspecting: bool) -> void:
	frozen = inspecting
	target_amount = .24 if inspecting else .16 if world_scale < .999 else 0.0
	caption.text = "TIME FROZEN · SCROLL TO REVIEW" if inspecting else "TIME SLOW"
	caption.modulate = Color(.8,.7,1) if inspecting else Color(.65,.85,1)
	caption.visible = target_amount > 0
	material.set_shader_parameter("tint",Color(.3,.18,.55) if inspecting else Color(.12,.3,.55))

func _process(delta: float) -> void:
	amount = move_toward(amount,target_amount,maxf(0,delta)*1.8)
	material.set_shader_parameter("amount",amount)
