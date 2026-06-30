---
name: idea-creator-user-llm
description: Generate research ideas with three methods. CAMP calls the Urban AI Scientist backend (server-side prompts + paper DB + user API key). DIRECT is Claude-native reasoning — no API key or backend needed. FAST calls the user's LLM directly with an urban science expert prompt, generating 1 idea. Use when the user invokes `/idea-creator-user-llm`.
argument-hint: [CAMP|DIRECT|FAST] [--temperature 0.5] [--paper_domain "Urban Science"] [--retrieval_limit 5] [--retrieval_method mixture] <research topic>
allowed-tools: Bash(*), Read, Write, WebSearch, WebFetch
---

# Idea Creator — User LLM

Generate structured research ideas by supplying your own LLM API key.

Four modes:
- **CAMP**: Server-side paper retrieval → CAMP hypothesis generation → idea (calls backend, requires API key)
- **DIRECT**: Claude-native reasoning — no external API, no backend, no credentials needed. Claude autonomously decides whether to search for relevant papers using its built-in web search tools, then designs the research strategy and generates the idea.
- **FAST**: Direct LLM call — generates 1 idea using a built-in urban science expert prompt. Requires API key; no backend needed.
- **novelty `<path>`**: Novelty check on an already-generated idea `.md` file. Searches Semantic Scholar or arXiv, analyzes related papers, and appends a `## Novelty Check` section to the file. Requires API key + optional Semantic Scholar API key.

⚠️ **Security notice (CAMP / FAST / novelty)**: Your API key is sent in the HTTPS request body
to the configured server (CAMP/novelty) or your own LLM provider (FAST). Only use with a backend you trust.

## Usage

```
/idea-creator-user-llm FAST 城市热岛效应与居民健康
/idea-creator-user-llm CAMP --paper_domain Economics 城市化与贫富差距
/idea-creator-user-llm DIRECT --temperature 0.7 LLM与公共政策
/idea-creator-user-llm CAMP --retrieval_limit 8 --retrieval_method dense 气候变化与城市韧性
/idea-creator-user-llm novelty ./idea-output/2026-06-29_urban_heat_camp.md
/idea-creator-user-llm novelty --source arxiv ./idea-output/2026-06-29_urban_heat_camp.md
```

## Credentials Setup (CAMP, FAST, and novelty — not required for DIRECT)

Create `~/.claude/skills/idea-creator-user-llm/credentials.json`:
```json
{
  "openai_api_key": "sk-...",
  "openai_base_url": "https://api.openai.com/v1",
  "llm_model": "gpt-4o-mini",
  "semantic_scholar_api_key": ""
}
```
`semantic_scholar_api_key` is optional but recommended to avoid rate limits. Leave as `""` to use the unauthenticated API.

Alternatively set environment variables `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `LLM_MODEL`
(env vars take precedence over the file).

**No backend URL config needed for DIRECT or FAST.** For CAMP: the backend address is fetched
automatically from the project's GitHub Pages config — no local setup required.

## Constants

- **CONFIG_PAGE**: `https://phycholosogy.github.io/Urban_AI_Scientist/config.js`
- **API_BASE**: resolved dynamically from `USER_LLM_API_BASE` key in CONFIG_PAGE (CAMP only)
- **METHODS**: `camp`, `direct`, `fast`
- **Defaults**:
  - temperature: 0.5
  - paper_domain: "Urban Science" (CAMP only)
  - retrieval_limit: 5 (CAMP only)
  - retrieval_method: "mixture" (CAMP only)

---

## Workflow

### Step 1: Parse Arguments

Parse in order:
1. **Mode**: `CAMP`, `DIRECT`, `FAST`, or `novelty` (case-insensitive, first positional arg)
2. **Optional flags**:
   - `--temperature <float>` (CAMP/FAST/novelty)
   - `--paper_domain <string>` (CAMP only)
   - `--retrieval_limit <int>` (CAMP only)
   - `--retrieval_method <string>` (CAMP only)
   - `--source <semantic|arxiv>` (novelty only, default: `semantic`)
3. **Topic or path**:
   - CAMP/DIRECT/FAST: all remaining text is the research topic
   - novelty: single argument is the path to an existing `.md` file

If mode is missing: ask the user to specify one.
If topic/path is empty: ask the user for it.

### Step 2: Load Credentials (CAMP, FAST, and novelty only)

**DIRECT skips this step entirely** — go straight to Step 3.

