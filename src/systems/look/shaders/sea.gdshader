shader_type spatial;
// Issue #879: the round sea of the tide world (OceanSphere, the water_ball type).
// The ball's ground mesh drawn as water: the water type's colours (color near,
// deep far and looking down into it), glossy, with long rollers and fine chop in
// its normals (the same swell the speeders ride: OceanSphere.swell) and foam on
// the crests. Anything the planet stands up out of the sea (its outposts' pads,
// the speeder pad out front) is a rusted pontoon: riveted plate in the pad colour
// with streaks of rust, its sides darker. Same layering as the sand (planet_center/
// radius, the per-instance hole that sinks an outer layer under the inner one)
// and the same twilight, so one real sun lights it like the other planets.

uniform vec4 color : source_color = vec4(0.11, 0.31, 0.43, 1.0);
uniform vec4 deep : source_color = vec4(0.04, 0.13, 0.21, 1.0);
uniform vec4 foam : source_color = vec4(0.85, 0.91, 0.93, 1.0);
uniform vec4 pad : source_color = vec4(0.48, 0.29, 0.18, 1.0);
uniform float roughness = 0.08;
uniform float metallic = 0.2;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform vec3 planet_center = vec3(0.0);
uniform float planet_radius = 0.0;
uniform float sea_radius = 0.0;           // the still sea's radius (planet_radius - depth)
uniform float swell_s = 7.0;
uniform float hole_sink = 6.0;
uniform vec4 dusk_color : source_color = vec4(0.12, 0.16, 0.24, 1.0);
uniform float dusk_strength = 0.25;
instance uniform vec4 hole_origin = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform vec3 hole_x = vec3(1.0, 0.0, 0.0);
instance uniform vec3 hole_z = vec3(0.0, 0.0, 1.0);

varying vec3 wpos;
varying vec3 wup;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wup = planet_radius > 0.0 ? normalize(wpos - planet_center) : vec3(0.0, 1.0, 0.0);
	if (hole_origin.w > 0.0) {
		vec3 rel = wpos - hole_origin.xyz;
		float edge = max(abs(dot(rel, hole_x)), abs(dot(rel, hole_z)));
		float k = 1.0 - smoothstep(hole_origin.w * 0.92, hole_origin.w * 1.02, edge);
		if (k > 0.0) {
			wpos -= wup * hole_sink * k;
			VERTEX = (inverse(MODEL_MATRIX) * vec4(wpos, 1.0)).xyz;
		}
	}
}

float n2(vec2 p) {
	return texture(noise_tex, p).r;
}

void fragment() {
	vec3 up = normalize(wup);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float lift = planet_radius > 0.0 ? length(wpos - planet_center) - sea_radius : 0.0;
	// A tangent frame on the ball for the ripples (any axis not along up).
	vec3 ax = abs(up.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tx = normalize(cross(ax, up));
	vec3 tz = cross(up, tx);
	vec2 uv = vec2(dot(wpos, tx), dot(wpos, tz));

	if (lift > 0.35) {
		// A pontoon: plate in a grid of panels, rivet lines, rust streaks; its ramps darker.
		vec2 cell = fract(uv / 2.5);
		float seam = step(cell.x, 0.03) + step(cell.y, 0.03);
		float rust = smoothstep(0.35, 0.8, n2(uv * 0.011) * 0.6 + n2(uv * 0.07) * 0.4);
		vec3 plate = mix(pad.rgb, pad.rgb * vec3(0.62, 0.45, 0.35), rust);
		plate *= 1.0 - 0.35 * clamp(seam, 0.0, 1.0);
		plate *= 0.9 + 0.2 * n2(floor(uv / 2.5) * 0.37);
		float side = 1.0 - clamp(dot(normalize(NORMAL), normalize((VIEW_MATRIX * vec4(up, 0.0)).xyz)), 0.0, 1.0);
		plate *= 1.0 - 0.45 * smoothstep(0.08, 0.4, side);
		// A tide line just above the water.
		plate = mix(plate * 0.55, plate, smoothstep(0.35, 0.9, lift));
		ALBEDO = plate;
		ROUGHNESS = 0.85;
		METALLIC = 0.5;
		SPECULAR = 0.3;
	} else {
		float t = TIME;
		float w = 6.2831853 / max(swell_s, 0.5);
		// Long rollers (as OceanSphere.swell) and two layers of chop drifting across.
		float roll = sin(uv.x * 0.045 + uv.y * 0.02 - t * w);
		float c1 = n2(uv * 0.018 + vec2(t * 0.012, t * 0.007));
		float c2 = n2(uv * 0.09 - vec2(t * 0.03, -t * 0.021));
		float c3 = n2(uv * 0.35 + vec2(t * 0.06, t * 0.05));
		float near_k = 1.0 - smoothstep(60.0, 900.0, dist);
		vec2 slope = vec2(cos(uv.x * 0.045 + uv.y * 0.02 - t * w) * 0.045, 0.0) * 6.0
			+ (vec2(c1, c2) - 0.5) * 0.22 + (vec2(c2, c3) - 0.5) * 0.16 * near_k;
		vec3 n_world = normalize(up - tx * slope.x - tz * slope.y);
		NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
		vec3 to_eye = normalize(CAMERA_POSITION_WORLD - wpos);
		float facing = clamp(dot(to_eye, up), 0.0, 1.0);
		vec3 water = mix(color.rgb, deep.rgb, pow(facing, 0.6) * 0.7 + smoothstep(400.0, 4000.0, dist) * 0.3);
		// Thin foam on the rollers' crests only (fine noise, so no floes), fading off far.
		float crest = smoothstep(0.86, 0.98, roll * 0.5 + 0.5) * smoothstep(0.62, 0.8, c3) * near_k;
		// Foam where the water laps a pad's foot (a band up its ramp, clear of the
		// open sea's float noise: the mesh is only ever ~cm off the still sea there).
		float lap = smoothstep(0.06, 0.14, lift) * (1.0 - smoothstep(0.2, 0.35, lift));
		water = mix(water, foam.rgb, clamp(crest * 0.4 + lap * (0.45 + 0.35 * c3), 0.0, 1.0));
		ALBEDO = water;
		ROUGHNESS = mix(roughness, 0.4, crest);
		METALLIC = metallic;
		SPECULAR = 0.6;
	}
	if (planet_radius > 0.0) {
		float sun_up = dot(up, normalize(sun_dir));
		EMISSION = ALBEDO * dusk_color.rgb * dusk_strength * smoothstep(0.25, -0.35, sun_up);
	}
}
