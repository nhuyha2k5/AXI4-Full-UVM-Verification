# Lỗi và giới hạn của DUT do môi trường kiểm chứng tìm ra

Mỗi mục dưới đây đều có **một test tái hiện** chạy trong regression. Test minh hoạ lỗi chưa sửa được đánh dấu
`XFAIL` (expected fail): nó phải FAIL; nếu PASS thì regression báo `XPASS` và coi là thất bại.
Dòng bằng chứng (EVIDENCE) được chép từ log của lần regression gần nhất, xem `reports/known_issues_evidence.txt`.

Bảy lỗi có **bản sửa tuỳ chọn** trong RTL, nằm trong khối `` `ifdef ``. Không định nghĩa macro thì RTL giữ nguyên
hành vi gốc. Regression chính build với các macro này (nếu không, mọi test ngẫu nhiên đều vấp cùng một lỗi và
không đo được gì khác); bản RTL gốc và các bản chỉ sửa một phần vẫn được build riêng (`*_orig`, `xbar_fix02`,
`xbar_fix06`, `xbar_fix07`) để chạy test minh hoạ. **Việc có đưa các bản sửa này vào thiết kế hay không là quyết định của người
thiết kế** – môi trường kiểm chứng chỉ chứng minh lỗi tồn tại và bản sửa đề xuất qua được toàn bộ regression.

| Mã | Khối | Mức độ | Tóm tắt | Test tái hiện | Bản sửa tuỳ chọn |
|---|---|---|---|---|---|
| RAM-01 | `axi_ram` | giới hạn | Burst WRAP bị xử lý như INCR | `ram` / `axi_ram_wrap_test` (XFAIL) | không |
| XBAR-01 | `axi_crossbar_wr/rd` | vi phạm giao thức | Đáp ứng DECERR phát ra trước khi yêu cầu được nhận xong | `xbar` / `xbar_decerr_b_order_test` (XFAIL) | không |
| XBAR-02 | `axi_crossbar_wr/rd` | **treo** | Sau DECERR bộ đếm giao dịch bị trừ lố, master bị khoá | `xbar_orig` / `xbar_decerr_lockup_test` (XFAIL) | `AXI_CROSSBAR_DECERR_CPL_FIX` |
| XBAR-03 | `axi_crossbar` | vi phạm giao thức, **báo lỗi nhầm ở mức hệ thống** | DECERR không giữ thứ tự với các đáp ứng cùng ID | `xbar` / `xbar_decerr_id_order_test`, `sys` / `sys_decerr_pipelined_test` (XFAIL) | không |
| XBAR-04 | `axi_crossbar_rd` | sai dữ liệu | Slave xen kẽ dữ liệu đọc giữa các ID → beat tới sai master | `xbar` / `xbar_read_interleave_test` (XFAIL) | không |
| XBAR-05 | `axi_crossbar_wr` | **mất dữ liệu** | Beat W đầu tiên sau một lần ghi DECERR bị nuốt | `xbar_fix02` / `xbar_decerr_wdata_test` (XFAIL) | `AXI_CROSSBAR_WREADY_GATE_FIX` |
| XBAR-06 | `axi_crossbar` | tham số bị bỏ qua | `M_*_REG_TYPE` không được truyền xuống `axi_crossbar_wr/rd` | `xbar_orig` / `xbar_param_test` (XFAIL) | `AXI_CROSSBAR_M_REG_TYPE_FIX` |
| XBAR-07 | `axi_crossbar_wr/rd` | **đáp ứng tới sai master** (bị XBAR-06 che) | Chọn master nhận đáp ứng bằng ID ở phía trước register slice | `xbar_fix06` / `xbar_smoke_test` (XFAIL) | `AXI_CROSSBAR_RESP_SELECT_FIX` |
| XBAR-08 | `axi_crossbar_rd` (`_wr` cùng cấu trúc) | **giới hạn không được tôn trọng** | Số giao dịch tới một slave vượt `M_ISSUE`; với `M_ISSUE = 1` giới hạn mất hẳn | `xbar_fix07` / `xbar_issue_limit_test` cfg `open` (XFAIL) | `AXI_CROSSBAR_ISSUE_LIMIT_FIX` |
| CDMA-01 | `axi_cdma` | **sai dữ liệu** | Mất một beat đọc khi nguồn/đích lệch nhau và dữ liệu đọc về liên tục | `cdma_orig` / `dma_cdma_offset_test` (XFAIL) | `AXI_CDMA_RREADY_FIX` |
| DMAWR-01 | `axi_dma_wr` | **mất dữ liệu** | Beat đầu của frame kế tiếp bị nuốt sau một frame ngắn có beat cuối bị tách | `dma_wr_orig` / `dma_wr_short_frame_split_test` (XFAIL) | `AXI_DMA_WR_TREADY_FIX` |
| DMA-01 | `axi_dma_wr` | giới hạn | Ngõ vào `abort` không được hiện thực | `dma_wr` / `dma_wr_abort_test` (PASS, ghi nhận hành vi) | không |

## Đối chiếu với mã gốc verilog-axi (Alex Forencich)

Đối chiếu ngày 2026-10-12 với nhánh `master` của `github.com/alexforencich/verilog-axi` (so SHA-256 của nội dung
sau khi bỏ khoảng trắng cuối dòng; bản của project lấy từ `_backup_original_2026-10-11/`, tức trước khi thêm
các khối `` `ifdef ``).

