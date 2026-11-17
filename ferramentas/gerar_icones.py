"""Gera as texturas do mod a partir da arte em ferramentas/icones/:

- mod/images/geladeira_categorias.tex/.xml: os selos das categorias (Carne, Legume…)
  e o "item específico". As versões "meio" (Meia carne, Meio legume…) são feitas
  aqui: a metade direita do selo fica apagada, com um tracejado no meio.
- mod/modicon.tex/.xml: o ícone do mod na lista de mods (de icones/icone_mod.jpg).

A arte original veio com um xadrez "pintado" no lugar da transparência; os PNGs em
icones/ já estão recortados (ferramentas/recortar_xadrez.py).

uso: uv run --no-project --with numpy --with pillow --with scipy python ferramentas/gerar_icones.py mod [previa.png]
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd

AQUI = Path(__file__).parent
sys.path.insert(0, str(AQUI))
import ktex  # noqa: E402
from caminhos import conversor_de_textura  # noqa: E402

ICONES = AQUI / "icones"
MOD = Path(sys.argv[1])
TAM, LADO = 128, 512           # cada selo 128x128 num atlas 512x512 (cabem 16)
MODICON = 128
TINTA = (40, 26, 16)


def categorias_usadas():
    """ids das categorias que as receitas usam (mod/scripts/geladeira_categorias.lua)"""
    texto = (MOD / "scripts" / "geladeira_categorias.lua").read_text(encoding="utf-8")
    return re.findall(r'id = "([a-z_]+)"', texto)


def meio(img):
    """Versão 'vale metade': metade direita do miolo apagada + tracejado vertical."""
    a = np.asarray(img.convert("RGBA")).astype(float)
    h, w = a.shape[:2]
    cheio = a[..., 3] > 128
    xs = np.where(cheio.any(0))[0]
    cx = (xs[0] + xs[-1]) / 2
    aro = int(w * 0.035)                                   # não mexe no aro do selo
    miolo = nd.binary_erosion(cheio, iterations=aro)
    direita = np.zeros_like(miolo)
    direita[:, int(cx):] = True
    m = miolo & direita
    papel = np.array([196, 176, 140])
    a[m, :3] = a[m, :3] * 0.30 + papel * 0.70 * 0.88      # bem desbotado, um pouco mais escuro
    out = Image.fromarray(a.astype(np.uint8))
    d = ImageDraw.Draw(out)
    ys = np.where(miolo[:, int(cx)])[0]
    passo, traco, larg = int(h * 0.06), int(h * 0.035), max(2, int(w * 0.014))
    for y in range(ys[0] + passo // 2, ys[-1] - traco, passo):
        d.line([(cx, y), (cx, y + traco)], fill=TINTA + (255,), width=larg)
    return out


def para_tex(img, destino):
    """PNG -> .tex: TextureConverter oficial da Klei se houver; senão o nosso ktex.py."""
    conv = conversor_de_textura()
    if conv is None:
        ktex.gravar(destino, img.transpose(Image.FLIP_TOP_BOTTOM))
        return
    with tempfile.TemporaryDirectory(dir=AQUI) as tmp:     # pasta do Windows (o .exe lê de lá)
        img.save(Path(tmp) / "img.png")
        subprocess.run([str(conv), "--swizzle", "--format", "bc3", "--platform", "opengl",
                        "-i", "img.png", "-o", "img.tex", "--mipmap", "--premultiply"], cwd=tmp, check=True,
                       stdout=subprocess.DEVNULL)
        destino.write_bytes((Path(tmp) / "img.tex").read_bytes())


def reduzir(img, lado):
    return img.resize((lado, lado), Image.LANCZOS)


def rente(img, margem=0.03):
    """Corta a sobra transparente em volta (quadrado centrado no selo + margem pequena),
    para todos os selos ocuparem o mesmo espaço no atlas."""
    caixa = img.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    if caixa is None:
        return img
    x0, y0, x1, y1 = caixa
    lado = max(x1 - x0, y1 - y0) * (1 + 2 * margem)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    quadro = Image.new("RGBA", (int(lado), int(lado)), (0, 0, 0, 0))
    quadro.alpha_composite(img, (int(lado / 2 - cx), int(lado / 2 - cy)))
    return quadro


# --- atlas das categorias
icones = []
for cid in categorias_usadas() + ["especifico"]:
    base = cid[len("meio_"):] if cid.startswith("meio_") else cid
    arq = ICONES / f"{base}.png"
    if not arq.exists():
        sys.exit(f"falta a arte {arq} (categoria {cid})")
    img = rente(Image.open(arq).convert("RGBA"))
    icones.append((cid, reduzir(meio(img) if cid.startswith("meio_") else img, TAM)))

atlas = Image.new("RGBA", (LADO, LADO), (0, 0, 0, 0))
linhas = ['<Atlas><Texture filename="geladeira_categorias.tex" /><Elements>']
por_linha = LADO // TAM
for i, (nome, im) in enumerate(icones):
    x, y = (i % por_linha) * TAM, (i // por_linha) * TAM
    atlas.alpha_composite(im, (x, y))
    # u/v como nos atlas do jogo: v conta de baixo para cima; meio pixel de margem
    u1, u2 = (x + 0.5) / LADO, (x + TAM - 0.5) / LADO
    v1, v2 = 1 - (y + TAM - 0.5) / LADO, 1 - (y + 0.5) / LADO
    linhas.append(f'<Element name="cat_{nome}.tex" u1="{u1}" u2="{u2}" v1="{v1}" v2="{v2}" />')
linhas.append("</Elements></Atlas>")
(MOD / "images").mkdir(exist_ok=True)
para_tex(atlas, MOD / "images" / "geladeira_categorias.tex")
(MOD / "images" / "geladeira_categorias.xml").write_text("".join(linhas), encoding="utf-8")
print(f"{len(icones)} selos -> {MOD / 'images'}")

# --- ícone do mod
icone = reduzir(Image.open(ICONES / "icone_mod.jpg").convert("RGBA"), MODICON)
para_tex(icone, MOD / "modicon.tex")
(MOD / "modicon.xml").write_text(
    '<Atlas><Texture filename="modicon.tex" /><Elements>'
    '<Element name="modicon.tex" u1="0" u2="1" v1="0" v2="1" /></Elements></Atlas>', encoding="utf-8")
print(f"modicon {MODICON}x{MODICON} -> {MOD}")

if len(sys.argv) > 2:                                      # prévia opcional, fora do mod
    previa = Image.new("RGBA", (LADO + 40 + MODICON, LADO), (214, 190, 140, 255))
    previa.alpha_composite(atlas, (0, 0))
    previa.alpha_composite(icone, (LADO + 40, 0))
    previa.save(sys.argv[2])
