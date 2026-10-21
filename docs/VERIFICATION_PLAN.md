# Kế hoạch kiểm chứng (Verification Plan)

Đối tượng: `axi_ram`, `axi_crossbar` (và các khối con), `axi_dma_rd`, `axi_dma_wr`, `axi_cdma`.
Công cụ: QuestaSim 10.7c, UVM 1.2. Kết quả chạy thật nằm ở `reports/` (sinh tự động, không gõ tay).

## 1. Chiến lược

| Tầng | Testbench | DUT | Thành phần VIP | Bộ so sánh (checker) |
|---|---|---|---|---|
| VIP | `tb/tb_vip` | không có (master ↔ slave) | 1 master, 1 slave | `axi4_mem_scoreboard`, monitor, SVA |
| Khối | `tb/tb_ram` | `axi_ram` | 1 master | `axi4_mem_scoreboard` (bộ nhớ tham chiếu theo byte) |
| Khối | `tb/tb_xbar` | `axi_crossbar` 2 master × 3 slave | 2 master, 3 slave | `xbar_scoreboard` (mô hình giải mã địa chỉ `xbar_decode`, so từng giao dịch theo tuyến, kiểm tra DECERR); `xbar_limit_checker` (giới hạn `M_ISSUE` / `S_ACCEPT` từng chu kỳ) |
| Khối | `tb/tb_dma` (3 top) | `axi_dma_rd`, `axi_dma_wr`, `axi_cdma` | 1 slave (bộ nhớ) + agent descriptor + agent AXI-Stream | `dma_scoreboard` (từng byte stream ↔ AXI, độ dài, tag/id/dest/user, mã lỗi status, tính hợp lệ của burst) |
| Hệ thống | `tb/tb_sys` | VIP master "cpu" + `axi_cdma` → `axi_crossbar` 2×2 → 2 × `axi_ram` | 1 master, 4 passive | `axi4_mem_scoreboard` cho cpu và cho DMA (chung một bộ nhớ tham chiếu), `dma_scoreboard` |

Mọi cổng AXI trong mọi testbench đều có monitor kiểm tra giao thức và SVA trong `axi4_if`.

Nguyên tắc:

1. **Tự kiểm tra hoàn toàn.** Một test chỉ PASS khi log có `TEST_RESULT: PASSED`, `UVM_ERROR : 0`,
   `UVM_FATAL : 0`, không có dòng lỗi của simulator, **và** số phép so sánh của scoreboard ≥ ngưỡng tối thiểu
   của test (`min_checks`) – test không so sánh gì thì FAIL.
2. **Ngẫu nhiên có ràng buộc + nhiều seed** cho phần lớn không gian; **test directed** cho các góc mà ngẫu
   nhiên khó chạm (đọc từ báo cáo coverage).
3. **Nhiều cấu hình tham số** của DUT được build riêng và merge coverage.
4. **Trung thực về coverage**: chỉ các lần chạy PASS mới được merge; chỉ loại trừ (exclude) những mục chứng
   minh được là không thể đạt, mỗi mục có lý do; báo cáo luôn đưa cả hai con số *trước* và *sau* loại trừ.
5. **Lỗi DUT không bị che.** Lỗi thiết kế tìm được có test minh hoạ riêng đánh dấu `XFAIL`
   (xem `docs/KNOWN_ISSUES.md`); nếu một test XFAIL bỗng PASS thì regression báo `XPASS` = thất bại.

## 2. Cấu hình build

