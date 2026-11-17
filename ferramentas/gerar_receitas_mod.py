"""Gera scripts/geladeira_receitas.lua para o mod: para cada prato da panela,
- `usa`: todo ingrediente que aparece em ALGUMA combinação de 4 em que o prato vence
  (é o que a busca por ingrediente da aba "Todas" consulta);
- `exemplo`: uma combinação que funciona (a do livro de receitas do jogo, se houver).

Força bruta com as regras REAIS do cooking.lua, sobre classes de equivalência:
ingredientes com as mesmas tags e que nenhuma regra cita pelo nome (names.x) se
comportam igual, então basta testar um representante de cada classe.

uso: python gerar_receitas_mod.py <scripts_dir> <panela.json> <saida.lua>
"""
import json
import re
import sys
import time
from pathlib import Path

from dst_lua import runtime

SCRIPTS, PANELA, OUT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
p = json.loads(PANELA.read_text(encoding="utf-8"))

# Só ingredientes que existem como item (têm nome no jogo)
ingredientes = {k: v for k, v in p["ingredientes"].items() if v["n"]}
citados = set()
for coz in ("panela", "portatil"):
    for r in p[coz].values():
        citados |= set(re.findall(r"names\.(\w+)", r["lua"]))

# Preferência para exemplos: ingredientes comuns e crus primeiro
COMUNS = ["meat", "monstermeat", "smallmeat", "drumstick", "froglegs", "fishmeat_small", "fishmeat",
          "bird_egg", "berries", "carrot", "potato", "corn", "pumpkin", "eggplant", "onion", "tomato",
          "garlic", "pepper", "asparagus", "ice", "twigs", "honey", "butter", "cave_banana", "dragonfruit",
          "pomegranate", "watermelon", "durian", "kelp", "red_cap", "green_cap", "blue_cap", "cactus_meat",
          "cutlichen", "berries_juicy", "fig", "batwing", "plantmeat", "moon_cap", "goatmilk", "milkywhites"]


def custo(item):
    if item in COMUNS:
        return COMUNS.index(item)
    return 60 + (5 if item.endswith(("_cooked", "_dried")) or item.startswith("cooked") else 0)


classes = {}
for item, v in ingredientes.items():
    chave = ("nome", item) if item in citados else ("tags", tuple(sorted(v["tags"].items())))
    classes.setdefault(chave, []).append(item)
grupos = sorted((sorted(m, key=custo) for m in classes.values()), key=lambda m: custo(m[0]))
reps = [g[0] for g in grupos]
print(f"{len(ingredientes)} ingredientes -> {len(reps)} classes")

lua, G, req = runtime(SCRIPTS, jit=True)
cooking = req("cooking")

forca_bruta = lua.eval(r"""
function(cooking, reps, custos)
  local portatil = cooking.recipes.portablecookpot
  local comum = cooking.recipes.cookpot
  local lista = {}
  for nome, r in pairs(portatil) do lista[#lista + 1] = r end
  local tags_de = {}
  for i = 1, #reps do tags_de[i] = cooking.ingredients[reps[i]].tags end

  -- res[cozinha][prato] = { usa = {idx=true}, chance, combo, custo }
  local res = { cookpot = {}, portablecookpot = {} }
  local ok = {}
  local n = #reps
  local combo = {0, 0, 0, 0}

  local function registra(coz, grupo)
    local total = 0
    for _, r in ipairs(grupo) do total = total + (r.weight or 1) end
    local c = custos[combo[1]] + custos[combo[2]] + custos[combo[3]] + custos[combo[4]]
    for _, r in ipairs(grupo) do
      local e = res[coz][r.name]
      if e == nil then e = { usa = {}, chance = -1 }; res[coz][r.name] = e end
      for k = 1, 4 do e.usa[combo[k]] = true end
      local chance = (r.weight or 1) / total
      if chance > e.chance or (chance == e.chance and c < e.custo) then
        e.chance, e.custo = chance, c
        e.combo = { combo[1], combo[2], combo[3], combo[4] }
      end
    end
  end

  local function topo(filtro)
    local melhor, grupo = -math.huge, {}
    for i = 1, #ok do
      local r = ok[i]
      if filtro == nil or filtro[r.name] then
        local pr = r.priority or 0
        if pr > melhor then melhor = pr; grupo = { r } elseif pr == melhor then grupo[#grupo + 1] = r end
      end
    end
    return grupo
  end

  local total = 0
  for a = 1, n do for b = a, n do for c = b, n do for d = c, n do
    combo[1], combo[2], combo[3], combo[4] = a, b, c, d
    local names, tags = {}, {}
    for k = 1, 4 do
      local item = reps[combo[k]]
      names[item] = (names[item] or 0) + 1
      for t, v in pairs(tags_de[combo[k]]) do tags[t] = (tags[t] or 0) + v end
    end
    for i = #ok, 1, -1 do ok[i] = nil end
    for i = 1, #lista do
      if lista[i].test("portablecookpot", names, tags) then ok[#ok + 1] = lista[i] end
    end
    registra("portablecookpot", topo(nil))
    registra("cookpot", topo(comum))
    total = total + 1
  end end end end
  return res, total
end
""")

