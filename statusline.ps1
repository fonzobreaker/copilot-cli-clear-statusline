# =============================================================================
#  cship-for-copilot-cli - Tokyo Night statusline for GitHub Copilot CLI
# -----------------------------------------------------------------------------
#  Port of https://github.com/stephenleo/cship (originally for Claude Code)
#  to GitHub Copilot CLI. Renders a two-line statusline:
#    line 1 - optional Starship prompt (if `starship` is on PATH)
#    line 2 - custom segments: model, context bar, plan credits, session AIC,
#             lines changed, git branch, cwd, session id, session duration.
#
#  ┌─────────────────────────────────────────────────────────────────────────┐
#  │  HOW TO CUSTOMIZE                                                       │
#  │  --------------------------------------------------------------------   │
#  │  • Reorder / hide segments: edit the "RENDER PIPELINE" section          │
#  │    at the bottom of this file. Comment a line with `#` to hide it,      │
#  │    move lines up/down to reorder.                                       │
#  │  • Change colors: edit the "Tokyo Night palette" section below.         │
#  │  • Change thresholds (context / credits warning colors):                │
#  │    look for `Threshold-Style` / `Threshold-Gold` calls.                 │
#  │  • Change icons / emojis: edit the "Glyphs" section below.              │
#  │  • Change plan total: set env var COPILOT_PLAN_CREDITS or edit          │
#  │    ~/.copilot/statusline-config.json ("planCredits" key).               │
#  └─────────────────────────────────────────────────────────────────────────┘
#
#  Compatibility: Windows PowerShell 5.1 in ConstrainedLanguage mode.
#  All Unicode glyphs are built via [char] casts so the file stays ASCII-safe.
# =============================================================================

# -----------------------------------------------------------------------------
# 0) RELIABILITY - silence non-terminating errors and warnings so nothing leaks
#    to stderr. A statusline must NEVER break the parent terminal.
# -----------------------------------------------------------------------------
$ErrorActionPreference   = 'SilentlyContinue'
$WarningPreference       = 'SilentlyContinue'
$ProgressPreference      = 'SilentlyContinue'
$InformationPreference   = 'SilentlyContinue'
$VerbosePreference       = 'SilentlyContinue'
$DebugPreference         = 'SilentlyContinue'

# -----------------------------------------------------------------------------
# 1) INPUT - read the JSON status payload from stdin
#    Copilot CLI pipes its status object here on every render.
#    $input is ConstrainedLanguage-safe (no [Console]::In needed).
#    Everything is wrapped: if the payload is missing, malformed, or not JSON
#    at all, $status stays $null and the script still renders whatever it can.
# -----------------------------------------------------------------------------
$statusJson = ''
$status     = $null
try {
    $statusJson = $input | Out-String
} catch { $statusJson = '' }

if (-not [string]::IsNullOrWhiteSpace($statusJson)) {
    try { $status = $statusJson | ConvertFrom-Json -ErrorAction Stop } catch { $status = $null }
}

# -----------------------------------------------------------------------------
# 2) DEBUG - dump last stdin to ~/.copilot/statusline-last.json (best-effort).
#    Comment this block out to disable the on-disk dump.
# -----------------------------------------------------------------------------
try {
    $dbgDir = Join-Path $env:USERPROFILE '.copilot'
    if (Test-Path $dbgDir) {
        $dbgFile = Join-Path $dbgDir 'statusline-last.json'
        Set-Content -Path $dbgFile -Value $statusJson -Encoding UTF8 -ErrorAction SilentlyContinue
    }
} catch { }

# -----------------------------------------------------------------------------
# 3) PALETTE - Tokyo Night, truecolor ANSI SGR escapes.
#    Change any hex value here to reskin the statusline.
# -----------------------------------------------------------------------------
$esc   = [string][char]27
$reset = "$esc[0m"
$bold  = "$esc[1m"
$dim   = "$esc[2m"

