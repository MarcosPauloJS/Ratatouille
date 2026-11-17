-- Teste do mod Ratatouille fora do jogo.
-- Roda dentro do ambiente de receitas/dst_lua.py (scripts reais do jogo: cooking.lua,
-- FOODGROUP, STRINGS...). O modmain roda num ambiente tão restrito quanto o do jogo.
-- uso: python testes/rodar.py   (ver rodar.py)
local dir = ...
local real = _G
require("cooking")
-- se o cooking.lua do jogo não carregou, o teste não vale nada: para aqui
assert(rawget(real, "GetCandidateRecipes") ~= nil, "cooking.lua do jogo não carregou (scripts do jogo ausentes?)")

local falhas = 0
local function confere(cond, msg)
    print((cond and "  ok   " or "  FALHA ") .. msg)
    if not cond then falhas = falhas + 1 end
end

-- Itens com o foodtype REAL de cada prefab (conferido nos prefabs do jogo)
local FOODTYPE = real.FOODTYPE
local function item(prefab, n, foodtype, extra)
    local c = { stackable = { StackSize = function() return n end } }
    if foodtype then c.edible = { foodtype = foodtype, healthvalue = 1, hungervalue = 1, sanityvalue = 0 } end
    for k, v in pairs(extra or {}) do c[k] = v end
    return { prefab = prefab, components = c, GetBasicDisplayName = function() return prefab end }
end

local geladeira = { item("meat", 6, FOODTYPE.MEAT, { cookable = { product = "cookedmeat" } }),
                    item("berries", 10, FOODTYPE.VEGGIE), item("ice", 8, FOODTYPE.GENERIC),
                    item("monstermeat", 2, FOODTYPE.MEAT) }
local mochila = { prefab = "backpack", slots = {
    item("honey", 3, FOODTYPE.GOODIES),
    item("goldnugget", 4, FOODTYPE.ELEMENTAL),     -- comida da lagosta de pedra: fora
    item("log", 7, FOODTYPE.WOOD),                 -- comida do Woodie castor: fora
} }
local inventario = {
    item("rocks", 20, FOODTYPE.ELEMENTAL),         -- fora
    item("flint", 9, FOODTYPE.ELEMENTAL),          -- fora
    item("nitre", 2, FOODTYPE.ELEMENTAL),          -- fora
    item("gears", 1, FOODTYPE.GEARS),              -- fora (WX-78)
    item("cutgrass", 12, FOODTYPE.ROUGHAGE),       -- fora (comida de bife)
    item("axe", 1, nil),                           -- fora (nem comestível)
    item("twigs", 10, nil),                        -- DENTRO: ingrediente de panela
    item("seeds", 5, FOODTYPE.SEEDS),              -- DENTRO: semente é dieta humana
    item("meat", 2, FOODTYPE.MEAT),                -- DENTRO (soma com a geladeira)
    item("batwing", 1, FOODTYPE.MEAT, { cookable = { product = "batwing_cooked" } }), -- DENTRO
}
local fridge = { components = { container = { slots = geladeira } }, IsValid = function() return true end,
                 HasTag = function(_, t) return t == "fridge" or t == "structure" end }
-- Chester de gelo: tags "chester" e "fridge" (sem "structure"); guarda qualquer coisa
local chester = { components = { container = { slots = {
    item("rocks", 5, FOODTYPE.ELEMENTAL), item("goldnugget", 2, FOODTYPE.ELEMENTAL),
    item("pickaxe", 1, nil), item("meat", 1, FOODTYPE.MEAT), item("carrot", 3, FOODTYPE.VEGGIE) } } },
    IsValid = function() return true end, HasTag = function(_, t) return t == "fridge" or t == "chester" end }
-- Chester comum: só tag "chester" (sem "fridge")
local chester_comum = { components = { container = { slots = {
    item("flint", 3, FOODTYPE.ELEMENTAL), item("berries", 2, FOODTYPE.VEGGIE) } } },
    IsValid = function() return true end, HasTag = function(_, t) return t == "chester" end }
