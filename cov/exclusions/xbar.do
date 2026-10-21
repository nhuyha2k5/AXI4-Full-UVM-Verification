# Coverage exclusions for axi_crossbar and its sub-modules (dut/axi_ram/).
# Applied by scripts/cov_report.ps1 to the merged UCDB.  Every item is unreachable for the
# reason given with it; nothing is excluded because it was merely hard to hit.  Coverage
# is reported both without and with this file.
#
# Verified configuration: 2 masters x 3 slaves, 3 address regions per slave, 32-bit
# address and data (tb/tb_xbar/xbar_cfg_pkg.sv), builds "default" and "open".  Items
# marked [CONFIG] are unreachable in this configuration only.

# ==============================================================================
# Elaboration-time code
# ==============================================================================
# calcBaseAddrs is a constant function.  It is called only in the initial value of the
# localparam M_BASE_ADDR_INT (and only when M_BASE_ADDR is 0), i.e. during elaboration;
# no simulation event ever executes its body.
coverage exclude -du axi_crossbar_addr -srcfile dut/axi_ram/axi_crossbar_addr.v -linerange 127-138 -comment "constant function calcBaseAddrs: evaluated at elaboration only"
# Parameter sanity checks in initial blocks.  Their "true" side prints an error and calls
# $finish at time 0, so it can only run with an illegal parameter set, which ends the
# simulation before any test starts.
coverage exclude -du axi_crossbar_addr -srcfile dut/axi_ram/axi_crossbar_addr.v -linerange 170-172 -comment "parameter check: address width out of range ends the simulation"
coverage exclude -du axi_crossbar_addr -srcfile dut/axi_ram/axi_crossbar_addr.v -linerange 190-200 -comment "parameter check: region not aligned ends the simulation"
coverage exclude -du axi_crossbar_addr -srcfile dut/axi_ram/axi_crossbar_addr.v -linerange 207-225 -comment "parameter check: overlapping regions ends the simulation"
coverage exclude -du axi_crossbar_rd -srcfile dut/axi_ram/axi_crossbar_rd.v -linerange 163-165 -comment "parameter check: address width out of range ends the simulation"
coverage exclude -du axi_crossbar_wr -srcfile dut/axi_ram/axi_crossbar_wr.v -linerange 181-183 -comment "parameter check: address width out of range ends the simulation"

# ==============================================================================
# Not hardware
# ==============================================================================
# Integer loop indices of the initial blocks and of the combinational address-decode loop.
coverage exclude -du axi_crossbar_addr -togglenode {i} -comment "integer loop index, not a design signal"
coverage exclude -du axi_crossbar_addr -togglenode {j} -comment "integer loop index, not a design signal"
coverage exclude -du axi_crossbar_rd -togglenode {i} -comment "integer loop index of the parameter-check initial block"
coverage exclude -du axi_crossbar_wr -togglenode {i} -comment "integer loop index of the parameter-check initial block"

# ==============================================================================
# axi_crossbar_addr
# ==============================================================================
# state_reg is declared 3 bits wide but only STATE_IDLE (0) and STATE_DECODE (1) exist.
coverage exclude -du axi_crossbar_addr -togglenode {state_reg[1]} -comment "only the state values 0 and 1 are ever assigned"
coverage exclude -du axi_crossbar_addr -togglenode {state_reg[2]} -comment "only the state values 0 and 1 are ever assigned"
coverage exclude -du axi_crossbar_addr -togglenode {state_next[1]} -comment "only the state values 0 and 1 are ever assigned"
coverage exclude -du axi_crossbar_addr -togglenode {state_next[2]} -comment "only the state values 0 and 1 are ever assigned"
coverage exclude -du axi_crossbar_addr -srcfile dut/axi_ram/axi_crossbar_addr.v -linerange 331 -allfalse -comment "state_reg only ever holds the two listed states"
# In the read-address instances (WC_OUTPUT = 0) m_wc_valid_reg is never set and the port
# m_wc_valid is left unconnected.  (In the write-address instances the port is merged with
# the net of the parent module; the register m_wc_valid_reg itself is fully covered.)
coverage exclude -du axi_crossbar_addr -togglenode {m_wc_valid} -comment "unconnected and constant 0 in the read-address instances (WC_OUTPUT=0)"

