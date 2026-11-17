"""Tira o xadrez 'pintado' (falsa transparência) das imagens dos selos."""
import glob, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage as nd

ORIG, SAIDA = sys.argv[1], sys.argv[2]
CONTORNO = (22, 12, 8)
for f in sorted(glob.glob(os.path.join(ORIG, '*.jpg'))):
    if os.path.basename(f).startswith('icone_mod'):
        continue
    a = np.asarray(Image.open(f).convert('RGB')).astype(int)
    sat = a.max(2) - a.min(2); lum = a.mean(2)
    cantos = np.concatenate([a[:40, :40], a[:40, -40:], a[-40:, :40], a[-40:, -40:]]).reshape(-1, 3).mean(1)
    claro = np.percentile(cantos, 90)                      # cinza claro do xadrez desta imagem
    xadrez = (sat < 10) & (lum < claro + 25)        # qualquer cinza neutro até o claro do xadrez
    rot, _ = nd.label(xadrez)
    ids = set(np.unique(np.concatenate([rot[0], rot[-1], rot[:, 0], rot[:, -1]]))) - {0}
    obj = ~np.isin(rot, list(ids))
    obj = nd.binary_opening(obj, iterations=3)
    rot2, n = nd.label(obj)
    obj = rot2 == (1 + int(np.argmax(nd.sum(obj, rot2, range(1, n + 1)))))
    obj = nd.binary_fill_holes(obj)
    # o contorno preto de fora some junto com o preto do xadrez: se a borda que sobrou
    # não é escura, refaz o contorno (+9 px) em marrom-escuro
    borda = obj & ~nd.binary_erosion(obj, iterations=2)
    raio = 9 if lum[borda].mean() > 60 else 2
    yy, xx = np.ogrid[-raio:raio + 1, -raio:raio + 1]
    maior = nd.binary_dilation(obj, structure=xx**2 + yy**2 <= raio * raio)
    a[maior & ~obj] = CONTORNO
    alfa = np.clip((nd.gaussian_filter(maior.astype(float), 1.0) - 0.5) * 2.5 + 0.5, 0, 1)
    nome = os.path.splitext(os.path.basename(f))[0].replace(' ', '_')
    Image.fromarray(np.dstack([a, (alfa * 255).astype(int)]).astype(np.uint8)).save(os.path.join(SAIDA, nome + '.png'))
    print('ok', nome, 'xadrez claro', round(claro), 'contorno', raio)