| Testbench | Cấu hình | Tham số | Ghi chú |
|---|---|---|---|
| `ram` | `default` / `pipe` / `init` | `PIPELINE_OUTPUT=0` / `=1` / `INIT_FILE=ram_init.hex` | |
| `xbar` | `default` / `open` | `default`: có tuyến bị cắt + slave secure, `M_ISSUE` = 4/2/1 cho slave 0/1/2; `open`: mọi tuyến đều nối, không secure, `M_ISSUE` = 1/4/2 | RTL có 5 sửa lỗi tuỳ chọn XBAR-02, -05, -06, -07, -08 |
| `xbar_orig`, `xbar_fix02`, `xbar_fix06`, `xbar_fix07` | `default` (`xbar_fix07`: thêm `open`) | RTL gốc / chỉ sửa XBAR-02 / sửa -02, -05, -06 / sửa tất cả trừ XBAR-08 | chỉ để chạy test minh hoạ lỗi |
| `dma_rd`, `dma_wr`, `cdma` | `default` / `aligned` / `burst1` / `burst256` | `ENABLE_UNALIGNED=1,MAX_BURST_LEN=16` / `ENABLE_UNALIGNED=0` / `MAX_BURST_LEN=1` / `=256` | `dma_wr`, `cdma` có sửa lỗi tuỳ chọn DMAWR-01, CDMA-01 |
| `dma_wr_orig`, `cdma_orig` | `default` | RTL gốc (bản của project) | chỉ để chạy test minh hoạ lỗi |
| `ram_up`, `dma_rd_up`, `dma_wr_up`, `cdma_up` | như testbench chính tương ứng (`ram_up`: không có `init`) | file **nguyên vẹn** tải từ kho của tác giả (`upstream_ref/`) | chạy lại toàn bộ test chính (kết quả `ORIG-PASS`/`ORIG-FAIL`, không tính vào regression) và các test minh hoạ lỗi CDMA-01, DMAWR-01 |
| `xbar_orig` | `default` / `open` | RTL crossbar không định nghĩa macro nào (giống hệt mã gốc) | ngoài test minh hoạ XBAR-02, XBAR-06, còn chạy lại toàn bộ test chính ở dạng `ORIG` |
| `sys` | `default` | crossbar 2×2, 2 RAM 64KB (một có `PIPELINE_OUTPUT=1`) | coverage báo riêng, không cộng vào số liệu mức khối |

## 3. Tính năng → test

### 3.1 `axi_ram`

| Tính năng | Test |
|---|---|
| Ghi / đọc cơ bản | `axi_ram_smoke_test` |
| Mọi bit địa chỉ và dữ liệu, biên 4KB, burst 256 beat, FIXED | `axi_ram_directed_test` |
| Mọi kiểu burst, size, lệch địa chỉ, strobe thưa | `axi_ram_write_read_test` |
| Ghi/đọc đồng thời có pipeline, backpressure ngẫu nhiên | `axi_ram_random_test` (random) |
| Giữ đáp ứng khi master chưa sẵn sàng | `axi_ram_backpressure_test` (random) |
| Reset giữa burst | `axi_ram_reset_test` (random) |
| `PIPELINE_OUTPUT=1` | các test trên với cấu hình `pipe` |
| `INIT_FILE` | `axi_ram_init_file_test` (cấu hình `init`) |
| Burst WRAP | `axi_ram_wrap_test` – **XFAIL, RAM-01** |

### 3.2 `axi_crossbar`

| Tính năng | Test |
|---|---|
| Mọi master tới mọi vùng của mọi slave được nối | `xbar_smoke_test` (PASS; **XFAIL XBAR-07** trên build `xbar_fix06`) |
| Kiểu register slice đúng như tham số `M_*_REG_TYPE` | `xbar_param_test` (PASS với sửa lỗi; **XFAIL XBAR-06** trên RTL gốc) |
| Mọi bit địa chỉ/dữ liệu, burst 256 beat, WRAP, biên 4KB, ID toàn 0 / toàn 1 qua crossbar | `xbar_directed_test` |
| Định tuyến + phân xử đồng thời, backpressure ngẫu nhiên | `xbar_random_test` (random) |
| DECERR: địa chỉ không ánh xạ, slave secure, tuyến không nối | `xbar_decerr_test` (random) |
| Thứ tự cùng ID tới nhiều slave, giới hạn `S_THREADS` / `S_ACCEPT` / `M_ISSUE` | `xbar_id_thread_test`, `xbar_issue_limit_test` (random; PASS với sửa lỗi, **XFAIL XBAR-08** trên build `xbar_fix07`); `xbar_limit_checker` chạy trong **mọi** test |
| Register slice và mux giữ dữ liệu khi bị chặn | `xbar_backpressure_test` (random) |
| Đáp ứng lỗi của slave về đúng master | `xbar_slave_error_test` (random) |
| Reset giữa lưu lượng | `xbar_reset_test` (random) |
| Reset giữa lúc đang bỏ dữ liệu của một lần ghi DECERR, rồi ghi với dữ liệu đi trước địa chỉ | `xbar_reset_drop_test` |
| AW và W tới slave lệch nhau theo cả hai chiều | `xbar_slave_skew_test` (random) |
| Hàng đợi DECERR khi master nhận chậm | `xbar_decerr_backlog_test` (random) |
| Sau DECERR master vẫn dùng được mọi slave | `xbar_decerr_lockup_test` (PASS với sửa lỗi; **XFAIL XBAR-02** trên RTL gốc) |
| Dữ liệu ghi sau một lần ghi bị DECERR | `xbar_decerr_wdata_test` (PASS với sửa lỗi; **XFAIL XBAR-05** khi chưa sửa) |
| B của DECERR phải sau dữ liệu ghi | `xbar_decerr_b_order_test` – **XFAIL XBAR-01** |
| DECERR giữ thứ tự trong cùng ID | `xbar_decerr_id_order_test` – **XFAIL XBAR-03** |
| Slave xen kẽ dữ liệu đọc giữa các ID | `xbar_read_interleave_test` – **XFAIL XBAR-04** |
| Cấu hình `open` (mọi tuyến nối, giới hạn `M_ISSUE` hoán vị) | param, smoke, directed, random, id_thread, backpressure, issue_limit, slave_skew, slave_error |