# ==============================================================================
# [CONFIG] AxREGION bits 3:2
# ==============================================================================
# AxREGION carries the index of the matching address region.  With M_REGIONS = 3 the index
# is 0, 1 or 2, so bits 3:2 are 0 everywhere a region value is generated or forwarded.
coverage exclude -du axi_crossbar_addr -togglenode {m_axi_aregion_reg[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_addr -togglenode {m_axi_aregion_reg[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_addr -togglenode {m_axi_aregion_next[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_addr -togglenode {m_axi_aregion_next[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_rd -togglenode {int_s_axi_arregion[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_rd -togglenode {int_s_axi_arregion[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_rd -togglenode {int_s_axi_arregion[6]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_rd -togglenode {int_s_axi_arregion[7]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_rd -togglenode {m_ifaces[0]/s_axi_arregion_mux[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_rd -togglenode {m_ifaces[0]/s_axi_arregion_mux[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_rd -togglenode {m_ifaces[1]/s_axi_arregion_mux[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_rd -togglenode {m_ifaces[1]/s_axi_arregion_mux[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_rd -togglenode {m_ifaces[2]/s_axi_arregion_mux[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_rd -togglenode {m_ifaces[2]/s_axi_arregion_mux[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_wr -togglenode {int_s_axi_awregion[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_wr -togglenode {int_s_axi_awregion[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_wr -togglenode {int_s_axi_awregion[6]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_wr -togglenode {int_s_axi_awregion[7]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_wr -togglenode {m_ifaces[0]/s_axi_awregion_mux[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_wr -togglenode {m_ifaces[0]/s_axi_awregion_mux[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_wr -togglenode {m_ifaces[1]/s_axi_awregion_mux[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_wr -togglenode {m_ifaces[1]/s_axi_awregion_mux[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_wr -togglenode {m_ifaces[2]/s_axi_awregion_mux[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar_wr -togglenode {m_ifaces[2]/s_axi_awregion_mux[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar -togglenode {m_axi_arregion[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar -togglenode {m_axi_arregion[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar -togglenode {m_axi_arregion[6]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar -togglenode {m_axi_arregion[7]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar -togglenode {m_axi_arregion[10]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar -togglenode {m_axi_arregion[11]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar -togglenode {m_axi_awregion[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar -togglenode {m_axi_awregion[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar -togglenode {m_axi_awregion[6]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar -togglenode {m_axi_awregion[7]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar -togglenode {m_axi_awregion[10]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_crossbar -togglenode {m_axi_awregion[11]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_register_rd -togglenode {genblk1/m_axi_arregion_reg[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_register_rd -togglenode {genblk1/m_axi_arregion_reg[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_register_rd -togglenode {genblk1/temp_m_axi_arregion_reg[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_register_rd -togglenode {genblk1/temp_m_axi_arregion_reg[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_register_wr -togglenode {genblk1/m_axi_awregion_reg[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_register_wr -togglenode {genblk1/m_axi_awregion_reg[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_register_wr -togglenode {genblk1/temp_m_axi_awregion_reg[2]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
coverage exclude -du axi_register_wr -togglenode {genblk1/temp_m_axi_awregion_reg[3]} -comment "CONFIG-LIMITED: region index <= 2 with M_REGIONS = 3"
# The register slices on the slave-interface side sit in front of the address decoder:
# their region input is tied to 4'd0 and their region output is left unconnected.
coverage exclude -du axi_register_rd -togglenode {m_axi_arregion} -comment "S-side instances: input tied to 4'd0, output unconnected (the M-side instances are covered through the parent net)"
coverage exclude -du axi_register_wr -togglenode {m_axi_awregion} -comment "S-side instances: input tied to 4'd0, output unconnected (the M-side instances are covered through the parent net)"

# ==============================================================================
# arbiter
# ==============================================================================
# Every instance uses ARB_LSB_HIGH_PRIORITY = 1: mask_next = {PORTS{1'b1}} << (index + 1),
# so bit 0 of the round-robin mask, and of the request vector masked with it, is always 0.
coverage exclude -du arbiter -togglenode {mask_next[0]} -comment "all-ones shifted left by at least 1: bit 0 is always 0"
coverage exclude -du arbiter -togglenode {mask_reg[0]} -comment "all-ones shifted left by at least 1: bit 0 is always 0"
coverage exclude -du arbiter -togglenode {masked_request_mask[0]} -comment "request ANDed with mask_reg, whose bit 0 is always 0"

# ==============================================================================
# Condition / expression rows that cannot occur
# ==============================================================================
# (1) A granted request cannot go away.  The arbiters hold a grant until it is acknowledged
# (ARB_BLOCK, ARB_BLOCK_ACK) and the granted VALID is a registered AXI valid that stays
# high until that same acknowledge.  Grant and valid therefore fall at the same clock edge
# and the row "granted, valid = 0" does not exist in a settled cycle.
coverage exclude -du axi_crossbar_rd -srcfile dut/axi_ram/axi_crossbar_rd.v -fecexprrow 511 3 -comment "a granted AR request stays valid until it is acknowledged"
coverage exclude -du axi_crossbar_rd -srcfile dut/axi_ram/axi_crossbar_rd.v -fecexprrow 366 3 -comment "the DECERR read response stays valid while it holds the grant"
coverage exclude -du axi_crossbar_wr -srcfile dut/axi_ram/axi_crossbar_wr.v -fecexprrow 584 3 -comment "a granted AW request stays valid until it is acknowledged"
coverage exclude -du axi_crossbar_wr -srcfile dut/axi_ram/axi_crossbar_wr.v -fecexprrow 420 3 -comment "a granted B response stays valid until it is acknowledged"
coverage exclude -du axi_crossbar_wr -srcfile dut/axi_ram/axi_crossbar_wr.v -fecexprrow 424 3 -comment "the DECERR write response stays valid while it holds the grant"
# (2) Redundant term: s_axi_a*valid_mux already contains "&& a_grant_valid", so
# "valid_mux && ready_mux && a_grant_valid" cannot have a_grant_valid = 0 with valid_mux = 1.
coverage exclude -du axi_crossbar_rd -srcfile dut/axi_ram/axi_crossbar_rd.v -fecexprrow 514 5 -comment "a_grant_valid is already part of s_axi_arvalid_mux"
coverage exclude -du axi_crossbar_wr -srcfile dut/axi_ram/axi_crossbar_wr.v -fecexprrow 587 5 -comment "a_grant_valid is already part of s_axi_awvalid_mux"
# (3) "else if (m_rc_valid && m_rc_ready)" is the else of "if (decerr_m_axi_*valid_reg)" and
# m_rc_ready is defined as !decerr_m_axi_*valid_reg: where the condition is evaluated,
# m_rc_ready is always 1.
coverage exclude -du axi_crossbar_rd -srcfile dut/axi_ram/axi_crossbar_rd.v -feccondrow 304 3 -comment "m_rc_ready = !decerr_m_axi_rvalid_reg is 1 in this else branch"
coverage exclude -du axi_crossbar_wr -srcfile dut/axi_ram/axi_crossbar_wr.v -feccondrow 368 3 -comment "m_rc_ready = !decerr_m_axi_bvalid_reg is 1 in this else branch"
