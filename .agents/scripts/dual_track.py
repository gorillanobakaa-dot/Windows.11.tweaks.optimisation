#!/usr/bin/env python3
"""
dual_track.py
=============
Dual-Track Generator — IBM/DITA edition.

Turns source code OR a changelog/diff into two parallel, complete documents:
  - DITA-structured developer documentation (concept + reference + task topics)
  - IBM-style plain-language explanation for non-technical readers

Neither track is a summary of the other. Both are full translations for
different audiences, structured according to IBM DITA information types.

THIS SCRIPT NEVER MAKES A NETWORK CALL. It has two jobs:

  PREP:   read your source and write a plain JSON file containing a system
          prompt, user prompt, and JSON Schema. That file is the complete spec.
  RENDER: read back a filled JSON file and render it to polished Markdown.

Whatever fills the JSON — Claude, GPT, a human, a shell pipeline — is
responsible for the middle step. This script doesn't care how it happens.

DITA INFORMATION TYPES USED
  concept       — background, context, "what is this"
  task          — numbered steps, prerequisites, expected results
  reference     — tables of flags, APIs, error codes, file lists
  troubleshoot  — symptom → cause → remedy triples

IBM STYLE RULES BAKED IN
  - Active voice, second person ("you"), present tense
  - One idea per sentence, one topic per section
  - Lead with the user's task, not the product's feature
  - Concrete specifics; no marketing language
  - Claim sourcing: every fact traceable to input or flagged as inference

INSTALLED AS `dual-track` ON PATH
This script is symlinked to ~/.local/bin/dual-track, so it runs from ANY project
directory — the kernel patch repo, the Firefox work tree, pfind, anywhere. It is
project-agnostic by design: it reads whatever source or changelog you point it at
and auto-detects the surrounding git repo, language and siblings for context.
There is no per-project configuration and nothing to copy into a new project.

USAGE
    # Source code -> two docs
    dual-track code prep internal/tui/tui.go --output-dir ./docs
    # ... fill the .prep.json files ...
    dual-track code render internal/tui/tui.go --output-dir ./docs --validate

    # Changelog/diff -> release notes
    dual-track release prep --input DEVELOPER-TRACK.md --output-dir Changelogs
    # ... fill the .prep.json files ...
    dual-track release render --output-dir Changelogs --validate

    # Pipe a diff directly
    git log v1..HEAD --stat | dual-track release prep --stdin --output-dir Changelogs

ALWAYS PASS --validate ON RENDER. It checks the required DITA topics are present,
that no banned marketing phrase survived, and that the document contains concrete
numbers. It exits 2 if any check fails, and writes the markdown anyway so you can
read what needs fixing.
"""

import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path


class DualTrackError(Exception):
    """Unrecoverable error. CLI catches this and exits with a message."""
    pass


# ══════════════════════════════════════════════════════════════════════
#  IBM STYLE RULES (injected into every system prompt)
# ══════════════════════════════════════════════════════════════════════

_IBM_STYLE = """IBM documentation style rules — apply ALL of these precisely:

VOICE AND TENSE (ibm-style?topic=language-grammar-verbs)
- Active voice only. "The function returns X" not "X is returned by the function".
  Rewrite every passive construction: "was committed" -> "you committed",
  "was verified" -> "the test verified", "was derived" -> "the analysis derived".
- Present tense throughout — even for historical descriptions of software behaviour.
  "The file contains 1969 lines" not "The file contained 1969 lines".
  "The bug is fixed" not "The bug was fixed".
  Exception: the Before/After comparison sections, where past tense is accurate.
- Second person only. "You configure", not "the user configures", not "we configured".

HEADINGS (ibm-style?topic=structure-format-headings)
- Sentence case for ALL headings. Capitalise only the first word and proper nouns.
  "What changed for you" not "What Changed For You".
  "Honest state of play" not "Honest State of Play".
  "Should you be concerned?" not "Should You Be Concerned?".

NUMBERS (ibm-style?topic=numbers-measurement-numerals-versus-words)
- Spell out zero through nine as words. Use numerals for 10 and above.
  "six missing environment variables" not "6 missing environment variables".
  "nine partial implementations" not "9 partial implementations".
  Exception: line numbers, version strings, file sizes, percentages, step numbers.

CODE AND FILE REFERENCES (ibm-style?topic=structure-format-highlighting)
- Every file name, path, flag, command, and code token must be in backticks.
  "`pfind.py`" not "pfind.py". "`--glob`" not "--glob". "`STATUS_REPORT.md`" not
  "STATUS_REPORT.md". "`args.globs`" not "args.globs". This applies everywhere:
  prose sentences, bullet points, table cells, headings.

WORD CHOICE (ibm-style?topic=tone, ibm-style?topic=language-grammar-adverbs-only)
- No marketing language. Banned: "powerful", "seamlessly", "robust", "easy to use",
  "best-in-class", "cutting-edge", "enhanced user experience", "significant
  improvements", "various bug fixes", "under the hood", "we are excited to announce",
  "performance optimizations", "various" (name the specific things instead).
- No weak adverbs that add no meaning: "rather", "quite", "very", "fairly",
  "somewhat", "pretty much". Delete them or replace with a stronger word.
- No minimiser words that dismiss user difficulty: "simply", "just", "easy",
  "obviously", "straightforward", "trivial", "all you need to".
- No self-congratulation. Do not describe the work as a triumph, elegant, masterful,
  perfect, or flawless. No dramatic framing: "neutralized", "battle", "heroic",
  "landmark". Do not write "I proved", "I immediately", "I discovered".

PROCEDURES (ibm-style?topic=structure-format-procedures)
- Every step in a procedure must state its expected result explicitly.
  Use "- **Pass:** <what success looks like>" on the line after the action.
  Use "- **Fail:** <what a broken state shows>" where relevant.

GENERAL
- One idea per sentence. One topic per section. No run-on explanations.
- Lead with the user's goal, not the product's feature.
- Concrete and specific: name the thing, give the number, state the version.
- If information is not in the source, write exactly:
  "Not available in the source material." Do not invent plausible answers."""

_CLAIM_SOURCING = """Claim sourcing — required for every CONCLUSION or ASSESSMENT:
Add one entry to "claim_sources" for each conclusion, comparison, or assessment —
any statement that required reasoning rather than copying. Do NOT add entries for
raw facts you quoted directly (line counts, file names, quoted strings). The table
exists to flag inferences a reader cannot independently verify.
Each entry has:
  "claim"    — the conclusion in a few words (e.g. "implementation is 80% complete")
  "basis"    — "stated_in_input" or "model_inference"
  "evidence" — the exact short phrase from the input that led to this conclusion,
               or null if basis is "model_inference"
Mark inferences honestly. A claim_sources list containing only "stated_in_input"
entries is a red flag — every assessment involves inference. Under-claiming
confidence is always safer than over-claiming it."""

_FILL_ALL_FIELDS = """Fill every field in the schema. If a field does not apply,
write "N/A — <one-line reason>" rather than omitting the field or leaving it blank."""


def _arr(item_props: dict, required: list = None) -> dict:
    """An array-of-objects schema whose ITEMS are constrained, not just typed."""
    return {"type": "array",
            "items": {"type": "object", "properties": item_props,
                      "required": required or list(item_props.keys())}}


# The claim-sourcing schema, enforced by the MACHINE and not merely described in
# the prompt.
#
# RESTORED 2026-07-30 from the pre-DITA ancestor at
# Scripts.For.Work/Documentation.Writing.Scripts/dual_track.py. The IBM/DITA
# rewrite replaced this with a bare {"type": "array", "items": {"type":
# "object"}} on every track, which accepts literally any object — a model could
# return [{"foo": 1}] and satisfy the schema.
#
# That is the wrong thing to leave unconstrained. Claim sourcing is the whole
# mechanism by which a reader can tell a measured fact from a model's guess, and
# PHILOSOPHY.md puts it plainly: "No one should have to trust a summary they
# cannot verify." The enum is what makes `basis` checkable rather than
# free-text — and score_document reads `basis == "stated_in_input"` exactly, so
# a model spelling it "stated in input" would silently score zero for evidence
# while looking perfectly well-sourced to a human.
#
# `evidence` stays nullable on purpose: a model_inference has no quoted evidence,
# and forcing a string there would invite one to be invented.
_CLAIM_SOURCES_FIELD = _arr(
    {"claim": {"type": "string"},
     "basis": {"type": "string", "enum": ["stated_in_input", "model_inference"]},
     "evidence": {"type": ["string", "null"]}},
    required=["claim", "basis"])


# ══════════════════════════════════════════════════════════════════════
#  DITA TOPIC SCHEMAS — CODE MODE
# ══════════════════════════════════════════════════════════════════════

# ── Developer track: concept + reference + task topics ────────────────

CODE_DEV_SYSTEM = f"""You are writing DITA-structured internal documentation for engineers
who will maintain, fork, or audit this code. Structure your output as three
DITA information types: concept (what and why), reference (tables of facts),
and task (how to operate it). Lead with WHY before HOW. Call out dead code,
tech debt, and security implications explicitly. Neutral, factual tone.

{_IBM_STYLE}
{_CLAIM_SOURCING}
{_FILL_ALL_FIELDS}
Respond with ONLY valid JSON matching the schema. No markdown fence, no text
before or after the JSON object."""

CODE_DEV_SCHEMA_HINT = """{
  "title": "Technical title for this module",

  /* DITA CONCEPT TOPIC — what this module is and why it exists */
  "concept": {
    "purpose": "One paragraph: the module's role in the system and trust level.",
    "known_alternatives": "Alternatives that were NOT chosen. Quote source comments explaining why. If none are documented, write 'Not available in the source material.' Do not infer rationale from the code structure.",
    "architecture": {
      "pattern": "e.g. Elm MVC, event loop, middleware chain",
      "dependencies": ["exact import or package name"],
      "trust_boundary": "What this code trusts and what it does not.",
      "attack_surface": "Entry points an attacker could reach."
    }
  },

  /* DITA REFERENCE TOPIC — lookup tables */
  "reference": {
    "flags": [{"name": "flag", "type": "bool|string|int", "default": "value",
               "effect": "what changes", "notes": "gotchas"}],
    "kill_switches": [{"location": "func or line", "condition": "when it fires",
                       "effect": "what it does", "reversible": true,
                       "notes": "operational notes"}],
    "api_surface": [{"symbol": "FuncName()", "signature": "full Go/Python/etc sig",
                     "description": "one-line purpose", "side_effects": "or none"}],
    "error_conditions": [{"code_or_message": "...", "cause": "...", "remedy": "..."}],
    "dead_code": [{"location": "...", "reason": "why it is dead", "risk": "if removed"}],
    "performance": {"cpu": "...", "memory": "...", "io": "...", "notes": "..."},
    "security": {"remote_execution": "...", "data_handling": "...",
                 "attack_surface": "...", "notes": "..."}
  },

  /* DITA TASK TOPIC — numbered steps to operate, test, or modify */
  "tasks": [
    {
      "task_title": "e.g. Run the unit tests for this module",
      "context": "When and why you would do this",
      "prerequisites": ["what must be true before you start"],
      "steps": [{"step": 1, "action": "exact command or code", "expected_result": "..."}],
      "post_conditions": "What is true after the task succeeds"
    }
  ],

  /* DITA TROUBLESHOOT TOPIC */
  "troubleshooting": [
    {"symptom": "...", "probable_cause": "...", "remedy": "...", "verification": "..."}
  ],

  "technical_debt": [{"item": "...", "severity": "low|medium|high",
                      "recommendation": "specific next action"}],
  "impact_if_removed": "What breaks or degrades if this module is deleted.",

  "claim_sources": [{"claim": "short fact", "basis": "stated_in_input or model_inference",
                     "evidence": "exact phrase or null"}]
}"""

CODE_DEV_JSONSCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "concept": {"type": "object", "properties": {
            "purpose": {"type": "string"},
            "known_alternatives": {"type": "string"},
            "architecture": {"type": "object", "properties": {
                "pattern": {"type": "string"},
                "dependencies": {"type": "array", "items": {"type": "string"}},
                "trust_boundary": {"type": "string"},
                "attack_surface": {"type": "string"}}}}},
        "reference": {"type": "object", "properties": {
            "flags": {"type": "array", "items": {"type": "object"}},
            "kill_switches": {"type": "array", "items": {"type": "object"}},
            "api_surface": {"type": "array", "items": {"type": "object"}},
            "error_conditions": {"type": "array", "items": {"type": "object"}},
            "dead_code": {"type": "array", "items": {"type": "object"}},
            "performance": {"type": "object"},
            "security": {"type": "object"}}},
        "tasks": {"type": "array", "items": {"type": "object"}},
        "troubleshooting": {"type": "array", "items": {"type": "object"}},
        "technical_debt": {"type": "array", "items": {"type": "object"}},
        "impact_if_removed": {"type": "string"},
        "claim_sources": _CLAIM_SOURCES_FIELD,
    },
    "required": ["title", "concept", "reference", "tasks", "impact_if_removed", "claim_sources"],
}

# ── Layman track: IBM plain-language concept + task topics ─────────────

CODE_LAYMAN_SYSTEM = f"""You are writing for someone who is about to run this code on their own
computer and cannot read it themselves. They are trusting a stranger with their
machine, their data, and possibly their money. That is a real, asymmetric risk.
Treat it seriously. This is not a "fun facts" explainer — it is the information
someone needs to make an informed decision about a real risk.

Apply IBM plain-language documentation principles:
- Write for a reading level of grade 8 (clear, direct sentences).
- Use second person: "you", not "the user" or "one".
- One idea per sentence. No jargon without an immediate real-world analogy.
- Be honest, including when the honest answer is "do not run this unless X."
- Explicitly state what data this code touches or sends, the realistic worst
  outcome if it is buggy or malicious, and concrete steps the reader can take
  to verify it — not "read the source code", they cannot.
- VERBOSITY AND ANALOGIES REQUIRED: Loosen the stiffness. Write expansively. Use rich, detailed, conversational analogies to fully illustrate the mechanism to a layperson without summarizing.
- Structure as IBM DITA concept (what it is) + task (what you do) topics.

{_IBM_STYLE}
{_CLAIM_SOURCING}
{_FILL_ALL_FIELDS}
Respond with ONLY valid JSON matching the schema. No markdown fence, no text
before or after the JSON object."""

CODE_LAYMAN_SCHEMA_HINT = """{
  "title": "Plain-English title — what this program does, not its technical name",

  /* DITA CONCEPT TOPIC — what this is */
  "concept": {
    "big_picture": "2-3 short paragraphs: what this code does in your real life.",
    "key_concepts": [{"name": "TechnicalWord", "plain_english": "what it means",
                      "analogy": "real-world comparison"}],
    "data_and_privacy": "What data this touches, sends, or stores. If nothing leaves your machine, say so explicitly.",
    "worst_case": "The most harmful outcome that is plausible given what this code actually does. State it in terms of what the user would experience, with a concrete example. Not catastrophized, not minimized. If you cannot name a specific harm, write 'Not available in the source material.' Do not write 'incorrect results' as a catch-all — name the specific result that would be incorrect and what it would cost the user."
  },

  /* DITA CONCEPT TOPIC — the walkthrough. NOT a summary of the developer track:
     the same mechanism, told so a non-coder follows the actual chain of events. */
  "how_it_works": [
    {"step": 1, "title": "Short name for this stage",
     "explanation": "What actually happens here, in plain language with an analogy. State what the code really does, not what it is for."}
  ],

  /* The surprising, counterintuitive or easily-misread parts. Include anything a
     reader would otherwise get WRONG on a first reading. */
  "quirky_things": [{"title": "...", "explanation": "why it is surprising and what it means for you"}],

  /* What this does to the machine and the person using it. "N/A — not measured"
     is a valid and expected answer; never estimate a number silently. */
  "real_world_impact": {
    "battery_cpu_ram": "Effect on battery, processor load and memory — with numbers if they were supplied, otherwise 'not measured'.",
    "speed": "Does anything get faster or slower, and by how much.",
    "your_privacy": "What this means for your privacy specifically.",
    "your_internet": "Effect on network use, connections or data allowance."
  },

  /* Any switch, guard or flag that turns behaviour off — the thing a worried
     reader most wants to find. Use "N/A — none" if there is none. */
  "kill_switch_explained": {
    "what_it_is": "The off switch, named and located in plain terms.",
    "without_it": "What would happen if it were not there.",
    "real_life_analogy": "A physical comparison."
  },

  /* Why being able to READ this at all matters — the transparency angle. This is
     the point of the whole exercise, not a footnote. */
  "open_source_angle": "Why it matters that you can inspect this yourself, and what you would be trusting blindly if you could not.",

  /* DITA TASK TOPIC — what you do before trusting it */
  "verification_task": {
    "task_title": "How to check this before you trust it",
    "context": "Why you should check before running unfamiliar code.",
    "steps": [{"step": 1, "action": "Concrete, doable step a non-coder can actually take.",
               "what_to_look_for": "How you know this step passed or failed."}]
  },

  /* DITA TASK TOPIC — how to use it */
  "usage_task": {
    "task_title": "How to use this",
    "prerequisites": ["what you need before starting"],
    "steps": [{"step": 1, "action": "...", "expected_result": "..."}]
  },

  /* DITA TROUBLESHOOT TOPIC */
  "troubleshooting": [
    {"symptom": "Something you might see go wrong",
     "plain_cause": "Why it happened, in plain language",
     "remedy": "What you do about it"}
  ],

  "should_you_run_this": "Honest, specific recommendation: run it / do not / only if X. Not a hedge.",
  "why_it_matters": "Why a developer would make these choices — in plain language.",
  "glossary": [{"term": "...", "definition": "one sentence, no jargon"}],

  "claim_sources": [{"claim": "short fact", "basis": "stated_in_input or model_inference",
                     "evidence": "exact phrase or null"}]
}"""