### 3.3 DMA (`axi_dma_rd`, `axi_dma_wr`, `axi_cdma`)

| Tính năng | Test |
|---|---|
| Truyền ngắn và nhiều burst | `dma_smoke_test` |
| Mọi lớp độ dài (quanh 1 word, 1 burst, 4KB), địa chỉ lệch, descriptor nối đuôi, backpressure | `dma_random_test` (random) |
| Bộ nhớ / stream hiếm khi sẵn sàng | `dma_backpressure_test` (random) |
| 4 tổ hợp nhanh/chậm của bộ nhớ và stream | `dma_throughput_test` (random) |
| SLVERR / DECERR → mã lỗi trong status, engine chạy tiếp | `dma_error_test` (random) |
| Reset giữa lúc truyền (thời điểm ngẫu nhiên, quét 0..5 chu kỳ sau khi nhận descriptor, lúc đang chờ dữ liệu stream) | `dma_reset_test` (random) |
| `enable` = 0 trước khi nhận descriptor và đổi ngẫu nhiên giữa lúc truyền | `dma_enable_test` (random) |
| Đáp ứng ghi bị giữ lại: engine dừng đúng ở 32 burst chưa được đáp ứng rồi chạy tiếp (`axi_dma_wr`, `axi_cdma`) | `dma_resp_backlog_test` |
| Mọi bit của các trường descriptor | `dma_field_walk_test` |
| Độ dài gần cực đại (2^20−1 byte) | `dma_long_test` |
| Mọi tổ hợp lệch nguồn/đích của `axi_cdma` | `dma_cdma_offset_test` (PASS với sửa lỗi; **XFAIL CDMA-01** trên RTL gốc) |
| Frame ngắn hơn descriptor, beat cuối bị tách qua 2 burst (`axi_dma_wr`) | `dma_wr_short_frame_split_test` (PASS với sửa lỗi; **XFAIL DMAWR-01** trên RTL gốc) |
| Ngõ vào `abort` của `axi_dma_wr` | `dma_wr_abort_test` (ghi nhận giới hạn DMA-01: không có tác dụng) |
| `ENABLE_UNALIGNED=0`, `AXI_MAX_BURST_LEN=1`, `=256` | random + error với cấu hình `aligned`, `burst1`, `burst256` |

### 3.4 Hệ thống

| Tính năng | Test |
|---|---|
| cpu ghi RAM0 → DMA chép sang RAM1 → cpu đọc lại | `sys_smoke_test` |
| cpu và DMA dùng đồng thời cả hai RAM qua crossbar | `sys_random_test` (random) |
| Descriptor trỏ ra ngoài bản đồ địa chỉ → status DECERR, hệ thống chạy tiếp (từng descriptor một) | `sys_decerr_test` |
| Descriptor lỗi nối đuôi descriptor hợp lệ: mã lỗi phải nằm đúng status | `sys_decerr_pipelined_test` – **XFAIL XBAR-03** |

## 4. Functional coverage

