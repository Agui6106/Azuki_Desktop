#!/usr/bin/env python3
"""Azuki RAWG client. One explicit request per invocation; public JSON only.

The credential never appears in command-line arguments, output, or errors.
"""
import argparse
import html
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import ssl
import stat
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE_URL = "https://api.rawg.io/api"
MAX_RESPONSE = 4 * 1024 * 1024
MAX_DESCRIPTION = 12000


class ClientError(Exception):
    pass


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
    def handle_data(self, data):
        self.parts.append(data)
    def handle_starttag(self, tag, attrs):
        if tag in ("p", "br", "li", "div"):
            self.parts.append("\n")


def description_text(raw):
    parser = PlainText()
    parser.feed(str(raw or ""))
    text = html.unescape("".join(parser.parts))
    return re.sub(r"\s+", " ", text).strip()[:MAX_DESCRIPTION]


def named_list(value):
    if not isinstance(value, list):
        return []
    return [v["name"] for v in value if isinstance(v, dict)
            and isinstance(v.get("name"), str) and v["name"].strip()]


def public_url(value):
    if not isinstance(value, str):
        return ""
    parsed = urllib.parse.urlsplit(value)
    return value if parsed.scheme == "https" and parsed.hostname else ""


def normalize_game(game, detail=False):
    if not isinstance(game, dict) or not isinstance(game.get("id"), int):
        raise ClientError("RAWG devolvió un registro de juego inválido.")
    slug = game.get("slug", "")
    url = "https://rawg.io/games/" + slug if re.fullmatch(r"[a-z0-9-]+", str(slug)) else "https://rawg.io"
    result = {
        "id": game["id"], "name": str(game.get("name") or ""),
        "released": game.get("released") or "",
        "developers": named_list(game.get("developers")),
        "publishers": named_list(game.get("publishers")),
        "genres": named_list(game.get("genres")),
        "rating": game.get("rating") if isinstance(game.get("rating"), (int, float)) else None,
        "metacritic": game.get("metacritic") if isinstance(game.get("metacritic"), (int, float)) else None,
        "imageUrl": public_url(game.get("background_image")),
        "rawgUrl": url,
        "description": description_text(game.get("description_raw") or game.get("description")) if detail else ""
    }
    return result


def credential_path():
    config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config").expanduser()
    return config / "azuki-tile-deck" / "rawg-credentials.json"


def checked_private(path, directory=False):
    try:
        info = path.lstat()
    except FileNotFoundError:
        raise ClientError("No se encontró la clave privada. Ejecuta primero rawg_check.py.")
    if stat.S_ISLNK(info.st_mode) or info.st_uid != os.getuid():
        raise ClientError("La ruta de credenciales tiene un propietario o tipo inseguro.")
    expected = 0o700 if directory else 0o600
    if stat.S_IMODE(info.st_mode) != expected:
        raise ClientError("Permisos incorrectos: se requieren 700 para el directorio y 600 para el archivo.")
    if directory and not stat.S_ISDIR(info.st_mode):
        raise ClientError("La ruta de configuración no es un directorio.")
    if not directory and not stat.S_ISREG(info.st_mode):
        raise ClientError("El archivo de credenciales no es regular.")


def read_key():
    path = credential_path()
    checked_private(path.parent, directory=True)
    checked_private(path)
    # O_NOFOLLOW also protects against replacing the file with a symlink.
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    with os.fdopen(fd, "r", encoding="utf-8") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
            raise ClientError("El archivo de credenciales cambió o tiene permisos inseguros.")
        content = stream.read(4096)
    try:
        key = json.loads(content).get("apiKey")
    except (ValueError, AttributeError):
        raise ClientError("El archivo privado no contiene JSON válido.")
    if not isinstance(key, str) or not key.strip():
        raise ClientError("La API key está vacía o no es válida.")
    return key.strip()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ClientError("RAWG intentó redirigir la petición; se rechazó para proteger la clave.")


def api_request(endpoint, params=None):
    key = read_key()
    query = dict(params or {})
    query["key"] = key
    url = BASE_URL + endpoint + "?" + urllib.parse.urlencode(query)
    opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(context=ssl.create_default_context()))
    request = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "AzukiTileDeck/0.6 (personal project)"})
    try:
        with opener.open(request, timeout=20) as response:
            if response.status != 200:
                raise ClientError("RAWG devolvió una respuesta inesperada.")
            raw = response.read(MAX_RESPONSE + 1)
            if len(raw) > MAX_RESPONSE:
                raise ClientError("La respuesta de RAWG supera el límite de seguridad.")
            return json.loads(raw.decode("utf-8"))
    except urllib.error.HTTPError as exc:
        messages = {401: "RAWG no aceptó la API key.", 403: "RAWG denegó el acceso.",
                    404: "El juego no existe en RAWG.", 429: "Límite de solicitudes alcanzado. Inténtalo más tarde."}
        raise ClientError(messages.get(exc.code, "RAWG devolvió HTTP " + str(exc.code) + "."))
    except (urllib.error.URLError, TimeoutError):
        raise ClientError("No se pudo conectar con RAWG. Comprueba la red.")
    except (UnicodeError, json.JSONDecodeError):
        raise ClientError("RAWG devolvió una respuesta JSON inválida.")


def run(action, encoded_query="", game_id=""):
    if action == "status":
        read_key()
        return {"ready": True}
    if action == "search":
        if len(encoded_query) > 1200 or not re.fullmatch(r"[A-Za-z0-9._~%\-]*", encoded_query):
            raise ClientError("La consulta no tiene un formato válido.")
        query = urllib.parse.unquote(encoded_query).strip()
        if not 2 <= len(query) <= 120:
            raise ClientError("Escribe entre 2 y 120 caracteres para buscar.")
        data = api_request("/games", {"search": query, "page_size": 10, "page": 1})
        return {"count": data.get("count", 0), "results": [normalize_game(g) for g in data.get("results", [])[:10]]}
    if action == "detail":
        if not re.fullmatch(r"[0-9]{1,12}", game_id):
            raise ClientError("ID de RAWG inválido.")
        return normalize_game(api_request("/games/" + game_id), detail=True)
    raise ClientError("Acción desconocida.")


def main():
    parser = argparse.ArgumentParser(description="Cliente local de RAWG para Azuki.")
    parser.add_argument("action", choices=["status", "search", "detail"])
    parser.add_argument("--query-encoded", default="")
    parser.add_argument("--game-id", default="")
    parser.add_argument("--request-id", default="0")
    args = parser.parse_args()
    result = {"ok": False, "requestId": args.request_id}
    code = 0
    try:
        result["data"] = run(args.action, args.query_encoded, args.game_id)
        result["ok"] = True
    except ClientError as exc:
        result["message"] = str(exc)
        code = 1
    except Exception:
        # Never print exception text: urllib exceptions can include a URL with the secret.
        result["message"] = "Error interno del cliente RAWG. Revisa la configuración local."
        code = 1
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return code


if __name__ == "__main__":
    sys.exit(main())
