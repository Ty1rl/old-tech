shader_type spatial;
render_mode cull_disabled;

#include "res://scenes/rooms/stone_tiles.gdshaderinc"

uniform vec3 base_color = vec3(0.20, 0.22, 0.23);
varying vec2 floor_position;

void vertex() {
	floor_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	ALBEDO = base_color * stone_tiles(floor_position);
	ROUGHNESS = 0.94;
}
