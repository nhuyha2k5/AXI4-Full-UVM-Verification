# AXI4 VIP – hướng dẫn sử dụng lại

`axi4_vip/` là một VIP AXI4-Full viết bằng UVM 1.2, không phụ thuộc vào DUT nào của đồ án.
Cả năm testbench trong project (RAM, crossbar, 3 DMA, hệ thống) đều dùng **cùng một bộ mã nguồn** VIP,
chỉ khác cấu hình. Tài liệu này mô tả cách đem VIP sang một project khác.

## 1. Thành phần

| File | Nội dung |
|---|---|
| `axi4_defines.svh` | Độ rộng tối đa của bus (`AXI4_ADDR_WIDTH`, `AXI4_DATA_WIDTH`, `AXI4_ID_WIDTH`, `AXI4_USER_WIDTH`), đặt bằng `+define+` khi biên dịch |
| `axi4_if.sv` | Interface 5 kênh, clocking block `cb`, SVA kiểm tra giao thức ở mức tín hiệu (lỗi báo qua `uvm_error("AXI4_SVA")`) |
| `axi4_pkg.sv` | Package chứa toàn bộ lớp bên dưới |
| `axi4_types.sv`, `axi4_burst_utils.sv` | Kiểu dữ liệu, hàm tính địa chỉ từng beat, byte lane, kiểm tra 4KB |
| `axi4_agent_cfg.sv` | Cấu hình của một cổng AXI (một object cho mỗi agent) |
| `axi4_seq_item.sv` | Transaction (1 burst), ràng buộc hợp lệ theo AXI4 |
| `axi4_master_driver.sv` | Driver master có pipeline: 5 kênh độc lập, nhiều giao dịch outstanding |
| `axi4_slave_driver.sv` | Driver slave phản ứng (reactive) có bộ nhớ, backpressure, trễ, đổi thứ tự, xen kẽ, lỗi |
| `axi4_monitor.sv` | Monitor + bộ kiểm tra giao thức mức transaction (id `AXI_PROTOCOL`), log mỗi giao dịch một dòng (`AXI_TXN`) |
| `axi4_coverage.sv` | Functional coverage theo từng hướng ghi/đọc, phạm vi bật tắt bằng cfg |
| `axi4_mem_model.sv` | Bộ nhớ thưa theo byte dùng cho slave và làm mô hình tham chiếu |
| `axi4_mem_scoreboard.sv` | Scoreboard cho DUT kiểu bộ nhớ (so từng byte, hiểu strobe, ghi chồng lấn, reset) |
| `axi4_seq_lib.sv` | Thư viện sequence |
| `axi4_agent.sv`, `axi4_sequencer.sv` | Agent (master / slave / passive) |

## 2. Ba vai trò của agent

```systemverilog
cfg.role = AXI4_MASTER_AGENT;   // sequencer + master driver + monitor   -> lái cổng slave của DUT
cfg.role = AXI4_SLAVE_AGENT;    // slave driver có bộ nhớ + monitor      -> đáp cổng master của DUT
cfg.role = AXI4_PASSIVE_AGENT;  // chỉ monitor/checker/coverage           -> gắn vào bus nội bộ
```

Trong project: RAM dùng 1 master; crossbar dùng 2 master + 3 slave; DMA dùng 1 slave; testbench hệ thống
dùng 1 master và 4 agent passive.

## 3. Kết nối vào một DUT mới

**Bước 1 – filelist.** Chọn độ rộng tối đa mà testbench cần (mọi cổng dùng chung một kiểu `virtual axi4_if`):

```
+incdir+axi4_vip
+define+AXI4_ADDR_WIDTH=32
+define+AXI4_DATA_WIDTH=32
+define+AXI4_ID_WIDTH=8
+define+AXI4_USER_WIDTH=1
axi4_vip/axi4_if.sv
axi4_vip/axi4_pkg.sv
```

**Bước 2 – top.** Tạo interface, nối vào DUT, đưa handle vào `uvm_config_db`:

