"""Roda os scripts oficiais do DST num Lua 5.1 isolado e exporta receitas em JSON.

uso: python -I extract.py <scripts_dir> <out.json>
"""
import json
import re
import sys
from pathlib import Path


SCRIPTS = Path(sys.argv[1])
OUT = Path(sys.argv[2])

from dst_lua import runtime

lua, G, req = runtime(SCRIPTS)
for mod in ["recipe", "recipes"]:
    req(mod)

foods = {}
for mod, cat in [("preparedfoods", "panela"), ("preparedfoods_warly", "warly")]:
    t = req(mod)
    for k, v in t.items():
        foods[k] = (cat, v)

# ---------- helpers ----------
def tbl(t):
    return dict(t.items()) if lua.eval("type")(t) == "table" else {}

TECH = tbl(G.TECH)
tech_by_sig = {}
for name, tree in TECH.items():
    sig = tuple(sorted((k, v) for k, v in tbl(tree).items() if v and v != 0))
    # Prefere nomes "canônicos" (mais curtos) quando há duplicatas
    if sig not in tech_by_sig or len(name) < len(tech_by_sig[sig]):
        tech_by_sig[sig] = name

def tech_name(level):
    sig = tuple(sorted((k, v) for k, v in tbl(level).items() if v and v != 0))
    if not sig:
        return "NONE"
    return tech_by_sig.get(sig, " + ".join(f"{k}{v}" for k, v in sig))

def num(x):
    if isinstance(x, (int, float)):
        return round(x, 3)
    return None

# ---------- filtros (abas do menu de craft) ----------
filters_of = {}
for fname, fdef in tbl(G.CRAFTING_FILTERS).items():
    recipes = tbl(fdef).get("recipes")
    if recipes is None:
        continue
    for _, rname in tbl(recipes).items():
        filters_of.setdefault(rname, []).append(fname)

# ---------- receitas de craft ----------
recipes_out = []
for name, r in tbl(G.AllRecipes).items():
    r = tbl(r)
    if r.get("is_deconstruction_recipe"):
        continue
    ings = []
    for key in ("ingredients", "character_ingredients", "tech_ingredients"):
        for _, ing in tbl(r.get(key)).items():
            ing = tbl(ing)
            ings.append({"item": ing.get("type"), "qtd": num(ing.get("amount"))})
    recipes_out.append({
        "nome": name,
        "produto": r.get("product"),
        "qtd": num(r.get("numtogive")) or 1,
        "ingredientes": ings,
        "tech": tech_name(r.get("level")),
        "personagem": r.get("builder_tag"),
        "skill": r.get("builder_skill"),
        "estacao": r.get("station_tag"),
        "construcao": bool(r.get("placer")),
        "sem_desbloqueio": bool(r.get("nounlock")),
        "filtros": sorted(filters_of.get(name, [])),
    })

# ---------- comidas da panela ----------
src_text = {}
for mod in ["preparedfoods", "preparedfoods_warly"]:
    src_text[mod] = (SCRIPTS / f"{mod}.lua").read_text(encoding="utf-8", errors="replace")

def test_src(mod, name):
    m = re.search(r"\n\s*" + re.escape(name) + r"\s*=\s*\{.*?test\s*=\s*function\s*\([^)]*\)\s*(.*?)\s*end\s*,",
                  src_text[mod], re.S)
    if not m:
        return None
    body = m.group(1).strip()
    return re.sub(r"^return\s+", "", body)

FOODTYPE_INV = {v: k for k, v in tbl(G.FOODTYPE).items()}
foods_out = []
for name, (cat, f) in foods.items():
    f = tbl(f)
    card = tbl(f.get("card_def"))
    example = []
    for _, pair in tbl(card.get("ingredients")).items():
        pair = tbl(pair)
        example.append({"item": pair.get(1), "qtd": num(pair.get(2))})
    pt = f.get("perishtime")
    foods_out.append({
        "nome": name,
        "categoria": cat,
        "vida": num(f.get("health")),
        "fome": num(f.get("hunger")),
        "sanidade": num(f.get("sanity")),
        "validade_dias": round(pt / 480, 1) if isinstance(pt, (int, float)) else None,
        "tempo_preparo_s": round(num(f.get("cooktime")) * 20, 1) if num(f.get("cooktime")) else None,
        "prioridade": num(f.get("priority")),
        "tipo": FOODTYPE_INV.get(f.get("foodtype"), f.get("foodtype")),
        "temperatura": num(f.get("temperature")),
        "duracao_temp_s": num(f.get("temperatureduration")),
        "exemplo": example,
        "condicao": test_src("preparedfoods" if cat == "panela" else "preparedfoods_warly", name),
    })

# ---------- nomes (inglês + PT-BR oficial) ----------
NAMES = tbl(tbl(G.STRINGS).get("NAMES"))
DESC = tbl(tbl(G.STRINGS).get("RECIPE_DESC"))
po = (SCRIPTS / "languages" / "portuguese_br.po").read_text(encoding="utf-8", errors="replace")
pt_names, pt_desc = {}, {}
for ctx, msgstr in re.findall(r'msgctxt "STRINGS\.(NAMES\.[A-Z0-9_]+|RECIPE_DESC\.[A-Z0-9_]+)"\s*\nmsgid ".*?"\s*\nmsgstr "(.*?)"\n', po):
    kind, key = ctx.split(".", 1)
    (pt_names if kind == "NAMES" else pt_desc)[key] = msgstr.replace('\\"', '"')

all_items = set()
for r in recipes_out:
    all_items.add(r["nome"]); all_items.add(r["produto"] or r["nome"])
    all_items.update(i["item"] for i in r["ingredientes"] if i["item"])
for f in foods_out:
    all_items.add(f["nome"]); all_items.update(i["item"] for i in f["exemplo"] if i["item"])

names = {}
for it in all_items:
    if not isinstance(it, str):
        continue
    k = it.upper()
    en = NAMES.get(k)
    names[it] = {"en": en if isinstance(en, str) else None, "pt": pt_names.get(k)}
desc = {}
for r in recipes_out:
    k = r["nome"].upper()
    en = DESC.get(k)
    desc[r["nome"]] = {"en": en if isinstance(en, str) else None, "pt": pt_desc.get(k)}

OUT.write_text(json.dumps({
    "craft": sorted(recipes_out, key=lambda x: x["nome"]),
    "comidas": sorted(foods_out, key=lambda x: x["nome"]),
    "nomes": names,
    "descricoes": desc,
}, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"craft={len(recipes_out)} comidas={len(foods_out)} nomes={len(names)} pt={sum(1 for v in names.values() if v['pt'])}")
