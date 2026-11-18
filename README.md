# TokenSpeed

TokenSpeed is a macOS 14+ menu bar app for OpenRouter throughput. It runs without a Dock icon.

## Install

With [Task](https://taskfile.dev):

```sh
task install     # release build → /Applications/TokenSpeed.app, then launch
task run         # debug build from dist/, then launch
task build       # release bundle in dist/ only
task uninstall
```

Set `INSTALL_DIR` to install somewhere else, for example `INSTALL_DIR=~/Applications task install`. You can also use **Run** in Codex or `./script/build_and_run.sh`.

To start TokenSpeed when you log in, turn on **Settings → General → Open TokenSpeed at login**. This needs the app bundle (from `task install` or `task run`), not a bare `swift run`.

## The popover

Click the menu bar reading to see your watched models grouped by provider. Each row shows median output tokens per second with its reporting window (such as `30m`), 24-hour uptime, and a sparkline of median TPS over the last 24 hours. Each sparkline uses its endpoint's own scale; hover it to see the first and latest readings and the range. Uptime turns orange below 99% and red below 95%.

The pinned row is highlighted. Hover a row and click the pin to show it in the menu bar instead, or right-click for **Show in Menu Bar** and **Open on OpenRouter**. Matching badge rules appear as labeled chips at the top. ⌘R refreshes, ⌘, opens Settings, and ⌘Q quits.

## Watchlist

In **Settings → Models**, click **+** to add a model: search the OpenRouter catalog, then choose an endpoint. Endpoints are sorted by current speed and show live TPS and uptime. **Automatic** picks the fastest endpoint in the most recent reported TPS window. The same model can be watched on multiple endpoints, such as GPT-6.2 Sol on OpenAI Standard and OpenAI Ultrafast.

Double-click a row (or select it and click **Change Endpoint…**) to switch its provider, tier, or region. Click a row's pin to show it in the menu bar. Drag rows to reorder them within a provider, and use the chevrons in a provider header to move the whole group. Select a row and press Delete or **−** to remove it. The starting watchlist is Claude Fable 5.2, Claude Opus 5.5, GPT-6.2 Sol, GPT-6.2 Astra, and Muse Ember on Google Vertex. Fable starts pinned.

## Badge rules

In **Settings → Badge Rules**, click **+** to add a rule, then pick a color. A condition compares a watched row's TPS or 24-hour uptime with a fixed value or a multiple of another watched row's same metric. For example, set **Show the badge when** to **Any condition is true** to show blue when Fable exceeds 20 TPS or runs at more than twice Opus's speed.

Each condition shows its current reading and whether it's true right now, and each rule shows whether it's matching and visible in the menu bar. The menu bar shows the first three enabled rules that match. Drag rules in the sidebar to change their priority, or right-click to enable, duplicate, move, or delete one. Removing a watched row clears any conditions that referenced it.

## OpenRouter data

TokenSpeed refreshes once a minute. Median TPS comes from the public feed used by [OpenRouter's provider pages](https://openrouter.ai/openai/gpt-6.2-sol/providers). Rules use the displayed readings, which can have different windows. The provider-page feed is a frontend API, so its schema may change.

OpenRouter only publishes daily throughput history, so TokenSpeed records every watched model's endpoints itself, once every 5 minutes, and keeps 24 hours in `~/Library/Application Support/TokenSpeed/throughput-history.json`. Sparklines fill in over time after you install or add a model, and gaps longer than 15 minutes (sleep, app not running) break the line.

24-hour uptime comes from the [OpenRouter Endpoints API](https://openrouter.ai/docs/api/api-reference/endpoints/list-all-endpoints-for-a-model). Missing values appear as a dash. When both live feeds fail for a model, its previous readings stay visible, dimmed and marked stale, and are excluded from badge rules until refreshed.

No OpenRouter API key is needed. TokenSpeed stores the watchlist, ordering, pinned row, and rules locally.
