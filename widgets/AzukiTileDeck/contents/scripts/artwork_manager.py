#!/usr/bin/env python3
"""Gestor local de artwork de Azuki. No usa red, credenciales ni shell.

inspect valida un archivo elegido por el usuario; copy conserva una copia
inmutable identificada por SHA-256. Nunca elimina imágenes automáticamente.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys
import tempfile
from urllib.parse import urlsplit, unquote

MAX_BYTES = 16 * 1024 * 1024
MAX_PIXELS = 24_000_000
MAX_DIMENSION = 16384

class ArtworkError(Exception):
    pass


def source_path(value):
    if not isinstance(value, str) or not value or len(value) > 8192 or "\x00" in value:
        raise ArtworkError("Selecciona un archivo local válido.")
    if value.startswith("/"):
        path = Path(value)
    else:
        url = urlsplit(value)
        if url.scheme != "file" or url.netloc not in ("", "localhost") or url.query or url.fragment:
            raise ArtworkError("Solo se admiten archivos locales; no se descargan URLs.")
        try:
            path = Path(unquote(url.path, encoding="utf-8", errors="strict"))
        except UnicodeError:
            raise ArtworkError("La ruta del archivo no tiene una codificación válida.")
    if not path.is_absolute() or "\x00" in str(path):
        raise ArtworkError("La ruta debe ser absoluta y válida.")
    try:
        return path.resolve(strict=True)
    except (OSError, RuntimeError):
        raise ArtworkError("No se pudo encontrar el archivo seleccionado.")


def read_image(path):
    try:
        with path.open("rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode):
                raise ArtworkError("El origen no es un archivo regular.")
            if info.st_size > MAX_BYTES:
                raise ArtworkError("La imagen supera el límite de 16 MiB.")
            data = stream.read(MAX_BYTES + 1)
    except ArtworkError:
        raise
    except OSError:
        raise ArtworkError("No se pudo leer el archivo seleccionado.")
    if len(data) > MAX_BYTES:
        raise ArtworkError("La imagen supera el límite de 16 MiB.")
    kind, width, height = image_info(data)
    if not (0 < width <= MAX_DIMENSION and 0 < height <= MAX_DIMENSION) or width * height > MAX_PIXELS:
        raise ArtworkError("La resolución de la imagen supera el límite de esta versión.")
    return data, kind, width, height


def image_info(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        if len(data) < 33 or data[12:16] != b"IHDR":
            raise ArtworkError("El archivo PNG no tiene una cabecera válida.")
        if data.find(b"acTL") >= 0:
            raise ArtworkError("Las imágenes animadas no están disponibles en esta versión.")
        width, height = struct.unpack(">II", data[16:24])
        return "png", width, height
    if data.startswith(b"\xff\xd8\xff"):
        position = 2
        while position + 4 <= len(data):
            if data[position] != 0xff:
                raise ArtworkError("El archivo JPEG no tiene una estructura válida.")
            while position < len(data) and data[position] == 0xff:
                position += 1
            if position >= len(data):
                break
            marker = data[position]
            position += 1
            if marker in (0xd8, 0xd9) or 0xd0 <= marker <= 0xd7 or marker == 0x01:
                continue
            if marker == 0xda:
                break
            if position + 2 > len(data):
                break
            length = struct.unpack(">H", data[position:position+2])[0]
            if length < 2 or position + length > len(data):
                break
            if marker in (0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf):
                if length < 7:
                    break
                height, width = struct.unpack(">HH", data[position+3:position+7])
                return "jpg", width, height
            position += length
        raise ArtworkError("No se pudieron leer las dimensiones del JPEG.")
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP" and len(data) >= 30:
        chunk = data[12:16]
        if chunk == b"VP8X":
            if data[20] & 0x02:
                raise ArtworkError("Las imágenes animadas no están disponibles en esta versión.")
            width = 1 + int.from_bytes(data[24:27], "little")
            height = 1 + int.from_bytes(data[27:30], "little")
        elif chunk == b"VP8 " and data[23:26] == b"\x9d\x01\x2a":
            width = int.from_bytes(data[26:28], "little") & 0x3fff
            height = int.from_bytes(data[28:30], "little") & 0x3fff
        elif chunk == b"VP8L" and data[20] == 0x2f:
            bits = int.from_bytes(data[21:25], "little")
            width = 1 + (bits & 0x3fff)
            height = 1 + ((bits >> 14) & 0x3fff)
        else:
            raise ArtworkError("El archivo WebP no tiene una cabecera compatible.")
        return "webp", width, height
    raise ArtworkError("Formato no compatible. Usa JPEG, PNG o WebP estático.")


def data_directory():
    home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share").expanduser()
    if not home.is_absolute():
        raise ArtworkError("XDG_DATA_HOME debe ser una ruta absoluta.")
    return home / "azuki-tile-deck" / "artwork"


def secure_directory(path):
    if path.exists() or path.is_symlink():
        info = path.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
            raise ArtworkError("La carpeta de Azuki tiene un propietario o permisos inseguros.")
    else:
        try:
            path.mkdir(mode=0o700, parents=True)
        except OSError:
            raise ArtworkError("No se pudo crear la carpeta privada de artwork.")


def managed_directory():
    root = data_directory().parent
    secure_directory(root)
    directory = root / "artwork"
    secure_directory(directory)
    return directory


def inspect(source):
    path = source_path(source)
    data, kind, width, height = read_image(path)
    return {
        "fileUrl": path.as_uri(), "name": path.name,
        "format": kind.upper(), "width": width, "height": height,
        "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()
    }


def copy_image(source, expected_sha256=""):
    path = source_path(source)
    data, kind, width, height = read_image(path)
    digest = hashlib.sha256(data).hexdigest()
    if expected_sha256 and digest != expected_sha256:
        raise ArtworkError("El archivo cambió desde la vista previa. Selecciónalo nuevamente.")
    directory = managed_directory()
    target = directory / (digest + "." + kind)
    if target.exists() or target.is_symlink():
        info = target.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise ArtworkError("El archivo administrado tiene un tipo o propietario inseguro.")
        with target.open("rb") as stream:
            existing = stream.read(MAX_BYTES + 1)
        if hashlib.sha256(existing).hexdigest() != digest:
            raise ArtworkError("El archivo administrado existente no coincide con su identificador.")
    else:
        fd, temporary = tempfile.mkstemp(prefix=".artwork-", dir=directory)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(temporary, 0o600)
            try:
                os.link(temporary, target)
            except FileExistsError:
                if target.is_symlink() or not target.is_file():
                    raise ArtworkError("El destino cambió durante la copia.")
                with target.open("rb") as stream:
                    existing = stream.read(MAX_BYTES + 1)
                if hashlib.sha256(existing).hexdigest() != digest:
                    raise ArtworkError("El destino cambió durante la copia.")
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    return {
        "fileUrl": target.as_uri(), "name": path.name,
        "format": kind.upper(), "width": width, "height": height,
        "bytes": len(data), "sha256": digest, "managed": True
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["inspect", "copy"])
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--source")
    group.add_argument("--source-encoded")
    parser.add_argument("--expected-sha256", default="")
    parser.add_argument("--request-id", default="0")
    args = parser.parse_args(argv)
    result = {"ok": False, "requestId": args.request_id}
    code = 0
    try:
        if args.source_encoded is not None:
            if len(args.source_encoded) > 24000 or not re.fullmatch(r"[A-Za-z0-9._~%\-]*", args.source_encoded):
                raise ArtworkError("La ruta codificada no es válida.")
            source = unquote(args.source_encoded, encoding="utf-8", errors="strict")
        else:
            source = args.source
        if args.expected_sha256 and not re.fullmatch(r"[0-9a-f]{64}", args.expected_sha256):
            raise ArtworkError("El identificador de imagen no es válido.")
        result["data"] = inspect(source) if args.action == "inspect" else copy_image(source, args.expected_sha256)
        result["ok"] = True
    except ArtworkError as exc:
        result["message"] = str(exc)
        code = 1
    except Exception:
        # No revelar rutas privadas ni contenido de excepciones de bibliotecas.
        result["message"] = "No se pudo procesar la imagen local. Revisa el archivo y sus permisos."
        code = 1
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return code

if __name__ == "__main__":
    sys.exit(main())
