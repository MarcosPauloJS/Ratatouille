-- Testa a LÓGICA do painel lateral e do conteúdo (abas, busca, ordem, filtros de grupo,
-- destaque no mundo, abrir/fechar/deslizar)
-- com widgets falsos no lugar dos do jogo (o desenho só dá para ver no jogo).
local dir = ...
local real = _G
real.require("fonts")          -- HEADERFONT, CHATFONT, NEWFONT_OUTLINE... (existem no jogo)

local falhas = 0
local function confere(cond, msg)
    print((cond and "  ok   " or "  FALHA ") .. msg)
    if not cond then falhas = falhas + 1 end
end

-- Widget falso: qualquer método devolve o próprio objeto; AddChild devolve o filho
local function Obj()
    return setmetatable({}, { __index = function(_, k)
        if k == "AddChild" then return function(_, c) return c end end
        return function(self) return self end
    end })
end
-- Widget falso como CLASSE de verdade do jogo (o conteúdo e o painel herdam dele).
-- Só os métodos do Widget que o mod usa em si mesmo; os demais não fazem nada.
-- (Não dá para usar um "__index pega-tudo" aqui: ele responderia também a campos
-- que valem nil, como self.ordem, e o teste mentiria.)
local Widget = real.Class(function(self, name) self.name = name end)
Widget.AddChild = function(_, c) return c end
Widget.MoveTo = function(self, de, para, t, fim) self.movido_para = para; if fim then fim() end end
Widget.GetPosition = function() return real.Vector3(0, 0, 0) end
Widget.OnControl = function() return false end
Widget.Show = function(self) self.visivel = true end
Widget.Hide = function(self) self.visivel = false end
for _, m in ipairs({ "SetPosition", "Kill", "ClearFocus", "SetFocus", "MoveToFront", "MoveToBack", "SetScale", "OnGainFocus", "OnLoseFocus" }) do
    Widget[m] = function(self) return self end
end

-- Botão falso com posição de verdade (o gatilho é arrastado e medido na tela).
-- Na tela, 1 unidade do HUD = 1,5 pixel e o canto inferior direito está em x=1920.
-- busca de arquivos do jogo (softresolvefilepath): uma pasta só, onde tudo existe
package.assetpath = package.assetpath or { { path = "../mods/Ratatouille/" } }
local kleifileexists_orig = rawget(real, "kleifileexists")
rawset(real, "kleifileexists", function(f, ...)        -- os arquivos do mod existem
    if f:find("geladeira_categorias", 1, true) then return true end
    return kleifileexists_orig ~= nil and kleifileexists_orig(f, ...)
end)
local ESCALA_TELA = 1.5
local function Botao(cb)
    local b = { click = cb, pos = real.Vector3(0, 0, 0), visivel = true }
    function b:SetPosition(x, y, z) if type(x) == "table" then x, y = x.x, x.y end; self.pos = real.Vector3(x, y, 0) end
    function b:GetPosition() return self.pos end
    function b:GetWorldPosition()
        local base = self.parent and self.parent:GetWorldPosition() or real.Vector3(0, 0, 0)
        return real.Vector3(base.x + self.pos.x * ESCALA_TELA, base.y + self.pos.y * ESCALA_TELA, 0)
    end
    function b:Show() self.visivel = true end
    function b:Hide() self.visivel = false end
    function b:SetTextColour(c) self.cor = c end
    function b:SetHoverText() end
    function b:MoveToFront() end
    function b:Kill() self.morto = true end
    return b
end
local raiz_canto = { GetWorldPosition = function() return real.Vector3(1920, 0, 0) end }
function raiz_canto:AddChild(c) c.parent = self; return c end