$cBase     = "$esc[38;2;169;177;214m"  # #a9b1d6  neutral text
$cCool     = "$esc[38;2;125;207;255m"  # #7dcfff  cool / OK
$cWarn     = "$esc[38;2;224;175;104m"  # #e0af68  warn (yellow)
$cCritical = "$esc[38;2;247;118;142m"  # #f7768e  critical (red/pink)
$cAccent   = "$esc[38;2;187;154;247m"  # #bb9af7  magenta accent
$cGreen    = "$esc[38;2;158;206;106m"  # #9ece6a  added lines
$cBlue     = "$esc[38;2;122;162;247m"  # #7aa2f7  cwd
$cMuted    = "$esc[38;2;86;95;137m"    # #565f89  session
$cGold     = "$esc[38;2;245;197;66m"   # #f5c542  credits (base)
$cGoldWarn = "$esc[38;2;234;154;35m"   # #ea9a23  credits amber (60%+)
$cGoldCrit = "$esc[38;2;217;91;60m"    # #d95b3c  credits brick red (80%+)

# -----------------------------------------------------------------------------
# 4) GLYPHS - built from Unicode codepoints so the source file stays ASCII
#    and cannot be corrupted by editor encoding changes.
#    To swap icons, replace the codepoint after 0x.
# -----------------------------------------------------------------------------
$midDot  = [string][char]0x00B7   # middle dot separator
$gFull   = [string][char]0x2588   # FULL BLOCK  - progress fill
$gLight  = [string][char]0x2591   # LIGHT SHADE - progress empty
# Emojis > U+FFFF use UTF-16 surrogate pairs.
$gBrain  = ([string][char]0xD83E) + ([string][char]0xDDE0) + ' '   # U+1F9E0 brain
$gRobot  = ([string][char]0xD83E) + ([string][char]0xDD16) + ' '   # U+1F916 robot
$gId     = ([string][char]0xD83C) + ([string][char]0xDD94) + ' '   # U+1F194 ID button
$gCoin   = ([string][char]0xD83E) + ([string][char]0xDE99) + ' '   # U+1FA99 coin
$gLaptop = ([string][char]0xD83D) + ([string][char]0xDCBB) + ' '   # U+1F4BB laptop
$gClock  = ([string][char]0x23F1) + ([string][char]0xFE0F) + ' '   # U+23F1 stopwatch

$separator = "$dim $midDot $reset"

# -----------------------------------------------------------------------------
# 5) HELPERS
# -----------------------------------------------------------------------------
function Format-Tokens {
    # Compact number formatting: 1234 -> "1k", 1500000 -> "1.5M"
    param($N)
    $x = 0.0 + $N
    if ($x -ge 1000000) { return ('{0:0.#}M' -f ($x / 1000000)) }
    if ($x -ge 1000)    { return ('{0:0}k'   -f ($x / 1000)) }
    return ([string][int]$x)
}

function Threshold-Style {
    # Context progress color: cool -> warn -> critical
    # Defaults: warn at 40%, critical at 70%.
    param($Pct, $Warn = 40.0, $Critical = 70.0)
    $p = 0.0 + $Pct
    if ($p -ge $Critical) { return ($bold + $cCritical) }
    if ($p -ge $Warn)     { return $cWarn }
    return $cCool
}

function Threshold-Gold {
    # Credits progress color: gold -> amber -> brick red
    # Defaults: warn at 60%, critical at 80% (matches HUD-ish behavior).
    param($Pct, $Warn = 60.0, $Critical = 80.0)
    $p = 0.0 + $Pct
    if ($p -ge $Critical) { return ($bold + $cGoldCrit) }
    if ($p -ge $Warn)     { return $cGoldWarn }
    return $cGold
}

function Invoke-Segment {
    # Executes a segment builder in isolation. Any exception, missing field,
    # or non-terminating error is swallowed and the segment is hidden ($null).
    # This is the only place segment failures can happen without breaking the
    # rest of the statusline.
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Builder
    )
    $out = $null
    try { $out = & $Builder } catch { $out = $null }
    if ($null -eq $out) { return $null }
    if ($out -is [string] -and [string]::IsNullOrWhiteSpace($out)) { return $null }
    return $out
}