t0 = time.time()
custos = lua.table_from({i + 1: custo(r) for i, r in enumerate(reps)})
res, total = forca_bruta(cooking, lua.table_from(reps), custos)
print(f"{total} combinações em {time.time() - t0:.0f}s")


def tbl(t):
    return dict(t.items()) if t is not None and lua.eval("type")(t) == "table" else {}


apelido_inv = {v: k for k, v in p["apelidos"].items()}   # meat_cooked -> cookedmeat (prefab)
pratos = {}
receitas = tbl(tbl(cooking.recipes)["portablecookpot"])
comum = tbl(tbl(cooking.recipes)["cookpot"])
for nome in sorted(receitas):
    if nome == "wetgoop":
        continue
    por = tbl(tbl(res["portablecookpot"]).get(nome))
    com = tbl(tbl(res["cookpot"]).get(nome))
    alvo = com or por
    if not alvo:
        continue
    usa = set()
    for idx in tbl(alvo["usa"]):
        usa.update(grupos[int(idx) - 1])
    # exemplo: o do livro de receitas do jogo, se existir; senão o melhor achado
    card = tbl(tbl(receitas[nome]).get("card_def"))
    exemplo = []
    for _, par in tbl(card.get("ingredients")).items():
        par = tbl(par)
        exemplo += [par[1]] * int(par[2])
    if not exemplo:
        exemplo = [reps[int(i) - 1] for i in tbl(alvo["combo"]).values()]
    pratos[nome] = {
        "warly": nome not in comum,
        "chance": round(float(alvo["chance"]), 3),
        "exemplo": [apelido_inv.get(x, x) for x in exemplo],
        "usa": sorted(apelido_inv.get(x, x) for x in usa),
    }


# --- Categorias: no exemplo, um ingrediente vira "Carne", "Legume"... quando QUALQUER outro
# item com exatamente as mesmas tags (ex.: cenoura, batata, milho = veggie 1) também faz o
# prato vencer, com a mesma chance. Itens únicos (mandrágora, ovo de passaralto, gelo...)
# ou citados pelo nome na receita continuam aparecendo como o próprio item.
# tag do jogo -> (id do ícone, nome, nome da meia unidade)
CATEG = {"meat": ("carne", "Carne", "Meia carne"), "veggie": ("legume", "Legume", "Meio legume"),
         "fruit": ("fruta", "Fruta", "Meia fruta"), "egg": ("ovo", "Ovo", "Meio ovo"),
         "fish": ("peixe", "Peixe", "Meio peixe"), "sweetener": ("adocante", "Adoçante", "Meio adoçante"),
         "dairy": ("laticinio", "Laticínio", "Meio laticínio"), "monster": ("monstro", "Monstro", "Meio monstro")}
IGNORAR = {"precook", "dried"}

vence = lua.eval(r"""
function(cooking, coz, prato, itens)
  local names, tags = {}, {}
  for _, item in ipairs(itens) do
    names[item] = (names[item] or 0) + 1
    for t, v in pairs(cooking.ingredients[item].tags) do tags[t] = (tags[t] or 0) + v end
  end
  local melhor, grupo = -math.huge, {}
  for _, r in pairs(cooking.recipes[coz]) do
    if r.test(coz, names, tags) then
      local pr = r.priority or 0
      if pr > melhor then melhor = pr; grupo = { r } elseif pr == melhor then grupo[#grupo + 1] = r end
    end
  end
  local total, meu = 0, 0
  for _, r in ipairs(grupo) do
    total = total + (r.weight or 1)
    if r.name == prato then meu = r.weight or 1 end
  end
  return total > 0 and meu / total or 0
end
""")


def tipo(item):
    return tuple(sorted((t, v) for t, v in ingredientes[item]["tags"].items() if t not in IGNORAR))


def rotulo(t):
    """tags exatas -> id da categoria ("legume", "meio_legume"...) ou None"""
    chaves = {k for k, _ in t}
    if chaves == {"meat", "fish"}:
        tag, valor = "fish", dict(t)["fish"]
    elif len(t) == 1 and t[0][0] in CATEG:
        tag, valor = t[0]
    else:
        return None
    if valor >= 1:
        return CATEG[tag][0]
    return "meio_" + CATEG[tag][0] if valor == 0.5 else None


