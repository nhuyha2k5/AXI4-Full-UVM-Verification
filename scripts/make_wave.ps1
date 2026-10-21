<#
.SYNOPSIS
  Run one test with full signal visibility and write its waveform database, to be opened in QuestaSim and screenshotted.
.DESCRIPTION
  The regression runs on an optimised design that hides internal signals and records no waveform.
  This script builds a separate, debug-visible copy (build/wave/<tb>, vopt +acc), runs the test with
  'log -r /*' and writes build/wave/<test>__<cfg>__s<seed>.wlf (and, with -Vcd, a .vcd that
  scripts/wave_hints.py uses to find interesting moments).  It does not touch the regression libraries.
.EXAMPLE
  .\scripts\make_wave.ps1 -Tb ram -Test axi_ram_smoke_test
  vsim -modelsimini modelsim.ini -view build/wave/axi_ram_smoke_test__default__s1.wlf -do docs/images/waves/fig_2_3_write_burst.do
#>
param(
    [Parameter(Mandatory)] [string]$Tb,
    [Parameter(Mandatory)] [string]$Test,
    [int]$Seed = 1,
    [string]$Cfg = 'default',
    [string[]]$Plus = @(),
    [switch]$Vcd,
    [switch]$Rebuild
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'dv_lib.ps1')
Push-Location $DvRoot
try {
    $t = Get-DvTb $Tb
    $lib = "build/wave/$Tb"
    $log = "build/wave/$Tb.build.log"
    if ($Rebuild -or -not (Test-Path "$lib/_info")) {
        New-Item -ItemType Directory -Force -Path build/wave | Out-Null
        if (Test-Path $lib) { & "$DvQuesta\vdel.exe" -lib $lib -all *> $null }
        & "$DvQuesta\vlib.exe" $lib | Out-Null
        Set-Content $log "# debug build of $Tb"
        if ($t.Rtl) { & "$DvQuesta\vlog.exe" -modelsimini $DvIni -work $lib @($t.RtlArgs) -f $t.Rtl *>> $log; if ($LASTEXITCODE) { throw "RTL compile failed, see $log" } }
        & "$DvQuesta\vlog.exe" -modelsimini $DvIni -sv -work $lib -f $t.Tb *>> $log
        if ($LASTEXITCODE) { throw "testbench compile failed, see $log" }
        foreach ($c in $t.Configs.Keys) {
            & "$DvQuesta\vopt.exe" -modelsimini $DvIni -work $lib $t.Top -o "opt_$c" '+acc' @($t.Configs[$c]) *>> $log
            if ($LASTEXITCODE) { throw "vopt failed for $c, see $log" }
        }
    }
    $stem = Get-DvStem $Test $Cfg $Seed
    $wlf = "build/wave/$stem.wlf"
    $do = 'log -r /*; '
    if ($Vcd) { $do += "vcd file build/wave/$stem.vcd; vcd add -r /$($t.Top)/*; " }
    $do += 'run -all; quit -f'
    $a = @('-modelsimini', $DvIni, '-c', '-lib', $lib, "opt_$Cfg", "+UVM_TESTNAME=$Test", '+UVM_VERBOSITY=UVM_MEDIUM',
           '-sv_seed', "$Seed", '-l', "build/wave/$stem.log", '-wlf', $wlf, '-do', $do) + $Plus
    & "$DvQuesta\vsim.exe" @a *> $null
    $v = Get-DvVerdict "build/wave/$stem.log" $LASTEXITCODE
    Write-Host ("{0}: {1}  ({2})" -f $(if ($v.Pass) { 'PASS' } else { 'FAIL' }), $Test, $v.Reason)
    Write-Host "waveform: $wlf"
    if ($Vcd) { Write-Host "vcd:      build/wave/$stem.vcd" }
}
finally { Pop-Location }
