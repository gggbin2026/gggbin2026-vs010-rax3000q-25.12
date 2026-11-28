#!/usr/bin/env python3
"""可选：用 Chromium 真渲染 /bridge/ /ap/ 的 ?demo=1 离线预览，拼成两张 PNG。
   不参与 verify.sh；沙盒需 playwright + chromium + Pillow。
"""
import http.server, threading, socketserver, pathlib, sys, shutil, tempfile
from PIL import Image, ImageDraw, ImageFont

OUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/data/workspace")
ROOT = pathlib.Path(__file__).resolve().parent.parent / "files" / "www"

class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw): super().__init__(*a, directory=str(ROOT), **kw)
    def log_message(self, *a): pass

def serve():
    s = socketserver.TCPServer(("127.0.0.1", 0), H)
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s, s.server_address[1]

def shot(page, url_w, url_h, port, name):
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True, executable_path="/usr/bin/google-chrome",
                              args=["--no-sandbox"])
        pg = b.new_page(viewport={"width": url_w, "height": url_h}, device_scale_factor=1)
        pg.goto(f"http://127.0.0.1:{port}/{page}/?demo=1", wait_until="networkidle")
        pg.wait_for_selector("#gauge .u-ring", timeout=10000)
        pg.screenshot(path=str(name), full_page=True)
        b.close()
    return Image.open(str(name)).convert("RGB")

def font(sz):
    for f in ("/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
              "/usr/share/fonts/wenquanyi/wqy-microhei.ttc"):
        if pathlib.Path(f).exists(): return ImageFont.truetype(f, sz)
    return ImageFont.load_default()

def main():
    s, port = serve()
    tmp = pathlib.Path(tempfile.mkdtemp())
    imgs = []
    for page, label in (("bridge", "网桥状态 / WDS Bridge"), ("ap", "AP 状态 / AP")):
        desk = shot(page, 1280, 900, port, tmp / f"{page}-desk.png")
        mob = shot(page, 390, 844, port, tmp / f"{page}-mob.png")
        # 限制高度，避免长图过大
        desk = desk.crop((0, 0, desk.width, min(desk.height, 3400)))
        mob = mob.crop((0, 0, mob.width, min(mob.height, 3400)))
        HDR = 54
        W, H = desk.width + mob.width + 60, max(desk.height, mob.height) + HDR + 34
        canvas = Image.new("RGB", (W, H), "#0b1422")
        d = ImageDraw.Draw(canvas)
        f = font(20)
        d.text((18, 15), f"WDS/AP（仿UBNT）· {label} · 6.12 界面预览", font=f, fill="#e8eef7")
        d.text((18, 40), "DEMO 演示数据 · 桌面 1280px ｜ 竖屏 390px · 非实机读数", font=font(12), fill="#8fa3bd")
        canvas.paste(desk, (10, HDR + 10))
        canvas.paste(mob, (desk.width + 40, HDR + 10))
        p = OUT / f"界面预览-{page}.png"
        canvas.save(p, optimize=True)
        imgs.append(p)
        print("wrote", p, p.stat().st_size, "bytes")
    shutil.rmtree(tmp)
    s.shutdown()

if __name__ == "__main__": main()
