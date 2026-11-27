shader_type spatial;
// A plain-coloured held weapon part (the seeker launcher's tube, LauncherLook) that
// can stay in view through a scope: pinned to the eye there (viewmodel_pin,
// GunSights.pin) and cut nearer than near_clip (GunSights.scope_view), so the
// tube's top runs out under the scope and the part beside the eye is gone.
render_mode skip_vertex_transform;

#include "res://src/systems/look/shaders/viewmodel_pin.gdshaderinc"

// Both sides drawn: where near_clip cuts the tube open the inside shows as dark
// metal, not a hole.
render_mode cull_disabled;

uniform vec3 albedo : source_color = vec3(0.3);
// The favela's painted metal (StallTextures._metal_tex: chips, grime, seams,
// rivets, scratches), grey round white and tinted by albedo, triplanar in the
// part's own space at tex_scale tiles a metre. Off: flat albedo.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform float tex_scale = 3.0;
varying vec3 obj_pos;
varying vec3 obj_n;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float near_clip = 0.0;

void vertex() {
	obj_pos = VERTEX;
	obj_n = NORMAL;
	mat4 mv = pin_modelview(MODELVIEW_MATRIX);
	VERTEX = (mv * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(mat3(mv) * NORMAL);
	TANGENT = normalize(mat3(mv) * TANGENT);
	BINORMAL = normalize(mat3(mv) * BINORMAL);
}

void fragment() {
	if (-VERTEX.z < near_clip) {
		discard;
	}
	ALBEDO = albedo;
	if (use_tex) {
		vec3 w = pow(abs(obj_n), vec3(4.0));
		w /= max(w.x + w.y + w.z, 1e-4);
		vec3 p = obj_pos * tex_scale;
		ALBEDO *= texture(albedo_tex, p.zy).rgb * w.x + texture(albedo_tex, p.xz).rgb * w.y + texture(albedo_tex, p.xy).rgb * w.z;
		NORMAL_MAP = texture(normal_tex, p.zy).rgb * w.x + texture(normal_tex, p.xz).rgb * w.y + texture(normal_tex, p.xy).rgb * w.z;
		NORMAL_MAP_DEPTH = 0.7;
	}
	METALLIC = metallic;
	ROUGHNESS = roughness;
	if (!FRONT_FACING) {
		ALBEDO = vec3(0.012, 0.012, 0.014);
		METALLIC = 0.0;
		ROUGHNESS = 0.9;
	}
}
