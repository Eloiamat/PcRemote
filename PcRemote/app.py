from flask import Flask, render_template, jsonify, request, session, send_from_directory
import subprocess
from functools import wraps
import secrets
import time

app = Flask(__name__)

app.secret_key = "PcRemote-2026-Una-Clave-Larga-Y-Segura"

PIN = "123456"

MAX_INTENTOS = 5
TIEMPO_BLOQUEO = 60

intentos_fallidos = 0
bloqueado_hasta = 0


def requiere_login(func):

    @wraps(func)
    def wrapper(*args, **kwargs):

        if not session.get("autenticado"):
            return jsonify({
                "error": "No autorizado"
            }), 401

        return func(*args, **kwargs)

    return wrapper


@app.route("/login", methods=["POST"])
def login():

    global intentos_fallidos, bloqueado_hasta

    ahora = time.time()

    if ahora < bloqueado_hasta:
        return jsonify({
            "success": False,
            "error": "Demasiados intentos. Espera un minuto."
        }), 429

    datos = request.get_json(silent=True) or {}

    pin = str(datos.get("pin", ""))

    if secrets.compare_digest(pin, PIN):

        intentos_fallidos = 0
        session["autenticado"] = True

        return jsonify({
            "success": True
        })

    intentos_fallidos += 1

    if intentos_fallidos >= MAX_INTENTOS:

        intentos_fallidos = 0
        bloqueado_hasta = time.time() + TIEMPO_BLOQUEO

        return jsonify({
            "success": False,
            "error": "Demasiados intentos. Espera un minuto."
        }), 429

    return jsonify({
        "success": False,
        "error": "PIN incorrecto"
    }), 401


@app.route("/logout", methods=["POST"])
def logout():

    session.clear()

    return jsonify({
        "success": True
    })


def obtener_sesion_activa():

    resultado = subprocess.run(
        ["loginctl", "list-sessions", "--no-legend"],
        capture_output=True,
        text=True,
        check=True
    )

    for linea in resultado.stdout.splitlines():

        partes = linea.split()

        if len(partes) >= 6:

            sesion = partes[0]
            usuario = partes[2]
            estado = partes[5]

            if usuario == "alumnat" and estado == "active":
                return sesion

    return None


def obtener_estado_bloqueo(sesion):

    resultado = subprocess.run(
        ["loginctl", "show-session", sesion, "-p", "LockedHint"],
        capture_output=True,
        text=True
    )

    return resultado.stdout.strip() == "LockedHint=yes"


@app.route("/")
def inicio():

    return render_template("index.html")

@app.route("/offline.html")
def offline():
    return render_template("offline.html")

@app.route("/sw.js")
def service_worker():

    return send_from_directory(
        "static",
        "sw.js",
        mimetype="application/javascript"
    )


@app.route("/api/ping")
def ping():

    return jsonify({
        "online": True
    })


@app.route("/api/status")
@requiere_login
def status():

    sesion = obtener_sesion_activa()

    if sesion is None:

        return jsonify({
            "online": False,
            "locked": False
        })

    bloqueado = obtener_estado_bloqueo(sesion)

    return jsonify({
        "online": True,
        "locked": bloqueado
    })


@app.route("/bloquear", methods=["POST"])
@requiere_login
def bloquear():

    sesion = obtener_sesion_activa()

    if sesion is None:

        return jsonify({
            "error": "No se ha encontrado una sesión activa"
        }), 500

    resultado = subprocess.run(
        ["loginctl", "lock-session", sesion],
        capture_output=True,
        text=True
    )

    if resultado.returncode != 0:

        return jsonify({
            "error": resultado.stderr
        }), 500

    return jsonify({
        "success": True
    })


if __name__ == "__main__":

    app.run(
        host="0.0.0.0",
        port=5000
    )
