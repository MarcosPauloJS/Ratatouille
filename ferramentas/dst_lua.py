"""Ambiente Lua 5.1 isolado que carrega os scripts oficiais do DST (stubs do motor)."""
import lupa.lua51 as lua51


def runtime(scripts_dir, jit=False):
    """Devolve (lua, G, req) com util/constants/strings/tuning já carregados.
    jit=True usa LuaJIT (bem mais rápido para força bruta; mesma semântica de Lua 5.1)."""
    SCRIPTS = scripts_dir
    if jit:
        import lupa.luajit21 as engine
    else:
        engine = lua51
    lua = engine.LuaRuntime(unpack_returned_tuples=True)
    G = lua.globals()
    G.SCRIPTS_DIR = str(SCRIPTS) + "/"

    lua.execute(r"""
    -- Stub genérico para APIs do motor (TheSim, TheNet, etc.)
    local stub_mt = {}
    local function newstub() return setmetatable({}, stub_mt) end
    stub_mt.__index = function() return newstub() end
    stub_mt.__call = function() return newstub() end
    stub_mt.__concat = function(a, b) return tostring(type(a)=="table" and "" or a)..tostring(type(b)=="table" and "" or b) end
    stub_mt.__tostring = function() return "" end
    for _, op in ipairs({"__add","__sub","__mul","__div","__unm","__mod","__pow"}) do
      stub_mt[op] = function() return 0 end
    end
    stub_mt.__lt = function() return false end
    stub_mt.__le = function() return false end
    STUB = newstub

    -- Funções do motor/locais que os scripts esperam
    setmetatable(_G, { __index = function(t, k) return newstub() end })
    function global(name) end
    function IsConsole() return false end
    function IsPS4() return false end
    function IsXB1() return false end
    function IsSteamDeck() return false end
    function IsSteam() return true end
    function IsRail() return false end
    function IsSpecialEventActive() return false end
    function IsAnyFestivalEventActive() return false end
    function IsFestivalEventActive() return false end
    function GetSpecialEventSkinTag() return nil end
    function resolvefilepath(p) return p end
    function softresolvefilepath(p) return p end
    function GetInventoryItemAtlas(p) return "images/inventoryimages.xml" end
    function GetScrapbookIconAtlas(p) return nil end
    function kleifileexists() return false end
    function moderror(m) print("moderror", m) end
    function modprint() end
    PLATFORM = "WIN32_STEAM"
    BRANCH = "release"
    CONFIGURATION = "PRODUCTION"
    APP_VERSION = "0"
    TheNet = newstub()
    TheSim = newstub()
    Profile = newstub()
    CRAFTING_ICONS_ATLAS = "images/crafting_menu_icons.xml"

    package.path = SCRIPTS_DIR .. "?.lua;" .. package.path
    local _req = require
    local loaded = {}
    function require(name)
      name = name:gsub("%.lua$", ""):gsub("^scripts/", "")
      if loaded[name] ~= nil then return loaded[name] end
      local f, err = loadfile(SCRIPTS_DIR .. name .. ".lua")
      if not f then
        -- módulo ausente/do motor: devolve stub
        loaded[name] = newstub()
        return loaded[name]
      end
      loaded[name] = true
      local ok, res = pcall(f)
      if not ok then
        print("[aviso] falha em require('"..name.."'): "..tostring(res))
        loaded[name] = newstub()
      else
        loaded[name] = (res == nil) and true or res
      end
      return loaded[name]
    end
    """)

    def req(name):
        return lua.eval(f'require("{name}")')

    for mod in ["class", "util", "vecutil", "vector3", "mathutil", "constants",
                "strings", "techtree", "tuning"]:
        req(mod)
    lua.execute("Tune()")
    return lua, G, req