# =============================================================================
#  6) MODULES - each function renders one segment (or returns $null to hide it)
# =============================================================================

# -----------------------------------------------------------------------------
# MODEL SEGMENT     ->  "🤖 Opus 4.7"
#   Reads the model id from stdin and normalizes it to a friendly display name.
# -----------------------------------------------------------------------------
function Get-ModelSegment {
    param($s)
    if ($null -eq $s) { return $null }
    # Field precedence follows blog.madkoo.net's schema:
    # currentModel > cost.model > model.display_name > model.id
    $raw = $null
    if ($null -ne $s.currentModel) { $raw = "$($s.currentModel)" }
    if ([string]::IsNullOrWhiteSpace($raw) -and $null -ne $s.cost -and $null -ne $s.cost.model) { $raw = "$($s.cost.model)" }
    if ([string]::IsNullOrWhiteSpace($raw) -and $null -ne $s.model) {
        if ($s.model -is [string]) { $raw = $s.model }
        else {
            if ($null -ne $s.model.display_name) { $raw = "$($s.model.display_name)" }
            elseif ($null -ne $s.model.displayName) { $raw = "$($s.model.displayName)" }
            elseif ($null -ne $s.model.name) { $raw = "$($s.model.name)" }
            elseif ($null -ne $s.model.id) { $raw = "$($s.model.id)" }
        }
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    # Strip Copilot decorations before matching the stable model id.
    $id = $raw.ToLower() -replace '\s*[\u00B7\|].*$', '' -replace '\s*\(.*$', '' -replace '[\s_]+', '-' -replace '[^a-z0-9.+-]', '' -replace '-+', '-'
    $id = $id.Trim('-')

    # Convert hyphen-separated words without maintaining a version-by-version map.
    function ConvertTo-ModelWords {
        param(
            [string]$Value,
            [string]$Separator = ' '
        )
        $words = @()
        foreach ($word in ($Value -split '-')) {
            if ([string]::IsNullOrWhiteSpace($word)) { continue }
            if ($word -match '^\d+(?:\.\d+)*$') {
                $words += $word
            }
            else {
                $words += ($word.Substring(0, 1).ToUpper() + $word.Substring(1).ToLower())
            }
        }
        return ($words -join $Separator)
    }

    # Decode provider ID conventions. Unknown IDs intentionally remain untouched.
    $display = $null
    if ($id -match '^gpt-(?<version>\d+(?:\.\d+)*)(?<suffix>(?:-[a-z0-9]+)*)$') {
        $display = "GPT-$($Matches.version)"
        $suffix = $Matches.suffix.Trim('-')
        if (-not [string]::IsNullOrWhiteSpace($suffix)) {
            $display += "-$(ConvertTo-ModelWords $suffix '-')"
        }
    }
    elseif ($id -match '^claude-(?<family>[a-z0-9]+(?:-[a-z0-9]+)*)-(?<version>\d+(?:\.\d+)*)$') {
        $display = "Claude $(ConvertTo-ModelWords $Matches.family) $($Matches.version)"
    }
    elseif ($id -match '^(?<provider>gemini|grok)-(?<name>[a-z0-9.]+(?:-[a-z0-9.]+)*)$') {
        $display = "$(ConvertTo-ModelWords $Matches.provider) $(ConvertTo-ModelWords $Matches.name)"
    }
    if ([string]::IsNullOrWhiteSpace($display)) { $display = $raw }
    return "$gRobot$bold$cCool$display$reset"
}

# -----------------------------------------------------------------------------
# CONTEXT BAR SEGMENT   ->  "🧠 ███░░░░░░░ 30%"
#   Progress bar of the current context window usage (from context_window.used_percentage).
# -----------------------------------------------------------------------------
function Get-ContextBarSegment {
    param($s)
    if ($null -eq $s -or $null -eq $s.context_window) { return $null }
    $ctx = $s.context_window
    # Use the "displayed" percentage (current_context_used_percentage) that matches
    # the value Copilot CLI shows next to the model. Fall back to computing it from
    # current_context_tokens / displayed_context_limit, and only as a last resort to
    # used_percentage (which is expressed against the full model window and stays low).
    $pct = $null
    foreach ($n in @('current_context_used_percentage','currentContextUsedPercentage')) {
        if ($null -ne $ctx.PSObject.Properties[$n]) { $pct = $ctx.PSObject.Properties[$n].Value; if ($null -ne $pct) { break } }
    }
    if ($null -eq $pct) {
        $used = $null; $size = $null
        foreach ($n in @('current_context_tokens','currentContextTokens')) {
            if ($null -ne $ctx.PSObject.Properties[$n]) { $used = $ctx.PSObject.Properties[$n].Value; if ($null -ne $used) { break } }
        }
        foreach ($n in @('displayed_context_limit','displayedContextLimit')) {
            if ($null -ne $ctx.PSObject.Properties[$n]) { $size = $ctx.PSObject.Properties[$n].Value; if ($null -ne $size) { break } }
        }
        if ($null -ne $used -and $null -ne $size -and (0.0 + $size) -gt 0) {
            $pct = (0.0 + $used) / (0.0 + $size) * 100.0
        }
    }
    if ($null -eq $pct) { $pct = $ctx.used_percentage }
    if ($null -eq $pct) { return $null }
    $pctNum = 0.0 + $pct
    $width = 10
    $filled = [int]($pctNum * $width / 100.0 + 0.5)
    if ($filled -lt 0) { $filled = 0 }
    if ($filled -gt $width) { $filled = $width }
    $bar = ($gFull * $filled) + ($gLight * ($width - $filled))
    $style = Threshold-Style $pctNum 40.0 70.0
    return "$gBrain$style$bar $([int]$pctNum)%$reset"
}

# -----------------------------------------------------------------------------
# CONTEXT TOKENS SEGMENT   ->  "16%(148k/264k)"
#   Redundant with the context bar (shows the same %). Disabled by default in
#   the render pipeline. Kept here in case you want to re-enable it.
# -----------------------------------------------------------------------------
function Get-ContextTokensSegment {
    param($s)
    if ($null -eq $s -or $null -eq $s.context_window) { return $null }
    $ctx = $s.context_window
    # Real Copilot CLI fields (from blog.madkoo.net): current_context_tokens + displayed_context_limit
    $used = $null
    foreach ($n in @('current_context_tokens','currentContextTokens','last_call_input_tokens','used_tokens')) {
        if ($null -ne $ctx.PSObject.Properties[$n]) { $used = $ctx.PSObject.Properties[$n].Value; if ($null -ne $used) { break } }
    }
    $size = $null
    foreach ($n in @('displayed_context_limit','displayedContextLimit','context_window_size','limit')) {
        if ($null -ne $ctx.PSObject.Properties[$n]) { $size = $ctx.PSObject.Properties[$n].Value; if ($null -ne $size) { break } }
    }
    $pct = $null
    foreach ($n in @('used_percentage','usedPercentage')) {
        if ($null -ne $ctx.PSObject.Properties[$n]) { $pct = $ctx.PSObject.Properties[$n].Value; if ($null -ne $pct) { break } }
    }
    if ($null -eq $size -or $null -eq $used) { return $null }
    if ($null -ne $pct) { $pctNum = 0.0 + $pct } else { $pctNum = (0.0 + $used) / (0.0 + $size) * 100.0 }
    $style = Threshold-Style $pctNum 40.0 70.0
    $usedStr = Format-Tokens $used
    $sizeStr = Format-Tokens $size
    return "$style$([int]$pctNum)%($usedStr/$sizeStr)$reset"
}

# -----------------------------------------------------------------------------
# LINES SEGMENT   ->  "+1550 -96"
#   Total lines added / removed across the session (from cost.total_lines_*).
# -----------------------------------------------------------------------------
function Get-LinesSegment {
    param($s)
    if ($null -eq $s -or $null -eq $s.cost) { return $null }
    $added = $s.cost.total_lines_added
    $removed = $s.cost.total_lines_removed
    if ($null -eq $added) { $added = 0 }
    if ($null -eq $removed) { $removed = 0 }
    if ([int]$added -eq 0 -and [int]$removed -eq 0) { return $null }
    return "$cGreen+$added$reset $cCritical-$removed$reset"
}

# -----------------------------------------------------------------------------
# PLAN CREDITS SEGMENT   ->  "🪙 ██████░░░░ 27% (1904/7000)"
#   Plan-wide AI credits used vs total.
#   USED value source (in order):
#     1) plan-quota-cache.json (6h TTL, populated by plan-quota.js -> GitHub API)
#     2) SUM(total_nano_aiu) from ~/.copilot/session-store.db for current month
#        (local approximation when no GH_TOKEN is available)
#   TOTAL value source (in order):
#     1) plan-quota-cache.json (authoritative, from API)
#     2) env var COPILOT_PLAN_CREDITS
#     3) "planCredits" key in ~/.copilot/statusline-config.json
#   Color thresholds: gold -> amber (60%+) -> brick red (80%+).
# -----------------------------------------------------------------------------
function Get-CreditsSegment {
    param($s)

    $total = $null
    $used  = $null
    $cachePath  = Join-Path $env:USERPROFILE '.copilot\plan-quota-cache.json'
    $helperPath = Join-Path $env:USERPROFILE '.copilot\plan-quota.js'
    $cacheFresh = $false
    if (Test-Path $cachePath) {
        try {
            $cache = Get-Content -Raw $cachePath | ConvertFrom-Json
            if ($null -ne $cache.total -and $cache.total -gt 0) {
                $nowMs = [double](Get-Date -UFormat %s) * 1000.0
                $ageMs = $nowMs - [double]$cache.ts
                $total = [double]$cache.total
                if ($null -ne $cache.used) { $used = [double]$cache.used }
                if ($ageMs -lt (6 * 3600 * 1000)) { $cacheFresh = $true }
            }
        } catch { }
    }
    if (-not $cacheFresh -and (Test-Path $helperPath)) {
        try {
            Start-Process -WindowStyle Hidden -FilePath 'node' -ArgumentList @($helperPath) -ErrorAction SilentlyContinue | Out-Null
        } catch { }
    }
    if ($null -eq $total -and -not [string]::IsNullOrWhiteSpace($env:COPILOT_PLAN_CREDITS)) {
        try { $total = [double]$env:COPILOT_PLAN_CREDITS } catch { $total = $null }
    }
    if ($null -eq $total) {
        $cfgPath = Join-Path $env:USERPROFILE '.copilot\statusline-config.json'
        if (Test-Path $cfgPath) {
            try {
                $cfg = Get-Content -Raw $cfgPath | ConvertFrom-Json
                if ($null -ne $cfg.planCredits) { $total = [double]$cfg.planCredits }
            } catch { }
        }
    }

    # Fallback for "used" when API cache is unavailable: aggregate total_nano_aiu
    # from Copilot CLI's session-store.db (all sessions on this machine).
    # This reflects plan-wide usage recorded locally (approximation of month-to-date).
    if ($null -eq $used) {
        $dbPath = Join-Path $env:USERPROFILE '.copilot\session-store.db'
        if ((Test-Path $dbPath) -and (Get-Command python -ErrorAction SilentlyContinue)) {
            $usageCache = Join-Path $env:USERPROFILE '.copilot\plan-usage-cache.json'
            $needRun = $true
            if (Test-Path $usageCache) {
                try {
                    $uc = Get-Content -Raw $usageCache | ConvertFrom-Json
                    $ageSec = ((Get-Date) - (Get-Item $usageCache).LastWriteTime).TotalSeconds
                    if ($ageSec -lt 60 -and $null -ne $uc.used) {
                        $used = [double]$uc.used
                        $needRun = $false
                    }
                } catch { }
            }
            if ($needRun) {
                try {
                    $monthPrefix = (Get-Date -Format 'yyyy-MM')
                    $q = "SELECT COALESCE(SUM(total_nano_aiu),0) FROM assistant_usage_events WHERE created_at >= '" + $monthPrefix + "-01'"
                    $py = "import sqlite3,json,sys" + [char]10 +
                          "try:" + [char]10 +
                          " c=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True)" + [char]10 +
                          " n=c.execute(sys.argv[2]).fetchone()[0]" + [char]10 +
                          " print(json.dumps({'used':n/1e9}))" + [char]10 +
                          "except Exception as e: print(json.dumps({'used':0}))"
                    $out = & python -c $py $dbPath $q 2>$null
                    if ($out) {
                        $j = $out | ConvertFrom-Json
                        if ($null -ne $j.used -and $j.used -gt 0) {
                            $used = [double]$j.used
                            try { $out | Set-Content -Path $usageCache -Encoding utf8 } catch { }
                        }
                    }
                } catch { }
            }
        }
    }

    if ($null -eq $used -or $null -eq $total -or $total -le 0) { return $null }

    $usedNum = 0.0 + $used
    $usedStr = ('{0:0}' -f $usedNum)

    if ($null -eq $total -or $total -le 0) {
        # No total known -> just show used amount, gold color
        return "$gCoin$cGold$usedStr$reset"
    }

    $pctNum = $usedNum / $total * 100.0
    if ($pctNum -lt 0) { $pctNum = 0 }
    if ($pctNum -gt 999) { $pctNum = 999 }
    $barPct = $pctNum
    if ($barPct -gt 100) { $barPct = 100 }
    $width = 10
    $filled = [int]($barPct * $width / 100.0 + 0.5)
    if ($filled -lt 0) { $filled = 0 }
    if ($filled -gt $width) { $filled = $width }
    $bar = ($gFull * $filled) + ($gLight * ($width - $filled))
    $style = Threshold-Gold $pctNum 60.0 80.0

    $totNum = 0.0 + $total
    $usedFmt = ('{0:0}' -f $usedNum)
    $totFmt  = ('{0:0}' -f $totNum)
    return "$gCoin$style$bar $([int]$pctNum)% ($usedFmt/$totFmt)$reset"
}

# -----------------------------------------------------------------------------
# REQUESTS SEGMENT   ->  "reqs 42"
#   Premium requests count. Copilot CLI's stdin does not currently expose this,
#   so this segment is usually hidden.
# -----------------------------------------------------------------------------
function Get-ReqsSegment {
    param($s)
    if ($null -eq $s) { return $null }
    $v = $null
    if ($null -ne $s.usage) {
        if ($null -ne $s.usage.premium_requests) { $v = $s.usage.premium_requests }
        elseif ($null -ne $s.usage.requests)     { $v = $s.usage.requests }
    }
    if ($null -eq $v -and $null -ne $s.cost -and $null -ne $s.cost.premium_requests) {
        $v = $s.cost.premium_requests
    }
    if ($null -eq $v) { return $null }
    return "$cAccent" + "reqs $v$reset"
}

# -----------------------------------------------------------------------------
# CWD SEGMENT   ->  "~\projects\myrepo" or "...\a\b\c"
#   Current working directory, with $HOME collapsed to ~ and long paths truncated.
#   Hidden when we are exactly at $HOME (would just print "~").
# -----------------------------------------------------------------------------
function Get-CwdSegment {
    param($s)
    $cwd = $null
    if ($null -ne $s) { $cwd = $s.cwd }
    if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = (Get-Location).Path }
    $userHome = $env:USERPROFILE
    if (-not [string]::IsNullOrWhiteSpace($userHome)) {
        $lc = $cwd.ToLower()
        $lh = $userHome.ToLower()
        if ($lc.StartsWith($lh)) { $cwd = '~' + $cwd.Substring($userHome.Length) }
    }
    $parts = @($cwd -split '[\\/]' | Where-Object { $_ -ne '' })
    if ($parts.Count -eq 0) { return $null }
    if ($parts.Count -eq 1 -and $parts[0] -eq '~') { return $null }
    if ($parts.Count -gt 3) {
        $tail = $parts[($parts.Count - 3)..($parts.Count - 1)] -join '\'
        $cwd = "...\$tail"
    }
    return "$cBlue$cwd$reset"
}