| Nơi | Covergroup | Nội dung |
|---|---|---|
| VIP, mỗi cổng, mỗi hướng | `axi4_cg_len_short/long`, `burst`, `wrap`, `size`, `align`, `resp`, `id`, `outstanding(_deep)`, `sideband`, `prot`, `qos`, `stall`, `bstall`, `nostall`, `strobe` | hình dạng burst, đáp ứng, độ sâu outstanding, backpressure (có / không bị chặn) trên từng kênh |
| Crossbar | `cg_route` | master × hướng × slave; slave × vùng địa chỉ |
| | `cg_decerr` | nguyên nhân DECERR (không ánh xạ / secure / tuyến không nối) × hướng; không ánh xạ theo từng master × hướng |
| | `cg_contention` | slave × hướng × (một master / cả hai master cùng tranh) |
| DMA | `dma_cg_shape` | lớp độ dài, số burst (1 / 2 / nhiều), có vượt biên 4KB hay không |
| | `dma_cg_align` | lệch đầu × lệch cuối; lệch đầu × (truyền trong một word / dài hơn) |
| | `dma_cg_rd_error`, `dma_cg_wr_error` | mã lỗi trong status |
| | `dma_cg_frame` | (`axi_dma_wr`) frame ngắn hơn / bằng / dài hơn descriptor |

Bin chỉ được tạo cho hành vi mà cổng đó có thể thể hiện (các núm `cov_*` trong `axi4_agent_cfg`); ví dụ cổng
của `axi_ram` không có bin đáp ứng lỗi vì RAM không bao giờ trả lỗi, và một kênh đáp ứng đi qua register slice
kiểu bypass của crossbar không có bin "không bị chặn chu kỳ nào" vì READY chỉ đến sau khi bộ phân xử cấp quyền.
Mỗi lần thu hẹp phạm vi như vậy đều có chú thích lý do ngay tại chỗ đặt núm trong mã testbench.

## 5. Code coverage và tiêu chí hoàn thành

* Loại đo: statement, branch, FEC condition, FEC expression, FSM, toggle (`+cover=bcesft`, chỉ trên RTL).
* "Total" = số *Total Coverage By Design Unit* của QuestaSim (trung bình các loại trên) cho từng nhóm:
  `ram` = `axi_ram`; `xbar` = `axi_crossbar`, `axi_crossbar_addr`, `axi_crossbar_rd`, `axi_crossbar_wr`,
  `axi_register_rd`, `axi_register_wr`, `arbiter`, `priority_encoder`; `dma` = `axi_dma_rd`, `axi_dma_wr`, `axi_cdma`.
* Mục tiêu: Total ≥ 98 % cho từng nhóm sau loại trừ có lý do; regression 0 FAIL, 0 XPASS.
* Kiểm tra cổng: `scripts\cov_report.ps1 -MinTotal 98` trả mã lỗi nếu một nhóm không đạt.
* Danh sách loại trừ: `cov/exclusions/*.do`; những gì còn thiếu sau loại trừ: `reports/coverage_<nhóm>_holes.txt`.
* Báo cáo đưa **ba con số** cho mỗi nhóm để thấy rõ ảnh hưởng của loại trừ:
  1. *none* – số thô của regression, không loại trừ gì;
  2. *unreachable only* – bỏ các mục không kích thích nào đạt được trong bất kỳ cấu hình nào (biến vòng lặp
     `integer`, tín hiệu gán hằng, mã chỉ chạy lúc elaboration, kiểm tra tham số gọi `$finish`, hàng điều kiện
     mâu thuẫn về cấu trúc);
  3. *unreachable + configuration-limited* – bỏ thêm các mục gắn nhãn `CONFIG-LIMITED`: chỉ không đạt được vì cấu
     hình đã kiểm chứng (bus dữ liệu 32 bit, 3 vùng địa chỉ mỗi slave). Cổng 98 % áp dụng cho con số này.
* Quy trình đóng coverage đã dùng: đọc từng lỗ → nếu có kích thích hợp lệ nào chạm được thì **viết test**
  (ví dụ: giữ đáp ứng B để chạm giới hạn 32 burst của DMA, reset đúng chu kỳ sau khi nhận descriptor, `TLAST`
  ngẫu nhiên khi `TVALID` thấp, hoán vị `M_ISSUE`) → chỉ khi chứng minh được bằng RTL là không thể đạt mới loại trừ.
  Hai lỗ coverage "không giải thích được" đã dẫn tới việc tìm ra lỗi thiết kế XBAR-06/07 và XBAR-08.
* Coverage thu với thiết lập mặc định của QuestaSim (không khử glitch delta-cycle): `-coverdeglitch` làm
  vsim 10.7c crash trên thiết kế này.
