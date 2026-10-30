import QtQuick
import "formas.js" as Formas

// Dibujo quieto de una gota (forma, color y dos ojos), para elegirla en Ajustes.
Canvas {
    id: dibujo
    property string forma: "esfera"
    property color color: "#0b0b0c"
    onFormaChanged: requestPaint()
    onColorChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const r = Formas.radios(forma), n = r.length, R = Math.min(width, height) * 0.45, cx = width / 2, cy = height / 2;
        ctx.fillStyle = color;
        ctx.beginPath();
        for (let i = 0; i <= n; i++) {
            const j = i % n, t = j / n * Math.PI * 2, x = cx + Math.cos(t) * r[j] * R, y = cy - Math.sin(t) * r[j] * R;
            if (i) ctx.lineTo(x, y); else ctx.moveTo(x, y);
        }
        ctx.fill();
        ctx.fillStyle = "#ffffff";
        const w = R * 0.19, h = R * 0.4;
        for (const lado of [-1, 1]) {
            ctx.beginPath();
            ctx.roundedRect(cx + lado * R * 0.25 - w / 2, cy - h / 2 - R * 0.06, w, h, w / 2, w / 2);
            ctx.fill();
        }
    }
}