CODE_LAYMAN_JSONSCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "concept": {"type": "object", "properties": {
            "big_picture": {"type": "string"},
            "key_concepts": {"type": "array", "items": {"type": "object"}},
            "data_and_privacy": {"type": "string"},
            "worst_case": {"type": "string"}}},
        "how_it_works": {"type": "array", "items": {"type": "object"}},
        "quirky_things": {"type": "array", "items": {"type": "object"}},
        "real_world_impact": {"type": "object", "properties": {
            "battery_cpu_ram": {"type": "string"},
            "speed": {"type": "string"},
            "your_privacy": {"type": "string"},
            "your_internet": {"type": "string"}}},
        "kill_switch_explained": {"type": "object", "properties": {
            "what_it_is": {"type": "string"},
            "without_it": {"type": "string"},
            "real_life_analogy": {"type": "string"}}},
        "open_source_angle": {"type": "string"},
        "verification_task": {"type": "object"},
        "usage_task": {"type": "object"},
        "troubleshooting": {"type": "array", "items": {"type": "object"}},
        "should_you_run_this": {"type": "string"},
        "why_it_matters": {"type": "string"},
        "glossary": {"type": "array", "items": {"type": "object"}},
        "claim_sources": _CLAIM_SOURCES_FIELD,
    },
    "required": ["title", "concept", "how_it_works", "real_world_impact",
                 "open_source_angle", "verification_task", "should_you_run_this",
                 "claim_sources"],
}


# ══════════════════════════════════════════════════════════════════════
#  AUDIT TRACK  (merged from doc_audit.py, 2026-07-30)
# ══════════════════════════════════════════════════════════════════════
#
# The third document. Layman and developer tracks explain what a thing IS; the
# audit answers "is it ready to ship, and what is still wrong with it".
#
# It is IBM-sectioned A–F and it is deliberately dual-track inside itself:
# Section B is the layman executive summary, Section C the technical one. A
# release decision that only a developer can read fails the same test as
# documentation only a developer can read.
#
# Section D merges the rule-based pre-check findings FIRST, then the model's.
# Each defect keeps a `basis` of "rule" or "model" so nobody has to guess which
# findings are facts and which are opinions.

AUDIT_SYSTEM = f"""You are producing an IBM-style readiness audit of the material below.
You are not summarising it and you are not selling it. You are answering one
question for someone about to decide whether to ship: what is wrong with this,
how bad is it, and what is left to do.

Two audiences read this single document, so two summaries are mandatory:
Section B is for a non-technical decision maker, Section C for an engineer.
Neither is a shortened version of the other.

Severity scale, and be strict about it:
  P0 — ships broken, or a security hole. Blocks release outright.
  P1 — will fail the build, or a serious functional defect.
  P2 — real problem, does not block release.
  P3 — minor, worth noting.

{_IBM_STYLE}
{_CLAIM_SOURCING}
{_FILL_ALL_FIELDS}

The readiness score must be justified by what you found. Do not award a high
score for material you could not verify — say what you could not check and score
it down. An audit that flatters is worthless.

Respond with ONLY valid JSON matching the schema. No markdown fence, no text
before or after the JSON object."""

AUDIT_SCHEMA_HINT = """{
  "target": "what was audited",
  "status": "PASS or FAIL — one word",

  /* SECTION B — for a non-technical reader. One physical metaphor allowed. */
  "executive_summary_layman": "What state this is in and whether it is safe to ship, in plain language.",

  /* SECTION C — for an engineer. Architecture, trade-offs, exact mechanisms. */
  "technical_summary_developer": "The same verdict, in technical terms.",

  /* SECTION D — model-found defects. Rule-found ones are merged in automatically,
     so do NOT repeat anything already listed in the pre-check. */
  "defects": [
    {"id": "P1-101", "severity": "P0|P1|P2|P3",
     "track_a": "the problem in plain language, with a physical analogy",
     "track_b": "file, line, symbol, mechanism",
     "remediation": "the specific action that fixes it",
     "effort": "e.g. 30min, 2h"}
  ],

  /* SECTION E — readiness. Be honest; an unverifiable claim scores DOWN. */
  "readiness": {
    "score_percent": 0,
    "done": ["what is genuinely finished"],
    "blockers": ["what must be resolved before shipping"],
    "todo": ["what remains but does not block"],
    "not_verified": ["what you could NOT check, and why — never leave this empty by default"]
  },

  /* SECTION F — what to do next, in phases. */
  "expansion_plan": [{"target": "file/function", "tweak": "...", "phase": "0|1|2", "impact": "..."}],

  "positive_observations": ["things that are genuinely right — real ones only"],
  "verification_commands": ["shell commands that PROVE the claims above"],

  "claim_sources": [{"claim": "short fact", "basis": "stated_in_input or model_inference",
                     "evidence": "exact phrase or null"}]
}"""

AUDIT_JSONSCHEMA = {
    "type": "object",
    "properties": {
        "target": {"type": "string"},
        "status": {"type": "string"},
        "executive_summary_layman": {"type": "string"},
        "technical_summary_developer": {"type": "string"},
        "defects": {"type": "array", "items": {"type": "object"}},
        "readiness": {"type": "object", "properties": {
            "score_percent": {"type": "number"},
            "done": {"type": "array", "items": {"type": "string"}},
            "blockers": {"type": "array", "items": {"type": "string"}},
            "todo": {"type": "array", "items": {"type": "string"}},
            "not_verified": {"type": "array", "items": {"type": "string"}}}},
        "expansion_plan": {"type": "array", "items": {"type": "object"}},
        "positive_observations": {"type": "array", "items": {"type": "string"}},
        "verification_commands": {"type": "array", "items": {"type": "string"}},
        "claim_sources": _CLAIM_SOURCES_FIELD,
    },
    "required": ["target", "status", "executive_summary_layman",
                 "technical_summary_developer", "readiness", "claim_sources"],
}


def render_audit(d: dict, target: str, infos: list = None,
                 precheck: list = None) -> str:
    """Render the audit as IBM Sections A–F.

    `precheck` defects are placed ahead of the model's, each tagged with its
    basis, because a deterministic finding and a model's opinion are different
    kinds of claim and the reader must be able to tell them apart at a glance.
    """
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    files = ", ".join(i.get('ref', i['name']) for i in infos) if infos else "see payload"

    L = [f"# IBM-Style Audit Report: {target}", "",
         "## SECTION A: DOCUMENT CONTROL", "",
         "| Attribute | Value |", "|---|---|",
         f"| **Target** | {target} |",
         f"| **Files scanned** | {files} |",
         f"| **Date / time** | {now} |",
         f"| **Audit status** | {d.get('status', 'N/A')} |", "",
         "## SECTION B: EXECUTIVE SUMMARY (Plain Language)", "",
         d.get("executive_summary_layman", "*Not supplied.*"), "",
         "## SECTION C: TECHNICAL SUMMARY (Developer)", "",
         d.get("technical_summary_developer", "*Not supplied.*"), "",
         "## SECTION D: DETECTED DEFECTS", ""]

    rule_defects = list(precheck or [])
    model_defects = [dict(x, basis=x.get('basis', 'model'))
                     for x in d.get("defects", [])]
    defects = rule_defects + model_defects

    if defects:
        L += [f"{len(rule_defects)} found by rules, {len(model_defects)} by "
              f"review. Rule findings are deterministic; review findings are "
              f"judgement.", ""]
        for f in defects:
            sev = f.get('severity', 'P3')
            basis = "rule" if f.get('basis') == 'rule' else "review"
            L += [f"### {SEV_EMOJI.get(sev, '🔵')} {f.get('id','')} — {sev} "
                  f"*(found by {basis})*", "",
                  f"- **Plain English:** {f.get('track_a','')}",
                  f"- **Technical:** {f.get('track_b','')}",
                  f"- **Fix:** {f.get('remediation','')}"]
            if f.get("effort"):
                L.append(f"- **Effort:** {f['effort']}")
            L.append("")
    else:
        L += ["*No defects found by rules or review. This is not a statement "
              "that the material is correct — only that nothing was detected.*", ""]

    r = d.get("readiness", {})
    L += ["## SECTION E: PRODUCTION READINESS", ""]
    score = r.get("score_percent")
    if score is not None:
        light = "🟢" if score >= 90 else ("🟡" if score >= 70 else "🔴")
        L += [f"**Overall readiness: {light} {score}%**", ""]
    for label, key, box in [("Done", "done", "x"), ("Blockers", "blockers", " "),
                            ("To do", "todo", " ")]:
        items = r.get(key) or []
        if items:
            L.append(f"**{label}:**")
            L += [f"- [{box}] {it}" for it in items]
            L.append("")
    # Printed even when empty: an audit that lists nothing as unverified is
    # claiming everything was checked, which is almost never true.
    nv = r.get("not_verified") or []
    L.append("**Not verified:**")
    if nv:
        L += [f"- {it}" for it in nv]
    else:
        L.append("- *Nothing listed. Treat that with suspicion — an audit that "
                 "verified everything is rare.*")
    L.append("")

    exp = d.get("expansion_plan", [])
    if exp:
        L += ["## SECTION F: PHASED PLAN", ""]
        for e in exp:
            L += [f"### Phase {e.get('phase','?')} — `{e.get('target','')}`",
                  f"- **Change:** {e.get('tweak','')}",
                  f"- **Expected impact:** {e.get('impact','')}", ""]

    pos = d.get("positive_observations", [])
    if pos:
        L += ["## POSITIVE OBSERVATIONS", ""] + [f"- {x}" for x in pos] + [""]

    vc = d.get("verification_commands", [])
    if vc:
        L += ["## VERIFICATION COMMANDS", "",
              "Run these to check the claims above rather than trusting them.", "",
              "```bash"] + list(vc) + ["```", ""]

    L.extend(render_claim_sources(d))
    L.append(TRANSPARENCY_FOOTER)
    return "\n".join(L)


# ══════════════════════════════════════════════════════════════════════
#  DITA TOPIC SCHEMAS — RELEASE MODE
# ══════════════════════════════════════════════════════════════════════

RELEASE_DEV_SYSTEM = f"""You write a technical release note precise enough for an engineer to
audit, reproduce, and build on without reading the diff themselves.
Structure your output using DITA information types:
  - concept: what changed and why
  - reference: tables of changed files, subsystems, test coverage
  - task: deployment and rollback steps
  - troubleshoot: known issues with symptom/cause/remedy triples
Neutral, factual tone. Like a postmortem, not a press release.

{_IBM_STYLE}
{_CLAIM_SOURCING}
{_FILL_ALL_FIELDS}
Respond with ONLY valid JSON matching the schema. No markdown fence, no text
before or after the JSON object."""

RELEASE_DEV_SCHEMA_HINT = """{
  "title": "Technical title: what changed, in one line",

  /* DITA CONCEPT — what changed and why */
  "concept": {
    "summary": "One paragraph: root cause, fix approach, scope of change.",
    "known_alternatives": "Approaches that were NOT chosen. Quote commit messages or comments explaining why. If none are documented, write 'Not available in the source material.' Do not infer rationale from the diff structure.",
    "architecture_impact": "What architectural invariants changed, if any."
  },

  /* DITA REFERENCE — lookup tables */
  "reference": {
    "toolchain": "compiler, linker flags, build command with exact flags",
    "resource_deltas": "binary size / RSS / cold start: before -> after, or N/A",
    "code_changes": [{"file": "...", "change": "added|removed|modified",
                      "old_behavior": "...", "new_behavior": "..."}],
    "subsystem_changes": [{"subsystem": "tui|network|storage|auth|other",
                           "details": "..."}],
    "test_coverage": {"added": "...", "removed": "...", "notes": "..."},
    "security_posture": "CVEs, attack surface delta, permission changes — or explicit 'no changes'."
  },

  /* DITA TASK — deployment */
  "deployment_task": {
    "prerequisites": ["..."],
    "steps": [{"step": "fetch|verify|install|verify_active|rollback",
               "command": "exact command or null",
               "expected_output": "..."}],
    "rollback_steps": [{"step": 1, "action": "...", "command": "..."}]
  },

  /* DITA TROUBLESHOOT */
  "troubleshooting": [
    {"symptom": "...", "probable_cause": "...", "remedy": "...",
     "severity": "low|medium|high", "deferred_to": "version or null"}
  ],

  "claim_sources": [{"claim": "...", "basis": "stated_in_input or model_inference",
                     "evidence": "exact phrase or null"}]
}"""

RELEASE_DEV_JSONSCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "concept": {"type": "object", "properties": {
            "summary": {"type": "string"},
            "known_alternatives": {"type": "string"},
            "architecture_impact": {"type": "string"}}},
        "reference": {"type": "object", "properties": {
            "toolchain": {"type": "string"},
            "resource_deltas": {"type": "string"},
            "code_changes": {"type": "array", "items": {"type": "object"}},
            "subsystem_changes": {"type": "array", "items": {"type": "object"}},
            "test_coverage": {"type": "object"},
            "security_posture": {"type": "string"}}},
        "deployment_task": {"type": "object"},
        "troubleshooting": {"type": "array", "items": {"type": "object"}},
        "claim_sources": _CLAIM_SOURCES_FIELD,
    },
    "required": ["title", "concept", "reference", "deployment_task", "claim_sources"],
}

RELEASE_LAYMAN_SYSTEM = f"""You write release notes for an intelligent, non-technical reader who
wants to know what changed and whether it affects them. This is a complete
translation of the technical change — nothing significant is omitted.

Apply IBM plain-language and DITA principles:
- Lead with the user's situation: "If you saw X, this release fixes it."
- Use before/after framing wherever a change is user-perceivable.
- Cover: what was broken, what was fixed, what you will notice, what was
  deliberately left out and why, privacy/data implications, install risk,
  known issues, likely questions, honest bottom line.
- Write "we" for the project team. Own decisions; do not hedge them.

{_IBM_STYLE}
{_CLAIM_SOURCING}
{_FILL_ALL_FIELDS}
Respond with ONLY valid JSON matching the schema. No markdown fence, no text
before or after the JSON object."""

RELEASE_LAYMAN_SCHEMA_HINT = """{
  "title": "One-line plain-English theme for this release",

  /* DITA CONCEPT — what happened */
  "concept": {
    "story": "Why this version exists. What was broken or annoying that prompted it.",
    "before_after": [{"area": "e.g. screen scrolling", "before": "what you saw",
                      "after": "what you see now", "who_it_affects": "everyone|some users"}],
    "deliberately_not_done": [{"item": "...", "why_not": "..."}]
  },

  /* DITA TASK — how to install */
  "install_task": {
    "prerequisites": ["what you need before starting"],
    "steps": [{"step": 1, "instructions": "...", "command": "exact command or null",
               "success_looks_like": "..."}],
    "rollback": "How to go back to the previous version, or 'not supported'."
  },

  /* DITA TROUBLESHOOT — known issues */
  "troubleshooting": [
    {"symptom": "what you see", "plain_cause": "why in plain language",
     "workaround": "what to do now", "status": "fixed in X / deferred / investigating"}
  ],

  "privacy_and_security": "Data/permission/telemetry changes, or explicit statement that none occurred.",
  "faq": [{"question": "phrased like a real user would ask", "answer": "..."}],
  "bottom_line": "4-7 sentences, prose, honest about tradeoffs.",

  "claim_sources": [{"claim": "...", "basis": "stated_in_input or model_inference",
                     "evidence": "exact phrase or null"}]
}"""

RELEASE_LAYMAN_JSONSCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "concept": {"type": "object", "properties": {
            "story": {"type": "string"},
            "before_after": {"type": "array", "items": {"type": "object"}},
            "deliberately_not_done": {"type": "array", "items": {"type": "object"}}}},
        "install_task": {"type": "object"},
        "troubleshooting": {"type": "array", "items": {"type": "object"}},
        "privacy_and_security": {"type": "string"},
        "faq": {"type": "array", "items": {"type": "object"}},
        "bottom_line": {"type": "string"},
        "claim_sources": _CLAIM_SOURCES_FIELD,
    },
    "required": ["title", "concept", "install_task", "privacy_and_security",
                 "bottom_line", "claim_sources"],
}


# ══════════════════════════════════════════════════════════════════════
#  BANNED PHRASES (validation)
# ══════════════════════════════════════════════════════════════════════

# Marketing language — press-release tone (ibm-style?topic=tone)
BANNED_PHRASES = {
    "significant improvements", "various bug fixes", "enhanced user experience",
    "performance optimizations", "we are excited to announce", "cutting-edge",
    "seamlessly integrates", "under the hood", "robust solution", "easy to use",
    "best-in-class", "powerful features", "world-class", "powerful tool",
    "powerful search", "seamlessly", "robust", "powerful",
}

# Weak adverbs and minimiser words (ibm-style?topic=language-grammar-adverbs-only)
# Padded with spaces to avoid matching mid-word (e.g. "rather" in "gather")
BANNED_WEAK_LANGUAGE = {
    " rather ", " quite ", " simply ", " just ", " fairly ",
    " somewhat ", "all you need to", "easy to",
}

# Self-congratulation — agent narrating its own heroics instead of the work
BANNED_SELF_CONGRAT = {
    "triumph", "masterful", "elegant solution", "perfectly", "flawlessly",
    "neutralizing", "i proved", "i immediately", "i discovered", "i solved",
    "relentless", "heroic", "landmark", "groundbreaking", "rogue code",
    "ingenious", "brilliantly", "i demonstrated",
}

# Combined set used by validate_json
ALL_BANNED = BANNED_PHRASES | BANNED_SELF_CONGRAT | BANNED_WEAK_LANGUAGE

TRANSPARENCY_FOOTER = """\n---\n**How to verify this document:**
`📄 stated in input` — the model's phrasing of something your source text said.
Find the matching line in the original to verify.
`🤖 model inference` — the model's own judgment or synthesis. Treat as opinion,
not measurement. Re-run on the same input and check whether specific numbers
stay consistent between runs."""


