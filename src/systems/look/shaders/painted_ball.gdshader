shader_type spatial;
// A moon seen from far off (a neighbour's sky, SpaceTravel._body): a smooth ball
// with the moon baked onto it as paint (tools/planets/bake_moon_paint.gd), not a
// lumpy low-poly rock. paint_tex: RGB the ground's colour (its rock, lava, the
// station's domes, tunnels and pit, the outposts), A how much light it gives off
// of its own (the lava, the station's lamps), from glow to hot. relief_tex: the ground's normal (world
// axes), so its craters still catch the one real sun. Same sun and wide twilight
// as the moon and lava rock shaders, so the ball matches the real one up close.

uniform samplerCube paint_tex : source_color, filter_linear_mipmap;
uniform samplerCube relief_tex : filter_linear_mipmap;
uniform float relief_tilt = 1.0;
uniform vec4 glow : source_color = vec4(1.0, 0.35, 0.08, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float glow_energy = 3.5;
uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform vec3 planet_center = vec3(0.0);
uniform vec4 dusk_color : source_color = vec4(0.22, 0.22, 0.26, 1.0);
uniform float dusk_strength = 0.25;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 up = normalize(wpos - planet_center);
	vec4 p = texture(paint_tex, up);
	vec3 rn = texture(relief_tex, up).rgb * 2.0 - 1.0;
	vec3 n = normalize(up + (rn - up * dot(rn, up)) * relief_tilt);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 alb = p.rgb;
	ALBEDO = alb;
	ROUGHNESS = 0.96;
	SPECULAR = 0.2;
	float sun_up = dot(up, normalize(sun_dir));
	vec3 light = mix(glow.rgb, hot.rgb, smoothstep(0.45, 0.95, p.a));
	EMISSION = light * p.a * glow_energy + alb * dusk_color.rgb * dusk_strength * smoothstep(0.25, -0.35, sun_up);
}