```bash
if [ -n "$OPENAI_API_KEY" ] && [ -n "$OPENAI_BASE_URL" ] && [ -n "$LLM_MODEL" ]; then
  _OPENAI_API_KEY="$OPENAI_API_KEY"
  _OPENAI_BASE_URL="$OPENAI_BASE_URL"
  _LLM_MODEL="$LLM_MODEL"
  _S2_API_KEY="${SEMANTIC_SCHOLAR_API_KEY:-}"
else
  CRED_FILE=~/.claude/skills/idea-creator-user-llm/credentials.json
  if [ ! -f "$CRED_FILE" ]; then
    echo "ERROR: LLM credentials not found."
    echo "Create $CRED_FILE:"
    echo '  {"openai_api_key": "sk-...", "openai_base_url": "https://...", "llm_model": "gpt-4o-mini", "semantic_scholar_api_key": ""}'
    echo "Or set env vars OPENAI_API_KEY, OPENAI_BASE_URL, LLM_MODEL."
    exit 1
  fi
  _OPENAI_API_KEY=$(python3 -c "import json; print(json.load(open('$CRED_FILE'))['openai_api_key'])")
  _OPENAI_BASE_URL=$(python3 -c "import json; print(json.load(open('$CRED_FILE'))['openai_base_url'])")
  _LLM_MODEL=$(python3 -c "import json; print(json.load(open('$CRED_FILE'))['llm_model'])")
  _S2_API_KEY=$(python3 -c "import json; print(json.load(open('$CRED_FILE')).get('semantic_scholar_api_key',''))")
fi
```

### Step 3: Branch by Mode

#### DIRECT path — skip all credential and backend steps, go directly to Step 4-DIRECT

#### FAST path — credentials already loaded, skip backend URL, go directly to Step 4-FAST

#### novelty path — credentials already loaded, resolve backend URL (same as CAMP), go to Step 4-NOVELTY

#### CAMP path — resolve backend URL:

```bash
CONFIG_PAGE="https://phycholosogy.github.io/Urban_AI_Scientist/config.js"

if [ -n "$USER_LLM_API_BASE" ]; then
  API_BASE="$USER_LLM_API_BASE"
else
  API_BASE=$(curl -s --max-time 15 "$CONFIG_PAGE" | \
    python3 -c "
import sys, re
m = re.search(r'USER_LLM_API_BASE\s*:\s*\"([^\"]+)\"', sys.stdin.read())
print(m.group(1) if m else '')
")
  if [ -z "$API_BASE" ]; then
    echo "ERROR: Could not fetch USER_LLM_API_BASE from $CONFIG_PAGE"
    echo "Check your internet connection, or set env var USER_LLM_API_BASE manually."
    exit 1
  fi
fi
```

### Step 4-DIRECT: Claude-Native Idea Generation (with optional web search)

No external API or backend calls. Claude generates the idea by itself, and autonomously decides whether to first search for relevant papers using its built-in `WebSearch` / `WebFetch` tools.

