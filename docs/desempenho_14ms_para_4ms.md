# Como o pior frame do mod caiu de ~14 ms para ~4 ms

Este documento explica a otimização aplicada no mod **Ratatouille** (na época chamado Listar Geladeira) para que ele
não derrube o FPS de quem hospeda o mundo, principalmente em PCs mais fracos.

**Resumo:** a quantidade total de trabalho **não mudou**: continua em ~360 ms de CPU no
pior caso. O que mudou foi **como esse trabalho é dividido entre os frames**. Antes, o mod
dividia por *quantidade* (300 combinações por frame) e fazia a varredura do mundo de uma
vez só. Agora ele divide por *tempo*: para quando gastou 3 ms no frame e continua no
frame seguinte.

---

## 1. Por que isso importa: o orçamento de um frame

O DST roda a lógica do jogo em **uma única thread de Lua**. Enquanto um pedaço de código
Lua está rodando, nada mais anda: nem os bichos, nem o personagem, nem a tela de quem
hospeda.

| FPS | Tempo de cada frame |
|---|---|
| 60 | 16,7 ms |
| 30 | 33,3 ms |

Esse tempo é dividido entre **tudo** que o jogo faz no frame: física, IA dos bichos, rede,
desenho na tela… Se um mod sozinho gasta 14 ms num frame, sobra pouco para o resto, e o
frame atrasa. O jogador sente isso como um **engasgo** (stutter).

Em PC rápido 14 ms passa quase despercebido. Num PC **3× mais lento** esses mesmos 14 ms
viram ~40 ms, ou seja, mais de um frame inteiro perdido de uma vez.

---

## 2. O que o mod faz quando alguém aperta L ou K

Tudo acontece **no servidor** (no PC de quem hospeda), em dois passos pesados:

1. **Varrer o mundo** (`CollectStock`): percorre `GLOBAL.Ents`, que guarda *todas* as
   entidades do mundo (árvores, pedras, bichos, itens no chão…), procurando geladeiras,
   Chester e Bolsa Térmica. Num mundo grande são dezenas de milhares de entidades.
2. **Testar a panela** (`AbaPanela`): testa toda combinação de 4 ingredientes contra
   todas as receitas do `cooking.lua`. O mod usa no máximo os 24 tipos de ingrediente
   mais abundantes (`MAX_TIPOS`), o que dá até 17.550 combinações × ~80 receitas cada.
   No cenário medido há 27 tipos; os 3 mais raros ficam de fora da panela.

Para não fazer tudo de uma vez, esse trabalho já rodava dentro de uma **thread** do
DST (`StartThread`).

### Como funcionam as "threads" do DST

Não são threads de verdade (não rodam em paralelo). São **corrotinas** do Lua
gerenciadas pelo agendador do jogo (`scripts/scheduler.lua`):

- `StartThread(fn)` registra a função como uma tarefa;
- a cada atualização do jogo, o agendador retoma a tarefa;
- quando a tarefa chama `Yield()`, ela **pausa** e devolve o controle para o jogo;
- na próxima atualização, ela **continua exatamente de onde parou**, com todas as
  variáveis locais intactas.

Ou seja: `Yield()` é o "ponto de respiro". Quanto mais bem colocados os `Yield()`, menor o
pedaço de trabalho em cada frame.

---

## 3. Como estava (antes)

```lua
local COMBOS_POR_FRAME = 300

-- dentro do teste de cada combinação da panela:
testadas = testadas + 1
if testadas % COMBOS_POR_FRAME == 0 then G.Yield() end
```

E a varredura do mundo **não tinha nenhum `Yield()`**:

```lua
for _, inst in pairs(G.Ents) do      -- 30 mil entidades de uma vez
    ...
end
```

### Os dois problemas

1. **A varredura inteira caía no primeiro frame.** As 30 mil entidades eram percorridas
   de uma vez, junto com a montagem da aba Itens. Esse era o frame de ~14 ms.
