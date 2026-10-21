# Testbench registry and regression list.
#
# $DvTbs : one entry per testbench.
#   Top     top-level module
#   Rtl     filelist of the design, compiled with coverage (null when there is no DUT)
#   RtlArgs extra vlog arguments for the design (for example a +define+)
#   Tb      filelist of the VIP and testbench
#   Configs named builds; the value is the list of extra vopt arguments (-g overrides)
#   Dus     design units whose coverage is reported for this testbench
#
# $DvTests : the regression.  Seeds = number of seeds (1..N) the test runs with.
#   Expect = 'XFAIL' marks a test that demonstrates a known design defect (see docs/KNOWN_ISSUES.md).

$DvTbs = [ordered]@{
    vip = @{ Top = 'tb_vip_top'; Rtl = $null; Tb = 'tb/tb_vip/tb.f'; Configs = [ordered]@{ default = @() }; Dus = @() }
    ram = @{ Top = 'tb_ram_top'; Rtl = 'tb/tb_ram/rtl.f'; Tb = 'tb/tb_ram/tb.f'; Dus = @('axi_ram')
             Configs = [ordered]@{ default = @(); pipe = @('-gPIPELINE_OUTPUT=1'); init = @('-gINIT_FILE=tb/tb_ram/ram_init.hex') } }
    # The crossbar is verified with the fixes for known issues XBAR-02, -05, -06, -07 and -08
    # enabled (all are opt-in `ifdef blocks; without the defines the RTL is the original).
    # 'xbar_orig' (no fix), 'xbar_fix02', 'xbar_fix06' and 'xbar_fix07' (fixes added one group
    # at a time) exist solely to run the tests that demonstrate the individual defects.
    xbar = @{ Top = 'tb_xbar_top'; Rtl = 'tb/tb_xbar/rtl.f'; Tb = 'tb/tb_xbar/tb.f'; Configs = [ordered]@{ default = @(); open = @('-gOPEN=1') }
              RtlArgs = @('+define+AXI_CROSSBAR_DECERR_CPL_FIX', '+define+AXI_CROSSBAR_WREADY_GATE_FIX', '+define+AXI_CROSSBAR_M_REG_TYPE_FIX', '+define+AXI_CROSSBAR_RESP_SELECT_FIX',
                          '+define+AXI_CROSSBAR_ISSUE_LIMIT_FIX')
              Dus = @('axi_crossbar', 'axi_crossbar_addr', 'axi_crossbar_rd', 'axi_crossbar_wr', 'axi_register_rd', 'axi_register_wr', 'arbiter', 'priority_encoder') }
    xbar_orig  = @{ Top = 'tb_xbar_top'; Rtl = 'tb/tb_xbar/rtl.f'; Tb = 'tb/tb_xbar/tb.f'; Configs = [ordered]@{ default = @(); open = @('-gOPEN=1') }; Dus = @() }
    xbar_fix02 = @{ Top = 'tb_xbar_top'; Rtl = 'tb/tb_xbar/rtl.f'; Tb = 'tb/tb_xbar/tb.f'; Configs = [ordered]@{ default = @() }; Dus = @()
                    RtlArgs = @('+define+AXI_CROSSBAR_DECERR_CPL_FIX') }
    # Every fix except the one for XBAR-07: demonstrates XBAR-07, which only shows once the
    # M_*_REG_TYPE parameters take effect (XBAR-06 fixed).
    xbar_fix06 = @{ Top = 'tb_xbar_top'; Rtl = 'tb/tb_xbar/rtl.f'; Tb = 'tb/tb_xbar/tb.f'; Configs = [ordered]@{ default = @() }; Dus = @()
                    RtlArgs = @('+define+AXI_CROSSBAR_DECERR_CPL_FIX', '+define+AXI_CROSSBAR_WREADY_GATE_FIX', '+define+AXI_CROSSBAR_M_REG_TYPE_FIX') }
    # Every fix except the one for XBAR-08 (issue limit).
    xbar_fix07 = @{ Top = 'tb_xbar_top'; Rtl = 'tb/tb_xbar/rtl.f'; Tb = 'tb/tb_xbar/tb.f'; Configs = [ordered]@{ default = @(); open = @('-gOPEN=1') }; Dus = @()
                    RtlArgs = @('+define+AXI_CROSSBAR_DECERR_CPL_FIX', '+define+AXI_CROSSBAR_WREADY_GATE_FIX', '+define+AXI_CROSSBAR_M_REG_TYPE_FIX',
                                '+define+AXI_CROSSBAR_RESP_SELECT_FIX') }
    # DMA engines.  Build configurations: 'aligned' = ENABLE_UNALIGNED 0, 'burst1'/'burst256' = AXI_MAX_BURST_LEN.
    # axi_dma_wr and axi_cdma are verified with the opt-in fixes for known issues DMAWR-01 and CDMA-01;
    # 'dma_wr_orig' and 'cdma_orig' are the unmodified RTL and only run the tests that demonstrate them.
    dma_rd = @{ Top = 'tb_dma_rd_top'; Rtl = 'tb/tb_dma/rtl_rd.f'; Tb = 'tb/tb_dma/tb_rd.f'; Dus = @('axi_dma_rd')
                Configs = [ordered]@{ default = @(); aligned = @('-gENABLE_UNALIGNED=0'); burst1 = @('-gMAX_BURST_LEN=1'); burst256 = @('-gMAX_BURST_LEN=256') } }
    dma_wr = @{ Top = 'tb_dma_wr_top'; Rtl = 'tb/tb_dma/rtl_wr.f'; Tb = 'tb/tb_dma/tb_wr.f'; Dus = @('axi_dma_wr'); RtlArgs = @('+define+AXI_DMA_WR_TREADY_FIX')
                Configs = [ordered]@{ default = @(); aligned = @('-gENABLE_UNALIGNED=0'); burst1 = @('-gMAX_BURST_LEN=1'); burst256 = @('-gMAX_BURST_LEN=256') } }
    cdma   = @{ Top = 'tb_cdma_top'; Rtl = 'tb/tb_dma/rtl_cdma.f'; Tb = 'tb/tb_dma/tb_cdma.f'; Dus = @('axi_cdma'); RtlArgs = @('+define+AXI_CDMA_RREADY_FIX')
                Configs = [ordered]@{ default = @(); aligned = @('-gENABLE_UNALIGNED=0'); burst1 = @('-gMAX_BURST_LEN=1'); burst256 = @('-gMAX_BURST_LEN=256') } }
    dma_wr_orig = @{ Top = 'tb_dma_wr_top'; Rtl = 'tb/tb_dma/rtl_wr.f'; Tb = 'tb/tb_dma/tb_wr.f'; Dus = @(); Configs = [ordered]@{ default = @() } }
    cdma_orig   = @{ Top = 'tb_cdma_top'; Rtl = 'tb/tb_dma/rtl_cdma.f'; Tb = 'tb/tb_dma/tb_cdma.f'; Dus = @(); Configs = [ordered]@{ default = @() } }

    # The unmodified upstream DMA engines (upstream_ref/): same testbench, no fix macros.  Used to tell
    # defects of the original library from defects introduced by the changes made in this project.
    dma_rd_up = @{ Top = 'tb_dma_rd_top'; Rtl = 'tb/tb_dma/rtl_rd_upstream.f';   Tb = 'tb/tb_dma/tb_rd.f';   Dus = @(); Configs = [ordered]@{ default = @(); aligned = @('-gENABLE_UNALIGNED=0'); burst1 = @('-gMAX_BURST_LEN=1'); burst256 = @('-gMAX_BURST_LEN=256') } }
    dma_wr_up = @{ Top = 'tb_dma_wr_top'; Rtl = 'tb/tb_dma/rtl_wr_upstream.f';   Tb = 'tb/tb_dma/tb_wr.f';   Dus = @(); Configs = [ordered]@{ default = @(); aligned = @('-gENABLE_UNALIGNED=0'); burst1 = @('-gMAX_BURST_LEN=1'); burst256 = @('-gMAX_BURST_LEN=256') } }
    cdma_up   = @{ Top = 'tb_cdma_top';   Rtl = 'tb/tb_dma/rtl_cdma_upstream.f'; Tb = 'tb/tb_dma/tb_cdma.f'; Dus = @(); Configs = [ordered]@{ default = @(); aligned = @('-gENABLE_UNALIGNED=0'); burst1 = @('-gMAX_BURST_LEN=1'); burst256 = @('-gMAX_BURST_LEN=256') } }
    # The unmodified upstream axi_ram (no INIT_FILE; the 'init' configuration does not exist here).
    ram_up    = @{ Top = 'tb_ram_top'; Rtl = 'tb/tb_ram/rtl_upstream.f'; Tb = 'tb/tb_ram/tb_upstream.f'; Dus = @()
                   Configs = [ordered]@{ default = @(); pipe = @('-gPIPELINE_OUTPUT=1') } }

    # System level: AXI4 VIP master + axi_cdma -> axi_crossbar -> 2 x axi_ram.
    # Integration = $true: its coverage is reported separately, not merged into the block-level numbers.
    sys = @{ Top = 'tb_sys_top'; Rtl = 'tb/tb_sys/rtl.f'; Tb = 'tb/tb_sys/tb.f'; Configs = [ordered]@{ default = @() }; Integration = $true
             RtlArgs = @('+define+AXI_CROSSBAR_DECERR_CPL_FIX', '+define+AXI_CROSSBAR_WREADY_GATE_FIX', '+define+AXI_CROSSBAR_M_REG_TYPE_FIX',
                         '+define+AXI_CROSSBAR_RESP_SELECT_FIX', '+define+AXI_CROSSBAR_ISSUE_LIMIT_FIX', '+define+AXI_CDMA_RREADY_FIX'); Dus = @() }
}