```systemverilog
axi4_if bus(.ACLK(clk), .ARESETn(rst_n));
my_dut dut(.s_axi_awid(bus.AWID[ID_W-1:0]), .s_axi_awaddr(bus.AWADDR), /* ... */);
assign bus.BUSER = '0;                       // tín hiệu DUT không có thì gán hằng
initial uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "bus_vif", bus);
```

Cổng DUT hẹp hơn độ rộng biên dịch thì cắt bit ở top và khai báo độ rộng thật trong cfg
(`cfg.addr_width`, `cfg.id_width`, `cfg.user_width`) để VIP không sinh / không kiểm tra các bit thừa.

**Bước 3 – env.**

```systemverilog
cfg = axi4_agent_cfg::type_id::create("cfg");
cfg.name = "cpu"; cfg.role = AXI4_MASTER_AGENT; cfg.vif = vif;
agent = axi4_agent::type_id::create("agent", this);
agent.cfg = cfg;                      // hoặc uvm_config_db#(axi4_agent_cfg)::set(this, "agent", "cfg", cfg)
...
agent.ap.connect(my_scoreboard.analysis_export);        // giao dịch đã hoàn tất
agent.addr_ap.connect(my_scoreboard.addr_export);       // pha địa chỉ vừa được chấp nhận (nếu cần)
```

**Bước 4 – test.** Chạy sequence trên `agent.sequencer`:

```systemverilog
axi4_rand_seq s = axi4_rand_seq::type_id::create("s");
s.num_txn = 200; s.wr_pct = 60; s.max_len = 15;
s.add_window(32'h0000_0000, 32'h0000_FFFF);   // vùng địa chỉ được phép
s.start(env.agent.sequencer);
```

## 4. Các núm cấu hình chính (`axi4_agent_cfg`)

Mọi núm đều đổi được trong lúc test đang chạy.

| Nhóm | Núm | Ý nghĩa |
|---|---|---|
| Master | `max_wr_outstanding`, `max_rd_outstanding` | số giao dịch đang bay tối đa |
| | `aw_delay_max`, `w_delay_max`, `ar_delay_max`, `zero_delay_pct` | trễ ngẫu nhiên trước khi kéo VALID |
| | `bready_pct`, `rready_pct` | xác suất READY mỗi chu kỳ (backpressure phía master) |
| | `w_follows_aw` | 1: dữ liệu ghi chỉ bắt đầu sau khi AW đã bắt tay |
| Slave | `awready_pct`, `wready_pct`, `arready_pct` | backpressure phía slave |
| | `b_delay_max`, `r_delay_max`, `r_beat_delay_max` | trễ đáp ứng |
| | `b_reorder`, `rd_reorder`, `rd_interleave` | đổi thứ tự / xen kẽ giữa các ID (vẫn giữ thứ tự trong cùng ID) |
| | `wr_resp`, `rd_resp`, `rd_resp_beat`, `add_error_range()` | trả SLVERR/DECERR toàn cục, theo beat, hoặc theo vùng địa chỉ |
| | `mem` | bộ nhớ của slave (có thể chia sẻ với scoreboard) |
| | `inj_early_rlast`, `inj_wrong_bid`, `inj_no_b`, `inj_no_r` | tiêm lỗi giao thức để kiểm chứng chính checker |
| Chung | `randomize_idle` | đặt giá trị ngẫu nhiên lên payload khi VALID thấp (bắt DUT dùng payload không kèm VALID) |
| | `enable_checker`, `enable_coverage`, `log_txn`, `timeout_cycles`, `allow_pending_at_end` | kiểm tra / log / watchdog |
| Coverage | `cov_wr`, `cov_rd`, `cov_long_bursts`, `cov_fixed`, `cov_wrap`, `cov_narrow`, `cov_unaligned`, `cov_err_resp`, `cov_multi_id`, `cov_outstanding`, `cov_sideband`, `cov_prot`, `cov_qos`, `cov_sparse_strb`, `cov_aw/ar/w/r/b_nostall` | chỉ tạo bin cho những hành vi mà cổng này **có thể** thể hiện |

