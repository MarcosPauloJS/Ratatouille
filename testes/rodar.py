"""Roda os testes do mod fora do jogo, com os scripts reais do DST.

uso (na raiz do repositório):
    uv run --no-project --with lupa python testes/rodar.py               # testes
    uv run --no-project --with lupa python testes/rodar.py --desempenho  # mede o pior caso

Na primeira vez extrai os scripts do jogo (data/databundles/scripts.zip) para
testes/scripts_do_jogo/ (~280 MB, fora do git). O jogo é achado pela variável
DST_DIR ou nos lugares comuns da Steam (veja ferramentas/caminhos.py).
"""
import sys
import zipfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "ferramentas"))
from caminhos import pacote_do_jogo  # noqa: E402
from dst_lua import runtime  # noqa: E402

PASTA = RAIZ / "testes" / "scripts_do_jogo"
MOD = RAIZ / "mod"


def pasta_scripts():
    scripts = PASTA / "scripts"
    if not (scripts / "cooking.lua").is_file():
        zip_ = pacote_do_jogo("scripts")
        print(f"extraindo {zip_} para {PASTA} ...")
        with zipfile.ZipFile(zip_) as z:
            z.extractall(PASTA)
    if not (scripts / "cooking.lua").is_file():
        sys.exit(f"ERRO: {scripts} não tem os scripts do jogo (cooking.lua não encontrado)")
    return scripts


scripts = pasta_scripts()
arquivos = ["medir_desempenho.lua"] if "--desempenho" in sys.argv else ["teste_mod.lua", "teste_tela.lua"]
falhou = False
for nome in arquivos:
    print(f"######## {nome}")
    lua, G, req = runtime(scripts)                # ambiente limpo para cada arquivo
    try:
        lua.execute((RAIZ / "testes" / nome).read_text(encoding="utf-8"), str(MOD))
    except Exception as e:                        # erro de Lua: mostra e marca falha
        print(e)
        falhou = True
sys.exit(1 if falhou else 0)
