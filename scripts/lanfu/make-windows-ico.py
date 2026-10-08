from PIL import Image, ImageFilter
import struct

ASSETS = "/mnt/d/Users/XuShuang/Desktop/LanFu/LanFu-品牌资产"
SRC = ASSETS + "/png/lanfu-mark-1024.png"
src = Image.open(SRC).convert("RGBA")
alpha = src.getchannel("A")
K = 17
opened = alpha.filter(ImageFilter.MinFilter(K)).filter(ImageFilter.MaxFilter(K))
simple = Image.composite(src, Image.new("RGBA", src.size, (0,0,0,0)), opened.point(lambda v: 255 if v > 96 else 0))

def bmp_entry(img):
    s = img.size[0]
    px = img.load()
    xor = bytearray()
    for y in range(s - 1, -1, -1):
        for x in range(s):
            r, g, b, a = px[x, y]
            xor += bytes((b, g, r, a))
    rowbytes = ((s + 31) // 32) * 4
    andmask = bytes(rowbytes * s)
    hdr = struct.pack("<IiiHHIIiiII", 40, s, s * 2, 1, 32, 0, len(xor) + len(andmask), 0, 0, 0, 0)
    return hdr + bytes(xor) + andmask

def write_ico(path, images):
    sizes = sorted(images)
    blobs = []
    for s in sizes:
        img = images[s]
        if s >= 256:
            img.save("/tmp/_e.png", format="PNG", optimize=True)
            blobs.append((s, open("/tmp/_e.png", "rb").read()))
        else:
            blobs.append((s, bmp_entry(img)))
    n = len(blobs)
    offset = 6 + 16 * n
    entries, data = b"", b""
    for s, payload in blobs:
        dim = 0 if s >= 256 else s
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(payload), offset)
        data += payload
        offset += len(payload)
    open(path, "wb").write(struct.pack("<HHH", 0, 1, n) + entries + data)
    chk = Image.open(path)
    print("  ", path.split("/")[-1], sorted(chk.info.get("sizes", [])))
    return chk

S = [16, 24, 32, 48, 64, 128, 256]
imgs = {}
for s in S:
    imgs[s] = simple.resize((s, s), Image.LANCZOS) if s <= 32 else src.resize((s, s), Image.LANCZOS)

write_ico("/tmp/lanfu-A.ico", imgs)
# 对照组：全部用完整标志的标准 Pillow 输出
Image.open(SRC).convert("RGBA").save("/tmp/lanfu-std.ico", format="ICO", sizes=[(s, s) for s in S])
print("   对照 std:", sorted(Image.open("/tmp/lanfu-std.ico").info.get("sizes", [])))

import shutil
shutil.copy("/tmp/lanfu-A.ico", ASSETS + "/favicon.ico")
shutil.copy("/tmp/lanfu-A.ico", "/home/xushuang/lanfu/packaging/windows/lanfu.ico")
shutil.copy("/tmp/lanfu-A.ico", "/home/xushuang/lanfu/ui/public/favicon.ico")
print("已写入 3 处")
