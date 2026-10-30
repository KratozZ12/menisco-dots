.pragma library
// Formas de las gotas del asistente, como funciones de distancia: el borde es donde valen 0
// (negativo = dentro). Las comparten el motor (asistente.js) y los dibujos quietos de Ajustes.

var N = 160;

function len(x, y) { return Math.sqrt(x * x + y * y); }
function smin(a, b, k) { var h = Math.max(k - Math.abs(a - b), 0) / k; return Math.min(a, b) - h * h * k * 0.25; }
function circ(x, y, cx, cy, r) { return len(x - cx, y - cy) - r; }
function rotp(x, y, a) { return [x * Math.cos(a) - y * Math.sin(a), x * Math.sin(a) + y * Math.cos(a)]; }
function seg(x, y, ax, ay, bx, by, r) {
    var px = x - ax, py = y - ay, dx = bx - ax, dy = by - ay;
    var h = Math.max(0, Math.min(1, (px * dx + py * dy) / (dx * dx + dy * dy)));
    return len(px - dx * h, py - dy * h) - r;
}
function tri(x, y) {
    var v = [[0, 0.78], [-0.78, -0.6], [0.78, -0.6]], d = 1e9, s = 1;
    for (var i = 0, j = 2; i < 3; j = i, i++) {
        var ex = v[j][0] - v[i][0], ey = v[j][1] - v[i][1], wx = x - v[i][0], wy = y - v[i][1];
        var h = Math.max(0, Math.min(1, (wx * ex + wy * ey) / (ex * ex + ey * ey)));
        d = Math.min(d, len(wx - ex * h, wy - ey * h));
        var c1 = y >= v[i][1], c2 = y < v[j][1], c3 = ex * wy > ey * wx;
        if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
    }
    return s * d - 0.24;
}
function union(x, y, cs, r, k) {
    var d = 1e9;
    for (var i = 0; i < cs.length; i++) d = smin(d, circ(x, y, cs[i][0], cs[i][1], r !== undefined ? r : cs[i][2]), k);
    return d;
}
// Forma dada por su radio en cada angulo (t = 0 a la derecha, crece hacia arriba).
function polar(R) { return function (x, y) { return len(x, y) - R(Math.atan2(y, x)); }; }
function modulo(a, m) { return ((a % m) + m) % m; }
// Poligono regular de lados n y apotema a, con un vertice arriba, esquinas suavizadas.
function poligono(n, a) {
    var paso = Math.PI * 2 / n;
    return polar(function (t) { return Math.min(a / Math.cos(modulo(t - Math.PI / 2, paso) - paso / 2), a * 1.13); });
}

var SDF = {
    esfera: function (x, y) { return circ(x, y, 0, 0, 0.95); },
    capsula: function (x, y) { var q = rotp(x, y, 0.03); return seg(q[0], q[1], -0.42, 0, 0.42, 0, 0.66); },
    triangulo: function (x, y) { return tri(x, y + 0.05); },
    gota: function (x, y) { return smin(circ(x, y, -0.03, -0.12, 0.82), circ(x, y, 0.26, 0.78, 0.12), 0.9); },
    nube: function (x, y) { return union(x, y, [[-0.6, 0.02, 0.44], [-0.15, 0.42, 0.48], [0.42, 0.3, 0.4], [0.55, -0.25, 0.44], [0.0, -0.45, 0.46], [-0.45, -0.38, 0.38]], undefined, 0.18); },
    trebol: function (x, y) { var q = rotp(x, y, 0.35); return union(q[0], q[1], [[0.42, 0.42], [-0.42, 0.42], [0.42, -0.42], [-0.42, -0.42]], 0.5, 0.2); },
    cuadro: polar(function (t) { return 0.8 / Math.pow(Math.pow(Math.abs(Math.cos(t + 0.3)), 4) + Math.pow(Math.abs(Math.sin(t + 0.3)), 4), 0.25); }),
    estrella: polar(function (t) { return 0.6 + 0.38 * Math.pow(Math.abs(Math.cos(2 * t)), 3); }),
    flor: polar(function (t) { return 0.75 + 0.2 * Math.cos(5 * (t - Math.PI / 2)); }),
    corazon: function (x, y) { x *= 1.2; y = y * 1.2 + 0.12; var a = x * x + y * y - 1; return a * a * a - x * x * y * y * y; },
    flor8: polar(function (t) { return 0.8 + 0.13 * Math.cos(8 * t); }),
    pentagono: poligono(5, 0.74),
    engrane: polar(function (t) { var c = Math.cos(8 * t) * 4, e = Math.exp(2 * c); return 0.78 + 0.16 * (e - 1) / (e + 1); }),
    hexagono: poligono(6, 0.8),
    calabaza: polar(function (t) { return 0.85 + 0.08 * Math.abs(Math.cos(3 * t)); })
};

// Las que se ofrecen en Ajustes, en orden (trebol queda solo para "confuso").
var LISTA = ["esfera", "nube", "cuadro", "estrella", "flor", "corazon", "flor8",
             "gota", "capsula", "triangulo", "pentagono", "engrane", "hexagono", "calabaza"];

// El contorno se guarda como un radio por angulo; asi dos formas se mezclan punto a punto.
var cache = {};
function radios(nombre) {
    if (cache[nombre]) return cache[nombre];
    var f = SDF[nombre] || SDF.esfera, r = [];
    for (var i = 0; i < N; i++) {
        var t = i / N * Math.PI * 2, cx = Math.cos(t), cy = Math.sin(t), lo = 0, hi = 2;
        for (var j = 0; j < 30; j++) { var m = (lo + hi) / 2; if (f(cx * m, cy * m) < 0) lo = m; else hi = m; }
        r.push(lo);
    }
    return cache[nombre] = r;
}