| File | So với mã gốc |
|---|---|
| `arbiter.v`, `priority_encoder.v`, `axi_register_rd.v`, `axi_register_wr.v`, `axi_crossbar_addr.v`, `axi_crossbar_rd.v`, `axi_crossbar_wr.v`, `axi_crossbar.v` | **giống hệt** |
| `axi_ram.v` | khác (377 dòng so với 373: thêm `INIT_FILE`) |
| `axi_dma_rd.v` | khác (714 so với 692 dòng) |
| `axi_dma_wr.v` | khác (952 so với 942 dòng: thêm trạng thái `STATE_PREP`) |
| `axi_cdma.v` | khác (809 so với 798 dòng: thêm trạng thái `READ_STATE_PREP`) |

Từ đó phân loại lại mức độ chắc chắn của từng mục:

| Mã | Có trong mã gốc? | Xác nhận độc lập | Kết luận |
|---|---|---|---|
| RAM-01 | có | README gốc ghi `axi_ram` chỉ hỗ trợ FIXED và INCR | **không phải lỗi** – giới hạn đã được công bố |
| XBAR-04 | có | issue #30 do chính tác giả mở: chưa hỗ trợ read data interleaving | **không phải lỗi mới** – tính năng chưa hỗ trợ, tác giả đã biết |
| XBAR-01 | có (file giống hệt) | issue #95 (người khác báo cùng hiện tượng); tác giả trả lời sẽ đưa vào danh sách việc cần làm | lỗi thật, đã được báo |
| XBAR-02 | có (file giống hệt) | issue #84 "Crossbar locks up after reading to write-only address" | lỗi thật, đã được báo |
| XBAR-06 | có (file giống hệt) | issue #79 "Parameters not passed on to axi_crossbar_wr and axi_crossbar_rd" | lỗi thật, đã được báo |
| XBAR-03, XBAR-05, XBAR-07, XBAR-08 | có (file giống hệt) | **chưa thấy ai báo** | bằng chứng: test tự kiểm tra FAIL trên file giống hệt mã gốc + nguyên nhân chỉ ra được trong RTL + bản sửa làm test PASS. Chưa có xác nhận độc lập |
| CDMA-01, DMAWR-01 | **có** – tái hiện được trên file gốc nguyên bản (tải ngày 2026-10-13 vào `upstream_ref/`, build `cdma_up`, `dma_wr_up`) | chưa thấy ai báo | cùng test, cùng triệu chứng (dữ liệu đích lệch nguồn; status sai id/dest/user và thiếu 4 byte) trên cả bản gốc lẫn bản của project → lỗi của mã gốc, không phải do phần sửa trong project. Chưa có xác nhận độc lập |
| DMA-01 | có (cổng `abort` trong mã gốc cũng không được dùng) | – | giới hạn |