# -----------------------------------------------------------------------------
# GIT BRANCH SEGMENT   ->  "main"
#   Current git branch (or short SHA if in detached HEAD). Requires `git` on PATH.
# -----------------------------------------------------------------------------
function Get-GitBranchSegment {
    param($s)
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $cwd = $null
    if ($null -ne $s) { $cwd = $s.cwd }
    if ([string]::IsNullOrWhiteSpace($cwd) -or -not (Test-Path $cwd)) { $cwd = (Get-Location).Path }
    $prev = (Get-Location).Path
    $branch = $null
    try {
        Set-Location -LiteralPath $cwd -ErrorAction Stop
        $branch = (& git symbolic-ref --quiet --short HEAD 2>$null)
        if ([string]::IsNullOrWhiteSpace($branch)) {
            $branch = (& git rev-parse --short HEAD 2>$null)
        }
    } catch { $branch = $null } finally {
        try { Set-Location -LiteralPath $prev } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($branch)) { return $null }
    $b = "$branch".Trim()
    return "$cWarn$b$reset"
}

# -----------------------------------------------------------------------------
# SESSION SEGMENT   ->  "🆔 3d3b390"
#   First 7 hex chars of the Copilot CLI session_id (dashes stripped).
# -----------------------------------------------------------------------------
function Get-SessionSegment {
    param($s)
    if ($null -eq $s) { return $null }
    $sid = $s.session_id
    if ([string]::IsNullOrWhiteSpace($sid)) { return $null }
    $short = "$sid" -replace '-', ''
    if ($short.Length -gt 7) { $short = $short.Substring(0, 7) }
    return "$gId$cMuted$short$reset"
}

