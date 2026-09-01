#!/usr/bin/env python3
"""Пульт — агент ПК.
pip install -r requirements.txt
python pult_agent.py
"""
from __future__ import annotations
import asyncio, base64, io, json, os, platform, random, socket, subprocess, sys
from pathlib import Path

PORT = 17420
SERVICE_TYPE = "_pultdesk._tcp.local."
MAX_DOWNLOAD = 25 * 1024 * 1024

try:
    import mss, websockets
    from PIL import Image
    from pynput.keyboard import Controller as KeyCtl, Key
    from pynput.mouse import Button, Controller as MouseCtl
    from zeroconf import ServiceInfo, Zeroconf
except ImportError:
    print("pip install websockets pynput zeroconf mss pillow")
    sys.exit(1)

mouse, keys = MouseCtl(), KeyCtl()
PIN = f"{random.randint(0, 9999):04d}"
SYSTEM = platform.system()
SPECIAL = {"enter": Key.enter, "esc": Key.esc, "tab": Key.tab, "backspace": Key.backspace, "delete": Key.delete, "up": Key.up, "down": Key.down, "left": Key.left, "right": Key.right, "f5": Key.f5, "f11": Key.f11, "win": Key.cmd, "cmd": Key.cmd}
MODS = {"ctrl": Key.ctrl, "alt": Key.alt, "shift": Key.shift}
MEDIA = {"playPause": Key.media_play_pause, "next": Key.media_next, "prev": Key.media_previous, "volumeUp": Key.media_volume_up, "volumeDown": Key.media_volume_down, "mute": Key.media_volume_mute}
QUALITY = {"low": (960, 40), "medium": (1280, 55), "high": (1920, 70)}

def screen_size():
    with mss.mss() as sct:
        mon = sct.monitors[1]
        return mon["width"], mon["height"]

def grab_jpeg(quality_key: str):
    width_cap, q = QUALITY.get(quality_key, QUALITY["medium"])
    with mss.mss() as sct:
        mon = sct.monitors[1]
        raw = sct.grab(mon)
        img = Image.frombytes("RGB", raw.size, raw.bgra, "raw", "BGRX")
    w, h = img.size
    if w > width_cap:
        h = int(h * width_cap / w); w = width_cap
        img = img.resize((w, h), Image.BILINEAR)
    buf = io.BytesIO(); img.save(buf, format="JPEG", quality=q, optimize=True)
    return buf.getvalue(), w, h

def roots():
    home = Path.home()
    items = [
        {"name": "Рабочий стол", "path": str(home / "Desktop"), "isDir": True, "size": 0},
        {"name": "Документы", "path": str(home / "Documents"), "isDir": True, "size": 0},
        {"name": "Загрузки", "path": str(home / "Downloads"), "isDir": True, "size": 0},
        {"name": "Домашняя", "path": str(home), "isDir": True, "size": 0},
    ]
    if SYSTEM == "Windows":
        for letter in "CDEFG":
            p = f"{letter}:\\"
            if os.path.exists(p):
                items.append({"name": f"Диск {letter}:", "path": p, "isDir": True, "size": 0})
    return [i for i in items if os.path.isdir(i["path"])]

def list_dir(path: str):
    if not path:
        return {"type": "dir", "path": "", "entries": roots()}
    target = Path(path).expanduser()
    if not target.exists() or not target.is_dir():
        return {"type": "error", "message": "Папка не найдена"}
    entries = []
    try:
        children = sorted(target.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower()))
    except PermissionError:
        return {"type": "error", "message": "Нет доступа"}
    for child in children:
        if child.name.startswith("."):
            continue
        try:
            is_dir = child.is_dir(); size = 0 if is_dir else child.stat().st_size
        except OSError:
            continue
        entries.append({"name": child.name, "path": str(child), "isDir": is_dir, "size": size, "kind": child.suffix.lstrip(".").lower() or None})
    return {"type": "dir", "path": str(target), "entries": entries[:400]}

def list_apps():
    items = []
    if SYSTEM == "Darwin":
        for app in sorted(Path("/Applications").glob("*.app")):
            items.append({"id": app.name, "name": app.stem, "path": str(app)})
    elif SYSTEM == "Windows":
        roots_menu = [
            Path(os.environ.get("PROGRAMDATA", r"C:\\ProgramData")) / "Microsoft/Windows/Start Menu/Programs",
            Path.home() / "AppData/Roaming/Microsoft/Windows/Start Menu/Programs",
        ]
        seen = set()
        for root in roots_menu:
            if not root.exists():
                continue
            for lnk in root.rglob("*.lnk"):
                if lnk.stem.lower() in seen:
                    continue
                seen.add(lnk.stem.lower())
                items.append({"id": str(lnk), "name": lnk.stem, "path": str(lnk)})
    items.sort(key=lambda x: x["name"].lower())
    return {"type": "apps", "items": items[:200]}

