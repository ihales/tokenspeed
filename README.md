# TokenSpeed

A tiny macOS menu bar app that tracks output tokens per second for [OpenRouter](https://openrouter.ai), Codex, and Claude Code.

<img src="docs/popover-local.png" alt="Local tab showing Codex and Claude Code throughput by model and speed tier, with one-hour sparklines and sample counts" width="420">
<img src="docs/popover.png" alt="OpenRouter tab showing a watchlist grouped by provider, with throughput, uptime, and sparklines" width="420">

*Example data shown in both screenshots.*

- **Local sessions.** See the last hour of Codex and Claude Code request TPS, grouped by model and speed tier, with sparklines and sample counts.
- **OpenRouter watchlist.** Track median TPS and uptime for a specific provider, tier, or region, or let **Automatic** follow the fastest endpoint.
- **Menu bar pin.** Hover over a row and click its pin to show that local model and tier or OpenRouter endpoint in the menu bar.
- **Badge rules.** Set alerts on OpenRouter throughput or uptime. Active rules appear as colored dots in the menu bar and labeled pills in the popover.
- **No API key or Dock icon.**

The popover remembers whether you last viewed Local or OpenRouter.

## Install

Requires macOS 14+, Swift 6, and [Task](https://taskfile.dev).

```sh
task install     # builds a release bundle into /Applications and launches it
```

To start TokenSpeed when you log in, turn on **Settings → General → Open TokenSpeed at login**.

Use `task run` for a debug build, `task build` to bundle into `dist/`, and `task uninstall` to remove the app.

## How it works

**Local** averages per-request output TPS over a rolling hour. Each timing includes the wait for first output and excludes tool execution between requests. The sample count shows how many completed requests had usable timing. TokenSpeed reads Codex rollouts and diagnostics from `~/.codex` and Claude Code transcripts from `~/.claude/projects`. It also honors `CODEX_HOME` and `CLAUDE_CONFIG_DIR`.

Local refreshes every 30 seconds while visible and every minute for a pinned source in the background. You can show or hide Codex and Claude Code independently in **Settings → General → Local Activity**.

**OpenRouter** refreshes every minute. Median TPS comes from the public feed behind provider pages, and 24-hour uptime comes from the Endpoints API. TokenSpeed records TPS every five minutes and keeps 24 hours of history in `~/Library/Application Support/TokenSpeed/`. [OpenRouter Endpoints API](https://openrouter.ai/docs/api/api-reference/endpoints/list-all-endpoints-for-a-model)
