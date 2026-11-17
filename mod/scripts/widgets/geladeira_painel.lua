-- Painel lateral do mod Ratatouille, no estilo do menu de craft do jogo.
-- O painel desliza da borda DIREITA (o menu de craft usa a esquerda). Ele é aberto por
-- um botão-gatilho com o ícone da geladeira, que fica por padrão no canto inferior
-- direito, logo acima do botão do mapa, e pode ser ARRASTADO para qualquer lugar
-- (a posição fica salva). Também abre/fecha com L/K.
-- É um Widget do HUD, não uma tela modal: o jogador continua andando, atacando e
-- interagindo com o mundo com o painel aberto. Só a caixa de busca segura o teclado,
-- e só enquanto se digita nela (o jogo bloqueia o movimento quando há texto sendo
-- editado: PlayerHud:HasInputFocus).
local Widget     = require "widgets/widget"
local TEMPLATES  = require "widgets/redux/templates"
local Image      = require "widgets/image"
local Text       = require "widgets/text"
local GeladeiraConteudo = require "widgets/geladeira_conteudo"

-- Medidas no espaço do right_root do HUD. O painel é só o pergaminho (470 x 640 unidades,
-- encolhido para 70%), sem moldura em volta: a largura visível é a do próprio papel.
local PERGAMINHO_L    = 470
local PERGAMINHO_A    = 640
local ESCALA          = 0.77         -- era 0.7; aumentado 10% (igual ao geladeira_conteudo)
local LARGURA_VISIVEL = PERGAMINHO_L * ESCALA
local MARGEM          = 30           -- espaço até a borda direita da tela
local DESLOCAMENTO_Y  = -35          -- abaixo do meio: as abas não encostam no minimapa/relógio
local TEMPO_ANIMACAO  = 0.25         -- igual ao menu de craft

-- Gatilho: no bottomright_root (mesmo canto do botão do mapa, que fica em (-60, 70))
local GATILHO_PADRAO  = Vector3(-60, 160, 0)
local GATILHO_LADO    = 64
local ARRASTO_MINIMO  = 8            -- pixels: menos que isso é clique, não arrasto
local ARQUIVO_POSICAO = "ratatouille_botao"

local GeladeiraPainel = Class(Widget, function(self, opcoes)
    Widget._ctor(self, "GeladeiraPainel")
    self.opcoes = opcoes               -- { pedir = function(aba), raiz_gatilho = widget }
    self.aberto = false

    -- Fechado: ui_root em x=0 com o conteúdo além da borda direita, e ESCONDIDO
    -- (nada aparece na tela). Aberto: aparece e desliza para a esquerda.
    self.pos_fechado = Vector3(0, DESLOCAMENTO_Y, 0)
    self.pos_aberto = Vector3(-(LARGURA_VISIVEL + 2 * MARGEM), DESLOCAMENTO_Y, 0)
    self.x_conteudo = LARGURA_VISIVEL / 2 + MARGEM

    self.ui_root = self:AddChild(Widget("geladeira_ui_root"))
    self.ui_root:SetPosition(self.pos_fechado:Get())
    self.ui_root:Hide()

    -- Enquanto os primeiros dados não chegam: o mesmo pergaminho com "Calculando..."
    self.carregando = self.ui_root:AddChild(Widget("carregando"))
    self.carregando:SetPosition(self.x_conteudo, 0)
    self.carregando:SetScale(ESCALA)
    local papel = self.carregando:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_menu_bg.tex"))
    papel:ScaleToSize(PERGAMINHO_L, PERGAMINHO_A)
    self.carregando:AddChild(Text(HEADERFONT, 28, "Calculando...", UICOLOURS.BROWN_DARK))

    self:CriarGatilho(opcoes.raiz_gatilho or self)
end)

