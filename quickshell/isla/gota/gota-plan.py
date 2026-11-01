#!/usr/bin/env python3
"""Aplica (o deshace) un plan de la Gota. La IA nunca cambia nada: lo hace este guion,
y solo despues de que el usuario pulsa "Hazlo".

Uso:
  gota-plan.py revisar plan.json   # ("-" = leer de la entrada) valida sin tocar nada; imprime JSON {ok, errores}
  gota-plan.py aplicar plan.json   # aplica y guarda como deshacerlo
  gota-plan.py deshacer            # revierte el ultimo plan aplicado

Reglas: nada fuera de la carpeta personal, nunca sobrescribe, nunca borra (papelera con
`gio trash`), y los comandos salen de una lista cerrada.
"""
import json
import os
import re
import shutil
import subprocess
import sys

CASA = os.path.realpath(os.path.expanduser("~"))
ESTADO = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(CASA, ".local/state")), "gota")
ULTIMO = os.path.join(ESTADO, "ultimo-plan.json")

# Comandos permitidos: lista cerrada, comparados como lista completa de argumentos.
COMANDOS = [
    re.compile(r"systemctl --user restart [\w@.\-]+"),
    re.compile(r"systemctl --user reset-failed [\w@.\-]+"),
    re.compile(r"bluetoothctl power (on|off)"),
    re.compile(r"rfkill unblock bluetooth"),
    re.compile(r"wpctl set-default \d+"),
]


def dentro(ruta):
    r = os.path.realpath(os.path.expanduser(ruta))
    return r if r == CASA or r.startswith(CASA + os.sep) else None


def revisar(plan):
    errores = []
    acciones = plan.get("acciones") if isinstance(plan, dict) else None
    if not isinstance(acciones, list) or not acciones:
        return ["el plan no trae acciones"]
    destinos = set()
    for i, a in enumerate(acciones, 1):
        t = a.get("tipo")
        if t == "carpeta":
            if not dentro(a.get("ruta", "")):
                errores.append(f"{i}: carpeta fuera de la carpeta personal")
        elif t == "mover":
            de, a_ = dentro(a.get("de", "")), dentro(a.get("a", ""))
            if not de or not a_:
                errores.append(f"{i}: mover fuera de la carpeta personal")
            elif not os.path.lexists(de):
                errores.append(f"{i}: no existe {a['de']}")
            elif os.path.lexists(a_) or a_ in destinos:
                errores.append(f"{i}: ya existe {a['a']}")
            elif de == CASA or a_.startswith(de + os.sep):
                errores.append(f"{i}: movimiento imposible")
            destinos.add(a_)
        elif t == "papelera":
            r = dentro(a.get("ruta", ""))
            if not r or r == CASA:
                errores.append(f"{i}: papelera fuera de la carpeta personal")
            elif not os.path.lexists(r):
                errores.append(f"{i}: no existe {a['ruta']}")
        elif t == "comando":
            cmd = a.get("cmd")
            if not (isinstance(cmd, list) and all(isinstance(x, str) for x in cmd)
                    and any(p.fullmatch(" ".join(cmd)) for p in COMANDOS)):
                errores.append(f"{i}: comando no permitido: {cmd}")
        else:
            errores.append(f"{i}: tipo desconocido {t!r}")
    return errores


def aplicar(plan):
    errores = revisar(plan)
    if errores:
        return {"ok": False, "errores": errores}
    hecho = []  # lo que se hizo, en orden, para poder deshacerlo
    fallos = []
    for a in plan["acciones"]:
        t = a["tipo"]
        try:
            if t == "carpeta":
                r = dentro(a["ruta"])
                if not os.path.isdir(r):
                    os.makedirs(r)
                    hecho.append({"tipo": "carpeta", "ruta": r})
            elif t == "mover":
                de, a_ = dentro(a["de"]), dentro(a["a"])
                if os.path.lexists(a_):
                    raise FileExistsError(a_)
                # Las carpetas que hagan falta se anotan, para quitarlas al deshacer.
                nuevas, p = [], os.path.dirname(a_)
                while not os.path.isdir(p):
                    nuevas.append(p)
                    p = os.path.dirname(p)
                for p in reversed(nuevas):
                    os.mkdir(p)
                    hecho.append({"tipo": "carpeta", "ruta": p})
                shutil.move(de, a_)
                hecho.append({"tipo": "mover", "de": de, "a": a_})
            elif t == "papelera":
                subprocess.run(["gio", "trash", dentro(a["ruta"])], check=True, capture_output=True)
                hecho.append({"tipo": "papelera", "ruta": dentro(a["ruta"])})
            elif t == "comando":
                subprocess.run(a["cmd"], check=True, capture_output=True, timeout=30)
                hecho.append({"tipo": "comando", "cmd": a["cmd"]})
        except Exception as e:
            fallos.append(f"{t}: {e}")
    os.makedirs(ESTADO, exist_ok=True)
    with open(ULTIMO, "w", encoding="utf-8") as f:
        json.dump({"hecho": hecho}, f, ensure_ascii=False, indent=1)
    return {"ok": not fallos, "hechos": len(hecho), "errores": fallos}


def deshacer():
    try:
        with open(ULTIMO, encoding="utf-8") as f:
            hecho = json.load(f)["hecho"]
    except (FileNotFoundError, KeyError, json.JSONDecodeError):
        return {"ok": False, "errores": ["no hay nada que deshacer"]}
    fallos, quedan = [], []
    # Al reves: primero se devuelven los archivos, despues se quitan las carpetas vacias.
    for h in reversed(hecho):
        try:
            if h["tipo"] == "mover":
                if os.path.lexists(h["de"]):
                    raise FileExistsError(h["de"])
                shutil.move(h["a"], h["de"])
            elif h["tipo"] == "carpeta":
                os.rmdir(h["ruta"])  # solo si quedo vacia; si no, falla y se deja
            elif h["tipo"] == "papelera":
                quedan.append(os.path.basename(h["ruta"]) + " sigue en la papelera")
            # los comandos (reiniciar un servicio) no tienen vuelta atras
        except Exception as e:
            fallos.append(f"{h['tipo']}: {e}")
    os.remove(ULTIMO)
    return {"ok": not fallos, "errores": fallos, "avisos": quedan}


if __name__ == "__main__":
    orden = sys.argv[1] if len(sys.argv) > 1 else ""
    if orden in ("revisar", "aplicar"):
        if sys.argv[2] == "-":
            plan = json.load(sys.stdin)
        else:
            with open(sys.argv[2], encoding="utf-8") as f:
                plan = json.load(f)
        r = {"ok": not (e := revisar(plan)), "errores": e} if orden == "revisar" else aplicar(plan)
    elif orden == "deshacer":
        r = deshacer()
    else:
        print(__doc__)
        sys.exit(2)
    print(json.dumps(r, ensure_ascii=False))
    sys.exit(0 if r["ok"] else 1)
