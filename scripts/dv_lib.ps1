# Shared helpers for run_test.ps1, regress.ps1 and cov_report.ps1.
# All paths are relative to the project root; the scripts set the location there.

$script:DvRoot   = Split-Path -Parent $PSScriptRoot
$script:DvQuesta = 'C:\questasim64_10.7c\win64'
$script:DvIni    = 'modelsim.ini'          # maps mtiUvm to the UVM 1.2 library

. (Join-Path $PSScriptRoot 'dv_config.ps1')

function Get-DvTb([string]$Name) {
    if (-not $DvTbs.Contains($Name)) { throw "Unknown testbench '$Name'. Known: $($DvTbs.Keys -join ', ')" }
    return $DvTbs[$Name]
}

function Get-DvStem([string]$Test, [string]$Cfg, [int]$Seed) {
    return ('{0}__{1}__s{2}' -f $Test, $Cfg, $Seed)
}

# Compile one testbench and optimise every build configuration of it.
# RTL is compiled with code-coverage instrumentation, testbench code without,
# so coverage numbers refer to the design only.
function Build-DvTb([string]$Name) {
    $tb  = Get-DvTb $Name
    $lib = "build/$Name"
    New-Item -ItemType Directory -Force -Path build, "logs/$Name" | Out-Null
    if (Test-Path $lib) { & "$DvQuesta\vdel.exe" -lib $lib -all *> $null }
    & "$DvQuesta\vlib.exe" $lib | Out-Null
    $log = "logs/$Name/compile.log"
    Set-Content -Path $log -Value "# compile log for testbench $Name"
    if ($tb.Rtl) {
        $rtlArgs = @($tb.RtlArgs)
        # Coverage is collected with the simulator's default settings.  The stricter
        # '-coverdeglitch 0' (count only the settled evaluation of a combinational
        # expression) was tried: vsim 10.7c then crashes at time 0 (SIGSEGV in the
        # initial block of axi_crossbar_addr), so it cannot be used here.
        & "$DvQuesta\vlog.exe" -modelsimini $DvIni -work $lib '+cover=bcesft' @rtlArgs -f $tb.Rtl *>> $log
        if ($LASTEXITCODE -ne 0) { throw "RTL compile failed for $Name, see $log" }
    }
    & "$DvQuesta\vlog.exe" -modelsimini $DvIni -sv -work $lib -f $tb.Tb *>> $log
    if ($LASTEXITCODE -ne 0) { throw "Testbench compile failed for $Name, see $log" }
    foreach ($cfg in $tb.Configs.Keys) {
        $gen = @($tb.Configs[$cfg])
        & "$DvQuesta\vopt.exe" -modelsimini $DvIni -work $lib $tb.Top -o "opt_$cfg" @gen *>> $log
        if ($LASTEXITCODE -ne 0) { throw "vopt failed for $Name/$cfg, see $log" }
    }
    $bad = Select-String -Path $log -Pattern '^\*\* (Error|Warning)' | Where-Object { $_.Line -notmatch 'vopt-2241|vlog-2286' }
    return [pscustomobject]@{ Tb = $Name; Log = $log; Warnings = @($bad).Count }
}

# Verdict of one simulation from its log.  A test passes only if it printed
# TEST_RESULT: PASSED, UVM counted no error/fatal, and the simulator itself
# reported no error (failed randomization, $error, assertion without UVM, ...).
function Get-DvVerdict([string]$LogPath, [int]$ExitCode) {
    if (-not (Test-Path $LogPath)) { return [pscustomobject]@{ Pass = $false; Reason = 'no log'; Checks = 0 } }
    # The verdict, the check count and the UVM totals are all in the last lines.
    $t = (Get-Content $LogPath -Tail 200) -join "`n"
    $reason = @()
    if ($ExitCode -ne 0)                    { $reason += "vsim exit code $ExitCode" }
    if ($t -notmatch 'TEST_RESULT: PASSED') { $reason += $(if ($t -match 'TEST_RESULT: FAILED') { 'TEST_RESULT: FAILED' } else { 'no TEST_RESULT line (crash, timeout or error limit)' }) }
    if ($t -notmatch 'UVM_ERROR :\s+0\b')   { $reason += 'UVM_ERROR count is not 0' }
    if ($t -notmatch 'UVM_FATAL :\s+0\b')   { $reason += 'UVM_FATAL count is not 0' }
    $simErr = @(Select-String -Path $LogPath -Pattern '^# \*\* (Error|Fatal)').Count
    if ($simErr -gt 0)                      { $reason += "$simErr simulator error line(s)" }
    $checks = 0
    if ($t -match 'checks performed : (\d+)') { $checks = [int]$Matches[1] }
    return [pscustomobject]@{ Pass = ($reason.Count -eq 0); Reason = ($reason -join '; '); Checks = $checks }
}
# Argument list for one vsim run.
function Get-DvSimArgs([string]$Tb, [string]$Cfg, [string]$Test, [int]$Seed, [string[]]$Plus, [bool]$Cov, [string]$Verbosity) {
    $stem = Get-DvStem $Test $Cfg $Seed
    $log  = "logs/$Tb/$stem.log"
    $a = @('-modelsimini', $DvIni, '-c', '-lib', "build/$Tb", "opt_$Cfg",
           "+UVM_TESTNAME=$Test", "+UVM_VERBOSITY=$Verbosity", '+UVM_MAX_QUIT_COUNT=100,NO', '-sv_seed', "$Seed",
           '-l', $log, '-wlf', "build/$Tb/$stem.wlf")
    if ($Plus) { $a += $Plus }
    $do = 'run -all; quit -f'
    if ($Cov) {
        New-Item -ItemType Directory -Force -Path "cov/ucdb/$Tb" | Out-Null
        $a  += '-coverage'
        $do  = "coverage save -onexit cov/ucdb/$Tb/$stem.ucdb; run -all; quit -f"
    }
    $a += @('-do', $do)
    return [pscustomobject]@{ Args = $a; Log = $log; Stem = $stem }
}
