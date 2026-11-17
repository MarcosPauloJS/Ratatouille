"""Extrai receitas simples (assar na fogueira e secar no varal) rodando os prefabs oficiais
com uma entidade falsa que registra os componentes.

uso: python -I extract_simple.py <scripts_dir> <receitas.json> <out_simples.json>
"""
import json
import re
import sys
from pathlib import Path

from lupa import lua51

SCRIPTS, DATA, OUT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
lua = lua51.LuaRuntime()
lua.globals().SCRIPTS_DIR = str(SCRIPTS) + "/"

lua.execute(r"""
local stub_mt = {}
local function newstub() return setmetatable({}, stub_mt) end
stub_mt.__index = function() return newstub() end
stub_mt.__call = function() return newstub() end
stub_mt.__concat = function(a, b) return tostring(type(a)=="table" and "" or a)..tostring(type(b)=="table" and "" or b) end
for _, op in ipairs({"__add","__sub","__mul","__div","__unm","__mod","__pow"}) do stub_mt[op] = function() return 0 end end
stub_mt.__lt = function() return false end
stub_mt.__le = function() return false end
STUB = newstub
setmetatable(_G, { __index = function() return newstub() end })
function global() end
function IsConsole() return false end
function IsSteamDeck() return false end
function IsSpecialEventActive() return false end
function IsAnyFestivalEventActive() return false end
function resolvefilepath(p) return p end
function softresolvefilepath(p) return p end
TheNet = newstub(); TheSim = newstub()
TheWorld = newstub()
rawset(TheWorld, "ismastersim", true)

local loaded = {}
function require(name)
  name = name:gsub("%.lua$", ""):gsub("^scripts/", "")
  if loaded[name] ~= nil then return loaded[name] end
  local f = loadfile(SCRIPTS_DIR .. name .. ".lua")
  if not f then loaded[name] = newstub() return loaded[name] end
  loaded[name] = true
  local ok, res = pcall(f)
  loaded[name] = ok and (res == nil and true or res) or newstub()
  return loaded[name]
end
for _, m in ipairs({"class","util","constants","strings","techtree","tuning"}) do require(m) end
Tune()

-- Componente "gravador": guarda campos atribuídos e chamadas de método
local function recorder(defaults)
  local calls = {}
  local obj = defaults or {}
  obj.__calls = calls
  return setmetatable(obj, { __index = function(t, k)
    return function(self, ...) calls[k] = {...}; return newstub() end
  end })
end
local DEFAULTS = {
  edible = function() return { healthvalue = 10, hungervalue = 10, sanityvalue = 0, foodtype = FOODTYPE.GENERIC } end,
}

-- Entidade falsa
local function fake_entity()
  local inst = newstub()
  -- Componentes que funções auxiliares do motor adicionariam (floater, etc.) são criados sob demanda
  rawset(inst, "components", setmetatable({}, { __index = function(t, k)
    local c = recorder(DEFAULTS[k] and DEFAULTS[k]() or {})
    rawset(t, k, c)
    return c
  end }))
  rawset(inst, "AddComponent", function(self, name)
    local c = recorder(DEFAULTS[name] and DEFAULTS[name]() or {})
    rawset(c, "__added", true)  -- adicionado explicitamente pelo prefab (não criado sob demanda)
    rawset(self.components, name, c)
    return c
  end)
  rawset(inst, "RemoveComponent", function(self, name) self.components[name] = nil end)
  rawset(inst, "AddTag", function() end)
  rawset(inst, "HasTag", function() return false end)
  rawset(inst, "ListenForEvent", function() end)
  rawset(inst, "SetPrefabName", function() end)
  return inst
end
function CreateEntity() return fake_entity() end

PREFABS = {}
function Prefab(name, fn, assets, deps) PREFABS[name] = fn; return { name = name } end

function LOAD_PREFAB_FILE(path)
  local f = loadfile(path)
  if not f then return end
  pcall(f)
end

local function grab(inst)
  local c = rawget(inst, "components") or {}
  local out = {}
  local e = rawget(c, "edible")
  if e and rawget(e, "__added") then
    out.health = type(e.healthvalue)=="number" and e.healthvalue or nil
    out.hunger = type(e.hungervalue)=="number" and e.hungervalue or nil
    out.sanity = type(e.sanityvalue)=="number" and e.sanityvalue or nil
    out.foodtype = type(e.foodtype)=="string" and e.foodtype or nil
    local tp = e.temperaturedelta
    if type(tp)=="number" then out.temp = tp end
  end
  local p = rawget(c, "perishable")
  if p and p.__calls.SetPerishTime then
    local t = p.__calls.SetPerishTime[1]
    if type(t)=="number" then out.perish = t end
  end
  local ck = rawget(c, "cookable")
  if ck and type(ck.product)=="string" then out.cooked = ck.product end
  local dr = rawget(c, "dryable")
  if dr then
    if dr.__calls.SetProduct and type(dr.__calls.SetProduct[1])=="string" then out.dried = dr.__calls.SetProduct[1] end
    if dr.__calls.SetDryTime and type(dr.__calls.SetDryTime[1])=="number" then out.drytime = dr.__calls.SetDryTime[1] end
  end
  return out
end

function RUN_ALL()
  local res, fails = {}, 0
  for name, fn in pairs(PREFABS) do
    local ok, inst = pcall(fn)
    if ok and type(inst)=="table" then
      local g = grab(inst)
      if next(g) then res[name] = g end
    else
      fails = fails + 1
    end
  end
  return res, fails
end
""")