### Chạy toàn bộ test trên mã gốc nguyên bản

Mọi test chính được chạy lại, cùng seed và cấu hình build, trên RTL không có bản sửa nào (crossbar không định nghĩa macro;
`axi_ram`, `axi_dma_rd`, `axi_dma_wr`, `axi_cdma` là file gốc trong `upstream_ref/`). Kết quả ghi là `ORIG-PASS` /
`ORIG-FAIL` và **không bao giờ** tính là lỗi của regression (`regress.ps1`, `Expect = 'ORIG'` trong `scripts/dv_config.ps1`).
Con số lấy từ `reports/regression_summary.md`; chi tiết từng test không qua nằm trong báo cáo đồ án, mục 7.2.

| Thiết kế (mã gốc) | Build | Số lần chạy | Qua | Không qua |
|---|---|---|---|---|
| `axi_ram` | `ram_up` | 43 | 42 | 1 (test burst WRAP, RAM-01) |
| `axi_crossbar` không bật bản sửa nào | `xbar_orig` | 73 | 5 | 68 |
| `axi_dma_rd` | `dma_rd_up` | 53 | 53 | 0 |
| `axi_dma_wr` | `dma_wr_up` | 58 | 49 | 9 (DMAWR-01) |
| `axi_cdma` | `cdma_up` | 56 | 14 | 42 (CDMA-01) |
| **Tổng** | | **283** | **163** | **120** |

Dấu hiệu trong log của các lần không qua (tìm bằng mẫu lỗi đặc trưng, không phải kết luận chắc chắn về nguyên nhân gốc):
crossbar: 56 lần treo hoặc hết thời gian chờ, 17 lần mất nhịp ghi sau DECERR (XBAR-05), 19 lần vượt giới hạn `M_ISSUE`
(XBAR-08), 33 lần đáp ứng không khớp giao dịch nào, 1 lần tham số register slice không được truyền (XBAR-06);
`axi_cdma`: 40/42 lần dữ liệu đích khác nguồn; `axi_dma_wr`: 9/9 lần sai status hoặc thiếu byte ghi.
`axi_dma_rd` và `axi_ram` (trừ WRAP) cho cùng kết quả trên mã gốc và trên bản đã chỉnh sửa trong project.

Ghi chú: README của mã gốc cho biết kho này đã ngừng bảo trì (thay bằng `fpganinja/taxi`), và trong issue #95 tác giả
viết: "The AXI crossbar is honestly rather rough and needs a lot of work."

---

## RAM-01 – `axi_ram` không hỗ trợ burst WRAP

* **Hiện tượng**: với `AxBURST = WRAP`, địa chỉ cứ tăng tiếp qua biên wrap thay vì quay về đầu khối.
* **Nguyên nhân**: `axi_ram.v` chỉ phân biệt FIXED với "khác FIXED" (`if (burst != 2'b00) addr = addr + size`).
* **Ảnh hưởng**: master dùng WRAP (thường là cache line fill) sẽ đọc/ghi sai ô nhớ.
* **Tái hiện**: `.\run_test.ps1 -Tb ram -Test axi_ram_wrap_test` → scoreboard báo dữ liệu sai ở các beat sau
  điểm quấn.
* **Xử lý trong testbench**: các test ngẫu nhiên của RAM chỉ sinh WRAP bắt đầu đúng biên wrap (không cần quấn);
  bin coverage WRAP của cổng RAM bị tắt (`cov_wrap = 0`).

## XBAR-01 – Đáp ứng DECERR phát ra quá sớm

* **Hiện tượng**: với một lần ghi tới địa chỉ không hợp lệ, `BVALID` (DECERR) lên trước khi beat W cuối được
  nhận. AXI4 (A3.3.1, quan hệ phụ thuộc giữa các kênh) yêu cầu đáp ứng ghi chỉ được phát sau beat W cuối.
