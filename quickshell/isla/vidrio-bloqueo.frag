#version 440
// Desbloqueo: la pantalla de bloqueo ("hoja") sube y su borde de abajo es liquid glass. En esa
// franja se ve lo de detras refractado (Snell simplificado, como el vidrio de Lniri) con los
// colores separados en el canto; las esquinas de abajo van redondeadas.
// Compilar: qsb --qt6 -o vidrio-bloqueo.frag.qsb vidrio-bloqueo.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 tam;       // tamano en pixeles
    float borde;    // y del borde de abajo de la hoja
    float radio;    // radio de las esquinas de abajo
    float banda;    // alto del vidrio, hacia arriba desde el borde
    float fuerza;   // desplazamiento maximo de la refraccion, en pixeles
    float croma;    // separacion de colores en el canto (0..1)
};
layout(binding = 1) uniform sampler2D hoja;
layout(binding = 2) uniform sampler2D detras;

// Distancia al contorno de la hoja (negativa dentro): rectangulo que llega hasta "borde" con las
// dos esquinas de abajo redondeadas.
float distHoja(vec2 p) {
    if (p.y > borde - radio && (p.x < radio || p.x > tam.x - radio)) {
        vec2 c = vec2(clamp(p.x, radio, tam.x - radio), borde - radio);
        return length(p - c) - radio;
    }
    return p.y - borde;
}

vec4 leer(sampler2D t, vec2 p) { return texture(t, clamp(p / tam, vec2(0.0), vec2(1.0))); }

void main() {
    vec2 p = qt_TexCoord0 * tam;
    float d = distHoja(p);
    vec4 fondo = leer(detras, p);
    if (d > 1.5) { fragColor = fondo * qt_Opacity; return; }

    // Contenido de la hoja, subido con ella.
    vec4 contenido = leer(hoja, vec2(p.x, p.y + (tam.y - borde)));

    // Perfil del vidrio: 1 abajo, 0 a "banda" px hacia arriba; curva concava como en Lniri. Se
    // mide en vertical (no al contorno) para que en las esquinas no haya un salto con los lados.
    float e = clamp(1.0 + (p.y - borde) / banda, 0.0, 1.0);
    float lente = 1.0 - sqrt(max(0.0, 1.0 - pow(smoothstep(0.0, 1.0, e), 2.2)));
    vec2 n = vec2(distHoja(p + vec2(2.0, 0.0)) - distHoja(p - vec2(2.0, 0.0)),
                  distHoja(p + vec2(0.0, 2.0)) - distHoja(p - vec2(0.0, 2.0)));
    n = length(n) > 0.001 ? normalize(n) : vec2(0.0, 1.0);
    float m = lente * fuerza;
    float r = leer(detras, p - n * m * (1.0 + croma)).r;
    float g = leer(detras, p - n * m).g;
    float b = leer(detras, p - n * m * (1.0 - croma)).b;
    vec3 vidrio = vec3(r, g, b);
    // Brillo del canto y un velo claro muy leve en todo el vidrio.
    float canto = smoothstep(-5.0, -1.0, d) * (1.0 - smoothstep(-1.0, 1.0, d));
    vidrio = mix(vidrio, vec3(1.0), canto * 0.6 + lente * 0.1 + 0.03);

    vec3 col = mix(contenido.rgb, vidrio, smoothstep(0.0, 0.85, e));
    float a = clamp(0.5 - d, 0.0, 1.0);
    fragColor = vec4(mix(fondo.rgb, col, a), 1.0) * qt_Opacity;
}
