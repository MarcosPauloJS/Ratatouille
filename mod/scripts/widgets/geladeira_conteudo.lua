-- Conteúdo do painel lateral do mod Ratatouille: abas, lista, busca, ordem e filtros.
-- É um Widget comum (não uma tela modal): vive dentro do HUD, então o jogador continua
-- andando e interagindo com o mundo enquanto ele está aberto. Quem desliza para dentro
-- e para fora da tela é o widgets/geladeira_painel.lua.
-- Arquivos em scripts/ rodam no ambiente global do jogo: Class, TheFrontEnd,
-- ANCHOR_*, UICOLOURS... estão disponíveis direto, sem GLOBAL.
local Widget     = require "widgets/widget"
local Text       = require "widgets/text"
local Image      = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local TEMPLATES  = require "widgets/redux/templates"

-- Medidas em "unidades do pergaminho" (o pergaminho inteiro é desenhado a 77%:
-- eram 70%, aumentado em 10%).
local ESCALA_JANELA      = 0.77
-- Painel estreito (coluna lateral): ~60% da largura da janela antiga (700).
-- Altura 496 = 620 - 20% (com 620 uma parte saía da tela).
local JANELA_L, JANELA_A = 470, 640       -- o PERGAMINHO inteiro (abas e botões ficam dentro dele)
local LISTA_L            = 380
local CELULA_A           = 58
local LINHAS_VISIVEIS    = 5
local ICONE              = 40
local STAT_L             = 44      -- largura de cada coluna Vida / Fome / Sanidade
local QTD_L              = 50
local MINI               = 20      -- ícone pequeno dos ingredientes (abas Disponível e Todas)
local MINI_PASSO         = 34      -- espaço de cada "2x [ícone]"
local TEXTO_X0           = 52      -- onde começa o texto da célula (depois do ícone)

-- Posições verticais (de cima para baixo), cada controle na sua linha
local Y_ABAS      = JANELA_A / 2 + 4      -- abas do livro de receitas, na borda de cima do papel
local Y_CONTROLES = JANELA_A / 2 - 58     -- linha "Ordenar:" com os ícones
local Y_FUNDO     = -JANELA_A / 2 + 30    -- a lista vai até aqui (sem rodapé nem botões embaixo)
local ALTURA_ORDEM = 44                   -- linha "Ordenar:" (+ Atualizar)
local TOPO_SEM_ORDEM = Y_CONTROLES + 22   -- aba sem ordenação (Legenda): lista logo abaixo das abas
local Y_BUSCA     = Y_CONTROLES - 44      -- caixa de busca (só aba Todas)
local ALTURA_BUSCA = 44                   -- nas abas sem busca, o que vem abaixo sobe isso
local Y_CHECKS    = Y_BUSCA - 42          -- 1ª linha de checkboxes (2 por linha)
local CHECK_LINHA = 32
local CHECK_COLUNA = 190
-- (sem linha de resumo: as contagens ficam ao lado de cada checkbox)
local Y_CABECALHO = Y_CHECKS - CHECK_LINHA - 34
local Y_LISTA     = Y_CABECALHO - 14 - LINHAS_VISIVEIS * CELULA_A / 2
-- (declarados ANTES de usar: o DST roda em modo estrito e um nome ainda não declarado
--  é lido como global inexistente, o que derruba o mod)

-- Checkbox j (1..4) em 2 colunas: posição dentro do contêiner de checkboxes
local function PosCheck(j)
    local col, lin = (j - 1) % 2, math.floor((j - 1) / 2)
    return col * CHECK_COLUNA, -lin * CHECK_LINHA
end

-- Visual de pergaminho, como o livro de receitas do jogo (cookbookwidget.lua):
-- fundo quagmire_recipe_menu_bg e texto marrom-escuro (UICOLOURS.BROWN_DARK).
local ATLAS_LIVRO = "images/quagmire_recipebook.xml"
local COR_TEXTO   = UICOLOURS.BROWN_DARK
local COR_SUAVE   = UICOLOURS.BROWN_MEDIUM

-- Cores das colunas de atributos: vermelho, laranja e azul ESCUROS (para ler no papel)
local COR_STAT = {
    vida = { 0.66, 0.14, 0.12, 1 },
    fome = { 0.62, 0.38, 0.04, 1 },
    sani = { 0.16, 0.30, 0.62, 1 },
}
local STATS = { "vida", "fome", "sani" }
-- versões claras das cores dos atributos, para ler sobre a caixa escura
local COR_STAT_CLARA = {
    vida = { 1.00, 0.55, 0.50, 1 },
    fome = { 1.00, 0.80, 0.40, 1 },
    sani = { 0.62, 0.78, 1.00, 1 },
}
-- Ordenações: um botão para cada; clicar no ativo volta para a ordem padrão
-- Só ícones: os dos medidores do jogo (coração, estômago, cérebro) e o "A-Z" do jogo
local ORDENS = {
    { id = "vida", icone = { "images/global_redux.xml", "status_health.tex" } },
    { id = "fome", icone = { "images/global_redux.xml", "status_hunger.tex" } },
    { id = "sani", icone = { "images/global_redux.xml", "status_sanity.tex" } },
    { id = "nome", icone = { "images/button_icons.xml", "sort_name.tex" } },
}
local ICONE_ORDEM, ICONE_PASSO = 40, 62

-- Centro X da coluna de atributo j (1..3) numa célula de largura L
local function XStat(L, j)
    return L / 2 - 6 - QTD_L - (3 - j) * STAT_L - STAT_L / 2
end

