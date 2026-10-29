// Motor del asistente de la isla: forma y color por emocion (transformacion elastica),
// ojos proyectados sobre una esfera en 3D, mirada con saltos rapidos y parpadeos sueltos.
// Sin ".pragma library": cada isla (una por monitor) tiene su propio estado.

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

// Formas como funciones de distancia: el borde es donde valen 0.
var SDF = {
    esfera: function (x, y) { return circ(x, y, 0, 0, 0.95); },
    capsula: function (x, y) { var q = rotp(x, y, 0.03); return seg(q[0], q[1], -0.42, 0, 0.42, 0, 0.66); },
    triangulo: function (x, y) { return tri(x, y + 0.05); },
    gota: function (x, y) { return smin(circ(x, y, -0.03, -0.12, 0.82), circ(x, y, 0.26, 0.78, 0.12), 0.9); },
    nube: function (x, y) { return union(x, y, [[-0.6, 0.02, 0.44], [-0.15, 0.42, 0.48], [0.42, 0.3, 0.4], [0.55, -0.25, 0.44], [0.0, -0.45, 0.46], [-0.45, -0.38, 0.38]], undefined, 0.18); },
    trebol: function (x, y) { var q = rotp(x, y, 0.35); return union(q[0], q[1], [[0.42, 0.42], [-0.42, 0.42], [0.42, -0.42], [-0.42, -0.42]], 0.5, 0.2); }
};

// El contorno se guarda como un radio por angulo; asi dos formas se mezclan punto a punto.
function radios(f) {
    var r = [];
    for (var i = 0; i < N; i++) {
        var t = i / N * Math.PI * 2, cx = Math.cos(t), cy = Math.sin(t), lo = 0, hi = 2;
        for (var j = 0; j < 30; j++) { var m = (lo + hi) / 2; if (f(cx * m, cy * m) < 0) lo = m; else hi = m; }
        r.push(lo);
    }
    return r;
}

var EM = {
    normal:  { forma: "esfera",    color: [11, 11, 12],   ojo: { a: .105, b: .235, sep: .27, lat: .13,  tiltIzq: 0,    tiltDer: 0 } },
    feliz:   { forma: "capsula",   color: [0, 201, 111],  ojo: { a: .12,  b: .2,   sep: .3,  lat: .14,  tiltIzq: 0,    tiltDer: 0 } },
    escucha: { forma: "triangulo", color: [17, 134, 255], ojo: { a: .075, b: .15,  sep: .19, lat: -.12, tiltIzq: 0,    tiltDer: 0 } },
    pensar:  { forma: "gota",      color: [122, 122, 122],ojo: { a: .09,  b: .25,  sep: .24, lat: .06,  tiltIzq: -.12, tiltDer: -.12 } },
    emocion: { forma: "nube",      color: [255, 106, 0],  ojo: { a: .07,  b: .2,   sep: .24, lat: .26,  tiltIzq: 1.2,  tiltDer: 1.2 } },
    confuso: { forma: "trebol",    color: [148, 101, 58], ojo: { a: .07,  b: .18,  sep: .21, lat: .05,  tiltIzq: .5,   tiltDer: -.3 } }
};
for (var id in EM) EM[id].r = radios(SDF[EM[id].forma]);

var de = EM.normal, a_ = EM.normal, p = 1, vp = 0, actual = "normal";
var S = { yaw: 0, pitch: 0, vy: 0, vp: 0, ty: 0, tp: 0, parp: 1, rot: 0, vrot: 0, rapido: false };
var salto = 0, vs = 0, cola = [], parpadeos = [], base = { y: 0, p: 0 }, proximoPlan = 0;

function mezR(f) { var r = []; for (var i = 0; i < N; i++) r.push(de.r[i] + (a_.r[i] - de.r[i]) * f); return r; }
function mezC(f) { var c = Math.max(0, Math.min(1, f)); return de.color.map(function (v, i) { return v + (a_.color[i] - v) * c; }); }
function mezO(f) { var o = {}; for (var kk in a_.ojo) o[kk] = de.ojo[kk] + (a_.ojo[kk] - de.ojo[kk]) * f; return o; }

function parpadear(t, veces) { for (var i = 0; i < veces; i++) parpadeos.push(t + i * 175); }

function poner(nuevo) {
    if (!EM[nuevo] || nuevo === actual) return;
    de = { r: mezR(p), color: mezC(p), ojo: mezO(p) };
    a_ = EM[nuevo]; actual = nuevo; p = 0; vp = 0; vs = -0.09;
    parpadear(Date.now(), 1);
}

