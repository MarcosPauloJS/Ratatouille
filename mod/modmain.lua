local G = GLOBAL
-- O ambiente do modmain só traz pairs, ipairs, print, math, table, type,
-- string, tostring, require e Class. O resto do Lua vem de GLOBAL.
local tonumber = G.tonumber

-- Ícones próprios das categorias (selo redondo: "qualquer carne", "meio legume"...),
-- gerados por ferramentas/gerar_icones.py
Assets = {
    G.Asset("ATLAS", "images/geladeira_categorias.xml"),
    G.Asset("IMAGE", "images/geladeira_categorias.tex"),
}
-- Caminho RELATIVO, igual ao do Asset: o jogo resolve os dois do mesmo jeito e acha a
-- textura carregada. (Com MODROOT na frente ele resolve para outro texto e não acha:
-- "Invalid resource handle for atlas ... did you remember to load the asset?")
local ATLAS_CATEGORIAS = "images/geladeira_categorias.xml"

local KEY              = G[GetModConfigData("key")] or G.KEY_L
local KEY_RECEITAS     = G[GetModConfigData("key_receitas")] or G.KEY_K
local RANGE            = GetModConfigData("range") or 0
local INCLUDE_SALTBOX  = GetModConfigData("include_saltbox")
local MOSTRAR_EM       = GetModConfigData("display") or "janela"

local NAMESPACE     = "ratatouille"
local MAX_ITENS     = 200  -- limite de linhas por aba (o texto inteiro vai numa RPC)
local MAX_CHAT      = 20   -- no chat, mostra menos por aba para não lotar
local MAX_TIPOS     = 24   -- panela: no máximo 24 tipos de ingrediente (os mais abundantes)

---------------------------------------------------------------------------
-- Desempenho: o trabalho pesado (varrer o mundo, testar combinações da panela)
-- roda numa thread e PAUSA quando gastou ~3 ms no frame. PC rápido termina em
-- poucos frames; PC fraco espalha por mais frames em vez de engasgar o jogo.
---------------------------------------------------------------------------
local ORCAMENTO_FRAME = 0.003                       -- segundos de CPU por frame
local relogio = G.os and G.os.clock                 -- o profiler do jogo usa os.clock()
local inicio_do_frame = 0
local passos = 0

local function ComecarFrame()
    inicio_do_frame = relogio and relogio() or 0
    passos = 0
end

-- Chamar dentro dos laços pesados. Só olha o relógio a cada 16 passos (é barato).
local function TalvezPausar()
    passos = passos + 1
    if passos % 16 ~= 0 then return end
    if relogio then
        if relogio() - inicio_do_frame < ORCAMENTO_FRAME then return end
    elseif passos < 160 then
        return                                      -- sem relógio: pausa a cada 160 passos
    end
    G.Yield()
    ComecarFrame()
end

-- Abas na ordem em que aparecem (Itens, Disponível; Todas é montada no cliente)
-- a tecla L abre "itens" e a K abre "disponivel"
local ABA_DA_TECLA = { listar = 1, receitas = 2 }   -- 2 = Disponível

---------------------------------------------------------------------------
-- FORMATO DA MENSAGEM servidor -> cliente (uma linha por registro, campos com TAB)
--   @ \t aba_inicial
--   # \t id \t titulo \t resumo \t vazio \t rodape \t colunas \t stats \t layout   (começa uma aba)
--   p|r \t prefab_ou_receita \t nome \t qtd \t detalhe \t vida \t fome \t sani \t icones \t extra
--   \t grupo  (panela | fogueira | varal: usado pelos checkboxes)
--   icones = "meat:2;honey:1" (ingredientes desenhados como ícone pequeno; :0 = sem número)
--   L \t prefab \t icebox@12.0,-30.5;chester@1.0,2.0   (onde o item está: recipiente@x,z)
--   F \t g=4;c=1;p=5   (contagem por fonte marcada: recipientes achados; p = tipos de comida)
---------------------------------------------------------------------------
local SEP = "\t"

local function Limpa(s) return (tostring(s or ""):gsub("[\t\n]", " ")) end