---------------------------------------------------------------------------
-- Busca: minúsculas e sem acento ("Pétalas" acha com "petalas")
---------------------------------------------------------------------------
local SEM_ACENTO = {
    ["á"]="a", ["à"]="a", ["â"]="a", ["ã"]="a", ["Á"]="a", ["À"]="a", ["Â"]="a", ["Ã"]="a",
    ["é"]="e", ["ê"]="e", ["É"]="e", ["Ê"]="e", ["í"]="i", ["Í"]="i",
    ["ó"]="o", ["ô"]="o", ["õ"]="o", ["Ó"]="o", ["Ô"]="o", ["Õ"]="o",
    ["ú"]="u", ["ü"]="u", ["Ú"]="u", ["Ü"]="u", ["ç"]="c", ["Ç"]="c",
}
local function Normaliza(s)
    s = tostring(s or "")
    for de, para in pairs(SEM_ACENTO) do s = s:gsub(de, para) end
    return s:lower()
end

local function Numero(s)
    if s == nil then return nil end
    return tonumber((s:gsub("^%+", "")))
end

---------------------------------------------------------------------------
-- Células da lista
---------------------------------------------------------------------------
-- Procura o atlas do ícone; devolve nil se o jogo não tiver a imagem
-- Ícone do inventário de um prefab. Cebola e tomate usam a imagem com outro nome
-- ("quagmire_onion.tex"), herdada do evento Gorge.
-- Confere de verdade: GetInventoryItemAtlas guarda as respostas numa tabela do jogo, e se
-- outro mod perguntou antes SEM no_fallback, fica guardado "inventoryimages4" para um ícone
-- que não existe lá (ex.: onion.tex). A imagem não troca e, no scroll, a linha
-- reaproveitada continua mostrando o ícone anterior.
local function AtlasQueTem(tex)
    local atlas = GetInventoryItemAtlas(tex, true)
    if atlas ~= nil and TheSim:AtlasContains(atlas, tex) then return atlas end
    return nil
end

local icone_do_prefab = {}     -- prefab -> { atlas, tex } (ou false se não tem ícone)
local function AtlasDoPrefab(prefab)
    local r = icone_do_prefab[prefab]
    if r == nil then
        local tex = prefab .. ".tex"
        local atlas = AtlasQueTem(tex)
        if atlas == nil then
            tex = "quagmire_" .. tex
            atlas = AtlasQueTem(tex)
        end
        r = atlas and { atlas, tex } or false
        icone_do_prefab[prefab] = r
    end
    if r then return r[1], r[2] end
    return nil
end

-- Ícone próprio do mod (selo de categoria). Só usa se a textura estiver mesmo carregada:
-- se não estiver, o jogo NÃO troca a imagem e a célula reaproveitada no scroll fica
-- mostrando o ícone anterior (a "mandrágora fantasma"). Aí cai no ícone do item.
local atlas_ok = {}
local function AtlasProprio(atlas, tex, prefab)
    local chave = atlas .. "|" .. tex
    if atlas_ok[chave] == nil then
        local caminho = softresolvefilepath(atlas)
        atlas_ok[chave] = caminho ~= nil and TheSim:AtlasContains(caminho, tex) == true
        if not atlas_ok[chave] then print("[Ratatouille] textura não carregada: " .. chave) end
    end
    if atlas_ok[chave] then return atlas, tex end
    if prefab then return AtlasDoPrefab(prefab) end
    return nil
end

local function AtlasDoIcone(entrada)
    if entrada.atlas then return AtlasProprio(entrada.atlas, entrada.tex, entrada.prefab) end
    if entrada.receita then
        local r = AllRecipes[entrada.receita]
        if r ~= nil then
            if r.atlas ~= nil then return r.atlas, r.image end
            local atlas = GetInventoryItemAtlas(r.image, true)
            if atlas ~= nil then return atlas, r.image end
        end
        return nil
    end
    return AtlasDoPrefab(entrada.prefab)
end

-- " (x4)" quando há número; nada quando não há
local function Contagem(n)
    return n ~= nil and string.format(" (x%d)", n) or ""
end