`cfg.set_backpressure(ready_pct, delay_max)` đặt cùng một mức cho mọi kênh.

Monitor cho phép test hỏi trạng thái bus: `agent.monitor.num_wr_outstanding()`, `num_rd_outstanding()`
(số giao dịch đã nhận địa chỉ nhưng chưa xong đáp ứng) và các bộ đếm `n_wr`, `n_rd`, `n_err_resp`,
`max_wr_out`, `max_rd_out`, `n_resets`.

## 5. Thư viện sequence

| Sequence | Mục đích |
|---|---|
| `axi4_base_seq` | lớp cơ sở: `do_write()`, `do_read()`, `issue()`, `wait_all()` |
| `axi4_rand_seq` | lưu lượng ngẫu nhiên có ràng buộc; các núm `num_txn, wr_pct, pipelined, max_len, use_fixed/incr/wrap, narrow, unaligned, sideband, sparse_pct, idle_max, id_lo/hi`, `add_window()`; hàm ảo `tweak()` để lớp con chỉnh từng item |
| `axi4_write_read_seq` | ghi rồi đọc lại đúng vùng vừa ghi |
| `axi4_4k_boundary_seq` | burst INCR kết thúc sát biên 4KB |
| `axi4_wrap_seq` | burst WRAP mọi độ dài hợp lệ, có quấn địa chỉ |
| `axi4_max_burst_seq` | burst 256 beat |
| `axi4_region_read_seq` | đọc quét một vùng |
| `axi4_addr_walk_seq`, `axi4_data_walk_seq` | walking-1/0 trên địa chỉ và dữ liệu |

## 6. Những gì VIP tự kiểm tra

* **SVA trong interface**: VALID giữ ổn định tới khi READY, payload ổn định và không X khi VALID, luật burst
  (WRAP 2/4/8/16 beat và địa chỉ thẳng hàng, FIXED ≤ 16 beat, INCR không vượt 4KB), VALID thấp trong reset.
* **Monitor**: số beat và vị trí WLAST/RLAST, BID/RID phải khớp một giao dịch đang chờ (đáp ứng được ghép với
  giao dịch cũ nhất của ID đó), đáp ứng không được đến trước yêu cầu (B trước beat W cuối, R trước AR), không có EXOKAY khi không exclusive,
  X trên các byte lane hợp lệ, watchdog theo `timeout_cycles`, giao dịch còn treo khi kết thúc test.
* **`axi4_mem_scoreboard`**: so sánh dữ liệu đọc từng byte với bộ nhớ tham chiếu, theo strobe; xử lý đúng các
  lần ghi chồng lấn đang bay; mọi đáp ứng phải là OKAY trừ khi testbench khai báo khác.

Bản thân VIP được kiểm chứng bằng `tb/tb_vip` (master nối thẳng slave, không DUT): 4 test chức năng và
3 test âm (tiêm RLAST sớm, BID sai, không đáp ứng) để chứng minh checker thực sự bắt được lỗi.

## 7. Giới hạn hiện tại

* Chỉ AXI4 (không có AXI3 WID / write interleaving), không hỗ trợ truy cập exclusive (AxLOCK chỉ được lái như
  tín hiệu phụ, không có mô hình exclusive monitor).
* Một cấu hình độ rộng dữ liệu cho mỗi lần biên dịch (`AXI4_DATA_WIDTH`); độ rộng địa chỉ / ID / user có thể
  khác nhau theo từng agent.
* Master driver không tự tiêm lỗi giao thức (chỉ slave có `inj_*`).
* Chưa có AXI4-Lite và AXI4-Stream trong VIP (`tb/common/axis_pkg.sv` là agent AXI-Stream nhỏ dùng riêng cho
  testbench DMA, không thuộc VIP).
