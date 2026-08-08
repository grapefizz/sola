// Glassy sides, solid face panel, crisp eyes
varying vec4 viewPosition;
varying vec3 vertexNormal;

uniform float iceAlpha;
uniform vec3 iceTint;

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 texcolor = Texel(tex, texture_coords);
    float lum = dot(texcolor.rgb, vec3(0.299, 0.587, 0.114));

    // Face panel was baked fully opaque; sides are ~0.6–0.8 alpha
    float faceTile = smoothstep(0.88, 0.96, texcolor.a);

    vec3 N = normalize(vertexNormal);
    vec3 V = normalize(-viewPosition.xyz);
    float fresnel = pow(clamp(1.0 - abs(dot(N, V)), 0.0, 1.0), 1.5);

    float ink = (1.0 - smoothstep(0.05, 0.32, lum)) * faceTile;
    float highlight = smoothstep(0.85, 0.96, lum) * faceTile;

    // Soft glass on sides; face stays solid
    float glass = mix(iceAlpha, min(0.96, iceAlpha + 0.12), fresnel);
    float alpha = mix(glass * texcolor.a, 1.0, faceTile);
    alpha = max(alpha, ink);
    alpha = clamp(alpha * color.a, 0.0, 1.0);

    vec3 rgb = texcolor.rgb;
    rgb *= mix(iceTint, vec3(1.0), faceTile);
    rgb = mix(rgb, vec3(0.92, 0.98, 1.0), fresnel * 0.25 * (1.0 - faceTile));
    rgb = mix(rgb, vec3(0.03, 0.04, 0.06), ink);
    rgb = mix(rgb, vec3(1.0), highlight);

    // Premultiply for clean canvas compositing
    return vec4(rgb * alpha, alpha);
}