-- Uma célula: ícone + nome (+ detalhe embaixo) + atributos + quantidade à direita
local function CriarCelula(ctx, index)
    local L = ctx.largura
    local w = Widget("celula")
    w.fundo = w:AddChild(Image("images/global.xml", "square.tex"))
    w.fundo:SetSize(L - 8, CELULA_A - 6)
    w.fundo:SetTint(0.31, 0.24, 0.15, 0.10)   -- faixa marrom bem leve sobre o papel

    w.icone = w:AddChild(Image())
    w.icone:SetPosition(-L / 2 + 26, 0)

    -- setinha de "abre/fecha" (pratos da panela na aba Disponível)
    w.seta = w:AddChild(Image())
    w.seta:SetPosition(-L / 2 + 8, -18)
    w.seta:SetClickable(false)
    w.seta:Hide()

    -- linha de combinação: ícones dos pratos que disputam o sorteio (empate)
    w.rivais = {}
    for k = 1, 3 do
        local r = w:AddChild(Image())
        r:SetPosition(-L / 2 + TEXTO_X0 + 96 + (k - 1) * 24, 10)
        r:SetClickable(false)
        r:Hide()
        w.rivais[k] = r
    end

    local texto_l = L - TEXTO_X0 - QTD_L - 12 - (ctx.stats and 3 * STAT_L or 0)
    w.nome = w:AddChild(Text(CHATFONT, 20, ""))
    w.nome:SetColour(COR_TEXTO)
    w.nome:SetHAlign(ANCHOR_LEFT)
    w.nome:SetRegionSize(texto_l, 28)

    w.detalhe = w:AddChild(Text(CHATFONT, 16, ""))
    w.detalhe:SetColour(COR_SUAVE)
    w.detalhe:SetHAlign(ANCHOR_LEFT)
    w.detalhe:SetRegionSize(texto_l, 20)
    w.detalhe:SetPosition(-L / 2 + TEXTO_X0 + texto_l / 2, -12)

    -- até 4 ingredientes como "2x [ícone]" na linha de baixo (abas Panela e Todas)
    w.minis = {}
    for k = 1, 4 do
        local m = w:AddChild(Widget("mini"))
        m:SetPosition(-L / 2 + TEXTO_X0 + (k - 1) * MINI_PASSO + 8, -13)
        m.n = m:AddChild(Text(CHATFONT, 15, "", COR_SUAVE))
        m.n:SetHAlign(ANCHOR_RIGHT)
        m.n:SetRegionSize(18, 20)
        m.img = m:AddChild(Image())
        m.img:SetPosition(19, 0)
        -- categoria ("Carne", "Legume"...) escrita depois do ícone de exemplo
        m.rot = m:AddChild(Text(CHATFONT, 15, "", COR_SUAVE))
        m.rot:SetHAlign(ANCHOR_LEFT)
        m.rot:Hide()
        m:Hide()
        w.minis[k] = m
    end

    if ctx.stats then
        w.stat = {}
        for j, k in ipairs(STATS) do
            local t = w:AddChild(Text(CHATFONT, 20, ""))
            t:SetColour(COR_STAT[k])
            t:SetHAlign(ANCHOR_MIDDLE)
            t:SetRegionSize(STAT_L, CELULA_A)
            t:SetPosition(XStat(L, j), 0)
            w.stat[k] = t
        end
    end

    w.qtd = w:AddChild(Text(CHATFONT, 18, ""))
    w.qtd:SetColour(COR_TEXTO)
    w.qtd:SetHAlign(ANCHOR_RIGHT)
    w.qtd:SetRegionSize(QTD_L, CELULA_A)
    w.qtd:SetPosition(L / 2 - 6 - QTD_L / 2, 0)

    w.texto_l = texto_l
    -- Mouse em cima da linha (o foco sobe da imagem de fundo até a célula): avisa a janela
    w.OnGainFocus = function(cel)
        Widget.OnGainFocus(cel)
        if ctx.ao_focar and cel.entrada then ctx.ao_focar(cel.entrada) end
    end
    w.OnLoseFocus = function(cel)
        Widget.OnLoseFocus(cel)
        if ctx.ao_focar then ctx.ao_focar(nil) end
    end
    -- Clique na linha (o controle "aceitar" chega à célula que está sob o mouse)
    w.OnControl = function(cel, control, down)
        if Widget.OnControl(cel, control, down) then return true end
        if control == CONTROL_ACCEPT and not down and cel.entrada and ctx.ao_clicar then
            return ctx.ao_clicar(cel.entrada)
        end
        return false
    end
    return w
end

-- largura aproximada de um texto curto na fonte 15 (conta letras, não bytes do UTF-8)
local function LarguraTexto(s)
    local letras = #(string.gsub(s, "[\128-\191]", ""))
    return letras * 7 + 4
end