---------------------------------------------------------------------------
-- Gatilho arrastável
---------------------------------------------------------------------------
function GeladeiraPainel:CriarGatilho(raiz)
    local atlas = GetInventoryItemAtlas("icebox.tex", true)
    local g = raiz:AddChild(TEMPLATES.StandardButton(nil, atlas and "" or "Gel.",
        { GATILHO_LADO, GATILHO_LADO }, atlas and { atlas, "icebox.tex" } or nil))
    g:SetPosition(GATILHO_PADRAO:Get())
    g:SetHoverText("Geladeira (L / K) - arraste para mover", { offset_y = 50 })
    self.gatilho = g

    -- Clique abre; segurar e mover arrasta. O botão trata o próprio controle de
    -- "aceitar" (clique esquerdo) para distinguir as duas coisas.
    g.OnControl = function(_, control, down)
        if control ~= CONTROL_ACCEPT then return false end
        if down then self:ComecarArrasto() else self:TerminarArrasto() end
        return true
    end

    self:CarregarPosicaoGatilho()
end

-- Quantos pixels da tela valem 1 unidade do HUD neste canto (resolução + tamanho do HUD).
-- Medido na hora, comparando a posição na tela com a posição local do próprio gatilho.
function GeladeiraPainel:PixelsPorUnidade()
    local g, pai = self.gatilho, self.gatilho.parent
    local local_x = g:GetPosition().x
    if pai ~= nil and math.abs(local_x) > 1 then
        local medido = (g:GetWorldPosition().x - pai:GetWorldPosition().x) / local_x
        if medido > 0.05 then return medido end
    end
    local w, h = TheSim:GetScreenSize()
    return math.min(w / RESOLUTION_X, h / RESOLUTION_Y, MAX_HUD_SCALE)   -- plano B
end

function GeladeiraPainel:ComecarArrasto()
    if self.arrasto ~= nil then return end
    local mx, my = TheInput:GetScreenPosition():Get()
    local pos = self.gatilho:GetPosition()
    self.arrasto = { mx = mx, my = my, x = pos.x, y = pos.y, escala = self:PixelsPorUnidade(), moveu = false }
    self.arrasto.mover = TheInput:AddMoveHandler(function(x, y)
        local a = self.arrasto
        if a == nil then return end
        if not a.moveu and math.abs(x - a.mx) + math.abs(y - a.my) < ARRASTO_MINIMO then return end
        a.moveu = true
        self.gatilho:SetPosition(self:LimitarNaTela(a.x + (x - a.mx) / a.escala, a.y + (y - a.my) / a.escala))
    end)
    -- Soltar o botão em qualquer lugar termina o arrasto (o mouse pode sair de cima do botão)
    self.arrasto.soltar = TheInput:AddMouseButtonHandler(function(botao, apertado)
        if botao == MOUSEBUTTON_LEFT and not apertado then self:TerminarArrasto() end
    end)
end

function GeladeiraPainel:TerminarArrasto()
    local a = self.arrasto
    if a == nil then return end
    self.arrasto = nil
    if a.mover then a.mover:Remove() end
    if a.soltar then a.soltar:Remove() end
    if a.moveu then
        self:SalvarPosicaoGatilho()
    else
        if self.aberto then self:Fechar() else self:Abrir(self.ultima_aba or 1) end
    end
end

-- Mantém o gatilho inteiro dentro da tela (origem do canto: inferior direito)
function GeladeiraPainel:LimitarNaTela(x, y)
    local w, h = TheSim:GetScreenSize()
    local escala = self:PixelsPorUnidade()
    local meio = GATILHO_LADO / 2
    x = math.max(-(w / escala) + meio, math.min(-meio, x))
    y = math.max(meio, math.min((h / escala) - meio, y))
    return x, y, 0
end

function GeladeiraPainel:SalvarPosicaoGatilho()
    local p = self.gatilho:GetPosition()
    TheSim:SetPersistentString(ARQUIVO_POSICAO, string.format("%.1f,%.1f", p.x, p.y), false)
end