# ══════════════════════════════════════════════════════════════════════
#  OFFLINE PRE-CHECK ENGINE  (merged from doc_audit.py, 2026-07-30)
# ══════════════════════════════════════════════════════════════════════
#
# MERGE NOTE. This came from `FIrefox.154.Work/doc-audit/doc_audit.py`, which
# was an earlier attempt at the same goal as this script. The two were never
# meant to be separate tools; they are the same idea at two stages, and this is
# the join. Nothing from either side was dropped.
#
# The pre-check exists because of one rule that is worth stating plainly:
# RULE-BASED FINDINGS GO IN THE DOCUMENT BEFORE ANY MODEL OPINION. A defect
# found by a deterministic rule is a fact; a defect a model noticed is a
# judgement. Mixing them without saying which is which is the failure this
# whole toolchain exists to prevent, so pre-check defects are merged into the
# audit's Section D ahead of anything the model contributed.
#
# Every defect is itself DUAL-TRACK — `track_a` explains it to a layperson with
# a physical analogy, `track_b` gives file, line and mechanism. That is the
# philosophy applied to its own diagnostics, and it is the single best idea in
# either script: even the bug reports leave nobody behind.

SOURCE_EXT = ['.cpp', '.cc', '.c', '.h', '.hpp', '.rs', '.js', '.mjs', '.ts',
              '.py', '.css', '.ftl', '.patch', '.sh', '.build', '.go', '.conf']
IGNORE_DIRS = ['.git', 'node_modules', '__pycache__', 'obj-', 'build', 'dist',
               'reference', 'venv', '.venv', 'target']
MAX_FILE_KB = 400

SEVERITIES = ('P0', 'P1', 'P2', 'P3')
SEV_EMOJI = {'P0': '🔴', 'P1': '🟠', 'P2': '🟡', 'P3': '🟢'}


def find_source_files(root: Path) -> list:
    """Collect documentable files under root, or [root] if it is a file."""
    if root.is_file():
        return [root]
    files = []
    for ext in SOURCE_EXT:
        for p in sorted(root.rglob(f"*{ext}")):
            if any(part in IGNORE_DIRS for part in p.parts):
                continue
            try:
                if p.stat().st_size > MAX_FILE_KB * 1024:
                    continue
            except OSError:
                continue
            files.append(p)
    return files


def analyze_file(p: Path, root: Path = None) -> dict:
    """Facts about one file. `sha256` is what makes a claim checkable later.

    `ref` is the name every rule and report must quote. It is the path relative
    to the scan root, NOT the bare filename: real trees keep an original and a
    patched copy of the same file, and a report saying "alc269.c: 2 TODO markers"
    twice is a report the reader cannot act on. Found by running this over the
    kernel patch set, which has exactly that shape.
    """
    content = p.read_text(encoding='utf-8', errors='ignore')
    lines = content.splitlines()
    code = sum(1 for l in lines
               if l.strip() and not l.strip().startswith(('//', '#', ';', '*')))
    complexity = len(re.findall(r'\b(if|for|while|switch|match|catch)\b', content)) + 1
    ref = p.name
    if root:
        try:
            ref = str(p.resolve().relative_to(Path(root).resolve()))
        except ValueError:
            ref = p.name
    return {
        'name': p.name, 'ref': ref, 'path': str(p), 'language': p.suffix.lstrip('.'),
        'lines': len(lines), 'code_lines': code, 'complexity': complexity,
        'sha256': hashlib.sha256(content.encode()).hexdigest()[:16],
        'content': content,
    }


def patch_added_lines(content: str) -> list:
    """The '+' side of a diff only.

    Judging a patch by its whole text reads REMOVED values as if they were
    present — the old number lives on the '-' line. Every rule that inspects a
    .patch must go through here.
    """
    return [l[1:] for l in content.splitlines()
            if l.startswith('+') and not l.startswith('+++')]


def patch_target(content: str) -> str:
    """The path a patch claims to modify, from its +++ header."""
    m = re.search(r'^\+\+\+ [ab]/(.+)$', content, re.MULTILINE)
    return m.group(1).strip() if m else None


class DefectCollector:
    """Accumulates dual-track defects with stable per-severity ids."""

    def __init__(self):
        self.defects = []
        self._n = {s: 0 for s in SEVERITIES}

    def add(self, severity: str, track_a: str, track_b: str, remediation: str,
            effort: str = None):
        """Record one defect.

        track_a  — plain language, ideally a physical analogy, no jargon.
        track_b  — file, symbol, mechanism. Precise enough to act on.
        """
        if severity not in SEVERITIES:
            raise DualTrackError(f"severity must be one of {SEVERITIES}, got {severity!r}")
        self._n[severity] += 1
        d = {'id': f"{severity}-{self._n[severity]:03d}", 'severity': severity,
             'track_a': track_a, 'track_b': track_b, 'remediation': remediation,
             'basis': 'rule'}
        if effort:
            d['effort'] = effort
        self.defects.append(d)


def builtin_precheck_rules(infos: list, collect: DefectCollector):
    """Rules that hold for any project, in any language.

    Deliberately few. A generic rule that fires wrongly trains the reader to
    ignore Section D, which costs more than the rule ever saves. Project-specific
    rules belong in a rules plugin — see load_project_rules.
    """
    for i in infos:
        body = ("\n".join(patch_added_lines(i['content']))
                if i['name'].endswith('.patch') else i['content'])

        todos = [l for l in body.splitlines()
                 if re.search(r'\b(TODO|FIXME|XXX|HACK)\b', l)]
        if todos:
            collect.add(
                'P2',
                "A sticky note saying 'finish this later' was left inside the "
                "machine. It still works, but somebody meant to come back to it.",
                f"{i.get('ref', i['name'])}: {len(todos)} TODO/FIXME/XXX/HACK "
                f"marker(s) in "
                f"{'added lines' if i['name'].endswith('.patch') else 'the file'}.",
                "Resolve it, or convert it into a tracked item so it is visible "
                "outside the source.")

        if i['name'].endswith('.patch'):
            tgt = patch_target(i['content'])
            if tgt and not patch_added_lines(i['content']):
                collect.add(
                    'P1',
                    "A repair instruction that removes things but adds nothing. "
                    "Worth checking it is meant to be a deletion.",
                    f"{i.get('ref', i['name'])}: targets {tgt} with no added lines.",
                    "Confirm this is an intentional pure deletion.")


def load_project_rules(rules_path: Path):
    """Import a project's own rule module and return its `rules` callable.

    The module must define `rules(infos, collect)` and call `collect.add(...)`.
    This is how Firefox's Rust-checksum, dead-patch-target and Necko buffer
    rules survive the merge without dragging Firefox specifics into a tool that
    also documents a kernel patch set and a Python search utility.

    Loaded by path rather than by package import on purpose: these files live
    inside project trees, not on sys.path, and must not need installing.
    """
    rules_path = Path(rules_path)
    if not rules_path.exists():
        raise DualTrackError(f"Rules file not found: {rules_path}")
    spec = importlib.util.spec_from_file_location(
        f"dual_track_rules_{rules_path.stem}", rules_path)
    if spec is None or spec.loader is None:
        raise DualTrackError(f"Could not load rules from {rules_path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    fn = getattr(mod, "rules", None)
    if not callable(fn):
        raise DualTrackError(
            f"{rules_path} must define rules(infos, collect). "
            f"Call collect.add(severity, track_a, track_b, remediation).")
    return fn


def default_rules_path(target: Path) -> Path:
    """Find a project's rules file by walking up from the target.

    Looks for `.dual-track-rules.py`, so a project opts in by adding one file
    and nothing else. Returns None when there isn't one — most projects need
    only the builtin rules.
    """
    target = Path(target).resolve()
    start = target if target.is_dir() else target.parent
    for d in [start, *start.parents]:
        candidate = d / ".dual-track-rules.py"
        if candidate.exists():
            return candidate
        if (d / ".git").exists():
            break
    return None


def run_precheck(infos: list, rules_path: Path = None) -> list:
    """Run builtin rules plus any project rules. Returns defect dicts.

    A broken rules plugin must not take the pre-check down with it: findings
    already collected are real and worth reporting, and a project that has just
    written its first rule file should get a usable error rather than nothing.
    """
    collector = DefectCollector()
    builtin_precheck_rules(infos, collector)
    if rules_path:
        try:
            load_project_rules(rules_path)(infos, collector)
        except DualTrackError:
            raise
        except Exception as e:
            collector.add(
                'P2',
                "The project's own extra safety checks could not run, so this "
                "report may be missing problems specific to this project.",
                f"Project rules {rules_path} raised {type(e).__name__}: {e}",
                "Fix the rules file, then re-run the pre-check.")
    return collector.defects


def render_precheck(topic: str, infos: list, defects: list) -> str:
    """The pre-check as a standalone document — no model involved, so say so."""
    counts = {s: sum(1 for d in defects if d['severity'] == s) for s in SEVERITIES}
    L = [f"# Offline Pre-Check: {topic}", "",
         f"*Generated {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} by rules only. "
         f"No model was involved, so everything below is a deterministic finding "
         f"about the files as they are on disk.*", "",
         "## Files Scanned", "",
         "| File | Language | Lines | Code | Complexity | SHA-256 |",
         "|---|---|---|---|---|---|"]
    for i in infos:
        L.append(f"| `{i.get('ref', i['name'])}` | {i['language']} | {i['lines']} | "
                 f"{i['code_lines']} | {i['complexity']} | `{i['sha256']}` |")
    L += ["", "## Findings", "",
          " · ".join(f"{SEV_EMOJI[s]} {s}: {counts[s]}" for s in SEVERITIES), ""]
    if not defects:
        L += ["*No findings. The rules found nothing wrong; this is not a "
              "statement that the code is correct.*", ""]
    for d in defects:
        L += [f"### {SEV_EMOJI[d['severity']]} {d['id']} — {d['severity']}", "",
              f"- **Plain English:** {d['track_a']}",
              f"- **Technical:** {d['track_b']}",
              f"- **Fix:** {d['remediation']}"]
        if d.get('effort'):
            L.append(f"- **Effort:** {d['effort']}")
        L.append("")
    return "\n".join(L)


# ══════════════════════════════════════════════════════════════════════
#  AUTO-CONTEXT GATHERING
# ══════════════════════════════════════════════════════════════════════

def _shell(cmd: str, cwd: Path = None, default: str = "") -> str:
    try:
        return subprocess.check_output(
            cmd, shell=True, cwd=cwd, text=True,
            stderr=subprocess.DEVNULL, timeout=15
        ).strip()
    except Exception:
        return default


def get_git_context(cwd: Path) -> dict:
    tags_raw = _shell("git tag --sort=-v:refname | head -10", cwd=cwd)
    tags = [t for t in tags_raw.splitlines() if t]
    last_tag = tags[0] if tags else ""
    commits_since = ""
    if last_tag:
        commits_since = _shell(f"git log {last_tag}..HEAD --oneline | head -30", cwd=cwd)
    return {
        "tags": tags,
        "last_tag": last_tag,
        "branch": _shell("git branch --show-current", cwd=cwd),
        "remote_url": _shell("git remote get-url origin", cwd=cwd),
        "commits_since_last_tag": commits_since.splitlines(),
        "total_commits": _shell("git rev-list --count HEAD", cwd=cwd),
    }


def get_project_metadata(cwd: Path) -> dict:
    for fname, bsys, name_re, ver_re in [
        ("pyproject.toml", "python",
         r'^name\s*=\s*"([^"]+)"', r'^version\s*=\s*"([^"]+)"'),
        ("Cargo.toml", "rust",
         r'^name\s*=\s*"([^"]+)"', r'^version\s*=\s*"([^"]+)"'),
    ]:
        p = cwd / fname
        if p.exists():
            text = p.read_text(errors="replace")
            name = re.search(name_re, text, re.MULTILINE)
            ver = re.search(ver_re, text, re.MULTILINE)
            return {"build_system": bsys,
                    "name": name.group(1) if name else None,
                    "version": ver.group(1) if ver else None}
    pkg = cwd / "package.json"
    if pkg.exists():
        try:
            d = json.loads(pkg.read_text())
            return {"build_system": "node", "name": d.get("name"),
                    "version": d.get("version")}
        except Exception:
            pass
    go_mod = cwd / "go.mod"
    if go_mod.exists():
        text = go_mod.read_text(errors="replace")
        m = re.search(r'^module\s+(\S+)', text, re.MULTILINE)
        return {"build_system": "go",
                "name": m.group(1).split("/")[-1] if m else None,
                "version": None}
    return {"build_system": "unknown", "name": None, "version": None}


def get_code_context(source: Path) -> dict:
    # A topic is a DIRECTORY, and this function reads its target as text.
    # Summarise the folder instead of crashing on it.
    if source.is_dir():
        members = find_source_files(source)
        return {
            "line_count": sum(len(m.read_text(errors="replace").splitlines())
                              for m in members),
            "language": "topic (" + ", ".join(
                sorted({m.suffix.lstrip('.') for m in members if m.suffix})) + ")",
            "imports": [],
            "sibling_files": [m.name for m in members[:20]],
            "test_files": [],
        }
    code = source.read_text(errors="replace")
    lines = code.splitlines()
    imports = [l.strip() for l in lines[:150]
               if l.strip().startswith(
                   ("import ", "from ", "require(", "using ", "#include",
                    "include ", "use ", "extern ", "package "))]
    siblings = ([f.name for f in source.parent.iterdir() if f.is_file()][:20]
                if source.parent.exists() else [])
    tests = []
    for pat in [
        source.parent / f"test_{source.name}",
        source.parent / f"{source.stem}_test{source.suffix}",
        source.parent / f"{source.stem}.test{source.suffix}",
    ]:
        if pat.exists():
            tests.append(str(pat.relative_to(source.parent)))
    return {
        "line_count": len(lines),
        "language": source.suffix.lstrip(".") or "unknown",
        "imports": imports[:20],
        "sibling_files": siblings,
        "test_files": tests[:5],
    }


def get_prior_doc_context(cwd: Path, max_docs: int = 3) -> list:
    """Find existing documentation in or near the target directory.

    This is the causality layer: if prior agents wrote STATUS_REPORT.md,
    IMPLEMENTATION_PROGRESS.md, gap analyses, session notes, or contradictory
    status docs, the model MUST know they exist and what they claim — because
    those claims are what the new document needs to either confirm or correct.

    Returns a list of (path, excerpt) tuples for the most recently modified docs,
    capped at max_docs to avoid flooding the context.
    """
    doc_patterns = ["STATUS*.md", "PROGRESS*.md", "REPORT*.md", "CHANGELOG*",
                    "GAP*.md", "AUDIT*.md", "SESSION*.md", "*_status.md",
                    "NOTES*.md", "PLAN*.md", "IMPLEMENTATION*.md", "FINDINGS*.md"]
    candidates = []
    for pattern in doc_patterns:
        for p in cwd.rglob(pattern):
            if any(part.startswith('.') for part in p.parts):
                continue
            try:
                candidates.append((p.stat().st_mtime, p))
            except OSError:
                pass
    candidates.sort(reverse=True)
    result = []
    for _, p in candidates[:max_docs]:
        try:
            content = p.read_text(encoding="utf-8", errors="replace")
            # First 40 lines — enough to see what the doc claims, not the full text
            excerpt = "\n".join(content.splitlines()[:40])
            result.append((p, excerpt))
        except OSError:
            pass
    return result


def build_context_block(source: Path = None, cwd: Path = None,
                        include_prior_docs: bool = True) -> str:
    parts = []
    cwd = cwd or (source.parent if source else Path.cwd())
    git = get_git_context(cwd)
    meta = get_project_metadata(cwd)

    parts += ["=" * 60, "PROJECT CONTEXT (auto-detected)", "=" * 60]
    if meta.get("name"):
        parts.append(f"Project:    {meta['name']}")
    if meta.get("version"):
        parts.append(f"Version:    {meta['version']}")
    if meta.get("build_system") != "unknown":
        parts.append(f"Build:      {meta['build_system']}")
    if git.get("last_tag"):
        parts.append(f"Last tag:   {git['last_tag']}")
    if git.get("branch"):
        parts.append(f"Branch:     {git['branch']}")
    if git.get("remote_url"):
        parts.append(f"Remote:     {git['remote_url']}")
    if git.get("commits_since_last_tag"):
        parts.append(f"Commits since {git['last_tag']}:")
        for c in git["commits_since_last_tag"][:15]:
            parts.append(f"  - {c}")

    if source:
        ctx = get_code_context(source)
        parts += ["", "-" * 40, f"FILE: {source.name}", "-" * 40]
        parts.append(f"Language:   {ctx['language']}")
        parts.append(f"Lines:      {ctx['line_count']}")
        if ctx["imports"]:
            parts.append(f"Imports:    {', '.join(ctx['imports'][:6])}")
        if ctx["sibling_files"]:
            parts.append(f"Siblings:   {', '.join(ctx['sibling_files'][:8])}")
        if ctx["test_files"]:
            parts.append(f"Tests:      {', '.join(ctx['test_files'])}")

    # Prior docs: the causality layer. The model must know what prior agents
    # claimed so it can confirm or correct them, not silently repeat them.
    if include_prior_docs:
        scan_root = source.parent if (source and source.is_file()) else (source or cwd)
        prior = get_prior_doc_context(scan_root)
        if prior:
            parts += ["", "=" * 60,
                      "PRIOR DOCUMENTATION FOUND — read these before writing.",
                      "Your document must confirm, correct, or supersede these claims.",
                      "Do NOT repeat a prior claim without verifying it against the",
                      "source material. If a prior doc contradicts the source, say so.",
                      "=" * 60]
            for p, excerpt in prior:
                parts += ["", f"--- {p.name} (first 40 lines) ---", excerpt,
                          f"[... truncated. Full path: {p}]"]

    parts += ["", "=" * 60, "END CONTEXT — source material follows", "=" * 60]
    return "\n".join(parts)


# ══════════════════════════════════════════════════════════════════════
#  JSON LOADING
# ══════════════════════════════════════════════════════════════════════

def _extract_json(raw: str) -> dict:
    text = raw.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1] if "\n" in text else text[3:]
        if text.endswith("```"):
            text = text.rsplit("```", 1)[0]
    text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        s, e = text.find("{"), text.rfind("}")
        if s != -1 and e != -1 and e > s:
            return json.loads(text[s:e + 1])
        raise