local function AplicarCelula(ctx, w, entrada, index)
    if entrada == nil then
        w:Hide()
        return
    end
    w:Show()
    -- linhas de combinação/aviso não têm ícone próprio (ficam "recuadas" sob o prato)
    local atlas, tex = nil, nil
    if entrada.tipo == nil or entrada.tipo == "item" then atlas, tex = AtlasDoIcone(entrada) end
    if atlas ~= nil then
        w.icone:SetTexture(atlas, tex)
        w.icone:ScaleToSize(ICONE, ICONE)
        w.icone:Show()
    else
        w.icone:Hide()
    end
    -- setinha: fechado aponta para a direita, aberto para baixo
    if entrada.expansivel then
        if entrada._aberto then
            w.seta:SetTexture("images/global_redux.xml", "scrollbar_arrow_down.tex")
        else
            w.seta:SetTexture("images/global_redux.xml", "arrow2_right.tex")
        end
        w.seta:ScaleToSize(14, 14)
        w.seta:Show()
    else
        w.seta:Hide()
    end
    -- concorrentes (só nas linhas de combinação com empate)
    for k = 1, 3 do
        local id = entrada.rivais and entrada.rivais[k]
        local ra, rt = nil, nil
        if id then ra, rt = AtlasDoPrefab(id) end
        if ra then
            w.rivais[k]:SetTexture(ra, rt)
            w.rivais[k]:ScaleToSize(20, 20)
            w.rivais[k]:Show()
        else
            w.rivais[k]:Hide()
        end
    end
    -- fundo: combinações num tom um pouco mais escuro, para ficarem "dentro" do prato
    if entrada.tipo then w.fundo:SetTint(0.31, 0.24, 0.15, 0.20) else w.fundo:SetTint(0.31, 0.24, 0.15, 0.10) end
    local L = ctx.largura
    local tem_detalhe = entrada.detalhe ~= nil and entrada.detalhe ~= ""
    w.nome:SetTruncatedString(entrada.nome, w.texto_l, 40, true)
    -- Com ícones: mostra "2x [ícone]" e, depois deles, o texto extra (ex.: empate)
    local icones = entrada.icones
    -- Largura de cada "2x [ícone] Rótulo". Se não couber antes das colunas de status,
    -- os status (e a quantidade) sobem para a linha do nome e os ingredientes usam a
    -- linha de baixo inteira.
    local passos, precisa = {}, 0
    for k = 1, 4 do
        local ic = icones and icones[k]
        if ic then
            passos[k] = MINI_PASSO + (ic.rotulo and LarguraTexto(ic.rotulo) + 2 or 0)
            precisa = precisa + passos[k]
        end
    end
    local linha_l = w.texto_l
    local subir = precisa - 4 > w.texto_l
    if subir then linha_l = L - TEXTO_X0 - 12 end
    local n_minis, usado = 0, 0          -- usado: largura ocupada pelos ingredientes
    local x_mini = -L / 2 + TEXTO_X0 + 8
    for k = 1, 4 do
        local m, ic = w.minis[k], icones and icones[k]
        local atlas, t = nil, nil
        if ic then
            if ic.atlas then atlas, t = AtlasProprio(ic.atlas, ic.tex, ic.prefab) else atlas, t = AtlasDoPrefab(ic.prefab) end
        end
        if atlas and usado + passos[k] - 4 > linha_l then atlas = nil end   -- nunca passa da linha
        if atlas then
            m.n:SetString((ic.n or 0) > 0 and (ic.n .. "x") or "")
            m.img:SetTexture(atlas, t)
            m.img:ScaleToSize(MINI, MINI)
            if ic.rotulo then
                local larg = LarguraTexto(ic.rotulo)
                m.rot:SetString(ic.rotulo)
                m.rot:SetRegionSize(larg, 20)
                m.rot:SetPosition(31 + larg / 2, 0)
                m.rot:Show()
            else
                m.rot:Hide()
            end
            m:SetPosition(x_mini, -13)
            x_mini = x_mini + passos[k]
            usado = usado + passos[k]
            m:Show()
            n_minis = n_minis + 1
        else
            m:Hide()
        end
    end
    local y_dir = subir and 10 or 0
    if w.stat then
        for j, k in ipairs(STATS) do w.stat[k]:SetPosition(XStat(L, j), y_dir) end
    end
    w.qtd:SetPosition(L / 2 - 6 - QTD_L / 2, y_dir)
    local texto = entrada.detalhe
    local x0, largura = -L / 2 + TEXTO_X0, w.texto_l
    if n_minis > 0 then
        texto = entrada.extra
        x0, largura = x0 + usado + 6, linha_l - usado - 6
        tem_detalhe = true
    end
    w.nome:SetPosition(-L / 2 + TEXTO_X0 + w.texto_l / 2, tem_detalhe and 10 or 0)
    if texto ~= nil and texto ~= "" and largura > 20 then
        w.detalhe:SetRegionSize(largura, 20)
        w.detalhe:SetPosition(x0 + largura / 2, -12)
        w.detalhe:SetTruncatedString(texto, largura, 90, true)
        w.detalhe:Show()
    else
        w.detalhe:Hide()
    end
    w.qtd:SetString(entrada.qtd or "")
    w.entrada = entrada
    if w.stat then
        for _, k in ipairs(STATS) do w.stat[k]:SetString(entrada[k] or "") end
    end
end

