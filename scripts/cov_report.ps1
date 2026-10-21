<#
.SYNOPSIS
  Merge the coverage databases of the last regression and write the coverage report.
.DESCRIPTION
  1. merges cov/ucdb/<tb>/*.ucdb per testbench (functional coverage) and all together (code coverage)
  2. applies the exclusion files in cov/exclusions/*.do (once without and once with
     the items marked CONFIG-LIMITED)
  3. writes reports/coverage_summary.md with, for every design group, three figures
     taken from vcover output: no exclusions, unreachable items excluded, and
     unreachable + configuration-limited items excluded
  4. writes reports/coverage_<group>_holes.txt listing whatever is still uncovered
  "Total" is QuestaSim's own figure: the mean of statement, branch, FEC condition,
  FEC expression, FSM and toggle coverage of the group's design units.
.EXAMPLE
  .\scripts\cov_report.ps1 -MinTotal 98
#>
param(
    [double]$MinTotal = 0   # exit code 1 if a group's total with exclusions is below this
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'dv_lib.ps1')
Push-Location $DvRoot
try {
    $vcover = "$DvQuesta\vcover.exe"
    $vsim   = "$DvQuesta\vsim.exe"
    New-Item -ItemType Directory -Force -Path reports, cov/merged | Out-Null

    # ---- merge -----------------------------------------------------------------
    $all = @()
    $perTb = [ordered]@{}
    # Only runs that passed in the last regression contribute to coverage.
    if (-not (Test-Path reports/regression_results.csv)) { throw 'reports/regression_results.csv not found. Run regress.ps1 first.' }
    $passed = Import-Csv reports/regression_results.csv | Where-Object Result -eq 'PASS'
    foreach ($tb in $DvTbs.Keys) {
        $dbs = @($passed | Where-Object Tb -eq $tb | ForEach-Object { "cov/ucdb/$($_.Tb)/$(Get-DvStem $_.Test $_.Cfg ([int]$_.Seed)).ucdb" } | Where-Object { Test-Path $_ })
        if ($dbs.Count -eq 0) { continue }
        $out = "cov/merged/$tb.ucdb"
        & $vcover merge -out $out @dbs *> "cov/merged/$tb.merge.log"
        if ($LASTEXITCODE -ne 0) { throw "vcover merge failed for $tb (cov/merged/$tb.merge.log)" }
        $perTb[$tb] = [pscustomobject]@{ Ucdb = $out; Count = $dbs.Count }
        # The system testbench instantiates the blocks with other parameters; it is reported on its own
        # and does not count towards (or against) the block-level numbers.
        if (-not $DvTbs[$tb].Integration) { $all += $out }
    }
    if ($all.Count -eq 0) { throw 'No UCDB found. Run regress.ps1 first (without -NoCov).' }
    & $vcover merge -out cov/merged/all_raw.ucdb @all *> cov/merged/all.merge.log
    if ($LASTEXITCODE -ne 0) { throw 'vcover merge failed for the combined database' }

    # ---- exclusions ------------------------------------------------------------
    # Two databases are derived from the raw one:
    #   all_strict.ucdb : without the items that cannot be reached in any configuration
    #   all_final.ucdb  : also without the items marked CONFIG-LIMITED (unreachable only
    #                     in the configurations that were verified)
    $exclFiles = @(Get-ChildItem cov/exclusions -Filter *.do -ErrorAction SilentlyContinue)
    function Invoke-Exclusions([string[]]$DoFiles, [string]$Out, [string]$Log) {
        $cmds = @($DoFiles | ForEach-Object { "do $_" }) + @("coverage save $Out", 'quit -f')
        if (Test-Path $Out) { [System.IO.File]::Delete((Join-Path $DvRoot $Out)) }
        & $vsim -modelsimini $DvIni -c -viewcov cov/merged/all_raw.ucdb -l $Log -do ($cmds -join '; ') *> $null
        $bad = @(Select-String -Path $Log -Pattern '^# \*\* (Error|Warning)|Cannot open|^# Error|invalid command')
        if (-not (Test-Path $Out)) { throw "Exclusion step did not produce $Out; see $Log" }
        if ($bad.Count -gt 0) {
            $bad | Select-Object -First 10 | ForEach-Object { Write-Host $_.Line -ForegroundColor Red }
            throw "An exclusion command was rejected; see $Log"
        }
    }
    $strictDo = foreach ($x in $exclFiles) {
        $p = "cov/merged/_strict_$($x.Name)"
        Set-Content -Path $p -Value (Get-Content $x.FullName | Where-Object { $_ -notmatch 'CONFIG-LIMITED' })
        $p
    }
    Invoke-Exclusions @($strictDo) 'cov/merged/all_strict.ucdb' 'cov/merged/exclusions_strict.log'
    Invoke-Exclusions @($exclFiles | ForEach-Object { "cov/exclusions/$($_.Name)" }) 'cov/merged/all_final.ucdb' 'cov/merged/exclusions.log'

    # ---- report helpers --------------------------------------------------------
    function Get-GroupCov([string]$Ucdb, [string[]]$Dus) {
        $duArgs = $Dus | ForEach-Object { '-du'; $_ }
        $txt = & $vcover report @duArgs -code bcesft $Ucdb 2>&1
        $t = [ordered]@{ Stmt = @(0, 0); Branch = @(0, 0); Cond = @(0, 0); Expr = @(0, 0); State = @(0, 0); Trans = @(0, 0); Toggle = @(0, 0) }
        $map = @{ 'Stmts' = 'Stmt'; 'Branches' = 'Branch'; 'FEC Condition Terms' = 'Cond'; 'FEC Expression Terms' = 'Expr'; 'States' = 'State'; 'Transitions' = 'Trans'; 'Toggle Bins' = 'Toggle' }
        $total = $null; $found = @()
        foreach ($line in $txt) {
            if ($line -match 'Design Unit: \S+\.(\S+)') { $found += $Matches[1] }
            if ($line -match '^\s+(Stmts|Branches|FEC Condition Terms|FEC Expression Terms|States|Transitions|Toggle Bins)\s+(\d+)\s+(\d+)\s+(\d+)\s+[\d.]+') {
                $k = $map[$Matches[1]]; $t[$k][0] += [int]$Matches[2]; $t[$k][1] += [int]$Matches[3]
            }
            if ($line -match 'Total Coverage By Design Unit \(filtered view\):\s+([\d.]+)%') { $total = [double]$Matches[1] }
        }
        return [pscustomobject]@{ Types = $t; Total = $total; Found = ($found | Select-Object -Unique); Missing = @($Dus | Where-Object { $found -notcontains $_ }) }
    }
    function Format-Type($pair) {
        if ($pair[0] -eq 0) { return 'n/a' }
        return ('{0:n2}% ({1}/{2})' -f (100.0 * $pair[1] / $pair[0]), $pair[1], $pair[0])
    }

    # ---- summary ---------------------------------------------------------------
    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add('# Coverage summary')
    $md.Add('')
    $md.Add("Generated by ``scripts/cov_report.ps1`` on $(Get-Date -Format 'yyyy-MM-dd HH:mm') from the UCDB files of the last regression.")
    $md.Add('Every number below is copied from `vcover report`; nothing is typed by hand.')
    $md.Add('')
    $md.Add('"Total" is the QuestaSim figure *Total Coverage By Design Unit*: the mean of statement, branch,')
    $md.Add('FEC condition, FEC expression, FSM and toggle coverage of the design units of the group.')
    $md.Add('')
    $md.Add('## Code coverage of the RTL')
    $md.Add('')
    $md.Add('| Group | Design units | Exclusions | Statement | Branch | FEC condition | FEC expression | FSM state | FSM transition | Toggle | **Total** |')
    $md.Add('|---|---|---|---|---|---|---|---|---|---|---|')
    $gateFail = @()
    foreach ($g in $DvCovGroups.Keys) {
        $dus = @($DvCovGroups[$g])
        foreach ($variant in @(@('none', 'cov/merged/all_raw.ucdb'), @('unreachable only', 'cov/merged/all_strict.ucdb'), @('with', 'cov/merged/all_final.ucdb'))) {
            $c = Get-GroupCov $variant[1] $dus
            if ($c.Total -eq $null) { continue }
            $ty = $c.Types
            $label = if ($variant[0] -eq 'with') { 'unreachable + configuration-limited' } else { $variant[0] }
            $md.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | **{10:n2}%** |' -f $g, ($c.Found -join ', '), $label,
                     (Format-Type $ty.Stmt), (Format-Type $ty.Branch), (Format-Type $ty.Cond), (Format-Type $ty.Expr),
                     (Format-Type $ty.State), (Format-Type $ty.Trans), (Format-Type $ty.Toggle), $c.Total))
            if ($c.Missing.Count -gt 0) { $md.Add("| | *no coverage data for: $($c.Missing -join ', ')* | | | | | | | | | |") }
            if ($variant[0] -eq 'with') {
                Write-Host ('{0,-6} total with exclusions: {1:n2}%' -f $g, $c.Total)
                if ($c.Total -lt $MinTotal) { $gateFail += $g }
                $duArgs = $dus | ForEach-Object { '-du'; $_ }
                & $vcover report @duArgs -details -zeros -code bcesft -output "reports/coverage_${g}_holes.txt" cov/merged/all_final.ucdb *> $null
            } else {
                Write-Host ('{0,-6} total, exclusions = {1}: {2:n2}%' -f $g, $variant[0], $c.Total)
            }
        }
    }
    $md.Add('')
    $md.Add("Block-level numbers: merged from the testbenches $((($perTb.Keys | Where-Object { -not $DvTbs[$_].Integration }) -join ', ')).")
    $md.Add('Uncovered items that remain after exclusions are listed in `reports/coverage_<group>_holes.txt`.')
    $sysTbs = @($perTb.Keys | Where-Object { $DvTbs[$_].Integration })
    if ($sysTbs.Count -gt 0) {
        $md.Add('')
        $md.Add('## Code coverage reached by the system testbench alone (information only)')
        $md.Add('')
        $md.Add('The system testbench checks the integration of the blocks (different parameters, few tests). Its coverage is')
        $md.Add('**not** part of the block-level numbers above and no exclusion is applied to it.')
        $md.Add('')
        $md.Add('| Testbench | Group | Statement | Branch | FEC condition | FEC expression | FSM state | FSM transition | Toggle | Total |')
        $md.Add('|---|---|---|---|---|---|---|---|---|---|')
        foreach ($tb in $sysTbs) {
            foreach ($g in $DvCovGroups.Keys) {
                $c = Get-GroupCov $perTb[$tb].Ucdb @($DvCovGroups[$g])
                if ($c.Total -eq $null) { continue }
                $ty = $c.Types
                $md.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9:n2}% |' -f $tb, $g, (Format-Type $ty.Stmt), (Format-Type $ty.Branch), (Format-Type $ty.Cond),
                         (Format-Type $ty.Expr), (Format-Type $ty.State), (Format-Type $ty.Trans), (Format-Type $ty.Toggle), $c.Total))
            }
        }
    }
    $md.Add('')
    $md.Add('## Exclusions')
    $md.Add('')
    $md.Add('| File | Exclusion commands | of which CONFIG-LIMITED |')
    $md.Add('|---|---|---|')
    foreach ($f in $exclFiles) {
        $n = @(Select-String -Path $f.FullName -Pattern '^\s*coverage exclude').Count
        $k = @(Select-String -Path $f.FullName -Pattern '^\s*coverage exclude.*CONFIG-LIMITED').Count
        $md.Add("| ``cov/exclusions/$($f.Name)`` | $n | $k |")
    }
    $md.Add('')
    $md.Add('Each command carries the reason why the item cannot be reached. The rule followed: an item is excluded')
    $md.Add('only when the RTL or the AXI4 specification makes it unreachable, never because it was hard to hit.')
    $md.Add('')
    $md.Add('Three figures are given per group so that the effect of the exclusions is visible:')
    $md.Add('')
    $md.Add('* **none** - raw coverage of the merged regression;')
    $md.Add('* **unreachable only** - without the items no stimulus can reach in any configuration (loop variables,')
    $md.Add('  signals tied to constants, elaboration-time code, structurally impossible condition rows);')
    $md.Add('* **unreachable + configuration-limited** - additionally without the items marked `CONFIG-LIMITED`, which are')
    $md.Add('  unreachable only because of the verified configuration (32-bit data bus, 3 address regions per slave).')
    $md.Add('  The gate of `-MinTotal` is applied to this figure.')
    $md.Add('')
    $md.Add('## Functional coverage (covergroups)')
    $md.Add('')
    $md.Add('| Testbench | Runs merged | Covergroup coverage | Covergroup types |')
    $md.Add('|---|---|---|---|')
    foreach ($tb in $perTb.Keys) {
        $txt = & $vcover report -cvg $perTb[$tb].Ucdb 2>&1
        $m = $txt | Select-String 'TOTAL COVERGROUP COVERAGE:\s+([\d.]+)%\s+COVERGROUP TYPES:\s+(\d+)' | Select-Object -First 1
        if ($m) { $md.Add(('| {0} | {1} | {2}% | {3} |' -f $tb, $perTb[$tb].Count, $m.Matches[0].Groups[1].Value, $m.Matches[0].Groups[2].Value)) }
        & $vcover report -cvg -details -output "reports/functional_coverage_$tb.txt" $perTb[$tb].Ucdb *> $null
    }
    $md.Add('')
    $md.Add('Bin-level detail per testbench: `reports/functional_coverage_<tb>.txt`.')
    Set-Content -Path reports/coverage_summary.md -Value $md
    Write-Host 'wrote reports/coverage_summary.md'
    if ($gateFail.Count -gt 0) { Write-Host "coverage gate ($MinTotal%) not met by: $($gateFail -join ', ')" -ForegroundColor Red; exit 1 }
}
finally { Pop-Location }