def load_filled_json(path: Path) -> dict:
    if not path.exists():
        raise DualTrackError(
            f"Expected a filled JSON file at {path} but it does not exist. "
            f"Read the matching *.prep.json, produce JSON matching its "
            f"'json_schema', and save it at this exact path first.")
    raw = path.read_text(encoding="utf-8", errors="replace")
    try:
        return _extract_json(raw)
    except json.JSONDecodeError as e:
        raise DualTrackError(
            f"{path} is not valid JSON ({e}). Save only a single JSON object "
            f"matching the schema from the matching *.prep.json — no fence, "
            f"no text before or after it.")


# ══════════════════════════════════════════════════════════════════════
#  CLAIM SOURCES RENDERER (shared)
# ══════════════════════════════════════════════════════════════════════

def render_claim_sources(d: dict) -> list:
    sources = d.get("claim_sources", [])
    if not sources:
        return []
    L = ["## Claim Sources\n",
         "| Claim | Basis | Evidence |",
         "|-------|-------|----------|"]
    for s in sources:
        claim = str(s.get("claim", "")).replace("|", "\\|")
        basis = s.get("basis", "")
        label = "📄 stated in input" if basis == "stated_in_input" else "🤖 model inference"
        ev = s.get("evidence")
        ev_cell = str(ev).replace("|", "\\|") if ev else "*(none — model judgment)*"
        L.append(f"| {claim} | {label} | {ev_cell} |")
    L.append("")
    return L


# ══════════════════════════════════════════════════════════════════════
#  MARKDOWN RENDERERS — CODE MODE
# ══════════════════════════════════════════════════════════════════════

def render_code_dev(d: dict, filename: str) -> str:
    now = datetime.now().strftime("%Y-%m-%d")
    L = [f"# {d.get('title', filename)}",
         f"\n> Generated {now} | Source: `{filename}`\n",
         "---\n"]

    concept = d.get("concept", {})
    if concept.get("purpose"):
        L += ["## Purpose\n", concept["purpose"] + "\n"]
    if concept.get("known_alternatives"):
        L += ["## Known Alternatives Considered\n", concept["known_alternatives"] + "\n"]

    arch = concept.get("architecture", {})
    if arch:
        L.append("## Architecture\n")
        if arch.get("pattern"):
            L.append(f"- **Pattern:** {arch['pattern']}")
        if arch.get("trust_boundary"):
            L.append(f"- **Trust boundary:** {arch['trust_boundary']}")
        if arch.get("attack_surface"):
            L.append(f"- **Attack surface:** {arch['attack_surface']}")
        if arch.get("dependencies"):
            L.append(f"- **Dependencies:** {', '.join(f'`{x}`' for x in arch['dependencies'])}")
        L.append("")

    ref = d.get("reference", {})

    if ref.get("flags"):
        L += ["## Flags & Configuration\n",
              "| Name | Type | Default | Effect | Notes |",
              "|------|------|---------|--------|-------|"]
        for f in ref["flags"]:
            L.append(f"| `{f.get('name','')}` | `{f.get('type','')}` | "
                     f"`{f.get('default','')}` | {f.get('effect','')} | {f.get('notes','')} |")
        L.append("")

    if ref.get("api_surface"):
        L += ["## API Surface\n",
              "| Symbol | Description | Side Effects |",
              "|--------|-------------|--------------|"]
        for a in ref["api_surface"]:
            L.append(f"| `{a.get('symbol','')}` | {a.get('description','')} | "
                     f"{a.get('side_effects','')} |")
        L.append("")

    if ref.get("kill_switches"):
        L.append("## Kill Switches\n")
        for k in ref["kill_switches"]:
            rev = "reversible" if k.get("reversible") else "**not reversible**"
            L.append(f"### `{k.get('location','')}`\n"
                     f"- **Condition:** {k.get('condition','')}\n"
                     f"- **Effect:** {k.get('effect','')}\n"
                     f"- {rev}\n"
                     f"- {k.get('notes','')}\n")

    if ref.get("dead_code"):
        L.append("## Dead Code\n")
        for c in ref["dead_code"]:
            L.append(f"- **`{c.get('location','')}`** — {c.get('reason','')} "
                     f"(risk: {c.get('risk','')})")
        L.append("")

    perf = ref.get("performance", {})
    if any(perf.values()):
        L.append("## Performance\n")
        for k in ("cpu", "memory", "io", "notes"):
            if perf.get(k):
                L.append(f"- **{k.upper()}:** {perf[k]}")
        L.append("")

    sec = ref.get("security", {})
    if any(sec.values()):
        L.append("## Security\n")
        for label, key in [("Remote execution", "remote_execution"),
                            ("Data handling", "data_handling"),
                            ("Attack surface", "attack_surface"),
                            ("Notes", "notes")]:
            if sec.get(key):
                L.append(f"- **{label}:** {sec[key]}")
        L.append("")

    if ref.get("error_conditions"):
        L += ["## Error Conditions\n",
              "| Error | Cause | Remedy |",
              "|-------|-------|--------|"]
        for e in ref["error_conditions"]:
            L.append(f"| `{e.get('code_or_message','')}` | {e.get('cause','')} | "
                     f"{e.get('remedy','')} |")
        L.append("")

    tasks = d.get("tasks", [])
    if tasks:
        L.append("## Tasks\n")
        for t in tasks:
            L.append(f"### {t.get('task_title','Task')}\n")
            if t.get("context"):
                L.append(t["context"] + "\n")
            prereqs = t.get("prerequisites", [])
            if prereqs:
                L.append("**Prerequisites:**")
                for p in prereqs:
                    L.append(f"- {p}")
                L.append("")
            for s in t.get("steps", []):
                L.append(f"**Step {s.get('step','')}:** {s.get('action','')}")
                if s.get("expected_result"):
                    L.append(f"  - Expected: {s['expected_result']}")
            if t.get("post_conditions"):
                L.append(f"\n**After this task:** {t['post_conditions']}")
            L.append("")

    ts = d.get("troubleshooting", [])
    if ts:
        L.append("## Troubleshooting\n")
        for t in ts:
            L.append(f"**Symptom:** {t.get('symptom','')}\n"
                     f"**Cause:** {t.get('probable_cause','')}\n"
                     f"**Remedy:** {t.get('remedy','')}\n"
                     f"**Verify:** {t.get('verification','')}\n")

    debt = d.get("technical_debt", [])
    if debt:
        icons = {"low": "🟡", "medium": "🟠", "high": "🔴"}
        L.append("## Technical Debt\n")
        for t in debt:
            sev = t.get("severity", "low")
            L.append(f"{icons.get(sev,'🟡')} **{sev.upper()}** — "
                     f"{t.get('item','')} → {t.get('recommendation','')}")
        L.append("")

    if d.get("impact_if_removed"):
        L += ["## Impact If Removed\n", d["impact_if_removed"] + "\n"]

    L.extend(render_claim_sources(d))
    L.append(TRANSPARENCY_FOOTER)
    L.append("\n*Auto-generated DITA-structured developer documentation.*")
    return "\n".join(L)


def render_code_layman(d: dict, filename: str) -> str:
    now = datetime.now().strftime("%Y-%m-%d")
    L = [f"# {d.get('title', filename)} — Plain Language Guide",
         f"\n> Generated {now} from `{filename}`\n",
         "---\n"]

    if d.get("should_you_run_this"):
        L += ["## Should You Run This?\n", d["should_you_run_this"] + "\n"]

    concept = d.get("concept", {})
    if concept.get("worst_case"):
        L += ["## Worst Case, Honestly\n", concept["worst_case"] + "\n"]
    if concept.get("data_and_privacy"):
        L += ["## What Data This Touches\n", concept["data_and_privacy"] + "\n"]

    vtask = d.get("verification_task", {})
    vsteps = vtask.get("steps", [])
    if vsteps:
        L += ["## Before You Trust It\n"]
        if vtask.get("context"):
            L.append(vtask["context"] + "\n")
        for s in vsteps:
            L.append(f"**Step {s.get('step','')}:** {s.get('action','')}")
            if s.get("what_to_look_for"):
                L.append(f"  - Look for: {s['what_to_look_for']}")
        L.append("")

    if concept.get("big_picture"):
        L += ["## The Big Picture\n", concept["big_picture"] + "\n"]

    concepts = concept.get("key_concepts", [])
    if concepts:
        L += ["## Key Concepts\n",
              "| Name | What It Means | Real-World Comparison |",
              "|------|--------------|------------------------|"]
        for c in concepts:
            L.append(f"| `{c.get('name','')}` | {c.get('plain_english','')} | "
                     f"{c.get('analogy','')} |")
        L.append("")

    # MERGED from doc_audit.py's render_layman: the walkthrough, the surprising
    # parts, structured impact, the off switch, and the transparency angle.
    # Without these the layman track really was a shorter developer track, which
    # PHILOSOPHY.md explicitly forbids — plain language is a parallel form of
    # rigour, not a reduced one.
    steps = d.get("how_it_works", [])
    if steps:
        L.append("## How It Works — Step by Step\n")
        for s in steps:
            L += [f"### Step {s.get('step','')}: {s.get('title','')}\n",
                  s.get("explanation", "") + "\n"]

    quirks = d.get("quirky_things", [])
    if quirks:
        L.append("## Quirky Things Worth Knowing\n")
        for q in quirks:
            L += [f"### {q.get('title','')}\n", q.get("explanation", "") + "\n"]

    impact = d.get("real_world_impact", {})
    if any(impact.get(k) for k in
           ("battery_cpu_ram", "speed", "your_privacy", "your_internet")):
        L.append("## What This Means For You\n")
        for label, key in [("Battery, Processor & Memory", "battery_cpu_ram"),
                           ("Speed", "speed"),
                           ("Your Privacy", "your_privacy"),
                           ("Your Internet", "your_internet")]:
            if impact.get(key):
                L += [f"### {label}\n", impact[key] + "\n"]

    ks = d.get("kill_switch_explained", {})
    if any(ks.get(k) for k in ("what_it_is", "without_it", "real_life_analogy")):
        L.append("## The Off Switch\n")
        if ks.get("what_it_is"):
            L.append(f"**What it is:** {ks['what_it_is']}\n")
        if ks.get("without_it"):
            L.append(f"**Without it:** {ks['without_it']}\n")
        if ks.get("real_life_analogy"):
            L.append(f"**Think of it like:** {ks['real_life_analogy']}\n")

    utask = d.get("usage_task", {})
    if utask.get("steps"):
        L.append(f"## {utask.get('task_title', 'How to Use This')}\n")
        prereqs = utask.get("prerequisites", [])
        if prereqs:
            L.append("**Before you start:**")
            for p in prereqs:
                L.append(f"- {p}")
            L.append("")
        for s in utask["steps"]:
            L.append(f"**Step {s.get('step','')}:** {s.get('action','')}")
            if s.get("expected_result"):
                L.append(f"  - You should see: {s['expected_result']}")
        L.append("")

    ts = d.get("troubleshooting", [])
    if ts:
        L.append("## If Something Goes Wrong\n")
        for t in ts:
            L.append(f"**{t.get('symptom','')}**\n"
                     f"{t.get('plain_cause','')}\n"
                     f"What to do: {t.get('remedy','')}\n")

    if d.get("why_it_matters"):
        L += ["## Why a Developer Would Do This\n", d["why_it_matters"] + "\n"]

    if d.get("open_source_angle"):
        L += ["## Why It Matters That You Can Read This\n",
              d["open_source_angle"] + "\n"]

    glossary = d.get("glossary", [])
    if glossary:
        L.append("## Glossary\n")
        for g in glossary:
            L.append(f"**{g.get('term','')}** — {g.get('definition','')}\n")

    L.extend(render_claim_sources(d))
    L.append(TRANSPARENCY_FOOTER)
    L.append(
        "\n*Human Track. Its Developer Track twin covers the same changes in "
        "technical detail. Neither is a simplified copy of the other — they are "
        "the same truth in two languages.*")
    return "\n".join(L)


# ══════════════════════════════════════════════════════════════════════
#  MARKDOWN RENDERERS — RELEASE MODE
# ══════════════════════════════════════════════════════════════════════

def render_release_dev(d: dict, meta: dict = None) -> str:
    meta = meta or {}
    L = [f"# {d.get('title', 'Technical Release Notes')}"]
    if meta.get("version"):
        L.append(f"\n**Version:** {meta['version']}")
    if meta.get("date"):
        L.append(f"**Date:** {meta['date']}")
    L.append("\n---\n")

    concept = d.get("concept", {})
    if concept.get("summary"):
        L += ["## Summary\n", concept["summary"] + "\n"]
    if concept.get("known_alternatives"):
        L += ["## Known Alternatives Considered\n", concept["known_alternatives"] + "\n"]
    if concept.get("architecture_impact"):
        L += ["## Architecture Impact\n", concept["architecture_impact"] + "\n"]

    ref = d.get("reference", {})
    if ref.get("toolchain"):
        L += ["## Toolchain\n", f"```\n{ref['toolchain']}\n```\n"]
    if ref.get("resource_deltas"):
        L += ["## Resource Deltas\n", ref["resource_deltas"] + "\n"]

    if ref.get("code_changes"):
        L += ["## Code Changes\n",
              "| File | Change | Old Behavior | New Behavior |",
              "|------|--------|--------------|--------------|"]
        for c in ref["code_changes"]:
            L.append(f"| `{c.get('file','')}` | {c.get('change','')} | "
                     f"{c.get('old_behavior','')} | {c.get('new_behavior','')} |")
        L.append("")

    if ref.get("subsystem_changes"):
        L.append("## Subsystem Changes\n")
        for s in ref["subsystem_changes"]:
            L.append(f"**{s.get('subsystem','').upper()}:** {s.get('details','')}\n")

    tc = ref.get("test_coverage", {})
    if any(tc.values()):
        L.append("## Test Coverage\n")
        for k in ("added", "removed", "notes"):
            if tc.get(k):
                L.append(f"- **{k.title()}:** {tc[k]}")
        L.append("")

    if ref.get("security_posture"):
        L += ["## Security Posture\n", ref["security_posture"] + "\n"]

    deploy = d.get("deployment_task", {})
    if deploy.get("steps"):
        L.append("## Deployment\n")
        prereqs = deploy.get("prerequisites", [])
        if prereqs:
            L.append("**Prerequisites:**")
            for p in prereqs:
                L.append(f"- {p}")
            L.append("")
        L.append("```bash")
        for s in deploy["steps"]:
            L.append(f"# {s.get('step','')}")
            if s.get("command"):
                L.append(s["command"])
            if s.get("expected_output"):
                L.append(f"# Expected: {s['expected_output']}")
        L.append("```\n")
        rollback = deploy.get("rollback_steps", [])
        if rollback:
            L.append("**Rollback:**")
            for s in rollback:
                L.append(f"  {s.get('step','')}. {s.get('action','')}",)
                if s.get("command"):
                    L.append(f"     `{s['command']}`")
            L.append("")

    ts = d.get("troubleshooting", [])
    if ts:
        L.append("## Known Issues\n")
        for t in ts:
            sev = t.get("severity", "?")
            defer = f" (deferred to {t['deferred_to']})" if t.get("deferred_to") else ""
            L.append(f"**[{sev}]** {t.get('symptom','')}{defer}\n"
                     f"- Cause: {t.get('probable_cause','')}\n"
                     f"- Remedy: {t.get('remedy','')}\n")

    L.extend(render_claim_sources(d))
    L.append(TRANSPARENCY_FOOTER)
    L.append("\n*Auto-generated DITA-structured technical release notes.*")
    return "\n".join(L)


def render_release_layman(d: dict, meta: dict = None) -> str:
    meta = meta or {}
    proj = meta.get("project", "Release")
    ver = meta.get("version", "")
    L = [f"# {proj} {ver} — {d.get('title', 'What Changed')}",
         f"\n**Date:** {meta.get('date', datetime.now().strftime('%Y-%m-%d'))}"]
    if meta.get("previous"):
        L.append(f"**Previous version:** {meta['previous']}")
    L.append("\n---\n")

    concept = d.get("concept", {})
    if concept.get("story"):
        L += ["## Why This Release Exists\n", concept["story"] + "\n"]

    if concept.get("before_after"):
        L.append("## What You Will Notice\n")
        for b in concept["before_after"]:
            L.append(f"**{b.get('area','')}**")
            L.append(f"- Before: {b.get('before','')}")
            L.append(f"- After:  {b.get('after','')}")
            if b.get("who_it_affects"):
                L.append(f"- Affects: {b['who_it_affects']}")
            L.append("")

    if concept.get("deliberately_not_done"):
        L.append("## Deliberately Not Done\n")
        for x in concept["deliberately_not_done"]:
            L.append(f"- **{x.get('item','')}** — {x.get('why_not','')}")
        L.append("")

    if d.get("privacy_and_security"):
        L += ["## Privacy & Security\n", d["privacy_and_security"] + "\n"]

    install = d.get("install_task", {})
    if install.get("steps"):
        L.append("## How to Install\n")
        prereqs = install.get("prerequisites", [])
        if prereqs:
            L.append("**Before you start:**")
            for p in prereqs:
                L.append(f"- {p}")
            L.append("")
        for s in install["steps"]:
            L.append(f"**Step {s.get('step','')}:** {s.get('instructions','')}")
            if s.get("command"):
                L.append(f"```\n{s['command']}\n```")
            if s.get("success_looks_like"):
                L.append(f"✓ {s['success_looks_like']}")
            L.append("")
        if install.get("rollback"):
            L += ["**To go back:** " + install["rollback"] + "\n"]

    ts = d.get("troubleshooting", [])
    if ts:
        L.append("## If Something Goes Wrong\n")
        for t in ts:
            L.append(f"**{t.get('symptom','')}**\n"
                     f"{t.get('plain_cause','')}\n"
                     f"What to do: {t.get('workaround','')}\n"
                     f"Status: {t.get('status','')}\n")

    faq = d.get("faq", [])
    if faq:
        L.append("## Common Questions\n")
        for qa in faq:
            L.append(f"**Q: {qa.get('question','')}**\nA: {qa.get('answer','')}\n")

    if d.get("bottom_line"):
        L += ["## Bottom Line\n", d["bottom_line"] + "\n"]

    L.extend(render_claim_sources(d))
    L.append(TRANSPARENCY_FOOTER)
    L.append("\n*Auto-generated plain-language release notes.*")
    return "\n".join(L)