local function Empacotar(d)
    local linhas = { "@" .. SEP .. d.abrir }
    for _, aba in ipairs(d.abas) do
        linhas[#linhas + 1] = table.concat({ "#", aba.id, Limpa(aba.titulo), Limpa(aba.resumo),
            Limpa(aba.vazio), Limpa(aba.rodape), tostring(aba.colunas or 1), aba.stats and "1" or "",
            aba.layout or "" }, SEP)
        for i = 1, math.min(#aba.itens, MAX_ITENS) do
            local e = aba.itens[i]
            linhas[#linhas + 1] = table.concat({ e.receita and "r" or "p", e.receita or e.prefab,
                Limpa(e.nome), Limpa(e.qtd), Limpa(e.detalhe), Limpa(e.vida), Limpa(e.fome), Limpa(e.sani),
                Limpa(e.icones), Limpa(e.extra), Limpa(e.grupo) }, SEP)
        end
    end
    -- Quantos de cada fonte (aparece ao lado dos checkboxes da aba Itens)
    if d.contagem_fontes then
        local partes = {}
        for letra, n in pairs(d.contagem_fontes) do partes[#partes + 1] = letra .. "=" .. n end
        linhas[#linhas + 1] = "F" .. SEP .. table.concat(partes, ";")
    end
    -- Onde está cada item (para destacar a geladeira no mundo ao passar o mouse)
    for prefab, lista in pairs(d.locais or {}) do
        local partes = {}
        for _, l in ipairs(lista) do partes[#partes + 1] = string.format("%s@%.1f,%.1f", l.cp, l.x, l.z) end
        linhas[#linhas + 1] = table.concat({ "L", prefab, table.concat(partes, ";") }, SEP)
    end
    return table.concat(linhas, "\n")
end

local function Campos(linha)
    local t = {}
    for campo in string.gmatch(linha .. SEP, "(.-)" .. SEP) do t[#t + 1] = campo end
    return t
end

local function Vazio(s) if s == "" then return nil end return s end

-- "meat:2;honey:1" -> { {prefab="meat", n=2}, {prefab="honey", n=1} }
local function LerIcones(s)
    if s == nil or s == "" then return nil end
    local t = {}
    for prefab, n in string.gmatch(s, "([^:;]+):(%d+)") do t[#t + 1] = { prefab = prefab, n = tonumber(n) } end
    return t
end

local function Desempacotar(texto)
    local d, aba = { abrir = 1, abas = {}, locais = {} }, nil
    for linha in string.gmatch(texto, "[^\n]+") do
        local c = Campos(linha)
        if c[1] == "F" then
            d.contagem_fontes = {}
            for letra, n in string.gmatch(c[2] or "", "(%a)=(%d+)") do d.contagem_fontes[letra] = tonumber(n) end
        elseif c[1] == "L" then
            local lista = {}
            for cp, x, z in string.gmatch(c[3] or "", "([^@;]+)@(%-?[%d%.]+),(%-?[%d%.]+)") do
                lista[#lista + 1] = { cp = cp, x = tonumber(x), z = tonumber(z) }
            end
            d.locais[c[2]] = lista
        elseif c[1] == "@" then
            d.abrir = tonumber(c[2]) or 1
        elseif c[1] == "#" then
            aba = { id = c[2], titulo = c[3], resumo = c[4], vazio = Vazio(c[5]), rodape = Vazio(c[6]),
                    colunas = tonumber(c[7]) or 1, stats = c[8] == "1", layout = Vazio(c[9]), itens = {} }
            d.abas[#d.abas + 1] = aba
        elseif aba ~= nil then
            aba.itens[#aba.itens + 1] = {
                receita = c[1] == "r" and c[2] or nil,
                prefab  = c[1] == "p" and c[2] or nil,
                nome = c[3], qtd = Vazio(c[4]), detalhe = Vazio(c[5]),
                vida = Vazio(c[6]), fome = Vazio(c[7]), sani = Vazio(c[8]),
                icones = LerIcones(c[9]), extra = Vazio(c[10]), grupo = Vazio(c[11]),
            }
        end
    end
    return d
end

---------------------------------------------------------------------------
-- CLIENTE: aba "Todas" (todos os pratos da panela), montada no próprio cliente.
-- scripts/geladeira_receitas.lua é gerado por receitas/gerar_receitas_mod.py:
-- para cada prato, um exemplo de combinação e os ingredientes que servem nele.
---------------------------------------------------------------------------
local aba_todas = nil   -- monta uma vez e reaproveita

-- Checkboxes das abas Disponível e Todas (o estado é o mesmo nas duas)
local FILTROS_RECEITA = { { id = "panela", rotulo = "Panela" }, { id = "fogueira", rotulo = "Fogueira" },
                          { id = "varal", rotulo = "Varal" } }
-- A aba Todas tem também "Warly": os 11 pratos que só saem no caldeirão dele
local FILTROS_TODAS = { { id = "panela", rotulo = "Panela" }, { id = "fogueira", rotulo = "Fogueira" },
                        { id = "varal", rotulo = "Varal" }, { id = "warly", rotulo = "Warly" } }

local function NomeDoItem(prefab)
    return G.STRINGS.NAMES[string.upper(prefab)] or prefab
end

local function NumTodas(v, com_sinal)
    if v == nil then return nil end
    local r = math.floor(v * 10 + 0.5) / 10
    local s = (r == math.floor(r)) and string.format("%d", r) or string.format("%.1f", r)
    if com_sinal and r > 0 then s = "+" .. s end
    return s
end

-- Categorias de ingrediente (scripts/geladeira_categorias.lua, gerado junto com as receitas)
local categorias = nil
local function Categorias()
    if categorias == nil then
        categorias = { lista = require "geladeira_categorias", por_id = {} }
        for _, c in ipairs(categorias.lista) do categorias.por_id[c.id] = c end
    end
    return categorias
end

local function TexDaCategoria(id) return "cat_" .. id .. ".tex" end

local function AbaTodas()
    if aba_todas ~= nil then return aba_todas end
    local dados = require "geladeira_receitas"
    local CAT = Categorias().por_id
    local receitas = require("cooking").recipes.portablecookpot
    local aba = { id = "todas", titulo = "Todas", colunas = 1, stats = true, itens = {},
                  rodape = "Busque um ingrediente. Selo redondo = qualquer item da categoria (veja a Legenda).",
                  vazio = "Nenhuma receita com esses filtros.",
                  busca = true, filtros = FILTROS_TODAS }
    for nome, d in pairs(dados) do
        local r = receitas[nome]
        if r ~= nil then
            -- d.cat[p] = "legume", "meio_legume"...: qualquer item dessa categoria serve no lugar de p.
            -- Itens da mesma categoria viram uma entrada só (cebola + berinjela = "2x Legume").
            local cat = {}
            for p, id in pairs(d.cat or {}) do if CAT[id] then cat[p] = id end end
            local conta, ordem, rep = {}, {}, {}
            for _, p in ipairs(d.exemplo) do
                local k = cat[p] or p
                if conta[k] == nil then ordem[#ordem + 1] = k; rep[k] = p end
                conta[k] = (conta[k] or 0) + 1
            end
            local partes = {}
            for _, k in ipairs(ordem) do
                partes[#partes + 1] = conta[k] .. "x " .. (CAT[k] and CAT[k].nome or NomeDoItem(k))
            end
            local busca = {}
            for i, p in ipairs(d.usa) do busca[i] = NomeDoItem(p) end
            for _, id in pairs(cat) do busca[#busca + 1] = CAT[id].nome end
            local icones = {}
            for _, k in ipairs(ordem) do
                local c = CAT[k]
                -- só o selo (sem o nome escrito): o nome fica na Legenda e na busca
                icones[#icones + 1] = c and { prefab = rep[k], n = conta[k], categoria = c.nome,
                                              atlas = ATLAS_CATEGORIAS, tex = TexDaCategoria(k) }
                                        or { prefab = k, n = conta[k] }
            end
            aba.itens[#aba.itens + 1] = {
                prefab = nome, nome = NomeDoItem(nome), icones = icones,
                detalhe = "Ex.: " .. table.concat(partes, ", "),
                qtd = d.warly and "Warly" or nil,
                vida = NumTodas(r.health, true), fome = NumTodas(r.hunger), sani = NumTodas(r.sanity, true),
                busca = busca, _ordem = r.hunger or 0, grupo = d.warly and "warly" or "panela",
            }
        end
    end

    -- Fogueira e varal (scripts/geladeira_simples.lua, gerado por receitas/gerar_simples_mod.py).
    -- Vários crus podem dar o MESMO produto (todas as sementes -> Sementes tostadas,
    -- tromba de verão/inverno -> Bife de tromba): vira UMA linha por produto+método,
    -- com o ícone de cada cru (até 4; o resto aparece como "+N").
    local por_produto, ordem_simples = {}, {}
    for _, r in ipairs(require "geladeira_simples") do
        local chave = r.metodo .. "|" .. r.produto
        local g = por_produto[chave]
        if g == nil then
            g = { r = r, crus = {} }
            por_produto[chave] = g
            ordem_simples[#ordem_simples + 1] = chave
        end
        g.crus[#g.crus + 1] = r.cru
    end
    for _, chave in ipairs(ordem_simples) do
        local g = por_produto[chave]
        local r = g.r
        local onde = r.metodo == "varal"
            and ("no varal" .. (r.dias and string.format(" (%s dia%s)", NumTodas(r.dias), r.dias == 1 and "" or "s") or ""))
            or "na fogueira"
        local icones, nomes = {}, {}
        for i, cru in ipairs(g.crus) do
            nomes[i] = NomeDoItem(cru)
            if i <= 4 then icones[i] = { prefab = cru, n = 0 } end
        end
        local mais = #g.crus > 4 and string.format("+%d ", #g.crus - 4) or ""
        aba.itens[#aba.itens + 1] = {
            prefab = r.produto, nome = NomeDoItem(r.produto), grupo = r.metodo,
            icones = icones, extra = mais .. onde,
            detalhe = table.concat(nomes, " ou ") .. " " .. onde,            -- texto da busca
            busca = nomes,
            vida = NumTodas(r.vida, true), fome = NumTodas(r.fome), sani = NumTodas(r.sani, true),
            _ordem = r.fome or 0,
        }
    end
    table.sort(aba.itens, function(a, b)
        if a._ordem ~= b._ordem then return a._ordem > b._ordem end
        return a.nome < b.nome
    end)
    aba.resumo = string.format("%d receita(s)", #aba.itens)
    aba_todas = aba
    return aba
end

-- Aba Legenda: explica os selos de categoria usados nos exemplos da aba Todas
local aba_legenda = nil
local function AbaLegenda()
    if aba_legenda ~= nil then return aba_legenda end
    local aba = { id = "legenda", titulo = "Legenda", colunas = 1, itens = {}, sem_ordem = true,
                  resumo = "Como ler os ingredientes",
                  rodape = "Clique numa categoria para ver todos os itens dela." }
    for _, c in ipairs(Categorias().lista) do
        local nomes, filhos = {}, {}
        for i = 1, math.min(#c.itens, 6) do nomes[i] = NomeDoItem(c.itens[i]) end
        -- clique na categoria abre a lista completa, com o ícone de cada item do jogo
        for i, p in ipairs(c.itens) do filhos[i] = { prefab = p, nome = NomeDoItem(p) } end
        aba.itens[#aba.itens + 1] = {
            chave = "cat:" .. c.id, filhos = filhos,
            prefab = c.itens[1], atlas = ATLAS_CATEGORIAS, tex = TexDaCategoria(c.id),
            nome = c.nome .. (c.valor < 1 and " (vale metade)" or ""),
            detalhe = "Ex.: " .. table.concat(nomes, ", ") .. (#c.itens > 6 and "..." or ""),
        }
    end
    -- Item específico: os itens que aparecem nos exemplos SEM selo (não valem pela categoria)
    local vistos, especificos = {}, {}
    for _, d in pairs(require "geladeira_receitas") do
        for _, p in ipairs(d.exemplo) do
            if not (d.cat and d.cat[p]) and not vistos[p] then
                vistos[p] = true
                especificos[#especificos + 1] = { prefab = p, nome = NomeDoItem(p) }
            end
        end
    end
    table.sort(especificos, function(a, b) return a.nome < b.nome end)
    aba.itens[#aba.itens + 1] = {
        chave = "cat:especifico", filhos = especificos,
        prefab = "mandrake", atlas = ATLAS_CATEGORIAS, tex = TexDaCategoria("especifico"),
        nome = "Item específico",
        detalhe = "Aparece com o ícone do próprio item: só ele serve, nenhum outro",
    }
    aba_legenda = aba
    return aba
end

---------------------------------------------------------------------------
-- CLIENTE: mostra o resultado (painel lateral ou chat)
---------------------------------------------------------------------------
local GeladeiraPainel = require "widgets/geladeira_painel"

local function TelaAtiva()
    return G.TheFrontEnd:GetActiveScreen()
end

local function MostrarNoChat(d)
    local function say(s) G.ChatHistory:SendCommandResponse(s) end
    for _, aba in ipairs(d.abas) do
        say(string.format("[%s] %s", aba.titulo, aba.resumo))
        local linha = {}
        for i = 1, math.min(#aba.itens, MAX_CHAT) do
            local e = aba.itens[i]
            local txt = e.qtd and (e.nome .. " " .. e.qtd) or e.nome
            if e.vida or e.fome or e.sani then
                txt = txt .. string.format(" (V%s F%s S%s)", e.vida or "-", e.fome or "-", e.sani or "-")
            end
            linha[#linha + 1] = txt
            if #linha == 4 then say("  " .. table.concat(linha, ", ")); linha = {} end
        end
        if #linha > 0 then say("  " .. table.concat(linha, ", ")) end
        if #aba.itens > MAX_CHAT then say(string.format("  ... e mais %d.", #aba.itens - MAX_CHAT)) end
    end
end

-- O painel lateral vive no HUD do jogador (criado em AddClassPostConstruct mais abaixo)
local function Painel()
    local hud = G.ThePlayer ~= nil and G.ThePlayer.HUD or nil
    return hud ~= nil and hud.controls ~= nil and hud.controls.geladeira_painel or nil
end

local function MostrarJanela(d)
    local painel = Painel()
    if painel == nil then return MostrarNoChat(d) end
    painel:MostrarDados(d)
end

---------------------------------------------------------------------------
-- CLIENTE: destacar no mundo as geladeiras que têm o item sob o mouse.
-- O servidor manda recipiente@x,z de cada item; aqui achamos a entidade no ponto e
-- fazemos ela brilhar em dourado, pulsando. Usa o canal "add colour" do AnimState,
-- separado do brilho de hover do jogo (componente highlight), para não brigar com ele.
-- Recipientes longe demais podem não existir no cliente: esses ficam sem destaque.
---------------------------------------------------------------------------
local destaque = { entidades = {}, tarefa = nil }

local function LimparDestaque()
    if destaque.tarefa ~= nil then
        destaque.tarefa:Cancel()
        destaque.tarefa = nil
    end
    for _, e in ipairs(destaque.entidades) do
        if e:IsValid() and e.AnimState ~= nil then e.AnimState:SetAddColour(0, 0, 0, 0) end
    end
    destaque.entidades = {}
end

local function Destacar(locais, prefabs)
    LimparDestaque()
    if locais == nil or prefabs == nil or G.ThePlayer == nil then return end
    local vistos = {}
    for _, prefab in ipairs(prefabs) do
        for _, l in ipairs(locais[prefab] or {}) do
            if l.cp:sub(1, 1) ~= "_" then           -- "_personagem": nada a destacar no mundo
                for _, e in ipairs(G.TheSim:FindEntities(l.x, 0, l.z, 2.5, nil, { "INLIMBO" })) do
                    if e.prefab == l.cp and not vistos[e] and e.AnimState ~= nil then
                        vistos[e] = true
                        destaque.entidades[#destaque.entidades + 1] = e
                    end
                end
            end
        end
    end
    if #destaque.entidades == 0 then return end
    local t = 0
    destaque.tarefa = G.ThePlayer:DoPeriodicTask(G.FRAMES, function()
        t = t + G.FRAMES
        local v = 0.22 + 0.12 * math.sin(t * 6)          -- pulsa ~1 vez por segundo
        for _, e in ipairs(destaque.entidades) do
            if e:IsValid() and e.AnimState ~= nil then e.AnimState:SetAddColour(v, v * 0.75, 0, 0) end
        end
    end)
end

-- Estado do cliente que sobrevive quando a janela é recriada
-- fontes: letras combinadas; g = geladeiras (e Caixa de Sal), c = Chester,
-- b = Bolsa Térmica, p = personagem (mãos + cursor + mochila). Chester vem ligado.
local ESTADO = { fontes = "gc", ordem = nil, filtro = "" }

-- Pede tudo ao servidor (as fontes vão junto; a janela abre na aba indicada)
local function Pedir(aba)
    SendModRPCToServer(GetModRPC(NAMESPACE, "pedir"), ESTADO.fontes, aba or 1)
end

local function Mostrar(texto)
    local d = Desempacotar(texto)
    if MOSTRAR_EM == "chat" then
        MostrarNoChat(d)                     -- a aba Todas é grande demais para o chat
    else
        for _, aba in ipairs(d.abas) do
            if aba.id == "disponivel" then aba.filtros = FILTROS_RECEITA end
        end
        d.abas[#d.abas + 1] = AbaTodas()
        d.abas[#d.abas + 1] = AbaLegenda()
        -- Checkbox Warly da aba Todas: liga se o personagem é o Warly, desliga se não é
        ESTADO.grupos_off = ESTADO.grupos_off or {}
        local eh_warly = G.ThePlayer ~= nil and G.ThePlayer.prefab == "warly"
        ESTADO.grupos_off.warly = (not eh_warly) or nil
        d.estado = ESTADO
        d.ao_mudar_fontes = function(_, aba) Pedir(aba) end
        d.ao_destacar = function(prefabs) Destacar(d.locais, prefabs) end
        d.ao_pedir_combos = function(prato) SendModRPCToServer(GetModRPC(NAMESPACE, "combos"), prato) end
        MostrarJanela(d)
    end
end

AddClientModRPCHandler(NAMESPACE, "resultado", Mostrar)

-- Chegaram as combinações de um prato: lê e entrega ao conteúdo do painel
local function ReceberCombos(texto)
    local prato, resto, lista = nil, 0, {}
    for linha in string.gmatch(texto, "[^\n]+") do
        local c = Campos(linha)
        if prato == nil then
            prato, resto = c[1], tonumber(c[2]) or 0
        else
            local rivais = {}
            for id in string.gmatch(c[3] or "", "[^,]+") do rivais[#rivais + 1] = id end
            lista[#lista + 1] = { icones = LerIcones(c[1]), chance = tonumber(c[2]) or 0, rivais = rivais }
        end
    end
    local painel = Painel()
    if prato and painel ~= nil and painel.conteudo ~= nil then
        painel.conteudo:ReceberCombos(prato, lista, resto)
    end
end
AddClientModRPCHandler(NAMESPACE, "combos", ReceberCombos)

---------------------------------------------------------------------------
-- SERVIDOR: varre as geladeiras e soma os itens
---------------------------------------------------------------------------
-- De que fonte é este recipiente? "g" geladeira/Caixa de Sal, "c" Chester,
-- "b" Bolsa Térmica, ou nil (não conta)
local function TipoDoRecipiente(inst)
    if inst.components.container == nil then return nil end
    -- Chester em qualquer forma (comum, de gelo, de sombra) tem a tag "chester"
    if inst:HasTag("chester") then return "c" end
    if inst:HasTag("fridge") then
        -- Geladeira construída tem tag "structure"; a Bolsa Térmica é o prefab "icepack".
        -- (Outras coisas com tag "fridge", como a árvore viva de Halloween, não contam.)
        if inst:HasTag("structure") then return "g" end
        if inst.prefab == "icepack" then return "b" end
        return nil
    end
    if INCLUDE_SALTBOX and inst:HasTag("saltbox") then return "g" end
    return nil
end

-- Item do personagem entra só se servir de comida: ingrediente de panela,
-- comida de gente, ou algo que se assa na fogueira / seca no varal.
-- Cuidado: pedra, pederneira e ouro TÊM componente edible (foodtype ELEMENTAL,
-- comida da lagosta de pedra); madeira é WOOD (Woodie castor), engrenagem é GEARS
-- (WX-78). Por isso o comestível só vale se o foodtype for da dieta humana
-- padrão do jogo (FOODGROUP.OMNI: carne, vegetal, inseto, semente, genérico, doce).
local DIETA_HUMANA = nil
local function ComidaDeGente(edible)
    if DIETA_HUMANA == nil then
        DIETA_HUMANA = {}
        for _, t in ipairs(G.FOODGROUP.OMNI.types) do DIETA_HUMANA[t] = true end
    end
    return DIETA_HUMANA[edible.foodtype] == true
end

local function ServeDeComida(item)
    local c = item.components
    return require("cooking").IsCookingIngredient(item.prefab)
        or (c.edible ~= nil and ComidaDeGente(c.edible))
        or c.cookable ~= nil or c.dryable ~= nil
end

-- estoque[prefab] = quantidade total (HashMap); amostra[prefab] = um item de verdade
-- fontes: "g" geladeiras, "p" personagem (inventário/mãos, item no cursor e mochila equipada)
local function CollectStock(player, fontes)
    local estoque, names, amostra = {}, {}, {}
    local boxes = 0
    local locais = {}             -- locais[prefab] = { {cp, x, z}, ... } (um por recipiente)
    local tipos_personagem = {}   -- prefabs vindos do personagem (para a contagem do checkbox)
    local function soma(item, so_comida, recipiente)
        if item == nil then return end
        if so_comida and not ServeDeComida(item) then return end
        local lista = locais[item.prefab]
        if lista == nil then lista = {}; locais[item.prefab] = lista end
        if recipiente == nil then
            -- veio do personagem: entra no "Guardado em" (não tem o que destacar no mundo)
            tipos_personagem[item.prefab] = true
            if lista._personagem == nil then
                lista._personagem = true
                lista[#lista + 1] = { cp = "_personagem", x = 0, z = 0 }
            end
        elseif lista[recipiente] == nil then        -- o mesmo recipiente só uma vez
            local x, _, z = recipiente.Transform:GetWorldPosition()
            lista[recipiente] = true
            lista[#lista + 1] = { cp = recipiente.prefab, x = x, z = z }
        end
        local count = item.components.stackable and item.components.stackable:StackSize() or 1
        estoque[item.prefab] = (estoque[item.prefab] or 0) + count
        names[item.prefab] = names[item.prefab] or item:GetBasicDisplayName()
        amostra[item.prefab] = amostra[item.prefab] or item
    end

    local achados = { g = 0, c = 0, b = 0 }    -- quantos recipientes de cada fonte
    local ja_contado = {}                      -- evita contar a mesma Bolsa Térmica duas vezes
    for _, inst in pairs(G.Ents) do
        TalvezPausar()
        local tipo = inst:IsValid() and TipoDoRecipiente(inst) or nil
        if tipo ~= nil and fontes:find(tipo, 1, true)
            and (RANGE <= 0 or inst:IsNear(player, RANGE)) then
            achados[tipo] = achados[tipo] + 1
            ja_contado[inst] = true
            -- Geladeira e Caixa de Sal só aceitam comida; Chester e Bolsa Térmica
            -- guardam qualquer coisa, então passam pelo filtro de comida
            local filtrar = tipo ~= "g"
            for _, item in pairs(inst.components.container.slots) do soma(item, filtrar, inst) end
        end
    end
    boxes = achados.g

    local personagem = fontes:find("p", 1, true) ~= nil
    local inv = player.components.inventory
    if personagem and inv ~= nil then
        -- do personagem, só o que serve de comida (ver ServeDeComida)
        for _, item in pairs(inv.itemslots) do soma(item, true) end
        soma(inv:GetActiveItem(), true)                  -- item segurado no cursor
        local mochila = inv:GetOverflowContainer()       -- mochila equipada (se houver)
        if mochila ~= nil and not ja_contado[mochila.inst] then   -- Bolsa Térmica já somada acima
            for _, item in pairs(mochila.slots) do soma(item, true) end
        end
    end
    -- tira as marcas internas (chaves = recipiente) e deixa só a lista
    for prefab, lista in pairs(locais) do
        local limpa = {}
        for i = 1, #lista do limpa[i] = lista[i] end
        locais[prefab] = limpa
    end
    local n_personagem = 0
    for _ in pairs(tipos_personagem) do n_personagem = n_personagem + 1 end
    -- só manda a contagem das fontes que foram procuradas (desmarcada = sem número)
    local contagem = {}
    for _, letra in ipairs({ "g", "c", "b" }) do
        if fontes:find(letra, 1, true) then contagem[letra] = achados[letra] end
    end
    if personagem then contagem.p = n_personagem end
    return { estoque = estoque, names = names, amostra = amostra, boxes = boxes, locais = locais,
             contagem_fontes = contagem,
             achados = achados, fontes = fontes, personagem = personagem,
             warly = player.prefab == "warly" }
end

-- "2 geladeira(s) + personagem"
local function DescreveFontes(s)
    local partes = {}
    if s.fontes:find("g", 1, true) then partes[#partes + 1] = string.format("%d geladeira(s)", s.achados.g) end
    if s.fontes:find("c", 1, true) then
        partes[#partes + 1] = s.achados.c > 0 and "Chester" or "Chester (não achado)"
    end
    if s.fontes:find("b", 1, true) then
        partes[#partes + 1] = s.achados.b > 0 and string.format("%d Bolsa(s) Térmica(s)", s.achados.b)
            or "Bolsa Térmica (não achada)"
    end
    if s.personagem then partes[#partes + 1] = "personagem" end
    return table.concat(partes, " + ")
end

local function NomeDoPrefab(prefab)
    return G.STRINGS.NAMES[string.upper(prefab)] or prefab
end

-- Número curto: inteiro quando dá, senão 1 casa; "+" opcional para vida/sanidade
local function Num(v, com_sinal)
    if v == nil then return nil end
    local r = math.floor(v * 10 + 0.5) / 10
    local s = (r == math.floor(r)) and string.format("%d", r) or string.format("%.1f", r)
    if com_sinal and r > 0 then s = "+" .. s end
    return s
end

-- Copia vida/fome/sanidade (valores base, sem estragar e sem dieta de personagem) para a entrada
local function ComAtributos(e, vida, fome, sani)
    e.vida, e.fome, e.sani = Num(vida, true), Num(fome), Num(sani, true)
    return e
end

local function AtributosDoItem(item)
    local ed = item and item.components.edible
    if ed == nil then return nil end
    return ed.healthvalue, ed.hungervalue, ed.sanityvalue
end

-- Atributos de um prefab que não temos em mãos (ex.: produto da fogueira):
-- cria um exemplar, lê o edible e apaga. Guarda em cache porque não mudam.
local cache_atributos = {}
local function AtributosDoPrefab(prefab)
    local c = cache_atributos[prefab]
    if c == nil then
        c = {}
        local inst = G.SpawnPrefab(prefab)
        if inst ~= nil then
            c = { AtributosDoItem(inst) }
            inst:Remove()
        end
        cache_atributos[prefab] = c
    end
    return c[1], c[2], c[3]
end

---------------------------------------------------------------------------
-- Aba 1: itens
---------------------------------------------------------------------------
local function AbaItens(s)
    local aba = { id = "itens", titulo = "Itens", colunas = 1, stats = true, itens = {} }   -- lista, como Disponível/Todas
    for prefab, count in pairs(s.estoque) do
        aba.itens[#aba.itens + 1] = ComAtributos(
            { prefab = prefab, nome = s.names[prefab] or prefab, n = count, qtd = "x" .. count },
            AtributosDoItem(s.amostra[prefab]))
    end
    table.sort(aba.itens, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.nome < b.nome
    end)
    aba.resumo = string.format("%s: %d tipo(s)", DescreveFontes(s), #aba.itens)
    aba.vazio = "Todas as geladeiras estão vazias."
    return aba
end

---------------------------------------------------------------------------
-- Aba 2: panela (regras de verdade do cooking.lua, todas as combinações de 4)
---------------------------------------------------------------------------
-- Mesmos apelidos de cooking.lua (a tabela de lá é local)
local APELIDOS = { cookedsmallmeat = "smallmeat_cooked", cookedmonstermeat = "monstermeat_cooked", cookedmeat = "meat_cooked" }

local function AbaPanela(s)
    local cooking = require("cooking")
    -- Warly cozinha no Caldeirão Portátil: regras "portablecookpot" (comuns + exclusivas dele)
    local cozinha = s.warly and "portablecookpot" or "cookpot"
    local aba = { id = "panela", titulo = "Panela", colunas = 1, stats = true, itens = {},
                  rodape = "Testa toda combinação de 4 itens; vence a receita de maior prioridade.",
                  vazio = "Nenhuma combinação dá um prato além da Gororoba." }

    -- Tipos que vão na panela, dos mais abundantes para os menos
    local tipos = {}
    for prefab in pairs(s.estoque) do
        if cooking.IsCookingIngredient(prefab) then tipos[#tipos + 1] = prefab end
    end
    table.sort(tipos, function(a, b) return s.estoque[a] > s.estoque[b] end)
    local cortados = 0
    if #tipos > MAX_TIPOS then
        cortados = #tipos - MAX_TIPOS
        for i = #tipos, MAX_TIPOS + 1, -1 do tipos[i] = nil end
    end

    local melhor, combo, testadas = {}, {}, 0
    -- todas[prato] = { {k = "meat:1;carrot:3", c = chance, rv = "prato1,prato2"}, ... }
    -- (todas as combinações dos seus itens que podem dar o prato; vira o "expandir" da lista)
    local todas = {}

    -- "meat:1;carrot:3" a partir da combinação atual (os iguais ficam juntos na lista)
    -- (devolve também a lista { {prefab, n}, ... } para a conta de quantas panelas)
    local function Chave()
        local partes, itens, ultimo, n = {}, {}, nil, 0
        for _, p in ipairs(combo) do
            if p == ultimo then n = n + 1
            else
                if ultimo then partes[#partes + 1] = ultimo .. ":" .. n; itens[#itens + 1] = { ultimo, n } end
                ultimo, n = p, 1
            end
        end
        if ultimo then partes[#partes + 1] = ultimo .. ":" .. n; itens[#itens + 1] = { ultimo, n } end
        return table.concat(partes, ";"), itens
    end

    local function Avaliar()
        local names, tags = {}, {}
        for _, prefab in ipairs(combo) do
            local nome = APELIDOS[prefab] or prefab
            names[nome] = (names[nome] or 0) + 1
            for tag, v in pairs(cooking.ingredients[nome].tags) do tags[tag] = (tags[tag] or 0) + v end
        end
        -- Função global do cooking.lua: devolve só as receitas de maior prioridade que passam
        local grupo = G.GetCandidateRecipes(cozinha, { names = names, tags = tags })
        local total = 0
        for _, r in ipairs(grupo) do total = total + (r.weight or 1) end
        local chave, itens = nil, nil
        for _, r in ipairs(grupo) do
            local chance = (r.weight or 1) / total
            if r.name ~= "wetgoop" then
                if chave == nil then chave, itens = Chave() end
                local rv = {}
                for _, o in ipairs(grupo) do if o ~= r then rv[#rv + 1] = o.name end end
                local lista = todas[r.name]
                if lista == nil then lista = {}; todas[r.name] = lista end
                lista[#lista + 1] = { k = chave, c = chance, rv = table.concat(rv, ","), it = itens }
            end
            local m = melhor[r.name]
            if m == nil or chance > m.chance then
                local rivais = {}
                for _, o in ipairs(grupo) do if o ~= r then rivais[#rivais + 1] = NomeDoPrefab(o.name) end end
                local copia = {}
                for i, p in ipairs(combo) do copia[i] = p end
                melhor[r.name] = { chance = chance, combo = copia, rivais = rivais, recipe = r }
            end
        end
        testadas = testadas + 1
        TalvezPausar()                                   -- não trava o servidor
    end

    local function Rec(i, restam)
        if restam == 0 then return Avaliar() end
        if i > #tipos then return end
        local max = math.min(restam, s.estoque[tipos[i]])
        for k = max, 0, -1 do
            for _ = 1, k do combo[#combo + 1] = tipos[i] end
            Rec(i + 1, restam - k)
            for _ = 1, k do combo[#combo] = nil end
        end
    end
    Rec(1, 4)

    -- Quantas panelas desse prato dá para fazer com o estoque? Reparte os itens entre
    -- as panelas: a cada passo usa a combinação que gasta os itens MAIS abundantes
    -- (assim sobra o raro para as próximas) e a repete até acabar algum item dela.
    -- Cada passo esgota pelo menos um tipo de item: poucos passos mesmo com muito estoque.
    -- Só combinações garantidas contam; se o prato não tem nenhuma, usa as de empate
    -- e mostra "~N" (pode sair outro prato).
    local JANELA_PANELAS = 64
    local function QuantasPanelas(lista)
        local usar, garantido = {}, false
        for _, c in ipairs(lista) do if c.c >= 0.999 then garantido = true; break end end
        for _, c in ipairs(lista) do
            if not garantido or c.c >= 0.999 then usar[#usar + 1] = c.it end
        end
        local resta = {}
        for p, n in pairs(s.estoque) do resta[p] = n end
        local total, inicio = 0, 1
        while true do
            local melhor_c, melhor_custo, vezes = nil, math.huge, 0
            -- O estoque só diminui: combinação que não cabe mais é marcada (false) e nunca
            -- mais é olhada. As combinações vêm na ordem da busca, que começa pelos itens
            -- mais abundantes; por isso basta comparar as primeiras JANELA que ainda cabem.
            local vistas = 0
            local idx = inicio
            while idx <= #usar and vistas < JANELA_PANELAS do
                local itens = usar[idx]
                if itens then
                    local custo, cabe = 0, math.huge
                    for _, par in ipairs(itens) do
                        local tem = resta[par[1]] or 0
                        if tem < par[2] then cabe = 0; break end
                        custo = custo + par[2] / tem
                        cabe = math.min(cabe, math.floor(tem / par[2]))
                    end
                    if cabe > 0 then
                        vistas = vistas + 1
                        if custo < melhor_custo then melhor_c, melhor_custo, vezes = itens, custo, cabe end
                    else
                        usar[idx] = false
                        if idx == inicio then inicio = idx + 1 end
                    end
                elseif idx == inicio then
                    inicio = idx + 1
                end
                idx = idx + 1
                TalvezPausar()                           -- pode ter milhares de combinações
            end
            if melhor_c == nil then break end
            for _, par in ipairs(melhor_c) do resta[par[1]] = resta[par[1]] - par[2] * vezes end
            total = total + vezes
            TalvezPausar()
        end
        return total, garantido
    end

    melhor.wetgoop = nil
    for dish, m in pairs(melhor) do
        local conta, ordem = {}, {}
        for _, p in ipairs(m.combo) do
            if conta[p] == nil then ordem[#ordem + 1] = p end
            conta[p] = (conta[p] or 0) + 1
        end
        local partes, icones = {}, {}
        for _, p in ipairs(ordem) do
            partes[#partes + 1] = conta[p] .. "x " .. (s.names[p] or p)
            icones[#icones + 1] = p .. ":" .. conta[p]
        end
        local detalhe = table.concat(partes, ", ")       -- continua indo: é o texto da busca
        local extra = nil
        if cooking.recipes.cookpot[dish] == nil then extra = "só no caldeirão do Warly" end
        if #m.rivais > 0 then
            extra = "empata com " .. table.concat(m.rivais, ", ")
            detalhe = detalhe .. "  (" .. extra .. ")"
        end
        local pct = math.floor(m.chance * 100 + 0.5)
        local r = m.recipe
        aba.itens[#aba.itens + 1] = ComAtributos({
            prefab = dish, nome = NomeDoPrefab(dish), detalhe = detalhe,
            icones = table.concat(icones, ";"), extra = extra, grupo = "panela",
            -- quantas panelas dá para fazer ("~" = só com sorte, empata com outro prato)
            qtd = (function()
                local n, garantido = QuantasPanelas(todas[dish] or {})
                return (garantido and "x" or "~") .. n
            end)(), ordem = r.hunger or 0,
        }, r.health, r.hunger, r.sanity)
    end
    table.sort(aba.itens, function(a, b)
        if a.ordem ~= b.ordem then return a.ordem > b.ordem end
        return a.nome < b.nome
    end)
    aba.resumo = string.format("%d prato(s) possíveis, %d combinações testadas", #aba.itens, testadas)
    aba.combos = todas
    if cortados > 0 then
        aba.resumo = aba.resumo .. string.format(" (%d tipos raros ignorados)", cortados)
    end
    return aba
end

---------------------------------------------------------------------------
-- Aba 3: fogueira e varal (lidos dos próprios itens: cookable / dryable)
---------------------------------------------------------------------------
local function AbaFogueira(s)
    local aba = { id = "fogueira", titulo = "Fogueira", colunas = 1, stats = true, itens = {},
                  vazio = "Nada nas geladeiras vai para a fogueira ou o varal." }
    -- Uma linha por produto+método, mesmo que venha de crus diferentes
    -- (ex.: duas sementes diferentes -> Sementes tostadas): soma as quantidades.
    local grupos, ordem = {}, {}
    local function Junta(produto, metodo, onde, cru, qtd)
        local chave = metodo .. "|" .. produto
        local g = grupos[chave]
        if g == nil then
            g = { produto = produto, metodo = metodo, onde = onde, crus = {}, qtd = 0 }
            grupos[chave] = g
            ordem[#ordem + 1] = chave
        end
        g.crus[#g.crus + 1] = cru
        g.qtd = g.qtd + qtd
    end
    for prefab, qtd in pairs(s.estoque) do
        local item = s.amostra[prefab]
        local cook = item.components.cookable
        if cook ~= nil and type(cook.product) == "string" then
            Junta(cook.product, "fogueira", "na fogueira", prefab, qtd)
        end
        local dry = item.components.dryable
        local produto = dry ~= nil and dry:GetProduct() or nil
        if type(produto) == "string" then
            local tempo = dry:GetDryTime()
            local dias = tempo and (tempo / G.TUNING.TOTAL_DAY_TIME) or nil
            Junta(produto, "varal", "no varal" .. (dias and string.format(" (%s dia%s)", Num(dias), dias == 1 and "" or "s") or ""),
                prefab, qtd)
        end
    end
    for _, chave in ipairs(ordem) do
        local g = grupos[chave]
        table.sort(g.crus)
        local icones, nomes = {}, {}
        for i, cru in ipairs(g.crus) do
            nomes[i] = s.names[cru] or cru
            if i <= 4 then icones[i] = cru .. ":0" end
        end
        local mais = #g.crus > 4 and string.format("+%d ", #g.crus - 4) or ""
        aba.itens[#aba.itens + 1] = ComAtributos({ prefab = g.produto, nome = NomeDoPrefab(g.produto),
            grupo = g.metodo, icones = table.concat(icones, ";"), extra = mais .. g.onde,
            detalhe = table.concat(nomes, " ou ") .. " " .. g.onde, qtd = "x" .. g.qtd },
            AtributosDoPrefab(g.produto))
    end
    table.sort(aba.itens, function(a, b) return a.detalhe < b.detalhe end)
    aba.resumo = string.format("%d item(ns) para assar ou secar", #aba.itens)
    return aba
end

---------------------------------------------------------------------------
-- Aba Disponível: panela + fogueira + varal juntos (checkboxes filtram no cliente)
---------------------------------------------------------------------------
local function AbaDisponivel(s)
    local panela, fogueira = AbaPanela(s), AbaFogueira(s)
    local aba = { id = "disponivel", titulo = "Disponível", colunas = 1, stats = true, itens = {},
                  -- "N prato(s) possíveis, M combinações testadas"
                  rodape = "Panela: o número é quantas panelas dá para fazer. Clique para ver as combinações."
                      .. (s.warly and " (Caldeirão do Warly)" or ""),
                  vazio = "Nada disponível com esses filtros." }
    for _, e in ipairs(panela.itens) do aba.itens[#aba.itens + 1] = e end
    for _, e in ipairs(fogueira.itens) do
        e.ordem = tonumber((tostring(e.fome or ""):gsub("^%+", ""))) or 0
        aba.itens[#aba.itens + 1] = e
    end
    table.sort(aba.itens, function(a, b)
        if a.ordem ~= b.ordem then return a.ordem > b.ordem end
        return a.nome < b.nome
    end)
    aba.resumo = string.format("%d receita(s)", #aba.itens)
    aba.combos = panela.combos
    return aba
end

---------------------------------------------------------------------------
-- RPCs: pedido do cliente -> relatório do servidor -> cliente
---------------------------------------------------------------------------
local ocupado = {}
local combos_do_jogador = {}       -- userid -> combinações por prato do último cálculo
local LIMITE_COMBOS = 120          -- quantas combinações de um prato vão por pedido

local function Responder(player, fontes, aba_inicial)
    if player == nil or not player:IsValid() then return end
    -- argumentos vêm do cliente: valida tudo
    if type(fontes) ~= "string" or not fontes:find("^[gcbp]+$") then fontes = "gc" end
    aba_inicial = tonumber(aba_inicial) or 1
    if aba_inicial < 1 or aba_inicial > 4 then aba_inicial = 1 end   -- 4 = Legenda (só do cliente)
    if ocupado[player.userid] then return end   -- já está calculando para esse jogador
    ocupado[player.userid] = true

    -- Thread: a panela pode testar milhares de combinações, então divide entre frames
    G.StartThread(function()
        ComecarFrame()
        local s = CollectStock(player, fontes)
        local d = { abrir = aba_inicial, abas = {} }
        if s.achados.g + s.achados.c + s.achados.b == 0 and not s.personagem then
            d.abas[1] = { id = "itens", titulo = "Itens", itens = {}, resumo = DescreveFontes(s),
                          vazio = "Nada encontrado. Construa uma Geladeira, aumente o alcance nas opções do mod ou marque outra fonte." }
            d.abrir = 1
        else
            d.abas = { AbaItens(s), AbaDisponivel(s) }
        end
        ocupado[player.userid] = nil
        if not player:IsValid() then return end

        d.locais = s.locais
        d.contagem_fontes = s.contagem_fontes
        for _, a in ipairs(d.abas) do
            if a.id == "disponivel" then combos_do_jogador[player.userid] = a.combos end
        end
        local texto = Empacotar(d)
        if player == G.ThePlayer then
            Mostrar(texto)                       -- host jogando sem servidor dedicado
        else
            SendModRPCToClient(GetClientModRPC(NAMESPACE, "resultado"), player.userid, texto)
        end
    end, "ratatouille_" .. tostring(player.userid))
end

AddModRPCHandler(NAMESPACE, "pedir", function(player, fontes, aba) Responder(player, fontes, aba) end)

-- Combinações de UM prato (ao expandir a linha): da garantida para a menos provável.
-- Formato: "prato \t restantes" e depois "chave \t chance \t concorrentes" por linha.
AddModRPCHandler(NAMESPACE, "combos", function(player, prato)
    if player == nil or not player:IsValid() or type(prato) ~= "string" then return end
    local lista = combos_do_jogador[player.userid] and combos_do_jogador[player.userid][prato] or {}
    if not lista.ordenada then
        table.sort(lista, function(a, b)
            if a.c ~= b.c then return a.c > b.c end
            return a.k < b.k
        end)
        lista.ordenada = true
    end
    local n = math.min(#lista, LIMITE_COMBOS)
    local linhas = { prato .. SEP .. (#lista - n) }
    for i = 1, n do
        local c = lista[i]
        linhas[#linhas + 1] = table.concat({ c.k, string.format("%.3f", c.c), c.rv }, SEP)
    end
    local texto = table.concat(linhas, "\n")
    if player == G.ThePlayer then
        ReceberCombos(texto)                      -- host jogando sem servidor dedicado
    else
        SendModRPCToClient(GetClientModRPC(NAMESPACE, "combos"), player.userid, texto)
    end
end)

---------------------------------------------------------------------------
-- CLIENTE: painel lateral no HUD (como o menu de craft, mas na borda direita)
---------------------------------------------------------------------------
AddClassPostConstruct("widgets/controls", function(controls)
    if MOSTRAR_EM == "chat" then return end
    -- painel na borda direita; o gatilho arrastável no canto inferior direito (acima do mapa)
    controls.geladeira_painel = controls.right_root:AddChild(GeladeiraPainel({
        pedir = Pedir, raiz_gatilho = controls.bottomright_root }))
end)

---------------------------------------------------------------------------
-- CLIENTE: rodinha do mouse em cima do painel rola a lista, não dá zoom na câmera.
-- O jogo só faz essa exceção para o menu de craft (PlayerController:DoCameraControl
-- checa controls.craftingmenu.focus). Para o nosso painel: enquanto o mouse está
-- sobre ele (o foco sobe até o painel), dizemos que "acabou de dar zoom", e o jogo
-- espera ZOOM_REPEAT (0,1 s) para o próximo. A rotação da câmera não é afetada.
---------------------------------------------------------------------------
AddComponentPostInit("playercontroller", function(self)
    local DoCameraControl_original = self.DoCameraControl
    self.DoCameraControl = function(pc, ...)
        local painel = Painel()
        if painel ~= nil and painel:EstaAberto() and painel.focus then
            pc.lastzoomtime = G.GetStaticTime()
        end
        return DoCameraControl_original(pc, ...)
    end
end)

---------------------------------------------------------------------------
-- CLIENTE: teclas. Fechado: abre na aba da tecla. Aberto na mesma aba: fecha.
-- Aberto em outra aba: só troca de aba (sem pedir de novo ao servidor).
---------------------------------------------------------------------------
local function BindKey(key, rpc_name)
    G.TheInput:AddKeyUpHandler(key, function()
        if G.ThePlayer == nil then return end
        if G.TheFrontEnd.forceProcessText then return end   -- digitando na busca (ou no chat)
        local tela = TelaAtiva()
        if not (tela and tela.name == "HUD") then return end -- mapa, menu de pausa etc.
        local painel = Painel()
        if painel ~= nil then
            painel:Alternar(ABA_DA_TECLA[rpc_name])
        else
            Pedir(ABA_DA_TECLA[rpc_name])                    -- modo chat
        end
    end)
end

BindKey(KEY, "listar")
if KEY_RECEITAS ~= KEY then
    BindKey(KEY_RECEITAS, "receitas")
end
