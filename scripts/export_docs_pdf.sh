#!/usr/bin/env bash
# ==============================================================================
# export_docs_pdf.sh — Convert Markdown Guides (with Mermaid Diagrams & Tables)
# into Client-Ready PDFs using Headless Google Chrome
#
# Usage:
#   ./infra/scripts/export_docs_pdf.sh
#   ./infra/scripts/export_docs_pdf.sh infra/docs/enterprise-deployment-guide.md
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [[ ! -x "${CHROME_BIN}" ]]; then
  if command -v google-chrome >/dev/null 2>&1; then
    CHROME_BIN="$(command -v google-chrome)"
  elif command -v chromium >/dev/null 2>&1; then
    CHROME_BIN="$(command -v chromium)"
  else
    echo "[ERROR] Google Chrome / Chromium not found. Install Chrome or run: npx md-to-pdf <file.md>" >&2
    exit 1
  fi
fi

if [[ $# -gt 0 ]]; then
  FILES=("$@")
else
  FILES=(
    "${REPO_ROOT}/infra/docs/enterprise-deployment-guide.md"
    "${REPO_ROOT}/infra/docs/agent-publishing-guide.md"
    "${REPO_ROOT}/infra/docs/skill-publishing-guide.md"
  )
fi

for MD_FILE in "${FILES[@]}"; do
  if [[ ! -f "${MD_FILE}" ]]; then
    echo "[WARN] File not found: ${MD_FILE}" >&2
    continue
  fi

  PDF_FILE="${MD_FILE%.md}.pdf"
  TMP_HTML="$(mktemp /tmp/ge_doc_export_XXXXXX).html"

  python3 - "${MD_FILE}" "${TMP_HTML}" <<'PYEOF'
import html
import json
import pathlib
import sys

md_path = pathlib.Path(sys.argv[1])
html_path = pathlib.Path(sys.argv[2])
raw_md = md_path.read_text(encoding="utf-8")
title = md_path.stem.replace("-", " ").title()

html_doc = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>{html.escape(title)}</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.5.1/github-markdown-light.min.css" />
  <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
  <style>
    @page {{
      size: A4;
      margin: 14mm 12mm 14mm 12mm;
    }}
    body {{
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      color: #1f2328;
      background: #ffffff;
    }}
    .markdown-body {{
      font-size: 11.5px;
      line-height: 1.5;
      max-width: 100%;
    }}
    .markdown-body h1 {{
      font-size: 20px;
      border-bottom: 2px solid #0969da;
      padding-bottom: 6px;
      color: #0969da;
    }}
    .markdown-body h2 {{
      font-size: 15.5px;
      border-bottom: 1px solid #d0d7de;
      padding-bottom: 4px;
      margin-top: 20px;
      page-break-after: avoid;
    }}
    .markdown-body h3, .markdown-body h4 {{
      page-break-after: avoid;
    }}
    .markdown-body pre {{
      font-size: 10px;
      line-height: 1.4;
      background-color: #f6f8fa;
      border: 1px solid #d0d7de;
      border-radius: 6px;
      padding: 10px;
      white-space: pre-wrap;
      word-break: break-word;
      page-break-inside: avoid;
    }}
    .markdown-body code {{
      font-size: 10px;
    }}
    .markdown-body table {{
      font-size: 10px;
      width: 100%;
      border-collapse: collapse;
      page-break-inside: auto;
    }}
    .markdown-body tr {{
      page-break-inside: avoid;
      page-break-after: auto;
    }}
    .markdown-body th {{
      background-color: #f0f4f9 !important;
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }}
    .mermaid {{
      text-align: center;
      margin: 14px 0;
      page-break-inside: avoid;
    }}
    .mermaid svg {{
      max-width: 100% !important;
      height: auto !important;
    }}
  </style>
</head>
<body>
  <article id="content" class="markdown-body"></article>
  <script>
    const rawMd = {json.dumps(raw_md)};
    const renderer = new marked.Renderer();
    const origCode = renderer.code.bind(renderer);
    renderer.code = function(code, infostring, escaped) {{
      const lang = (infostring || '').trim();
      const text = typeof code === 'object' ? code.text : code;
      const codeLang = typeof code === 'object' ? (code.lang || '') : lang;
      if (codeLang === 'mermaid') {{
        const escapedMermaid = text
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;');
        return '<div class="mermaid">' + escapedMermaid + '</div>';
      }}
      return origCode(code, infostring, escaped);
    }};
    marked.use({{ renderer, gfm: true, breaks: false }});
    document.getElementById('content').innerHTML = marked.parse(rawMd);
    mermaid.initialize({{ startOnLoad: true, theme: 'default', securityLevel: 'loose' }});
  </script>
</body>
</html>
"""
html_path.write_text(html_doc, encoding="utf-8")
PYEOF

  echo "[INFO] Rendering ${MD_FILE} -> ${PDF_FILE} ..."
  "${CHROME_BIN}" \
    --headless \
    --disable-gpu \
    --no-pdf-header-footer \
    --virtual-time-budget=8000 \
    --print-to-pdf="${PDF_FILE}" \
    "file://${TMP_HTML}" 2>/dev/null

  rm -f "${TMP_HTML}"
  echo "[OK] Generated: ${PDF_FILE}"
done