---------------------------------------------------------------------------
-- dados = { abrir = índice da aba, abas = { {id, titulo, resumo, vazio, rodape, colunas, stats, itens}, ... } }
-- aba.busca = true mostra a caixa de busca (só a aba Todas usa)
-- aba.filtros (opcional) = { {id, rotulo}, ... } desenha checkboxes que filtram itens por e.grupo
-- cada item: { prefab|receita, nome, qtd, detalhe, vida, fome, sani, busca?, icones?, extra?, grupo? }
--   icones (opcional): { {prefab, n}, ... } desenhados como "2x [ícone]"; extra = texto depois deles
--   busca (opcional): lista de nomes de ingredientes que a busca também deve casar
local GeladeiraConteudo = Class(Widget, function(self, dados)
    Widget._ctor(self, "GeladeiraConteudo")
    self.dados = dados
    -- estado sobrevive quando a janela é recriada (ex.: ao marcar "Personagem")
    self.estado = dados.estado or { ordem = nil, filtro = "", fontes = "gc" }
    self.ordem = self.estado.ordem          -- nil = ordem padrão
    self.filtro = self.estado.filtro or ""
    self.expandido = {}     -- prato -> true (linhas abertas na aba Disponível)
    self.combos = {}        -- prato -> { lista = {...}, resto = N } (vindo do servidor)

    -- Pré-calcula o texto de busca e os números de cada item (uma vez só)
    for _, aba in ipairs(dados.abas) do
        for i, e in ipairs(aba.itens) do
            e._i = i
            e._nome = Normaliza(e.nome)
            e._texto = e._nome .. " " .. Normaliza(e.detalhe) .. " " .. Normaliza(table.concat(e.busca or {}, " "))
            e._exemplo = Normaliza(e.detalhe)
            e._vida, e._fome, e._sani = Numero(e.vida), Numero(e.fome), Numero(e.sani)
        end
    end

    -- Sem fundo escurecido e sem âncora própria: o painel lateral cuida da posição
    self.root = self:AddChild(Widget("root"))

    -- O painel é só o PERGAMINHO do livro de receitas (sem moldura escura em volta).
    -- self.janela mantém a escala de 70% e as coordenadas de antes.
    self.janela = self.root:AddChild(Widget("pergaminho_root"))
    self.janela:SetScale(ESCALA_JANELA)
    self.pergaminho = self.janela:AddChild(Image(ATLAS_LIVRO, "quagmire_recipe_menu_bg.tex"))
    self.pergaminho:ScaleToSize(JANELA_L, JANELA_A)

    -- Abas do livro de receitas, encaixadas na borda de cima do papel. Depois delas,
    -- uma aba estreita "X" que fecha o painel (não há mais botões embaixo).
    self.abas = {}
    local ABA_FECHAR_L = 46
    local MARGEM_ABAS = 24
    local passo_abas = (JANELA_L - MARGEM_ABAS - ABA_FECHAR_L) / math.max(#dados.abas, 1)
    local x0_abas = -(JANELA_L - MARGEM_ABAS) / 2
    -- a aba do livro tem 371 px; estreita para caber todas sem encavalar
    local escala_aba = math.min(0.42, (passo_abas + 6) / 371)
    -- Legibilidade: texto maior, com sombra escura (como os botões do jogo) e cores claras.
    -- Aba ativa quase branca; inativas douradas claras; mouse em cima, laranja-dourado.
    local function Aba(titulo, x, escala, tamanho, ao_clicar, largura)
        local t = self.janela:AddChild(ImageButton(ATLAS_LIVRO, "quagmire_recipe_tab_inactive.tex",
            nil, nil, nil, "quagmire_recipe_tab_active.tex"))
        t:SetNormalScale(escala, 0.6)
        t:SetFocusScale(escala + 0.02, 0.62)
        t:SetFont(HEADERFONT)
        t:SetTextSize(tamanho)
        t:SetText(titulo, true, { 1.5, -1.5 })
        -- se o texto passar da largura da aba, diminui a fonte até caber
        if largura and type(t.text) == "table" and t.text.GetRegionSize then
            local tam = tamanho
            while tam > 16 and t.text:GetRegionSize() > largura do
                tam = tam - 1
                t:SetTextSize(tam)
            end
        end
        t:SetTextColour(UICOLOURS.GOLD_CLICKABLE)
        t:SetTextFocusColour(UICOLOURS.GOLD_FOCUS)
        t:SetTextSelectedColour(UICOLOURS.GOLD_SELECTED)
        t:SetPosition(x, Y_ABAS)
        t:SetOnClick(ao_clicar)
        return t
    end
    for i, aba in ipairs(dados.abas) do
        self.abas[i] = Aba(aba.titulo, x0_abas + (i - 0.5) * passo_abas, escala_aba,
            #dados.abas > 3 and 22 or 24, function() self:MostrarAba(i) end, passo_abas - 12)
    end
    self.aba_fechar = Aba("X", x0_abas + #dados.abas * passo_abas + ABA_FECHAR_L / 2 + 2,
        (ABA_FECHAR_L + 6) / 371, 24, function() self:Fechar() end)

    -- Busca (filtra a aba atual enquanto digita)
    self.busca = self.janela:AddChild(TEMPLATES.StandardSingleLineTextEntry(self.filtro, LISTA_L - 10, 40, CHATFONT, 24,
        "Buscar nome ou ingrediente"))
    self.busca:SetPosition(0, Y_BUSCA)
    self.busca.textbox:SetTextLengthLimit(30)
    local function aplicar_busca()
        local txt = self.busca.textbox:GetString() or ""
        if txt ~= self.filtro then
            self.filtro = txt
            self.estado.filtro = txt
            self:Atualizar()
        end
    end
    self.busca.textbox.OnTextInputted = aplicar_busca
    self.busca.textbox.OnTextEntered = aplicar_busca

    -- Ordenação: "Ordenar:" + 4 ícones clicáveis. Inativos ficam apagados; o ativo fica
    -- forte (maior primeiro; no A-Z, ordem alfabética).
    -- Clicar no ativo volta para a ordem padrão.
    self.rotulo_ordem = self.janela:AddChild(Text(CHATFONT, 20, "Ordenar:", COR_TEXTO))
    self.rotulo_ordem:SetHAlign(ANCHOR_RIGHT)
    self.rotulo_ordem:SetRegionSize(140, 30)          -- cabe "Atualizando..." (alinhado à direita)
    self.rotulo_ordem:SetPosition(-LISTA_L / 2 + 20, Y_CONTROLES)
    self.botoes_ordem = {}
    for j, o in ipairs(ORDENS) do
        local b = self.janela:AddChild(ImageButton(o.icone[1], o.icone[2]))
        -- Mesma textura com e sem foco: sem isto o ImageButton aplica a escala de foco
        -- sobre o tamanho ORIGINAL da textura (ícone gigante) e, ao sair, volta para
        -- escala 1 (continua gigante). Com ignore_standard_scaling ele usa
        -- tamanho forçado x escala. ForceImageSize por último: SetNormalScale mexe na imagem.
        b.ignore_standard_scaling = true
        b:SetNormalScale(1, 1)
        b:SetFocusScale(1.15, 1.15)
        b:ForceImageSize(ICONE_ORDEM, ICONE_ORDEM)
        b:SetOnClick(function()
            if self.ordem == j then self.ordem = nil else self.ordem = j end   -- (x and nil or j) não funciona em Lua
            self.estado.ordem = self.ordem
            self:MarcarOrdem()
            self:Atualizar()
        end)
        b:SetPosition(-58 + (j - 1) * ICONE_PASSO, Y_CONTROLES)
        self.botoes_ordem[j] = b
    end
    self:MarcarOrdem()

    -- Atualizar: ícone no fim da linha "Ordenar:" (só nas abas que vêm do servidor:
    -- Itens e Disponível). Enquanto recalcula, o rótulo "Ordenar:" vira "Atualizando...".
    self.botao_atualizar = self.janela:AddChild(ImageButton("images/button_icons.xml", "update.tex"))
    self.botao_atualizar.ignore_standard_scaling = true
    self.botao_atualizar:SetNormalScale(1, 1)
    self.botao_atualizar:SetFocusScale(1.15, 1.15)
    self.botao_atualizar:ForceImageSize(ICONE_ORDEM, ICONE_ORDEM)
    self.botao_atualizar:SetHoverText("Atualizar", { offset_y = 40 })
    self.botao_atualizar:SetOnClick(function()
        if dados.ao_atualizar then dados.ao_atualizar(self.aba_indice) end
    end)
    self.botao_atualizar:SetPosition(LISTA_L / 2 - 4, Y_CONTROLES)

    -- Fontes (só na aba Itens): de onde vêm os itens
    self.fontes = self.janela:AddChild(Widget("fontes"))
    self.fontes:SetPosition(-LISTA_L / 2 + 20, Y_CHECKS)
    local function check(j, letra, rotulo)
        local x, y = PosCheck(j)
        local marcado = (self.estado.fontes or "gc"):find(letra, 1, true) ~= nil
        local c = self.fontes:AddChild(TEMPLATES.StandardCheckbox(function()
            return self:AlternarFonte(letra)
        end, 30, marcado))
        c:SetPosition(x, y)
        -- contagem vinda do servidor: recipientes achados (ou tipos de comida, no Personagem)
        local n = dados.contagem_fontes and dados.contagem_fontes[letra]
        local t = self.fontes:AddChild(Text(CHATFONT, 20, rotulo .. Contagem(n), COR_TEXTO))
        t:SetHAlign(ANCHOR_LEFT)
        t:SetRegionSize(160, 30)
        t:SetPosition(x + 100, y)
    end
    -- g = geladeiras (e Caixa de Sal), c = Chester, b = Bolsa Térmica, p = personagem
    check(1, "g", "Geladeiras")
    check(2, "c", "Chester")
    check(3, "b", "Bolsa Térmica")
    check(4, "p", "Personagem")
    self.fontes:Hide()


    -- (sem rodapé: a lista ocupa até o fim do papel)

    -- Cabeçalho das colunas Vida / Fome / Sanidade (só nas abas que têm atributos)
    self.cabecalho = self.janela:AddChild(Widget("cabecalho"))
    self.cabecalho:SetPosition(-10, Y_CABECALHO)
    local rotulos = { vida = "Vida", fome = "Fome", sani = "Sanid." }
    for j, k in ipairs(STATS) do
        local t = self.cabecalho:AddChild(Text(CHATFONT, 16, rotulos[k], COR_STAT[k]))
        t:SetPosition(XStat(LISTA_L, j), 0)
    end
    self.cabecalho:Hide()

    self.vazio = self.janela:AddChild(Text(CHATFONT, 24, "", COR_TEXTO))
    self.vazio:SetRegionSize(JANELA_L - 60, 160)
    self.vazio:SetPosition(0, Y_LISTA)
    self.vazio:EnableWordWrap(true)

    self:MostrarAba(dados.abrir or 1)
end)

function GeladeiraConteudo:MostrarAba(i)
    local aba = self.dados.abas[i]
    if aba == nil then return end
    self.aba = aba
    self.aba_atual = aba.id
    self.aba_indice = i
    self:Destacar(nil)                     -- trocou de aba: apaga o destaque no mundo
    for j, t in ipairs(self.abas) do
        if j == i then t:Select(); t:MoveToFront() else t:Unselect() end
    end
    if aba.id == "itens" then self.fontes:Show() else self.fontes:Hide() end
    if aba.busca then self.busca:Show() else self.busca:Hide() end   -- busca só onde a aba pede (Todas)
    self.rotulo_ordem:SetString("Ordenar:")
    if aba.id == "itens" or aba.id == "disponivel" then self.botao_atualizar:Show() else self.botao_atualizar:Hide() end

    -- Layout de cima para baixo: cada linha só ocupa espaço se a aba tem aquilo.
    -- y = centro da próxima linha livre.
    local y = Y_CONTROLES
    if aba.sem_ordem then
        self.rotulo_ordem:Hide()
        for _, b in ipairs(self.botoes_ordem) do b:Hide() end
    else
        self.rotulo_ordem:Show()
        for _, b in ipairs(self.botoes_ordem) do b:Show() end
        y = y - ALTURA_ORDEM
    end
    if aba.busca then
        self.busca:SetPosition(0, y)
        y = y - 42
    end
    local n_checks = (aba.id == "itens" and 4) or (aba.filtros and #aba.filtros) or 0
    self.y_checks = y
    self.fontes:SetPosition(-LISTA_L / 2 + 20, y)
    if n_checks > 0 then y = y - (math.ceil(n_checks / 2) - 1) * CHECK_LINHA - 34 end
    local topo
    if aba.stats then
        self.cabecalho:SetPosition(-10, y)
        topo = y - 14
    elseif n_checks > 0 or aba.busca or not aba.sem_ordem then
        topo = y + 14
    else
        topo = TOPO_SEM_ORDEM
    end
    -- quantas linhas cabem até o fim do papel
    self.linhas_visiveis = math.max(3, math.floor((topo - Y_FUNDO) / CELULA_A))
    self.topo_lista = topo
    self.y_lista = topo - self.linhas_visiveis * CELULA_A / 2
    self.vazio:SetPosition(0, self.y_lista)
    self:CriarFiltrosDeGrupo(aba)

    if self.lista ~= nil then
        self.lista:Kill()
        self.lista = nil
    end
    self.ctx_lista = { largura = nil, stats = nil, ao_focar = function(e) self:Focar(e) end,
                       ao_clicar = function(e) return self:AlternarCombos(e) end }
    local colunas = aba.colunas or 1
    local largura = math.floor(LISTA_L / colunas)
    self.ctx_lista.largura = largura
    self.ctx_lista.stats = aba.stats and colunas == 1
    self.lista = self.janela:AddChild(TEMPLATES.ScrollingGrid({}, {
        scroll_context   = self.ctx_lista,
        widget_width     = largura,
        widget_height    = CELULA_A,
        num_columns      = colunas,
        num_visible_rows = self.linhas_visiveis,
        item_ctor_fn     = CriarCelula,
        apply_fn         = AplicarCelula,
        scrollbar_offset = 20,
        scrollbar_height_offset = -40,
        force_peek       = true,
    }))
    self.lista:SetPosition(-10, self.y_lista)
    self:Atualizar()
end

-- Aplica busca + ordenação na aba atual
function GeladeiraConteudo:Atualizar(manter_rolagem)
    local aba = self.aba
    local q = aba.busca and Normaliza(self.filtro):gsub("^%s+", ""):gsub("%s+$", "") or ""
    local itens = {}
    local desligados = self.estado.grupos_off or {}
    for _, e in ipairs(aba.itens) do
        if (e.grupo == nil or not desligados[e.grupo])
            and (q == "" or e._texto:find(q, 1, true)) then
            itens[#itens + 1] = e
        end
    end

    local ordem = self.ordem and ORDENS[self.ordem].id or "padrao"
    if aba.sem_ordem then ordem = nil end                  -- Legenda: fica na ordem em que foi montada
    local campo = (ordem == "vida" and "_vida") or (ordem == "fome" and "_fome") or (ordem == "sani" and "_sani") or nil
    if ordem ~= nil then table.sort(itens, function(a, b)
        -- Com busca: quem tem o ingrediente no exemplo/detalhe vem antes de quem só "aceita"
        if q ~= "" then
            local ea, eb = a._nome:find(q, 1, true) or a._exemplo:find(q, 1, true), b._nome:find(q, 1, true) or b._exemplo:find(q, 1, true)
            if (ea ~= nil) ~= (eb ~= nil) then return ea ~= nil end
        end
        if campo then
            local va, vb = a[campo], b[campo]
            if va ~= vb then
                if va == nil then return false end
                if vb == nil then return true end
                return va > vb
            end
        elseif ordem == "nome" then
            if a._nome ~= b._nome then return a._nome < b._nome end
        end
        return a._i < b._i
    end) end

    -- Contagem ao lado de cada checkbox de grupo: quantas receitas daquele grupo
    -- (respeitando a busca, mas não os próprios checkboxes)
    if aba.filtros and self.rotulos_grupo then
        local por_grupo = {}
        for _, e in ipairs(aba.itens) do
            if e.grupo and (q == "" or e._texto:find(q, 1, true)) then
                por_grupo[e.grupo] = (por_grupo[e.grupo] or 0) + 1
            end
        end
        for _, f in ipairs(aba.filtros) do
            local r = self.rotulos_grupo[f.id]
            if r then r:SetString(f.rotulo .. Contagem(por_grupo[f.id] or 0)) end
        end
    end

    if #itens == 0 then
        self.lista:Hide()
        self.cabecalho:Hide()
        self.vazio:SetString(q ~= "" and "Nada encontrado com essa busca." or (aba.vazio or "Nada por aqui."))
        self.vazio:Show()
        self.default_focus = self.busca
        return
    end
    self.vazio:Hide()
    if aba.stats then self.cabecalho:Show() else self.cabecalho:Hide() end
    self.lista:Show()
    self.lista:SetItemsData(self:ComCombinacoes(itens))
    if not manter_rolagem then self.lista:ResetScroll() end
    self.default_focus = self.lista
end

-- Prato da panela na aba Disponível: dá para abrir e ver as combinações
-- Linhas que abrem com um clique:
--   * prato da panela na aba Disponível (as combinações vêm do servidor);
--   * linha com e.filhos (ex.: categoria da Legenda), que já traz a lista pronta.
local function Expansivel(aba, e)
    if e.tipo ~= nil then return false end
    if e.filhos ~= nil then return #e.filhos > 0 end
    return aba.id == "disponivel" and e.grupo == "panela" and e.qtd ~= nil and e.qtd ~= ""
end

local function ChaveAberta(e) return e.chave or e.prefab end

-- Lista final: cada prato aberto ganha, logo abaixo, uma linha por combinação
-- (da garantida para a menos provável), ou "Carregando..." enquanto o servidor responde.
function GeladeiraConteudo:ComCombinacoes(itens)
    local final = {}
    for _, e in ipairs(itens) do
        final[#final + 1] = e
        e.expansivel = Expansivel(self.aba, e)
        e._aberto = e.expansivel and self.expandido[ChaveAberta(e)] or nil
        if e._aberto and e.filhos ~= nil then
            for _, f in ipairs(e.filhos) do
                final[#final + 1] = { tipo = "item", prefab = f.prefab, nome = f.nome, detalhe = f.detalhe }
            end
        elseif e._aberto then
            local cs = self.combos[e.prefab]
            if cs == nil then
                final[#final + 1] = { tipo = "aviso", nome = "Carregando combinações..." }
            else
                for _, c in ipairs(cs.lista) do
                    local pct = math.floor(c.chance * 100 + 0.5)
                    final[#final + 1] = {
                        tipo = "combo", icones = c.icones, rivais = c.rivais,
                        nome = pct >= 100 and "Garantido" or "Empata com",
                        qtd = pct .. "%",
                    }
                end
                if cs.resto > 0 then
                    final[#final + 1] = { tipo = "aviso", nome = string.format("... e mais %d combinações", cs.resto) }
                end
            end
        end
    end
    return final
end

-- Clique numa linha: prato da panela abre/fecha; na 1ª vez pede as combinações
function GeladeiraConteudo:AlternarCombos(e)
    if not (e and e.expansivel) then return false end
    local chave = ChaveAberta(e)
    if self.expandido[chave] then
        self.expandido[chave] = nil
    else
        self.expandido[chave] = true
        if e.filhos == nil and self.combos[e.prefab] == nil and self.dados.ao_pedir_combos then
            self.dados.ao_pedir_combos(e.prefab)
        end
    end
    self:Atualizar(true)
    return true
end

-- Chegaram do servidor as combinações de um prato
function GeladeiraConteudo:ReceberCombos(prato, lista, resto)
    self.combos[prato] = { lista = lista, resto = resto or 0 }
    if self.expandido[prato] and self.aba and self.aba.id == "disponivel" then self:Atualizar(true) end
end

function GeladeiraConteudo:MarcarOrdem()
    for j, b in ipairs(self.botoes_ordem) do
        if j == self.ordem then
            b:SetImageNormalColour(1, 1, 1, 1)        -- ativo: forte
        else
            b:SetImageNormalColour(1, 1, 1, 0.45)     -- inativo: apagado
        end
    end
end

-- Mouse entrou (e) ou saiu (nil) de um item: destaque no mundo das geladeiras que o têm
function GeladeiraConteudo:Focar(e)
    local id = self.aba and self.aba.id
    if id == "itens" or id == "disponivel" then self:Destacar(e) end
end

-- Destaca as geladeiras/Chester/Bolsa que têm o item. Na aba Itens é o próprio item;
-- na Disponível são os ingredientes da receita (os ícones pequenos da linha).
function GeladeiraConteudo:Destacar(e)
    if self.dados.ao_destacar == nil then return end
    if e == nil then return self.dados.ao_destacar(nil) end
    local prefabs = {}
    if e.icones ~= nil then
        for _, ic in ipairs(e.icones) do prefabs[#prefabs + 1] = ic.prefab end
    elseif e.prefab ~= nil then
        prefabs[1] = e.prefab
    end
    self.dados.ao_destacar(prefabs)
end

-- Checkboxes de grupo (ex.: aba Todas: Panela / Fogueira / Varal). Filtram no cliente,
-- sem pedir nada ao servidor. aba.filtros = { {id, rotulo}, ... }; cada item tem e.grupo.
function GeladeiraConteudo:CriarFiltrosDeGrupo(aba)
    if self.grupos ~= nil then
        self.grupos:Kill()
        self.grupos = nil
    end
    self.rotulos_grupo = nil
    if aba.filtros == nil then return end
    self.estado.grupos_off = self.estado.grupos_off or {}
    local off = self.estado.grupos_off
    self.grupos = self.janela:AddChild(Widget("grupos"))
    self.rotulos_grupo = {}
    self.grupos:SetPosition(-LISTA_L / 2 + 20, self.y_checks or Y_CHECKS)
    for j, f in ipairs(aba.filtros) do
        local x, y = PosCheck(j)
        local c = self.grupos:AddChild(TEMPLATES.StandardCheckbox(function()
            local ligados = 0
            for _, g in ipairs(aba.filtros) do if not off[g.id] then ligados = ligados + 1 end end
            if not off[f.id] and ligados == 1 then return true end   -- deixa pelo menos um
            off[f.id] = not off[f.id] or nil
            self:Atualizar()
            return not off[f.id]
        end, 30, not off[f.id]))
        c:SetPosition(x, y)
        local t = self.grupos:AddChild(Text(CHATFONT, 20, f.rotulo, COR_TEXTO))
        t:SetHAlign(ANCHOR_LEFT)
        t:SetRegionSize(160, 30)
        t:SetPosition(x + 100, y)
        self.rotulos_grupo[f.id] = t
    end
end

-- Liga/desliga uma fonte ("g" geladeiras, "p" personagem) e pede os dados de novo.
-- Devolve o novo estado do checkbox (pelo menos uma fonte fica marcada).
function GeladeiraConteudo:AlternarFonte(letra)
    local f = self.estado.fontes or "gc"
    local tem = f:find(letra, 1, true) ~= nil
    local nova = tem and f:gsub(letra, "") or (f .. letra)
    if nova == "" then return true end         -- não deixa desmarcar a última
    self.estado.fontes = nova
    self:AvisarCarregando()
    if self.dados.ao_mudar_fontes then self.dados.ao_mudar_fontes(nova, self.aba_indice) end
    return not tem
end

-- Ao sumir (fechou o painel ou chegaram dados novos), apaga o destaque no mundo
function GeladeiraConteudo:Kill()
    self:Destacar(nil)
    Widget.Kill(self)
end

function GeladeiraConteudo:Fechar()
    if self.dados.ao_fechar then self.dados.ao_fechar() end
end

-- "Atualizando..." enquanto o servidor recalcula (botão Atualizar ou troca de fonte)
function GeladeiraConteudo:AvisarCarregando()
    self.botao_atualizar:Hide()
    self.rotulo_ordem:SetString("Atualizando...")
    self.rotulo_ordem:Show()
end

return GeladeiraConteudo