function azar(a, b) { return a + Math.random() * (b - a); }

// Que hace la mirada a continuacion. Tranquilo casi siempre; los arranques vivos son ocasionales.
function planear(t) {
    var r = Math.random();
    if (r < 0.45) {                      // mira a otro lado y, a veces, recorre con saltitos
        base = { y: azar(-0.65, 0.65), p: azar(-0.36, 0.36) };
        var lejos = len(base.y - S.yaw, base.p - S.pitch) > 0.5;
        cola.push({ t: t, y: base.y, p: base.p });
        if (lejos || Math.random() < 0.2) parpadear(t + 10, Math.random() < 0.3 ? 2 : 1);
        var tt = t + azar(250, 450);
        if (Math.random() < 0.45) {
            var n = Math.floor(azar(1, 3));
            for (var i = 0; i < n; i++) { cola.push({ t: tt, y: base.y + azar(-0.12, 0.12), p: base.p + azar(-0.07, 0.07) }); tt += azar(160, 320); }
        }
        return tt + azar(2500, 5500);
    } else if (r < 0.6) {                // vistazo de reojo y regresa
        var lado = Math.random() < 0.5 ? -1 : 1;
        cola.push({ t: t, y: lado * azar(0.55, 0.75), p: base.p + azar(-0.1, 0.1) });
        cola.push({ t: t + azar(280, 400), y: base.y, p: base.p });
        return t + azar(3000, 6000);
    } else if (r < 0.72) {               // rafaga corta de micro movimientos
        var t2 = t;
        for (var j = 0; j < 3; j++) { cola.push({ t: t2, y: base.y + azar(-0.1, 0.1), p: base.p + azar(-0.06, 0.06) }); t2 += azar(120, 200); }
        return t2 + azar(2500, 5000);
    }
    parpadear(t, Math.random() < 0.3 ? 2 : 1);   // solo parpadea
    return t + azar(2500, 6000);
}

// Resorte independiente de los Hz: dt = cuadros de 60 Hz transcurridos (0.42 a 144 Hz).
function resorte(x, v, objetivo, rigidez, freno, dt) {
    v = (v + (objetivo - x) * rigidez * dt) * Math.pow(freno, dt);
    return [x + v * dt, v];
}

// Avanza un cuadro. Devuelve true si algo se movio y hay que redibujar.
function avanzar(t, dt) {
    dt = Math.min(dt || 1, 3);
    if (actual === "pensar") { S.ty = 0.5; S.tp = 0.42; cola = []; S.rapido = false; }
    else {
        if (t > proximoPlan) proximoPlan = planear(t);
        while (cola.length && cola[0].t <= t) { var c = cola.shift(); S.ty = c.y; S.tp = c.p; S.rapido = true; }
    }
    var sp = S.rapido ? 0.26 : 0.09, dm = S.rapido ? 0.52 : 0.7;
    var r;
    r = resorte(S.yaw, S.vy, S.ty, sp, dm, dt); S.yaw = r[0]; S.vy = r[1];
    r = resorte(S.pitch, S.vp, S.tp, sp, dm, dt); S.pitch = r[0]; S.vp = r[1];
    r = resorte(p, vp, 1, 0.09, 0.74, dt); p = r[0]; vp = r[1];
    r = resorte(salto, vs, 0, 0.12, 0.78, dt); salto = r[0]; vs = r[1];
    var trot = actual === "confuso" ? Math.sin(t / 260) * 0.08 : 0;
    r = resorte(S.rot, S.vrot, trot, 0.1, 0.8, dt); S.rot = r[0]; S.vrot = r[1];

    parpadeos = parpadeos.filter(function (b) { return t - b < 200; });
    var pa = 1;
    for (var i = 0; i < parpadeos.length; i++) {
        var dt = t - parpadeos[i];
        if (dt < 0) continue;
        pa = Math.min(pa, dt < 55 ? 1 - dt / 55 : dt < 130 ? (dt - 55) / 75 : 1);
    }
    S.parp = Math.max(0, pa);

    var quieto = Math.abs(S.vy) + Math.abs(S.vp) + Math.abs(vp) + Math.abs(vs) + Math.abs(S.vrot) < 0.0004
              && Math.abs(S.ty - S.yaw) + Math.abs(S.tp - S.pitch) + Math.abs(1 - p) < 0.002
              && parpadeos.length === 0 && actual !== "confuso";
    return !quieto;
}

