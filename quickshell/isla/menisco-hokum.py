#!/usr/bin/env python3
"""Ayudante de Ajustes > Notificaciones: edita ~/.config/hokum/config.kdl.

Toca solo el bloque `behaviour` y las reglas de una sola app (`rule app="X" { ... }`);
lo demas del archivo (tema, tokens, comentarios) queda igual. Cada cambio se valida con
`hokum check`: si Hokum lo rechaza, se deja como estaba. Hokum recarga solo al guardarse.

Uso:
  menisco-hokum.py leer                              # JSON con lo que muestran los ajustes
  menisco-hokum.py comportamiento position top-left  # valor "" = quitar (default de Hokum)
  menisco-hokum.py app Discord mostrar|ocultar si|no   # si/no = atraviesa No molestar

Hokum 0.1.2 (el instalado) todavia no conoce `sound`: su documentacion en GitHub va por delante.
  menisco-hokum.py quitar Discord
"""
import json
import os
import re
import subprocess
import sys

CONFIG = os.path.expanduser("~/.config/hokum/config.kdl")


def leer_archivo():
    try:
        with open(CONFIG, encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def guardar(texto):
    anterior = leer_archivo()
    with open(CONFIG, "w", encoding="utf-8") as f:
        f.write(texto)
    r = subprocess.run(["hokum", "check", CONFIG], capture_output=True, text=True)
    if r.returncode != 0:
        with open(CONFIG, "w", encoding="utf-8") as f:
            f.write(anterior)
        error = (r.stderr or r.stdout).strip().splitlines()
        print("error: " + (error[-1] if error else "config invalida"))
        sys.exit(1)
    print("ok")


def llaves(texto, inicio):
    """Posicion despues de la } que cierra la { que abre en `inicio`."""
    nivel = 0
    for i in range(inicio, len(texto)):
        if texto[i] == "{":
            nivel += 1
        elif texto[i] == "}":
            nivel -= 1
            if nivel == 0:
                return i + 1
    return len(texto)


def bloque_comportamiento(texto):
    m = re.search(r"^behaviour\s*\{", texto, re.M)
    return (m.start(), llaves(texto, m.end() - 1)) if m else None


def reglas(texto):
    """[(app, inicio, fin, cuerpo)] de las reglas que solo buscan por app."""
    r = []
    for m in re.finditer(r'^rule app="([^"]+)"\s*\{', texto, re.M):
        fin = llaves(texto, m.end() - 1)
        r.append((m.group(1), m.start(), fin, texto[m.end():fin - 1]))
    return r


def leer():
    t = leer_archivo()
    comp = {}
    b = bloque_comportamiento(t)
    if b:
        for linea in t[b[0]:b[1]].splitlines()[1:]:
            linea = linea.split("//")[0].strip().rstrip("}").strip()
            if linea:
                clave, _, valor = linea.partition(" ")
                comp[clave] = valor.strip().strip('"')
    apps = []
    for app, _, _, cuerpo in reglas(t):
        modo = "ocultar" if re.search(r"\bhide\b", cuerpo) else "mostrar"
        apps.append({"app": app, "modo": modo, "interrumpe": bool(re.search(r"\binterrupt\b", cuerpo))})
    print(json.dumps({
        "posicion": comp.get("position", "top-right"),
        "dura": comp.get("stay", "6"),
        "maximo": int(comp.get("show-at-most", "5")),
        "apps": apps,
    }))


def comportamiento(clave, valor):
    t = leer_archivo()
    b = bloque_comportamiento(t)
    if not b:
        t = t.rstrip("\n") + "\n\nbehaviour {\n}\n"
        b = bloque_comportamiento(t)
    cuerpo = t[b[0]:b[1]]
    cuerpo = re.sub(rf"^\s*{re.escape(clave)}\b.*\n", "", cuerpo, flags=re.M)
    if valor != "":
        cuerpo = cuerpo[:-1].rstrip() + f"\n    {clave} {valor}\n}}"
    guardar(t[:b[0]] + cuerpo + t[b[1]:])


def app(nombre, modo, interrumpe="no"):
    t = leer_archivo()
    previa = next((x for x in reglas(t) if x[0] == nombre), None)
    # De la regla anterior se conserva lo que no maneja Menisco (tokens, template, timeout...).
    resto = ""
    if previa:
        resto = re.sub(r"\b(hide|interrupt)\b", "", previa[3])
        resto = re.sub(r"[;\s]*\n[;\s]*", "\n", resto).strip(" ;\n")
    partes = [resto] if resto else []
    if modo == "ocultar":
        partes.append("hide")
    if interrumpe == "si":
        partes.append("interrupt")
    nueva = f'rule app="{nombre}" {{ {"; ".join(partes)} }}' if partes else ""
    if previa:
        t = t[:previa[1]] + nueva + t[previa[2]:]
        if not nueva:
            t = re.sub(r"\n{3,}", "\n\n", t)
    elif nueva:
        t = t.rstrip("\n") + "\n" + nueva + "\n"
    guardar(t)


def quitar(nombre):
    app(nombre, "mostrar")


if __name__ == "__main__":
    orden, *resto = sys.argv[1:]
    {"leer": leer, "comportamiento": comportamiento, "app": app, "quitar": quitar}[orden](*resto)