* **Nguyên nhân**: `axi_crossbar_wr` bật `decerr_m_axi_bvalid` ngay khi nhận lệnh từ bộ giải mã địa chỉ
  (`m_rc_valid && m_rc_ready`), không chờ dữ liệu ghi đang bị bỏ (`w_drop_reg`) kết thúc bằng `WLAST`.
  Phía đọc tương tự: `RVALID` của DECERR có thể lên cùng lúc với bắt tay AR.
* **Ảnh hưởng**: master chặt chẽ theo chuẩn có thể coi đây là lỗi giao thức; master thông thường vẫn chạy.
* **Tái hiện**: `.\run_test.ps1 -Tb xbar -Test xbar_decerr_b_order_test` → monitor báo
  `BVALID asserted before the last W beat was accepted (response AXI4_RESP_DECERR issued too early)`.
* **Xử lý trong testbench**: ở các test khác thông báo này được **miễn trừ có đếm** bằng
  `waive_known_issue("XBAR-01", ...)`; số lần miễn trừ được in trong phần TEST SUMMARY của log.

## XBAR-02 – Master bị khoá sau DECERR (đã có bản sửa tuỳ chọn)

* **Hiện tượng**: sau một vài truy cập bị DECERR, master đó không còn được cấp truy cập nào nữa (treo, test hết
  thời gian).
* **Nguyên nhân**: giao dịch DECERR không bao giờ được đếm vào (`trans_start` không xảy ra) nhưng khi đáp ứng
  DECERR hoàn tất thì `s_cpl_valid` vẫn báo hoàn thành → `trans_count` / bộ đếm thread trong `axi_crossbar_addr`
  bị trừ xuống dưới 0 và tràn thành giá trị cực đại → điều kiện giới hạn `S_ACCEPT` luôn đúng.
* **Bản sửa** (`AXI_CROSSBAR_DECERR_CPL_FIX`, `axi_crossbar_wr.v` và `axi_crossbar_rd.v`): không báo hoàn thành
  cho đáp ứng đến từ nhánh DECERR (`b_grant_encoded != M_COUNT_P1-1`, tương tự cho kênh R).
* **Tái hiện**: `.\run_test.ps1 -Tb xbar_orig -Test xbar_decerr_lockup_test` FAIL; cùng test với `-Tb xbar` PASS.

## XBAR-03 – DECERR không giữ thứ tự trong cùng một ID

* **Hiện tượng**: master gửi liên tiếp, cùng ID, một truy cập hợp lệ tới slave chậm rồi một truy cập không hợp lệ.
  Đáp ứng DECERR (do crossbar tự sinh) về **trước** đáp ứng của truy cập hợp lệ. AXI4 (A5.3.1) yêu cầu các đáp
  ứng cùng ID phải theo đúng thứ tự yêu cầu.
* **Nguyên nhân**: trong `axi_crossbar_addr`, nhánh giải mã thất bại đi thẳng sang phát lệnh DECERR mà không
  qua điều kiện thread (`thread_match_dest`...) – tức không chờ các giao dịch cùng ID đang bay hoàn tất.
* **Ảnh hưởng**: master ghép đáp ứng theo thứ tự sẽ gán nhầm DECERR cho giao dịch hợp lệ.
* **Tái hiện**: `.\run_test.ps1 -Tb xbar -Test xbar_decerr_id_order_test`.
* **Hậu quả ở mức hệ thống** (tìm thấy khi chạy testbench tích hợp): `axi_cdma` chỉ dùng ID 0 và phát AW của
  descriptor kế tiếp trước khi nhận xong đáp ứng B của descriptor hiện tại. Nếu descriptor kế tiếp ghi ra ngoài
  bản đồ địa chỉ, DECERR của crossbar vượt lên trước đáp ứng của RAM → engine gán DECERR cho **descriptor hợp lệ**
  (status `error=7` sai chỗ) còn descriptor lỗi lại báo thành công.
  Tái hiện: `.\run_test.ps1 -Tb sys -Test sys_decerr_pipelined_test` (kiểm tra trực tiếp mã lỗi của từng status).
