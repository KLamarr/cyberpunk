// Materiale unico condiviso da tutti gli NPC. La mesh porta i colori della tavolozza nei
// vertex color; l'atlante npc_atlas.png aggiunge il dettaglio in scala di grigi (trama del
// tessuto, piastre, volto) con filtro nearest. Alpha del vertex color = 0 segna le parti
// luminose (visore, impianto CALMA), tinte dal colore per istanza che cambia con lo stato.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform float glow_energy = 1.6;
instance uniform vec4 glow_color : source_color = vec4(0.3, 0.9, 1.0, 1.0);

// I colori della tavolozza sono sRGB (quelli del selettore). Il renderer Compatibility
// lavora già in sRGB; Forward+ e Mobile lavorano in lineare e vanno convertiti.
vec3 palette_color(vec3 c, bool output_srgb) {
	if (output_srgb) {
		return c;
	}
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec3 t = texture(atlas, UV).rgb;
	float g = 1.0 - COLOR.a;
	vec3 base = t * palette_color(COLOR.rgb, OUTPUT_IS_SRGB);
	ALBEDO = mix(base, t * glow_color.rgb * 0.25, g);
	EMISSION = t * glow_color.rgb * g * glow_energy;
	ROUGHNESS = 1.0;
}
