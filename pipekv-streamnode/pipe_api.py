from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse, Response
from fastapi.middleware.cors import CORSMiddleware
import httpx
import os
import sys
import re
import requests
from dotenv import load_dotenv

load_dotenv()
SERVICE_KEY = os.getenv("X_SERVICE_KEY")
ALLOWED_REF = os.getenv("ALLOWED_REF")

if not SERVICE_KEY or not re.fullmatch(r"[a-f0-9\-]{36}", SERVICE_KEY, re.IGNORECASE):
    print("Invalid or missing X_SERVICE_KEY. Please check your .env file.")
    sys.exit(1)

def get_public_ip():
    try:
        return requests.get("https://api.ipify.org", timeout=10).text.strip() 
    except:
        return "127.0.0.1"

PIPE_BASE_URL = f"https://{get_public_ip()}"


app = FastAPI()
# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=[ALLOWED_REF], 
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def is_valid_file(f: str, exts: list[str]): # Extension check
    return all([
        ".." not in f,
        "/" not in f,
        any(f.endswith(ext) for ext in exts)
    ])

SAFE_HEADERS = {
    "content-type", "content-length", "x-cache", "x-cache-node",
    "x-kv-version", "x-kv-latency-ms", "accept-ranges"
}

# Fetch file from Pipe KV
async def fetch_from_kv(filename: str):
    url = f"{PIPE_BASE_URL}/kv/{filename.lstrip('/')}"
    headers = {
        "X-Service-Key": SERVICE_KEY,
        "Accept": "*/*",
    }
    async with httpx.AsyncClient(timeout=10.0, verify=False) as client:
        return await client.get(url, headers=headers)

@app.get("/m3u8/{filename}")
async def serve_m3u8(filename: str, request: Request):
    if not is_valid_file(filename, [".m3u8"]):
        raise HTTPException(status_code=403, detail="Forbidden")

    origin = request.headers.get("origin", "")
    referer = request.headers.get("referer", "")
    if not (origin.startswith(ALLOWED_REF) or referer.startswith(ALLOWED_REF)):
        raise HTTPException(status_code=403, detail="Origin blocked")

    r = await fetch_from_kv(filename)
    if r.status_code != 200:
        raise HTTPException(status_code=r.status_code, detail="Not found")

    return Response(
        content=r.content,
        media_type="application/vnd.apple.mpegurl",
        headers={"Cache-Control": "public, max-age=5"}
    )

@app.get("/ts/{filename}")
async def serve_ts(filename: str, request: Request):
    if not is_valid_file(filename, [".ts"]):
        raise HTTPException(status_code=403, detail="Forbidden")

    origin = request.headers.get("origin", "")
    referer = request.headers.get("referer", "")
    if not (origin.startswith(ALLOWED_REF) or referer.startswith(ALLOWED_REF)):
        raise HTTPException(status_code=403, detail="Origin blocked")

    r = await fetch_from_kv(filename)
    if r.status_code != 200:
        raise HTTPException(status_code=r.status_code, detail="Not found")

    filtered_headers = {
        k.lower(): v for k, v in r.headers.items()
        if k.lower() in SAFE_HEADERS
    }

    return StreamingResponse(
        iter(r.iter_bytes()),
        media_type=filtered_headers.get("content-type", "video/mp2t"),
        headers=filtered_headers
    )