* **Xử lý trong testbench**: các test ngẫu nhiên của crossbar dùng ID riêng cho truy cập tới vùng không hợp lệ
  (`split_decerr_ids = 1`); `sys_decerr_test` phát từng descriptor một quanh các descriptor lỗi.

## XBAR-04 – Dữ liệu đọc xen kẽ từ slave bị chuyển sai master

* **Hiện tượng**: khi một slave xen kẽ các beat R của hai burst khác ID (AXI4 cho phép) và hai burst đó thuộc
  hai master khác nhau, một master nhận được beat không phải của mình / thiếu beat.
* **Nguyên nhân**: bộ mux R của master `m` giữ quyền (grant) cho slave `n` tới khi thấy `RLAST`, và trong lúc
  đó lấy `RVALID` thô của slave (`int_m_axi_rvalid[n]`) mà không kiểm tra beat đó có thuộc master `m` hay không
  (tín hiệu đã lọc theo RID là `int_axi_rvalid[n*S_COUNT+m]` chỉ được dùng cho request/acknowledge của arbiter).
  Khi slave xen một beat của master khác vào giữa burst, master đang giữ grant thấy thêm một beat "ma".
* **Ảnh hưởng**: sai dữ liệu nếu slave phía dưới có xen kẽ dữ liệu đọc. Slave không xen kẽ (như `axi_ram`) thì
  không bị.
* **Tái hiện**: `.\run_test.ps1 -Tb xbar -Test xbar_read_interleave_test`.
* **Xử lý trong testbench**: ngoài test này, slave VIP chỉ đổi thứ tự theo burst (`rd_reorder`), không xen kẽ beat.

## XBAR-05 – Mất beat W đầu tiên sau một lần ghi bị DECERR (đã có bản sửa tuỳ chọn)

* **Hiện tượng**: master gửi dữ liệu ghi sớm (W đi trước AW). Sau một lần ghi bị DECERR, lần ghi hợp lệ kế tiếp
  tới slave thiếu beat đầu → slave nhận burst lệch, treo chờ `WLAST`.
* **Nguyên nhân**: `int_s_axi_wready` không được chặn bằng `w_select_valid_reg`. Khi chưa có lệnh ghi hợp lệ,
  `w_select_reg` còn trỏ tới slave cũ; nếu slave đó đang sẵn sàng thì `WREADY` lọt về master, beat W được
  "nhận" nhưng không được chuyển đi đâu.
* **Bản sửa** (`AXI_CROSSBAR_WREADY_GATE_FIX`, `axi_crossbar_wr.v`): `WREADY` chỉ được chuyển về khi
  `w_select_valid_reg = 1`.
* **Tái hiện**: `.\run_test.ps1 -Tb xbar_fix02 -Test xbar_decerr_wdata_test` FAIL (build chỉ có bản sửa XBAR-02);
  cùng test với `-Tb xbar` PASS.
* **Góc reset**: `w_drop_reg` không được xoá khi reset. Reset giữa lúc đang bỏ dữ liệu của một lần ghi DECERR
  để lại cờ này ở mức 1; RTL gốc sau đó nuốt dữ liệu ghi tới trước địa chỉ. `xbar_reset_drop_test` kiểm tra
  trường hợp này trên RTL đã sửa.

## XBAR-06 – Tham số `M_*_REG_TYPE` của `axi_crossbar` không có tác dụng (đã có bản sửa tuỳ chọn)

* **Hiện tượng**: `axi_crossbar` khai báo `M_AW_REG_TYPE`, `M_W_REG_TYPE`, `M_B_REG_TYPE`, `M_AR_REG_TYPE`,
  `M_R_REG_TYPE` nhưng không nối chúng vào `axi_crossbar_wr` / `axi_crossbar_rd`. Register slice phía cổng master
  của crossbar luôn dùng kiểu mặc định (AW/AR = 1, W = 2, B/R = 0) bất kể người dùng cấu hình gì.
* **Cách phát hiện**: phân tích lỗ coverage – một hàng FEC của bộ mux AW không bao giờ đạt dù testbench tạo đúng
  tình huống ở cổng; dò tín hiệu nội bộ cho thấy register slice "bypass" theo cấu hình thực ra vẫn là thanh ghi.
