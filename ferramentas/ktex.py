"""Lê e grava texturas .tex do Don't Starve (formato KTEX, DXT5 com mipmaps).

Cabeçalho (como nos .tex do próprio jogo): "KTEX" + uint32 com campos de bits
plataforma(4) formato(5) tipo(4) n_mips(5) flags(2) resto(12 bits = 1).
Depois, para cada mip: largura, altura, pitch (uint16) e tamanho (uint32); em seguida
os dados de todos os mips, na mesma ordem.
"""
import struct

import numpy as np

DXT5, TIPO_2D = 2, 1


def _cab(n_mips, formato=DXT5, flags=3):     # flags 3 = o que o TextureConverter oficial grava
    return struct.pack("<4sI", b"KTEX", 0 | formato << 4 | TIPO_2D << 9 | n_mips << 13 | flags << 18 | 0xFFF << 20)


def _565(c):
    c = c.astype(np.int32)
    return (c[..., 0] * 31 // 255) << 11 | (c[..., 1] * 63 // 255) << 5 | (c[..., 2] * 31 // 255)


def _de565(v):
    r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
    return np.stack([r * 255 // 31, g * 255 // 63, b * 255 // 31], -1).astype(np.int32)


def decodificar_dxt5(dados, w, h):
    bw, bh = max(1, w // 4), max(1, h // 4)
    b = np.frombuffer(dados, np.uint8).reshape(bh * bw, 16)
    a0, a1 = b[:, 0].astype(np.int32), b[:, 1].astype(np.int32)
    abits = np.zeros(len(b), np.uint64)
    for i in range(6):
        abits |= b[:, 2 + i].astype(np.uint64) << np.uint64(8 * i)
    paleta_a = np.zeros((len(b), 8), np.int32)
    paleta_a[:, 0], paleta_a[:, 1] = a0, a1
    for i in range(2, 8):
        m8 = (( (8 - i) * a0 + (i - 1) * a1) // 7)
        m6 = (((6 - i) * a0 + (i - 1) * a1) // 5) if i < 6 else (0 if i == 6 else 255)
        paleta_a[:, i] = np.where(a0 > a1, m8, m6)
    c0 = b[:, 8].astype(np.int32) | b[:, 9].astype(np.int32) << 8
    c1 = b[:, 10].astype(np.int32) | b[:, 11].astype(np.int32) << 8
    cb = (b[:, 12].astype(np.uint32) | b[:, 13].astype(np.uint32) << 8 |
          b[:, 14].astype(np.uint32) << 16 | b[:, 15].astype(np.uint32) << 24)
    p0, p1 = _de565(c0), _de565(c1)
    paleta_c = np.stack([p0, p1, (2 * p0 + p1) // 3, (p0 + 2 * p1) // 3], 1)
    out = np.zeros((len(b), 16, 4), np.uint8)
    for px in range(16):
        ia = ((abits >> np.uint64(3 * px)) & np.uint64(7)).astype(np.int64)
        ic = ((cb >> np.uint32(2 * px)) & np.uint32(3)).astype(np.int64)
        out[:, px, :3] = paleta_c[np.arange(len(b)), ic]
        out[:, px, 3] = paleta_a[np.arange(len(b)), ia]
    img = out.reshape(bh, bw, 4, 4, 4).transpose(0, 2, 1, 3, 4).reshape(bh * 4, bw * 4, 4)
    return img[:h, :w]


def ler(caminho_ou_bytes):
    d = caminho_ou_bytes if isinstance(caminho_ou_bytes, bytes) else open(caminho_ou_bytes, "rb").read()
    assert d[:4] == b"KTEX"
    h = struct.unpack("<I", d[4:8])[0]
    formato, n_mips = (h >> 4) & 31, (h >> 13) & 31
    assert formato == DXT5, f"formato {formato} não suportado"
    pos, mips = 8, []
    for _ in range(n_mips):
        mips.append(struct.unpack("<HHHI", d[pos:pos + 10])); pos += 10
    w, hh, _, tam = mips[0]
    return decodificar_dxt5(d[pos:pos + tam], w, hh)       # só o mip maior


def _codificar_bloco(px):
    """px: (N, 16, 4) uint8 -> (N, 16) bytes DXT5."""
    n = len(px)
    a = px[:, :, 3].astype(np.int32)
    a0, a1 = a.max(1), a.min(1)
    iguais = a0 == a1
    paleta = np.zeros((n, 8), np.int32)
    paleta[:, 0], paleta[:, 1] = a0, a1
    for i in range(2, 8):
        paleta[:, i] = ((8 - i) * a0 + (i - 1) * a1) // 7
    ia = np.abs(a[:, :, None] - paleta[:, None, :]).argmin(2)
    ia[iguais] = 0
    abits = np.zeros(n, np.uint64)
    for p in range(16):
        abits |= ia[:, p].astype(np.uint64) << np.uint64(3 * p)
    rgb = px[:, :, :3].astype(np.int32)
    peso = (px[:, :, 3:] > 8)                    # cor de pixel transparente não importa
    grande = np.where(peso, rgb, -1).max(1)
    pequeno = np.where(peso, rgb, 256).min(1)
    vazio = grande[:, 0] < 0
    grande[vazio], pequeno[vazio] = 0, 0
    c0, c1 = _565(np.clip(grande, 0, 255)), _565(np.clip(pequeno, 0, 255))
    troca = c0 < c1
    c0, c1 = np.where(troca, c1, c0), np.where(troca, c0, c1)
    p0, p1 = _de565(c0), _de565(c1)
    pal = np.stack([p0, p1, (2 * p0 + p1) // 3, (p0 + 2 * p1) // 3], 1)
    ic = ((rgb[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(3).argmin(2)
    ic[c0 == c1] = 0
    cbits = np.zeros(n, np.uint32)
    for p in range(16):
        cbits |= ic[:, p].astype(np.uint32) << np.uint32(2 * p)
    out = np.zeros((n, 16), np.uint8)
    out[:, 0], out[:, 1] = a0, a1
    for i in range(6):
        out[:, 2 + i] = ((abits >> np.uint64(8 * i)) & np.uint64(255)).astype(np.uint8)
    out[:, 8], out[:, 9] = c0 & 255, c0 >> 8
    out[:, 10], out[:, 11] = c1 & 255, c1 >> 8
    for i in range(4):
        out[:, 12 + i] = (cbits >> np.uint32(8 * i)) & np.uint32(255)
    return out


def codificar_dxt5(img):
    h, w = img.shape[:2]
    H, W = max(4, (h + 3) // 4 * 4), max(4, (w + 3) // 4 * 4)
    p = np.zeros((H, W, 4), np.uint8); p[:h, :w] = img
    blocos = p.reshape(H // 4, 4, W // 4, 4, 4).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 4)
    return _codificar_bloco(blocos).tobytes()


def gravar(caminho, img_pil):
    """img_pil: Image RGBA com lados potência de 2. Grava todos os mips até 1x1."""
    from PIL import Image
    mips, im = [], img_pil.convert("RGBA")
    while True:
        a = np.asarray(im).copy()
        # alfa pré-multiplicado, como o jogo espera nas imagens da interface
        a[..., :3] = (a[..., :3].astype(np.uint16) * a[..., 3:] // 255).astype(np.uint8)
        mips.append((im.width, im.height, codificar_dxt5(a)))
        if im.width == 1 and im.height == 1:
            break
        im = im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.LANCZOS)
    saida = bytearray(_cab(len(mips)))
    for w, h, dados in mips:
        saida += struct.pack("<HHHI", w, h, max(1, (w + 3) // 4) * 16, len(dados))
    for _, _, dados in mips:
        saida += dados
    open(caminho, "wb").write(saida)