local function bolsa(slots)
    return { prefab = "icepack", components = { container = { slots = slots } },
             Transform = { GetWorldPosition = function() return 50, 0, 50 end },
             AnimState = { SetAddColour = function() end },
             IsValid = function() return true end, HasTag = function(_, t) return t == "fridge" end }
end
local bolsa_chao = bolsa({ item("rocks", 3, FOODTYPE.ELEMENTAL), item("potato", 4, FOODTYPE.VEGGIE) })
local arvore = { prefab = "livingtree_halloween", components = { container = { slots = { item("charcoal", 9, nil) } } },
                 IsValid = function() return true end, HasTag = function(_, t) return t == "fridge" end }
-- Posição e cor de cada recipiente (para o destaque no mundo)
local function posicionar(e, prefab, x, z)
    e.prefab = e.prefab or prefab
    e.pos = { x = x, z = z }
    e.Transform = { GetWorldPosition = function() return x, 0, z end }
    e.AnimState = { SetAddColour = function(_, r) e.cor = r end }
end
posicionar(fridge, "icebox", 10, 20)
posicionar(chester, "chester", 3, 4)
posicionar(chester_comum, "chester", -5, 6)
posicionar(arvore, "livingtree_halloween", 90, 90)
local player = { userid = "u1", IsValid = function() return true end, HasTag = function() return false end,
    components = { inventory = { itemslots = inventario,
        GetActiveItem = function() return item("ice", 4, FOODTYPE.GENERIC) end,
        GetOverflowContainer = function() return mochila end } } }

-- GLOBAL falso por cima do ambiente real do jogo
local handlers, keys, postinits = {}, {}, {}
local stack = { "HUD" }        -- cada MostrarDados do painel empilha {dados, aba_atual} aqui
local tela_ativa = "HUD"
local G = setmetatable({
    KEY_L = 108, KEY_K = 107, Ents = { fridge, chester, chester_comum, bolsa_chao, arvore },
    ChatHistory = { SendCommandResponse = function() end },
    TheInput = { AddKeyUpHandler = function(_, k, f) keys[k] = f end },
    TheFrontEnd = {
        GetActiveScreen = function() return { name = tela_ativa } end,
    },
    StartThread = function(fn) local co = coroutine.create(fn)
        while coroutine.status(co) ~= "dead" do assert(coroutine.resume(co)) end end,
    Yield = coroutine.yield,
    SpawnPrefab = function() return nil end,
    Asset = function(tipo, arq) return { tipo = tipo, arq = arq } end,
}, { __index = function(_, k)
    -- GLOBAL estrito como no DST: ler global inexistente é erro
    local v = rawget(real, k)
    if v == nil then error("GLOBAL." .. tostring(k) .. " não existe (variable is not declared)", 2) end
    return v
end })
G.ThePlayer = player

