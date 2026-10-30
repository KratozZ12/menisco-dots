#!/usr/bin/env python3
"""Mide el rendimiento del equipo para la isla de Menisco y escribe una linea JSON por vuelta.

Uso: rendimiento.py [segundos entre medidas]   (por defecto 1.2)

Por linea: consumo del CPU (W, por RAPL), uso del CPU (%), temperatura del CPU (k10temp),
consumo, uso y temperatura de la GPU NVIDIA (nvidia-smi) y los 3 programas que mas CPU usan
en esa vuelta (por diferencia de tiempos en /proc, no el promedio de toda su vida).
"""
import glob
import json
import os
import subprocess
import sys
import time

INTERVALO = float(sys.argv[1]) if len(sys.argv) > 1 else 1.2
RAPL = "/sys/class/powercap/intel-rapl:0/energy_uj"
HZ = os.sysconf("SC_CLK_TCK")


def leer(ruta, defecto=""):
    try:
        with open(ruta) as f:
            return f.read()
    except OSError:
        return defecto


def sensor_cpu():
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        if leer(h + "/name").strip() in ("k10temp", "coretemp", "zenpower"):
            return h + "/temp1_input"
    return None


def cpu_total():
    v = [int(x) for x in leer("/proc/stat").split("\n")[0].split()[1:]]
    return sum(v), v[3] + v[4]          # total, inactivo (idle + iowait)


def procesos():
    """{nombre: ticks de CPU acumulados} sumando todos los procesos con ese nombre."""
    r = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        s = leer(f"/proc/{d}/stat")
        if not s or not leer(f"/proc/{d}/cmdline"):   # sin cmdline = hilo del kernel (kworker...)
            continue
        nombre = s[s.find("(") + 1:s.rfind(")")]
        campos = s[s.rfind(")") + 2:].split()
        r[nombre] = r.get(nombre, 0) + int(campos[11]) + int(campos[12])
    return r


def gpu():
    try:
        o = subprocess.run(["nvidia-smi", "--query-gpu=power.draw,utilization.gpu,temperature.gpu",
                            "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=3).stdout
        w, u, t = [x.strip() for x in o.split(",")]
        return float(w), float(u), float(t)
    except Exception:
        return None, None, None


temp_cpu = sensor_cpu()
e0, (t0, i0), p0, m0 = int(leer(RAPL, "0") or 0), cpu_total(), procesos(), time.monotonic()
while True:
    time.sleep(INTERVALO)
    e1, (t1, i1), p1, m1 = int(leer(RAPL, "0") or 0), cpu_total(), procesos(), time.monotonic()
    dt = m1 - m0
    cpu_w = max(0.0, (e1 - e0) / 1e6 / dt) if e1 >= e0 else None   # el contador da la vuelta a veces
    uso = 100 * (1 - (i1 - i0) / max(1, t1 - t0))
    nucleos = os.cpu_count() or 1
    top = sorted(((n, (p1[n] - p0.get(n, 0)) / HZ / dt * 100 / nucleos) for n in p1), key=lambda x: -x[1])[:3]
    gw, gu, gt = gpu()
    print(json.dumps({
        "cpuW": round(cpu_w, 1) if cpu_w is not None else None,
        "cpuUso": round(uso),
        "cpuTemp": round(int(leer(temp_cpu, "0")) / 1000) if temp_cpu else None,
        "gpuW": gw, "gpuUso": gu, "gpuTemp": gt,
        "top": [[n, round(p, 1)] for n, p in top if p > 0.05],
    }), flush=True)
    e0, t0, i0, p0, m0 = e1, t1, i1, p1, m1