function rot3(q, yaw, pitch) {
    var x = q[0], y = q[1], z = q[2];
    var x1 = x * Math.cos(yaw) + z * Math.sin(yaw), z1 = -x * Math.sin(yaw) + z * Math.cos(yaw);
    return [x1, y * Math.cos(pitch) - z1 * Math.sin(pitch), y * Math.sin(pitch) + z1 * Math.cos(pitch)];
}
// Punto de la superficie de la esfera, desplazado (dx, dy) sobre el plano tangente.
function sup(lon, lat, dx, dy) {
    var P = [Math.sin(lon) * Math.cos(lat), Math.sin(lat), Math.cos(lon) * Math.cos(lat)];
    var E = [Math.cos(lon), 0, -Math.sin(lon)];
    var Nn = [-Math.sin(lon) * Math.sin(lat), Math.cos(lat), -Math.cos(lon) * Math.sin(lat)];
    var v = [P[0] + E[0] * dx + Nn[0] * dy, P[1] + E[1] * dx + Nn[1] * dy, P[2] + E[2] * dx + Nn[2] * dy];
    var l = Math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return [v[0] / l, v[1] / l, v[2] / l];
}
function pill(a, b, n) {
    var pts = [], c = Math.max(b - a, 0), i, t;
    for (i = 0; i <= n; i++) { t = Math.PI * i / n; pts.push([a * Math.cos(t), c + a * Math.sin(t)]); }
    for (i = 0; i <= n; i++) { t = Math.PI + Math.PI * i / n; pts.push([a * Math.cos(t), -c + a * Math.sin(t)]); }
    return pts;
}

// ojos: escala de los ojos; a tamano isla (unos 23 px) se ven mejor un poco mas grandes.
function dibujar(ctx, cx, cy, R, ojos) {
    ojos = ojos || 1;
    var r = mezR(p), col = mezC(p), o = mezO(p), i;
    ctx.save();
    ctx.translate(cx, cy + salto * R);
    ctx.rotate(S.rot);
    ctx.fillStyle = "rgb(" + Math.round(col[0]) + "," + Math.round(col[1]) + "," + Math.round(col[2]) + ")";
    ctx.beginPath();
    for (i = 0; i <= N; i++) {
        var j = i % N, t = j / N * Math.PI * 2;
        var x = Math.cos(t) * r[j] * R, y = -Math.sin(t) * r[j] * R;
        if (i) ctx.lineTo(x, y); else ctx.moveTo(x, y);
    }
    ctx.fill();

    // Al moverse rapido los ojos se ensanchan y se aplastan un poco, como en dibujos animados.
    var vel = Math.min(len(S.vy, S.vp) * 5, 0.28);
    var a = o.a * ojos * (1 + vel * 0.6), b = o.b * ojos * (1 - vel * 0.35) * Math.max(S.parp, 0.07);
    var lados = [-1, 1];
    for (var l = 0; l < 2; l++) {
        var lado = lados[l], lon = lado * o.sep, lat = o.lat;
        var c3 = rot3(sup(lon, lat, 0, 0), S.yaw, S.pitch);
        if (c3[2] < 0.05) continue;
        ctx.globalAlpha = Math.min(1, (c3[2] - 0.05) / 0.25);
        ctx.fillStyle = "#ffffff";
        ctx.beginPath();
        var tilt = -(lado < 0 ? o.tiltIzq : o.tiltDer);
        var pts = pill(a, b, 14);
        for (i = 0; i < pts.length; i++) {
            var e = rotp(pts[i][0], pts[i][1], tilt);
            var q = rot3(sup(lon, lat, e[0], e[1]), S.yaw, S.pitch);
            var X = q[0] * R * 0.95, Y = -q[1] * R * 0.95;
            if (i) ctx.lineTo(X, Y); else ctx.moveTo(X, Y);
        }
        ctx.closePath();
        ctx.fill();
        ctx.globalAlpha = 1;
    }
    ctx.restore();
}

// Cuando el asistente esta quieto, cuanto falta (ms) para su siguiente gesto.
function msHastaGesto() {
    var t = Date.now(), siguiente = proximoPlan;
    if (cola.length) siguiente = Math.min(siguiente, cola[0].t);
    for (var i = 0; i < parpadeos.length; i++) siguiente = Math.min(siguiente, parpadeos[i]);
    return Math.max(16, siguiente - t);
}
