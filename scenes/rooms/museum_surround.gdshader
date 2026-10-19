shader_type spatial;
render_mode unshaded, fog_disabled;

#include "res://scenes/rooms/stone_tiles.gdshaderinc"

// Decorative stone beyond the cutaway walls. Opaque and static: no textures,
// lights, transparency or animation. The playable floor sits above this plane.
uniform vec3 stone_color : source_color = vec3(0.115, 0.105, 0.092);
uniform vec3 darkness_color : source_color = vec3(0.024, 0.022, 0.020);
varying vec2 floor_position;

void vertex() {
	floor_position = VERTEX.xz;
}

void fragment() {
	float distance_to_center = max(abs(floor_position.x), abs(floor_position.y));
	float fade = smoothstep(24.0, 64.0, distance_to_center);
	vec3 stone = stone_color * stone_tiles(floor_position);
	ALBEDO = mix(stone, darkness_color, fade);
}
