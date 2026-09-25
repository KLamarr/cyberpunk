// Post-process sul SubViewport a bassa risoluzione: quantizzazione del colore con
// dithering ordinato (Bayer 4x4), leggera vignettatura. Emula i 15/16 bit dell'epoca.
shader_type canvas_item;

uniform bool dither_enabled = true;
uniform float color_levels = 32.0;
uniform float dither_strength = 1.0;
uniform float brightness = 1.0;
uniform float vignette = 0.35;
uniform vec4 flash_color : source_color = vec4(0.0);

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb * brightness;
	if (dither_enabled) {
		ivec2 p = ivec2(floor(UV / TEXTURE_PIXEL_SIZE));
		int idx = (p.x % 4) + (p.y % 4) * 4;
		float t = (BAYER[idx] + 0.5) / 16.0 - 0.5;
		float lv = color_levels - 1.0;
		c = floor(c * lv + 0.5 + t * dither_strength) / lv;
	}
	vec2 d = UV - 0.5;
	c *= 1.0 - vignette * dot(d, d) * 2.0;
	c = mix(c, flash_color.rgb, flash_color.a);
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
