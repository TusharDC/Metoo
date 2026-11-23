#!/usr/bin/env python3
"""
Generate the Shararat AI-girl roster with Google Nano Banana Pro (gemini-3-pro-image),
upload each avatar to Supabase Storage, and upsert the character into ai_characters.

Consistency note: this generates ONE avatar per girl. For multiple photos of the
SAME face, pass the avatar back as a reference image (inline_data) in a follow-up
call — hook left as generate_gallery() for the next phase.

Env required:
  GEMINI_API_KEY               Google AI Studio key (billing enabled)
  SUPABASE_URL                 https://<ref>.supabase.co
  SUPABASE_SERVICE_ROLE_KEY    service_role key (storage + table writes)
Optional:
  IMAGE_MODEL   default gemini-3-pro-image   (use gemini-2.5-flash-image for cheaper)
  LIMIT         default 0 (all); set e.g. 3 to test a few first
  DRY_RUN       '1' to skip generation/upload and just print the plan

Run:
  cd backend/scripts
  LIMIT=3 python3 generate_models.py          # test 3 first, eyeball quality
  python3 generate_models.py                  # full roster
"""
import base64
import json
import os
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("pip3 install requests  (then re-run)")

HERE = Path(__file__).resolve().parent
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
SB_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SR = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
MODEL = os.environ.get("IMAGE_MODEL", "gemini-3-pro-image")
LIMIT = int(os.environ.get("LIMIT", "0"))
DRY_RUN = os.environ.get("DRY_RUN") == "1"

if not DRY_RUN and not all([GEMINI_API_KEY, SB_URL, SR]):
    sys.exit("Set GEMINI_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY")


def gen_face(appearance: str) -> tuple[bytes, str]:
    prompt = (
        f"{appearance}. Candid natural iPhone selfie portrait of one person, photorealistic, "
        "realistic skin texture with pores and subtle imperfections, soft natural lighting, "
        "warm genuine smile, looking at camera, fully clothed, tasteful, SFW. "
        "Vertical 3:4 portrait, single subject, no text, no watermark."
    )
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={GEMINI_API_KEY}"
    body = {"contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"responseModalities": ["IMAGE"]}}
    r = requests.post(url, json=body, timeout=180)
    if r.status_code >= 400:
        raise RuntimeError(f"gemini {r.status_code}: {r.text[:300]}")
    for p in r.json()["candidates"][0]["content"]["parts"]:
        inline = p.get("inlineData") or p.get("inline_data")
        if inline and inline.get("data"):
            return base64.b64decode(inline["data"]), inline.get("mimeType", "image/jpeg")
    raise RuntimeError("no image in response")


def upload_avatar(slug: str, data: bytes, mime: str) -> str:
    ext = "png" if "png" in mime else "jpg"
    path = f"{slug}.{ext}"
    r = requests.post(
        f"{SB_URL}/storage/v1/object/characters/{path}",
        headers={"Authorization": f"Bearer {SR}", "x-upsert": "true", "Content-Type": mime},
        data=data, timeout=60,
    )
    r.raise_for_status()
    return path


def upsert_character(g: dict, avatar_path: str, sort_order: int):
    region_short = g["region"].split("(")[0].strip()
    payload = {
        "slug": g["slug"],
        "name": g["name"],
        "tagline": g["personality"],
        "bio": f'{g["age"]} • {region_short}',
        "personality": g["personality"],
        "system_prompt": g["persona"],
        "avatar_path": avatar_path,
        "accent_color": g.get("accent_color", "#E91E63"),
        "default_mood": g.get("default_mood", "playful"),
        "traits": g.get("traits", []),
        "sort_order": sort_order,
        "is_active": True,
    }
    r = requests.post(
        f"{SB_URL}/rest/v1/ai_characters?on_conflict=slug",
        headers={"apikey": SR, "Authorization": f"Bearer {SR}",
                 "Content-Type": "application/json",
                 "Prefer": "resolution=merge-duplicates,return=minimal"},
        json=payload, timeout=30,
    )
    r.raise_for_status()


def main():
    roster = json.loads((HERE / "roster.json").read_text())
    if LIMIT:
        roster = roster[:LIMIT]
    print(f"Model={MODEL}  girls={len(roster)}  dry_run={DRY_RUN}\n")
    ok = 0
    for i, g in enumerate(roster):
        try:
            print(f"[{i+1}/{len(roster)}] {g['name']} ({g['region']}) …", end=" ", flush=True)
            if DRY_RUN:
                print("(dry)"); ok += 1; continue
            data, mime = gen_face(g["appearance"])
            path = upload_avatar(g["slug"], data, mime)
            upsert_character(g, path, 10 + i)
            print(f"done -> {path} ({len(data)//1024} KB)")
            ok += 1
            time.sleep(1)
        except Exception as e:
            print(f"FAILED: {e}")
    print(f"\n{ok}/{len(roster)} generated + seeded.")


if __name__ == "__main__":
    main()