# ══════════════════════════════════════════════════════════════════════
#  VALIDATION
# ══════════════════════════════════════════════════════════════════════

def validate_json(data: dict, required_nonempty: list) -> dict:
    checks = {}
    for key in required_nonempty:
        val = data.get(key)
        if isinstance(val, (list, dict)):
            present = len(val) > 0
        else:
            present = bool(val)
        checks[f"has_{key}"] = (present, f"'{key}' is empty or missing")

    all_text = " " + json.dumps(data).lower() + " "
    found_marketing = [p for p in BANNED_PHRASES if p in all_text]
    found_weak = [p.strip() for p in BANNED_WEAK_LANGUAGE if p in all_text]
    found_congrat = [p for p in BANNED_SELF_CONGRAT if p in all_text]
    checks["avoids_banned_phrases"] = (
        len(found_marketing) == 0 and len(found_weak) == 0,
        "banned language found: " + ", ".join(found_marketing + found_weak)
        if (found_marketing or found_weak) else ""
    )
    checks["avoids_self_congratulation"] = (
        len(found_congrat) == 0,
        "self-congratulatory language found: " + ", ".join(found_congrat) if found_congrat else ""
    )
    digit_count = sum(c.isdigit() for c in all_text)
    checks["has_concrete_numbers"] = (
        digit_count > 8,
        f"only {digit_count} digits — check for vague, unquantified claims"
    )
    return checks


def _invocation() -> str:
    """How this script was actually invoked, for the 'now run this' hints.

    It is installed on PATH as `dual-track` (a symlink) as well as being run as
    `python3 dual_track.py` from its own directory. Hardcoding either one prints
    a command the reader cannot copy, which for a tool whose whole job is a
    two-stage handoff is worse than unhelpful — the next stage is often run by a
    different agent, or by the same one in a later session with no memory of how
    the first stage was started.
    """
    invoked = Path(sys.argv[0]).name
    if invoked.endswith(".py"):
        return f"python3 {invoked}"
    return invoked


# ── Quality score (merged from doc-audit/MASTER_TEMPLATE.md, 2026-07-30) ──
#
# doc_audit.py's checklist was "score ≥ 85/100 before accepting", weighted across
# six categories. That was a HUMAN scoring exercise, which meant in practice it
# was skipped or self-awarded. Here the measurable parts are computed from the
# rendered document, so the number cannot be flattered.
#
# What is deliberately NOT scored: whether the prose is any good. No arithmetic
# can judge that. The score gates structure and evidence — the things that are
# countable — and the banned-phrase and claim-sourcing checks cover honesty.
# A high score means "nothing obvious is missing", never "this is well written".

QUALITY_WEIGHTS = {
    "structure": 20,      # required topics present
    "evidence": 25,       # claim sources, concrete numbers
    "organisation": 20,   # tables, headings, code blocks
    "separation": 15,     # tracks not collapsed into one another
    "task_orientation": 10,  # numbered steps, verification commands
    "modularity": 10,     # glossary, cross-references
}


def score_document(md: str, data: dict, required: list, track: str = "") -> tuple:
    """Score a rendered document out of 100. Returns (total, {category: (got, max)}).

    Every component is derived from the document or its data, never asserted.

    TRACK-AWARE, and it has to be. The first version applied one set of weights
    to all three document types and an audit scored 4/10 on "task orientation"
    and 4/10 on "modularity" — because audits contain no how-to steps and no
    glossary, and never should. It passed only because the other categories were
    full marks. A gate that penalises a document for correctly being what it is
    trains you to ignore the gate, which is the same failure as a rule that
    flags everything. Each track is scored against what IT should contain:
      layman     — steps, glossary, analogies
      developer  — steps, tables, commands
      audit      — verification commands, defect basis, an honest not-verified list
    """
    got = {}
    is_audit = track == "audit"

    present = sum(1 for k in required if data.get(k))
    got["structure"] = (round(QUALITY_WEIGHTS["structure"] * present / len(required))
                        if required else QUALITY_WEIGHTS["structure"])

    # Evidence: sourced claims, and claims actually backed by quoted evidence.
    claims = data.get("claim_sources") or []
    sourced = [c for c in claims if c.get("basis") == "stated_in_input" and c.get("evidence")]
    digits = sum(c.isdigit() for c in md)
    ev = 0
    if claims:
        ev += 10
        ev += min(8, round(8 * len(sourced) / len(claims)))
    if digits > 8:
        ev += 7
    got["evidence"] = (min(ev, QUALITY_WEIGHTS["evidence"]), QUALITY_WEIGHTS["evidence"])
    got["structure"] = (got["structure"], QUALITY_WEIGHTS["structure"])

    org = 0
    if "|---" in md or "|--" in md:
        org += 8                       # at least one table
    headings = len(re.findall(r'^##+ ', md, re.M))
    org += min(8, headings)
    if "```" in md:
        org += 4                       # at least one code block
    got["organisation"] = (min(org, QUALITY_WEIGHTS["organisation"]),
                           QUALITY_WEIGHTS["organisation"])

    # Separation: checks both directions.
    # (a) A layman document that leaks code identifiers has collapsed into the
    #     developer track — penalise for jargon.
    # (b) A layman document whose concept text shares too many words with the
    #     developer purpose text has collapsed at the idea level — penalise for
    #     semantic overlap, not just surface syntax.
    sep = QUALITY_WEIGHTS["separation"]
    jargon_hits = len(re.findall(r'\b\w+\(\)|::|\bstruct\b|\bmalloc\b|\btypedef\b|\bvoid\b', md))
    is_layman = bool(data.get("should_you_run_this") or data.get("bottom_line")
                     or data.get("open_source_angle"))
    if is_layman:
        if jargon_hits > 12:
            sep -= 6
        # Semantic overlap check: compare layman big_picture against itself for
        # developer-only vocabulary density (a proxy for the track having collapsed).
        big_pic = (data.get("concept") or {}).get("big_picture", "")
        dev_terms = len(re.findall(
            r'\b(function|method|class|object|instance|parameter|argument|'
            r'return value|null|boolean|integer|string|array|dict|hash|'
            r'import|module|library|api|endpoint|callback|async|thread|'
            r'compile|runtime|exception|stack trace)\b',
            big_pic, re.I))
        if dev_terms > 6:
            sep -= 6
    got["separation"] = (max(0, sep), QUALITY_WEIGHTS["separation"])

    task = 0
    if is_audit:
        # An audit is task-oriented when it tells you how to CHECK it, not how to
        # use the thing. Verification commands are the whole point of Section G.
        if data.get("verification_commands"):
            task += 6
        if "```bash" in md or "```sh" in md:
            task += 4
    else:
        if re.search(r'\*\*Step \d|^\s*\d+\.\s', md, re.M):
            task += 6
        if "```bash" in md or "```sh" in md or "```" in md:
            task += 4
    got["task_orientation"] = (min(task, QUALITY_WEIGHTS["task_orientation"]),
                               QUALITY_WEIGHTS["task_orientation"])

    mod = 0
    if is_audit:
        # For an audit, "modular and cross-referenced" means every defect is
        # traceable and the limits of the audit are stated. An audit claiming to
        # have verified everything scores zero here — that is the intent.
        if (data.get("readiness") or {}).get("not_verified"):
            mod += 6
        if "Claim Sources" in md:
            mod += 4
    else:
        if data.get("glossary"):
            mod += 6
        if "Claim Sources" in md:
            mod += 4
    got["modularity"] = (min(mod, QUALITY_WEIGHTS["modularity"]),
                         QUALITY_WEIGHTS["modularity"])

    total = sum(v[0] for v in got.values())
    return total, got


def print_quality_score(track: str, total: int, breakdown: dict, threshold: int) -> bool:
    verdict = "PASS" if total >= threshold else "BELOW THRESHOLD"
    print(f"\nQUALITY SCORE — {track}: {total}/100 (need {threshold}) — {verdict}",
          file=sys.stderr)
    for cat, (g, m) in breakdown.items():
        bar = "#" * g + "." * (m - g)
        print(f"  {cat:<17} {g:>3}/{m:<3} {bar}", file=sys.stderr)
    if total < threshold:
        print("  A low score means something countable is missing — usually claim "
              "sources, numbers, or steps. It is not a judgement of the writing.",
              file=sys.stderr)
    return total >= threshold


def _exit_on_failed_validation(failed_tracks: list):
    """Exit non-zero if --validate found problems.

    Called AFTER the markdown has been written, deliberately. The documents are
    still useful to look at while deciding what to fix, and a validation failure
    is "do not publish this", not "this could not be produced".

    Until 2026-07-30 both render paths called print_validation and threw its
    return value away, so --validate printed ✗ marks and still exited 0. The
    project checklist treats --validate as a gate that must never be skipped;
    running it and not running it were in fact identical, which is the worst
    possible state for a check to be in — it bought confidence it never earned.
    """
    if not failed_tracks:
        return
    print(f"\nVALIDATION FAILED for: {', '.join(failed_tracks)}.\n"
          f"The markdown was still written so you can read it, but do not publish "
          f"it until the checks above pass.", file=sys.stderr)
    sys.exit(2)


def print_validation(checks: dict) -> bool:
    print("\nQUALITY VALIDATION", file=sys.stderr)
    print("-" * 40, file=sys.stderr)
    all_pass = True
    for name, (passed, detail) in checks.items():
        icon = "✓" if passed else "✗"
        print(f"  {icon}  {name.replace('_', ' ')}", file=sys.stderr)
        # A failure counts whether or not it has a detail string to explain
        # itself. This used to read `if not passed and detail:`, so a check that
        # failed with an empty detail printed ✗ and still reported "All checks
        # passed" — the validator lying is worse than no validator.
        if not passed:
            all_pass = False
            if detail:
                print(f"       → {detail}", file=sys.stderr)
    print("-" * 40, file=sys.stderr)
    print("All checks passed." if all_pass else
          "Some checks failed — review before publishing.", file=sys.stderr)
    return all_pass


# ══════════════════════════════════════════════════════════════════════
#  PREP FILE FORMAT
# ══════════════════════════════════════════════════════════════════════

def _prep_envelope(system_prompt: str, user_prompt: str, schema_hint: str,
                   jsonschema: dict, write_to: Path, then_run: str) -> dict:
    return {
        "instructions": (
            "Produce ONE JSON object matching 'json_schema'. "
            "Save ONLY that JSON — no markdown fence, no text before or after — "
            "to the exact path in 'write_completion_to'. "
            "'schema_with_hints' explains each field in plain language. "
            "'system_prompt' sets voice and rules; 'user_prompt' has the input material. "
            "PUBLICATION RULE — this is not optional: the DELIVERABLES are the "
            "rendered .md files only. Never commit or upload this file, any "
            ".prep.json, .filled.json, PAYLOAD.* or PRECHECK.json — they are "
            "local working files (a .gitignore in the output directory enforces "
            "this; do not remove or bypass it). After the rendered .md files "
            "are committed AND pushed, run the 'cleanup' command shown in "
            "'after_publish' to retire the working files."
        ),
        "system_prompt": system_prompt,
        "user_prompt": user_prompt,
        "json_schema": jsonschema,
        "schema_with_hints": schema_hint,
        "write_completion_to": str(write_to),
        "then_run": then_run,
        "after_publish": (f"{_invocation()} cleanup {write_to.parent} "
                          "# ONLY after the rendered .md files are committed and pushed"),
    }


def _write_prep_file(path: Path, envelope: dict):
    path.write_text(json.dumps(envelope, indent=2), encoding="utf-8")


# Working files the pipeline creates on the way to the rendered .md
# deliverables. Never published; targeted by the cleanup command.
INTERMEDIATE_GLOBS = ["*.prep.json", "*.filled.json", "PAYLOAD.*", "PRECHECK.json"]

GITIGNORE_HEADER = "# dual_track.py working files — local only, never published\n"


def write_output_gitignore(out_dir: Path):
    """Drop a .gitignore covering the intermediates into the output dir.

    Merges with an existing .gitignore instead of overwriting it: only the
    missing patterns are appended. This makes 'git add -A' safe — the
    deliverable .md files are committable, the working files are not.
    """
    gi = out_dir / ".gitignore"
    existing = gi.read_text(encoding="utf-8") if gi.exists() else ""
    have = {line.strip() for line in existing.splitlines()}
    missing = [p for p in INTERMEDIATE_GLOBS if p not in have]
    if not missing:
        return
    block = ("" if not existing else ("" if existing.endswith("\n") else "\n"))
    if GITIGNORE_HEADER.strip() not in have:
        block += GITIGNORE_HEADER
    block += "\n".join(missing) + "\n"
    gi.write_text(existing + block, encoding="utf-8")


# ══════════════════════════════════════════════════════════════════════
#  TRACK REGISTRIES
# ══════════════════════════════════════════════════════════════════════

def _render_audit_for_code(d: dict, filename: str) -> str:
    """Adapter so the audit track fits the (data, name) renderer signature.

    Pre-check defects are picked up from a sibling PRECHECK.json when one exists,
    which is what makes `precheck` and `render` compose without the operator
    having to thread the findings through by hand. Carried over from
    doc_audit.py's render mode, which did the same lookup.
    """
    return render_audit(d, filename, precheck=_load_sidecar_precheck(filename))


_CODE_TRACKS = {
    "layman": (CODE_LAYMAN_SYSTEM, CODE_LAYMAN_SCHEMA_HINT,
               CODE_LAYMAN_JSONSCHEMA, render_code_layman),
    "developer": (CODE_DEV_SYSTEM, CODE_DEV_SCHEMA_HINT,
                  CODE_DEV_JSONSCHEMA, render_code_dev),
    "audit": (AUDIT_SYSTEM, AUDIT_SCHEMA_HINT,
              AUDIT_JSONSCHEMA, _render_audit_for_code),
}

_CODE_VALIDATION = {
    "layman": ["concept", "how_it_works", "real_world_impact",
               "open_source_angle", "verification_task", "should_you_run_this"],
    "developer": ["concept", "reference", "tasks", "impact_if_removed"],
    "audit": ["executive_summary_layman", "technical_summary_developer",
              "readiness"],
}

_RELEASE_TRACKS = {
    "layman": (RELEASE_LAYMAN_SYSTEM, RELEASE_LAYMAN_SCHEMA_HINT,
               RELEASE_LAYMAN_JSONSCHEMA, render_release_layman),
    "developer": (RELEASE_DEV_SYSTEM, RELEASE_DEV_SCHEMA_HINT,
                  RELEASE_DEV_JSONSCHEMA, render_release_dev),
}

_RELEASE_VALIDATION = {
    "layman": ["concept", "install_task", "bottom_line"],
    "developer": ["concept", "reference", "deployment_task"],
}


# Where run_code_prep/render stash the pre-check so the audit renderer can find
# it without the caller passing it along. Set by the code-mode runners.
_PRECHECK_SIDECAR_DIR = None


def _load_sidecar_precheck(_name: str) -> list:
    """Read PRECHECK.json from the current output dir, if the pre-check ran.

    Returns [] rather than raising when it is absent or unreadable: an audit
    without the rule findings is incomplete, but an audit that refuses to render
    is useless, and the missing findings are visible in Section D's counts.
    """
    if not _PRECHECK_SIDECAR_DIR:
        return []
    p = Path(_PRECHECK_SIDECAR_DIR) / "PRECHECK.json"
    if not p.exists():
        return []
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except (json.JSONDecodeError, OSError):
        return []


def _track_list(fmt: str) -> list:
    """Tracks to produce. "both" means layman + developer, NOT the audit.

    The audit is opt-in via --format audit or --format all, because it answers a
    release question rather than a documentation one and is not always wanted.
    """
    if fmt == "both":
        return ["layman", "developer"]
    if fmt == "all":
        return ["layman", "developer", "audit"]
    return [fmt]


# ══════════════════════════════════════════════════════════════════════
#  PAYLOAD MODE  (merged from doc_audit.py, 2026-07-30)
# ══════════════════════════════════════════════════════════════════════
#
# The zero-quota path, and the reason it is not optional: a whole working day on
# this machine can amount to two prompts. When there is no quota and no API key,
# `payload` writes a single self-contained .txt you can paste into any free chat
# window. Save the JSON reply, run `render`, and you have the same document the
# expensive path produces.
#
# prep/render already do this without a network call — payload is the variant for
# when the operator is a human with a browser rather than an agent with a tool
# loop. It is the same two-stage handoff either way.

