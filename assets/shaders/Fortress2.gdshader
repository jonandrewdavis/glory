// 2D starfield in the sky with scrolling effect ver 1.0
// Source: https://godotshaders.com/shader/2d-starfield-in-the-sky-with-scrolling-effect-ver-1-0/ (CC0)
shader_type canvas_item;

// Global multiplier on TIME; 1.0 is the original speed, 0.03 is barely perceptible.
uniform float time_scale : hint_range(0.0, 1.0, 0.001) = 0.005;
// Fraction of grid cells that actually contain a star; 1.0 is the original (every cell).
uniform float star_fill : hint_range(0.0, 1.0, 0.01) = 0.12;
// Extra multiplier on top of time_scale for twinkling only.
uniform float twinkle_time_scale : hint_range(0.0, 1.0, 0.01) = 0.05;
// Star sway runs on real time (not time_scale) so it stays visible while everything else crawls.
uniform float sway_amount : hint_range(0.0, 0.5, 0.01) = 0.08;
// Camera position in pixels, fed by sky_parallax.gd. Layers shift at different rates for depth.
uniform vec2 camera_offset = vec2(0.0);
uniform float parallax_strength : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float density : hint_range(0.0, 300.0, 1.) = 150.;
uniform int layer_parascale : hint_range(0, 5, 1) = 2;
uniform float speedx : hint_range(-10.0, 10.0, 0.1) = 0.1;
uniform float speedy : hint_range(-10.0, 10.0, 0.1) = 0.;
uniform float star_horizontal_wave : hint_range(0.0, 10.0, 0.1) = 0.15;
uniform float star_size : hint_range(0.0, 100.0, 0.1) = 2.0;
uniform float twinkle_effect : hint_range(0.0, 1.0, 0.1) = 0.08;
uniform float twinkle_speed : hint_range(0.0, 100.0, 0.1) = 0.3;

uniform float fbm_strength : hint_range(0.0, 3.0, 0.01) = 0.03;
uniform float fbm_mix : hint_range(0.0, 1.0, 0.01) = 0.02;
uniform float fbm_freq : hint_range(0, 200, 1) = 4;
uniform float fbm_amp : hint_range(0, 10., 0.01) = 1.5;
uniform float fbm_speed : hint_range(-10.0, 10.0, 0.01) = 5.;
uniform float warp_scale : hint_range(0, 10., 0.01) = 2.;

uniform float cloud_freq : hint_range(0, 100, 1) = 40;
uniform float cloud_amp : hint_range(0, 1., 0.01) = 0.0;
uniform float cloud_speed : hint_range(0, 10., 0.01) = 5.;

uniform float cloud_color_ci1 : hint_range(0, 1., 0.01) = 0.75;
uniform float cloud_color_ci2 : hint_range(0, 1., 0.01) = 0.45;
uniform float cloud_color_ci3 : hint_range(0, 1., 0.01) = 0.9;
uniform float cloud_color_shiftx : hint_range(-100, 100., 0.5) = 0.;
uniform float cloud_color_shifty : hint_range(-100, 100., 0.5) = 0.;

uniform vec3 background_color : source_color = vec3(0.02, 0.04, 0.12);

float onedx(float x) {
	return x == 0. ? 1. : 1.0 / x;
}

float onedx2(float x) {
	return onedx(x) * onedx(x);
}

float getBetaW(float x, float f, float size) {
	return size * x * PI / f;
}

float getBetaH(float y, float f, float size) {
	return size * y * PI / f;
}

float getI(vec2 uv, float f, vec2 SIZE) {
	return onedx2(getBetaW(uv.x, f, SIZE.x)) * onedx2(getBetaH(uv.y, f, SIZE.y));
}

float random(vec2 st) {
	return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43759.5453123);
}

float noise(vec2 st) {
	vec2 i = floor(st);
	vec2 f = fract(st);

	float a = random(i);
	float b = random(i + vec2(1.0, 0.0));
	float c = random(i + vec2(0.0, 1.0));
	float d = random(i + vec2(1.0, 1.0));

	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(a, b, u.x) +
		(c - a) * u.y * (1.0 - u.x) +
		(d - b) * u.x * u.y;
}

float fbm(vec2 st) {
	float value = 0.0;
	float freq = fbm_freq;
	float amp = fbm_amp;

	for (int i = 0; i < 5; i++) {
		value += fbm_amp * noise(st * freq);
		freq *= 2.7;
		amp *= 0.5;
	}

	return value;
}