**0. Decide whether to search for papers** (Claude's autonomous judgment — do not ask the user):

Search if **any** of the following apply:
- The topic involves recent empirical trends, datasets, or domain-specific findings that may post-date Claude's training
- Identifying a concrete research gap requires knowing what has already been published
- A targeted search would plausibly reveal methodological precedents worth building on or departing from

Skip search if: the topic is sufficiently conceptual or broad that Claude's existing knowledge is clearly adequate, or if forming a meaningful query is impractical.

**If searching** — use Claude's built-in `WebSearch` / `WebFetch` tools (no user credentials required):
1. Construct 2–4 targeted queries, for example:
   - `"<topic>" urban science site:arxiv.org`
   - `"<topic>" empirical study`
   - `"<topic>" review methodology`
2. Skim titles and abstracts from results; fetch full abstracts via `WebFetch` when a result looks closely relevant
3. Record the 3–5 most relevant papers: **title, authors, year, key contribution** — these will be used to identify the research gap and populate the References section in the output
4. Print progress: `[web search] ✓  found N relevant papers`

**1. Design the research strategy**: Given the topic (and retrieved papers if any), analyze the strongest, most feasible research direction — evaluate novelty, empirical testability, available data, and methodology. If papers were retrieved, explicitly identify the gap relative to existing work. Select one focused direction.

**2. Generate the idea** with these components:
- A clear, falsifiable research title
- An abstract (150–250 words) describing the research gap, question, proposed data and method, expected hypothesis or relationship, and contribution

**3. Quality-check the generated idea**:
- Is the research question clear and falsifiable?
- Is the methodology feasible with available data?
- Is the contribution novel (relative to retrieved papers if any, or to Claude's training knowledge)?
- If any criterion fails, refine the idea before saving.

### Step 4-FAST: Direct LLM Generation (1 idea)

No backend call. Call the user's LLM directly with the urban science expert prompt.

```bash
_ULM_TOPIC="<topic>" \
_ULM_TEMP="<temperature>" \
_OPENAI_API_KEY="$_OPENAI_API_KEY" \
_OPENAI_BASE_URL="$_OPENAI_BASE_URL" \
_LLM_MODEL="$_LLM_MODEL" \
python3 - << 'PYEOF'
import json, os, sys, urllib.request, urllib.error

api_key  = os.environ["_OPENAI_API_KEY"]
base_url = os.environ["_OPENAI_BASE_URL"].rstrip("/")
model    = os.environ["_LLM_MODEL"]
topic    = os.environ["_ULM_TOPIC"]
temperature = float(os.environ.get("_ULM_TEMP", "0.5"))

PROMPT = f"""You are an expert in urban climate science, climate-responsive urban design, extreme heat, urban resilience, urban climate modeling, radiative cooling, and climate–urban interactions.

Based on the topic or keywords provided below, generate exactly 1 original and publishable urban science research idea.

Input topic:
{topic}


Requirements:

- The idea must address a clear scientific question, research gap, urban mechanism, or testable hypothesis.
- Prioritize feasible data and methods, including remote sensing, weather observations, urban morphology, building data, street-view imagery, demographic data, CFD, urban climate models, building-energy simulation, spatial statistics, causal inference, and cross-city comparison.
- Avoid generic sustainability topics and ideas whose main novelty is simply using a new machine-learning model.
- Do not fabricate results. Write the abstract as a proposed study.
- The abstract should be 150–200 words.
- All content must be in English.

Return only a valid JSON object. Do not include Markdown, comments, explanations, or text before or after the JSON.

Use exactly this structure:

{{
  "topic": "[repeat the original input topic exactly]",
  "title": "A concise, publication-ready academic title",
  "abstract": "A 150–200-word abstract describing the research gap, scientific question, proposed data, methods, expected contribution, and practical relevance."
}}

Ensure that the output is syntactically valid JSON, uses double quotation marks, contains no trailing commas, and can be parsed directly by a JSON parser."""

body = {
    "model": model,
    "messages": [{"role": "user", "content": PROMPT}],
    "temperature": temperature,
}

req = urllib.request.Request(
    f"{base_url}/chat/completions",
    data=json.dumps(body).encode(),
    headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    },
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.load(resp)
except urllib.error.URLError as e:
    msg = str(e).replace(api_key, api_key[:4] + "****" + api_key[-4:])
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

content = data["choices"][0]["message"]["content"].strip()

# Strip markdown code fences if model wrapped the JSON
if content.startswith("```"):
    content = content.split("```", 2)[1]
    if content.startswith("json"):
        content = content[4:]
    content = content.rsplit("```", 1)[0].strip()

idea = json.loads(content)
assert isinstance(idea, dict) and "title" in idea and "abstract" in idea, "Invalid idea structure"

with open("/tmp/urban_ai_fast_done.json", "w", encoding="utf-8") as f:
    json.dump({"idea": idea}, f, ensure_ascii=False, indent=2)

print(f"  [FAST] Idea generated ✓", flush=True)
PYEOF
```

On error: STOP and report. On success: idea is in `/tmp/urban_ai_fast_done.json`.

**NEVER print `_OPENAI_API_KEY` in any output.**

### Step 4-CAMP: Call Backend with SSE Stream

Build the request body using Python so the API key never appears in shell process arguments:

```bash
_ULM_TOPIC="<topic>" \
_ULM_METHOD="<camp_or_direct>" \
_ULM_TEMP="<temperature>" \
_ULM_DOMAIN="<paper_domain>" \
_ULM_LIMIT="<retrieval_limit>" \
_ULM_RMETHOD="<retrieval_method>" \
_OPENAI_API_KEY="$_OPENAI_API_KEY" \
_OPENAI_BASE_URL="$_OPENAI_BASE_URL" \
_LLM_MODEL="$_LLM_MODEL" \
_API_BASE="$API_BASE" \
python3 - << 'PYEOF'
import json, os, sys, urllib.request, urllib.error

api_key  = os.environ["_OPENAI_API_KEY"]
base_url = os.environ["_OPENAI_BASE_URL"]
api_base = os.environ["_API_BASE"]

body = {
    "topic":            os.environ["_ULM_TOPIC"],
    "method":           os.environ["_ULM_METHOD"],
    "temperature":      float(os.environ.get("_ULM_TEMP", "0.5")),
    "paper_domain":     os.environ.get("_ULM_DOMAIN", "Urban Science"),
    "retrieval_limit":  int(os.environ.get("_ULM_LIMIT", "5")),
    "retrieval_method": os.environ.get("_ULM_RMETHOD", "mixture"),
    "openai_api_key":   api_key,
    "openai_base_url":  base_url,
    "llm_model":        os.environ["_LLM_MODEL"],
}

req = urllib.request.Request(
    f"{api_base}/api/generate/stream",
    data=json.dumps(body).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=300) as resp:
        done_data = None
        for raw_line in resp:
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line.startswith("data:"):
                continue
            payload = json.loads(line[5:].strip())
            event = payload.get("event")
            if event == "step":
                label = payload.get("label", payload.get("key", ""))
                print(f"  [{label}] ✓", flush=True)
            elif event == "error":
                msg = payload.get("message", "unknown error")
                print(f"\nERROR: {msg}", file=sys.stderr)
                sys.exit(1)
            elif event == "done":
                done_data = payload
                break
        if done_data:
            with open("/tmp/urban_ai_done.json", "w", encoding="utf-8") as f:
                json.dump(done_data, f, ensure_ascii=False, indent=2)
except urllib.error.URLError as e:
    msg = str(e).replace(api_key, api_key[:4] + "****" + api_key[-4:])
    print(f"\nERROR: Cannot reach backend: {msg}", file=sys.stderr)
    sys.exit(1)
PYEOF
```

On `error`: STOP and report. On `done`: `new_idea` field contains the generated idea.

**NEVER print `_OPENAI_API_KEY` in any output.**

### Step 4-NOVELTY: Call Backend Novelty Check

First, parse the `.md` file to extract Title and Abstract:

```bash
_ULM_MD_PATH="<path to .md file>"
_ULM_SOURCE="<semantic|arxiv>"  # default: semantic

python3 - << 'PYEOF'
import os, re, sys

md_path = os.environ["_ULM_MD_PATH"]
with open(md_path, encoding="utf-8") as f:
    content = f.read()

# Extract Title (line after "## Title")
title_m = re.search(r"##\s+Title\s*\n+(.+)", content)
# Extract Abstract (text after "## Abstract" until next ## or end)
abstract_m = re.search(r"##\s+Abstract\s*\n+([\s\S]+?)(?=\n##|\Z)", content)

if not title_m or not abstract_m:
    print("ERROR: Could not find Title or Abstract in the .md file.", file=sys.stderr)
    sys.exit(1)

title    = title_m.group(1).strip()
abstract = abstract_m.group(1).strip()

with open("/tmp/urban_ai_novelty_input.json", "w", encoding="utf-8") as f:
    import json
    json.dump({"title": title, "abstract": abstract}, f, ensure_ascii=False)

print(f"Title:    {title[:80]}")
print(f"Abstract: {abstract[:120]}...")
PYEOF
```

If parsing fails: STOP and report. Then call the backend:

```bash
_OPENAI_API_KEY="$_OPENAI_API_KEY" \
_OPENAI_BASE_URL="$_OPENAI_BASE_URL" \
_LLM_MODEL="$_LLM_MODEL" \
_S2_API_KEY="$_S2_API_KEY" \
_ULM_SOURCE="$_ULM_SOURCE" \
_ULM_TEMP="<temperature>" \
_API_BASE="$API_BASE" \
python3 - << 'PYEOF'
import json, os, sys, urllib.request, urllib.error

api_key = os.environ["_OPENAI_API_KEY"]
s2_key  = os.environ.get("_S2_API_KEY", "")
api_base = os.environ["_API_BASE"]

with open("/tmp/urban_ai_novelty_input.json", encoding="utf-8") as f:
    idea = json.load(f)

body = {
    "title":                     idea["title"],
    "abstract":                  idea["abstract"],
    "source":                    os.environ.get("_ULM_SOURCE", "semantic"),
    "openai_api_key":            api_key,
    "openai_base_url":           os.environ["_OPENAI_BASE_URL"],
    "llm_model":                 os.environ["_LLM_MODEL"],
    "temperature":               float(os.environ.get("_ULM_TEMP", "0.5")),
    "semantic_scholar_api_key":  s2_key,
}

req = urllib.request.Request(
    f"{api_base}/api/novelty/stream",
    data=json.dumps(body).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=300) as resp:
        done_data = None
        for raw_line in resp:
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line.startswith("data:"):
                continue
            payload = json.loads(line[5:].strip())
            event = payload.get("event")
            if event == "step":
                print(f"  [{payload.get('label', payload.get('key',''))}] ✓", flush=True)
            elif event == "error":
                msg = payload.get("message", "unknown error")
                print(f"\nERROR: {msg}", file=sys.stderr)
                sys.exit(1)
            elif event == "done":
                done_data = payload
                break
        if done_data:
            with open("/tmp/urban_ai_novelty_done.json", "w", encoding="utf-8") as f:
                json.dump(done_data, f, ensure_ascii=False, indent=2)
except urllib.error.URLError as e:
    msg = str(e).replace(api_key, api_key[:4] + "****" + api_key[-4:])
    print(f"\nERROR: Cannot reach backend: {msg}", file=sys.stderr)
    sys.exit(1)
PYEOF
```

On `error`: STOP and report. On `done`: result is in `/tmp/urban_ai_novelty_done.json`.

**NEVER print `_OPENAI_API_KEY` or `_S2_API_KEY` in any output.**

### Step 5: Save Result

Save to `./idea-output/` relative to the **current working directory**.

#### FAST — save idea from `/tmp/urban_ai_fast_done.json`:

Filename: `./idea-output/YYYY-MM-DD_<topic-slug>_fast.md`

```markdown
# Generated Idea

**Method**: FAST
**Topic**: <topic>
**Model**: <llm_model>
**Parameters**: <non-default params if any>
**Generated**: <ISO timestamp>

## Title
<idea["title"]>

## Abstract
<idea["abstract"]>
```

#### DIRECT — save Claude-generated idea (constructed directly in memory, no temp file):

Filename: `./idea-output/YYYY-MM-DD_<topic-slug>_direct.md`

```markdown
# Generated Idea

**Method**: DIRECT
**Topic**: <topic>
**Web Search**: <Yes — N papers consulted | No>
**Parameters**: <non-default params if any>
**Generated**: <ISO timestamp>

## Title
<title>

## Abstract
<abstract>

## References Consulted
<!-- Include only if web search was performed; omit this section entirely otherwise -->
- <Author(s) (Year). Title. Venue/URL>
- ...
```

#### CAMP — save single idea from `/tmp/urban_ai_done.json`:

Filename: `./idea-output/YYYY-MM-DD_<topic-slug>_camp.md`

```markdown
# Generated Idea

**Method**: CAMP
**Topic**: <topic>
**Model**: <llm_model>
**Parameters**: <non-default params if any>
**Generated**: <ISO timestamp>

## Title
<new_idea["Title"] or new_idea["title"]>

## Abstract
<new_idea["Abstract"] or new_idea["abstract"]>
```

#### novelty — append `## Novelty Check` to the **original input `.md` file**:

Do NOT create a new file. Open the input `.md` file and append the section below.
Read `/tmp/urban_ai_novelty_done.json` to get `summarized_novelty_result` and `analyzed_papers`.

```markdown

---

## Novelty Check

**Source**: semantic / arxiv
**Model**: <llm_model>
**Checked**: <ISO timestamp>

### Summary

<summarized_novelty_result>

### Papers Analyzed (<N> papers)

1. **<analyzed_papers[0].title>**
   <analyzed_papers[0].analysis>

2. **<analyzed_papers[1].title>**
   <analyzed_papers[1].analysis>

... (all analyzed papers)
```

### Step 6: Display Results

Show:
1. Method and parameters used
2. Step-by-step progress (CAMP: SSE steps; DIRECT: Claude reasoning progress; FAST: model call progress)
3. The generated idea(s): title + abstract for each
4. Save location

---

## Key Rules

### Security
- **NEVER print, echo, or log `_OPENAI_API_KEY` or `_S2_API_KEY`** in any output or error message.
- Pass credentials via environment variables into the Python subprocess — never inline in shell arguments.
- Mask both keys (first4****last4) before displaying any error message that might contain them.
- **DIRECT requires no credentials** — do not prompt for them.

### Autonomy
- **NEVER ask the user a question or wait for input.** Auto-select defaults.
- **No auto-fallback**: if any method fails, report the error as-is and stop.

### General
- **Topic and method are required.**
- **Show step progress** so the user can see generation is proceeding.
- Credentials file missing (CAMP/FAST) → print setup instructions and stop cleanly.
- CONFIG_PAGE fetch failure (CAMP) → print troubleshooting hint and stop cleanly.
- **DIRECT can optionally use web search** — Claude's built-in `WebSearch`/`WebFetch` tools require no credentials. If web search is unavailable, Claude falls back to generating the idea from its own knowledge without error.
