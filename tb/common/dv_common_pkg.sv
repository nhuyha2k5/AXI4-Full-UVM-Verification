// Test infrastructure shared by every testbench: a base test that documents
// itself in the log and derives the verdict, and plusarg helpers.
package dv_common_pkg;
  timeunit 1ns;
  timeprecision 1ps;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  function automatic int dv_plusarg_int(string name, int dflt);
    int v;
    if ($value$plusargs({name, "=%d"}, v)) return v;
    return dflt;
  endfunction

  function automatic bit dv_plusarg_flag(string name);
    return $test$plusargs(name) != 0;
  endfunction

  // Turns errors that a test provokes on purpose into counted INFO messages.
  class dv_expected_error_catcher extends uvm_report_catcher;
    string       ids[$];
    int unsigned min_hits[$];   // per id: how often it must be seen (0 = merely tolerated)
    int unsigned hits[$];
    function new(string name = "dv_expected_error_catcher");
      super.new(name);
    endfunction
    virtual function action_e catch();
      if (get_severity() == UVM_ERROR)
        foreach (ids[i]) if (get_id() == ids[i]) begin
          hits[i]++;
          set_severity(UVM_INFO);
          set_message({"[EXPECTED ERROR ", ids[i], "] ", get_message()});
          break;
        end
      return THROW;
    endfunction
    function int unsigned total_hits();
      int unsigned n = 0;
      foreach (hits[i]) n += hits[i];
      return n;
    endfunction
  endclass

  // Demotes the reports of one known, documented design defect to INFO and
  // counts them, so that the rest of a test stays meaningful.  The defect is
  // demonstrated by a dedicated test that runs without this waiver.
  class dv_known_issue_catcher extends uvm_report_catcher;
    string       issue;      // identifier in docs/KNOWN_ISSUES.md
    string       id;         // report id to match
    string       substr;     // text the message must contain
    int unsigned hits;
    function new(string name = "dv_known_issue_catcher");
      super.new(name);
    endfunction
    virtual function action_e catch();
      string msg = get_message();
      if (get_severity() != UVM_ERROR || get_id() != id) return THROW;
      for (int i = 0; i + substr.len() <= msg.len(); i++)
        if (msg.substr(i, i + substr.len() - 1) == substr) begin
          hits++;
          set_severity(UVM_INFO);
          set_message({"[KNOWN ISSUE ", issue, "] ", msg});
          break;
        end
      return THROW;
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Base test.
  //
  // A concrete test fills in dut_name / intent / stimulus / checking (and adds
  // lines to cfg_lines) in its constructor or build_phase.  The base class
  // prints them as a header, prints a result summary at the end, and decides
  // PASSED / FAILED:
  //   - no UVM_ERROR or UVM_FATAL was reported, and
  //   - at least min_checks checks were really performed (num_checks()), and
  //   - for negative tests, every expected error id was seen at least once.
  // The last line of every log is  "TEST_RESULT: PASSED|FAILED ...".
  // ---------------------------------------------------------------------------
  virtual class dv_base_test extends uvm_test;
    string       dut_name = "(not set)";
    string       intent   = "(not set)";
    string       stimulus = "(not set)";
    string       checking = "(not set)";
    string       cfg_lines[$];       // configuration shown in the header
    int unsigned min_checks = 1;
    int unsigned timeout_us = 20000; // simulated time limit; +DV_TIMEOUT_US overrides
    int unsigned seed;
    protected dv_expected_error_catcher catcher;
    protected dv_known_issue_catcher    known_issues[$];

    function new(string n, uvm_component p);
      super.new(n, p);
      seed = $get_initial_random_seed();
    endfunction

    // Number of checks the scoreboards performed in this test.
    virtual function int unsigned num_checks();
      return 0;
    endfunction

    // Result lines for the summary (scoreboard and traffic statistics).
    virtual function void result_lines(ref string q[$]);
    endfunction

    // Declare an error id that this test provokes on purpose.  It is demoted to
    // INFO; the test fails unless it is reported at least min_hits times.
    function void expect_error(string id, int unsigned min_hits = 1);
      if (catcher == null) begin
        catcher = new();
        uvm_report_cb::add(null, catcher);
      end
      catcher.ids.push_back(id);
      catcher.min_hits.push_back(min_hits);
      catcher.hits.push_back(0);
    endfunction

    // Waive the reports of a documented design defect (see docs/KNOWN_ISSUES.md).
    function void waive_known_issue(string issue, string id, string substr);
      dv_known_issue_catcher k = new({"known_issue_", issue});
      k.issue = issue; k.id = id; k.substr = substr;
      uvm_report_cb::add(null, k);
      known_issues.push_back(k);
    endfunction

    function int unsigned expected_error_hits();
      return (catcher == null) ? 0 : catcher.total_hits();
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      timeout_us = dv_plusarg_int("DV_TIMEOUT_US", timeout_us);
    endfunction

    protected task watchdog();
      #(timeout_us * 1us);
      `uvm_fatal("DV_TIMEOUT", $sformatf("test did not finish within %0d us of simulated time", timeout_us))
    endtask

    virtual function void start_of_simulation_phase(uvm_phase phase);
      string s;
      fork
        watchdog();
      join_none
      s = {"\n==============================================================================\n",
           $sformatf(" TEST      : %s\n", get_type_name()),
           $sformatf(" DUT       : %s\n", dut_name),
           $sformatf(" INTENT    : %s\n", intent),
           $sformatf(" STIMULUS  : %s\n", stimulus),
           $sformatf(" CHECKING  : %s\n", checking),
           $sformatf(" SEED      : %0d\n", seed),
           $sformatf(" UVM       : %s    TIMEOUT: %0d us\n", uvm_revision_string(), timeout_us)};
      foreach (cfg_lines[i]) s = {s, $sformatf(" CONFIG    : %s\n", cfg_lines[i])};
      if (catcher != null) foreach (catcher.ids[i])
        s = {s, $sformatf(" EXPECTED  : error id %s %s (negative test)\n", catcher.ids[i],
                          (catcher.min_hits[i] > 0) ? "must be reported" : "is tolerated as a side effect")};
      foreach (known_issues[i])
        s = {s, $sformatf(" WAIVER    : known issue %s (report id %s containing \"%s\") is counted, not failed\n",
                          known_issues[i].issue, known_issues[i].id, known_issues[i].substr)};
      s = {s, "=============================================================================="};
      `uvm_info("TEST_INFO", s, UVM_NONE)
    endfunction

    virtual function void report_phase(uvm_phase phase);
      uvm_report_server srv = uvm_report_server::get_server();
      string q[$];
      string s;
      int    errs;
      bit    pass;
      if (num_checks() < min_checks)
        `uvm_error("DV_NO_CHECK", $sformatf("only %0d check(s) were performed, at least %0d required: the test proved nothing", num_checks(), min_checks))
      if (catcher != null) foreach (catcher.ids[i])
        if (catcher.hits[i] < catcher.min_hits[i])
          `uvm_error("DV_NEG_MISS", $sformatf("negative test: error id %s was reported %0d time(s), at least %0d required",
                                              catcher.ids[i], catcher.hits[i], catcher.min_hits[i]))
      errs = srv.get_severity_count(UVM_ERROR) + srv.get_severity_count(UVM_FATAL);
      pass = (errs == 0);
      result_lines(q);
      s = "\n------------------------------ TEST SUMMARY ----------------------------------\n";
      foreach (q[i]) s = {s, " ", q[i], "\n"};
      s = {s, $sformatf(" checks performed : %0d (minimum required %0d)\n", num_checks(), min_checks)};
      if (catcher != null) foreach (catcher.ids[i])
        s = {s, $sformatf(" expected error   : %s reported %0d time(s), demoted to INFO\n", catcher.ids[i], catcher.hits[i])};
      foreach (known_issues[i])
        s = {s, $sformatf(" known issue      : %s occurred %0d time(s) (waived, see docs/KNOWN_ISSUES.md)\n", known_issues[i].issue, known_issues[i].hits)};
      s = {s, $sformatf(" UVM_WARNING=%0d UVM_ERROR=%0d UVM_FATAL=%0d\n",
                        srv.get_severity_count(UVM_WARNING), srv.get_severity_count(UVM_ERROR), srv.get_severity_count(UVM_FATAL))};
      s = {s, "------------------------------------------------------------------------------\n"};
      s = {s, $sformatf("TEST_RESULT: %s test=%s seed=%0d", pass ? "PASSED" : "FAILED", get_type_name(), seed)};
      `uvm_info("TEST_DONE", s, UVM_NONE)
    endfunction
  endclass
endpackage
