"""Gera scripts/geladeira_simples.lua para o mod: o que assar na fogueira e secar no varal.

Vem de simples.json (extract_simple.py, que lê os componentes cookable/dryable/edible
dos prefabs do jogo). O cliente não consegue perguntar isso aos itens, então vai como tabela.

uso: python -I gerar_simples_mod.py <simples.json> <saida.lua>
"""
import json
import sys
from pathlib import Path

SIMPLES, OUT = Path(sys.argv[1]), Path(sys.argv[2])
linhas_json = json.loads(SIMPLES.read_text(encoding="utf-8"))


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def num(v):
    return "nil" if v is None else repr(round(float(v), 2))


linhas = ["-- GERADO por receitas/gerar_simples_mod.py a partir dos prefabs do jogo. Não edite à mão.",
          "-- metodo: fogueira | varal; cru -> produto; vida/fome/sani = valores base do produto; dias = tempo no varal",
          "return {"]
for o in sorted(linhas_json, key=lambda o: (o["m"], o["raw"])):
    c = o["c"]
    linhas.append(
        f"  {{ metodo = {lua_str(o['m'])}, cru = {lua_str(o['raw'])}, produto = {lua_str(o['prod'])}, "
        f"vida = {num(c.get('h'))}, fome = {num(c.get('u'))}, sani = {num(c.get('s'))}, dias = {num(o.get('t'))} }},")
linhas.append("}")
OUT.write_text("\n".join(linhas) + "\n", encoding="utf-8")
print(f"{len(linhas_json)} receitas -> {OUT} ({OUT.stat().st_size} bytes)")