2. **"300 combinações" não é uma medida de tempo.** O custo de cada combinação varia: depende
   de quantas receitas passam no teste e de quantas tags os ingredientes têm. E o custo
   de 300 combinações num PC rápido é muito menor do que num PC fraco. Um número fixo
   nunca é o certo para todo mundo: num PC rápido pausa demais, num lento pausa de menos.

### Medição (antes)

Pior caso: 3 geladeiras cheias com 27 tipos diferentes de ingrediente + 30 mil outras
entidades. Tempo de CPU de cada frame em ms:

```
13.6  8.9  9.8  7.0  7.5  8.0  5.9  6.1  5.6  5.9 ... (59 frames, ~6 ms cada)
```

- o **1º frame** (~14 ms) era a varredura do mundo inteira;
- os outros (~6 ms cada) eram blocos de 300 combinações da panela.

---

## 4. O que mudou (depois)

### Ideia: orçamento de tempo em vez de contagem

Em vez de "pause a cada N passos", a regra passou a ser **"pause quando já gastou 3 ms
neste frame"**. É o mesmo princípio de *time slicing* usado em motores de jogo:

- **PC rápido**: faz muito trabalho em 3 ms, então termina em poucos frames;
- **PC fraco**: faz menos trabalho em 3 ms, então usa mais frames, **mas nenhum frame passa
  muito de 3 ms**.

O custo por frame fica **igual em qualquer PC**; o que se ajusta sozinho é quantos frames
o trabalho leva.

### O código (`mod/modmain.lua`)

```lua
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
```

E ele é chamado nos **dois** laços pesados:

```lua
-- 1) varredura do mundo (antes não tinha pausa nenhuma)
for _, inst in pairs(G.Ents) do
    TalvezPausar()
    ...
end

-- 2) teste de cada combinação da panela (antes: a cada 300)
TalvezPausar()
```

E o relógio é zerado quando a thread começa:

```lua
G.StartThread(function()
    ComecarFrame()
    local s = CollectStock(player, fontes)
    ...
end)
```

### Detalhes de cada decisão

**Por que 3 ms?** É ~18% de um frame a 60 FPS e ~9% a 30 FPS: sobra folga para o jogo
mesmo num PC fraco. Valores menores deixam a janela demorar mais para abrir; valores
maiores voltam a pesar no frame.

**Por que olhar o relógio só a cada 16 passos?** Chamar `os.clock()` também custa. Um passo
(testar uma combinação ou olhar uma entidade) leva microssegundos, então checar o relógio
a cada 16 passos dá precisão de sobra (o frame passa dos 3 ms por bem pouco) e o custo da
checagem some.

**Por que `os.clock()`?** Ele mede tempo de CPU com resolução fina e está disponível no Lua
do DST: o próprio jogo usa em `scripts/profiler.lua`. O `modmain.lua` não enxerga `os`
direto (o ambiente dele só tem `pairs`, `ipairs`, `print`, `math`, `table`, `type`,
`string`, `tostring`, `require` e `Class`), por isso o acesso é `GLOBAL.os.clock`.

**E se não existir relógio?** O código tem um plano B: pausa a cada 160 passos (contagem
fixa, como antes, só que menor). Assim o mod nunca quebra.

**Por que a pausa funciona no meio da recursão da panela?** As combinações são geradas
por uma função recursiva (`Rec`). No Lua 5.1, `coroutine.yield` pode pausar de dentro de
funções Lua aninhadas sem problema. O que **não pode** é pausar atravessando uma função em C
(por exemplo, de dentro do comparador de um `table.sort` ou de um `pcall`). Os
`TalvezPausar()` foram colocados só em código Lua puro, fora de `table.sort`/`pcall`.

---

## 5. Resultado

Mesmo cenário (pior caso), mesma máquina, Lua 5.1 interpretado (sem JIT, como no DST):

