// Superfici del livello: texture scelta in base all'orientamento della faccia
// (pavimento / soffitto / pareti), proiettata in spazio mondo come nel Dark Engine,
// dove i brush avevano densità di texel costante. Filtro nearest + mipmap.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D tex_wall : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D tex_floor : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D tex_ceil : source_color, filter_nearest_mipmap, repeat_enable;
uniform float wall_scale = 0.5;   // ripetizioni per metro
uniform float floor_scale = 0.5;
uniform float ceil_scale = 0.5;
uniform vec3 tint : source_color = vec3(1.0);
uniform float specular_amount = 0.15;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 n = normalize(wnorm);
	// tutte le coordinate dipendono solo dalla posizione: derivate continue, niente cuciture di mip
	vec3 cx = texture(tex_wall, vec2(wpos.z, -wpos.y) * wall_scale).rgb;
	vec3 cz = texture(tex_wall, vec2(wpos.x, -wpos.y) * wall_scale).rgb;
	vec3 cf = texture(tex_floor, wpos.xz * floor_scale).rgb;
	vec3 cc = texture(tex_ceil, wpos.xz * ceil_scale).rgb;
	vec3 wall = abs(n.x) > abs(n.z) ? cx : cz;
	vec3 c = n.y > 0.6 ? cf : (n.y < -0.6 ? cc : wall);
	ALBEDO = c * tint;
	ROUGHNESS = 0.85;
	SPECULAR = specular_amount;
}