def citados_em(nome):
    r = p["panela"].get(nome) or p["portatil"].get(nome) or {"lua": ""}
    return set(re.findall(r"names\.(\w+)", r["lua"]))


def categorias(nome, exemplo, warly):
    coz = "portablecookpot" if warly else "cookpot"
    base = vence(cooking, coz, nome, lua.table_from(exemplo))
    cats = {}
    for x in dict.fromkeys(exemplo):
        if x not in ingredientes:
            continue
        t = tipo(x)
        nome_cat = rotulo(t)
        if x in citados_em(nome):
            continue                      # a receita pede este item pelo nome
        # itens que alguma receita pede pelo nome (folha de carne, tromba...) são "especiais":
        # não precisam funcionar aqui para o ingrediente contar como da categoria
        membros = [y for y in ingredientes if y != x and tipo(y) == t and y not in citados]
        # precisa ter outro item "de verdade" (não só a versão cozida/seca do mesmo)
        raiz = x.replace("_cooked", "").replace("cooked", "").replace("_dried", "")
        outros = [y for y in ingredientes if tipo(y) == t and y.replace("_cooked", "").replace("cooked", "").replace("_dried", "") != raiz]
        if nome_cat is None or not outros:
            continue
        if all(vence(cooking, coz, nome, lua.table_from([y if i == x else i for i in exemplo])) >= base - 1e-9
               for y in membros):
            cats[apelido_inv.get(x, x)] = nome_cat
    return cats


for nome, d in pratos.items():
    ex_cozinha = [p["apelidos"].get(x, x) for x in d["exemplo"]]   # nomes do cooking.lua
    d["cat"] = categorias(nome, ex_cozinha, d["warly"])
print("com categoria:", sum(1 for d in pratos.values() if d["cat"]), "de", len(pratos))


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def cat(d):
    return "{" + ", ".join(f"[{lua_str(k)}] = {lua_str(v)}" for k, v in sorted(d.items())) + "}"


def lista(xs):
    return "{" + ", ".join(lua_str(x) for x in xs) + "}"


linhas = ["-- GERADO por receitas/gerar_receitas_mod.py a partir do cooking.lua do jogo. Não edite à mão.",
          "-- usa: ingredientes que aparecem em alguma combinação em que o prato vence (busca da aba Todas).",
          "-- exemplo: uma combinação que funciona (a do livro de receitas do jogo, quando existe).",
          "-- cat: item do exemplo que pode ser trocado por qualquer outro da mesma categoria -> id (geladeira_categorias.lua).",
          "return {"]
for nome, d in pratos.items():
    linhas.append(f"  {nome} = {{ warly = {str(d['warly']).lower()}, chance = {d['chance']}, "
                  f"exemplo = {lista(d['exemplo'])}, cat = {cat(d['cat'])},\n    usa = {lista(d['usa'])} }},")
linhas.append("}")
OUT.write_text("\n".join(linhas) + "\n", encoding="utf-8")
print(f"{len(pratos)} pratos -> {OUT} ({OUT.stat().st_size} bytes); "
      f"warly={sum(d['warly'] for d in pratos.values())}")


# --- geladeira_categorias.lua: o que é cada categoria (aba Legenda do mod)
usadas = {c for d in pratos.values() for c in d["cat"].values()}
cru = lambda y: not (y.endswith(("_cooked", "_dried")) or y.startswith("cooked"))
saida_cat = ["-- GERADO por receitas/gerar_receitas_mod.py. Não edite à mão.",
             "-- Categorias de ingrediente da aba Todas. itens: exemplos que valem exatamente isso.",
             "return {"]
for tag, (cid, nome_cat, nome_meio) in CATEG.items():
    for id_, nome_, valor in ((cid, nome_cat, 1), ("meio_" + cid, nome_meio, 0.5)):
        if id_ not in usadas:
            continue
        membros = sorted({apelido_inv.get(y, y) for y in ingredientes
                          if rotulo(tipo(y)) == id_ and cru(y)}, key=lambda y: (y in citados, custo(y), y))
        saida_cat.append(f"  {{ id = {lua_str(id_)}, nome = {lua_str(nome_)}, tag = {lua_str(tag)}, valor = {valor}, "
                         f"itens = {lista(membros)} }},")
saida_cat.append("}")
OUT_CAT = OUT.with_name("geladeira_categorias.lua")
OUT_CAT.write_text("\n".join(saida_cat) + "\n", encoding="utf-8")
print(f"{len(usadas)} categorias -> {OUT_CAT}")
