#!/usr/bin/env python3
"""Ayudante de los ajustes de Menisco: edita la config de niri y el vidrio de Lniri.

Cada cambio se valida con `niri validate`; si la config queda mal, se deja como estaba
y se imprime el motivo (los ajustes lo muestran). niri recarga solo al guardarse el archivo.

Uso:
  menisco-niri.py esquinas 20
  menisco-niri.py espacio 16
  menisco-niri.py borde 40                     # opacidad del borde activo, en %
  menisco-niri.py salida HDMI-A-1 modo 1920x1080@143.999
  menisco-niri.py salida HDMI-A-1 escala 1.25
  menisco-niri.py salida HDMI-A-1 posicion 0 0
  menisco-niri.py salida HDMI-A-1 principal
  menisco-niri.py vidrio '{"refraccion":70,...}'
  menisco-niri.py atajo lanzador Mod+Space
"""
import json
import os
import re
import subprocess
import sys

NIRI = os.path.expanduser("~/.config/niri/config.kdl")
LNIRI = os.path.expanduser("~/.config/lniri")

# Atajos que se pueden cambiar: id -> texto que identifica la accion en su linea.
ATAJOS = {
    "lanzador": '"lanzador" "toggle"',
    "ajustes": '"ajustes" "toggle"',
    "captura": "Mod+Shift+S",          # se busca por la tecla actual (Print hace lo mismo)
    "bloquear": 'spawn "swaylock"',
    "terminal": 'spawn "alacritty"',
    "cerrar": "close-window",
    "vista": "toggle-overview",
    "maximizar": "maximize-column;",
}


def leer(ruta):
    with open(ruta, encoding="utf-8") as f:
        return f.read()


def guardar_validando(ruta, texto, validar_con=None):
    """Escribe y valida; si niri rechaza la config, restaura la anterior."""
    anterior = leer(ruta)
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(texto)
    r = subprocess.run(["niri", "validate", "-c", validar_con or ruta], capture_output=True, text=True)
    if r.returncode != 0:
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(anterior)
        error = (r.stderr or r.stdout).strip().splitlines()
        print("error: " + (error[-1] if error else "config invalida"))
        sys.exit(1)
    print("ok")


def bloque(texto, cabecera):
    """(inicio, fin) del bloque `cabecera {` ... `}` de primer nivel, o None."""
    m = re.search(r"^" + re.escape(cabecera) + r"\s*\{", texto, re.M)
    if not m:
        return None
    nivel, i = 0, m.end() - 1
    while i < len(texto):
        if texto[i] == "{":
            nivel += 1
        elif texto[i] == "}":
            nivel -= 1
            if nivel == 0:
                return m.start(), i + 1
        i += 1
    return None


def esquinas(n):
    t = leer(NIRI)
    t, k = re.subn(r"(geometry-corner-radius )\d+(\s*// esquinas-ventanas)", rf"\g<1>{int(n)}\2", t)
    if not k:
        sys.exit("error: falta la marca esquinas-ventanas")
    guardar_validando(NIRI, t)


def espacio(n):
    t = leer(NIRI)
    a, b = bloque(t, "layout")
    capa = re.sub(r"^(\s*gaps )\d+", rf"\g<1>{int(n)}", t[a:b], count=1, flags=re.M)
    guardar_validando(NIRI, t[:a] + capa + t[b:])


def borde(pct):
    alfa = round(int(pct) / 100 * 255)
    t = leer(NIRI)
    a, b = bloque(t, "layout")
    fa, fb = bloque(t[a:b], "    focus-ring")
    # ^\s* para no tocar "inactive-color", que tambien contiene "active-color".
    anillo = re.sub(r'^(\s*active-color ")#ffffff[0-9a-fA-F]{2}(")', rf"\g<1>#ffffff{alfa:02x}\2", t[a:b][fa:fb], flags=re.M)
    guardar_validando(NIRI, t[:a] + t[a:b][:fa] + anillo + t[a:b][fb:] + t[b:])


def salida(nombre, accion, *args):
    t = leer(NIRI)
    cab = f'output "{nombre}"'
    rango = bloque(t, cab)
    if not rango:
        t = t.rstrip("\n") + f"\n{cab} {{\n}}\n"
        rango = bloque(t, cab)
    a, b = rango
    cuerpo = t[a:b]

    def poner(clave, linea):
        nonlocal cuerpo
        if re.search(rf"^\s*{clave}\b", cuerpo, re.M):
            cuerpo = re.sub(rf"^\s*{clave}\b.*$", "    " + linea, cuerpo, count=1, flags=re.M)
        else:
            cuerpo = cuerpo[:-1].rstrip() + "\n    " + linea + "\n}"

    vivo = None
    if accion == "modo":
        poner("mode", f'mode "{args[0]}"')
        vivo = ["mode", args[0]]
    elif accion == "escala":
        poner("scale", f"scale {args[0]}")
        vivo = ["scale", args[0]]
    elif accion == "posicion":
        poner("position", f"position x={int(args[0])} y={int(args[1])}")
        vivo = ["position", "set", str(int(args[0])), str(int(args[1]))]
    elif accion == "principal":
        # Solo un monitor puede llevar focus-at-startup.
        t = re.sub(r"^\s*focus-at-startup\s*\n", "", t, flags=re.M)
        a, b = bloque(t, cab)
        cuerpo = t[a:b]
        cuerpo = cuerpo[:-1].rstrip() + "\n    focus-at-startup\n}"
    t = t[:a] + cuerpo + t[b:]
    guardar_validando(NIRI, t)
    if vivo:
        subprocess.run(["niri", "msg", "output", nombre] + vivo, capture_output=True)


