<#
.SYNOPSIS
  Compile one testbench and run one test (QuestaSim 10.7c, UVM 1.2).
.EXAMPLE
  .\run_test.ps1 -Tb ram -Test axi_ram_random_test -Seed 7
  .\run_test.ps1 -Tb xbar -Test xbar_random_test -Seed 3 -Cov -Plus '+NUM_TXN=500'
  .\run_test.ps1 -Tb ram -Test axi_ram_smoke_test -NoBuild -Verbosity UVM_HIGH
.NOTES
  The log is written to logs/<tb>/<test>__<cfg>__s<seed>.log and starts with a
  header describing the test; the last line is TEST_RESULT: PASSED or FAILED.
#>
param(
    [Parameter(Mandatory)] [string]$Tb,
    [Parameter(Mandatory)] [string]$Test,
    [int]$Seed = 1,
    [string]$Cfg = 'default',
    [string[]]$Plus = @(),
    [switch]$Cov,
    [switch]$NoBuild,
    [string]$Verbosity = 'UVM_MEDIUM'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\dv_lib.ps1')
Push-Location $DvRoot
try {
    if (-not $NoBuild) {
        $b = Build-DvTb $Tb
        Write-Host "compiled $Tb (log: $($b.Log), warnings: $($b.Warnings))"
    }
    $sim = Get-DvSimArgs $Tb $Cfg $Test $Seed $Plus $Cov.IsPresent $Verbosity
    $simArgs = $sim.Args
    & "$DvQuesta\vsim.exe" @simArgs *> $null
    $v = Get-DvVerdict $sim.Log $LASTEXITCODE
    $color = if ($v.Pass) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1} cfg={2} seed={3} checks={4} {5}" -f $(if ($v.Pass) { 'PASS' } else { 'FAIL' }), $Test, $Cfg, $Seed, $v.Checks, $v.Reason) -ForegroundColor $color
    Write-Host "log: $($sim.Log)"
    if (-not $v.Pass) { exit 1 }
}
finally { Pop-Location }
