
`timescale 1ns / 1ps

module tb_axi_lite_memory;

    // AXI signals
    reg         ACLK;
    reg         ARESETN;

    reg  [31:0] S_AXIL_AWADDR;
    reg         S_AXIL_AWVALID;
    wire        S_AXIL_AWREADY;

    reg  [31:0] S_AXIL_WDATA;
    reg  [3:0]  S_AXIL_WSTRB;
    reg         S_AXIL_WVALID;
    wire        S_AXIL_WREADY;

    wire [1:0]  S_AXIL_BRESP;
    wire        S_AXIL_BVALID;
    reg         S_AXIL_BREADY;

    reg  [31:0] S_AXIL_ARADDR;
    reg         S_AXIL_ARVALID;
    wire        S_AXIL_ARREADY;

    wire [31:0] S_AXIL_RDATA;
    wire [1:0]  S_AXIL_RRESP;
    wire        S_AXIL_RVALID;
    reg         S_AXIL_RREADY;

    // Test variables
    integer num_matches = 0;
    integer num_mismatches = 0;
    reg [31:0] expected_data;
    reg [31:0] memory_data [0:255]; // Store written data for validation

    // Instantiate DUT
    axi_lite_memory dut (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .S_AXIL_AWADDR(S_AXIL_AWADDR),
        .S_AXIL_AWVALID(S_AXIL_AWVALID),
        .S_AXIL_AWREADY(S_AXIL_AWREADY),
        .S_AXIL_WDATA(S_AXIL_WDATA),
        .S_AXIL_WSTRB(S_AXIL_WSTRB),
        .S_AXIL_WVALID(S_AXIL_WVALID),
        .S_AXIL_WREADY(S_AXIL_WREADY),
        .S_AXIL_BRESP(S_AXIL_BRESP),
        .S_AXIL_BVALID(S_AXIL_BVALID),
        .S_AXIL_BREADY(S_AXIL_BREADY),
        .S_AXIL_ARADDR(S_AXIL_ARADDR),
        .S_AXIL_ARVALID(S_AXIL_ARVALID),
        .S_AXIL_ARREADY(S_AXIL_ARREADY),
        .S_AXIL_RDATA(S_AXIL_RDATA),
        .S_AXIL_RRESP(S_AXIL_RRESP),
        .S_AXIL_RVALID(S_AXIL_RVALID),
        .S_AXIL_RREADY(S_AXIL_RREADY)
    );

    // Clock generation: 100 MHz
    initial ACLK = 0;
    always #5 ACLK = ~ACLK;

    // Test sequence
    integer i, j;  // Use separate variables for loop counters
    reg [31:0] addr;
    reg [31:0] write_data;
    reg [7:0] current_block;
    reg [7:0] current_offset;

    initial begin
        // Initialize signals
        ARESETN = 0;
        S_AXIL_AWADDR = 32'h00110011;
        S_AXIL_AWVALID = 0;
        S_AXIL_WDATA = 0;
        S_AXIL_WSTRB = 4'hF;
        S_AXIL_WVALID = 0;
        S_AXIL_BREADY = 0;    // Start low - drive when BVALID is asserted
        S_AXIL_ARADDR = 32'h11001100;
        S_AXIL_ARVALID = 0;
        S_AXIL_RREADY = 0;    // Start low - drive when RVALID is asserted

        #20 ARESETN = 1;
        #10;

        // Loop through blocks
        for (i = 0; i < 4; i = i + 1) begin
            current_block = i;  // Store current block in separate variable
            $display("\n==== TESTING MEMORY BLOCK NUMBER : %0d ====", current_block);
            
            // Write 10 addresses
            for (j = 0; j < 10; j = j + 1) begin
                current_offset = j;  // Store current offset in separate variable
                
                // Properly position block bits at [7:6] and offset at [5:0]
                addr = {24'd0, current_block[1:0], 6'd0} | current_offset[5:0];
                
                // Create unique data including block number in most significant byte
                write_data = {current_block, current_offset, 16'hABCD};
                
                axi_write(addr, write_data, current_block, current_offset);
                memory_data[addr[7:0]] = write_data;  // Store written data
            end

            // Read 10 addresses
            for (j = 0; j < 10; j = j + 1) begin
                current_offset = j;
                
                // Same address formation for read
                addr = {24'd0, current_block[1:0], 6'd0} | current_offset[5:0];
                
                expected_data = memory_data[addr[7:0]];  // Get expected data
                axi_read(addr, expected_data, current_block, current_offset);
            end
        end

        // Report test results
        $display("\n==== TEST SUMMARY ====");
        $display("Total Matches:    %0d", num_matches);
        $display("Total Mismatches: %0d", num_mismatches);
        if (num_mismatches == 0)
            $display("TEST PASSED!");
        else
            $display("TEST FAILED!");

        #50 $finish;
    end

    // AXI Write Task with proper BREADY handshake and block/offset display
    task axi_write(input [31:0] addr, input [31:0] data, input [7:0] blk, input [7:0] off);
    begin
        @(posedge ACLK);
        S_AXIL_AWADDR  <= addr;
        S_AXIL_AWVALID <= 1;
        S_AXIL_WDATA   <= data;
        S_AXIL_WSTRB   <= 4'hF;
        S_AXIL_WVALID  <= 1;
        S_AXIL_BREADY  <= 0;  // Initially low

        // Wait for AWREADY and WREADY together
        wait(S_AXIL_AWREADY && S_AXIL_WREADY);
        @(posedge ACLK);
        S_AXIL_AWVALID <= 0;
        S_AXIL_WVALID  <= 0;

        // Wait for BVALID from slave
        wait(S_AXIL_BVALID);
        @(posedge ACLK);
        S_AXIL_BREADY <= 1;  // Accept write response

        @(posedge ACLK);
        S_AXIL_BREADY <= 0;  // Deassert after handshake
        
        $display("Wrote Addr 0x%08h => Data 0x%08h (Block: %0d, Offset: %0d)", 
                addr, data, blk, off);
    end
    endtask

    // AXI Read Task with proper RREADY handshake and data verification
    task axi_read(input [31:0] addr, input [31:0] expected, input [7:0] blk, input [7:0] off);
    begin
        @(posedge ACLK);
        S_AXIL_ARVALID <= 1;
        S_AXIL_RREADY  <= 0;  // Initially low
        S_AXIL_ARADDR  <= addr;
        
        // Wait for ARREADY
        wait(S_AXIL_ARREADY);
        @(posedge ACLK);
        S_AXIL_ARVALID <= 0;

        // Wait for RVALID from slave
        wait(S_AXIL_RVALID);
        @(posedge ACLK);
        S_AXIL_RREADY <= 1;   // Accept read data

        // Check if read data matches expected data
        if (S_AXIL_RDATA === expected) begin
            num_matches = num_matches + 1;
            $display("Read Addr 0x%08h => Data: 0x%08h [MATCH] (Block: %0d, Offset: %0d)", 
                    addr, S_AXIL_RDATA, blk, off);
        end else begin
            num_mismatches = num_mismatches + 1;
            $display("Read Addr 0x%08h => Data: 0x%08h, Expected: 0x%08h [MISMATCH] (Block: %0d, Offset: %0d)", 
                    addr, S_AXIL_RDATA, expected, blk, off);
        end

        @(posedge ACLK);
        S_AXIL_RREADY <= 0;   // Deassert after handshake
        
        @(posedge ACLK);
    end
    endtask
  initial begin 
    $dumpfile("dump.vcd");
    $dumpvars(0,tb_axi_lite_memory);
  end

              
endmodule