$DvTests = @(
    @{ Tb = 'vip'; Test = 'vip_directed_test';        Seeds = 2 }
    @{ Tb = 'vip'; Test = 'vip_random_test';          Seeds = 10 }
    @{ Tb = 'vip'; Test = 'vip_error_resp_test';      Seeds = 3 }
    @{ Tb = 'vip'; Test = 'vip_reset_test';           Seeds = 5 }
    @{ Tb = 'vip'; Test = 'vip_neg_early_rlast_test'; Seeds = 1 }
    @{ Tb = 'vip'; Test = 'vip_neg_wrong_bid_test';   Seeds = 1 }
    @{ Tb = 'vip'; Test = 'vip_neg_no_response_test'; Seeds = 1 }

    @{ Tb = 'ram'; Test = 'axi_ram_smoke_test';        Seeds = 1 }
    @{ Tb = 'ram'; Test = 'axi_ram_directed_test';     Seeds = 2 }
    @{ Tb = 'ram'; Test = 'axi_ram_write_read_test';   Seeds = 6 }
    @{ Tb = 'ram'; Test = 'axi_ram_random_test';       Seeds = 10 }
    @{ Tb = 'ram'; Test = 'axi_ram_backpressure_test'; Seeds = 4 }
    @{ Tb = 'ram'; Test = 'axi_ram_reset_test';        Seeds = 4 }
    @{ Tb = 'ram'; Test = 'axi_ram_smoke_test';        Seeds = 1; Cfg = 'pipe' }
    @{ Tb = 'ram'; Test = 'axi_ram_write_read_test';   Seeds = 3; Cfg = 'pipe' }
    @{ Tb = 'ram'; Test = 'axi_ram_random_test';       Seeds = 6; Cfg = 'pipe' }
    @{ Tb = 'ram'; Test = 'axi_ram_backpressure_test'; Seeds = 3; Cfg = 'pipe' }
    @{ Tb = 'ram'; Test = 'axi_ram_reset_test';        Seeds = 2; Cfg = 'pipe' }
    @{ Tb = 'ram'; Test = 'axi_ram_init_file_test';    Seeds = 1; Cfg = 'init' }
    @{ Tb = 'ram'; Test = 'axi_ram_wrap_test';         Seeds = 1; Expect = 'XFAIL'; Issue = 'RAM-01' }

    @{ Tb = 'xbar'; Test = 'xbar_smoke_test';        Seeds = 1 }
    @{ Tb = 'xbar'; Test = 'xbar_param_test';        Seeds = 1 }
    @{ Tb = 'xbar'; Test = 'xbar_param_test';        Seeds = 1; Cfg = 'open' }
    @{ Tb = 'xbar_orig'; Test = 'xbar_param_test';   Seeds = 1; Expect = 'XFAIL'; Issue = 'XBAR-06' }
    @{ Tb = 'xbar_fix06'; Test = 'xbar_smoke_test';  Seeds = 1; Expect = 'XFAIL'; Issue = 'XBAR-07' }
    @{ Tb = 'xbar_fix07'; Test = 'xbar_issue_limit_test'; Seeds = 1; Cfg = 'open'; Expect = 'XFAIL'; Issue = 'XBAR-08' }
    @{ Tb = 'xbar'; Test = 'xbar_directed_test';     Seeds = 2 }
    @{ Tb = 'xbar'; Test = 'xbar_random_test';       Seeds = 12 }
    @{ Tb = 'xbar'; Test = 'xbar_decerr_test';       Seeds = 4 }
    @{ Tb = 'xbar'; Test = 'xbar_id_thread_test';    Seeds = 6 }
    @{ Tb = 'xbar'; Test = 'xbar_backpressure_test'; Seeds = 4 }
    @{ Tb = 'xbar'; Test = 'xbar_slave_error_test';  Seeds = 4 }
    @{ Tb = 'xbar'; Test = 'xbar_reset_test';        Seeds = 4 }
    @{ Tb = 'xbar'; Test = 'xbar_reset_drop_test';   Seeds = 3 }
    @{ Tb = 'xbar'; Test = 'xbar_issue_limit_test';    Seeds = 3 }
    @{ Tb = 'xbar'; Test = 'xbar_decerr_backlog_test'; Seeds = 3 }
    @{ Tb = 'xbar'; Test = 'xbar_slave_skew_test';     Seeds = 3 }
    @{ Tb = 'xbar'; Test = 'xbar_smoke_test';          Seeds = 1; Cfg = 'open' }
    @{ Tb = 'xbar'; Test = 'xbar_directed_test';       Seeds = 1; Cfg = 'open' }
    @{ Tb = 'xbar'; Test = 'xbar_random_test';         Seeds = 6; Cfg = 'open' }
    @{ Tb = 'xbar'; Test = 'xbar_id_thread_test';      Seeds = 3; Cfg = 'open' }
    @{ Tb = 'xbar'; Test = 'xbar_backpressure_test';   Seeds = 2; Cfg = 'open' }
    @{ Tb = 'xbar'; Test = 'xbar_issue_limit_test';    Seeds = 3; Cfg = 'open' }
    @{ Tb = 'xbar'; Test = 'xbar_slave_skew_test';     Seeds = 2; Cfg = 'open' }
    @{ Tb = 'xbar'; Test = 'xbar_slave_error_test';    Seeds = 2; Cfg = 'open' }
    @{ Tb = 'xbar'; Test = 'xbar_decerr_lockup_test';  Seeds = 2 }
    @{ Tb = 'xbar'; Test = 'xbar_decerr_b_order_test'; Seeds = 1; Expect = 'XFAIL'; Issue = 'XBAR-01' }
    @{ Tb = 'xbar_orig'; Test = 'xbar_decerr_lockup_test'; Seeds = 1; Expect = 'XFAIL'; Issue = 'XBAR-02' }
    @{ Tb = 'xbar'; Test = 'xbar_decerr_id_order_test'; Seeds = 1; Expect = 'XFAIL'; Issue = 'XBAR-03' }
    @{ Tb = 'xbar'; Test = 'xbar_read_interleave_test'; Seeds = 1; Expect = 'XFAIL'; Issue = 'XBAR-04' }
    @{ Tb = 'xbar'; Test = 'xbar_decerr_wdata_test'; Seeds = 3 }
    @{ Tb = 'xbar_fix02'; Test = 'xbar_decerr_wdata_test'; Seeds = 1; Expect = 'XFAIL'; Issue = 'XBAR-05' }

    @{ Tb = 'dma_rd'; Test = 'dma_smoke_test';        Seeds = 1 }
    @{ Tb = 'dma_rd'; Test = 'dma_random_test';       Seeds = 12 }
    @{ Tb = 'dma_rd'; Test = 'dma_backpressure_test'; Seeds = 4 }
    @{ Tb = 'dma_rd'; Test = 'dma_throughput_test';   Seeds = 3 }
    @{ Tb = 'dma_rd'; Test = 'dma_error_test';        Seeds = 6 }
    @{ Tb = 'dma_rd'; Test = 'dma_reset_test';        Seeds = 4 }
    @{ Tb = 'dma_rd'; Test = 'dma_enable_test';       Seeds = 3 }
    @{ Tb = 'dma_rd'; Test = 'dma_field_walk_test';   Seeds = 1 }
    @{ Tb = 'dma_rd'; Test = 'dma_long_test';         Seeds = 1 }
    @{ Tb = 'dma_rd'; Test = 'dma_random_test';       Seeds = 4; Cfg = 'aligned' }
    @{ Tb = 'dma_rd'; Test = 'dma_error_test';        Seeds = 2; Cfg = 'aligned' }
    @{ Tb = 'dma_rd'; Test = 'dma_random_test';       Seeds = 4; Cfg = 'burst1' }
    @{ Tb = 'dma_rd'; Test = 'dma_error_test';        Seeds = 2; Cfg = 'burst1' }
    @{ Tb = 'dma_rd'; Test = 'dma_random_test';       Seeds = 4; Cfg = 'burst256' }
    @{ Tb = 'dma_rd'; Test = 'dma_error_test';        Seeds = 2; Cfg = 'burst256' }

    @{ Tb = 'dma_wr'; Test = 'dma_smoke_test';        Seeds = 1 }
    @{ Tb = 'dma_wr'; Test = 'dma_random_test';       Seeds = 12 }
    @{ Tb = 'dma_wr'; Test = 'dma_backpressure_test'; Seeds = 4 }
    @{ Tb = 'dma_wr'; Test = 'dma_throughput_test';   Seeds = 3 }
    @{ Tb = 'dma_wr'; Test = 'dma_error_test';        Seeds = 6 }
    @{ Tb = 'dma_wr'; Test = 'dma_reset_test';        Seeds = 4 }
    @{ Tb = 'dma_wr'; Test = 'dma_enable_test';       Seeds = 3 }
    @{ Tb = 'dma_wr'; Test = 'dma_field_walk_test';   Seeds = 1 }
    @{ Tb = 'dma_wr'; Test = 'dma_long_test';         Seeds = 1 }
    @{ Tb = 'dma_wr'; Test = 'dma_random_test';       Seeds = 4; Cfg = 'aligned' }
    @{ Tb = 'dma_wr'; Test = 'dma_error_test';        Seeds = 2; Cfg = 'aligned' }
    @{ Tb = 'dma_wr'; Test = 'dma_random_test';       Seeds = 4; Cfg = 'burst1' }
    @{ Tb = 'dma_wr'; Test = 'dma_error_test';        Seeds = 2; Cfg = 'burst1' }
    @{ Tb = 'dma_wr'; Test = 'dma_random_test';       Seeds = 4; Cfg = 'burst256' }
    @{ Tb = 'dma_wr'; Test = 'dma_error_test';        Seeds = 2; Cfg = 'burst256' }
    @{ Tb = 'dma_wr'; Test = 'dma_wr_abort_test';     Seeds = 2 }
    @{ Tb = 'dma_wr'; Test = 'dma_resp_backlog_test'; Seeds = 3 }
    @{ Tb = 'dma_wr'; Test = 'dma_wr_short_frame_split_test'; Seeds = 3 }
    @{ Tb = 'dma_wr_orig'; Test = 'dma_wr_short_frame_split_test'; Seeds = 1; Expect = 'XFAIL'; Issue = 'DMAWR-01' }

    @{ Tb = 'cdma'; Test = 'dma_smoke_test';        Seeds = 1 }
    @{ Tb = 'cdma'; Test = 'dma_random_test';       Seeds = 12 }
    @{ Tb = 'cdma'; Test = 'dma_backpressure_test'; Seeds = 4 }
    @{ Tb = 'cdma'; Test = 'dma_throughput_test';   Seeds = 3 }
    @{ Tb = 'cdma'; Test = 'dma_error_test';        Seeds = 6 }
    @{ Tb = 'cdma'; Test = 'dma_reset_test';        Seeds = 4 }
    @{ Tb = 'cdma'; Test = 'dma_enable_test';       Seeds = 3 }
    @{ Tb = 'cdma'; Test = 'dma_field_walk_test';   Seeds = 1 }
    @{ Tb = 'cdma'; Test = 'dma_long_test';         Seeds = 1 }
    @{ Tb = 'cdma'; Test = 'dma_random_test';       Seeds = 4; Cfg = 'aligned' }
    @{ Tb = 'cdma'; Test = 'dma_error_test';        Seeds = 2; Cfg = 'aligned' }
    @{ Tb = 'cdma'; Test = 'dma_random_test';       Seeds = 4; Cfg = 'burst1' }
    @{ Tb = 'cdma'; Test = 'dma_error_test';        Seeds = 2; Cfg = 'burst1' }
    @{ Tb = 'cdma'; Test = 'dma_random_test';       Seeds = 4; Cfg = 'burst256' }
    @{ Tb = 'cdma'; Test = 'dma_error_test';        Seeds = 2; Cfg = 'burst256' }

    @{ Tb = 'cdma'; Test = 'dma_cdma_offset_test';  Seeds = 3 }
    @{ Tb = 'cdma'; Test = 'dma_resp_backlog_test'; Seeds = 3 }
    @{ Tb = 'cdma_orig'; Test = 'dma_cdma_offset_test'; Seeds = 1; Expect = 'XFAIL'; Issue = 'CDMA-01' }

    # The same two defects on the unmodified upstream files (upstream_ref/).
    @{ Tb = 'cdma_up';   Test = 'dma_cdma_offset_test';          Seeds = 1; Expect = 'XFAIL'; Issue = 'CDMA-01' }
    @{ Tb = 'dma_wr_up'; Test = 'dma_wr_short_frame_split_test'; Seeds = 1; Expect = 'XFAIL'; Issue = 'DMAWR-01' }

    @{ Tb = 'sys'; Test = 'sys_smoke_test';  Seeds = 1 }
    @{ Tb = 'sys'; Test = 'sys_random_test'; Seeds = 6 }
    @{ Tb = 'sys'; Test = 'sys_decerr_test'; Seeds = 4 }
    @{ Tb = 'sys'; Test = 'sys_decerr_pipelined_test'; Seeds = 1; Expect = 'XFAIL'; Issue = 'XBAR-03' }
)


