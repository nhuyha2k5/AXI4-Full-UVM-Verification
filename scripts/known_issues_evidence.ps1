<#
.SYNOPSIS
  Collect the evidence for the known design issues from the logs of the last regression.
.DESCRIPTION
  For every run marked XFAIL in reports/regression_results.csv, copies the test header
  (intent, stimulus) and the first error lines of its log into
  reports/known_issues_evidence.txt.  Nothing is typed by hand.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'dv_lib.ps1')
Push-Location $DvRoot
try {
    $rows = Import-Csv reports/regression_results.csv | Where-Object { $_.Issue } | Sort-Object Issue, Tb, Test
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add("Evidence for the known issues (docs/KNOWN_ISSUES.md), generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') from the regression logs.")
    $out.Add('')
    foreach ($r in $rows) {
        $out.Add(('=' * 100))
        $out.Add("$($r.Issue)   testbench=$($r.Tb)   test=$($r.Test)   cfg=$($r.Cfg)   seed=$($r.Seed)   regression result=$($r.Result)")
        $out.Add("log: $($r.Log)")
        if (-not (Test-Path $r.Log)) { $out.Add('  (log not found)'); continue }
        $lines = Get-Content $r.Log
        $lines | Where-Object { $_ -match '^#\s+(INTENT|STIMULUS|DUT)\s+:' } | ForEach-Object { $out.Add('  ' + ($_ -replace '^#\s+', '')) }
        $errs = @($lines | Where-Object { $_ -match '^# UVM_(ERROR|FATAL) .*@' })
        $out.Add("  error/fatal messages in the log: $($errs.Count); first ones:")
        $errs | Select-Object -First 3 | ForEach-Object {
            $s = $_ -replace '^# ', ''
            if ($s.Length -gt 420) { $s = $s.Substring(0, 420) + ' ...' }
            $out.Add('    ' + $s)
        }
        $res = $lines | Where-Object { $_ -match 'TEST_RESULT:' } | Select-Object -Last 1
        if ($res) { $out.Add('  ' + ($res -replace '^#\s+', '')) } else { $out.Add('  no TEST_RESULT line (the simulation was stopped by the watchdog or the error limit)') }
        $out.Add('')
    }
    Set-Content -Path reports/known_issues_evidence.txt -Value $out
    Write-Host "wrote reports/known_issues_evidence.txt ($($rows.Count) run(s))"
}
finally { Pop-Location }