# -----------------------------------------------------------------------------
# SESSION CREDITS SEGMENT   ->  "💻 1602 AIC"
#   AI credits consumed by the current session (from ai_used).
#   Uses the default text color (no accent) so it's clearly distinct from the
#   plan-wide 🪙 segment above.
# -----------------------------------------------------------------------------
function Get-SessionCreditsSegment {
    param($s)
    if ($null -eq $s -or $null -eq $s.ai_used) { return $null }
    $used = $null
    if ($null -ne $s.ai_used.formatted) {
        try { $used = [double]$s.ai_used.formatted } catch { $used = $null }
    }
    if ($null -eq $used -and $null -ne $s.ai_used.total_nano_aiu) {
        try { $used = (0.0 + $s.ai_used.total_nano_aiu) / 1000000000.0 } catch { $used = $null }
    }
    if ($null -eq $used) { return $null }
    $txt = ('{0:0}' -f $used)
    return "$gLaptop$txt AIC$reset"
}

# -----------------------------------------------------------------------------
# DURATION SEGMENT   ->  "⏱️ 02:41:10"
#   Elapsed time of the current session (from cost.total_duration_ms), HH:MM:SS.
# -----------------------------------------------------------------------------
function Get-DurationSegment {
    param($s)
    $ms = $null
    if ($null -ne $s) {
        if ($null -ne $s.cost) {
            if ($null -ne $s.cost.total_duration_ms)      { $ms = $s.cost.total_duration_ms }
            elseif ($null -ne $s.cost.totalDurationMs)    { $ms = $s.cost.totalDurationMs }
        }
        if ($null -eq $ms) {
            if ($null -ne $s.total_duration_ms) { $ms = $s.total_duration_ms }
            elseif ($null -ne $s.totalDurationMs) { $ms = $s.totalDurationMs }
        }
    }
    if ($null -eq $ms) { $ms = 0 }
    $totalSec = [int]((0.0 + $ms) / 1000.0)
    if ($totalSec -lt 0) { $totalSec = 0 }
    $h = [int]($totalSec / 3600)
    $m = [int](($totalSec % 3600) / 60)
    $sec = $totalSec % 60
    $txt = '{0:D2}:{1:D2}:{2:D2}' -f $h, $m, $sec
    return "$dim$gClock$txt$reset"
}