| | Antes | Depois |
|---|---|---|
| CPU total do pedido | ~383 ms | ~364 ms |
| Frames usados | 59 | 115 |
| **Pior frame** | **~14–17 ms** | **~4 ms** |
| Frame típico | ~6 ms | ~3,1 ms |
| Tempo até a janela abrir (a 30 atualizações/s) | ~2 s | ~4 s |

Tempos de cada frame depois da mudança:

```
3.0  3.0  3.3  4.0  3.1  3.1  3.3  3.4  3.3  3.4  3.2 ... (115 frames, ~3,1 ms cada)
```

### O que se ganhou e o que se pagou

- **Ganhou:** nenhum frame passa de ~4 ms, em qualquer PC. O primeiro frame, que antes era o
  pior por causa da varredura do mundo, agora também respeita o limite.
- **Pagou:** a janela demora mais para abrir no pior caso, porque o mesmo trabalho foi
  espalhado em mais frames. Foi uma troca consciente: **é melhor a janela demorar alguns
  segundos do que o jogo de todo mundo engasgar.**

### Ressalvas honestas

- Os números são desta máquina. Em outra máquina os tempos absolutos mudam, mas o
  **pior frame continua perto de 3–4 ms**, porque o limite é de tempo, não de quantidade.
- O tempo até a janela abrir depende de quantas vezes por segundo o servidor atualiza.
  O jogo define `FRAMES = 1/30` em `constants.lua`, mas servidores dedicados podem ter
  outra taxa (`tick_rate` no `cluster.ini`). Com menos atualizações por segundo, a janela
  demora proporcionalmente mais.
- O pior caso (27 tipos diferentes de ingrediente) é raro. Com menos tipos, o número de
  combinações cai muito: 12 tipos dão 1.365 combinações, contra 17.550 com 24 tipos. Na prática
  a janela abre bem mais rápido.
- Depois que a janela abre, trocar de aba, ordenar e mexer nos checkboxes de grupo é
  instantâneo: não refaz a conta. Só os checkboxes de **fonte** (Geladeiras, Chester,
  Bolsa Térmica, Personagem) pedem tudo de novo ao servidor.

---

## 6. Quando o mod custa zero

Fora do momento em que alguém aperta L ou K, o mod **não executa nada**:

- não tem tarefa periódica (`DoPeriodicTask`);
- não tem código rodando a cada frame (`OnUpdate`/`StartUpdating`);
- não ouve eventos do jogo (`ListenForEvent`);
- não altera prefabs, componentes ou jogadores (`AddPrefabPostInit` etc.).

No cliente de quem abre a janela: a mensagem recebida tem ~5 KB, a janela é montada em ~8 ms
na primeira vez (carrega as 175 receitas da aba Todas) e ~0 ms nas seguintes, com ~350 KB de
memória ocupada. Os outros jogadores não fazem nada.

---

## 7. Como medir de novo

O script `testes/medir_desempenho.lua` monta o pior caso (3 geladeiras com 27 tipos de
ingrediente + 30 mil entidades), roda um pedido completo e mede cada frame da thread.
Ele usa os scripts reais do jogo (`cooking.lua`, `STRINGS`…) através de `ferramentas/dst_lua.py`.

```bash
uv run --no-project --with lupa python testes/rodar.py --desempenho
```

Saída esperada (aproximada):

```
SERVIDOR  27 tipos na geladeira, 30003 entidades no mundo
  tempo total de CPU: 364 ms, espalhado em 115 frames
  pior frame: 3.7 ms  (a 30 FPS cada frame tem 33 ms)
  a janela abre depois de ~3.8 s a 30 FPS
  mensagem enviada ao jogador: 4.8 KB
CLIENTE
  1ª vez que abre: 8 ms (carrega as 175 receitas da aba Todas)
  próximas vezes: 0 ms
  memória que fica ocupada: ~351 KB
```

Para experimentar outro orçamento, mude `ORCAMENTO_FRAME` no `modmain.lua` e rode de novo.
