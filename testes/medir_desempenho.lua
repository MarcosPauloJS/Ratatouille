-- Mede o custo do mod no PIOR caso: 3 geladeiras cheias com 27 tipos diferentes
-- de ingrediente + 30 mil outras entidades no mundo. Roda no Lua 5.1 interpretado
-- (sem JIT), o mesmo tipo de Lua do DST. Os tempos dependem da máquina.
local dir = ...
local real = _G
local cooking = require("cooking")
local clock = os.clock

-- 27 ingredientes de panela diferentes, com nome no jogo e comida de gente
local escolhidos = {}
for nome, _ in pairs(cooking.ingredients) do
    if real.STRINGS.NAMES[nome:upper()] and #escolhidos < 27 then escolhidos[#escolhidos + 1] = nome end
end
table.sort(escolhidos)
local function item(prefab, n)
    return { prefab = prefab, GetBasicDisplayName = function() return prefab end,
             components = { stackable = { StackSize = function() return n end },
                            edible = { foodtype = "VEGGIE", healthvalue = 1, hungervalue = 10, sanityvalue = 0 } } }
end
local ents = {}
for g = 0, 2 do
    local slots = {}
    for k = 1, 9 do slots[k] = item(escolhidos[g * 9 + k], 10) end
    ents[#ents + 1] = { prefab = "icebox", Transform = { GetWorldPosition = function() return g * 5, 0, 0 end },
                        components = { container = { slots = slots } }, IsValid = function() return true end,
                        HasTag = function(_, t) return t == "fridge" or t == "structure" end }
end
for i = 1, 30000 do   -- árvores, pedras, bichos...: só custam a checagem
    ents[#ents + 1] = { components = {}, IsValid = function() return true end, HasTag = function() return false end }
end

local frames, pior_frame, total_servidor = 0, 0, 0
local enviado
local player = { userid = "u1", prefab = "wilson", IsValid = function() return true end,
                 HasTag = function() return false end, components = {} }
local G = setmetatable({
    KEY_L = 108, KEY_K = 107, Ents = ents,
    ChatHistory = { SendCommandResponse = function() end },
    TheInput = { AddKeyUpHandler = function() end },
    TheFrontEnd = { GetActiveScreen = function() return { name = "HUD" } end, PushScreen = function() end,
                    PopScreen = function() end },
    StartThread = function(fn)
        local co = coroutine.create(fn)
        while coroutine.status(co) ~= "dead" do
            local t0 = clock()
            assert(coroutine.resume(co))
            local dt = clock() - t0
            frames = frames + 1
            total_servidor = total_servidor + dt
            if dt > pior_frame then pior_frame = dt end
        end
    end,
    Yield = coroutine.yield,
    SpawnPrefab = function() return nil end,
    Asset = function(tipo, arq) return { tipo = tipo, arq = arq } end,
    ThePlayer = {},   -- outro jogador: a resposta vai por RPC (medimos o tamanho)
}, { __index = real })
local handlers = {}
local env = setmetatable({
    GLOBAL = G, MODROOT = "../mods/Ratatouille/", GetModConfigData = function(k) return ({ key = "KEY_L", key_receitas = "KEY_K", range = 0,
        include_saltbox = true, display = "janela" })[k] end,
    require = function(n)
        if n == "widgets/geladeira_painel" then return function() return {} end end
        if n == "geladeira_receitas" or n == "geladeira_simples" or n == "geladeira_categorias" then return dofile(dir .. "/scripts/" .. n .. ".lua") end
        return real.require(n)
    end,
    AddClientModRPCHandler = function(_, _, f) handlers.cliente = f end,
    AddModRPCHandler = function(_, n, f) handlers[n] = f end,
    AddClassPostConstruct = function() end,
    AddComponentPostInit = function() end,
    SendModRPCToClient = function(_, _, texto) enviado = texto end,
    GetClientModRPC = function() end, GetModRPC = function(_, n) return n end,
    SendModRPCToServer = function() end,
    pairs = pairs, ipairs = ipairs, print = print, math = math, table = table, type = type,
    string = string, tostring = tostring, Class = function() end,
}, { __index = function(_, k) error("global inexistente no modmain: " .. tostring(k), 2) end })
local main = assert(loadfile(dir .. "/modmain.lua")); setfenv(main, env); main()

-- SERVIDOR: um pedido completo
handlers.pedir(player, "gcbp", 2)
print(string.format("SERVIDOR  %d tipos na geladeira, %d entidades no mundo", #escolhidos, #ents))
print(string.format("  tempo total de CPU: %.0f ms, espalhado em %d frames", total_servidor * 1000, frames))
print(string.format("  pior frame: %.1f ms  (a 30 FPS cada frame tem 33 ms)", pior_frame * 1000))
print(string.format("  a janela abre depois de ~%.1f s a 30 FPS", frames / 30))
print(string.format("  mensagem enviada ao jogador: %.1f KB", #enviado / 1024))

-- CLIENTE: receber a mensagem e montar as abas (inclui carregar a aba Todas na 1ª vez)
collectgarbage("collect")
local mem0 = collectgarbage("count")
local t0 = clock()
handlers.cliente(enviado)
local t1 = clock()
handlers.cliente(enviado)
local t2 = clock()
collectgarbage("collect")
print("CLIENTE")
print(string.format("  1ª vez que abre: %.0f ms (carrega as 175 receitas da aba Todas)", (t1 - t0) * 1000))
print(string.format("  próximas vezes: %.0f ms", (t2 - t1) * 1000))
print(string.format("  memória que fica ocupada: ~%.0f KB", collectgarbage("count") - mem0))