def vidrio(js):
    v = json.loads(js)
    f = lambda clave, maximo: round(v[clave] / 100 * maximo, 2)
    optica = f"""        liquid-glass {{
            mode "kwin-glass"
            refraction-strength {f('refraccion', 6.0)}
            power-factor 2.4
            refraction-bevel-intensity {round(4 + v['refraccion'] / 100 * 18, 1)}
            refraction-offset-strength {round(2 + v['refraccion'] / 100 * 14, 1)}
            edge-thickness 0.3
            fringing {f('aberracion', 1.0)}
            glow-weight {f('brillo', 0.8)}
            edge-lighting {round(v['brillo'] / 100 * 1.5, 2)}
            saturation 1.3
        }}"""
    reglas = []
    if v.get("ventanas"):
        reglas.append(f"window-rule {{\n    background-effect {{\n        blur true\n        xray true\n{optica}\n    }}\n}}")
    if v.get("dock"):
        reglas.append(f'layer-rule {{\n    match namespace="^dock$"\n    geometry-corner-radius 22\n    background-effect {{\n        blur true\n        xray true\n{optica}\n    }}\n}}')
    texto = "// Generado por los ajustes de Menisco (menisco-niri.py vidrio). Se reescribe al cambiarlos.\n\n" + "\n\n".join(reglas) + "\n"
    activo = os.path.join(LNIRI, "vidrio-activo.kdl")
    with open(activo, "w", encoding="utf-8") as fh:
        fh.write(texto)
    encendido = os.path.getsize(os.path.join(LNIRI, "vidrio.kdl")) > 0
    if encendido:
        with open(os.path.join(LNIRI, "vidrio.kdl"), "w", encoding="utf-8") as fh:
            fh.write(texto)

    # El desenfoque es del bloque blur de niri (lo comparten niri y Lniri).
    t = leer(NIRI)
    d = v["desenfoque"] / 100
    nuevo = f"blur {{\n    passes {1 if d < 0.34 else 2 if d < 0.67 else 3}\n    offset {round(0.5 + d * 2.5, 2)}\n    noise 0      // sin grano\n}}"
    t = re.sub(r"^blur \{.*?^\}", nuevo, t, count=1, flags=re.M | re.S)
    guardar_validando(NIRI, t)


def atajo(id_, tecla):
    if id_ not in ATAJOS:
        sys.exit("error: atajo desconocido")
    t = leer(NIRI)
    a, b = bloque(t, "binds")
    binds = t[a:b]
    lineas = binds.split("\n")
    marca = ATAJOS[id_]
    idx = next((i for i, l in enumerate(lineas)
                if not l.strip().startswith("//") and
                (l.strip().startswith(marca + " ") if id_ == "captura" else marca in l)), None)
    if idx is None:
        sys.exit("error: no encontre ese atajo en la config")
    vieja = lineas[idx].split()[0]
    if tecla != vieja and any(l.split() and l.split()[0].lower() == tecla.lower() for l in lineas
                              if not l.strip().startswith("//")):
        print(f"error: {tecla} ya esta en uso")
        sys.exit(1)
    lineas[idx] = lineas[idx].replace(vieja, tecla, 1)
    if id_ == "captura":
        ATAJOS["captura"] = tecla
    guardar_validando(NIRI, t[:a] + "\n".join(lineas) + t[b:])


def atajos():
    """Imprime {id: tecla actual} para que los ajustes los muestren."""
    t = leer(NIRI)
    a, b = bloque(t, "binds")
    r = {}
    for id_, marca in ATAJOS.items():
        for l in t[a:b].split("\n"):
            s = l.strip()
            if s.startswith("//") or not s:
                continue
            if (s.startswith(marca + " ") if id_ == "captura" else marca in s):
                r[id_] = s.split()[0]
                break
    print(json.dumps(r))


if __name__ == "__main__":
    orden, *resto = sys.argv[1:]
    {"esquinas": esquinas, "espacio": espacio, "borde": borde, "salida": salida,
     "vidrio": vidrio, "atajo": atajo, "atajos": atajos}[orden](*resto)
