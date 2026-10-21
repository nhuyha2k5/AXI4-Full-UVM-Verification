<#
.SYNOPSIS
  Run the regression defined in scripts/dv_config.ps1 (QuestaSim 10.7c, UVM 1.2).
.EXAMPLE
  .\regress.ps1                     # everything, with coverage
  .\regress.ps1 -Tb ram,xbar        # only these testbenches
  .\regress.ps1 -Tb dma_wr -Filter '*random*' -NoCov
  .\regress.ps1 -SeedScale 3        # three times as many seeds per test
.NOTES
  Results: logs/<tb>/*.log (one per run), reports/regression_results.csv.
  Coverage databases: cov/ucdb/<tb>/*.ucdb; run scripts\cov_report.ps1 next.
  Exit code 0 only if every run passed.
#>
param(
    [string[]]$Tb = @(),
    [string]$Filter = '*',
    [switch]$NoCov,
    [switch]$NoBuild,
    [int]$Jobs = 4,
    [int]$SeedScale = 1,
    [string]$Verbosity = 'UVM_MEDIUM'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\dv_lib.ps1')
Push-Location $DvRoot
try {
    $Tb = @($Tb | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # also accept "a,b" as one string
    $tests = $DvTests | Where-Object { ($Tb.Count -eq 0 -or $Tb -contains $_.Tb) -and $_.Test -like $Filter }
    if (-not $tests) { throw 'No test matches the selection.' }
    $tbNames = $tests | ForEach-Object { $_.Tb } | Select-Object -Unique

    if (-not $NoBuild) {
        foreach ($n in $tbNames) {
            $b = Build-DvTb $n
            Write-Host "compiled $n (warnings: $($b.Warnings))"
        }
    }
    New-Item -ItemType Directory -Force -Path reports | Out-Null

    # Expand the list into individual runs.
    $runs = foreach ($t in $tests) {
        $cfg  = if ($t.Cfg)  { $t.Cfg }  else { 'default' }
        $plus = if ($t.Plus) { @($t.Plus) } else { @() }
        $n    = [Math]::Max(1, $t.Seeds * $(if ($t.Seeds -gt 1) { $SeedScale } else { 1 }))
        foreach ($seed in 1..$n) {
            $sim = Get-DvSimArgs $t.Tb $cfg $t.Test $seed $plus (-not $NoCov) $Verbosity
            [pscustomobject]@{ Tb = $t.Tb; Cfg = $cfg; Test = $t.Test; Seed = $seed; Args = $sim.Args; Log = $sim.Log; Stem = $sim.Stem
                               Expect = $(if ($t.Expect) { $t.Expect } else { 'PASS' }); Issue = "$($t.Issue)" }
        }
    }
    Write-Host "running $($runs.Count) simulations, $Jobs at a time"

    $vsim = "$DvQuesta\vsim.exe"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $done = $runs | ForEach-Object -ThrottleLimit $Jobs -Parallel {
        $r = $_
        $a = $r.Args
        & $using:vsim @a *> $null
        [pscustomobject]@{ Tb = $r.Tb; Cfg = $r.Cfg; Test = $r.Test; Seed = $r.Seed; Log = $r.Log; Exit = $LASTEXITCODE
                           Stem = $r.Stem; Expect = $r.Expect; Issue = $r.Issue }
    }

    # A test marked Expect='XFAIL' documents a known defect of the design: it is
    # expected to fail (XFAIL).  If it passes (XPASS) the list is out of date,
    # which counts as a regression failure.  Only PASS runs feed coverage.
    $results = foreach ($d in $done) {
        $v = Get-DvVerdict $d.Log $d.Exit
        # Expect='ORIG': reference run on the unmodified RTL of the original library.  The
        # outcome is recorded (ORIG-PASS / ORIG-FAIL) and never counts as a regression failure.
        $res = if ($d.Expect -eq 'XFAIL') { if ($v.Pass) { 'XPASS' } else { 'XFAIL' } }
               elseif ($d.Expect -eq 'ORIG') { if ($v.Pass) { 'ORIG-PASS' } else { 'ORIG-FAIL' } }
               else { if ($v.Pass) { 'PASS' } else { 'FAIL' } }
        [pscustomobject]@{ Tb = $d.Tb; Cfg = $d.Cfg; Test = $d.Test; Seed = $d.Seed; Result = $res; Checks = $v.Checks
                           Issue = $d.Issue; Reason = $v.Reason; Log = $d.Log; Ucdb = "cov/ucdb/$($d.Tb)/$($d.Stem).ucdb" }
    }
    $results = $results | Sort-Object Tb, Test, Cfg, Seed
    $csv = 'reports/regression_results.csv'
    if ($Tb.Count -gt 0 -and (Test-Path $csv)) {
        # Partial run: keep the rows of testbenches that were not rerun.
        $keep = Import-Csv $csv | Where-Object { $tbNames -notcontains $_.Tb }
        @($keep) + @($results) | Sort-Object Tb, Test, Cfg, Seed | Export-Csv -NoTypeInformation -Path $csv
    } else {
        $results | Export-Csv -NoTypeInformation -Path $csv
    }

    $results | Group-Object Tb, Test, Cfg | ForEach-Object {
        $p = @($_.Group | Where-Object Result -eq 'PASS').Count
        $x = @($_.Group | Where-Object Result -eq 'XFAIL').Count
        $o = @($_.Group | Where-Object { $_.Result -like 'ORIG-*' }).Count
        if ($o -gt 0) { $p = @($_.Group | Where-Object Result -eq 'ORIG-PASS').Count }
        $c = if ($o -gt 0) { 'Cyan' } elseif ($p -eq $_.Count) { 'Green' } elseif ($x -eq $_.Count) { 'Yellow' } else { 'Red' }
        $note = if ($x -gt 0) { "  (known issue $($_.Group[0].Issue): $x expected failure(s))" } else { '' }
        Write-Host ("  {0,-8} {1,-40} {2,-10} {3}/{4} passed{5}" -f $_.Group[0].Tb, $_.Group[0].Test, $_.Group[0].Cfg, $p, $_.Count, $note) -ForegroundColor $c
    }
    $fail  = @($results | Where-Object { $_.Result -in 'FAIL', 'XPASS' })
    $xfail = @($results | Where-Object Result -eq 'XFAIL')
    $pass  = @($results | Where-Object Result -eq 'PASS')
    $orig  = @($results | Where-Object { $_.Result -like 'ORIG-*' })
    foreach ($f in $fail) { Write-Host ("  {0} {1} seed={2}: {3}  ({4})" -f $f.Result, $f.Test, $f.Seed, $f.Reason, $f.Log) -ForegroundColor Red }
    Write-Host ("{0} runs: {1} PASS, {2} FAIL, {3} XFAIL (known issues), {4} reference runs on the original RTL ({5} ORIG-PASS)  ({6:n0} s)" -f $results.Count, $pass.Count, $fail.Count, $xfail.Count, $orig.Count, @($orig | Where-Object Result -eq 'ORIG-PASS').Count, $sw.Elapsed.TotalSeconds)
    if ($fail.Count -ne 0) { exit 1 }
}
finally { Pop-Location }