def write_payloads(out_dir: Path, slug: str, tracks: list, envelopes: dict) -> list:
    """Write paste-ready prompt files, one per track.

    Each is standalone on purpose: system prompt, schema and source in one file,
    so nothing has to be assembled by hand in a browser tab at the point where
    the operator has already run out of everything else.
    """
    written = []
    for track in tracks:
        env = envelopes[track]
        text = (
            f"{env['system_prompt']}\n\n"
            f"{'=' * 68}\n{env['user_prompt']}\n{'=' * 68}\n\n"
            f"Reply with ONLY the JSON object. Save it to:\n"
            f"  {env['write_completion_to']}\n"
        )
        p = out_dir / f"PAYLOAD.{slug}.{track}.txt"
        p.write_text(text, encoding="utf-8")
        written.append(p)
    return written


# ── Optional model calls, preserved from doc_audit.py ──────────────────
#
# dual-track's DEFAULT remains "never makes a network call": prep writes a spec,
# something else fills it, render reads it back. These functions exist because
# doc_audit.py could finish the job unattended and dropping that would lose a
# real capability. They are reached only via `--call-model`.

def _post_json(url: str, headers: dict, data: dict, timeout: int = 600) -> dict:
    import urllib.request
    req = urllib.request.Request(url, data=json.dumps(data).encode(),
                                 headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return json.loads(res.read().decode())


def call_anthropic(prompt: str, model: str = "claude-sonnet-5") -> str:
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        raise DualTrackError("ANTHROPIC_API_KEY not set")
    r = _post_json("https://api.anthropic.com/v1/messages",
                   {"x-api-key": key, "anthropic-version": "2023-06-01",
                    "content-type": "application/json"},
                   {"model": model, "max_tokens": 8192,
                    "messages": [{"role": "user", "content": prompt}]})
    return r["content"][0]["text"]


def call_gemini(prompt: str, model: str = "gemini-2.5-flash") -> str:
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        raise DualTrackError("GEMINI_API_KEY not set")
    url = (f"https://generativelanguage.googleapis.com/v1beta/models/"
           f"{model}:generateContent?key={key}")
    r = _post_json(url, {"content-type": "application/json"},
                   {"contents": [{"parts": [{"text": prompt}]}],
                    "generationConfig": {"responseMimeType": "application/json"}})
    return r["candidates"][0]["content"]["parts"][0]["text"]


def call_ollama(prompt: str, model: str = "gemma4:latest") -> str:
    # LOCAL LLMs REMOVED 2026-08-09. This machine (i7-3632QM, no AVX2) cannot run
    # a useful generative model without maxing CPU/fan. The prep/render workflow
    # needs no model at all — a coding agent fills the spec. --allow-local now
    # fails loud instead of blasting the fans with a weak model.
    raise DualTrackError(
        "Local LLM generation is disabled on this machine (removed 2026-08-09). "
        "Use the default prep/render workflow (no network — an agent fills the "
        "spec), or set ANTHROPIC_API_KEY / GEMINI_API_KEY for --call-model.")


def query_model(prompt: str, choice: str, ollama_model: str,
                allow_local: bool = False) -> str:
    """Ask a model to fill a spec. MODEL-FIRST, exactly as doc_audit.py had it.

    The local Ollama model is an EMERGENCY fallback for a human with no quota
    left, never a normal channel. When an agent is driving this script the local
    model must not be reached: a capable model that started the job should finish
    it, not silently hand the work to a weak local one and produce a document
    that looks the same but is not. That distinction is invisible in the output,
    which is exactly why it is enforced here rather than left to judgement.
    """
    if choice.startswith("claude"):
        return call_anthropic(prompt, choice)
    if choice.startswith("gemini"):
        return call_gemini(prompt, choice)
    if choice == "auto":
        if os.environ.get("ANTHROPIC_API_KEY"):
            return call_anthropic(prompt)
        if os.environ.get("GEMINI_API_KEY"):
            return call_gemini(prompt)
        if allow_local:
            return call_ollama(prompt, ollama_model)
        raise DualTrackError(
            "No ANTHROPIC_API_KEY or GEMINI_API_KEY, and --allow-local was not "
            "given. Either set a key, pass --allow-local to fall back to Ollama, "
            "or drop --call-model and use the prep/render workflow (which needs "
            "no network at all).")
    # An explicit model name that is neither claude nor gemini is an Ollama tag.
    if not allow_local:
        raise DualTrackError(
            f"{choice!r} looks like a local Ollama model. Pass --allow-local to "
            f"confirm you intend to use it.")
    return call_ollama(prompt, choice)


def strip_fences(raw: str) -> str:
    raw = raw.strip()
    if raw.startswith("```"):
        raw = raw.split("\n", 1)[1] if "\n" in raw else raw[3:]
    if raw.endswith("```"):
        raw = raw.rsplit("```", 1)[0]
    return raw.strip()


# ══════════════════════════════════════════════════════════════════════
#  MODE RUNNER — PRECHECK
# ══════════════════════════════════════════════════════════════════════

def run_precheck_mode(args):
    """Standalone rule scan. Writes PRECHECK.md and PRECHECK.json.

    Useful on its own — it is the only output in this whole tool that involves no
    model at all, so it is the one thing you can run and fully trust without
    reading a claim-sources table. Exits 1 if any P0 or P1 was found, so it can
    gate a build.
    """
    target = Path(args.target)
    if not target.exists():
        raise DualTrackError(f"target not found: {target}")
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    write_output_gitignore(out_dir)

    root = target if target.is_dir() else target.parent
    files = find_source_files(target)
    if not files:
        raise DualTrackError(f"no documentable source files under {target}")
    infos = [analyze_file(f, root) for f in files]

    rules_path = Path(args.rules) if args.rules else default_rules_path(target)
    defects = run_precheck(infos, rules_path)

    slug = re.sub(r'[^a-z0-9]+', '-', target.name.lower()).strip('-') or "precheck"
    md_path = out_dir / "PRECHECK.md"
    md_path.write_text(render_precheck(slug, infos, defects), encoding="utf-8")
    (out_dir / "PRECHECK.json").write_text(
        json.dumps(defects, indent=2), encoding="utf-8")

    counts = {s: sum(1 for d in defects if d['severity'] == s) for s in SEVERITIES}
    print(f"Scanned {len(infos)} file(s)"
          f"{f' with {rules_path.name}' if rules_path else ' (builtin rules only)'}.",
          file=sys.stderr)
    print("  " + " · ".join(f"{s}: {counts[s]}" for s in SEVERITIES), file=sys.stderr)
    print(f"  {md_path}", file=sys.stderr)

    blocking = counts['P0'] + counts['P1']
    if blocking:
        print(f"\n{blocking} blocking finding(s) (P0/P1). See {md_path}.",
              file=sys.stderr)
        sys.exit(1)


# ══════════════════════════════════════════════════════════════════════
#  MODE RUNNERS — CODE
# ══════════════════════════════════════════════════════════════════════

def build_topic_source(target: Path) -> tuple:
    """Assemble a whole directory into one source block. Returns (text, infos, slug).

    WHY DIRECTORIES ARE FIRST-CLASS. doc_audit.py documented a *topic* — a folder
    of related patches — as one unit, and its instructions were explicit: "one
    pair + one audit per TOPIC, never per file". This script originally accepted
    a single file only, so migrating Firefox to it would have silently changed
    twenty patches documented together into twenty unrelated documents. That is
    a capability loss disguised as a path error, and it is exactly what "merge so
    nothing is lost" has to prevent.

    Files are separated by headers carrying the same facts the pre-check reports,
    so a claim about "the third patch" stays checkable.
    """
    infos = [analyze_file(f, target) for f in find_source_files(target)]
    if not infos:
        raise DualTrackError(f"no documentable source files under {target}")
    parts = [f"TOPIC: {target.name} — {len(infos)} file(s)", ""]
    for i in infos:
        parts += [
            "=" * 68,
            f"FILE: {i['ref']}  ({i['language']}, {i['lines']} lines, "
            f"sha256:{i['sha256']})",
            "=" * 68,
            i['content'], ""]
    slug = re.sub(r'[^a-z0-9]+', '-', target.name.lower()).strip('-') or "topic"
    return "\n".join(parts), infos, slug


def run_code_prep(args):
    source = Path(args.source_file)
    if not source.exists():
        print(f"Error: not found: {args.source_file}", file=sys.stderr)
        sys.exit(1)
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    write_output_gitignore(out_dir)

    if source.is_dir():
        code, topic_infos, stem = build_topic_source(source)
        print(f"Topic mode: {len(topic_infos)} file(s) documented as one unit.",
              file=sys.stderr)
    else:
        code = source.read_text(encoding="utf-8", errors="replace")
        topic_infos = None
        stem = source.stem

    context_block = ""
    if not args.no_auto_context:
        context_block = build_context_block(source=source) + "\n\n"

    # Pre-check BEFORE the prompts are written, so its findings can be handed to
    # the model as established fact. This is doc_audit.py's rule preserved: rules
    # first, opinion second. The model is told not to re-report them.
    precheck_block = ""
    tracks = _track_list(args.format)
    if not args.no_precheck:
        rules_path = Path(args.rules) if args.rules else default_rules_path(source)
        infos = (topic_infos if topic_infos is not None
                 else [analyze_file(source, source.parent)])
        defects = run_precheck(infos, rules_path)
        (out_dir / "PRECHECK.json").write_text(
            json.dumps(defects, indent=2), encoding="utf-8")
        (out_dir / "PRECHECK.md").write_text(
            render_precheck(stem, infos, defects), encoding="utf-8")
        print(f"Pre-check: {len(defects)} finding(s)"
              f"{f' (rules: {rules_path.name})' if rules_path else ' (builtin rules only)'}"
              f" -> {out_dir / 'PRECHECK.md'}", file=sys.stderr)
        if defects:
            precheck_block = (
                "ALREADY-KNOWN DEFECTS — found by deterministic rules, not by you.\n"
                "They are already in the report. Do NOT list them again in your\n"
                "'defects' array. You may refer to them when judging readiness.\n"
                + json.dumps(defects, indent=2) + "\n\n")

    # Grounding numbers. The rule is absolute and predates this merge: if a
    # measurement was not supplied, the document says "not measured". It never
    # estimates one silently.
    grounding = ""
    if getattr(args, "context", None):
        ctx = Path(args.context)
        if not ctx.exists():
            raise DualTrackError(f"--context file not found: {ctx}")
        grounding = (
            "VERIFIED MEASUREMENTS — these are real, use them and cite them as\n"
            "stated_in_input. Any number NOT in this block does not exist: write\n"
            "\"not measured\" rather than estimating.\n"
            + ctx.read_text(encoding="utf-8") + "\n\n")

    written = []
    envelopes = {}
    next_cmd = (f"{_invocation()} code render {args.source_file} "
                f"--output-dir {args.output_dir} --validate")

    for track in tracks:
        system, schema_hint, jsonschema, _ = _CODE_TRACKS[track]
        prep_path = out_dir / f"{stem}_{track}.prep.json"
        filled_path = out_dir / f"{stem}_{track}.filled.json"
        user_prompt = (
            f"{context_block}{grounding}"
            f"{precheck_block if track == 'audit' else ''}"
            f"Analyze this {'topic (multiple related files)' if topic_infos else 'source code'} "
            f"and return JSON matching the schema.\n"
            f"SCHEMA HINTS:\n{schema_hint}\n\n"
            f"SOURCE ({source.name}, {len(code.splitlines())} lines):\n{code}"
        )
        envelope = _prep_envelope(system, user_prompt, schema_hint, jsonschema,
                                  filled_path, next_cmd)
        envelopes[track] = envelope
        _write_prep_file(prep_path, envelope)
        written.append((track, prep_path, filled_path))

    # Zero-quota path: paste-ready prompts for a human with only a browser.
    if getattr(args, "payload", False):
        paths = write_payloads(out_dir, stem, tracks, envelopes)
        print(f"Wrote {len(paths)} paste-ready payload(s):\n", file=sys.stderr)
        for p in paths:
            print(f"  {p}", file=sys.stderr)
        print("\nPaste one into any chat AI, save the JSON reply to the path named "
              "at the end of the file, then run render.", file=sys.stderr)

    # Unattended path: fill the specs now by calling a model.
    if getattr(args, "call_model", False):
        for track in tracks:
            env = envelopes[track]
            print(f"Calling model for the {track} track ...", file=sys.stderr)
            raw = query_model(f"{env['system_prompt']}\n\n{env['user_prompt']}",
                              args.model, args.ollama_model, args.allow_local)
            filled = Path(env["write_completion_to"])
            filled.write_text(strip_fences(raw), encoding="utf-8")
            print(f"  filled {filled}", file=sys.stderr)
        print(f"\nAll tracks filled. Now run:\n  {next_cmd}",
              file=sys.stderr)

    print(f"Wrote {len(written)} prep file(s) for `{source.name}`:\n")
    for track, prep_path, _ in written:
        print(f"  [{track}] {prep_path}")
    print(f"\nFill each file, then run:\n  {next_cmd}")


def run_code_render(args):
    global _PRECHECK_SIDECAR_DIR
    source = Path(args.source_file)
    out_dir = Path(args.output_dir)
    # Lets the audit renderer pick up PRECHECK.json written by the prep step.
    _PRECHECK_SIDECAR_DIR = out_dir
    # Must derive the stem exactly as prep did, or render looks for filled JSON
    # under a name prep never wrote.
    stem = (re.sub(r'[^a-z0-9]+', '-', source.name.lower()).strip('-') or "topic"
            if source.is_dir() else source.stem)
    results = {}
    failed_validation = []

    for track in _track_list(args.format):
        _, _, _, renderer = _CODE_TRACKS[track]
        filled_path = out_dir / f"{stem}_{track}.filled.json"
        data = load_filled_json(filled_path)

        if args.validate:
            if not print_validation(validate_json(data, _CODE_VALIDATION.get(track, []))):
                failed_validation.append(track)

        md = renderer(data, source.name)
        results[track] = md
        if args.validate:
            total, breakdown = score_document(
                md, data, _CODE_VALIDATION.get(track, []), track)
            if not print_quality_score(track, total, breakdown, args.min_score):
                if track not in failed_validation:
                    failed_validation.append(track)
        (out_dir / f"{stem}_{track}.json").write_text(
            json.dumps(data, indent=2), encoding="utf-8")
        (out_dir / f"{stem}_{track}.md").write_text(md, encoding="utf-8")
        print(f"  wrote {out_dir / f'{stem}_{track}.md'}", file=sys.stderr)

    wrote = False
    if args.output_layman and "layman" in results:
        Path(args.output_layman).write_text(results["layman"], encoding="utf-8")
        wrote = True
    if args.output_dev and "developer" in results:
        Path(args.output_dev).write_text(results["developer"], encoding="utf-8")
        wrote = True
    if getattr(args, "output_audit", None) and "audit" in results:
        Path(args.output_audit).write_text(results["audit"], encoding="utf-8")
        wrote = True
    if args.output:
        full = "\n\n---\n\n".join(
            results[t] for t in _track_list(args.format) if t in results)
        Path(args.output).write_text(full, encoding="utf-8")
        wrote = True
    if args.json:
        print(json.dumps(results))
    elif not wrote and args.format != "both":
        print(results[_track_list(args.format)[0]])

    _exit_on_failed_validation(failed_validation)


# ══════════════════════════════════════════════════════════════════════
#  MODE RUNNERS — RELEASE
# ══════════════════════════════════════════════════════════════════════

def _release_meta(args) -> dict:
    return {
        "project": getattr(args, "project", None) or "Release",
        "version": getattr(args, "version", None) or "",
        "previous": getattr(args, "previous", None),
        "target": getattr(args, "target", None),
        "date": getattr(args, "date", None) or datetime.now().strftime("%Y-%m-%d"),
    }


def run_release_prep(args):
    if args.stdin:
        print("Reading from stdin (Ctrl+D when done)...", file=sys.stderr)
        technical_input = sys.stdin.read().strip()
    elif args.input:
        p = Path(args.input)
        if not p.exists():
            print(f"Error: file not found: {args.input}", file=sys.stderr)
            sys.exit(1)
        technical_input = p.read_text(encoding="utf-8", errors="replace")
    else:
        cwd = Path(args.output_dir).parent if args.output_dir != "." else Path.cwd()
        git_ctx = get_git_context(cwd)
        if not git_ctx.get("last_tag"):
            print("Error: no --input/--stdin, and no git tags to auto-generate from.",
                  file=sys.stderr)
            sys.exit(1)
        tag = git_ctx["last_tag"]
        print(f"Auto-generating from git: commits since {tag}...", file=sys.stderr)
        technical_input = _shell(f"git log {tag}..HEAD --stat", cwd=cwd)
        if not technical_input.strip():
            technical_input = (f"No commits since {tag}. "
                               "This appears to be a maintenance or documentation release.")
        if not args.version and git_ctx.get("tags"):
            parts = tag.lstrip("v").split(".")
            if len(parts) >= 2 and parts[-1].isdigit():
                parts[-1] = str(int(parts[-1]) + 1)
                args.version = "v" + ".".join(parts)

    if not technical_input.strip():
        print("Error: input is empty.", file=sys.stderr)
        sys.exit(1)

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    write_output_gitignore(out_dir)
    meta = _release_meta(args)
    meta_block = "\n".join(f"{k.upper()}: {v}" for k, v in meta.items() if v)
    (out_dir / "release.meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

    context_block = ""
    if not args.no_auto_context:
        context_block = build_context_block(
            cwd=out_dir if out_dir.exists() else Path.cwd()) + "\n\n"

    next_cmd = f"{_invocation()} release render --output-dir {args.output_dir} --validate"

    for track in ["layman", "developer"]:
        system, schema_hint, jsonschema, _ = _RELEASE_TRACKS[track]
        prep_path = out_dir / f"release_{track}.prep.json"
        filled_path = out_dir / f"release_{track}.filled.json"
        user_prompt = (
            f"{context_block}{meta_block}\n\n"
            f"CHANGE INPUT:\n{technical_input}\n\n"
            f"Return JSON matching:\n{schema_hint}"
        )
        _write_prep_file(prep_path, _prep_envelope(
            system, user_prompt, schema_hint, jsonschema, filled_path, next_cmd))
        print(f"  [{track}] {prep_path}")

    print(f"\nFill each file, then run:\n  {next_cmd}")


def run_release_render(args):
    out_dir = Path(args.output_dir)
    meta_path = Path(args.meta) if args.meta else out_dir / "release.meta.json"
    meta = (json.loads(meta_path.read_text(encoding="utf-8"))
            if meta_path.exists() else _release_meta(args))

    results = {}
    failed_validation = []
    for track in ["layman", "developer"]:
        attr = f"{track}_json"
        default = out_dir / f"release_{track}.filled.json"
        path = Path(getattr(args, attr)) if getattr(args, attr, None) else default
        data = load_filled_json(path)
        _, _, _, renderer = _RELEASE_TRACKS[track]

        if args.validate:
            if not print_validation(validate_json(data, _RELEASE_VALIDATION.get(track, []))):
                failed_validation.append(track)

        md = renderer(data, meta)
        results[track] = md
        if args.validate:
            total, breakdown = score_document(
                md, data, _RELEASE_VALIDATION.get(track, []), track)
            if not print_quality_score(track, total, breakdown, args.min_score):
                if track not in failed_validation:
                    failed_validation.append(track)

    full_md = results["layman"] + "\n\n---\n\n" + results["developer"]

    wrote = False
    if args.output_layman:
        Path(args.output_layman).write_text(results["layman"], encoding="utf-8")
        wrote = True
    if args.output_dev:
        Path(args.output_dev).write_text(results["developer"], encoding="utf-8")
        wrote = True
    if args.output:
        Path(args.output).write_text(full_md, encoding="utf-8")
        wrote = True
    if args.json:
        print(json.dumps(results))
    elif not wrote:
        print(full_md)

    _exit_on_failed_validation(failed_validation)


# ══════════════════════════════════════════════════════════════════════
#  SESSION MODE — "what did we do in this folder"
# ══════════════════════════════════════════════════════════════════════
#
# This is the input mode that code/release cannot produce. It answers:
# "an agent (or a human) worked in this directory — document what was done."
#
# The primary inputs are:
#   git diff (what changed)
#   git log --stat (when, in what order, with size)
#   an optional narrative file (why — the reasoning the agent would not have
#   committed, such as why an approach was abandoned or a bug was found)
#
# The model is told explicitly: you are writing about WORK DONE, not about
# the current state of the code. The two are different. "The code now contains
# X" is a state fact. "We added X because Y failed" is a work fact.
# The layman track answers: "what happened here and what does it mean for me?"
# The developer track answers: "what exactly changed, why, and what is left?"

SESSION_DEV_SYSTEM = f"""You are writing a work record for an engineer who needs to understand
exactly what was done in this session, why each decision was made, and what
remains. This is not a description of the current code state — it is a record
of the work: what was attempted, what succeeded, what failed, and what was
deliberately deferred.

Structure your output using DITA information types:
  - concept: what problem was being solved, what approach was taken, what was
    the state before vs after
  - reference: tables of changed files, decisions made, things tried and
    abandoned, open items
  - task: how to verify the work is correct, how to continue it

Be precise about what is DONE vs CLAIMED vs UNTESTED. If the git log says a
feature was added but there is no test evidence, say so. Do not promote
"added to argparse" to "implemented" — those are different states.

{_IBM_STYLE}
{_CLAIM_SOURCING}
{_FILL_ALL_FIELDS}
Respond with ONLY valid JSON matching the schema. No markdown fence, no text
before or after the JSON object."""

SESSION_DEV_SCHEMA_HINT = """{
  "title": "One line: what work was done, e.g. 'pfind v3.0.0: ripgrep+eza merge'",

  /* DITA CONCEPT — the work, not the current state */
  "concept": {
    "problem_being_solved": "What was broken, missing, or needed. The starting condition.",
    "approach_taken": "How the problem was addressed. The strategy, not the steps.",
    "before_state": "What the relevant system/file/feature looked like before this session.",
    "after_state": "What it looks like now. Be honest: 'added to CLI but not wired' is not 'implemented'.",
    "known_alternatives": "Approaches that were NOT taken. Quote commit messages or comments. If none documented, write 'Not available in the source material.'"
  },

  /* DITA REFERENCE — the audit trail */
  "reference": {
    "files_changed": [{"file": "path/to/file", "change": "added|modified|deleted",
                       "what_changed": "one line", "why": "the reason for this specific change"}],
    "decisions_made": [{"decision": "what was decided",
                        "reason": "why — quote a comment or commit message if available, otherwise mark as inference",
                        "basis": "stated_in_input or model_inference"}],
    "tried_and_abandoned": [{"attempt": "what was tried",
                              "why_abandoned": "what went wrong or why it was a dead end"}],
    "claimed_but_not_verified": ["list anything the prior docs claim is done but that has no test evidence in the diff"],
    "open_items": [{"item": "what remains", "priority": "high|medium|low",
                    "blocking": "what it blocks, or 'nothing currently'"}]
  },

  /* DITA TASK — verification */
  "verification_task": {
    "task_title": "How to verify this work is correct",
    "steps": [{"step": 1, "action": "exact command or check",
               "expected_result": "what passing looks like",
               "what_failure_looks_like": "what a broken state would show"}]
  },

  "technical_debt": [{"item": "...", "severity": "low|medium|high",
                      "recommendation": "specific next action"}],

  "claim_sources": [{"claim": "a conclusion you drew", "basis": "stated_in_input or model_inference",
                     "evidence": "exact phrase that led to this conclusion, or null"}]
}"""

SESSION_DEV_JSONSCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "concept": {"type": "object", "properties": {
            "problem_being_solved": {"type": "string"},
            "approach_taken": {"type": "string"},
            "before_state": {"type": "string"},
            "after_state": {"type": "string"},
            "known_alternatives": {"type": "string"}}},
        "reference": {"type": "object", "properties": {
            "files_changed": {"type": "array", "items": {"type": "object"}},
            "decisions_made": {"type": "array", "items": {"type": "object"}},
            "tried_and_abandoned": {"type": "array", "items": {"type": "object"}},
            "claimed_but_not_verified": {"type": "array", "items": {"type": "string"}},
            "open_items": {"type": "array", "items": {"type": "object"}}}},
        "verification_task": {"type": "object"},
        "technical_debt": {"type": "array", "items": {"type": "object"}},
        "claim_sources": _CLAIM_SOURCES_FIELD,
    },
    "required": ["title", "concept", "reference", "verification_task", "claim_sources"],
}