* **Ảnh hưởng**: không sai chức năng, nhưng độ trễ / đường timing không theo cấu hình; và các kiểu register slice
  khác mặc định ở phía master **chưa từng được mô phỏng** trước khi sửa.
* **Bản sửa** (`AXI_CROSSBAR_M_REG_TYPE_FIX`, `axi_crossbar.v`): truyền 5 tham số xuống hai khối con.
* **Tái hiện**: `.\run_test.ps1 -Tb xbar_orig -Test xbar_param_test` FAIL (testbench đọc lại tham số đã elaborate
  của hai khối con và so với giá trị yêu cầu); cùng test với `-Tb xbar` PASS.

## XBAR-07 – Đáp ứng B/R tới sai master khi có register slice phía master (đã có bản sửa tuỳ chọn)

* **Hiện tượng**: với `M_B_REG_TYPE != 0` hoặc `M_R_REG_TYPE != 0`, đáp ứng ghi / dữ liệu đọc bị chuyển tới master
  khác hoặc lặp lại; master gốc treo chờ.
* **Nguyên nhân**: `b_select` / `r_select` (master nhận đáp ứng) được tính từ `m_axi_bid` / `m_axi_rid` ở **phía
  trước** register slice, trong khi `valid` và dữ liệu lấy ở **phía sau** (`int_m_axi_bvalid`, `int_m_axi_rvalid`).
  Khi có thanh ghi ở giữa, hai thứ thuộc hai beat khác nhau.
* **Vì sao trước đây không lộ**: XBAR-06 khiến B và R phía master luôn là bypass, nên hai phía trùng nhau. Sửa
  XBAR-06 xong thì XBAR-07 xuất hiện ngay ở test đơn giản nhất – nhờ VIP đặt giá trị ngẫu nhiên lên `RID`/`BID`
  khi `VALID` thấp (`randomize_idle`).
* **Bản sửa** (`AXI_CROSSBAR_RESP_SELECT_FIX`, `axi_crossbar_wr.v`, `axi_crossbar_rd.v`): dùng `int_m_axi_bid` /
  `int_m_axi_rid`.
* **Tái hiện**: `.\run_test.ps1 -Tb xbar_fix06 -Test xbar_smoke_test` FAIL (build có mọi bản sửa trừ bản này);
  cùng test với `-Tb xbar` PASS.

## XBAR-08 – Giới hạn `M_ISSUE` bị vượt (đã có bản sửa tuỳ chọn)

* **Hiện tượng**: khi hai master cùng xin đọc một slave, số giao dịch đọc đang bay ở cổng slave đó vượt
  `M_ISSUE`: 5 thay vì 4, 3 thay vì 2; và với `M_ISSUE = 1` đo được tới 5 giao dịch cùng lúc.
* **Nguyên nhân**: `trans_limit = trans_count_reg >= M_ISSUE && !trans_complete` chặn *yêu cầu* tới bộ phân xử.
  Ở chu kỳ một địa chỉ đã được cấp quyền được chuyển đi (`trans_start`), bộ đếm chưa kịp tăng, nên yêu cầu của
  master còn lại lọt qua và được cấp quyền ngay sau đó – quyền đã cấp thì không bị thu hồi. Với `M_ISSUE = 1`
  bộ đếm chỉ rộng 1 bit: 1 + 1 quay về 0 và từ đó giới hạn không còn tác dụng.
  Phía ghi dùng cùng công thức nhưng còn điều kiện `!w_select_valid_next`, nên trong regression không quan sát
  thấy vượt giới hạn ghi.
* **Cách phát hiện**: sau khi hoán vị `M_ISSUE` trong build `open`, log cho thấy slave có `M_ISSUE = 1` vẫn có
  3–5 giao dịch đọc cùng lúc. Trước đó testbench **không kiểm tra** các giới hạn này (chỉ kiểm tra dữ liệu); đã
  thêm `xbar_limit_checker` đếm từng chu kỳ ở mọi cổng.
