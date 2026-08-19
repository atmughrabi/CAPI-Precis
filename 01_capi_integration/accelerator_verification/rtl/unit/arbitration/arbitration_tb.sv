// -----------------------------------------------------------------------------
// Executable unit coverage for every CAPI-Precis arbitration module.
//
// Devices under test
//   priority_arbiters.sv            vc_FixedArbChain, vc_FixedArb,
//                                   vc_VariableArbChain, vc_VariableArb,
//                                   vc_RoundRobinArbChain, vc_RoundRobinArb,
//                                   vc_RoundRobinArb_V2
//   fixed_priority_arbiter.sv       fixed_priority_arbiter_N_input_1_ouput,
//                                   fixed_priority_arbiter_1_input_N_ouput
//   round_robin_priority_arbiter.sv round_robin_priority_arbiter_N_input_1_ouput,
//                                   round_robin_priority_arbiter_1_input_N_ouput
//
// The reference model is written from the arbitration contract (circular
// first-match priority, post-grant rotation, payload routing) and never
// mirrors the gate structure of the devices under test.
// -----------------------------------------------------------------------------

module arbitration_tb;

  localparam int MAX_N = 5;

  localparam int COMB_COUNT = 5;
  localparam int RR_COUNT   = 5;
  localparam int WRAP_COUNT = 5;

  localparam int COMB_N [0:COMB_COUNT-1] = '{1, 2, 3, 4, 5};
  localparam int RR_N   [0:RR_COUNT-1]   = '{1, 2, 3, 4, 5};
  localparam int WRAP_N [0:WRAP_COUNT-1] = '{1, 2, 3, 4, 3};
  localparam int WRAP_W [0:WRAP_COUNT-1] = '{8, 8, 8, 8, 33};

  localparam int EXPECTED_DONE = COMB_COUNT + (4 * RR_COUNT) + (4 * WRAP_COUNT);
  localparam int REPORT_LIMIT  = 256;

  logic clock = 1'b0;
  always #5 clock = ~clock;

  int unsigned errors;
  int unsigned reports;
  int unsigned done_count;
  int unsigned bins_hit;

  int unsigned v_fixed_chain;
  int unsigned v_fixed_arb;
  int unsigned v_var_chain;
  int unsigned v_var_arb;
  int unsigned v_rr_chain;
  int unsigned v_rr_arb;
  int unsigned v_rr_v2;
  int unsigned v_wrap_fanin;
  int unsigned v_wrap_fanout;

  //--------------------------------------------------------------------------
  // Functional bins
  //--------------------------------------------------------------------------

  bit fixed_chain_winner [0:COMB_COUNT-1][0:MAX_N-1];
  bit fixed_chain_idle   [0:COMB_COUNT-1];
  bit fixed_chain_kin    [0:COMB_COUNT-1];
  bit fixed_chain_all    [0:COMB_COUNT-1];
  bit fixed_arb_winner   [0:COMB_COUNT-1][0:MAX_N-1];
  bit fixed_arb_idle     [0:COMB_COUNT-1];
  bit fixed_arb_all      [0:COMB_COUNT-1];

  bit var_chain_cross [0:COMB_COUNT-1][0:MAX_N-1][0:MAX_N-1];
  bit var_chain_idle  [0:COMB_COUNT-1];
  bit var_chain_kin   [0:COMB_COUNT-1];
  bit var_arb_cross   [0:COMB_COUNT-1][0:MAX_N-1][0:MAX_N-1];
  bit var_arb_idle    [0:COMB_COUNT-1];

  // group 0 vc_RoundRobinArbChain with reset priority index 0
  // group 1 vc_RoundRobinArbChain with reset priority index N-1
  // group 2 vc_RoundRobinArb
  // group 3 vc_RoundRobinArb_V2
  bit rr_winner [0:3][0:RR_COUNT-1][0:MAX_N-1];
  bit rr_state  [0:3][0:RR_COUNT-1][0:MAX_N-1];
  bit rr_fair   [0:3][0:RR_COUNT-1];
  bit rr_idle   [0:3][0:RR_COUNT-1];
  bit rr_reset  [0:3][0:RR_COUNT-1];
  bit rr_kin    [0:1][0:RR_COUNT-1];

  // module 0 fixed priority wrapper, module 1 round-robin wrapper
  bit wrap_fanin_source [0:1][0:WRAP_COUNT-1][0:MAX_N-1];
  bit wrap_fanin_clear  [0:1][0:WRAP_COUNT-1];
  bit wrap_fanin_stall  [0:1][0:WRAP_COUNT-1];
  bit wrap_fanin_reset  [0:1][0:WRAP_COUNT-1];
  bit wrap_fanin_multi  [0:1][0:WRAP_COUNT-1];
  bit wrap_fanin_aligned[0:1][0:WRAP_COUNT-1];
  bit wrap_fanin_miss   [0:1][0:WRAP_COUNT-1];
  bit wrap_fanin_resume [0:1][0:WRAP_COUNT-1];
  bit wrap_fanout_dest  [0:1][0:WRAP_COUNT-1][0:MAX_N-1];
  bit wrap_fanout_zero  [0:1][0:WRAP_COUNT-1];
  bit wrap_fanout_stall [0:1][0:WRAP_COUNT-1];
  bit wrap_fanout_reset [0:1][0:WRAP_COUNT-1];
  bit wrap_fanout_clear [0:1][0:WRAP_COUNT-1];
  bit wrap_fanout_resume[0:1][0:WRAP_COUNT-1];

  //--------------------------------------------------------------------------
  // Independent reference model helpers
  //--------------------------------------------------------------------------

  // First requester found by scanning circularly upward from `start`.
  function automatic int pick_first(
      input int               n,
      input int               start,
      input logic [MAX_N-1:0] reqs
  );
    int index;
    pick_first = -1;
    for(int offset = 0; offset < n; offset++) begin
      index = (start + offset) % n;
      if(reqs[index] === 1'b1) begin
        pick_first = index;
        break;
      end
    end
  endfunction

  function automatic logic [MAX_N-1:0] onehot_of(input int index);
    onehot_of = '0;
    if(index >= 0)
      onehot_of[index] = 1'b1;
  endfunction

  function automatic int index_of(input logic [MAX_N-1:0] value);
    index_of = -1;
    for(int bit_index = 0; bit_index < MAX_N; bit_index++)
      if(value[bit_index] === 1'b1)
        index_of = bit_index;
  endfunction

  // Highest selected index; the wrapper payload loop lets the last matching
  // iteration win when the select vector is multi-hot.
  function automatic int last_index_of(input int n, input logic [MAX_N-1:0] value);
    last_index_of = -1;
    for(int bit_index = 0; bit_index < n; bit_index++)
      if(value[bit_index] === 1'b1)
        last_index_of = bit_index;
  endfunction

  function automatic logic [MAX_N-1:0] wide(input int value);
    wide = value[MAX_N-1:0];
  endfunction

  function automatic void report_failure(
      input string class_name,
      input string instance_name,
      input string check_name,
      input string detail
  );
    errors++;
    if(reports < REPORT_LIMIT) begin
      reports++;
      $display(
        "ERROR arbitration_unit class=%s instance=%s check=%s %s",
        class_name,
        instance_name,
        check_name,
        detail
      );
    end
  endfunction

  function automatic void require_bin(input bit value, input string name);
    if(!value)
      report_failure("coverage", "arbitration_tb", "missing-bin", name);
    else
      bins_hit++;
  endfunction

  //--------------------------------------------------------------------------
  // Combinational arbiters: exhaustive request vectors for every parameter
  //--------------------------------------------------------------------------

  generate
    for(genvar c = 0; c < COMB_COUNT; c++) begin : g_comb
      localparam int N = COMB_N[c];

      logic         fc_kin;
      logic [N-1:0] fc_reqs;
      logic [N-1:0] fc_grants;
      logic         fc_kout;

      logic [N-1:0] fa_reqs;
      logic [N-1:0] fa_grants;

      logic         vc_kin;
      logic [N-1:0] vc_prio;
      logic [N-1:0] vc_reqs;
      logic [N-1:0] vc_grants;
      logic         vc_kout;

      logic [N-1:0] va_prio;
      logic [N-1:0] va_reqs;
      logic [N-1:0] va_grants;

      vc_FixedArbChain #(N) u_fixed_chain (
        .kin   (fc_kin   ),
        .reqs  (fc_reqs  ),
        .grants(fc_grants),
        .kout  (fc_kout  )
      );

      vc_FixedArb #(N) u_fixed_arb (
        .reqs  (fa_reqs  ),
        .grants(fa_grants)
      );

      vc_VariableArbChain #(N) u_var_chain (
        .kin      (vc_kin   ),
        .priority_(vc_prio  ),
        .reqs     (vc_reqs  ),
        .grants   (vc_grants),
        .kout     (vc_kout  )
      );

      vc_VariableArb #(N) u_var_arb (
        .priority_(va_prio  ),
        .reqs     (va_reqs  ),
        .grants   (va_grants)
      );

      function automatic string tag(input string module_name);
        tag = $sformatf("%s[N=%0d]", module_name, N);
      endfunction

      function automatic void check_common(
          input string        module_name,
          input logic [N-1:0] reqs,
          input logic [N-1:0] grants,
          input logic [N-1:0] expected,
          input string        context_text
      );
        if(grants !== expected)
          report_failure(
            "combinational-arbitration",
            tag(module_name),
            "grants",
            $sformatf(
              "%s reqs=%b expected=%b actual=%b",
              context_text, reqs, expected, grants
            )
          );
        if(!$onehot0(grants))
          report_failure(
            "combinational-arbitration",
            tag(module_name),
            "one-hot-grant",
            $sformatf("%s reqs=%b actual=%b", context_text, reqs, grants)
          );
        if((grants & ~reqs) != '0)
          report_failure(
            "combinational-arbitration",
            tag(module_name),
            "grant-implies-request",
            $sformatf("%s reqs=%b actual=%b", context_text, reqs, grants)
          );
      endfunction

      function automatic void check_fixed_chain(input int request_value);
        logic [MAX_N-1:0] reqs;
        logic [MAX_N-1:0] expected;
        logic             expected_kout;
        int               winner;

        reqs = '0;
        reqs[N-1:0] = fc_reqs;
        winner = (fc_kin === 1'b1) ? -1 : pick_first(N, 0, reqs);
        expected = onehot_of(winner);
        expected_kout = (|fc_reqs) | fc_kin;

        check_common(
          "vc_FixedArbChain",
          fc_reqs,
          fc_grants,
          expected[N-1:0],
          $sformatf("kin=%b", fc_kin)
        );
        if(fc_kout !== expected_kout)
          report_failure(
            "combinational-arbitration",
            tag("vc_FixedArbChain"),
            "kout",
            $sformatf(
              "kin=%b reqs=%b expected=%b actual=%b",
              fc_kin, fc_reqs, expected_kout, fc_kout
            )
          );

        v_fixed_chain++;
        if(fc_kin === 1'b0 && winner >= 0)
          fixed_chain_winner[c][winner] = 1'b1;
        if(fc_kin === 1'b0 && request_value == 0)
          fixed_chain_idle[c] = 1'b1;
        if(fc_kin === 1'b1 && request_value != 0)
          fixed_chain_kin[c] = 1'b1;
        if(fc_kin === 1'b0 && request_value == ((1 << N) - 1))
          fixed_chain_all[c] = 1'b1;
      endfunction

      function automatic void check_fixed_arb(input int request_value);
        logic [MAX_N-1:0] reqs;
        logic [MAX_N-1:0] expected;
        int               winner;

        reqs = '0;
        reqs[N-1:0] = fa_reqs;
        winner = pick_first(N, 0, reqs);
        expected = onehot_of(winner);

        check_common("vc_FixedArb", fa_reqs, fa_grants, expected[N-1:0], "kin=none");

        v_fixed_arb++;
        if(winner >= 0)
          fixed_arb_winner[c][winner] = 1'b1;
        if(request_value == 0)
          fixed_arb_idle[c] = 1'b1;
        if(request_value == ((1 << N) - 1))
          fixed_arb_all[c] = 1'b1;
      endfunction

      function automatic void check_var_chain(
          input int priority_index,
          input int request_value
      );
        logic [MAX_N-1:0] reqs;
        logic [MAX_N-1:0] expected;
        logic             expected_kout;
        int               winner;

        reqs = '0;
        reqs[N-1:0] = vc_reqs;
        winner = (vc_kin === 1'b1) ? -1 : pick_first(N, priority_index, reqs);
        expected = onehot_of(winner);
        expected_kout = (|vc_reqs) | vc_kin;

        check_common(
          "vc_VariableArbChain",
          vc_reqs,
          vc_grants,
          expected[N-1:0],
          $sformatf("kin=%b priority=%0d", vc_kin, priority_index)
        );
        if(vc_kout !== expected_kout)
          report_failure(
            "combinational-arbitration",
            tag("vc_VariableArbChain"),
            "kout",
            $sformatf(
              "kin=%b priority=%0d reqs=%b expected=%b actual=%b",
              vc_kin, priority_index, vc_reqs, expected_kout, vc_kout
            )
          );

        v_var_chain++;
        if(vc_kin === 1'b0 && winner >= 0)
          var_chain_cross[c][priority_index][(winner - priority_index + N) % N] = 1'b1;
        if(vc_kin === 1'b0 && request_value == 0)
          var_chain_idle[c] = 1'b1;
        if(vc_kin === 1'b1 && request_value != 0)
          var_chain_kin[c] = 1'b1;
      endfunction

      function automatic void check_var_arb(
          input int priority_index,
          input int request_value
      );
        logic [MAX_N-1:0] reqs;
        logic [MAX_N-1:0] expected;
        int               winner;

        reqs = '0;
        reqs[N-1:0] = va_reqs;
        winner = pick_first(N, priority_index, reqs);
        expected = onehot_of(winner);

        check_common(
          "vc_VariableArb",
          va_reqs,
          va_grants,
          expected[N-1:0],
          $sformatf("priority=%0d", priority_index)
        );

        v_var_arb++;
        if(winner >= 0)
          var_arb_cross[c][priority_index][(winner - priority_index + N) % N] = 1'b1;
        if(request_value == 0)
          var_arb_idle[c] = 1'b1;
      endfunction

      initial begin
        logic [MAX_N-1:0] priority_vector;

        fc_kin  = 1'b0;
        fc_reqs = '0;
        fa_reqs = '0;
        vc_kin  = 1'b0;
        vc_prio = 1;
        vc_reqs = '0;
        va_prio = 1;
        va_reqs = '0;
        #1;

        for(int kin_value = 0; kin_value < 2; kin_value++)
          for(int request_value = 0; request_value < (1 << N); request_value++) begin
            fc_kin  = kin_value[0];
            fc_reqs = request_value[N-1:0];
            #1;
            check_fixed_chain(request_value);
          end

        for(int request_value = 0; request_value < (1 << N); request_value++) begin
          fa_reqs = request_value[N-1:0];
          #1;
          check_fixed_arb(request_value);
        end

        for(int kin_value = 0; kin_value < 2; kin_value++)
          for(int priority_index = 0; priority_index < N; priority_index++) begin
            priority_vector = onehot_of(priority_index);
            for(int request_value = 0; request_value < (1 << N); request_value++) begin
              vc_kin  = kin_value[0];
              vc_prio = priority_vector[N-1:0];
              vc_reqs = request_value[N-1:0];
              #1;
              check_var_chain(priority_index, request_value);
            end
          end

        for(int priority_index = 0; priority_index < N; priority_index++) begin
          priority_vector = onehot_of(priority_index);
          for(int request_value = 0; request_value < (1 << N); request_value++) begin
            va_prio = priority_vector[N-1:0];
            va_reqs = request_value[N-1:0];
            #1;
            check_var_arb(priority_index, request_value);
          end
        end

        done_count++;
      end
    end
  endgenerate

  //--------------------------------------------------------------------------
  // vc_RoundRobinArbChain: both reset priority parameters
  //--------------------------------------------------------------------------

  generate
    for(genvar v = 0; v < 2; v++) begin : g_rr_chain
      for(genvar c = 0; c < RR_COUNT; c++) begin : cfg
        localparam int N          = RR_N[c];
        localparam int RSTN_INDEX = (v == 0) ? 0 : (N - 1);
        localparam int RSTN_VALUE = (v == 0) ? 1 : (1 << (N - 1));

        logic         rstn;
        logic         kin;
        logic [N-1:0] reqs;
        logic [N-1:0] grants;
        logic         kout;

        int               m_state;
        int               m_next;
        int               tick;
        logic [MAX_N-1:0] prev_reqs;
        logic [MAX_N-1:0] prev_grants;

        vc_RoundRobinArbChain #(N, RSTN_VALUE) u_rr_chain (
          .clock (clock ),
          .rstn  (rstn  ),
          .kin   (kin   ),
          .reqs  (reqs  ),
          .grants(grants),
          .kout  (kout  )
        );

        function automatic string tag();
          tag = $sformatf(
            "vc_RoundRobinArbChain[N=%0d,rstn_index=%0d]", N, RSTN_INDEX
          );
        endfunction

        function automatic int evaluate();
          logic [MAX_N-1:0] reqs_wide;
          logic [MAX_N-1:0] expected;
          logic             expected_kout;
          int               winner;

          reqs_wide = '0;
          reqs_wide[N-1:0] = reqs;
          winner = (kin === 1'b1) ? -1 : pick_first(N, m_state, reqs_wide);
          expected = onehot_of(winner);
          expected_kout = (|reqs) | kin;

          if(grants !== expected[N-1:0])
            report_failure(
              "round-robin-rotation",
              tag(),
              "grants",
              $sformatf(
                "cycle=%0d rstn=%b kin=%b state=%0d reqs=%b expected=%b actual=%b prev_reqs=%b prev_grants=%b",
                tick, rstn, kin, m_state, reqs, expected[N-1:0], grants,
                prev_reqs[N-1:0], prev_grants[N-1:0]
              )
            );
          if(!$onehot0(grants))
            report_failure(
              "round-robin-rotation",
              tag(),
              "one-hot-grant",
              $sformatf(
                "cycle=%0d state=%0d reqs=%b actual=%b", tick, m_state, reqs, grants
              )
            );
          if((grants & ~reqs) != '0)
            report_failure(
              "round-robin-rotation",
              tag(),
              "grant-implies-request",
              $sformatf(
                "cycle=%0d state=%0d reqs=%b actual=%b", tick, m_state, reqs, grants
              )
            );
          if(kout !== expected_kout)
            report_failure(
              "round-robin-rotation",
              tag(),
              "kout",
              $sformatf(
                "cycle=%0d kin=%b reqs=%b expected=%b actual=%b",
                tick, kin, reqs, expected_kout, kout
              )
            );

          v_rr_chain++;
          rr_state[v][c][m_state] = 1'b1;
          if(winner >= 0)
            rr_winner[v][c][winner] = 1'b1;
          if(rstn === 1'b0)
            rr_reset[v][c] = 1'b1;
          if(rstn === 1'b1 && reqs == '0 && grants == '0)
            rr_idle[v][c] = 1'b1;
          if(kin === 1'b1 && reqs != '0 && grants == '0)
            rr_kin[v][c] = 1'b1;

          prev_reqs = reqs_wide;
          prev_grants = '0;
          prev_grants[N-1:0] = grants;
          tick++;
          evaluate = winner;
        endfunction

        // Applies the state established by the edge and the cycle stimulus.
        function automatic void drive(
            input logic             rstn_value,
            input logic             kin_value,
            input logic [MAX_N-1:0] reqs_value
        );
          m_state = m_next;
          rstn = rstn_value;
          kin  = kin_value;
          reqs = reqs_value[N-1:0];
          if(rstn === 1'b0)
            m_state = RSTN_INDEX;
        endfunction

        // Checks the settled cycle and computes the next rotation state.
        function automatic int commit();
          int winner;
          winner = evaluate();
          if(rstn === 1'b0)
            m_next = RSTN_INDEX;
          else
            m_next = (winner >= 0) ? ((winner + 1) % N) : m_state;
          commit = winner;
        endfunction

        // One clock cycle: drive after the edge, sample mid-cycle.
        task automatic cycle(
            input logic             rstn_value,
            input logic             kin_value,
            input logic [MAX_N-1:0] reqs_value
        );
          @(posedge clock);
          #1;
          drive(rstn_value, kin_value, reqs_value);
          @(negedge clock);
          void'(commit());
        endtask

        // Mid-cycle asynchronous reset; grants are combinational so the reset
        // priority must appear without a clock edge.
        task automatic async_reset_check(input logic [MAX_N-1:0] reqs_value);
          @(posedge clock);
          #1;
          m_state = m_next;
          rstn = 1'b1;
          kin  = 1'b0;
          reqs = reqs_value[N-1:0];
          @(negedge clock);
          rstn = 1'b0;
          #1;
          m_state = RSTN_INDEX;
          void'(evaluate());
          m_next = RSTN_INDEX;
        endtask

        initial begin
          logic [MAX_N-1:0] all_reqs;
          bit               seen [0:MAX_N-1];
          int               winner;

          all_reqs = '0;
          all_reqs[N-1:0] = '1;
          rstn = 1'b0;
          kin  = 1'b0;
          reqs = '0;
          m_state = RSTN_INDEX;
          m_next  = RSTN_INDEX;
          tick    = 0;
          prev_reqs   = '0;
          prev_grants = '0;

          // Reset held: the priority state must not advance.
          repeat(3) cycle(1'b0, 1'b0, all_reqs);
          async_reset_check(all_reqs);

          // Released with no requests: no grant, state frozen.
          repeat(2) cycle(1'b1, 1'b0, '0);

          // Exhaustive (priority state, request vector) sweep. The first cycle
          // of each pair steers the rotation to the wanted state.
          for(int priority_index = 0; priority_index < N; priority_index++)
            for(int request_value = 0; request_value < (1 << N); request_value++) begin
              cycle(1'b1, 1'b0, onehot_of((priority_index + N - 1) % N));
              cycle(1'b1, 1'b0, wide(request_value));
            end

          // Destination stall: kin blocks the grant and freezes rotation.
          cycle(1'b1, 1'b0, onehot_of(N - 1));
          repeat(2) cycle(1'b1, 1'b1, all_reqs);
          cycle(1'b1, 1'b0, all_reqs);

          // Bounded fairness: every requester wins inside one N cycle window.
          for(int index = 0; index < MAX_N; index++)
            seen[index] = 1'b0;
          cycle(1'b1, 1'b0, all_reqs);
          for(int window = 0; window < N; window++) begin
            @(posedge clock);
            #1;
            drive(1'b1, 1'b0, all_reqs);
            @(negedge clock);
            winner = commit();
            if(winner >= 0)
              seen[winner] = 1'b1;
          end
          for(int index = 0; index < N; index++)
            if(!seen[index])
              report_failure(
                "round-robin-rotation",
                tag(),
                "fairness-bound",
                $sformatf(
                  "requester %0d starved inside a %0d cycle window", index, N
                )
              );
          if(seen[N-1])
            rr_fair[v][c] = 1'b1;

          // A single held request wins every cycle.
          repeat(3) cycle(1'b1, 1'b0, onehot_of(0));

          done_count++;
        end
      end
    end
  endgenerate

  //--------------------------------------------------------------------------
  // vc_RoundRobinArb
  //--------------------------------------------------------------------------

  generate
    for(genvar c = 0; c < RR_COUNT; c++) begin : g_rr_arb
      localparam int N = RR_N[c];

      logic         rstn;
      logic [N-1:0] reqs;
      logic [N-1:0] grants;

      int               m_state;
      int               m_next;
      int               tick;
      logic [MAX_N-1:0] prev_reqs;
      logic [MAX_N-1:0] prev_grants;

      vc_RoundRobinArb #(N) u_rr_arb (
        .clock (clock ),
        .rstn  (rstn  ),
        .reqs  (reqs  ),
        .grants(grants)
      );

      function automatic string tag();
        tag = $sformatf("vc_RoundRobinArb[N=%0d]", N);
      endfunction

      function automatic int evaluate();
        logic [MAX_N-1:0] reqs_wide;
        logic [MAX_N-1:0] expected;
        int               winner;

        reqs_wide = '0;
        reqs_wide[N-1:0] = reqs;
        winner = pick_first(N, m_state, reqs_wide);
        expected = onehot_of(winner);

        if(grants !== expected[N-1:0])
          report_failure(
            "round-robin-rotation",
            tag(),
            "grants",
            $sformatf(
              "cycle=%0d rstn=%b state=%0d reqs=%b expected=%b actual=%b prev_reqs=%b prev_grants=%b",
              tick, rstn, m_state, reqs, expected[N-1:0], grants,
              prev_reqs[N-1:0], prev_grants[N-1:0]
            )
          );
        if(!$onehot0(grants))
          report_failure(
            "round-robin-rotation",
            tag(),
            "one-hot-grant",
            $sformatf(
              "cycle=%0d state=%0d reqs=%b actual=%b", tick, m_state, reqs, grants
            )
          );
        if((grants & ~reqs) != '0)
          report_failure(
            "round-robin-rotation",
            tag(),
            "grant-implies-request",
            $sformatf(
              "cycle=%0d state=%0d reqs=%b actual=%b", tick, m_state, reqs, grants
            )
          );

        v_rr_arb++;
        rr_state[2][c][m_state] = 1'b1;
        if(winner >= 0)
          rr_winner[2][c][winner] = 1'b1;
        if(rstn === 1'b0)
          rr_reset[2][c] = 1'b1;
        if(rstn === 1'b1 && reqs == '0 && grants == '0)
          rr_idle[2][c] = 1'b1;

        prev_reqs = reqs_wide;
        prev_grants = '0;
        prev_grants[N-1:0] = grants;
        tick++;
        evaluate = winner;
      endfunction

      function automatic void drive(
          input logic             rstn_value,
          input logic [MAX_N-1:0] reqs_value
      );
        m_state = m_next;
        rstn = rstn_value;
        reqs = reqs_value[N-1:0];
        if(rstn === 1'b0)
          m_state = 0;
      endfunction

      function automatic int commit();
        int winner;
        winner = evaluate();
        if(rstn === 1'b0)
          m_next = 0;
        else
          m_next = (winner >= 0) ? ((winner + 1) % N) : m_state;
        commit = winner;
      endfunction

      task automatic cycle(
          input logic             rstn_value,
          input logic [MAX_N-1:0] reqs_value
      );
        @(posedge clock);
        #1;
        drive(rstn_value, reqs_value);
        @(negedge clock);
        void'(commit());
      endtask

      task automatic async_reset_check(input logic [MAX_N-1:0] reqs_value);
        @(posedge clock);
        #1;
        m_state = m_next;
        rstn = 1'b1;
        reqs = reqs_value[N-1:0];
        @(negedge clock);
        rstn = 1'b0;
        #1;
        m_state = 0;
        void'(evaluate());
        m_next = 0;
      endtask

      initial begin
        logic [MAX_N-1:0] all_reqs;
        bit               seen [0:MAX_N-1];
        int               winner;

        all_reqs = '0;
        all_reqs[N-1:0] = '1;
        rstn = 1'b0;
        reqs = '0;
        m_state = 0;
        m_next  = 0;
        tick    = 0;
        prev_reqs   = '0;
        prev_grants = '0;

        repeat(3) cycle(1'b0, all_reqs);
        async_reset_check(all_reqs);

        repeat(2) cycle(1'b1, '0);

        for(int priority_index = 0; priority_index < N; priority_index++)
          for(int request_value = 0; request_value < (1 << N); request_value++) begin
            cycle(1'b1, onehot_of((priority_index + N - 1) % N));
            cycle(1'b1, wide(request_value));
          end

        for(int index = 0; index < MAX_N; index++)
          seen[index] = 1'b0;
        cycle(1'b1, all_reqs);
        for(int window = 0; window < N; window++) begin
          @(posedge clock);
          #1;
          drive(1'b1, all_reqs);
          @(negedge clock);
          winner = commit();
          if(winner >= 0)
            seen[winner] = 1'b1;
        end
        for(int index = 0; index < N; index++)
          if(!seen[index])
            report_failure(
              "round-robin-rotation",
              tag(),
              "fairness-bound",
              $sformatf("requester %0d starved inside a %0d cycle window", index, N)
            );
        if(seen[N-1])
          rr_fair[2][c] = 1'b1;

        repeat(3) cycle(1'b1, onehot_of(0));

        done_count++;
      end
    end
  endgenerate

  //--------------------------------------------------------------------------
  // vc_RoundRobinArb_V2: masked round robin with a registered grant
  //--------------------------------------------------------------------------

  generate
    for(genvar c = 0; c < RR_COUNT; c++) begin : g_rr_v2
      localparam int N = RR_N[c];

      logic         rstn;
      logic [N-1:0] reqs;
      logic [N-1:0] grants;

      int               m_base;
      int               m_next_base;
      logic [MAX_N-1:0] m_grants;
      logic [MAX_N-1:0] m_next_grants;
      int               tick;
      logic [MAX_N-1:0] prev_reqs;
      logic [MAX_N-1:0] prev_grants;

      vc_RoundRobinArb_V2 #(N) u_rr_v2 (
        .clock (clock ),
        .rstn  (rstn  ),
        .reqs  (reqs  ),
        .grants(grants)
      );

      function automatic string tag();
        tag = $sformatf("vc_RoundRobinArb_V2[N=%0d]", N);
      endfunction

      function automatic int evaluate();
        logic [MAX_N-1:0] reqs_wide;
        int               winner;

        reqs_wide = '0;
        reqs_wide[N-1:0] = reqs;

        if(grants !== m_grants[N-1:0])
          report_failure(
            "round-robin-rotation",
            tag(),
            "grants",
            $sformatf(
              "cycle=%0d rstn=%b base=%0d reqs=%b expected=%b actual=%b prev_reqs=%b prev_grants=%b",
              tick, rstn, m_base, reqs, m_grants[N-1:0], grants,
              prev_reqs[N-1:0], prev_grants[N-1:0]
            )
          );
        if(!$onehot0(grants))
          report_failure(
            "round-robin-rotation",
            tag(),
            "one-hot-grant",
            $sformatf(
              "cycle=%0d base=%0d reqs=%b actual=%b", tick, m_base, reqs, grants
            )
          );

        v_rr_v2++;
        rr_state[3][c][m_base] = 1'b1;
        winner = index_of(m_grants);
        if(winner >= 0)
          rr_winner[3][c][winner] = 1'b1;
        if(rstn === 1'b0)
          rr_reset[3][c] = 1'b1;
        if(rstn === 1'b1 && reqs == '0 && grants == '0)
          rr_idle[3][c] = 1'b1;

        prev_reqs = reqs_wide;
        prev_grants = '0;
        prev_grants[N-1:0] = grants;
        tick++;
        evaluate = winner;
      endfunction

      function automatic void drive(
          input logic             rstn_value,
          input logic [MAX_N-1:0] reqs_value
      );
        m_base   = m_next_base;
        m_grants = m_next_grants;
        rstn = rstn_value;
        reqs = reqs_value[N-1:0];
        if(rstn === 1'b0) begin
          m_base   = 0;
          m_grants = '0;
        end
      endfunction

      function automatic int commit();
        logic [MAX_N-1:0] reqs_wide;
        int               winner;
        int               granted;

        granted = evaluate();

        reqs_wide = '0;
        reqs_wide[N-1:0] = reqs;
        winner = pick_first(N, m_base, reqs_wide);
        if(rstn === 1'b0) begin
          m_next_base   = 0;
          m_next_grants = '0;
        end else begin
          m_next_grants = onehot_of(winner) & ~m_grants;
          m_next_base   = (granted >= 0) ? ((granted + 1) % N) : m_base;
        end
        commit = granted;
      endfunction

      task automatic cycle(
          input logic             rstn_value,
          input logic [MAX_N-1:0] reqs_value
      );
        @(posedge clock);
        #1;
        drive(rstn_value, reqs_value);
        @(negedge clock);
        void'(commit());
      endtask

      // Mid-cycle asynchronous reset clears the registered grant immediately.
      task automatic async_reset_check(input logic [MAX_N-1:0] reqs_value);
        @(posedge clock);
        #1;
        m_base   = m_next_base;
        m_grants = m_next_grants;
        rstn = 1'b1;
        reqs = reqs_value[N-1:0];
        @(negedge clock);
        rstn = 1'b0;
        #1;
        m_base   = 0;
        m_grants = '0;
        void'(evaluate());
        m_next_base   = 0;
        m_next_grants = '0;
      endtask

      initial begin
        logic [MAX_N-1:0] all_reqs;
        bit               seen [0:MAX_N-1];
        int               granted;

        all_reqs = '0;
        all_reqs[N-1:0] = '1;
        rstn = 1'b0;
        reqs = '0;
        m_base        = 0;
        m_next_base   = 0;
        m_grants      = '0;
        m_next_grants = '0;
        tick          = 0;
        prev_reqs     = '0;
        prev_grants   = '0;

        repeat(3) cycle(1'b0, all_reqs);
        async_reset_check(all_reqs);

        repeat(2) cycle(1'b1, '0);

        // The steering pair drives the rotation pointer to a known base and
        // leaves the registered grant clear; the request pair then exposes the
        // grant and its one cycle blackout.
        for(int base_index = 0; base_index < N; base_index++)
          for(int request_value = 0; request_value < (1 << N); request_value++) begin
            repeat(2) cycle(1'b1, onehot_of((base_index + N - 1) % N));
            repeat(2) cycle(1'b1, wide(request_value));
          end

        // Bounded fairness: the blackout halves throughput so the window is 2N.
        for(int index = 0; index < MAX_N; index++)
          seen[index] = 1'b0;
        repeat(2) cycle(1'b1, all_reqs);
        for(int window = 0; window < 2 * N; window++) begin
          @(posedge clock);
          #1;
          drive(1'b1, all_reqs);
          @(negedge clock);
          granted = commit();
          if(granted >= 0)
            seen[granted] = 1'b1;
        end
        for(int index = 0; index < N; index++)
          if(!seen[index])
            report_failure(
              "round-robin-rotation",
              tag(),
              "fairness-bound",
              $sformatf(
                "requester %0d starved inside a %0d cycle window", index, 2 * N
              )
            );
        if(seen[N-1])
          rr_fair[3][c] = 1'b1;

        repeat(4) cycle(1'b1, onehot_of(0));

        done_count++;
      end
    end
  endgenerate

  //--------------------------------------------------------------------------
  // Fan-in wrappers: N payload buffers arbitrated onto one output
  //--------------------------------------------------------------------------

  generate
    for(genvar m = 0; m < 2; m++) begin : g_fanin
      for(genvar c = 0; c < WRAP_COUNT; c++) begin : cfg
        localparam int N = WRAP_N[c];
        localparam int W = WRAP_W[c];

        logic         rstn;
        logic         enabled;
        logic [0:W-1] buffer_in [0:N-1];
        logic [N-1:0] submit;
        logic [N-1:0] requests;
        logic [0:W-1] arbiter_out;
        logic [N-1:0] ready;

        int               tick;
        int               m_rr_state;
        int               m_rr_next;
        logic [MAX_N-1:0] m_grant;
        logic [MAX_N-1:0] m_grant_reg;
        logic [MAX_N-1:0] m_grant_latched;
        logic             m_enabled_internal;
        logic [MAX_N-1:0] m_ready;
        logic [0:W-1]     m_out;

        logic [0:W-1]     payload_pattern;
        logic [0:W-1]     payload_marker;
        bit               cur_align;
        bit               prev_align;
        logic             prev_rstn;
        logic             prev_gate;
        logic [MAX_N-1:0] prev_submit;
        logic [MAX_N-1:0] prev_publish;

        if(m == 0) begin : dut
          fixed_priority_arbiter_N_input_1_ouput #(N, W) u_fanin (
            .clock      (clock      ),
            .rstn       (rstn       ),
            .enabled    (enabled    ),
            .buffer_in  (buffer_in  ),
            .submit     (submit     ),
            .requests   (requests   ),
            .arbiter_out(arbiter_out),
            .ready      (ready      )
          );
        end else begin : dut
          round_robin_priority_arbiter_N_input_1_ouput #(N, W) u_fanin (
            .clock      (clock      ),
            .rstn       (rstn       ),
            .enabled    (enabled    ),
            .buffer_in  (buffer_in  ),
            .submit     (submit     ),
            .requests   (requests   ),
            .arbiter_out(arbiter_out),
            .ready      (ready      )
          );
        end

        function automatic string tag();
          string module_name;
          if(m == 0)
            module_name = "fixed_priority_arbiter_N_input_1_ouput";
          else
            module_name = "round_robin_priority_arbiter_N_input_1_ouput";
          tag = $sformatf("%0s[N=%0d,W=%0d]", module_name, N, W);
        endfunction

        // Alternating payload stripe; consecutive ticks invert every bit so
        // the payload buses reach both toggle polarities.
        function automatic logic [0:W-1] stripe(input int phase);
          for(int position = 0; position < W; position++)
            stripe[position] = logic'((phase + position) % 2);
        endfunction

        // Publication gate seen by the output register this cycle. The
        // round-robin wrapper delays `enabled` by one cycle.
        function automatic logic gate_now();
          gate_now = (m == 0) ? enabled : m_enabled_internal;
        endfunction

        // Combinational grant presented to the wrapper this cycle.
        function automatic logic [MAX_N-1:0] current_grant();
          logic [MAX_N-1:0] reqs_wide;
          if(N == 1)
            return m_grant_reg;
          reqs_wide = '0;
          reqs_wide[N-1:0] = requests;
          if(m == 0)
            return onehot_of(pick_first(N, 0, reqs_wide));
          return onehot_of(pick_first(N, m_rr_state, reqs_wide));
        endfunction

        function automatic void evaluate();
          if(ready !== m_ready[N-1:0])
            report_failure(
              "wrapper-fan-in",
              tag(),
              "ready",
              $sformatf(
                "cycle=%0d rstn=%b enabled=%b requests=%b submit=%b expected=%b actual=%b",
                tick, rstn, enabled, requests, submit, m_ready[N-1:0], ready
              )
            );
          if(arbiter_out !== m_out)
            report_failure(
              "wrapper-fan-in",
              tag(),
              "payload",
              $sformatf(
                "cycle=%0d rstn=%b enabled=%b requests=%b submit=%b expected=%0h actual=%0h",
                tick, rstn, enabled, requests, submit, m_out, arbiter_out
              )
            );
          if(!$onehot0(ready))
            report_failure(
              "wrapper-fan-in",
              tag(),
              "one-hot-grant",
              $sformatf("cycle=%0d requests=%b actual=%b", tick, requests, ready)
            );

          v_wrap_fanin++;
          if(rstn === 1'b0)
            wrap_fanin_reset[m][c] = 1'b1;
          if(rstn === 1'b1 && gate_now() === 1'b0)
            wrap_fanin_stall[m][c] = 1'b1;
          if(prev_rstn === 1'b1 && prev_gate === 1'b1 && prev_submit == '0 &&
             m_out == '0)
            wrap_fanin_clear[m][c] = 1'b1;
          if(prev_rstn === 1'b1 && prev_gate === 1'b1 &&
             $countones(prev_submit[N-1:0]) > 1)
            wrap_fanin_multi[m][c] = 1'b1;
          if(prev_publish != '0)
            wrap_fanin_source[m][c][index_of(prev_publish)] = 1'b1;
          // The payload followed the delayed winner even though a higher
          // indexed requester was submitting in the same cycle.
          if(prev_rstn === 1'b1 && prev_gate === 1'b1 &&
             $countones(prev_submit[N-1:0]) > 1 && prev_publish != '0 &&
             index_of(prev_publish) != last_index_of(N, prev_submit))
            wrap_fanin_aligned[m][c] = 1'b1;
          // Submitters that never owned the delayed grant publish nothing.
          if(prev_rstn === 1'b1 && prev_gate === 1'b1 && prev_submit != '0 &&
             prev_publish == '0 && m_out == '0)
            wrap_fanin_miss[m][c] = 1'b1;
          if(prev_gate === 1'b0 && gate_now() === 1'b1)
            wrap_fanin_resume[m][c] = 1'b1;
          tick++;
        endfunction

        // Applies one clock edge worth of model state updates. ready takes
        // the current winner while the payload is published against the grant
        // that was advertised one cycle earlier, which is the grant that made
        // the requester pop its buffer.
        function automatic void advance();
          logic             gate;
          logic [MAX_N-1:0] submit_wide;
          logic [MAX_N-1:0] publish;
          int               select_index;

          gate = gate_now();
          submit_wide = '0;
          submit_wide[N-1:0] = submit;
          publish = m_grant_latched & submit_wide;

          if(rstn === 1'b0) begin
            m_ready         = '0;
            m_out           = '0;
            m_grant_reg     = '0;
            m_grant_latched = '0;
            m_rr_next       = 0;
            m_enabled_internal = 1'b0;
            publish = '0;
          end else begin
            if(gate === 1'b1) begin
              select_index = index_of(publish);
              if(select_index >= 0)
                m_out = buffer_in[select_index];
              else
                m_out = '0;
              m_grant_latched = m_ready;
              m_ready = '0;
              m_ready[N-1:0] = m_grant[N-1:0];
            end else begin
              publish = '0;
            end
            m_grant_reg = '0;
            m_grant_reg[N-1:0] = requests;
            if(N > 1 && m == 1)
              m_rr_next = (index_of(m_grant) >= 0) ?
                ((index_of(m_grant) + 1) % N) : m_rr_state;
            else
              m_rr_next = 0;
            m_enabled_internal = enabled;
          end

          prev_align   = cur_align;
          prev_rstn    = rstn;
          prev_gate    = gate;
          prev_submit  = submit_wide;
          prev_publish = publish;
        endfunction

        task automatic cycle(
            input logic             rstn_value,
            input logic             enabled_value,
            input logic [MAX_N-1:0] request_value,
            input bit               align_submit,
            input logic [MAX_N-1:0] submit_value
        );
          @(posedge clock);
          #1;
          rstn     = rstn_value;
          enabled  = enabled_value;
          requests = request_value[N-1:0];
          payload_pattern = stripe(tick);
          for(int index = 0; index < N; index++) begin
            payload_marker = index + 1;
            buffer_in[index] = payload_pattern ^ payload_marker;
          end
          if(rstn === 1'b0) begin
            m_ready         = '0;
            m_out           = '0;
            m_grant_reg     = '0;
            m_grant_latched = '0;
            m_rr_state      = 0;
            m_rr_next       = 0;
            m_enabled_internal = 1'b0;
          end
          m_rr_state = m_rr_next;
          m_grant    = current_grant();
          cur_align  = align_submit;
          // A requester submits its data on the cycle after it saw ready.
          submit     = align_submit ? m_grant_latched[N-1:0] : submit_value[N-1:0];
          @(negedge clock);
          evaluate();
          advance();
        endtask

        initial begin
          logic [MAX_N-1:0] all_reqs;

          all_reqs = '0;
          all_reqs[N-1:0] = '1;
          rstn     = 1'b0;
          enabled  = 1'b1;
          requests = '0;
          submit   = '0;
          for(int index = 0; index < N; index++)
            buffer_in[index] = '0;
          tick        = 0;
          m_rr_state  = 0;
          m_rr_next   = 0;
          m_grant         = '0;
          m_grant_reg     = '0;
          m_grant_latched = '0;
          m_enabled_internal = 1'b0;
          m_ready      = '0;
          m_out        = '0;
          cur_align    = 1'b0;
          prev_align   = 1'b0;
          prev_rstn    = 1'b0;
          prev_gate    = 1'b0;
          prev_submit  = '0;
          prev_publish = '0;

          // Reset drives both outputs to zero.
          repeat(2) cycle(1'b0, 1'b1, all_reqs, 1'b0, all_reqs);

          // Aligned payload and grant traffic over every request pattern,
          // then drain the request/grant/submit pipeline.
          for(int request_value = 1; request_value < (1 << N); request_value++)
            cycle(1'b1, 1'b1, wide(request_value), 1'b1, '0);
          repeat(3) cycle(1'b1, 1'b1, all_reqs, 1'b1, '0);

          // Submit deasserted clears the published payload.
          repeat(2) cycle(1'b1, 1'b1, all_reqs, 1'b0, '0);

          // Destination stall: outputs hold while the wrapper is disabled and
          // resume on release.
          repeat(3) cycle(1'b1, 1'b0, all_reqs, 1'b0, all_reqs);
          repeat(2) cycle(1'b1, 1'b1, all_reqs, 1'b1, '0);

          // Multi-hot submit: the payload must follow the delayed winner,
          // not the highest submitter.
          if(N > 1)
            repeat(3) cycle(1'b1, 1'b1, all_reqs, 1'b0, all_reqs);

          // Submitting without ever owning the grant publishes nothing.
          repeat(4) cycle(1'b1, 1'b1, '0, 1'b0, all_reqs);

          // No request at all: no grant and no published payload.
          repeat(2) cycle(1'b1, 1'b1, '0, 1'b1, '0);

          // Payload polarity sweep: hold one source so its buffer reaches both
          // stripe polarities on the shared output.
          for(int source = 0; source < N; source++)
            repeat(4) cycle(1'b1, 1'b1, onehot_of(source), 1'b1, '0);

          // Asynchronous reset in the middle of a cycle.
          @(posedge clock);
          #1;
          rstn     = 1'b1;
          enabled  = 1'b1;
          requests = all_reqs[N-1:0];
          payload_pattern = stripe(tick);
          for(int index = 0; index < N; index++) begin
            payload_marker = index + 1;
            buffer_in[index] = payload_pattern ^ payload_marker;
          end
          m_rr_state = m_rr_next;
          m_grant    = current_grant();
          cur_align  = 1'b1;
          submit     = m_grant_latched[N-1:0];
          @(negedge clock);
          evaluate();
          rstn    = 1'b0;
          #1;
          m_ready = '0;
          m_out   = '0;
          m_grant_latched = '0;
          evaluate();
          advance();
          @(posedge clock);
          #1;
          rstn = 1'b1;

          done_count++;
        end
      end
    end
  endgenerate

  //--------------------------------------------------------------------------
  // Fan-out wrappers: one payload distributed to N destinations
  //--------------------------------------------------------------------------

  generate
    for(genvar m = 0; m < 2; m++) begin : g_fanout
      for(genvar c = 0; c < WRAP_COUNT; c++) begin : cfg
        localparam int N = WRAP_N[c];
        localparam int W = WRAP_W[c];

        logic         rstn;
        logic         enabled;
        logic [0:W-1] buffer_in;
        logic [N-1:0] requests;
        logic [0:W-1] arbiter_out [0:N-1];
        logic [N-1:0] ready;

        int               tick;
        int               m_rr_state;
        int               m_rr_next;
        logic [MAX_N-1:0] m_grant;
        logic [MAX_N-1:0] m_grant_reg;
        logic [MAX_N-1:0] m_grant_latched;
        logic [MAX_N-1:0] prev_latched;
        logic             prev_enabled;
        logic [0:W-1]     m_out [0:N-1];
        bit               settled;
        bit               had_payload;

        if(m == 0) begin : dut
          fixed_priority_arbiter_1_input_N_ouput #(N, W) u_fanout (
            .clock      (clock      ),
            .rstn       (rstn       ),
            .enabled    (enabled    ),
            .buffer_in  (buffer_in  ),
            .requests   (requests   ),
            .arbiter_out(arbiter_out),
            .ready      (ready      )
          );
        end else begin : dut
          round_robin_priority_arbiter_1_input_N_ouput #(N, W) u_fanout (
            .clock      (clock      ),
            .rstn       (rstn       ),
            .enabled    (enabled    ),
            .buffer_in  (buffer_in  ),
            .requests   (requests   ),
            .arbiter_out(arbiter_out),
            .ready      (ready      )
          );
        end

        function automatic string tag();
          string module_name;
          if(m == 0)
            module_name = "fixed_priority_arbiter_1_input_N_ouput";
          else
            module_name = "round_robin_priority_arbiter_1_input_N_ouput";
          tag = $sformatf("%0s[N=%0d,W=%0d]", module_name, N, W);
        endfunction

        function automatic logic [MAX_N-1:0] current_grant();
          logic [MAX_N-1:0] reqs_wide;
          if(N == 1)
            return m_grant_reg;
          reqs_wide = '0;
          reqs_wide[N-1:0] = requests;
          if(m == 0)
            return onehot_of(pick_first(N, 0, reqs_wide));
          return onehot_of(pick_first(N, m_rr_state, reqs_wide));
        endfunction

        // Alternating payload stripe; consecutive ticks invert every bit so
        // the payload buses reach both toggle polarities.
        function automatic logic [0:W-1] stripe(input int phase);
          for(int position = 0; position < W; position++)
            stripe[position] = logic'((phase + position) % 2);
        endfunction

        function automatic void evaluate();
          logic [MAX_N-1:0] expected_ready;
          bit               published;

          expected_ready = '0;
          if(enabled === 1'b1)
            expected_ready[N-1:0] = m_grant_latched[N-1:0];

          if(ready !== expected_ready[N-1:0])
            report_failure(
              "wrapper-fan-out",
              tag(),
              "ready",
              $sformatf(
                "cycle=%0d rstn=%b enabled=%b requests=%b expected=%b actual=%b",
                tick, rstn, enabled, requests, expected_ready[N-1:0], ready
              )
            );
          if(!$onehot0(ready))
            report_failure(
              "wrapper-fan-out",
              tag(),
              "one-hot-grant",
              $sformatf("cycle=%0d requests=%b actual=%b", tick, requests, ready)
            );

          published = 1'b0;
          if(settled)
            for(int index = 0; index < N; index++) begin
              if(arbiter_out[index] !== m_out[index])
                report_failure(
                  "wrapper-fan-out",
                  tag(),
                  "payload",
                  $sformatf(
                    "cycle=%0d rstn=%b enabled=%b destination=%0d requests=%b expected=%0h actual=%0h",
                    tick, rstn, enabled, index, requests,
                    m_out[index], arbiter_out[index]
                  )
                );
              if(prev_latched[index] === 1'b1)
                wrap_fanout_dest[m][c][index] = 1'b1;
              if(m_out[index] != '0)
                published = 1'b1;
            end
          if(published)
            had_payload = 1'b1;

          v_wrap_fanout++;
          if(rstn === 1'b0)
            wrap_fanout_reset[m][c] = 1'b1;
          if(rstn === 1'b1 && enabled === 1'b0)
            wrap_fanout_stall[m][c] = 1'b1;
          if(rstn === 1'b1 && enabled === 1'b1 && prev_enabled === 1'b0)
            wrap_fanout_resume[m][c] = 1'b1;
          // Reset must drop a payload that was already published.
          if(rstn === 1'b0 && settled && had_payload && !published)
            wrap_fanout_clear[m][c] = 1'b1;
          // Only the granted destination carries the payload; the rest read
          // zero. With one destination the same property is the idle case.
          if(settled && N > 1 && $onehot(prev_latched[N-1:0]))
            wrap_fanout_zero[m][c] = 1'b1;
          if(settled && N == 1 && prev_latched[N-1:0] == '0)
            wrap_fanout_zero[m][c] = 1'b1;
          tick++;
        endfunction

        function automatic void advance();
          logic [MAX_N-1:0] latched_now;

          latched_now = m_grant_latched;
          prev_latched = latched_now;
          // arbiter_out has no reset in the production wrapper.
          for(int index = 0; index < N; index++)
            m_out[index] = latched_now[index] ? buffer_in : {W{1'b0}};
          prev_enabled = enabled;
          if(rstn === 1'b0) begin
            m_grant_latched = '0;
            m_grant_reg     = '0;
            m_rr_next       = 0;
          end else begin
            if(enabled === 1'b1)
              m_grant_latched = m_grant;
            m_grant_reg = '0;
            m_grant_reg[N-1:0] = requests;
            if(N > 1 && m == 1)
              m_rr_next = (index_of(m_grant) >= 0) ?
                ((index_of(m_grant) + 1) % N) : m_rr_state;
            else
              m_rr_next = 0;
          end
          settled = 1'b1;
        endfunction

        task automatic cycle(
            input logic             rstn_value,
            input logic             enabled_value,
            input logic [MAX_N-1:0] request_value
        );
          @(posedge clock);
          #1;
          rstn      = rstn_value;
          enabled   = enabled_value;
          requests  = request_value[N-1:0];
          buffer_in = stripe(tick);
          if(rstn === 1'b0) begin
            m_grant_latched = '0;
            m_grant_reg     = '0;
            m_rr_state      = 0;
            m_rr_next       = 0;
            prev_latched    = '0;
            for(int index = 0; index < N; index++)
              m_out[index] = '0;
          end
          m_rr_state = m_rr_next;
          m_grant    = current_grant();
          @(negedge clock);
          evaluate();
          advance();
        endtask

        initial begin
          logic [MAX_N-1:0] all_reqs;

          all_reqs = '0;
          all_reqs[N-1:0] = '1;
          rstn      = 1'b0;
          enabled   = 1'b1;
          requests  = '0;
          buffer_in = '0;
          tick      = 0;
          settled   = 1'b0;
          m_rr_state      = 0;
          m_rr_next       = 0;
          m_grant         = '0;
          m_grant_reg     = '0;
          m_grant_latched = '0;
          prev_latched    = '0;
          prev_enabled    = 1'b0;
          had_payload     = 1'b0;
          for(int index = 0; index < N; index++)
            m_out[index] = '0;

          repeat(2) cycle(1'b0, 1'b1, all_reqs);

          for(int request_value = 1; request_value < (1 << N); request_value++)
            cycle(1'b1, 1'b1, wide(request_value));
          repeat(2) cycle(1'b1, 1'b1, all_reqs);

          // Destination stall: ready drops, the latched grant freezes and
          // publication resumes on release.
          repeat(3) cycle(1'b1, 1'b0, all_reqs);
          repeat(2) cycle(1'b1, 1'b1, all_reqs);

          // No request at all: nothing is latched and every destination clears.
          repeat(2) cycle(1'b1, 1'b1, '0);

          // Payload polarity sweep: hold one destination so its output reaches
          // both stripe polarities.
          for(int destination = 0; destination < N; destination++)
            repeat(3) cycle(1'b1, 1'b1, onehot_of(destination));

          // Asynchronous reset in the middle of a cycle clears grant_latched.
          @(posedge clock);
          #1;
          rstn      = 1'b1;
          enabled   = 1'b1;
          requests  = all_reqs[N-1:0];
          buffer_in = stripe(tick);
          m_rr_state = m_rr_next;
          m_grant    = current_grant();
          @(negedge clock);
          evaluate();
          rstn = 1'b0;
          #1;
          m_grant_latched = '0;
          prev_latched    = '0;
          for(int index = 0; index < N; index++)
            m_out[index] = '0;
          evaluate();
          advance();
          @(posedge clock);
          #1;
          rstn = 1'b1;

          done_count++;
        end
      end
    end
  endgenerate

  //--------------------------------------------------------------------------
  // Bin closure and evidence
  //--------------------------------------------------------------------------

  initial begin
    wait(done_count == EXPECTED_DONE);
    #1;

    if(errors != 0) begin
      $display("FAIL arbitration_unit errors=%0d reported=%0d", errors, reports);
      $fatal(1, "arbitration unit checks failed");
    end

    for(int c = 0; c < COMB_COUNT; c++) begin
      for(int index = 0; index < COMB_N[c]; index++) begin
        require_bin(
          fixed_chain_winner[c][index],
          $sformatf("fixed_chain_winner[N=%0d][%0d]", COMB_N[c], index)
        );
        require_bin(
          fixed_arb_winner[c][index],
          $sformatf("fixed_arb_winner[N=%0d][%0d]", COMB_N[c], index)
        );
      end
      require_bin(fixed_chain_idle[c], $sformatf("fixed_chain_idle[N=%0d]", COMB_N[c]));
      require_bin(fixed_chain_kin[c], $sformatf("fixed_chain_kin[N=%0d]", COMB_N[c]));
      require_bin(fixed_chain_all[c], $sformatf("fixed_chain_all[N=%0d]", COMB_N[c]));
      require_bin(fixed_arb_idle[c], $sformatf("fixed_arb_idle[N=%0d]", COMB_N[c]));
      require_bin(fixed_arb_all[c], $sformatf("fixed_arb_all[N=%0d]", COMB_N[c]));
    end

    for(int c = 0; c < COMB_COUNT; c++) begin
      for(int p = 0; p < COMB_N[c]; p++)
        for(int d = 0; d < COMB_N[c]; d++) begin
          require_bin(
            var_chain_cross[c][p][d],
            $sformatf("var_chain_cross[N=%0d][p=%0d][offset=%0d]", COMB_N[c], p, d)
          );
          require_bin(
            var_arb_cross[c][p][d],
            $sformatf("var_arb_cross[N=%0d][p=%0d][offset=%0d]", COMB_N[c], p, d)
          );
        end
      require_bin(var_chain_idle[c], $sformatf("var_chain_idle[N=%0d]", COMB_N[c]));
      require_bin(var_chain_kin[c], $sformatf("var_chain_kin[N=%0d]", COMB_N[c]));
      require_bin(var_arb_idle[c], $sformatf("var_arb_idle[N=%0d]", COMB_N[c]));
    end

    for(int g = 0; g < 4; g++)
      for(int c = 0; c < RR_COUNT; c++) begin
        for(int index = 0; index < RR_N[c]; index++) begin
          require_bin(
            rr_winner[g][c][index],
            $sformatf("rr_winner[group=%0d][N=%0d][%0d]", g, RR_N[c], index)
          );
          require_bin(
            rr_state[g][c][index],
            $sformatf("rr_state[group=%0d][N=%0d][%0d]", g, RR_N[c], index)
          );
        end
        require_bin(rr_fair[g][c], $sformatf("rr_fair[group=%0d][N=%0d]", g, RR_N[c]));
        require_bin(rr_idle[g][c], $sformatf("rr_idle[group=%0d][N=%0d]", g, RR_N[c]));
        require_bin(rr_reset[g][c], $sformatf("rr_reset[group=%0d][N=%0d]", g, RR_N[c]));
      end

    for(int g = 0; g < 2; g++)
      for(int c = 0; c < RR_COUNT; c++)
        require_bin(rr_kin[g][c], $sformatf("rr_kin[group=%0d][N=%0d]", g, RR_N[c]));

    for(int m = 0; m < 2; m++)
      for(int c = 0; c < WRAP_COUNT; c++) begin
        for(int index = 0; index < WRAP_N[c]; index++) begin
          require_bin(
            wrap_fanin_source[m][c][index],
            $sformatf("wrap_fanin_source[module=%0d][cfg=%0d][%0d]", m, c, index)
          );
          require_bin(
            wrap_fanout_dest[m][c][index],
            $sformatf("wrap_fanout_dest[module=%0d][cfg=%0d][%0d]", m, c, index)
          );
        end
        require_bin(
          wrap_fanin_clear[m][c],
          $sformatf("wrap_fanin_clear[module=%0d][cfg=%0d]", m, c)
        );
        require_bin(
          wrap_fanin_stall[m][c],
          $sformatf("wrap_fanin_stall[module=%0d][cfg=%0d]", m, c)
        );
        require_bin(
          wrap_fanin_reset[m][c],
          $sformatf("wrap_fanin_reset[module=%0d][cfg=%0d]", m, c)
        );
        if(WRAP_N[c] > 1) begin
          require_bin(
            wrap_fanin_multi[m][c],
            $sformatf("wrap_fanin_multi[module=%0d][cfg=%0d]", m, c)
          );
          require_bin(
            wrap_fanin_aligned[m][c],
            $sformatf("wrap_fanin_aligned[module=%0d][cfg=%0d]", m, c)
          );
        end
        require_bin(
          wrap_fanin_miss[m][c],
          $sformatf("wrap_fanin_miss[module=%0d][cfg=%0d]", m, c)
        );
        require_bin(
          wrap_fanin_resume[m][c],
          $sformatf("wrap_fanin_resume[module=%0d][cfg=%0d]", m, c)
        );
        require_bin(
          wrap_fanout_zero[m][c],
          $sformatf("wrap_fanout_zero[module=%0d][cfg=%0d]", m, c)
        );
        require_bin(
          wrap_fanout_clear[m][c],
          $sformatf("wrap_fanout_clear[module=%0d][cfg=%0d]", m, c)
        );
        require_bin(
          wrap_fanout_resume[m][c],
          $sformatf("wrap_fanout_resume[module=%0d][cfg=%0d]", m, c)
        );
        require_bin(
          wrap_fanout_stall[m][c],
          $sformatf("wrap_fanout_stall[module=%0d][cfg=%0d]", m, c)
        );
        require_bin(
          wrap_fanout_reset[m][c],
          $sformatf("wrap_fanout_reset[module=%0d][cfg=%0d]", m, c)
        );
      end

    if(errors != 0) begin
      $display("FAIL arbitration_unit missing functional bins errors=%0d", errors);
      $fatal(1, "arbitration unit bin closure failed");
    end

    $display(
      "EVIDENCE arbitration_unit fixed_chain=%0d fixed_arb=%0d var_chain=%0d var_arb=%0d rr_chain=%0d rr_arb=%0d rr_v2=%0d wrap_fanin=%0d wrap_fanout=%0d",
      v_fixed_chain, v_fixed_arb, v_var_chain, v_var_arb,
      v_rr_chain, v_rr_arb, v_rr_v2, v_wrap_fanin, v_wrap_fanout
    );
    $display(
      "PASS arbitration_unit vectors=%0d bins=%0d",
      v_fixed_chain + v_fixed_arb + v_var_chain + v_var_arb +
      v_rr_chain + v_rr_arb + v_rr_v2 + v_wrap_fanin + v_wrap_fanout,
      bins_hit
    );
    $finish;
  end

endmodule
