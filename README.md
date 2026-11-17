# 🐀 Ratatouille

**O livro de receitas que fica ao lado da tela no Don't Starve Together.**

Ratatouille olha suas geladeiras, o Chester, a Bolsa Térmica e o inventário do personagem e
responde a pergunta de todo fim de tarde: *"o que dá para cozinhar com o que eu tenho?"*

O painel abre na lateral direita, como o menu de craft, e **não pausa nem prende o personagem**:
você continua andando, colhendo e cozinhando com ele aberto.

---

## ✨ O que ele faz

| Aba | O que mostra |
|---|---|
| **Itens** | Tudo o que está guardado, somado de todas as geladeiras, com vida, fome e sanidade. Passe o mouse num item e as geladeiras que têm ele **brilham no mundo**. |
| **Disponível** | Os pratos que dá para fazer **agora**: panela, fogueira e varal. Mostra **quantas panelas** dá para cozinhar com o estoque. Clique num prato para ver **todas as combinações**, da garantida para a menos provável, com os pratos que podem "roubar" a vez. |
| **Todas** | As receitas do jogo (panela, fogueira, varal e as do Warly), com **busca por ingrediente**. Os ingredientes aparecem como **selos de categoria** (qualquer carne, qualquer legume…) quando qualquer item daquele tipo serve. |
| **Legenda** | O que significa cada selo. Clique numa categoria para ver todos os itens que entram nela. |

Também tem:

- **Filtros** por fonte (Geladeiras, Chester, Bolsa Térmica, Personagem) e por tipo (Panela, Fogueira, Varal, Warly);
- **Ordenação** por vida, fome, sanidade ou nome;
- **Reconhece o Warly**: usa o Caldeirão Portátil e as receitas exclusivas dele;
- **Botão arrastável** para abrir o painel, que lembra onde você o deixou.

As regras da panela **não são copiadas à mão**: o mod usa o próprio `cooking.lua` do jogo, então
prioridades, pesos e empates são exatamente os do jogo.

## 🎮 Como usar

| Tecla | Ação |
|---|---|
| **L** | Abre o painel na aba **Itens** (aperte de novo para fechar) |
| **K** | Abre o painel na aba **Disponível** |

As teclas podem ser trocadas nas configurações do mod. Também dá para mostrar a lista no **chat**
em vez do painel.

### Configurações

| Opção | O que faz |
|---|---|
| Tecla / Tecla das receitas | Quais teclas abrem o painel |
| Mostrar em | Painel lateral ou chat |
| Alcance | Mundo todo, perto (30) ou só a base (80) |
| Incluir Caixa de Sal | Conta a Caixa de Sal junto com as geladeiras |

### Desempenho

O mod roda no **servidor** e divide o trabalho pesado em pedacinhos de no máximo ~4 ms por frame,
então o jogo não engasga nem com geladeiras lotadas. Os detalhes estão em
[`docs/desempenho_14ms_para_4ms.md`](docs/desempenho_14ms_para_4ms.md).

## 📦 Instalação

**Pela Steam Workshop** (recomendado): inscreva-se na página do mod e ative-o no seu mundo.
<!-- TODO: link da Workshop quando for publicado -->

**Manual** (para testar a versão do GitHub): copie a pasta [`mod/`](mod) para
`Don't Starve Together/mods/` com o nome `Ratatouille` e ative-a nos mods do mundo.

> O mod precisa estar ativo no servidor e nos jogadores (`all_clients_require_mod`). Num mundo
> com servidor dedicado, coloque-o também no `dedicated_server_mods_setup.lua`.

## 🧪 Rodando os testes