function GeladeiraPainel:CarregarPosicaoGatilho()
    TheSim:GetPersistentString(ARQUIVO_POSICAO, function(ok, texto)
        if not ok or texto == nil or self.gatilho == nil then return end
        local x, y = texto:match("^(%-?[%d%.]+),(%-?[%d%.]+)$")
        if x and y then self.gatilho:SetPosition(self:LimitarNaTela(tonumber(x), tonumber(y))) end
    end)
end

---------------------------------------------------------------------------
-- Abrir / fechar
---------------------------------------------------------------------------
function GeladeiraPainel:EstaAberto()
    return self.aberto
end

local function Som(nome)
    if TheFocalPoint ~= nil and TheFocalPoint.SoundEmitter ~= nil then
        TheFocalPoint.SoundEmitter:PlaySound(nome)
    end
end

-- Abre na aba indicada e pede dados novos ao servidor (o mundo pode ter mudado)
function GeladeiraPainel:Abrir(aba)
    self.ultima_aba = aba or self.ultima_aba or 1
    if not self.aberto then
        self.aberto = true
        self.gatilho:Hide()                -- aberto, o gatilho não fica por cima de nada
        if self.gatilho.hovertext_root ~= nil then self.gatilho.hovertext_root:Hide() end   -- dica não fica presa
        self.ui_root:Show()
        self.ui_root:MoveTo(self.ui_root:GetPosition(), self.pos_aberto, TEMPO_ANIMACAO)
        Som("dontstarve/HUD/craft_open")
    end
    if self.conteudo ~= nil then
        self.conteudo:MostrarAba(self.ultima_aba)
        self.conteudo:AvisarCarregando()
    end
    self.opcoes.pedir(self.ultima_aba)
end

function GeladeiraPainel:Fechar()
    if not self.aberto then return end
    self.aberto = false
    self:ClearFocus()                      -- solta a caixa de busca, se estiver digitando
    if self.conteudo ~= nil then self.conteudo:Destacar(nil) end   -- apaga o destaque no mundo
    self.gatilho:Show()
    self.ui_root:MoveTo(self.ui_root:GetPosition(), self.pos_fechado, TEMPO_ANIMACAO, function()
        -- terminou de sair: esconde tudo (nada do painel fica visível na borda)
        if not self.aberto then self.ui_root:Hide() end
    end)
    Som("dontstarve/HUD/craft_close")
end

-- Teclas L/K: fechado abre; aberto na mesma aba fecha; aberto em outra aba troca
function GeladeiraPainel:Alternar(aba)
    if not self.aberto then
        self:Abrir(aba)
    elseif self.conteudo ~= nil and self.conteudo.aba_indice ~= aba and self.conteudo.dados.abas[aba] ~= nil then
        self.ultima_aba = aba
        self.conteudo:MostrarAba(aba)
    else
        self:Fechar()
    end
end

-- Chegaram dados do servidor: troca o conteúdo (busca, ordem e filtros vêm do estado compartilhado)
function GeladeiraPainel:MostrarDados(d)
    d.ao_fechar = function() self:Fechar() end
    d.ao_atualizar = function(aba)
        if self.conteudo ~= nil then self.conteudo:AvisarCarregando() end
        self.opcoes.pedir(aba or self.ultima_aba or 1)
    end
    if self.conteudo ~= nil then self.conteudo:Kill() end
    if self.carregando ~= nil then
        self.carregando:Kill()
        self.carregando = nil
    end
    self.conteudo = self.ui_root:AddChild(GeladeiraConteudo(d))
    self.conteudo:SetPosition(self.x_conteudo, 0)
    self.ultima_aba = self.conteudo.aba_indice
end

-- O gatilho mora em outra raiz do HUD; quando o painel morre, ele vai junto
function GeladeiraPainel:Kill()
    if self.arrasto ~= nil then self:TerminarArrasto() end
    if self.gatilho ~= nil then self.gatilho:Kill(); self.gatilho = nil end
    Widget.Kill(self)
end

return GeladeiraPainel
