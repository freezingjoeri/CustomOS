#!/usr/bin/env python3
"""
Simple Ollama client for CustomOS Guardian.

Reads a JSON blob with metrics from stdin and asks a local Ollama model
for a short, human-friendly verdict like:

  - "All systems green."
  - "Issue detected in Plex service (inactive)."

If Ollama or the model is not available, this script should fail silently
so Guardian can fall back to its rule-based interpretation.
"""

import json
import os
import sys
from textwrap import dedent

try:
    import requests  # type: ignore
except Exception:
    # If requests is not available, we don't hard-fail; Guardian will ignore us.
    sys.exit(0)


OLLAMA_API_URL = os.environ.get("OLLAMA_API_URL", "http://localhost:11434/api/generate")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "llama3")


def build_prompt(metrics: dict) -> str:
    """
    Turn the metrics dict into a compact, instruction-oriented prompt.
    """
    services = metrics.get("services", {})
    memory = metrics.get("memory", {})
    cpu = metrics.get("cpu_load", {})

    prompt = dedent(
        f"""
        You are the CustomOS Guardian, a concise monitoring assistant.

        Your job:
          - Look at CPU, memory, and service status.
          - Respond with ONE or two short sentences.
          - If everything looks fine, say "All systems green."
          - If any problem is detected, mention it explicitly
            (e.g., "Issue detected in Plex service").

        Data (JSON):
        CPU load: {cpu}
        Memory: {memory}
        Services: {services}

        Respond with a short human-friendly verdict only, no JSON, no extra explanation.
        """
    ).strip()

    return prompt


def call_ollama(prompt: str) -> str:
    """
    Call the Ollama HTTP API. See https://github.com/jmorganca/ollama
    """
    try:
        resp = requests.post(
            OLLAMA_API_URL,
            json={
                "model": OLLAMA_MODEL,
                "prompt": prompt,
                "stream": False,
            },
            timeout=15,
        )
        resp.raise_for_status()
        data = resp.json()
        text = data.get("response") or data.get("text") or ""
        return text.strip()
    except Exception:
        # Fail quietly; Guardian will handle fallback.
        return ""


def main() -> None:
    try:
        raw = sys.stdin.read()
        metrics = json.loads(raw or "{}")
    except Exception:
        # If input is not valid JSON, just bail quietly.
        sys.exit(0)

    prompt = build_prompt(metrics)
    verdict = call_ollama(prompt)
    if verdict:
        print(verdict)


if __name__ == "__main__":
    main()

