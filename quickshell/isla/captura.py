#!/usr/bin/env python3
"""Ayudante del modo captura de Menisco (Captura.qml).

  captura.py ventanas HDMI-A-1                         # JSON de las ventanas del espacio visible
  captura.py guardar FOTO X Y ANCHO ALTO ESCALA EDITAR [PUNTOS]
                                                       # recorta la foto congelada, guarda y copia;
                                                       # PUNTOS = JSON [[x,y],...] de 0 a 1 dentro de
                                                       # la caja: lo de fuera de la forma queda transparente
  captura.py editar-ultima                             # abre en swappy la captura mas reciente

Se guarda donde guardaba niri (screenshot-path de su config), asi la isla la ve llegar y
muestra la miniatura. Las coordenadas llegan en pixeles logicos; la foto esta en fisicos.
"""
import glob
import json
import os
import subprocess
import sys
import time

from PIL import Image

CARPETA = os.path.expanduser("~/Pictures/Screenshots")


def niri(*args):
    return json.loads(subprocess.run(["niri", "msg", "-j", *args], capture_output=True, text=True).stdout)


def ventanas(salida):
    activo = next((w["id"] for w in niri("workspaces") if w["output"] == salida and w["is_active"]), None)
    lista = [{"id": v["id"], "titulo": v["title"] or v["app_id"], "app": v["app_id"] or ""}
             for v in niri("windows") if v["workspace_id"] == activo]
    print(json.dumps(lista, ensure_ascii=False))


def editar(ruta):
    subprocess.Popen(["swappy", "-f", ruta], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def recortar_forma(img, puntos):
    """Deja transparente lo que queda fuera del poligono (puntos de 0 a 1 dentro de la imagen)."""
    from PIL import ImageDraw
    k = 4   # la mascara se dibuja a 4x y se reduce: borde suave en curvas y diagonales
    mascara = Image.new("L", (img.width * k, img.height * k), 0)
    ImageDraw.Draw(mascara).polygon([(px * img.width * k, py * img.height * k) for px, py in puntos], fill=255)
    img = img.convert("RGBA")
    img.putalpha(mascara.resize(img.size, Image.LANCZOS))
    return img


def guardar(foto, x, y, ancho, alto, escala, con_editor, puntos=""):
    e = float(escala)
    caja = tuple(round(float(v) * e) for v in (x, y, float(x) + float(ancho), float(y) + float(alto)))
    os.makedirs(CARPETA, exist_ok=True)
    ruta = os.path.join(CARPETA, time.strftime("Screenshot from %Y-%m-%d %H-%M-%S.png"))
    # Se escribe aparte y se mueve de golpe: la isla lee el archivo en cuanto aparece.
    img = Image.open(foto).crop(caja)
    if puntos:
        img = recortar_forma(img, json.loads(puntos))
    img.save(ruta + ".tmp", "PNG")
    os.replace(ruta + ".tmp", ruta)
    with open(ruta, "rb") as f:
        subprocess.run(["wl-copy", "--type", "image/png"], stdin=f)
    if con_editor == "1":
        editar(ruta)
    print(ruta)


def editar_ultima():
    time.sleep(0.8)   # niri escribe el archivo un instante despues de la accion
    capturas = glob.glob(os.path.join(CARPETA, "*.png"))
    if capturas:
        editar(max(capturas, key=os.path.getmtime))


if __name__ == "__main__":
    orden, *resto = sys.argv[1:]
    {"ventanas": ventanas, "guardar": guardar, "editar-ultima": editar_ultima}[orden](*resto)