-- Painel lateral falso (o de verdade só dá para ver no jogo): mesma interface
local painel = { aberto = false }
function painel:EstaAberto() return self.aberto end
function painel:Alternar(aba)
    if not self.aberto then
        self.aberto = true; self.opcoes.pedir(aba)
    elseif self.conteudo and self.conteudo.aba_indice ~= aba and self.conteudo.dados.abas[aba] then
        self.conteudo.aba_indice = aba; stack[#stack].aba_atual = self.conteudo.dados.abas[aba].id
    else
        self.aberto = false
    end
end
local combos_recebidos
function painel:MostrarDados(d)
    self.conteudo = { aba_indice = d.abrir, dados = d,
        ReceberCombos = function(_, prato, lista, resto) combos_recebidos = { prato = prato, lista = lista, resto = resto } end }
    stack[#stack + 1] = { dados = d, aba_atual = d.abas[d.abrir].id }
end
local FakePainel = function(opcoes) painel.opcoes = opcoes; return painel end
local controls = { right_root = { AddChild = function(_, c) return c end } }
player.HUD = { controls = controls }
local cfg = { key = "KEY_L", key_receitas = "KEY_K", range = 0, include_saltbox = true,
              display = "janela" }
local env = setmetatable({
    GLOBAL = G, MODROOT = "../mods/Ratatouille/", GetModConfigData = function(k) return cfg[k] end,
    require = function(n)
        if n == "widgets/geladeira_painel" then return FakePainel end
        if n == "geladeira_receitas" or n == "geladeira_simples" or n == "geladeira_categorias" then return dofile(dir .. "/scripts/" .. n .. ".lua") end
        return real.require(n)
    end,
    AddClientModRPCHandler = function() end,
    AddModRPCHandler = function(_, n, f) handlers[n] = f end,
    AddClassPostConstruct = function(caminho, fn) assert(caminho == "widgets/controls"); fn(controls) end,
    AddComponentPostInit = function(nome, fn) postinits[nome] = fn end,
    SendModRPCToClient = function() end, GetClientModRPC = function() end,
    GetModRPC = function(_, n) return n end,
    SendModRPCToServer = function(rpc, ...) handlers[rpc](player, ...) end,
    -- igual ao env de mods.lua: só isso do Lua padrão
    pairs = pairs, ipairs = ipairs, print = print, math = math, table = table, type = type,
    string = string, tostring = tostring, Class = function() end,
}, { __index = function(_, k) error("global inexistente no modmain: " .. tostring(k), 2) end })
local main = assert(loadfile(dir .. "/modmain.lua")); setfenv(main, env); main()

local function itens_da_janela()
    local t = {}
    for _, e in ipairs(stack[#stack].dados.abas[1].itens) do t[e.prefab] = tonumber((e.qtd:gsub("x", ""))) end
    return t
end

print("== Abas")
keys[107]()
local nomes = {}
for _, a in ipairs(stack[#stack].dados.abas) do nomes[#nomes + 1] = a.id end
confere(table.concat(nomes, ",") == "itens,disponivel,todas,legenda", "abas = " .. table.concat(nomes, ","))
confere(stack[#stack].aba_atual == "disponivel", "K abre na aba Disponível")
local disp = stack[#stack].dados.abas[2]
local g = {}
for _, e in ipairs(disp.itens) do g[e.grupo or "?"] = (g[e.grupo or "?"] or 0) + 1 end
confere(disp.filtros ~= nil and #disp.filtros == 3, "Disponível tem os 3 checkboxes")
confere((g.panela or 0) > 0 and (g.fogueira or 0) > 0 and g["?"] == nil,
    string.format("Disponível junta panela (%d) e fogueira (%d), todo item com grupo", g.panela or 0, g.fogueira or 0))
local assada
for _, e in ipairs(disp.itens) do if e.prefab == "cookedmeat" then assada = e end end
confere(assada and assada.icones[1].prefab == "meat" and assada.icones[1].n == 0 and assada.extra == "na fogueira",
    "carne -> carne assada com ícone da carne e 'na fogueira'")
confere(stack[#stack].dados.abas[3].busca == true and not disp.busca, "busca só na aba Todas")

print("== Padrão: Geladeiras + Chester")
confere(stack[#stack].dados.estado.fontes == "gc", "Chester vem marcado por padrão (fontes = gc)")
local t = itens_da_janela()
confere(t.berries == 12 and t.ice == 8, "geladeira entra; frutinhas 10 + 2 do Chester comum")
confere(t.flint == nil, "pederneira do Chester comum fica de fora")
confere(t.rocks == nil and t.goldnugget == nil and t.pickaxe == nil, "pedra, ouro e picareta do Chester ficam de fora")
confere(t.meat == 7 and t.carrot == 3, "comida do Chester entra (carne 6 + 1, cenoura 3)")

confere(t.potato == nil and t.charcoal == nil, "Bolsa Térmica desmarcada e árvore de Halloween não contam")

print("== + Bolsa Térmica")
local d = stack[#stack].dados
d.estado.fontes = "gcb"; d.ao_mudar_fontes("gcb", 1)
t = itens_da_janela()
confere(t.potato == 4 and t.rocks == nil, "batata da Bolsa entra, pedra fica de fora")
confere(stack[#stack].dados.abas[1].resumo:find("Bolsa", 1, true) ~= nil, "resumo: " .. stack[#stack].dados.abas[1].resumo)

print("== Geladeiras + Chester + personagem")
d = stack[#stack].dados
d.estado.fontes = "gcp"; d.ao_mudar_fontes("gcp", 1)
t = itens_da_janela()
for _, p in ipairs({ "rocks", "flint", "nitre", "gears", "cutgrass", "axe", "goldnugget", "log" }) do
    confere(t[p] == nil, p .. " ficou de fora")
end
confere(t.twigs == 10, "gravetos entram (ingrediente de panela)")
confere(t.seeds == 5, "sementes entram (dieta humana)")
confere(t.meat == 9, "carne soma geladeira 6 + Chester 1 + mãos 2")
confere(t.ice == 12, "gelo soma geladeira 8 + cursor 4")
confere(t.honey == 3, "mel da mochila entra")
confere(t.batwing == 1, "asa de morcego entra")

print("== Aba Todas: panela + fogueira + varal")
local todas = stack[#stack].dados.abas[3]
local n = { panela = 0, fogueira = 0, varal = 0 }
for _, e in ipairs(todas.itens) do n[e.grupo] = (n[e.grupo] or 0) + 1 end
confere(todas.id == "todas" and todas.filtros ~= nil and #todas.filtros == 4, "Todas tem 4 filtros (com Warly)")
local repetido = {}
local dup = nil
for _, e in ipairs(todas.itens) do
    local k = e.grupo .. "|" .. e.prefab
    if repetido[k] then dup = k end
    repetido[k] = true
end
confere(dup == nil, "cada produto aparece uma vez por método (repetido: " .. tostring(dup) .. ")")
local sementes, tromba
for _, e in ipairs(todas.itens) do
    if e.prefab == "seeds_cooked" then sementes = e end
    if e.prefab == "trunk_cooked" then tromba = e end
end
confere(sementes and #sementes.icones == 4 and sementes.extra:find("^%+%d+ na fogueira"), "Sementes tostadas: 4 ícones + \"" .. tostring(sementes and sementes.extra) .. "\"")
confere(tromba and #tromba.icones >= 2, "Bife de tromba junta as trombas (" .. (tromba and #tromba.icones or 0) .. " ícones)")
confere(n.panela == 69 and n.warly == 11 and n.fogueira == 47 and n.varal == 15,
    string.format("panela=%d warly=%d fogueira=%d varal=%d", n.panela, n.warly or 0, n.fogueira, n.varal))
local carne_varal
for _, e in ipairs(todas.itens) do if e.grupo == "varal" and e.icones[1].prefab == "meat" then carne_varal = e end end
local function prato_todas(id) for _, e in ipairs(todas.itens) do if e.prefab == id then return e end end end
local function rotulos(e) local r = {} for _, ic in ipairs(e.icones) do r[#r + 1] = ic.categoria or ic.prefab end return table.concat(r, ",") end
for _, e in ipairs(todas.itens) do
    for _, ic in ipairs(e.icones or {}) do assert(ic.rotulo == nil, "Todas: categoria sem nome escrito (" .. e.prefab .. ")") end
end
local kab, sopa = prato_todas("kabobs"), prato_todas("mandrakesoup")
confere(rotulos(kab) == "Carne,Legume,twigs" and kab.icones[2].n == 2, "Espetinho: cebola + berinjela = 2x Legume, graveto não (" .. rotulos(kab) .. ")")
confere(rotulos(sopa) == "Carne,mandrake", "Sopa de mandrágora: mandrágora continua específica (" .. rotulos(sopa) .. ")")
confere(rotulos(prato_todas("talleggs")) == "Carne,Legume,tallbirdegg" and prato_todas("talleggs").detalhe:find("2x Carne"),
    "Ovos de passaralto: ovo de passaralto específico (" .. prato_todas("talleggs").detalhe .. ")")
local sapo = prato_todas("frogglebunwich")
confere(rotulos(sapo) == "froglegs,Meio legume,Legume", "Sanduíche de sapo: Meio legume (cogumelo) separado de Legume (" .. rotulos(sapo) .. ")")
confere(sapo.icones[2].atlas == "images/geladeira_categorias.xml" and sapo.icones[2].tex == "cat_meio_legume.tex"
    and sapo.icones[1].atlas == nil, "categoria usa o selo do mod; item específico usa o ícone do jogo")

print("== Aba Legenda")
local leg = stack[#stack].dados.abas[4]
confere(#leg.itens[3].filhos == 13 and leg.itens[3].chave == "cat:legume", "Legume abre com 13 itens (" .. #leg.itens[3].filhos .. ")")
local esp = leg.itens[10]
local nomes_esp = {}
for _, f in ipairs(esp.filhos) do nomes_esp[f.prefab] = true end
confere(esp.nome == "Item específico" and esp.chave == "cat:especifico" and nomes_esp.mandrake and nomes_esp.tallbirdegg
    and nomes_esp.ice and nomes_esp.twigs and not nomes_esp.carrot,
    "Item específico abre com mandrágora, ovo de passaralto, gelo, graveto (e sem cenoura): " .. #esp.filhos .. " itens")
confere(leg.id == "legenda" and #leg.itens == 10 and leg.itens[10].tex == "cat_especifico.tex", "Legenda: 9 categorias + \"só aquele item\" com ícone próprio (" .. #leg.itens .. ")")
confere(leg.itens[4].nome:find("Meio legume") and leg.itens[4].nome:find("vale metade") and leg.itens[4].tex == "cat_meio_legume.tex",
    "Legenda explica o meio legume: " .. leg.itens[4].nome .. " / " .. leg.itens[4].detalhe)
confere(carne_varal ~= nil and carne_varal.prefab == "meat_dried", "carne no varal vira charque (" .. tostring(carne_varal and carne_varal.extra) .. ")")

print("== Warly")
local function tem_prato(prato)
    for _, e in ipairs(stack[#stack].dados.abas[2].itens) do if e.prefab == prato then return e end end
end
local function todas_aba() return stack[#stack].dados.abas[3] end
d = stack[#stack].dados
d.estado.fontes = "gcp"; d.ao_mudar_fontes("gcp", 2)
confere(#todas_aba().filtros == 4 and todas_aba().filtros[4].id == "warly", "Todas tem checkbox Warly")
local nw = 0
for _, e in ipairs(todas_aba().itens) do if e.grupo == "warly" then nw = nw + 1 end end
confere(nw == 11, "11 pratos no grupo Warly (" .. nw .. ")")
confere(stack[#stack].dados.estado.grupos_off.warly == true, "não é Warly: checkbox Warly vem desmarcado")
confere(tem_prato("monstertartare") == nil, "não é Warly: tartar de monstro (exclusivo) não aparece em Disponível")

player.prefab = "warly"
d = stack[#stack].dados
d.ao_mudar_fontes("gcp", 2)
confere(stack[#stack].dados.estado.grupos_off.warly == nil, "é Warly: checkbox Warly vem marcado")
local tartar = tem_prato("monstertartare")
confere(tartar ~= nil and tartar.extra and tartar.extra:find("Warly", 1, true),
    "é Warly: tartar de monstro aparece em Disponível (" .. tostring(tartar and tartar.extra) .. ")")
confere(stack[#stack].dados.abas[2].rodape:find("Warly", 1, true) ~= nil, "rodapé avisa: " .. stack[#stack].dados.abas[2].rodape)
player.prefab = nil
d = stack[#stack].dados
d.ao_mudar_fontes("gcp", 2)
confere(stack[#stack].dados.estado.grupos_off.warly == true, "trocou de personagem: volta desmarcado ao abrir")

print("== Teclas com o painel lateral")
confere(painel.opcoes ~= nil and type(painel.opcoes.pedir) == "function", "painel criado no HUD (right_root) com a função de pedir")
painel.aberto = false
local antes = #stack
keys[107]()                                             -- K: abre em Disponível e pede ao servidor
confere(painel.aberto and #stack == antes + 1 and stack[#stack].aba_atual == "disponivel", "K abre o painel na aba Disponível")
antes = #stack
keys[108]()                                             -- L: troca para Itens SEM pedir de novo
confere(#stack == antes and stack[#stack].aba_atual == "itens", "L com o painel aberto troca para Itens (sem novo pedido)")
keys[108]()                                             -- L de novo: fecha
confere(not painel.aberto, "L de novo fecha o painel")
tela_ativa = "MapScreen"; keys[108]()
confere(not painel.aberto, "com o mapa aberto, L não faz nada")
tela_ativa = "HUD"
G.TheFrontEnd.forceProcessText = true; keys[108]()
confere(not painel.aberto, "digitando (busca/chat), L não faz nada")
G.TheFrontEnd.forceProcessText = nil

print("== Rodinha do mouse sobre o painel")
G.GetStaticTime = function() return 500 end
local zooms = 0
local pc = { lastzoomtime = 1 }
function pc:DoCameraControl()       -- imita o jogo: só dá zoom se passou 0,1 s do último
    if 500 - self.lastzoomtime > 0.1 then zooms = zooms + 1; self.lastzoomtime = 500 end
end
postinits.playercontroller(pc)
painel.aberto, painel.focus = true, true
pc.lastzoomtime = 1; pc:DoCameraControl()
confere(zooms == 0, "mouse em cima do painel aberto: a câmera NÃO dá zoom")
painel.focus = false
pc.lastzoomtime = 1; pc:DoCameraControl()
confere(zooms == 1, "mouse fora do painel: zoom normal")
painel.aberto, painel.focus = false, true
pc.lastzoomtime = 1; pc:DoCameraControl()
confere(zooms == 2, "painel fechado: zoom normal")

print("== Contagem por fonte (ao lado dos checkboxes)")
d = stack[#stack].dados
d.estado.fontes = "gc"; d.ao_mudar_fontes("gc", 1)
local cf = stack[#stack].dados.contagem_fontes or {}
confere(cf.g == 1 and cf.c == 2 and cf.b == nil and cf.p == nil,
    string.format("só gc: geladeiras=%s chesters=%s (bolsa/personagem desmarcados ficam sem número)", tostring(cf.g), tostring(cf.c)))
d = stack[#stack].dados
d.estado.fontes = "gcbp"; d.ao_mudar_fontes("gcbp", 1)
cf = stack[#stack].dados.contagem_fontes or {}
confere(cf.b == 1 and cf.p == 6, string.format("gcbp: bolsas=%s, tipos de comida no personagem=%s (carne, gravetos, sementes, asa, gelo, mel)", tostring(cf.b), tostring(cf.p)))
d = stack[#stack].dados
d.estado.fontes = "gcp"; d.ao_mudar_fontes("gcp", 1)

print("== Destaque no mundo")
d = stack[#stack].dados
local lm = d.locais and d.locais.meat or {}
local onde = {}
for _, l in ipairs(lm) do onde[#onde + 1] = l.cp .. "@" .. l.x .. "," .. l.z end
table.sort(onde)
confere(table.concat(onde, " ") == "_personagem@0,0 chester@3,4 icebox@10,20", "servidor diz onde está a carne: " .. table.concat(onde, " "))
confere(#d.locais.seeds == 1 and d.locais.seeds[1].cp == "_personagem", "item só do personagem: só 'Personagem' no Guardado em")
local tarefa_fn, cancelada
local todos = { fridge, chester, chester_comum, arvore }
G.TheSim = { FindEntities = function(_, x, y, z, r)
    local achou = {}
    for _, e in ipairs(todos) do
        if (e.pos.x - x) ^ 2 + (e.pos.z - z) ^ 2 <= r * r then achou[#achou + 1] = e end
    end
    return achou
end }
player.DoPeriodicTask = function(_, periodo, fn) tarefa_fn = fn; cancelada = false
    return { Cancel = function() cancelada = true end } end
d.ao_destacar({ "meat" })
tarefa_fn()
confere((fridge.cor or 0) > 0 and (chester.cor or 0) > 0, "mouse na carne: geladeira e Chester brilham")
confere(chester_comum.cor == nil, "Chester comum (sem carne) não brilha")
d.ao_destacar(nil)
confere(cancelada and fridge.cor == 0 and chester.cor == 0, "mouse saiu: brilho apagado e animação parada")

print("== Disponível: combinações de um prato")
d = stack[#stack].dados
d.estado.fontes = "gcp"; d.ao_mudar_fontes("gcp", 2)
local disp = stack[#stack].dados.abas[2]
local alvo
for _, e in ipairs(disp.itens) do if e.grupo == "panela" then alvo = e; break end end
confere(alvo ~= nil and alvo.qtd:match("^[x~]%d+$") and tonumber(alvo.qtd:sub(2)) > 0,
    "linha do prato mostra quantas panelas dá para fazer (" .. tostring(alvo and alvo.prefab) .. ": " .. tostring(alvo and alvo.qtd) .. ")")
-- o mel é o limite: só 3 (no personagem), e o presunto com mel pede mel pelo nome
local presunto
for _, e in ipairs(disp.itens) do if e.prefab == "honeyham" then presunto = e end end
local np = presunto and tonumber(presunto.qtd:sub(2))
confere(presunto == nil or (np >= 1 and np <= 3), "presunto com mel: no máximo 3 panelas (3 méis): " .. tostring(presunto and presunto.qtd))
-- total de panelas nunca passa do que os itens permitem (4 itens por panela)
local itens_panela = 0
for _, e in ipairs(stack[#stack].dados.abas[1].itens) do
    local n = tonumber(((e.qtd or ""):gsub("x", "")))
    if n then itens_panela = itens_panela + n end
end
for _, e in ipairs(disp.itens) do
    if e.grupo == "panela" then
        assert(tonumber(e.qtd:sub(2)) * 4 <= itens_panela, e.prefab .. " " .. e.qtd .. " passa do estoque")
    end
end
combos_recebidos = nil
stack[#stack].dados.ao_pedir_combos(alvo.prefab)
local cr = combos_recebidos
confere(cr and cr.prato == alvo.prefab and #cr.lista + cr.resto >= 1,
    string.format("servidor devolve as combinações (%d enviadas + %d restantes = %s)", cr and #cr.lista or -1, cr and cr.resto or -1, alvo.qtd))
local ordenado = true
for i = 2, #(cr and cr.lista or {}) do if cr.lista[i].chance > cr.lista[i - 1].chance then ordenado = false end end
confere(ordenado, "da garantida para a menos provável")
local n_ing = 0
for _, ic in ipairs(cr.lista[1].icones) do n_ing = n_ing + ic.n end
confere(n_ing == 4, "cada combinação tem 4 ingredientes")

print("== Bolsa Térmica equipada (é bolsa no mundo E mochila do personagem)")
local bolsa_eq = bolsa({ item("fish", 5, FOODTYPE.MEAT) })
bolsa_eq.components.container.inst = bolsa_eq        -- como no jogo: componente aponta para a entidade
G.Ents[#G.Ents + 1] = bolsa_eq
local mochila_antiga = mochila
player.components.inventory.GetOverflowContainer = function() return bolsa_eq.components.container end
d = stack[#stack].dados
d.estado.fontes = "gcbp"; d.ao_mudar_fontes("gcbp", 1)
t = itens_da_janela()
confere(t.fish == 5, "peixe da bolsa equipada contado uma vez só (" .. tostring(t.fish) .. ")")

print(falhas == 0 and "TUDO OK" or (falhas .. " FALHA(S)"))
if falhas > 0 then error(falhas .. " teste(s) falharam", 0) end