Os testes rodam **fora do jogo**, usando os scripts reais do DST num Lua 5.1 (via
[lupa](https://github.com/scoder/lupa)). Eles conferem o fluxo do servidor (leitura das
geladeiras, filtros, receitas, combinações, quantidade de panelas) e a lógica da janela (abas,
busca, ordem, colapsos, layout).

Você precisa de:

- o **Don't Starve Together** instalado (os testes leem `data/databundles/scripts.zip`);
- **Python 3.10+** e o [**uv**](https://docs.astral.sh/uv/).

```bash
# na raiz do repositório
uv run --no-project --with lupa python testes/rodar.py               # todos os testes
uv run --no-project --with lupa python testes/rodar.py --desempenho  # mede o pior caso
```

Na primeira execução os scripts do jogo são extraídos para `testes/scripts_do_jogo/`
(~280 MB, ignorada pelo git). O jogo é encontrado nos lugares comuns da Steam; se o seu
estiver em outro lugar, informe a pasta:

```bash
DST_DIR="/caminho/para/Don't Starve Together" uv run --no-project --with lupa python testes/rodar.py
```

O comando termina com `TUDO OK` em cada arquivo (e código de saída 0) quando tudo passa.

### Regerando os dados e os ícones

Os arquivos em `mod/scripts/geladeira_*.lua` e `mod/images/` são **gerados** a partir do jogo
pelas ferramentas em [`ferramentas/`](ferramentas). Rode de novo quando uma atualização do DST
mudar receitas:

```bash
# receitas da panela (força bruta com as regras reais do cooking.lua; leva ~1 min)
uv run --no-project --with lupa python ferramentas/gerar_receitas_mod.py \
    testes/scripts_do_jogo/scripts ferramentas/panela.json mod/scripts/geladeira_receitas.lua

# fogueira e varal
python3 -I ferramentas/gerar_simples_mod.py ferramentas/simples.json mod/scripts/geladeira_simples.lua

# selos das categorias e ícone do mod (a partir da arte em ferramentas/icones/)
uv run --no-project --with numpy --with pillow --with scipy python ferramentas/gerar_icones.py mod
```

A arte fica em [`ferramentas/icones/`](ferramentas/icones): um PNG por categoria (`carne.png`,
`legume.png`…, mais `especifico.png`) e o `icone_mod.jpg`. As versões "meio" (Meia carne, Meio
legume…) são geradas automaticamente a partir das inteiras. Para converter para o formato do jogo
(`.tex`), o gerador usa o `TextureConverter` oficial do **Don't Starve Mod Tools** (Steam) quando
ele está instalado.

## 🗂️ Estrutura

```
mod/                       o mod em si (é esta pasta que vai para o jogo / Workshop)
  modinfo.lua              nome, versão e configurações
  modmain.lua              servidor (leitura das geladeiras, receitas) e cliente (teclas, RPC)
  scripts/widgets/         o painel lateral e o conteúdo das abas
  scripts/geladeira_*.lua  dados gerados (receitas, fogueira/varal, categorias)
  images/                  selos das categorias
  modicon.tex / .xml       ícone na lista de mods
testes/                    testes fora do jogo e medição de desempenho
ferramentas/               geradores dos dados e dos ícones
  icones/                  a arte original dos selos e do ícone do mod
docs/                      explicações técnicas
```

## 🐛 Encontrou um bug? Tem uma ideia?

Abra uma [**issue**](../../issues/new/choose):

1. Clique em **Issues → New issue** e escolha **Bug** ou **Sugestão**.
2. Para bugs, conte **o que você fez**, **o que esperava** e **o que aconteceu**. Prints ajudam muito!
3. Se o jogo travou ou deu erro, anexe o log. Ele fica em
   `Documentos/Klei/DoNotStarveTogether/client_log.txt` (e `master_server_log.txt`, se você é o host).
4. Diga se estava jogando **sozinho, como host ou num servidor dedicado**, e se usava outros mods.

Pull requests também são bem-vindos. Rode os testes antes de enviar. 🙂

## ❤️ Gostou? Ajude o Ratatouille a crescer

Este mod é feito no tempo livre, por diversão e por amor ao Don't Starve. Se ele salvou o jantar
da sua base, há várias formas de retribuir, e todas fazem diferença:

- 🍲 **Compartilhe** com seus amigos e com o pessoal do seu servidor;
- ⭐ **Avalie** na [Steam Workshop](#-instalação) e deixe um comentário: isso ajuda outros jogadores a encontrar o mod;
- 🌟 **Dê uma estrela** aqui no GitHub;
- 💡 **Sugira ideias** e **reporte bugs** nas [issues](../../issues): é assim que o mod evolui;
- ☕ E, se quiser apoiar financeiramente, você pode **me pagar um café**:

<a href="https://buymeacoffee.com/marcospaulojs" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="45"></a>

Obrigado por jogar! Não morra de fome. 🔥

---

<sub>Código sob a [licença MIT](LICENSE). Ratatouille é um mod feito por fã e não tem relação com a Klei Entertainment.
Don't Starve Together é marca da Klei Entertainment.</sub>
