shader_type canvas_item;
uniform float flash = 0.0;
varying vec4 vertex_tint;
void vertex() {
	vertex_tint = COLOR;
}
void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	COLOR = vec4(mix(texel.rgb, vec3(1.0), flash), texel.a) * vertex_tint;
}
