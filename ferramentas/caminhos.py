"""Onde estão o jogo e as ferramentas de mod da Klei.

Use a variável de ambiente DST_DIR (pasta "Don't Starve Together") e, se quiser,
DST_MOD_TOOLS (pasta "Don't Starve Mod Tools"). Sem elas, procura nos lugares
comuns da Steam (Windows, WSL e Linux).
"""
import glob
import os
from pathlib import Path

_STEAM = [
    "C:/Program Files (x86)/Steam/steamapps/common",
    "/mnt/c/Program Files (x86)/Steam/steamapps/common",
    "/mnt/*/SteamLibrary/steamapps/common",
    "/mnt/*/Steam/steamapps/common",
    os.path.expanduser("~/.steam/steam/steamapps/common"),
    os.path.expanduser("~/.local/share/Steam/steamapps/common"),
]


def _achar(variavel, nome):
    if os.environ.get(variavel):
        return Path(os.environ[variavel])
    for base in _STEAM:
        for p in glob.glob(os.path.join(base, nome)):
            return Path(p)
    return None


def pasta_do_jogo():
    p = _achar("DST_DIR", "Don't Starve Together")
    if p is None:
        raise SystemExit("Não achei o Don't Starve Together. Defina DST_DIR com a pasta do jogo.")
    return p


def pacote_do_jogo(nome):
    """data/databundles/<nome>.zip (scripts.zip, images.zip)"""
    return pasta_do_jogo() / "data" / "databundles" / f"{nome}.zip"


def conversor_de_textura():
    """TextureConverter.exe do Don't Starve Mod Tools (ou None se não instalado)"""
    p = _achar("DST_MOD_TOOLS", "Don't Starve Mod Tools")
    exe = p / "mod_tools" / "tools" / "bin" / "TextureConverter.exe" if p else None
    return exe if exe and exe.exists() else None
