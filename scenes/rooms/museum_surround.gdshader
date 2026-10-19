shader_type spatial;
render_mode unshaded, fog_disabled;

// Decorative stone beyond the cutaway walls. Opaque and static: no textures,
// lights, transparency or animation. The playable floor sits above this plane.
uniform vec3 stone_color : source_color = vec3(0.115, 0.105, 0.092);
uniform vec3 darkness_color : source_color = vec3(0.024, 0.022, 0.020);
varying vec2 floor_position;

void vertex() {
	floor_position = VERTEX.xz;
}

void fragment() {
	vec2 tile = floor_position / vec2(4.0, 3.0);
	vec2 edge = min(fract(tile), 1.0 - fract(tile));
	vec2 pixel_width = max(fwidth(tile), vec2(0.001));
	vec2 inside = smoothstep(vec2(0.006), vec2(0.006) + pixel_width, edge);
	float seam = 1.0 - min(inside.x, inside.y);
	float variation = mod(floor(tile.x) + floor(tile.y), 2.0) * 0.025;
	float distance_to_center = max(abs(floor_position.x), abs(floor_position.y));
	float fade = smoothstep(24.0, 64.0, distance_to_center);
	vec3 stone = stone_color * (1.0 - variation - seam * 0.18);
	ALBEDO = mix(stone, darkness_color, fade);
}