# -----------------------------------------------------------------------------
# STARSHIP TOP LINE   ->  passthrough of `starship prompt` output
#   If starship (https://starship.rs) is on PATH, its rendered prompt becomes
#   the first line above our custom segments. Otherwise this line is skipped.
# -----------------------------------------------------------------------------
function Get-StarshipLine {
    param($s)
    if (-not (Get-Command starship -ErrorAction SilentlyContinue)) { return $null }
    $cwd = $null
    if ($null -ne $s) { $cwd = $s.cwd }
    if ([string]::IsNullOrWhiteSpace($cwd) -or -not (Test-Path $cwd)) { $cwd = (Get-Location).Path }
    $prev = (Get-Location).Path
    $out = $null
    try {
        Set-Location -LiteralPath $cwd -ErrorAction Stop
        $out = (& starship prompt 2>$null | Out-String).TrimEnd()
    } catch { $out = $null } finally {
        try { Set-Location -LiteralPath $prev } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($out)) { return $null }
    return $out
}

# =============================================================================
#  7) RENDER PIPELINE
# -----------------------------------------------------------------------------
#  Layout (three lines, top one optional):
#    line 0 (optional): starship prompt
#    line A (upper)   : 🆔 · 💻 · +/- lines · ⏱️
#    [ blank spacer line ]
#    line B (lower)   : 🤖 · 🧠 · 🪙
#
#  Move any `$xxx += (Get-...)` line between $topSegments / $bottomSegments
#  to change which line a segment appears on. Prefix a line with `#` to hide
#  the segment, or move lines up/down to reorder.
# =============================================================================

