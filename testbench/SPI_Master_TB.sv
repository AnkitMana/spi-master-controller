
`timescale 1ns / 1ps

module SPI_Master_TB;

  localparam integer HALF_BIT = 2;
  localparam integer NUM_MODES = 4;
  localparam integer MAX_CYCLES = 250;

  reg clk = 1'b0;
  reg [3:0] rst_n = 4'b0000;
  reg [7:0] tx_data [0:3];
  reg [3:0] tx_dv = 4'b0000;
  reg [3:0] miso = 4'b0000;

  wire [3:0] tx_ready;
  wire [3:0] rx_dv;
  wire [7:0] rx_data [0:3];
  wire [3:0] spi_clk;
  wire [3:0] mosi;

  integer total = 0;
  integer passed = 0;
  integer failed = 0;
  integer mode;
  integer bit_index;
  integer pattern_index;

  reg [7:0] patterns [0:17];

  always #5 clk = ~clk;

  // Instantiate four independent DUTs, one for each SPI mode.
  genvar g;
  generate
    for (g = 0; g < NUM_MODES; g = g + 1) begin : GEN_DUT
      SPI_master #(
        .SPI_MODE(g),
        .CLKS_PER_HALF_BIT(HALF_BIT)
      ) dut (
        .i_Rst_L(rst_n[g]),
        .i_Clk(clk),
        .i_TX_Byte(tx_data[g]),
        .i_TX_DV(tx_dv[g]),
        .o_TX_Ready(tx_ready[g]),
        .o_RX_DV(rx_dv[g]),
        .o_RX_Byte(rx_data[g]),
        .o_SPI_Clk(spi_clk[g]),
        .i_SPI_MISO(miso[g]),
        .o_SPI_MOSI(mosi[g])
      );
    end
  endgenerate

  // Every check prints its result.
  task check;
    input condition;
    input [8*120-1:0] message;
    begin
      total = total + 1;

      if (condition === 1'b1) begin
        passed = passed + 1;
        $display("[PASS] %0s", message);
      end
      else begin
        failed = failed + 1;
        $display("[FAIL] %0s", message);
      end
    end
  endtask

  // Wait for a DUT to become ready without hanging the simulation.
  task wait_ready;
    input integer m;
    output reg success;
    integer cycles;
    begin
      success = 1'b0;
      cycles = 0;

      while ((tx_ready[m] !== 1'b1) &&
             (cycles < MAX_CYCLES)) begin
        @(negedge clk);
        cycles = cycles + 1;
      end

      if (tx_ready[m] === 1'b1)
        success = 1'b1;
    end
  endtask

  // One SPI transfer.
  //
  // The testbench models a simple SPI slave:
  // - CPHA=0: first MISO bit is prepared before the transfer.
  // - CPHA=1: first MISO bit is prepared on the first shift edge.
  // - MOSI is captured on the selected sampling edge.
  //
  // This task uses the visible SPI clock. Because the DUT's SPI clock
  // output is registered, the final waveform must still be inspected
  // to confirm timing against the internal leading/trailing-edge logic.
  task transfer;
    input integer m;
    input [7:0] tx;
    input [7:0] rx;

    integer cycles;
    integer edge_count;
    integer sample_count;
    integer shift_count;
    integer k;

    reg cpol;
    reg cpha;
    reg sample_level;
    reg shift_level;
    reg previous_clk;
    reg ready_ok;
    reg valid_seen;
    reg [7:0] captured_tx;
    reg [7:0] expected_rx;
    reg [8*120-1:0] msg;

    begin
      cpol = (m >= 2);
      cpha = (m == 1 || m == 3);

      sample_level = cpha ? cpol : ~cpol;
      shift_level = ~sample_level;

      $display("");
      $display("================================================");
      $display("TRANSFER: MODE=%0d TX=%02h EXPECTED_RX=%02h",
               m, tx, rx);
      $display("CPOL=%0d CPHA=%0d", cpol, cpha);
      $display("================================================");

      wait_ready(m, ready_ok);
      check(ready_ok, "Controller ready before transfer");

      if (!ready_ok) begin
        $display("[ABORT] Cannot start transfer: controller not ready");
      end
      else begin
        // Initialise the slave's first bit before asserting TX_DV.
        tx_data[m] = tx;
        miso[m] = rx[7];

        @(negedge clk);
        tx_dv[m] = 1'b1;

        @(negedge clk);
        tx_dv[m] = 1'b0;

        captured_tx = 8'h00;
        expected_rx = rx;
        edge_count = 0;
        sample_count = 0;
        shift_count = 0;
        cycles = 0;
        valid_seen = 1'b0;
        previous_clk = spi_clk[m];

        // Observe actual SPI clock transitions, with a timeout.
        while ((sample_count < 8) && (cycles < MAX_CYCLES)) begin
          @(posedge clk);
          #1;
          cycles = cycles + 1;

          if (spi_clk[m] !== previous_clk) begin
            previous_clk = spi_clk[m];
            edge_count = edge_count + 1;

            if (spi_clk[m] === sample_level) begin
              captured_tx = {captured_tx[6:0], mosi[m]};
              sample_count = sample_count + 1;

              $display(
                "[INFO] MODE=%0d SAMPLE=%0d MOSI=%b MISO=%b TIME=%0t",
                m, sample_count, mosi[m], miso[m], $time
              );
            end

            if (spi_clk[m] === shift_level) begin
              if (cpha) begin
                // CPHA=1: first shift edge presents RX bit 7.
                if (shift_count < 8)
                  miso[m] = rx[7-shift_count];
              end
              else begin
                // CPHA=0: first sample occurred before the first
                // shift edge, so the next bit is RX bit 6.
                if ((shift_count + 1) < 8)
                  miso[m] = rx[6-shift_count];
              end

              shift_count = shift_count + 1;
            end
          end

          if (rx_dv[m] === 1'b1)
            valid_seen = 1'b1;
        end

        check(sample_count == 8,
              "Exactly eight SPI sampling edges observed");

        $display("[INFO] MODE=%0d TX expected=%02h captured=%02h",
                 m, tx, captured_tx);

        check(captured_tx === tx,
              "MOSI byte matches expected TX byte");

        // Allow the final registered receive data and valid pulse
        // to settle. Keep watching RX_DV during this interval.
        for (k = 0; k < 5; k = k + 1) begin
          @(negedge clk);
          if (rx_dv[m] === 1'b1)
            valid_seen = 1'b1;
        end

        $display("[INFO] MODE=%0d RX expected=%02h actual=%02h",
                 m, expected_rx, rx_data[m]);

        check(rx_data[m] === expected_rx,
              "Received byte matches expected RX byte");

        check(valid_seen,
              "RX_DV asserted during receive transaction");

        wait_ready(m, ready_ok);
        check(ready_ok, "Controller ready after transfer");
      end
    end
  endtask

  // Reset test. Reset is asserted asynchronously while the
  // controller is idle; reset-during-transfer is checked separately.
  task reset_test;
    input integer m;
    reg cpol;
    reg reset_ready;
    begin
      cpol = (m >= 2);

      $display("");
      $display("RESET TEST: MODE=%0d", m);

      @(negedge clk);
      rst_n[m] = 1'b0;
      tx_dv[m] = 1'b0;
      #1;

      check(spi_clk[m] === cpol,
            "SPI clock returns to idle polarity on reset");

      repeat (2) @(negedge clk);
      rst_n[m] = 1'b1;

      wait_ready(m, reset_ready);
      check(reset_ready, "Controller becomes ready after reset");
    end
  endtask

  // Assert reset during an active transaction.
  task reset_during_transfer_test;
    input integer m;
    reg cpol;
    reg ready_after_reset;
    begin
      cpol = (m >= 2);

      $display("");
      $display("MID-TRANSFER RESET TEST: MODE=%0d", m);

      wait_ready(m, ready_after_reset);

      if (ready_after_reset) begin
        tx_data[m] = 8'hA5;
        miso[m] = 1'b1;

        @(negedge clk);
        tx_dv[m] = 1'b1;

        @(negedge clk);
        tx_dv[m] = 1'b0;

        // Allow the transaction to start before asserting reset.
        repeat (3) @(negedge clk);

        rst_n[m] = 1'b0;
        #1;

        check(spi_clk[m] === cpol,
              "Clock returns to idle polarity on mid-transfer reset");

        repeat (2) @(negedge clk);
        rst_n[m] = 1'b1;

        wait_ready(m, ready_after_reset);
        check(ready_after_reset,
              "Controller recovers to ready after mid-transfer reset");
      end
      else begin
        check(1'b0, "Could not start mid-transfer reset test");
      end
    end
  endtask

  initial begin
    $display("");
    $display("***********************************************");
    $display(" SPI MASTER SELF-CHECKING TESTBENCH");
    $display(" Modes: 0, 1, 2, 3");
    $display(" Half-bit divider: %0d", HALF_BIT);
    $display("***********************************************");

    // Byte patterns: boundary, alternating, walking-one, walking-zero.
    patterns[0]  = 8'h00;
    patterns[1]  = 8'hFF;
    patterns[2]  = 8'hAA;
    patterns[3]  = 8'h55;
    patterns[4]  = 8'hA5;
    patterns[5]  = 8'h5A;
    patterns[6]  = 8'h3C;
    patterns[7]  = 8'hC3;
    patterns[8]  = 8'h81;
    patterns[9]  = 8'h7E;
    patterns[10] = 8'h01;
    patterns[11] = 8'hFE;
    patterns[12] = 8'h02;
    patterns[13] = 8'hFD;
    patterns[14] = 8'h04;
    patterns[15] = 8'hFB;
    patterns[16] = 8'h08;
    patterns[17] = 8'hF7;

    for (mode = 0; mode < NUM_MODES; mode = mode + 1) begin
      tx_data[mode] = 8'h00;
      miso[mode] = 1'b0;
    end

    // Start in reset, then release all four DUTs.
    repeat (5) @(negedge clk);
    rst_n = 4'b1111;
    repeat (5) @(negedge clk);

    // Check each mode's idle clock polarity and initial readiness.
    for (mode = 0; mode < NUM_MODES; mode = mode + 1) begin
      $display("");
      $display("************ CHECKING MODE %0d ************", mode);

      check(spi_clk[mode] === ((mode >= 2) ? 1'b1 : 1'b0),
            "Correct SPI idle clock polarity");

      begin : READY_CHECK
        reg ready_ok;
        wait_ready(mode, ready_ok);
        check(ready_ok, "Ready after initial reset");
      end
    end

    // Test every selected TX pattern against a different RX pattern.
    // This exercises all four SPI modes and a variety of bit patterns.
    for (mode = 0; mode < NUM_MODES; mode = mode + 1) begin
      for (pattern_index = 0;
           pattern_index < 18;
           pattern_index = pattern_index + 1) begin

        // Reverse pattern order for RX so TX and RX are independent.
        transfer(mode,
                 patterns[pattern_index],
                 patterns[17-pattern_index]);
      end
    end

    // Test a reset for each mode, then verify recovery.
    for (mode = 0; mode < NUM_MODES; mode = mode + 1) begin
      reset_test(mode);
    end

    // Reset in the middle of a transaction for each mode.
    for (mode = 0; mode < NUM_MODES; mode = mode + 1) begin
      reset_during_transfer_test(mode);
    end

    $display("");
    $display("***********************************************");
    $display(" FINAL TEST SUMMARY");
    $display(" TOTAL CHECKS : %0d", total);
    $display(" PASSED       : %0d", passed);
    $display(" FAILED       : %0d", failed);

    if (total > 0)
      $display(" SCORE        : %0.2f%%",
               100.0 * passed / total);

    if (failed == 0)
      $display(" RESULT       : PASS");
    else
      $display(" RESULT       : FAIL");

    $display("***********************************************");

    $finish;
  end

  // Global watchdog prevents a stuck simulation.
  initial begin
    #1000000;
    $display("[FATAL] Global simulation timeout");
    $finish;
  end

endmodule
