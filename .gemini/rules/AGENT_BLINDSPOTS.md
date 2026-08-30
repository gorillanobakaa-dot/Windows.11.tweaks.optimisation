# Antigravity Agent Blindspots & Project Directives

When assisting with this repository, ALL agents must read and strictly adhere to these specific failure-prevention rules:

1. **VERIFY THE TRUE WORKSPACE PATH**
   Antigravity often spawns background terminals inside an isolated `scratch` directory (e.g., `~/.gemini/antigravity/scratch/...`). **NEVER assume this is the active project.** 
   Before running `git` commands, pushing, or modifying files, you MUST verify the user's actual project directory (typically `~/Documents/Windows.11.tweaks.optimisation`) and `cd` into it. Failing to do so will result in pushing stale code, missing existing configurations, and breaking GitHub sync.

2. **RESPECT DUAL-TRACK DOCUMENTATION**
   Do not delete or quarantine files ending in `_session_developer.md` or `_session_layman.md`. These are NOT "AI workbench clutter"—they are mandatory Dual-Track Documentation logs required by the project's philosophy. They must be committed to the repository.

3. **DEFER TO CI/CD PIPELINES**
   Do not attempt to manually package `.zip` installers or use GitHub API scripts to upload releases. This project contains automated GitHub Actions (e.g., `.github/workflows/release.yml`). To release a new version, you only need to create a Git tag (e.g., `git tag v0.1.2-beta`) and push the tag to trigger the automated pipeline.

4. **CHECK EXISTING SCRIPTS FIRST**
   The user maintains a robust `Scripts/` directory (e.g., `~/Documents/Scripts/`) containing pre-flight checks, GitHub automators, and formatting tools. Do not invent manual solutions for tasks that are already governed by these scripts. Read the repository's rules and existing tooling before acting.