SESSION_LAYMAN_SYSTEM = f"""You are writing for someone who commissioned this work, can read the
outcome but cannot read the code, and needs to understand what was done, what
it means for them, and whether they should be concerned.

This is NOT a technical release note. It is a plain-language account of a
session of work. Write as if explaining to a careful, intelligent non-coder:
  - What problem were we solving?
  - What did we actually do?
  - What is finished, what is not, and what does "not finished" mean in practice?
  - Is there anything they need to know about quality or risk?
  - What should they expect to be able to do now that they could not before?

Be honest about partial work. "We added the flag to the menu but it does not do
anything yet" is a real state. Document it, not a polished version of it.

{_IBM_STYLE}
{_CLAIM_SOURCING}
{_FILL_ALL_FIELDS}
Respond with ONLY valid JSON matching the schema. No markdown fence, no text
before or after the JSON object."""

SESSION_LAYMAN_SCHEMA_HINT = """{
  "title": "Plain-English title: what happened in this session",

  /* DITA CONCEPT */
  "concept": {
    "big_picture": "2-3 paragraphs. What problem were we solving and why does it matter?",
    "before_after": [{"area": "what aspect changed", "before": "what it was like",
                      "after": "what it is like now", "who_it_affects": "everyone|some users"}],
    "honest_state": "What is genuinely done, what is half-done, and what was not touched. Be specific — 'mostly done' is not a state.",
    "worst_case": "The most harmful outcome if something that looks done turns out to be broken. State it in terms of what the user would experience, with a concrete example."
  },

  "what_you_can_do_now": ["List things the user can now do that they could not before. One per item. If nothing is new for end users yet, say so."],

  "what_is_still_missing": [{"item": "...", "practical_impact": "what the user cannot do yet because of this"}],

  /* DITA TASK */
  "how_to_verify": {
    "task_title": "How to check that what we say is done actually works",
    "steps": [{"step": 1, "action": "concrete step a non-coder can follow or delegate",
               "success_looks_like": "..."}]
  },

  "should_you_be_concerned": "Honest assessment. Not a reassurance. If there are risks, name them.",

  "glossary": [{"term": "...", "definition": "one sentence, no jargon"}],

  "claim_sources": [{"claim": "a conclusion you drew", "basis": "stated_in_input or model_inference",
                     "evidence": "exact phrase or null"}]
}"""

SESSION_LAYMAN_JSONSCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "concept": {"type": "object", "properties": {
            "big_picture": {"type": "string"},
            "before_after": {"type": "array", "items": {"type": "object"}},
            "honest_state": {"type": "string"},
            "worst_case": {"type": "string"}}},
        "what_you_can_do_now": {"type": "array", "items": {"type": "string"}},
        "what_is_still_missing": {"type": "array", "items": {"type": "object"}},
        "how_to_verify": {"type": "object"},
        "should_you_be_concerned": {"type": "string"},
        "glossary": {"type": "array", "items": {"type": "object"}},
        "claim_sources": _CLAIM_SOURCES_FIELD,
    },
    "required": ["title", "concept", "what_you_can_do_now", "what_is_still_missing",
                 "should_you_be_concerned", "claim_sources"],
}

_SESSION_TRACKS = {
    "layman": (SESSION_LAYMAN_SYSTEM, SESSION_LAYMAN_SCHEMA_HINT,
               SESSION_LAYMAN_JSONSCHEMA, None),   # renderer added below
    "developer": (SESSION_DEV_SYSTEM, SESSION_DEV_SCHEMA_HINT,
                  SESSION_DEV_JSONSCHEMA, None),
}

_SESSION_VALIDATION = {
    "layman": ["concept", "what_you_can_do_now", "what_is_still_missing",
               "should_you_be_concerned"],
    "developer": ["concept", "reference", "verification_task"],
}


def render_session_dev(d: dict, slug: str) -> str:
    now = datetime.now().strftime("%Y-%m-%d")
    L = [f"# {d.get('title', slug)}",
         f"\n> Session record generated {now}\n",
         "---\n"]
    concept = d.get("concept", {})
    for label, key in [("Problem Being Solved", "problem_being_solved"),
                       ("Approach Taken", "approach_taken"),
                       ("Before", "before_state"),
                       ("After", "after_state"),
                       ("Known Alternatives", "known_alternatives")]:
        if concept.get(key):
            L += [f"## {label}\n", concept[key] + "\n"]

    ref = d.get("reference", {})
    if ref.get("files_changed"):
        L += ["## Files Changed\n",
              "| File | Change | What Changed | Why |",
              "|------|--------|--------------|-----|"]
        for f in ref["files_changed"]:
            L.append(f"| `{f.get('file','')}` | {f.get('change','')} | "
                     f"{f.get('what_changed','')} | {f.get('why','')} |")
        L.append("")
    if ref.get("decisions_made"):
        L.append("## Decisions Made\n")
        for dec in ref["decisions_made"]:
            basis = dec.get("basis", "model_inference")
            icon = "📄" if basis == "stated_in_input" else "🤖"
            L.append(f"- {icon} **{dec.get('decision','')}** — {dec.get('reason','')}")
        L.append("")
    if ref.get("tried_and_abandoned"):
        L.append("## Tried and Abandoned\n")
        for t in ref["tried_and_abandoned"]:
            L.append(f"- **{t.get('attempt','')}** — {t.get('why_abandoned','')}")
        L.append("")
    if ref.get("claimed_but_not_verified"):
        L.append("## ⚠ Claimed But Not Verified\n")
        L.append("*Prior documents claimed these are done. No test evidence found in this diff:*\n")
        for item in ref["claimed_but_not_verified"]:
            L.append(f"- {item}")
        L.append("")
    if ref.get("open_items"):
        L += ["## Open Items\n",
              "| Item | Priority | Blocks |",
              "|------|----------|--------|"]
        for o in ref["open_items"]:
            L.append(f"| {o.get('item','')} | {o.get('priority','')} | "
                     f"{o.get('blocking','')} |")
        L.append("")

    vtask = d.get("verification_task", {})
    if vtask.get("steps"):
        L.append(f"## {vtask.get('task_title','Verification')}\n")
        for s in vtask["steps"]:
            action = s.get('action', '')
            L.append(f"**Step {s.get('step','')}:**")
            L += ["```bash", action, "```"]
            if s.get("expected_result"):
                L.append(f"  - **Pass:** {s['expected_result']}")
            if s.get("what_failure_looks_like"):
                L.append(f"  - **Fail:** {s['what_failure_looks_like']}")
            L.append("")
        L.append("")

    dev_glossary = d.get("glossary", [])
    if dev_glossary:
        L.append("## Glossary\n")
        for g in dev_glossary:
            L.append(f"**{g.get('term','')}** — {g.get('definition','')}\n")

    debt = d.get("technical_debt", [])
    if debt:
        icons = {"low": "🟡", "medium": "🟠", "high": "🔴"}
        L.append("## Technical Debt\n")
        for t in debt:
            sev = t.get("severity", "low")
            L.append(f"{icons.get(sev,'🟡')} **{sev.upper()}** — "
                     f"{t.get('item','')} → {t.get('recommendation','')}")
        L.append("")

    L.extend(render_claim_sources(d))
    L.append(TRANSPARENCY_FOOTER)
    L.append("\n*Session record. Developer track. "
             "Covers work done, not current code state.*")
    return "\n".join(L)


def render_session_layman(d: dict, slug: str) -> str:
    now = datetime.now().strftime("%Y-%m-%d")
    L = [f"# {d.get('title', slug)} — Plain Language",
         f"\n> Session record generated {now}\n",
         "---\n"]
    concept = d.get("concept", {})
    if concept.get("big_picture"):
        L += ["## What happened\n", concept["big_picture"] + "\n"]
    if concept.get("honest_state"):
        L += ["## Honest state of play\n", concept["honest_state"] + "\n"]
    if concept.get("worst_case"):
        L += ["## Worst case if something is wrong\n", concept["worst_case"] + "\n"]

    ba = concept.get("before_after", [])
    if ba:
        L.append("## What changed for you\n")
        for b in ba:
            L.append(f"**{b.get('area','')}**")
            L.append(f"- Before: {b.get('before','')}")
            L.append(f"- After:  {b.get('after','')}")
            if b.get("who_it_affects"):
                L.append(f"- Affects: {b['who_it_affects']}")
            L.append("")

    can_do = d.get("what_you_can_do_now", [])
    if can_do:
        L.append("## What you can do now\n")
        for item in can_do:
            L.append(f"- {item}")
        L.append("")

    missing = d.get("what_is_still_missing", [])
    if missing:
        L.append("## What is still missing\n")
        for m in missing:
            L.append(f"- **{m.get('item','')}** — {m.get('practical_impact','')}")
        L.append("")

    vtask = d.get("how_to_verify", {})
    if vtask.get("steps"):
        L.append(f"## {vtask.get('task_title','How to check')}\n")
        for s in vtask["steps"]:
            action = s.get('action', '')
            L.append(f"**Step {s.get('step','')}:**")
            L += ["```bash", action, "```"]
            if s.get("success_looks_like"):
                L.append(f"  - **Pass:** {s['success_looks_like']}")
            L.append("")
        L.append("")

    if d.get("should_you_be_concerned"):
        L += ["## Should you be concerned?\n", d["should_you_be_concerned"] + "\n"]

    glossary = d.get("glossary", [])
    if glossary:
        L.append("## Glossary\n")
        for g in glossary:
            L.append(f"**{g.get('term','')}** — {g.get('definition','')}\n")

    L.extend(render_claim_sources(d))
    L.append(TRANSPARENCY_FOOTER)
    L.append("\n*Session record. Plain-language track. "
             "Its developer twin covers the same session in technical detail.*")
    return "\n".join(L)


# Wire renderers into track registry (defined after functions exist)
_SESSION_TRACKS["layman"] = (SESSION_LAYMAN_SYSTEM, SESSION_LAYMAN_SCHEMA_HINT,
                              SESSION_LAYMAN_JSONSCHEMA, render_session_layman)
_SESSION_TRACKS["developer"] = (SESSION_DEV_SYSTEM, SESSION_DEV_SCHEMA_HINT,
                                 SESSION_DEV_JSONSCHEMA, render_session_dev)