for p in sorted((SCRIPTS / "prefabs").glob("*.lua")):
    txt = p.read_text(encoding="utf-8", errors="replace")
    # Só carrega arquivos que têm comida, para ir rápido e evitar efeitos colaterais
    if re.search(r'"(edible|cookable|dryable)"', txt):
        lua.globals().LOAD_PREFAB_FILE(str(p))

res, fails = lua.globals().RUN_ALL()
items = {k: dict(v.items()) for k, v in res.items()}
print("prefabs com dados:", len(items), "falhas:", fails)

d = json.loads(DATA.read_text(encoding="utf-8"))
po = (SCRIPTS / "languages" / "portuguese_br.po").read_text(encoding="utf-8", errors="replace")
PT, EN = {}, {}
for key, en, pt in re.findall(r'msgctxt "STRINGS\.NAMES\.([A-Z0-9_]+)"\s*\nmsgid "(.*?)"\s*\nmsgstr "(.*?)"\n', po):
    PT[key], EN[key] = pt or en, en

NAME_FIX = {"fish": ("Peixe", "Fish")}  # a tradução oficial traz "Pescar" aqui

def nm(p):
    if p in NAME_FIX:
        return {"pt": NAME_FIX[p][0], "en": NAME_FIX[p][1]}
    return {"pt": PT.get(p.upper()) or EN.get(p.upper()) or p, "en": EN.get(p.upper()) or ""}

def stats(p):
    it = items.get(p, {})
    per = it.get("perish")
    return {
        "h": round(it["health"], 2) if "health" in it else None,
        "u": round(it["hunger"], 2) if "hunger" in it else None,
        "s": round(it["sanity"], 2) if "sanity" in it else None,
        "p": round(per / 480, 1) if per else None,
        "ty": it.get("foodtype"),
        "edible": "health" in it,
    }

out = []
SKIP = re.compile(r"^(quagmire_)|_worldgen$")
for raw, it in sorted(items.items()):
    if SKIP.search(raw):
        continue
    for method, key in (("fogueira", "cooked"), ("varal", "dried")):
        prod = it.get(key)
        if not prod:
            continue
        r, c = stats(raw), stats(prod)
        if not c["edible"] and not r["edible"]:
            continue  # ex.: itens que viram algo não comestível
        out.append({
            "m": method,
            "raw": raw, "rn": nm(raw)["pt"], "ren": nm(raw)["en"],
            "prod": prod, "pn": nm(prod)["pt"], "pen": nm(prod)["en"],
            "r": r, "c": c,
            "t": round(it["drytime"] / 480, 2) if method == "varal" and it.get("drytime") else None,
        })

OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
print("receitas simples:", len(out), "fogueira:", sum(o["m"] == "fogueira" for o in out), "varal:", sum(o["m"] == "varal" for o in out))
for k in ["batwing", "meat", "carrot", "berries", "monstermeat", "egg", "fish", "smallmeat"]:
    for o in out:
        if o["raw"] == k:
            print(o["m"], o["rn"], o["r"], "->", o["pn"], o["c"], o["t"])