-- Mouse, tela e arquivo salvos falsos
local mouse = real.Vector3(0, 0, 0)
local atlas_do_mod_carregado = true      -- o selo do mod está carregado no jogo?
local ao_mover, ao_botao, salvo
env_extra = {
    -- funções que no jogo dependem do motor (atlas de imagens)
    -- como no jogo: cebola e tomate só existem como "quagmire_onion.tex" etc.
    -- Como no jogo com outro mod (Craft Pot) instalado: a resposta guardada para
    -- onion.tex é "inventoryimages4", mas o ícone NÃO está lá (só quagmire_onion.tex).
    GetInventoryItemAtlas = function(tex)
        if tex == "onion.tex" or tex == "tomato.tex" then return "images/inventoryimages4.xml" end
        return "images/inventoryimages1.xml"
    end,
    -- declarada no jogo com global("TheFocalPoint") em main.lua; aqui, um emissor de som mudo
    TheFocalPoint = { SoundEmitter = { PlaySound = function() end } },
    TheInput = {
        GetScreenPosition = function() return mouse end,
        AddMoveHandler = function(_, fn) ao_mover = fn; return { Remove = function() ao_mover = nil end } end,
        AddMouseButtonHandler = function(_, fn) ao_botao = fn; return { Remove = function() ao_botao = nil end } end,
    },
    TheSim = {
        AtlasContains = function(_, atlas, tex)
            if tex == "onion.tex" or tex == "tomato.tex" then return false end
            return atlas_do_mod_carregado or not atlas:find("geladeira_categorias")
        end,
        GetScreenSize = function() return 1920, 1080 end,
        SetPersistentString = function(_, nome, texto) salvo = { nome, texto } end,
        GetPersistentString = function(_, nome, cb) cb(true, "-200.0,300.0") end,
    },
}