# Design groups for the coverage report: group name -> RTL design units.
$DvCovGroups = [ordered]@{
    ram  = @('axi_ram')
    xbar = @('axi_crossbar', 'axi_crossbar_addr', 'axi_crossbar_rd', 'axi_crossbar_wr', 'axi_register_rd', 'axi_register_wr', 'arbiter', 'priority_encoder')
    dma  = @('axi_dma_rd', 'axi_dma_wr', 'axi_cdma')
}
# Reference runs on the unmodified RTL of the original library (Expect = 'ORIG').
# Every test of a main testbench is repeated, with the same seeds, on the build that has no fix macros
# (crossbar) or on the unmodified upstream files (RAM, DMA engines).  The outcome is recorded as
# ORIG-PASS / ORIG-FAIL and never counts as a regression failure; it shows how much of the
# regression the original code passes.  Tests that already demonstrate a known defect are not repeated.
$DvOrigMap = @{ ram = 'ram_up'; xbar = 'xbar_orig'; dma_rd = 'dma_rd_up'; dma_wr = 'dma_wr_up'; cdma = 'cdma_up' }
$DvTests += @{ Tb = 'ram_up'; Test = 'axi_ram_wrap_test'; Seeds = 1; Expect = 'ORIG' }
# (Variable names are prefixed: this file is dot-sourced by scripts that have parameters such as -Tb,
# and PowerShell variable names are not case sensitive.)
$DvTests += foreach ($origSrc in @($DvTests)) {
    if ($origSrc.Expect -in 'XFAIL', 'ORIG' -or -not $DvOrigMap.Contains($origSrc.Tb)) { continue }
    $origTb  = $DvOrigMap[$origSrc.Tb]
    $origCfg = if ($origSrc.Cfg) { $origSrc.Cfg } else { 'default' }
    if (-not $DvTbs[$origTb].Configs.Contains($origCfg)) { continue }
    $origDup = @($DvTests | Where-Object { $_.Tb -eq $origTb -and $_.Test -eq $origSrc.Test -and ($(if ($_.Cfg) { $_.Cfg } else { 'default' }) -eq $origCfg) })
    if ($origDup.Count -gt 0) { continue }
    $origNew = @{} + $origSrc
    $origNew.Tb = $origTb; $origNew.Expect = 'ORIG'
    $origNew
}
