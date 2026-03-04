shader_type canvas_item;

uniform vec4 color : source_color = vec4(0.7, 0.0, 0.0, 0.4);
uniform float center_radius : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv) * 2.0;
	float a = smoothstep(center_radius, 0.95, d) * color.a;
	COLOR = vec4(color.rgb, a);
}