local grid
local fake = {
    ["widgets/widget"] = Widget,
    ["widgets/text"] = function(_, _, texto)      -- guarda o texto para o teste conferir
        local t = Obj(); t.texto = texto
        t.SetString = function(self, x) self.texto = x end
        t.SetColour = function(self, c) self.cor = c end
        t.SetTruncatedString = function(self, x) self.texto = x end
        t.SetPosition = function(self, x, y) self.y = y end
        t.Show = function(self) self.visivel = true end
        t.Hide = function(self) self.visivel = false end
        return t
    end,
    ["widgets/image"] = function() return Obj() end,
    ["widgets/imagebutton"] = setmetatable({ OnGainFocus = function() end, OnLoseFocus = function() end },
                                           { __call = function()
                                               local b = Obj()
                                               b.SetOnClick = function(self, fn) self.click = fn end
                                               b.SetImageNormalColour = function(self, r, g, bb, a) self.alfa = a end
                                               b.SetTextures = function(self, atlas, normal) self.textura = normal end
                                               b.GetPosition = function() return real.Vector3(0, 0, 0) end
                                               b.Select = function(self) self.selecionada = true end
                                               b.Unselect = function(self) self.selecionada = false end
                                               b.Show = function(self) self.visivel = true end
                                               b.Hide = function(self) self.visivel = false end
                                               b.SetText = function(self, t) self.texto = t end
                                               return b
                                           end }),
    ["widgets/redux/headertabs"] = function() return Obj() end,
    ["widgets/redux/templates"] = {
        BackgroundTint = function() return Obj() end,
        RectangleWindow = function() local w = Obj(); w.mid_center = Obj(); return w end,
        StandardSingleLineTextEntry = function() local w = Obj(); w.textbox = Obj(); return w end,
        StandardButton = function(cb) return Botao(cb) end,
        StandardCheckbox = function(cb, _, marcado) local c = Obj(); c.click = cb; c.marcado = marcado
            checkboxes = checkboxes or {}; checkboxes[#checkboxes + 1] = c; return c end,
        ScrollingGrid = function(_, opts) local g = Obj(); g.opts = opts
            g.SetItemsData = function(self, it) self.itens = it end; grid = g; return g end,
    },
}
-- Ambiente ESTRITO como o do DST: ler uma global que não existe é erro.
-- (O ambiente de teste do jogo devolve um "stub" para qualquer global inexistente;
--  sem isto, um nome usado antes de ser declarado passava despercebido e só quebrava no jogo.)
local env = setmetatable({ require = function(n) return assert(fake[n], "require inesperado: " .. n) end },
                         { __index = function(_, k)
                               if env_extra[k] ~= nil then return env_extra[k] end
                               local v = rawget(real, k)
                               if v == nil then error("variable '" .. tostring(k) .. "' is not declared", 2) end
                               return v
                           end })
local function carregar(arquivo)
    local chunk = assert(loadfile(dir .. "/scripts/widgets/" .. arquivo))
    setfenv(chunk, env)
    return chunk()
end
local GeladeiraConteudo = carregar("geladeira_conteudo.lua")
fake["widgets/geladeira_conteudo"] = GeladeiraConteudo
local GeladeiraPainel = carregar("geladeira_painel.lua")

local function e(nome, v, f, s, extra)
    local t = { prefab = "x", nome = nome, vida = v, fome = f, sani = s }
    for k, x in pairs(extra or {}) do t[k] = x end
    return t
end
local dados = { abrir = 1,
  -- onde está a "Carne" (prefab x): 2 geladeiras, 1 Chester e no personagem
  locais = { x = { { cp = "icebox" }, { cp = "icebox" }, { cp = "chester" }, { cp = "_personagem" } } },
  abas = {
    { id = "itens", titulo = "Itens", stats = true, colunas = 1, itens = {
        e("Carne", "+25", "25", "-10", { qtd = "x6" }), e("Pétalas", "+1", "0", "0"), e("Gravetos") } },
    { id = "todas", titulo = "Todas", stats = true, colunas = 1, busca = true,
      filtros = { { id = "panela", rotulo = "Panela" }, { id = "fogueira", rotulo = "Fogueira" }, { id = "varal", rotulo = "Varal" } },
      itens = {
        e("Almôndegas", "+3", "62.5", "+5", { grupo = "panela", detalhe = "Ex.: 1x Carne, 3x Gelo", busca = { "Carne", "Gelo", "Mel" } }),
        e("Presunto com mel", "+30", "75", "+5", { grupo = "panela", detalhe = "Ex.: 2x Carne, 1x Mel", busca = { "Carne", "Mel" } }),
        e("Carne assada", "+3", "25", "0", { grupo = "fogueira", detalhe = "Carne na fogueira", busca = { "Carne" } }),
        e("Charque", "+20", "25", "+15", { grupo = "varal", detalhe = "Carne no varal", busca = { "Carne" } }),
      } } } }

local tela = GeladeiraConteudo(dados)
local function nomes()
    local t = {}
    for _, x in ipairs(grid.itens or {}) do t[#t + 1] = x.nome end
    return table.concat(t, " | ")
end

print("== Itens (mesma lista das abas Disponível e Todas)")
confere(grid.opts.num_columns == 1 and grid.opts.num_visible_rows >= 6, "lista de 1 coluna ocupando o papel até embaixo (" .. grid.opts.num_visible_rows .. " linhas)")
confere(grid.opts.scroll_context.stats == true, "colunas Vida/Fome/Sanid. na lista")
local o = grid.opts
local function celula(i) local c = o.item_ctor_fn(o.scroll_context, i); o.apply_fn(o.scroll_context, c, grid.itens[i], i); return c end
local function celula_de(nome) for i, x in ipairs(grid.itens) do if x.nome == nome then return celula(i) end end end
local c_carne = celula_de("Carne")
confere(c_carne.stat ~= nil and c_carne.stat.vida.texto == "+25" and c_carne.stat.fome.texto == "25" and c_carne.stat.sani.texto == "-10",
    "linha da Carne com os 3 atributos")
confere(c_carne.qtd.texto == "x6", "quantidade na coluna da direita: " .. tostring(c_carne.qtd.texto))
confere(tela.info == nil, "sem caixa de detalhes")
do  -- ingredientes com categoria: se não cabem antes dos status, os status sobem
    local curto = { prefab = "meatballs", nome = "Almôndegas", vida = "+3", icones = { { prefab = "meat", n = 1 }, { prefab = "ice", n = 3 } } }
    local longo = { prefab = "icecream", nome = "Sorvete", vida = "+0", icones = { { prefab = "berries", n = 1, rotulo = "Fruta ½" },
        { prefab = "ice", n = 1 }, { prefab = "honey", n = 1, rotulo = "Adoçante" }, { prefab = "butter", n = 1 } } }
    local c1 = celula(1); o.apply_fn(o.scroll_context, c1, curto, 1)
    confere(c1.stat.vida.y == 0, "poucos ingredientes: status no meio da linha")
    o.apply_fn(o.scroll_context, c1, longo, 1)
    confere(c1.stat.vida.y == 10 and c1.qtd.y == 10, "ingredientes longos: status sobem para a linha do nome")
    o.apply_fn(o.scroll_context, c1, curto, 1)
    confere(c1.stat.vida.y == 0, "célula reaproveitada volta ao normal")
end

print("== Destaque no mundo a partir da interface")
local pedidos_destaque = {}
tela.dados.ao_destacar = function(prefabs) pedidos_destaque[#pedidos_destaque + 1] = prefabs and table.concat(prefabs, ",") or "nada" end
tela:MostrarAba(1)
o = grid.opts
w = o.item_ctor_fn(o.scroll_context, 1); o.apply_fn(o.scroll_context, w, grid.itens[1], 1)
w:OnGainFocus()                                           -- linha da lista (como em Disponível/Todas)
confere(pedidos_destaque[#pedidos_destaque] == "x", "aba Itens: mouse no item destaca as geladeiras dele")
w:OnLoseFocus()
confere(pedidos_destaque[#pedidos_destaque] == "nada", "mouse saiu: apaga")
tela:MostrarAba(2)
local n_antes = #pedidos_destaque
o = grid.opts
w = o.item_ctor_fn(o.scroll_context, 1); o.apply_fn(o.scroll_context, w, grid.itens[1], 1)
w:OnGainFocus()
confere(#pedidos_destaque == n_antes, "aba Todas: mouse na linha NÃO destaca nada (não é do seu estoque)")
tela.dados.ao_destacar = nil
tela:MostrarAba(1)

print("== Abas do livro de receitas")
confere(#tela.abas == 2 and tela.abas[1].selecionada and not tela.abas[2].selecionada, "aba 1 selecionada, aba 2 não")
tela.abas[2].click()
confere(tela.aba_indice == 2 and tela.abas[2].selecionada and not tela.abas[1].selecionada, "clicar na aba 2 troca e marca")
tela.abas[1].click()

print("== Ordem")
local ok_escala = true
for _, b in ipairs(tela.botoes_ordem) do ok_escala = ok_escala and (rawget(b, "ignore_standard_scaling") == true) end
confere(ok_escala, "ícones de ordenar crescem sobre o tamanho forçado (ignore_standard_scaling)")
tela.botoes_ordem[1].click()
confere(tela.ordem == 1 and tela.botoes_ordem[1].alfa == 1 and tela.botoes_ordem[2].alfa == 0.45,
    "ordenação como antes: ícone de Vida ativo (forte), os outros apagados")
tela.botoes_ordem[1].click()
confere(tela.ordem == nil, "clicar de novo volta ao padrão")

print("== Todas: filtros de grupo")
checkboxes = {}
tela:MostrarAba(2)
confere(#checkboxes == 3, "3 checkboxes (Panela, Fogueira, Varal)")
confere(nomes() == "Almôndegas | Presunto com mel | Carne assada | Charque", "todos ligados: " .. nomes())
checkboxes[1].click()                                   -- desliga Panela
confere(nomes() == "Carne assada | Charque", "sem Panela: " .. nomes())
checkboxes[2].click()                                   -- desliga Fogueira
confere(nomes() == "Charque", "só Varal: " .. nomes())
confere(checkboxes[3].click() == true and nomes() == "Charque", "não deixa desligar o último")
checkboxes[1].click(); checkboxes[2].click()            -- religa
tela.filtro = "carne"; tela:Atualizar()
confere(nomes():find("Carne assada", 1, true) and nomes():find("Almôndegas", 1, true), "busca 'carne' acha nos 3 grupos: " .. nomes())
tela.filtro = ""

print("== Contagem ao lado dos checkboxes de grupo")
tela.filtro = ""
checkboxes = {}
tela:MostrarAba(2)
local rg = tela.rotulos_grupo
confere(rg.panela.texto == "Panela (x2)" and rg.fogueira.texto == "Fogueira (x1)" and rg.varal.texto == "Varal (x1)",
    "contagem por grupo: " .. rg.panela.texto .. " / " .. rg.fogueira.texto .. " / " .. rg.varal.texto)
tela.filtro = "almondega"; tela:Atualizar()
confere(rg.panela.texto == "Panela (x1)" and rg.fogueira.texto == "Fogueira (x0)", "com busca, conta só o que bate: " .. rg.panela.texto .. " / " .. rg.fogueira.texto)
tela.filtro = ""; tela:Atualizar()

print("== Busca só na aba Todas")
local mostrada
tela.busca.Show = function() mostrada = true end
tela.busca.Hide = function() mostrada = false end
tela.filtro = "almondega"
tela:MostrarAba(1)
confere(mostrada == false and nomes() == "Carne | Pétalas | Gravetos", "Itens: caixa escondida e busca ignorada (" .. nomes() .. ")")
checkboxes = {}
tela:MostrarAba(2)
confere(mostrada == true and nomes() == "Almôndegas", "Todas: caixa visível e busca vale (" .. nomes() .. ")")
tela.filtro = ""

print("== Sem barra de pesquisa, sem buraco; sem rodapé")
tela:MostrarAba(1)
local topo_itens, linhas_itens = tela.topo_lista, tela.linhas_visiveis
checkboxes = {}
tela:MostrarAba(2)
confere(tela.topo_lista == topo_itens - 42 and tela.linhas_visiveis <= linhas_itens,
    "aba com busca (Todas): a caixa ocupa 42 a mais (" .. topo_itens .. " -> " .. tela.topo_lista .. ")")
confere(tela.rodape == nil and tela.botao_fechar == nil, "sem rodapé e sem botão Fechar embaixo")
local fundo = tela.y_lista - tela.linhas_visiveis * 58 / 2
confere(fundo >= -640 / 2 + 30 and fundo < -640 / 2 + 30 + 58, "a lista vai até o fim do papel (fundo em " .. fundo .. ")")

print("== Atualizar ao lado de Ordenar; Fechar é uma aba")
tela:MostrarAba(1)
confere(tela.botao_atualizar.visivel == true, "Itens: Atualizar aparece")
checkboxes = {}
tela:MostrarAba(2)
confere(tela.botao_atualizar.visivel == false, "Todas: sem Atualizar (não vem do servidor)")
local fechou = false
tela.dados.ao_fechar = function() fechou = true end
confere(tela.aba_fechar ~= nil and tela.aba_fechar.texto == "X", "aba X no fim das abas")
tela.aba_fechar.click()
confere(fechou, "aba X fecha o painel")
tela.dados.ao_fechar = nil
tela:AvisarCarregando()
confere(tela.rotulo_ordem.texto == "Atualizando..." and tela.botao_atualizar.visivel == false, "atualizando: o rótulo avisa")
confere(tela.seta_ordem == nil, "sem a setinha embaixo do ícone de ordenação")

print("== Filtros sobrevivem à troca de aba")
checkboxes = {}
checkboxes_antes = nil
tela:MostrarAba(1); tela:MostrarAba(2)
checkboxes[2].click()                                   -- desliga Fogueira
checkboxes = {}
tela:MostrarAba(1); tela:MostrarAba(2)
confere(checkboxes[2].marcado == false and not nomes():find("Carne assada", 1, true), "Fogueira continua desligada")

print("== Disponível: prato da panela abre com as combinações")
local pedidos_combos = {}
local disp = GeladeiraConteudo({ abrir = 1, abas = { { id = "disponivel", titulo = "Disponível", stats = true, colunas = 1,
    filtros = { { id = "panela", rotulo = "Panela" }, { id = "fogueira", rotulo = "Fogueira" } },
    itens = {
        e("Almôndegas", "+3", "62.5", "+5", { prefab = "meatballs", grupo = "panela", qtd = "3",
            icones = { { prefab = "meat", n = 1 }, { prefab = "carrot", n = 3 } } }),
        e("Carne assada", "+3", "25", "0", { prefab = "cookedmeat", grupo = "fogueira", qtd = "x6",
            icones = { { prefab = "meat", n = 0 } } }),
    } } },
    ao_pedir_combos = function(prato) pedidos_combos[#pedidos_combos + 1] = prato end })
local function linhas() local t = {} for _, x in ipairs(grid.itens) do t[#t + 1] = x.tipo and ("[" .. x.nome .. " " .. (x.qtd or "") .. "]") or x.nome end return table.concat(t, " | ") end
local prato = grid.itens[1]
confere(prato.expansivel and not prato._aberto, "prato da panela pode abrir (começa fechado)")
confere(grid.itens[2].expansivel == false, "fogueira não abre")
confere(grid.opts.scroll_context.ao_clicar(grid.itens[2]) == false, "clicar na fogueira não faz nada")
grid.opts.scroll_context.ao_clicar(prato)
confere(pedidos_combos[1] == "meatballs" and linhas() == "Almôndegas | [Carregando combinações... ] | Carne assada",
    "clicou: pede ao servidor e mostra 'Carregando': " .. linhas())
disp:ReceberCombos("meatballs", {
    { icones = { { prefab = "meat", n = 1 }, { prefab = "carrot", n = 3 } }, chance = 1, rivais = {} },
    { icones = { { prefab = "berries", n = 4 } }, chance = 0.5, rivais = { "jammypreserves" } },
}, 5)
confere(linhas() == "Almôndegas | [Garantido 100%] | [Empata com 50%] | [... e mais 5 combinações ] | Carne assada",
    "combinações embaixo do prato, da garantida para a menor: " .. linhas())
local oc = grid.opts
local cel = oc.item_ctor_fn(oc.scroll_context, 3); oc.apply_fn(oc.scroll_context, cel, grid.itens[3], 3)
confere(cel.rivais ~= nil and grid.itens[3].rivais[1] == "jammypreserves", "linha de empate traz o ícone do concorrente")
grid.opts.scroll_context.ao_clicar(grid.itens[1])
confere(linhas() == "Almôndegas | Carne assada" and #pedidos_combos == 1, "clicou de novo: fecha")
grid.opts.scroll_context.ao_clicar(grid.itens[1])
confere(#pedidos_combos == 1 and linhas():find("Garantido", 1, true), "reabrir usa o que já chegou (sem novo pedido)")

print("== Ícone da cebola")
do
    local c = celula(1)
    local tex_usada
    c.icone.SetTexture = function(_, atlas, tex) tex_usada = tex end
    o.apply_fn(o.scroll_context, c, { prefab = "onion", nome = "Cebola" }, 1)
    confere(tex_usada == "quagmire_onion.tex", "cebola usa quagmire_onion.tex (" .. tostring(tex_usada) .. ")")
end

print("== Legenda: sem ordenação")
do
    local leg = GeladeiraConteudo({ abrir = 2, abas = {
        { id = "itens", titulo = "Itens", colunas = 1, itens = { e("Carne") } },
        { id = "legenda", titulo = "Legenda", colunas = 1, sem_ordem = true, itens = {
            e("Zebra", nil, nil, nil, { atlas = "images/geladeira_categorias.xml", tex = "cat_carne.tex" }),
            e("Abacate"), e("Meio legume") } } } })
    local function ordem() local t = {} for _, x in ipairs(grid.itens) do t[#t + 1] = x.nome end return table.concat(t, ",") end
    leg.ordem = 4; leg:Atualizar()          -- mesmo com "por nome" escolhido antes, a Legenda não reordena
    confere(ordem() == "Zebra,Abacate,Meio legume", "Legenda fica na ordem montada (" .. ordem() .. ")")
    confere(leg.rotulo_ordem.visivel == false, "Legenda: \"Ordenar:\" escondido")
    confere(leg.topo_lista > 270 and leg.linhas_visiveis >= 9 and leg.botao_atualizar.visivel == false,
        "Legenda: lista começa logo abaixo das abas e usa o papel todo (" .. leg.linhas_visiveis .. " linhas)")
    local c = grid.opts.item_ctor_fn(grid.opts.scroll_context, 1); grid.opts.apply_fn(grid.opts.scroll_context, c, grid.itens[1], 1)
    local tex_usada
    c.icone.SetTexture = function(_, atlas, tex) tex_usada = tex end
    grid.opts.apply_fn(grid.opts.scroll_context, c, { nome = "Carne", prefab = "meat", atlas = "images/geladeira_categorias.xml", tex = "cat_carne.tex" }, 1)
    confere(tex_usada == "cat_carne.tex", "Legenda: selo do mod quando a textura está carregada (" .. tostring(tex_usada) .. ")")
    -- textura NÃO carregada: usa o ícone do item (e não deixa a imagem anterior na célula)
    atlas_do_mod_carregado = false
    local Novo = carregar("geladeira_conteudo.lua")          -- módulo novo (sem cache de atlas)
    Novo({ abrir = 1, abas = { { id = "legenda", titulo = "Legenda", colunas = 1, sem_ordem = true, itens = { e("X") } } } })
    local c2 = grid.opts.item_ctor_fn(grid.opts.scroll_context, 1)
    tex_usada = nil
    c2.icone.SetTexture = function(_, atlas, tex) tex_usada = tex end
    grid.opts.apply_fn(grid.opts.scroll_context, c2, { nome = "Carne", prefab = "meat", atlas = "images/geladeira_categorias.xml", tex = "cat_carne.tex" }, 1)
    confere(tex_usada == "meat.tex", "selo não carregado: cai no ícone do item (" .. tostring(tex_usada) .. ")")
    atlas_do_mod_carregado = true
    leg:MostrarAba(1)
    confere(leg.rotulo_ordem.visivel == true, "voltou para Itens: \"Ordenar:\" aparece de novo")
end

print("== Legenda: categoria abre com os itens")
do
    local leg = GeladeiraConteudo({ abrir = 1, abas = {
        { id = "legenda", titulo = "Legenda", colunas = 1, sem_ordem = true, itens = {
            { chave = "cat:legume", prefab = "carrot", nome = "Legume", atlas = "images/geladeira_categorias.xml", tex = "cat_legume.tex",
              filhos = { { prefab = "carrot", nome = "Cenoura" }, { prefab = "onion", nome = "Cebola" } } },
            { chave = "cat:carne", prefab = "meat", nome = "Carne", atlas = "images/geladeira_categorias.xml", tex = "cat_carne.tex",
              filhos = { { prefab = "meat", nome = "Carne crua" } } },
            { prefab = "mandrake", nome = "Item específico" } } } } })
    local function ls() local t = {} for _, x in ipairs(grid.itens) do t[#t + 1] = (x.tipo and "[" or "") .. x.nome .. (x.tipo and "]" or "") end return table.concat(t, " | ") end
    confere(grid.itens[1].expansivel and not grid.itens[3].expansivel, "categoria tem setinha; linha sem filhos não")
    grid.opts.scroll_context.ao_clicar(grid.itens[1])
    confere(ls() == "Legume | [Cenoura] | [Cebola] | Carne | Item específico", "Legume aberto: " .. ls())
    local c = grid.opts.item_ctor_fn(grid.opts.scroll_context, 2)
    local tex_usada
    c.icone.SetTexture = function(_, atlas, tex) tex_usada = tex end
    grid.opts.apply_fn(grid.opts.scroll_context, c, grid.itens[3], 3)
    confere(tex_usada == "quagmire_onion.tex", "item da categoria com o ícone do jogo (" .. tostring(tex_usada) .. ")")
    grid.opts.scroll_context.ao_clicar(grid.itens[4])
    confere(ls() == "Legume | [Cenoura] | [Cebola] | Carne | [Carne crua] | Item específico", "duas categorias abertas: " .. ls())
    grid.opts.scroll_context.ao_clicar(grid.itens[1])
    confere(ls() == "Legume | Carne | [Carne crua] | Item específico", "fechou Legume: " .. ls())
end

print("== Painel lateral")
local pedidos = {}
local p = GeladeiraPainel({ pedir = function(aba) pedidos[#pedidos + 1] = aba end, raiz_gatilho = raiz_canto })
confere(not p:EstaAberto() and p.carregando ~= nil, "começa fechado, com 'Calculando...' pronto")
confere(p.ui_root.visivel == false, "fechado: o painel fica ESCONDIDO (nada aparece na borda)")
confere(p.gatilho.parent == raiz_canto, "gatilho fica no canto inferior direito (bottomright_root)")
confere(p.gatilho.pos.x == -200 and p.gatilho.pos.y == 300, "posição salva do gatilho é carregada (-200, 300)")
p:Alternar(2)
confere(p:EstaAberto() and pedidos[1] == 2, "abrir pede os dados da aba 2 ao servidor")
confere(p.ui_root.visivel == true and p.gatilho.visivel == false, "aberto: painel aparece e o gatilho some")
confere(p.ui_root.movido_para == p.pos_aberto and p.pos_aberto.x < 0, "desliza para dentro da tela (x < 0)")
local d2 = { abrir = 2, abas = dados.abas }
p:MostrarDados(d2)
confere(p.conteudo ~= nil and p.carregando == nil and p.conteudo.aba_indice == 2, "dados chegaram: mostra o conteúdo na aba 2")
p:Alternar(1)
confere(p:EstaAberto() and p.conteudo.aba_indice == 1 and #pedidos == 1, "outra tecla só troca de aba (sem novo pedido)")
d2.ao_atualizar(1)
confere(#pedidos == 2 and pedidos[2] == 1, "botão Atualizar pede de novo")
p:Alternar(1)
confere(not p:EstaAberto() and p.ui_root.movido_para == p.pos_fechado, "mesma tecla fecha e desliza para fora")
confere(p.ui_root.visivel == false and p.gatilho.visivel == true, "fechou: painel escondido no fim da animação, gatilho volta")
p:Alternar(1)
confere(p:EstaAberto() and #pedidos == 3, "reabrir pede dados novos (o mundo pode ter mudado)")
d2.ao_fechar()
confere(not p:EstaAberto(), "botão Fechar do conteúdo fecha o painel")


print("== Gatilho: clique x arrasto")
local n = #pedidos
mouse = real.Vector3(1000, 500, 0)
p.gatilho:OnControl(real.CONTROL_ACCEPT, true)
p.gatilho:OnControl(real.CONTROL_ACCEPT, false)          -- soltou sem mover: é clique
confere(p:EstaAberto() and #pedidos == n + 1, "clique no gatilho abre o painel")
p:Fechar()
local antes = p.gatilho.pos
p.gatilho:OnControl(real.CONTROL_ACCEPT, true)
ao_mover(1000 - 150, 500 + 75)                           -- arrasta 150 px p/ esquerda, 75 p/ cima
ao_botao(real.MOUSEBUTTON_LEFT, false)                   -- soltou fora do botão
confere(not p:EstaAberto(), "arrastar NÃO abre o painel")
confere(math.abs(p.gatilho.pos.x - (antes.x - 100)) < 0.01 and math.abs(p.gatilho.pos.y - (antes.y + 50)) < 0.01,
    string.format("gatilho andou 150/75 px = 100/50 unidades (%.1f, %.1f)", p.gatilho.pos.x, p.gatilho.pos.y))
confere(salvo and salvo[1] == "ratatouille_botao" and salvo[2] == "-300.0,350.0", "posição salva: " .. tostring(salvo and salvo[2]))
confere(ao_mover == nil and ao_botao == nil, "terminou o arrasto: para de ouvir o mouse")
p.gatilho:OnControl(real.CONTROL_ACCEPT, true)
ao_mover(5000, 5000)                                     -- tenta jogar para fora da tela
p.gatilho:OnControl(real.CONTROL_ACCEPT, false)
confere(p.gatilho.pos.x <= -32 and p.gatilho.pos.y <= 1080 / ESCALA_TELA - 32, "não sai da tela (fica preso na borda)")

print(falhas == 0 and "TUDO OK" or (falhas .. " FALHA(S)"))
if falhas > 0 then error(falhas .. " teste(s) falharam", 0) end
