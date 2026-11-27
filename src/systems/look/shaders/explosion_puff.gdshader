shader_type spatial;
// One puff of an explosion's fireball or smoke (ExplosionFx), drawn on a camera-facing
// quad by a CPUParticles3D. No texture: a lumpy disc of value noise that eats itself
// away from the rim as the puff ages, so it reads as a solid billowing shape rather
// than a soft blob. The particle's colour ramp carries the white-hot -> orange ->
// red -> soot change over its life.
//
// Fire (roil 1) burns inside the puff: the thick middle and the bright billows run
// hot (yellow to white), the creases between them and the rim run cooler (orange to
// ember red), and the whole puff cools as it ages, handing over to the ramp's soot.
// Smoke (roil 0, shade 1) is one colour with a darker rim, lit as a lumpy ball: a dome
// over the disc, bent by the noise's own slope on screen (screen derivatives, no extra
// noise), lit by the sun with a little wrap, the sky's fill (darker deep in the puff),
// light through its thin rim when the sun is behind it, and a warm glow from below
// while it is young (the fire under it). ExplosionFx feeds it the sun.
//
// A jet (stretch > 0, on an emitter that aligns the particle's Y to its flight) is
// drawn long along where it is going, trailing back towards where it came from, and
// pulls in to a round puff as it slows and ages: tongues of flame thrown out of the
// burst. Same noise, same cost per pixel.
//
// INSTANCE_CUSTOM (CPUParticles3D): x = the particle's angle, y = its age 0..1,
// z = its anim offset, used as a steady random seed (ExplosionFx sets it 0..1).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float erode = 0.75;        // how much of the puff is eaten away by the end of its life
uniform float soft = 0.07;         // edge softness (small = crisp, toon-like)
uniform float energy = 3.0;        // HDR boost while young (the scene's glow picks it up)
uniform float heat = 1.5;          // extra white in the thick middle while young
uniform float shade = 0.0;         // 0 = fire, lit from within; 1 = smoke, lit from above
uniform float lumps = 2.4;         // noise frequency across the puff
uniform float roil = 0.0;          // 0 = one colour (smoke); 1 = fire burning hot and cool inside the puff
uniform float stretch = 0.0;       // a jet: this many times longer along its flight while young
uniform float bump = 1.1;          // smoke: how much the lumps bend its light
uniform float wrap = 0.25;         // smoke: how far the sun wraps round the puff
uniform float under_glow = 0.9;    // smoke: fire light on its underside while young
uniform vec3 sun_dir = vec3(0.3, 0.5, 0.8);       // world, towards the sun (ExplosionFx sets it)
uniform vec3 sun_col = vec3(1.35, 1.04, 0.73);
uniform vec3 amb_col = vec3(0.32, 0.29, 0.31);