def launch(app_id: str):
    if SYSTEM == "Darwin":
        subprocess.Popen(["open", "-a", app_id.replace(".app", "")])
    elif SYSTEM == "Windows":
        os.startfile(app_id)
    else:
        subprocess.Popen(["xdg-open", app_id])

def handle_input(msg):
    kind = msg.get("type")
    if kind == "move":
        mouse.move(float(msg.get("dx", 0)), float(msg.get("dy", 0)))
    elif kind == "click":
        btn = {"right": Button.right, "middle": Button.middle}.get(msg.get("button"), Button.left)
        mouse.click(btn)
    elif kind == "tap":
        sw, sh = screen_size()
        mouse.position = (int(float(msg.get("x", 0)) * sw), int(float(msg.get("y", 0)) * sh))
        mouse.click(Button.right if msg.get("button") == "right" else Button.left)
    elif kind == "scroll":
        mouse.scroll(int(msg.get("dx", 0)), int(msg.get("dy", 0)))
    elif kind == "type":
        keys.type(msg.get("text") or "")
    elif kind == "key":
        held = [MODS[m] for m in msg.get("modifiers") or [] if m in MODS]
        for m in held: keys.press(m)
        code = (msg.get("code") or "").lower()
        key = SPECIAL.get(code)
        if key: keys.tap(key)
        elif len(code) == 1: keys.tap(code)
        for m in reversed(held): keys.release(m)
    elif kind == "media":
        key = MEDIA.get(msg.get("action"))
        if key: keys.tap(key)
    elif kind == "launch":
        try: launch(msg.get("id") or "")
        except OSError as exc: print("launch", exc)

async def stream_loop(ws, state):
    while state["on"]:
        try:
            jpeg, w, h = await asyncio.to_thread(grab_jpeg, state["quality"])
            await ws.send(json.dumps({"type": "frame", "w": w, "h": h, "jpeg": base64.b64encode(jpeg).decode("ascii")}))
        except Exception as exc:
            print("frame", exc); await asyncio.sleep(1)
        await asyncio.sleep({"low": 0.12, "medium": 0.08, "high": 0.05}.get(state["quality"], 0.08))

async def client(ws):
    print("Клиент. PIN", PIN)
    state = {"on": False, "quality": "medium"}
    stream_task = None
    async for raw in ws:
        try: msg = json.loads(raw)
        except json.JSONDecodeError: continue
        kind = msg.get("type")
        if kind == "pair":
            if msg.get("pin") != PIN:
                await ws.close(code=4001, reason="bad pin"); return
            await ws.send(json.dumps({"type": "ok"})); continue
        if kind == "stream":
            state["on"] = bool(msg.get("on")); state["quality"] = msg.get("quality") or "medium"
            if state["on"] and stream_task is None:
                stream_task = asyncio.create_task(stream_loop(ws, state))
            if not state["on"] and stream_task:
                stream_task.cancel(); stream_task = None
            continue
        if kind == "listDir":
            await ws.send(json.dumps(list_dir(msg.get("path") or ""), default=str)); continue
        if kind == "download":
            path = Path(msg.get("path") or "")
            if not path.is_file() or path.stat().st_size > MAX_DOWNLOAD:
                await ws.send(json.dumps({"type": "error", "message": "Файл слишком большой"})); continue
            await ws.send(json.dumps({"type": "file", "name": path.name, "data": base64.b64encode(path.read_bytes()).decode("ascii")})); continue
        if kind == "upload":
            folder = Path(msg.get("path") or Path.home() / "Downloads"); folder.mkdir(parents=True, exist_ok=True)
            name = os.path.basename(msg.get("name") or "file")
            try:
                (folder / name).write_bytes(base64.b64decode(msg.get("data") or ""))
                await ws.send(json.dumps(list_dir(str(folder)), default=str))
            except (OSError, ValueError) as exc:
                await ws.send(json.dumps({"type": "error", "message": str(exc)}))
            continue
        if kind == "apps":
            await ws.send(json.dumps(list_apps())); continue
        handle_input(msg)
    if stream_task: stream_task.cancel()

async def main():
    hostname = socket.gethostname()
    lan = "127.0.0.1"
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(("8.8.8.8", 80)); lan = s.getsockname()[0]; s.close()
    except OSError:
        try: lan = socket.gethostbyname(hostname)
        except OSError: pass
    print(f"Пульт-агент  {hostname}\nPIN          {PIN}\nIP           {lan}\nПорт         {PORT}\nНа iPhone: + → этот IP → этот PIN")
    zc = Zeroconf()
    info = ServiceInfo(SERVICE_TYPE, f"{hostname}.{SERVICE_TYPE}", port=PORT, addresses=[socket.inet_aton(lan)], properties={"os": SYSTEM.encode(), "name": hostname.encode()}, server=f"{hostname}.local.")
    zc.register_service(info)
    async with websockets.serve(client, "0.0.0.0", PORT, max_size=8 * 1024 * 1024):
        try: await asyncio.Future()
        finally:
            zc.unregister_service(info); zc.close()

if __name__ == "__main__":
    asyncio.run(main())