* **Ảnh hưởng**: slave chỉ chịu được N giao dịch đồng thời (lý do đặt `M_ISSUE`) có thể bị quá tải.
* **Bản sửa** (`AXI_CROSSBAR_ISSUE_LIMIT_FIX`, `axi_crossbar_rd.v`, `axi_crossbar_wr.v`): tính luôn giao dịch
  đang bắt đầu trong chu kỳ hiện tại, `(trans_count_reg + trans_start) >= M_ISSUE`.
* **Tái hiện**: `.\run_test.ps1 -Tb xbar_fix07 -Test xbar_issue_limit_test -Cfg open` FAIL với
  `[XBAR_LIMIT] slave port 0, reads (M_ISSUE): 2 in flight, limit is 1`; cùng test với `-Tb xbar` PASS.
* **Giới hạn của phép kiểm tra phía master**: `S_ACCEPT` được kiểm tra với biên nới thêm bằng độ sâu của register
  slice trên kênh địa chỉ và kênh đáp ứng (cổng thấy giao dịch sớm hơn và đáp ứng muộn hơn bộ đếm bên trong).
  `S_THREADS` không được kiểm tra trực tiếp ở cổng.

## CDMA-01 – `axi_cdma` mất một beat đọc (đã có bản sửa tuỳ chọn)

* **Hiện tượng**: với `ENABLE_UNALIGNED = 1`, khi độ lệch byte của nguồn và đích khác nhau và bộ nhớ trả dữ liệu
  đọc liên tục (không có khoảng nghỉ), dữ liệu ghi ra đích bị lệch một word từ giữa bản sao.
* **Nguyên nhân**: trong `AXI_STATE_WRITE`, ở chu kỳ nhận beat đọc cuối của một burst mà phía ghi còn chu kỳ
  phải xuất, `m_axi_rready_next` giữ giá trị tính theo `input_active_reg` (cũ) → `RREADY` cao thêm một chu kỳ,
  beat đầu của burst đọc kế tiếp bị nhận rồi bỏ.
* **Bản sửa** (`AXI_CDMA_RREADY_FIX`, `axi_cdma.v`): `m_axi_rready_next = m_axi_wready_int && input_active_next`.
* **Tái hiện**: `.\run_test.ps1 -Tb cdma_orig -Test dma_cdma_offset_test` FAIL; cùng test với `-Tb cdma` PASS.

## DMAWR-01 – `axi_dma_wr` nuốt beat đầu của frame kế tiếp (đã có bản sửa tuỳ chọn)

* **Hiện tượng**: frame ngắn hơn descriptor, có beat cuối (TLAST) bị chia qua hai burst AXI do lệch địa chỉ.
  Frame kế tiếp mất beat đầu; status của descriptor sau mang `id/dest/user` sai.
* **Nguyên nhân**: khi phát burst mới, `s_axis_write_data_tready_next` được bật lại mà không xét
  `shift_axis_input_tready` – phần dư của beat TLAST vẫn còn trong thanh ghi dịch nên beat mới được nhận sẽ
  bị ghi đè.
* **Bản sửa** (`AXI_DMA_WR_TREADY_FIX`, `axi_dma_wr.v`): thêm điều kiện `&& shift_axis_input_tready`.
* **Tái hiện**: `.\run_test.ps1 -Tb dma_wr_orig -Test dma_wr_short_frame_split_test` FAIL; cùng test với
  `-Tb dma_wr` PASS.

## DMA-01 – Ngõ vào `abort` của `axi_dma_wr` không có tác dụng

* **Hiện tượng**: cổng `abort` tồn tại nhưng không được dùng trong logic; kéo `abort` lúc đang truyền không dừng
  được gì.
* **Tái hiện / ghi nhận**: `dma_wr_abort_test` kéo `abort` nhiều lần giữa lúc truyền và kiểm tra rằng mọi
  descriptor vẫn hoàn tất đúng dữ liệu. Test này PASS – nó ghi nhận hành vi hiện có, không khẳng định đó là
  hành vi mong muốn.
* **Hệ quả cho coverage**: toggle của `abort` được đo bình thường; không có logic nào phụ thuộc vào nó.
