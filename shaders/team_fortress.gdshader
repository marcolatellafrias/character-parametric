shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D albedo_tex    : source_color, hint_default_white;
uniform sampler2D ao_tex        : hint_default_white;
uniform sampler2D spec_mask_tex : hint_default_white;
uniform sampler2D warp_ramp_tex : source_color, hint_default_white;
uniform sampler2D normal_map_tex : hint_normal;

uniform vec3  light_dir         = vec3(0.5, 1.0, 0.5);
uniform vec4  rim_color         : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power         : hint_range(1.0, 8.0)   = 3.0;
uniform float rim_strength      : hint_range(0.0, 1.0)   = 0.3;
uniform float specular_power    : hint_range(1.0, 128.0) = 32.0;
uniform float specular_strength : hint_range(0.0, 1.0)   = 0.5;
uniform float ao_influence      : hint_range(0.0, 1.0)   = 0.5;

void fragment() {
    vec3  albedo    = texture(albedo_tex,    UV).rgb;
    float ao        = texture(ao_tex,        UV).r;
    float spec_mask = texture(spec_mask_tex, UV).r;

    // Normal map via TBN (requiere que la mesh tenga tangentes generadas)
    vec3 normal_ts = texture(normal_map_tex, UV).rgb * 2.0 - 1.0;
    mat3 TBN = mat3(normalize(TANGENT), normalize(BINORMAL), normalize(NORMAL));
    vec3 N = normalize(TBN * normal_ts);

    vec3 V = VIEW;
    vec3 L = normalize((VIEW_MATRIX * vec4(normalize(light_dir), 0.0)).xyz);

    // Warped diffuse: samplea el ramp con NdotL en [0,1]
    float NdotL = dot(N, L) * 0.5 + 0.5;
    float warp  = texture(warp_ramp_tex, vec2(NdotL, 0.5)).r;

    // AO como piso de luz ambiente
    float ambient = mix(1.0 - ao_influence, 1.0, ao);

    // Rim (fresnel)
    float fresnel = pow(1.0 - max(dot(N, V), 0.0), rim_power);
    vec3  rim     = fresnel * rim_strength * rim_color.rgb;

    // Specular Blinn-Phong
    vec3  H     = normalize(L + V);
    float spec  = pow(max(dot(N, H), 0.0), specular_power) * spec_mask * specular_strength;

    // Final: albedo * (ao + warp) + rim + specular
    ALBEDO = albedo * (ambient + warp) + rim + spec;
}