name = "Ratatouille"
description = [[Seu livro de receitas ao lado da tela. Mostra o que tem nas geladeiras, Chester,
Bolsa Térmica e no personagem, e o que dá para cozinhar com isso: panela, fogueira e varal.

Itens: tudo o que você guardou, com vida, fome e sanidade.
Disponível: pratos que dá para fazer agora e quantas panelas.
Todas: todas as receitas do jogo, com busca por ingrediente.
Legenda: o que significa cada selo de categoria.

L abre em Itens, K em Disponível; a mesma tecla fecha. Você continua andando com ele aberto.]]
author = "Marcos"
-- Durante o desenvolvimento NÃO mude a versão com o mundo aberto: o c_reset() derruba
-- o mundo (SERVER_MODS_NOT_ON_WORKSHOP) quando a versão no disco difere da carregada.
-- Troque só entre lançamentos, com o jogo fechado.
version = "1.0.0"
api_version = 10

-- ícone na lista de mods (gerado por ferramentas/gerar_icones.py)
icon_atlas = "modicon.xml"
icon = "modicon.tex"

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false

-- O cliente precisa do mod (tecla + exibição) e o servidor também (leitura das geladeiras)
all_clients_require_mod = true
client_only_mod = false

server_filter_tags = { "utility", "icebox" }

-- modinfo.lua roda num ambiente isolado: sem ipairs/pairs/string/table.
-- Use apenas Lua puro (for numérico, #, ..).
local key_names = { "L", "K", "J", "O", "P", "G", "H", "F1", "F2", "F3", "F4", "F5" }
local keys = {}
for i = 1, #key_names do
    keys[i] = { description = key_names[i], data = "KEY_" .. key_names[i] }
end

configuration_options = {
    {
        name = "key",
        label = "Tecla",
        hover = "Tecla que lista os itens das geladeiras.",
        options = keys,
        default = "KEY_L",
        client = true,
    },
    {
        name = "key_receitas",
        label = "Tecla das receitas",
        hover = "Tecla que abre a janela na aba Disponível.",
        options = keys,
        default = "KEY_K",
        client = true,
    },
    {
        name = "display",
        label = "Mostrar em",
        hover = "Onde mostrar a lista.",
        options = {
            { description = "Janela", data = "janela" },
            { description = "Chat",   data = "chat" },
        },
        default = "janela",
        client = true,
    },
    {
        name = "range",
        label = "Alcance",
        hover = "Quais geladeiras contar.",
        options = {
            { description = "Mundo todo", data = 0 },
            { description = "Perto (30)",  data = 30 },
            { description = "Base (80)",   data = 80 },
        },
        default = 0,
    },
    {
        name = "include_saltbox",
        label = "Incluir Caixa de Sal",
        options = {
            { description = "Sim", data = true },
            { description = "Não", data = false },
        },
        default = true,
    },
}
