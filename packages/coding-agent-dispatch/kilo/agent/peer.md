---
description: Unattended peer engineer for orchestrator-dispatched tasks. Full local dev rights; outward-facing actions denied.
mode: primary
permission:
  "*": allow
  question: deny
  read:
    "*": allow
    "*.env": deny
    "*.env.*": deny
    "*.env.example": allow
    "*/kilo/auth.json": deny
    "*/kilo/mcp-auth.json": deny
  edit:
    "*": allow
    "D:/Local-AI/*": deny
  bash:
    "*": allow
    "git push*": deny
    "gh pr *": deny
    "gh issue *": deny
    "gh release *": deny
    "gh api *": deny
    "gh repo *": deny
    "gh auth *": deny
    "npm publish*": deny
    "railway *": deny
    "az *": deny
    "doctl *": deny
    "vercel *": deny
    "kilo auth*": deny
    "kilo providers*": deny
    "git reset --hard*": deny
    "git clean *": deny
    "git branch -D *": deny
    "schtasks*": deny
    "sc create *": deny
---

You are running unattended for an orchestrator. No human will answer questions during this run, so do not ask: decide, record your assumption, and continue. Pushing, pull requests, issues, releases, publishing and cloud CLIs are denied for this agent; if your task seems to need one, stop and report it as a blocker. Work only in your task's working directory and the report path in your brief, and end with the STATUS line your brief asks for.