# Line 0: optional Starship prompt (hides itself if starship missing).
# Wrapped: if starship crashes or hangs its stdout, the whole line is dropped.
$line0 = Invoke-Segment { Get-StarshipLine $status }

# ---- Line A: session id · session AIC · lines changed · duration ----
$topSegments = @()
$topSegments += (Invoke-Segment { Get-SessionSegment        $status })   # 🆔 session id
$topSegments += (Invoke-Segment { Get-SessionCreditsSegment $status })   # 💻 session AIC used
$topSegments += (Invoke-Segment { Get-LinesSegment          $status })   # +added -removed lines
$topSegments += (Invoke-Segment { Get-DurationSegment       $status })   # ⏱️ session duration

# ---- Line B: model · context · plan credits ----
$bottomSegments = @()
$bottomSegments += (Invoke-Segment { Get-ModelSegment          $status })   # 🤖 model name
$bottomSegments += (Invoke-Segment { Get-ContextBarSegment     $status })   # 🧠 context progress bar
$bottomSegments += (Invoke-Segment { Get-CreditsSegment        $status })   # 🪙 plan AIC used / total
# $bottomSegments += (Invoke-Segment { Get-ContextTokensSegment $status })  # redundant tokens display, disabled
# $bottomSegments += (Invoke-Segment { Get-ReqsSegment          $status })  # premium requests
# $bottomSegments += (Invoke-Segment { Get-GitBranchSegment     $status })  # git branch (usually via starship)
# $bottomSegments += (Invoke-Segment { Get-CwdSegment           $status })  # cwd (usually via starship)

$topVisible    = @($topSegments    | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$bottomVisible = @($bottomSegments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$lineA = ($topVisible    -join $separator)
$lineB = ($bottomVisible -join $separator)

if (-not [string]::IsNullOrWhiteSpace($line0)) { Write-Output $line0 }
if (-not [string]::IsNullOrWhiteSpace($lineA)) {
    Write-Output $lineA
    Write-Output ''   # blank spacer between the two custom lines
}
Write-Output $lineB