varying vec3 v_custom;          // INSTANCE_CUSTOM, which fragment() cannot read
varying vec3 v_x;               // the quad's right and up in view space (smoke's dome)
varying vec3 v_y;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_custom = INSTANCE_CUSTOM.xyz;
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	if (stretch > 0.0) {
		// A jet: a screen-facing quad whose long side runs along the flight as the
		// camera sees it. Head-on it is barely stretched; side-on, fully.
		vec3 fly = mat3(VIEW_MATRIX) * (MODEL_MATRIX[1].xyz / max(sc.y, 1e-5));
		float side = length(fly.xy);
		vec2 y2 = side > 1e-4 ? fly.xy / side : vec2(0.0, 1.0);
		float young = 1.0 - INSTANCE_CUSTOM.y;
		float st = 1.0 + stretch * side * young * young;
		vec4 centre = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
		centre.xy -= y2 * sc.y * (st - 1.0) * 0.5;      // the head leads, the tail trails back
		float thin = 1.0 / (1.0 + 0.3 * (st - 1.0));         // longer is thinner
		MODELVIEW_MATRIX = mat4(vec4(y2.y, -y2.x, 0.0, 0.0) * sc.x * thin, vec4(y2, 0.0, 0.0) * sc.y * st, vec4(0.0, 0.0, sc.z, 0.0), centre);
	} else {
		// Face the camera (as StandardMaterial3D's particle billboard), turned by the
		// particle's angle and keeping its scale.
		mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
		float a = INSTANCE_CUSTOM.x;
		w = w * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * w;
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(sc.x, 0.0, 0.0, 0.0), vec4(0.0, sc.y, 0.0, 0.0), vec4(0.0, 0.0, sc.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_x = normalize(MODELVIEW_MATRIX[0].xyz);
	v_y = normalize(MODELVIEW_MATRIX[1].xyz);
}

void fragment() {
	float age = v_custom.y;
	float seed = v_custom.z * 61.0;
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	// The noise drifts a little as it ages: the puff boils instead of sliding.
	float n = fbm(UV * lumps + vec2(seed, seed * 1.37) + vec2(age * 0.6, -age * 0.9));
	float body = 1.0 - r + (n - 0.5) * 1.1;
	float cut = 0.04 + erode * age * age;
	float a = smoothstep(cut, cut + soft, body);
	if (a <= 0.001) {
		discard;
	}
	float young = 1.0 - smoothstep(0.15, 0.55, age);
	float core = smoothstep(cut + 0.05, cut + 0.6, body);
	vec3 col = COLOR.rgb;
	float burn = roil * (1.0 - smoothstep(0.38, 0.72, age));     // fire until it hands over to soot
	if (burn > 0.0) {
		// How hot this bit burns: deep in the puff and on the billows, cooling with age.
		float depth = smoothstep(cut, cut + 0.5, body);
		float billow = smoothstep(0.3, 0.75, n);
		float t = depth * mix(0.4, 1.2, billow) * (1.0 - 0.6 * age);
		vec3 hot = mix(vec3(0.45, 0.05, 0.015), vec3(1.0, 0.36, 0.06), smoothstep(0.1, 0.45, t));
		hot = mix(hot, vec3(1.0, 0.72, 0.3), smoothstep(0.45, 0.78, t));
		hot = mix(hot, vec3(1.0, 0.96, 0.86), smoothstep(0.78, 1.05, t));
		// The ramp still says how bright the puff is at this age; the heat picks the
		// colour inside it, and the cool creases sit darker than the hot billows.
		float lum = max(COLOR.r, max(COLOR.g, COLOR.b));
		col = mix(col, hot * lum * (0.3 + 1.25 * t), burn);
		col *= 1.0 + heat * young * core * core * billow;
		a *= mix(1.0, 0.7 + 0.3 * depth, burn);                       // thin hot gas at the rim
	} else {
		col *= 1.0 + heat * young * core * core;
	}
	float rim = smoothstep(cut, cut + 0.14, body);
	if (shade > 0.0) {
		// Smoke, lit as a lumpy ball (see the top). `shade` is a uniform, so the
		// derivatives are taken on every pixel of the puff alike.
		col *= mix(0.7, 1.0, rim);
		float px = max(length(vec2(dFdx(UV.x), dFdy(UV.x))) + length(vec2(dFdx(UV.y), dFdy(UV.y))), 1e-5) * 0.5;
		vec2 g = vec2(dFdx(body), -dFdy(body)) / px;
		vec2 off = c.x * v_x.xy - c.y * v_y.xy;
		vec3 nrm = normalize(vec3(off * 1.6 - g * bump * 0.15, sqrt(max(0.05, 1.0 - r * r))));
		vec3 down = normalize((VIEW_MATRIX * vec4(0.0, -1.0, 0.0, 0.0)).xyz);
		vec3 sun = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
		float thick = smoothstep(cut, cut + 0.6, body);
		float diff = clamp((dot(nrm, sun) + wrap) / (1.0 + wrap), 0.0, 1.0);
		float back = pow(clamp(-sun.z, 0.0, 1.0), 2.0) * (1.0 - thick) * 0.7;
		float fresh = 1.0 - smoothstep(0.0, 0.4, age);
		vec3 glow = vec3(1.0, 0.42, 0.12) * under_glow * fresh * fresh * clamp(dot(nrm, down) * 0.7 + 0.4, 0.0, 1.0);
		vec3 lit = amb_col * mix(1.0, 0.5, thick) + sun_col * (diff * mix(1.0, 0.85, thick) + back) + glow * 3.0;
		col *= mix(vec3(1.0), lit, shade);
	} else {
		col *= mix(mix(0.55, 1.0, rim), 1.0, burn);   // a darker rim, once fire is soot
	}
	col *= mix(1.0, energy, young);
	ALBEDO = col;
	ALPHA = a * COLOR.a;
}
