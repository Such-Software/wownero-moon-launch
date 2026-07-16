shader_type canvas_item;
// Procedural animated starfield — twinkling stars at multiple depth layers.
// Apply to a ColorRect or Sprite2D that covers the screen.

uniform float star_density : hint_range(0.0, 0.02, 0.001) = 0.005;
uniform float twinkle_speed : hint_range(0.1, 5.0) = 2.5;
uniform float brightness : hint_range(0.5, 3.0) = 1.5;
uniform vec2 scroll_offset = vec2(0.0, 0.0);

// Hash function for pseudo-random star placement
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(443.897, 441.423, 437.195));
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth noise for twinkle variation
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Single star layer at given scale and speed.
// sharpen (0..1): near-layer waveform sharpening for dwell-then-flash blink.
float star_layer(vec2 uv, float scale, float speed_mult, float sharpen) {
	vec2 cell = floor(uv * scale);
	vec2 sub = fract(uv * scale);
	float rnd = hash(cell);
	// Only some cells have a star (density control)
	if (rnd > star_density * scale * 0.5) {
		return 0.0;
	}
	// Star position within cell
	vec2 star_pos = vec2(hash(cell + 0.1), hash(cell + 0.7));
	float dist = length(sub - star_pos);
	// Star radius varies
	float radius = 0.01 + rnd * 0.02;
	float star = smoothstep(radius, 0.0, dist);
	// Twinkle: phase varies per star, and rate varies per star so stars
	// desynchronize in *rate* not just phase.
	float phase = rnd * 6.283;
	float rate = 0.6 + 1.2 * hash(cell + 0.3);
	float base = 0.5 + 0.5 * sin(TIME * twinkle_speed * speed_mult * rate + phase);
	// Sharpen near-layer waveform (k~2.5): dwell-dim then flash reads as blinking.
	// max(base,0) guards pow() against sub-zero sin() on fast-approx mobile GPUs.
	float twinkle = mix(base, pow(max(base, 0.0), 2.5), sharpen);
	// Sparkle pop: ~10% of stars get an occasional bright high-freq glint,
	// applied branchlessly to keep the density early-out the only branch.
	float sparkle_mask = step(0.9, hash(cell + 0.5));
	float sparkle = 0.5 + 0.5 * sin(TIME * 6.0 + phase);
	twinkle *= mix(1.0, sparkle, sparkle_mask);
	// Slight color temperature shift per star
	return star * twinkle;
}

void fragment() {
	vec2 uv = SCREEN_UV + scroll_offset * 0.0001;
	// Deep black base
	vec3 col = vec3(0.02, 0.02, 0.04);
	// Layer 1: distant tiny stars (slow twinkle)
	float s1 = star_layer(uv, 80.0, 0.7, 0.0);
	col += vec3(0.7, 0.8, 1.0) * s1 * 0.6;
	// Layer 2: mid-depth stars
	float s2 = star_layer(uv + vec2(17.3, 31.7), 40.0, 1.0, 0.0);
	col += vec3(1.0, 0.95, 0.8) * s2 * 0.8;
	// Layer 3: near bright stars (fast twinkle, sharpened blink)
	float s3 = star_layer(uv + vec2(53.1, 97.3), 20.0, 1.5, 1.0);
	col += vec3(1.0, 1.0, 1.0) * s3 * 1.0;
	// Subtle nebula haze
	float n = noise(uv * 5.0 + TIME * 0.02);
	col += vec3(0.08, 0.03, 0.12) * n * 0.3;
	COLOR = vec4(col * brightness, 1.0);
}
