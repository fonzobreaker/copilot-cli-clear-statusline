# copilot-cli-clear-statusline

A compact, information-dense **custom status line for [GitHub Copilot CLI](https://docs.github.com/copilot/how-tos/set-up/install-copilot-cli)** on Windows.

It reads the JSON payload that Copilot CLI pipes to your status line command on every refresh and renders two lines with:

- 👨🏻‍💻 **GitHub username** — from the Copilot payload when available, otherwise from the active account in `~/.copilot/config.json` (`lastLoggedInUser.login`), re-read on every refresh so `/user switch` is reflected without waiting for the quota cache,
- 🤖 the **model** currently in use,
- 🧠 the **context window** fill percentage with a progress bar,
- 🪙 **plan-wide AI credits** used vs total (with color-coded warning thresholds),
- 💻 **session AI credits** consumed by the current session,
- ➕➖ **lines added / removed** during the session,
- 🆔 **session id**,
- ⏱️ **session duration**.

![platform](https://img.shields.io/badge/platform-Windows-blue)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![License MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

```text
👨🏻‍💻 username · 🆔 3d3b390 · 💻 2369 AIC · +2211 -333 · ⏱️ 18:57:42

🤖 Opus 4.7 · 🧠 ██░░░░░░░░ 16% · 🪙 ████░░░░░░ 37% (2618/7000)
```

An optional third line at the top is a passthrough of your [Starship](https://starship.rs) prompt, if `starship` is available on `PATH`.

---

## Requirements

- **Windows 10 / 11**
- **PowerShell 5.1+** (bundled with Windows) — works in FullLanguage and ConstrainedLanguage modes.
- **[GitHub Copilot CLI](https://docs.github.com/copilot/how-tos/set-up/install-copilot-cli)** 1.0.44 or newer.
- **Node.js** *(optional)* — required only if you want to auto-fetch the plan total from the GitHub Copilot user API. Without it, the script uses local fallbacks.
- **[Starship](https://starship.rs)** *(optional)* — enables the top prompt line.

---

## Installation

### 1. Copy the files

Copy the four runtime files into `~/.copilot/`:

```powershell
$src = "$HOME\Downloads\copilot-cli-clear-statusline"   # or wherever you cloned it
Copy-Item "$src\statusline.ps1"          "$HOME\.copilot\statusline.ps1" -Force
Copy-Item "$src\statusline.cmd"          "$HOME\.copilot\statusline.cmd" -Force
Copy-Item "$src\plan-quota.js"           "$HOME\.copilot\plan-quota.js"  -Force
Copy-Item "$src\statusline-config.json"  "$HOME\.copilot\statusline-config.json" -Force
```

### 2. Enable the status line in `~/.copilot/settings.json`

Add or merge these three keys (adjust the path to your user profile):

```jsonc
{
  "experimental": true,
  "statusLine": {
    "type": "command",
    "command": "C:\\Users\\<YOU>\\.copilot\\statusline.cmd",
    "padding": 1
  },
  "feature_flags": {
    "enabled": ["STATUS_LINE"]
  }
}
```

> ⚠️ On Windows all three keys are **required**. Missing any of them produces a blank status line with no error. Use an absolute path and escape backslashes in JSON.

### 3. Restart Copilot CLI

Close every open Copilot CLI session and start a new one. The status line appears immediately.

---

## ARS - Always Render Something

This status line is built around this one principle: **always render something**.

- Every external dependency is treated as optional. Input parsing, plan-quota retrieval, git inspection, and every individual segment fail independently and degrade gracefully. When live data isn't available, cached values or local approximations are used where possible; otherwise only the affected segment is omitted.

- Errors and warnings are suppressed, so failures never leak to the terminal or interrupt your workflow.
---

## Features

- 🤖 **Model** — a regex-formatted name derived from `model.id` (for example, `Claude Opus 4.7`, `GPT-5.4`, or `Gemini 3.1 Pro`). Unrecognized IDs are displayed unchanged.
- 🧠 **Context window** — 10-cell progress bar plus percentage, driven by `context_window.used_percentage`.
- 🪙 **Plan AI credits** — used vs total with color thresholds: gold → amber at 60% → brick red at 80%.
- 💻 **Session AI credits** — AIC consumed by the current session, read from `ai_used`.
- ➕➖ **Lines changed** — from `cost.total_lines_added` and `cost.total_lines_removed`.
- 👨🏻‍💻 **GitHub username** — read in this order: Copilot payload `username`, active account `lastLoggedInUser.login` in `~/.copilot/config.json`, cached GitHub token login, then `GH_USERNAME` / `GITHUB_ACTOR`. If none is available, only this segment is hidden. The active account is read on every refresh, so `/user switch` does not wait for the quota cache. The coin segment still uses the account associated with the configured quota API token, which can differ from the selected Copilot account.
- 🆔 **Session id** — short 7-char id.
- ⏱️ **Session duration** — `HH:MM:SS` from `cost.total_duration_ms`.
- Color palette with truecolor ANSI SGR escapes.
- Works under **PowerShell 5.1 in ConstrainedLanguage mode** (locked-down corporate laptops).
- **ASCII-only source**: every Unicode glyph is built from its codepoint via `[char]` casts, so editor encoding changes cannot corrupt the render.
- Optional Starship passthrough for the top line — get git branch, sync state, language versions, and everything else Starship already renders well.

---

## Files

| File | Purpose |
|------|---------|
| `statusline.ps1`        | Main script. Reads stdin JSON and renders both lines. |
| `statusline.cmd`        | Windows wrapper. Forces UTF-8 (`chcp 65001`) then invokes PowerShell. **Required** — pointing Copilot CLI directly at `powershell.exe` breaks stdin encoding in 1.0.44+. |
| `plan-quota.js`         | Node.js helper. Fetches the plan quota from the GitHub Copilot user API and caches it. |
| `statusline-config.json`| Optional fallback config (`planCredits`). |

Files written at runtime (all safe to delete):

- `~/.copilot/statusline-last.json` — last stdin payload, handy for debugging.
- `~/.copilot/plan-quota-cache.json` — cached API response (6 h TTL).
- `~/.copilot/plan-usage-cache.json` — cached local DB aggregation (60 s TTL).

---

## Configuration

### Reordering, hiding, and enabling segments

Open `statusline.ps1` and jump to the **RENDER PIPELINE** section at the bottom. Two lists control the whole layout:

```powershell
# ---- Line A: username · session id · session AIC · lines changed · duration ----
$topSegments = @()
$topSegments += (Invoke-Segment { Get-UsernameSegment       $status })   # 👨🏻‍💻 authenticated username
$topSegments += (Invoke-Segment { Get-SessionSegment        $status })   # 🆔 session id
$topSegments += (Invoke-Segment { Get-SessionCreditsSegment $status })   # 💻 session AIC used
$topSegments += (Invoke-Segment { Get-LinesSegment          $status })   # +added -removed lines
$topSegments += (Invoke-Segment { Get-DurationSegment       $status })   # ⏱️ session duration

# ---- Line B: model · context · plan credits ----
$bottomSegments = @()
$bottomSegments += (Invoke-Segment { Get-ModelSegment          $status })   # 🤖 model name
$bottomSegments += (Invoke-Segment { Get-ContextBarSegment     $status })   # 🧠 context progress bar
$bottomSegments += (Invoke-Segment { Get-CreditsSegment        $status })   # 🪙 plan AIC used / total
# $bottomSegments += (Invoke-Segment { Get-ContextTokensSegment $status })  # redundant tokens display
# $bottomSegments += (Invoke-Segment { Get-ReqsSegment          $status })  # premium requests (not in stdin)
# $bottomSegments += (Invoke-Segment { Get-GitBranchSegment     $status })  # git branch (usually via starship)
# $bottomSegments += (Invoke-Segment { Get-CwdSegment           $status })  # cwd (usually via starship)
```

- **Hide** a segment: prefix its line with `#`.
- **Show** a segment: remove the leading `#`.
- **Reorder**: move lines up or down.
- **Move between lines**: cut a line from one list, paste it into the other.

A segment that returns `$null` — because a required field is missing or the builder threw — is automatically skipped by `Invoke-Segment`.

### Palette

The **PALETTE** section defines twelve named colors as truecolor ANSI escapes. Edit any RGB triplet to reskin the status line. Notable ones:

| Variable | Default | Where it is used |
|----------|---------|------------------|
| `$cCool`     | `#7dcfff` | context bar when usage is low |
| `$cWarn`     | `#e0af68` | context bar warning at 40%+ |
| `$cCritical` | `#f7768e` | context bar critical at 70%+ |
| `$cGold`     | `#f5c542` | credits bar under 60% |
| `$cGoldWarn` | `#ea9a23` | credits bar amber at 60%+ |
| `$cGoldCrit` | `#d95b3c` | credits bar brick red at 80%+ |
| `$cGreen`    | `#9ece6a` | added lines |
| `$cBlue`     | `#7aa2f7` | current directory |

### Thresholds

Two helpers pick the color based on percentage:

- `Threshold-Style $Pct 40 70` — cool / warn / critical for the context bar.
- `Threshold-Gold  $Pct 60 80` — gold / amber / brick red for plan credits.

Change the two numbers in the `Get-*Segment` bodies to move the thresholds.

### Icons and emojis

The **GLYPHS** section defines every icon via its Unicode codepoint, for example:

```powershell
$gBrain  = ([string][char]0xD83E) + ([string][char]0xDDE0) + ' '   # U+1F9E0 brain
```

Replace the `0x....` values with the codepoint of any other emoji to change the icon without touching the rest of the script. Emojis above `U+FFFF` require the two surrogate halves.

---

## The `🪙` plan credits segment

Copilot CLI does not send the plan's monthly AIC quota in its status line payload, so we have to source it out of band. The script resolves it in this order:

**Used amount:**

1. `plan-quota-cache.json` — populated by `plan-quota.js` from the GitHub Copilot user API (authoritative).
2. Local aggregation: `SUM(total_nano_aiu)` from `~/.copilot/session-store.db` for the current calendar month (approximation — only counts events recorded on this machine).

**Total amount:**

1. `plan-quota-cache.json` (authoritative).
2. Environment variable `COPILOT_PLAN_CREDITS`.
3. `planCredits` key in `~/.copilot/statusline-config.json`.

If neither used nor total can be resolved, the whole segment is hidden.

### (Optional) auto-detect your plan total via GitHub API

The bundled `plan-quota.js` calls `GET https://api.github.com/copilot_internal/user` and caches `quota_snapshots.premium_interactions.entitlementRequests` (plan total AIC) plus `usedRequests` (month-to-date usage). Cache TTL is 6 hours; refreshes are fired in the background so they never block the render.

1. Create a [personal access token (classic)](https://github.com/settings/tokens) with **only** the `copilot` scope.
2. Save it as an environment variable. The helper checks these names in order: `GH_TOKEN`, `GITHUB_TOKEN`, `COPILOT_TOKEN`, `GITHUB_COPILOT_TOKEN`.

   ```powershell
   # persistent (user-level)
   setx GH_TOKEN "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
   # or just this shell
   $env:GH_TOKEN = "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
   ```

3. Restart your terminal, then force-refresh the cache once:

   ```powershell
   node "$HOME\.copilot\plan-quota.js"
   Get-Content "$HOME\.copilot\plan-quota-cache.json"
   ```

   Expected output: `{"ts":..., "total":7000, "used":1750}` (numbers are yours).

Without a token the segment still works via the local DB aggregation, which is usually within a few percent of the real figure.

Reference AIC/month by plan (for the manual fallback):

| Plan       | AIC / month |
|------------|-------------|
| Free       | 0           |
| Pro        | 300         |
| Pro+       | 1500        |
| Business   | 300         |
| Enterprise | varies      |

---

## Troubleshooting

**Status line is completely blank.**
Check that `experimental: true`, the full `statusLine` block, and `feature_flags.enabled: ["STATUS_LINE"]` are all present in `~/.copilot/settings.json`. Missing any of them yields a silent no-op on Windows.

**Emojis or block glyphs render as `?` or mojibake.**
Your terminal is not on a UTF-8 code page, or your font lacks the glyphs. The provided `.cmd` wrapper forces `chcp 65001`; if you removed it, put it back. Install and use a Nerd Font.

**`Ignoring unknown top-level key(s) in user settings file …: "planCredits"`.**
That warning appears if you put `planCredits` directly inside `~/.copilot/settings.json`. Move it to `~/.copilot/statusline-config.json` — Copilot CLI validates its own settings and does not know that key.

**🪙 plan segment is hidden.**
No `used` value could be resolved. Either set `GH_TOKEN` so `plan-quota.js` can fetch the real value, or ensure `~/.copilot/session-store.db` exists **and** Python 3 is on `PATH` so the local aggregation fallback can run.

**Plan `used` doesn't match the default Copilot HUD.**
Without `GH_TOKEN` the fallback aggregates local usage events for the current calendar month. GitHub's own billing may use a different cycle start day, and any usage from other machines is missing locally. Configure `GH_TOKEN` for exact values.

**`Cannot invoke method. Method invocation is supported only on core types in this language mode.`**
Your PowerShell is in ConstrainedLanguage mode (WDAC / AppLocker). The script is already written to work under it, but any customization you add should stick to cmdlets and avoid `[Type]::Method` calls, `Add-Type`, and `New-Object` on non-core types.

**Something else went wrong.**
Look at `~/.copilot/statusline-last.json` (the last stdin payload). Every render overwrites it, so it always reflects the state that caused the current output.

---

## Credits

- **[stephenleo/cship](https://github.com/stephenleo/cship)** — the original Rust status line for Claude Code that inspired the visual language and overall setup.
- **[avatorl/copilot-cli-statusline](https://github.com/avatorl/copilot-cli-statusline)** — reference reliability model and its assumption to test the solutions against that principles.
- **[pascalvanderheiden](https://github.com/pascalvanderheiden)** — early Windows Copilot CLI status line port that documented the `feature_flags` + `.cmd` wrapper requirements.
- **[Tokyo Night](https://github.com/enkia/tokyo-night-vscode-theme)** — color palette.

---

## License

MIT — see [`LICENSE`](./LICENSE). Contributions welcome!