def _build_session_input(target: Path, narrative_file: Path = None,
                         since: str = None) -> tuple:
    """Assemble the three-layer session input: diff + log + narrative.

    Returns (text, slug). The three layers serve distinct purposes:
      git diff --stat  — what files changed and by how much (scope)
      git diff         — the exact changes (evidence for decisions)
      git log --stat   — the sequence of commits (timeline)
      narrative file   — why (the reasoning that wasn't committed)

    Any layer that is unavailable is noted explicitly rather than silently
    skipped, so the model knows what it is NOT seeing.
    """
    cwd = target if target.is_dir() else target.parent
    slug = re.sub(r'[^a-z0-9]+', '-', target.name.lower()).strip('-') or "session"

    since_arg = since or "HEAD~10"   # default: last 10 commits
    parts = [f"SESSION INPUT — directory: {target}", f"Generated: {datetime.now().isoformat()}", ""]

    # Layer 1: diff stat (scope overview)
    diff_stat = _shell(f"git diff {since_arg} --stat", cwd=cwd)
    if diff_stat:
        parts += ["=" * 60, f"GIT DIFF STAT (since {since_arg})", "=" * 60, diff_stat, ""]
    else:
        parts += [f"GIT DIFF STAT: not available (no git repo, or no changes since {since_arg})", ""]

    # Layer 2: full diff (evidence)
    diff_full = _shell(f"git diff {since_arg} -- . ':(exclude)*.lock'", cwd=cwd)
    if diff_full:
        # Cap at ~600 lines to avoid flooding the context; model sees scope from stat
        diff_lines = diff_full.splitlines()
        truncated = len(diff_lines) > 600
        diff_display = "\n".join(diff_lines[:600])
        parts += ["=" * 60, f"GIT DIFF (first 600 lines{', truncated' if truncated else ''})",
                  "=" * 60, diff_display, ""]
        if truncated:
            parts.append(f"[... {len(diff_lines) - 600} more lines truncated. "
                         f"Use --since to narrow the range if needed.]\n")
    else:
        parts += ["GIT DIFF: not available (no changes or no git repo)", ""]

    # Layer 3: commit log (timeline)
    log = _shell(f"git log {since_arg} --oneline --stat", cwd=cwd)
    if log:
        parts += ["=" * 60, f"GIT LOG (since {since_arg})", "=" * 60, log, ""]
    else:
        parts += ["GIT LOG: not available", ""]

    # Layer 4: narrative (the why — what was not committed)
    if narrative_file and narrative_file.exists():
        narrative = narrative_file.read_text(encoding="utf-8", errors="replace")
        parts += ["=" * 60,
                  f"NARRATIVE / SESSION NOTES ({narrative_file.name})",
                  "These are the agent's or operator's own notes about this session.",
                  "This is the primary source for WHY decisions were made.",
                  "=" * 60, narrative, ""]
    else:
        parts += ["NARRATIVE: not provided. The 'why' behind decisions must be",
                  "inferred from commit messages and diff context, or marked as",
                  "model_inference in claim_sources.", ""]

    # Prior documentation: what prior agents claimed
    prior = get_prior_doc_context(cwd)
    if prior:
        parts += ["=" * 60,
                  "PRIOR DOCUMENTATION — claims from previous docs in this directory.",
                  "Your document must confirm, correct, or supersede these claims.",
                  "Do NOT repeat a prior claim without checking it against the diff.",
                  "=" * 60]
        for p, excerpt in prior:
            parts += ["", f"--- {p.name} ---", excerpt,
                      f"[truncated. Full path: {p}]"]

    return "\n".join(parts), slug


def run_session_prep(args):
    target = Path(args.target)
    if not target.exists():
        raise DualTrackError(f"target not found: {target}")
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    write_output_gitignore(out_dir)

    narrative = Path(args.narrative) if getattr(args, "narrative", None) else None
    session_input, slug = _build_session_input(
        target,
        narrative_file=narrative,
        since=getattr(args, "since", None))

    tracks = _track_list(args.format)
    next_cmd = (f"{_invocation()} session render {args.target} "
                f"--output-dir {args.output_dir} --validate")
    written = []
    envelopes = {}

    for track in tracks:
        system, schema_hint, jsonschema, _ = _SESSION_TRACKS[track]
        prep_path = out_dir / f"{slug}_session_{track}.prep.json"
        filled_path = out_dir / f"{slug}_session_{track}.filled.json"
        user_prompt = (
            f"Document the work done in this session. You are writing about WHAT WAS DONE "
            f"and WHY, not the current state of the code.\n\n"
            f"SCHEMA HINTS:\n{schema_hint}\n\n"
            f"SESSION INPUT:\n{session_input}"
        )
        envelope = _prep_envelope(system, user_prompt, schema_hint, jsonschema,
                                  filled_path, next_cmd)
        envelopes[track] = envelope
        _write_prep_file(prep_path, envelope)
        written.append((track, prep_path, filled_path))

    if getattr(args, "payload", False):
        paths = write_payloads(out_dir, f"{slug}_session", tracks, envelopes)
        print(f"Wrote {len(paths)} paste-ready payload(s):", file=sys.stderr)
        for p in paths:
            print(f"  {p}", file=sys.stderr)

    print(f"Wrote {len(written)} session prep file(s) for `{target.name}`:\n")
    for track, prep_path, _ in written:
        print(f"  [{track}] {prep_path}")
    print(f"\nFill each file, then run:\n  {next_cmd}")


def run_session_render(args):
    target = Path(args.target)
    out_dir = Path(args.output_dir)
    slug = re.sub(r'[^a-z0-9]+', '-', target.name.lower()).strip('-') or "session"

    results = {}
    failed_validation = []

    for track in _track_list(args.format):
        _, _, _, renderer = _SESSION_TRACKS[track]
        filled_path = out_dir / f"{slug}_session_{track}.filled.json"
        data = load_filled_json(filled_path)

        if args.validate:
            if not print_validation(validate_json(data, _SESSION_VALIDATION.get(track, []))):
                failed_validation.append(track)

        md = renderer(data, slug)
        results[track] = md

        if args.validate:
            total, breakdown = score_document(
                md, data, _SESSION_VALIDATION.get(track, []), track)
            if not print_quality_score(track, total, breakdown, args.min_score):
                if track not in failed_validation:
                    failed_validation.append(track)

        (out_dir / f"{slug}_session_{track}.md").write_text(md, encoding="utf-8")
        print(f"  wrote {out_dir / f'{slug}_session_{track}.md'}", file=sys.stderr)

    if args.output:
        full = "\n\n---\n\n".join(
            results[t] for t in _track_list(args.format) if t in results)
        Path(args.output).write_text(full, encoding="utf-8")

    _exit_on_failed_validation(failed_validation)


# ══════════════════════════════════════════════════════════════════════
#  CLEANUP — retire working files AFTER the deliverables are published
# ══════════════════════════════════════════════════════════════════════

def _git(out_dir: Path, cmd: str) -> str:
    return _shell(f"git {cmd}", cwd=out_dir)


def run_cleanup(args):
    """Quarantine the pipeline's working files (.prep.json, .filled.json,
    PAYLOAD.*, PRECHECK.json) once — and only once — the rendered .md
    deliverables are proven committed AND pushed.

    Refuses loudly otherwise. Nothing is ever deleted by default: files are
    moved to a dated folder under the trash root so the cleanup is
    reversible. --delete performs a real deletion and exists only for an
    owner who explicitly asked for removal.
    """
    out_dir = Path(args.output_dir).resolve()
    if not out_dir.is_dir():
        raise DualTrackError(f"output dir not found: {out_dir}")

    intermediates = sorted(
        p for pattern in INTERMEDIATE_GLOBS for p in out_dir.glob(pattern))
    if not intermediates:
        print(f"Nothing to clean in {out_dir} — no working files present.")
        return

    deliverables = sorted(p for p in out_dir.glob("*.md"))
    if not deliverables:
        raise DualTrackError(
            f"Refusing to clean {out_dir}: no rendered .md files exist there.\n"
            "The working files are the only record — render first:\n"
            f"  {_invocation()} <mode> render ... --output-dir {out_dir}")

    # ── Publication proof ─────────────────────────────────────────────
    if args.skip_publish_check:
        print("⚠️  --skip-publish-check: NOT verifying the .md files are pushed.")
    else:
        toplevel = _git(out_dir, "rev-parse --show-toplevel")
        if not toplevel:
            raise DualTrackError(
                f"Refusing to clean: {out_dir} is not inside a git repository, "
                "so publication cannot be verified.\n"
                "If this output is intentionally not under git, re-run with "
                "--skip-publish-check.")
        problems = []
        for md in deliverables:
            # git runs with cwd=out_dir, so pathspecs are relative to out_dir
            if not _git(out_dir, f"ls-files -- '{md.name}'"):
                problems.append(f"  NOT COMMITTED: {md.name}")
            elif _git(out_dir, f"status --porcelain -- '{md.name}'"):
                problems.append(f"  MODIFIED SINCE COMMIT: {md.name}")
        upstream = _git(out_dir, "rev-parse --abbrev-ref --symbolic-full-name @{u}")
        if not upstream:
            problems.append("  NO UPSTREAM: the branch has no remote tracking "
                            "branch, so 'pushed' cannot be verified.")
        else:
            unpushed = _git(out_dir, "log --oneline @{u}..HEAD")
            if unpushed:
                problems.append(f"  UNPUSHED COMMITS ahead of {upstream}:\n    "
                                + "\n    ".join(unpushed.splitlines()[:5]))
        if problems:
            raise DualTrackError(
                "Refusing to clean — publication of the deliverables is NOT "
                "confirmed:\n" + "\n".join(problems) +
                "\nCommit and push the .md files first, then re-run cleanup.")
        print(f"✅ Publication confirmed: {len(deliverables)} .md file(s) "
              f"committed and pushed ({upstream}).")

    # ── Retire the working files ──────────────────────────────────────
    if args.delete:
        for p in intermediates:
            p.unlink()
            print(f"  🗑️  deleted {p.name}")
        print(f"\nDeleted {len(intermediates)} working file(s). "
              "(--delete was explicit; no copy kept)")
        return

    trash_root = Path(args.trash).expanduser() if args.trash else None
    if trash_root is None:
        house = Path.home() / "Agents.Work.Trash"
        trash_root = house if house.is_dir() else out_dir / ".dual-track-retired"
    dest = trash_root / f"dual-track-cleanup-{datetime.now().strftime('%y-%m-%d-%H-%M')}"
    dest.mkdir(parents=True, exist_ok=True)
    for p in intermediates:
        shutil.move(str(p), str(dest / p.name))
        print(f"  📦 {p.name}  →  {dest}")
    print(f"\nQuarantined {len(intermediates)} working file(s) to:\n  {dest}\n"
          "Nothing was deleted — restore by moving the files back.")


# ══════════════════════════════════════════════════════════════════════
#  CLI
# ══════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description=(
            "Dual-track documentation generator (IBM/DITA edition). "
            "Produces layman + developer + audit tracks. Rule-based pre-check "
            "runs offline; prep/render never makes a network call. "
            "See module docstring for the workflow."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    mode_sub = parser.add_subparsers(dest="mode", required=True)

    # ── code ──────────────────────────────────────────────────────────
    code_p = mode_sub.add_parser("code", help="Document a source code file")
    code_action = code_p.add_subparsers(dest="action", required=True)

    cp = code_action.add_parser("prep", help="Write prep file(s) — do this first")
    cp.add_argument("source_file")
    cp.add_argument("--output-dir", default="./docs")
    cp.add_argument("--format", choices=["both", "all", "layman", "developer", "audit"],
                    default="both",
                    help="both = layman + developer (default); all = adds the audit")
    cp.add_argument("--no-auto-context", action="store_true")
    cp.add_argument("--rules", metavar="FILE",
                    help="Project rule plugin. Default: nearest .dual-track-rules.py")
    cp.add_argument("--no-precheck", action="store_true",
                    help="Skip the rule pre-check. Rarely right — it is the only "
                         "part of the report that is not a model's opinion.")
    cp.add_argument("--context", metavar="FILE",
                    help="File of VERIFIED measurements. Numbers absent from it "
                         "must be written as 'not measured', never estimated.")
    cp.add_argument("--payload", action="store_true",
                    help="Also write paste-ready PAYLOAD.*.txt prompts for use in "
                         "any free chat window when there is no quota or key.")
    cp.add_argument("--call-model", action="store_true",
                    help="Fill the specs now by calling a model. Off by default: "
                         "prep/render needs no network at all.")
    cp.add_argument("--model", default="auto",
                    help="auto | claude-* | gemini-* | an Ollama tag")
    cp.add_argument("--ollama-model", default="gemma4:latest")
    cp.add_argument("--allow-local", action="store_true",
                    help="Permit the local Ollama model. EMERGENCY use by a human "
                         "with no quota — never the normal channel for an agent.")

    cr = code_action.add_parser("render", help="Render filled JSON to Markdown")
    cr.add_argument("source_file")
    cr.add_argument("--output-dir", default="./docs")
    cr.add_argument("--format", choices=["both", "all", "layman", "developer", "audit"],
                    default="both")
    cr.add_argument("--no-validate", dest="validate", action="store_false",
                    help="Skip quality validation. Default is to validate.")
    cr.set_defaults(validate=True)
    cr.add_argument("--output-audit", metavar="FILE")
    cr.add_argument("--min-score", type=int, default=85, metavar="N",
                    help="Quality gate threshold, 0-100 (default 85).")
    cr.add_argument("--output", "-o")
    cr.add_argument("--output-layman", metavar="FILE")
    cr.add_argument("--output-dev", metavar="FILE")
    cr.add_argument("--json", action="store_true")
    cr.add_argument("--no-auto-context", action="store_true")

    # ── precheck ──────────────────────────────────────────────────────
    pc = mode_sub.add_parser(
        "precheck",
        help="Rule-based defect scan. No model, no network, no opinions.")
    pc.add_argument("target", help="File or directory to scan")
    pc.add_argument("--output-dir", default=".")
    pc.add_argument("--rules", metavar="FILE")
    pc.set_defaults(action="run")

    # ── session ───────────────────────────────────────────────────────
    ses_p = mode_sub.add_parser(
        "session",
        help="Document what was done in a directory: git diff + log + optional narrative")
    ses_action = ses_p.add_subparsers(dest="action", required=True)

    sp = ses_action.add_parser(
        "prep", help="Assemble session input and write prep file(s) — do this first")
    sp.add_argument("target", help="Directory where the work happened")
    sp.add_argument("--output-dir", default=".")
    sp.add_argument("--format", choices=["both", "layman", "developer"],
                    default="both")
    sp.add_argument("--since", metavar="REF",
                    help="Git ref to diff from (default: HEAD~10). "
                         "Use a tag (v1.2.3), a commit hash, or HEAD~N.")
    sp.add_argument("--narrative", metavar="FILE",
                    help="Plain-text file of session notes / reasoning. "
                         "This is the 'why' layer — what the agent decided and why. "
                         "If omitted, WHY must be inferred from commit messages.")
    sp.add_argument("--payload", action="store_true",
                    help="Also write paste-ready PAYLOAD.*.txt prompts.")

    sr = ses_action.add_parser("render", help="Render filled session JSON to Markdown")
    sr.add_argument("target", help="Directory where the work happened (used for naming)")
    sr.add_argument("--output-dir", default=".")
    sr.add_argument("--format", choices=["both", "layman", "developer"], default="both")
    sr.add_argument("--output", "-o")
    sr.add_argument("--no-validate", dest="validate", action="store_false",
                    help="Skip quality validation. Default is to validate.")
    sr.set_defaults(validate=True)
    sr.add_argument("--min-score", type=int, default=85, metavar="N")
    sr.add_argument("--json", action="store_true")

    # ── cleanup ───────────────────────────────────────────────────────
    cu = mode_sub.add_parser(
        "cleanup",
        help="Retire working files (.prep/.filled/PAYLOAD/PRECHECK.json) after "
             "the rendered .md deliverables are confirmed committed and pushed.")
    cu.add_argument("output_dir", help="The --output-dir the docs were rendered into")
    cu.add_argument("--trash", metavar="DIR",
                    help="Quarantine folder root (default: ~/Agents.Work.Trash "
                         "if it exists, else <output-dir>/.dual-track-retired)")
    cu.add_argument("--delete", action="store_true",
                    help="Really delete instead of quarantining. Only when the "
                         "owner explicitly asked for permanent removal.")
    cu.add_argument("--skip-publish-check", action="store_true",
                    help="Skip the committed-and-pushed verification. Only for "
                         "outputs that are intentionally not under git.")
    cu.set_defaults(action="run")

    # ── release ───────────────────────────────────────────────────────
    rel_p = mode_sub.add_parser("release", help="Generate release notes from a changelog/diff")
    rel_action = rel_p.add_subparsers(dest="action", required=True)

    rp = rel_action.add_parser("prep", help="Write prep file(s) — do this first")
    src = rp.add_mutually_exclusive_group()
    src.add_argument("--input", "-i", metavar="FILE")
    src.add_argument("--stdin", action="store_true")
    rp.add_argument("--output-dir", default=".")
    rp.add_argument("--project", "-p")
    rp.add_argument("--version", "-v")
    rp.add_argument("--previous")
    rp.add_argument("--target", "-t")
    rp.add_argument("--date")
    rp.add_argument("--no-auto-context", action="store_true")

    rr = rel_action.add_parser("render", help="Render filled JSON to Markdown")
    rr.add_argument("--output-dir", default=".")
    rr.add_argument("--layman-json", metavar="FILE")
    rr.add_argument("--dev-json", metavar="FILE")
    rr.add_argument("--meta", metavar="FILE")
    rr.add_argument("--project", "-p")
    rr.add_argument("--version", "-v")
    rr.add_argument("--previous")
    rr.add_argument("--target", "-t")
    rr.add_argument("--date")
    rr.add_argument("--output", "-o")
    rr.add_argument("--output-layman", metavar="FILE")
    rr.add_argument("--output-dev", metavar="FILE")
    rr.add_argument("--no-validate", dest="validate", action="store_false",
                    help="Skip quality validation. Default is to validate.")
    rr.set_defaults(validate=True)
    rr.add_argument("--min-score", type=int, default=85, metavar="N")
    rr.add_argument("--json", action="store_true")

    args = parser.parse_args()
    try:
        dispatch = {
            ("code", "prep"): run_code_prep,
            ("code", "render"): run_code_render,
            ("release", "prep"): run_release_prep,
            ("release", "render"): run_release_render,
            ("precheck", "run"): run_precheck_mode,
            ("cleanup", "run"): run_cleanup,
            ("session", "prep"): run_session_prep,
            ("session", "render"): run_session_render,
        }
        dispatch[(args.mode, args.action)](args)
    except DualTrackError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