vec2 clouduv(vec2 uv, float time, vec2 centers[6]) {
	const int count = 3;
	const vec2 flowDir = vec2(0.20, -0.07);

	vec2 cloud_shiftspeed = time * vec2(speedx, speedy) * fbm_speed;
	vec2 p = uv * warp_scale - cloud_shiftspeed;
	vec2 warp = vec2(
		fbm(p + vec2(5.2, 1.3) + time * flowDir * 1.2),
		fbm(p + vec2(-2.8, 3.1) - time * flowDir * 0.9)
	);

	uv += (warp - 0.5) * fbm_strength;

	for (int i = 0; i < count; i++) {
		vec2 toC = uv - centers[i];
		float r = length(toC) + 1e-6;
		float rip = sin(r * cloud_freq - time * cloud_speed) * cloud_amp;
		uv += normalize(toC) * rip;
	}

	return uv;
}

vec2 getSnowflakeWorldCenter(vec2 gridId, vec2 timeOffset, vec2 snowOffset, float layerScale) {
	return (gridId + snowOffset + timeOffset) / layerScale;
}

vec2 rotate(vec2 uv, float addtheta) {
	float theta = atan(uv.y, uv.x) + addtheta;
	float r = sqrt(uv.x * uv.x + uv.y * uv.y);
	vec2 ruv;
	ruv.x = r * cos(theta);
	ruv.y = r * sin(theta);

	return ruv;
}

void fragment() {
	vec3 color = background_color;
	float t = TIME * time_scale;

	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 st = SCREEN_UV;
	st.x = st.x / screen_size.y * screen_size.x;

	vec2 cuv = (st - 0.5) * 2.0;

	for (int layer = 0; layer < 4; layer++) {
		float layerScale = exp(float(layer * layer_parascale + 1) * density * 0.002);
		vec2 layerSpeed = vec2(speedx, speedy) * vec2(1.0 + float(layer) * 0.3);
		float layerSize = star_size * (1.0 - float(layer) * 0.2);

		vec2 layerSt = st * layerScale;
		vec2 cuvSt = cuv;

		// Nearer layers (lower index, bigger and brighter stars) move more with the camera.
		vec2 parallax = camera_offset / screen_size.y * layerScale * parallax_strength * (1.0 - float(layer) * 0.2);
		vec2 timeOffset = t * layerSpeed - parallax;
		layerSt -= timeOffset;

		vec2 gridSt = fract(layerSt);
		vec2 gridId = floor(layerSt);

		float randSeed = random(gridId);
		if (random(gridId + vec2(11.7, 3.3)) > star_fill) {
			continue;
		}

		vec2 snowPos = vec2(
			0.5 + sway_amount * sin(randSeed * 6.28 + TIME * star_horizontal_wave),
			0.5 + 0.2 * cos(randSeed * 12.56)
		);

		float dist = distance(gridSt, snowPos);

		float snowSize = layerSize * 0.01 * (0.5 + 0.5 * randSeed);
		float brightness = 1.0 - float(layer) * 0.3;

		float M = exp(-dist * dist / (snowSize * snowSize));

		float rotateAngle = 0.01 * (t * cos(randSeed * 120.0 + t * 0.05));

		vec2 fst = rotate(cuvSt - (getSnowflakeWorldCenter(gridId, timeOffset, snowPos, layerScale) - 0.5) * 2.0, rotateAngle);

		float snowflake = M * 0.5 * (getI(fst, 0.8 - dist * 42.0, vec2(1.0 / snowSize)) + 1.);

		float tt = t * twinkle_time_scale;
		float twinkle = (1. - twinkle_effect) + twinkle_effect * (sin(randSeed * 100.0 + tt * twinkle_speed) * cos(randSeed * 120.0 + tt * (twinkle_speed + 2.)));
		snowflake *= twinkle;

		vec3 colortype = vec3(random(gridId - 3.0), random(gridId + 7.0), random(gridId + 5.0));

		color = max(color + (snowflake * brightness) * colortype, color);
	}

	vec2 centers[6];
	centers[0] = vec2(-0.3, 0.4);
	centers[1] = vec2(0.7, -0.5);
	centers[2] = vec2(-0.5, 0.7);

	cuv -= vec2(cloud_color_shiftx, cloud_color_shifty);
	vec2 fuv = clouduv(cuv, t, centers);

	COLOR = vec4(mix(color, vec3(fuv.x * (1. - cloud_color_ci1) + fuv.y * cloud_color_ci2, fuv.x * (1. - cloud_color_ci3) + fuv.y * cloud_color_ci2, fuv.x * (1. - cloud_color_ci3) + fuv.y * cloud_color_ci1), fbm_mix), 1.0);
}
