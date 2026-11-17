"""Exporta a "matemática da panela" direto do cooking.lua oficial.

- valores de cada ingrediente (carne 1, vegetal 0.5...), por prefab
- todas as receitas da panela comum e do caldeirão do Warly, com prioridade,
  peso e a função test() traduzida para JavaScript
- apelidos de prefab (cookedmeat -> meat_cooked)

uso: python -I extract_panela.py <scripts_dir> <receitas.json> <out.json>
"""
import json
import re
import sys
from pathlib import Path

from dst_lua import runtime

SCRIPTS = Path(sys.argv[1])
RECEITAS = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
OUT = Path(sys.argv[3])

lua, G, req = runtime(SCRIPTS)
cooking = req("cooking")


def tbl(t):
    return dict(t.items()) if lua.eval("type")(t) == "table" else {}


# ---------- ingredientes ----------
ingredientes = {}
for name, data in tbl(cooking.ingredients).items():
    tags = {k: v for k, v in tbl(tbl(data)["tags"]).items() if k not in ("precook", "dried")}
    ingredientes[name] = tags

src_cooking = (SCRIPTS / "cooking.lua").read_text(encoding="utf-8")
bloco = re.search(r"local aliases\s*=\s*\{(.*?)\}", src_cooking, re.S).group(1)
apelidos = dict(re.findall(r"(\w+)\s*=\s*\"(\w+)\"", bloco))

# ---------- receitas: texto exato do test() via debug.getinfo ----------
linhas_cache = {}


def fonte_do_test(fn):
    info = lua.eval("function(f) local i = debug.getinfo(f, 'S'); return i.source, i.linedefined, i.lastlinedefined end")(fn)
    source, ini, fim = info
    path = Path(source.lstrip("@"))
    if path not in linhas_cache:
        linhas_cache[path] = path.read_text(encoding="utf-8").splitlines()
    corpo = "\n".join(linhas_cache[path][ini - 1:fim])
    m = re.search(r"function\s*\(\s*cooker\s*,\s*names\s*,\s*tags\s*\)(.*)end", corpo, re.S)
    corpo = m.group(1)
    corpo = re.sub(r"--[^\n]*", "", corpo).strip()
    assert corpo.startswith("return"), corpo
    return corpo[len("return"):].strip()


LUA_PARA_JS = [(r"\band\b", "&&"), (r"\bor\b", "||"), (r"\bnot\b", "!"), (r"~=", "!="), (r"\bnil\b", "undefined")]


def para_js(expr):
    """Tradução direta: só usa names.x, tags.x, números, and/or/not e comparações.
    Diferença Lua x JS: em Lua 0 é verdadeiro. Aqui os valores de names/tags
    nunca são 0 (só existem quando o item está na panela), então a tradução é segura.
    O verificar_panela.py compara Lua e JS em milhares de combinações."""
    proibido = re.sub(r"\b(names|tags)\.\w+|\b(and|or|not|nil|true|false)\b|[\d.]+|[()<>=~+\-\s]", "", expr)
    assert proibido == "", f"trecho não traduzível: {proibido!r} em {expr!r}"
    js = expr
    for a, b in LUA_PARA_JS:
        js = re.sub(a, b, js)
    return re.sub(r"\s+", " ", js)


def receitas_do(cozinha):
    out = {}
    for name, r in tbl(tbl(cooking.recipes).get(cozinha)).items():
        r = tbl(r)
        expr = fonte_do_test(r["test"])
        out[name] = {"pr": r.get("priority") or 0, "peso": r.get("weight") or 1,
                     "lua": expr, "js": para_js(expr)}
    return out


panela = receitas_do("cookpot")
portatil = receitas_do("portablecookpot")

# ---------- nomes PT-BR ----------
po = (SCRIPTS / "languages" / "portuguese_br.po").read_text(encoding="utf-8", errors="replace")
pt = dict(re.findall(r'msgctxt "STRINGS\.NAMES\.([A-Z0-9_]+)"\s*\nmsgid ".*?"\s*\nmsgstr "(.*?)"\n', po))
en = tbl(tbl(G.STRINGS).get("NAMES"))
inverso = {v: k for k, v in apelidos.items()}       # meat_cooked -> cookedmeat (nome do prefab)


NAME_FIX = {"FISH": "Peixe"}   # a tradução oficial traz "Pescar" aqui (igual ao extract_simple.py)


def nome(item):
    prefab = inverso.get(item, item)
    if prefab.upper() in NAME_FIX:
        return NAME_FIX[prefab.upper()]
    k = prefab.upper()
    return pt.get(k) or (en.get(k) if isinstance(en.get(k), str) else None)


ing_out = {}
for item, tags in sorted(ingredientes.items()):
    ing_out[item] = {"prefab": inverso.get(item, item), "n": nome(item), "tags": tags}

nomes_pratos = {}
for k in set(panela) | set(portatil):
    nomes_pratos[k] = nome(k)

OUT.write_text(json.dumps({
    "ingredientes": ing_out,
    "apelidos": apelidos,
    "panela": panela,
    "portatil": portatil,
    "nomes_pratos": nomes_pratos,
}, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"ingredientes={len(ing_out)} sem_nome={sum(1 for v in ing_out.values() if not v['n'])} "
      f"panela={len(panela)} portatil={len(portatil)}")
