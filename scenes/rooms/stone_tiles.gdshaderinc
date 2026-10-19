// World-space seams keep the pattern aligned across floor tiles and aisle strips.
// Derivative filtering avoids thin lines shimmering at the steep camera angle.
float stone_tiles(vec2 position) {
	vec2 tile = position / vec2(4.0, 3.0);
	vec2 edge = min(fract(tile), 1.0 - fract(tile));
	vec2 pixel_width = max(fwidth(tile), vec2(0.001));
	vec2 inside = smoothstep(vec2(0.006), vec2(0.006) + pixel_width, edge);
	float seam = 1.0 - min(inside.x, inside.y);
	float variation = mod(floor(tile.x) + floor(tile.y), 2.0) * 0.025;
	return 1.0 - variation - seam * 0.18;
}
