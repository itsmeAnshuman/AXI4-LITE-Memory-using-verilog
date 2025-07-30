//Module and Port Declarations

module axi_lite_memory #(parameter DW = 32)(
    input                   ACLK,
    input                   ARESETN,
    // Write Address Channel
    input       [31:0]      S_AXIL_AWADDR,
    input                   S_AXIL_AWVALID,
    output reg              S_AXIL_AWREADY,
    // Write Data Channel
    input       [DW-1:0]    S_AXIL_WDATA,
    input       [(DW/8)-1:0] S_AXIL_WSTRB,
    input                   S_AXIL_WVALID,
    output reg              S_AXIL_WREADY,
    // Write Response Channel
    output      [1:0]       S_AXIL_BRESP,
    output reg              S_AXIL_BVALID,
    input                   S_AXIL_BREADY,
    // Read Address Channel
    input       [31:0]      S_AXIL_ARADDR,
    input                   S_AXIL_ARVALID,
    output reg              S_AXIL_ARREADY,
    // Read Data Channel
    output reg  [DW-1:0]    S_AXIL_RDATA,
    output      [1:0]       S_AXIL_RRESP,
    output reg              S_AXIL_RVALID,
    input                   S_AXIL_RREADY 
);
//Internal Signals and Memory
  integer i;
reg [DW-1:0] check_data;

// Memory Blocks (4 x 64 x 32-bit)
reg [DW-1:0] block0 [0:63];
reg [DW-1:0] block1 [0:63];
reg [DW-1:0] block2 [0:63];
reg [DW-1:0] block3 [0:63];

// Initialize Memory Content
initial begin
    for(i = 0; i < 64; i = i + 1) begin
        block0[i] = 32'h00000000;
        block1[i] = 32'h11111111;
        block2[i] = 32'h22222222;
        block3[i] = 32'h33333333;
    end
end
  //State Registers and Flags//
  
// Handshake Flags
reg aw_handshake, w_handshake, ar_handshake;

// Response Signals
reg [1:0] b_resp, r_resp;

// FSM States
localparam WIDLE = 2'b00, WRITE = 2'b01, WCOMPUTE = 2'b10, WRESPOND = 2'b11;
localparam RIDLE = 2'b00, READ = 2'b01, RCOMPUTE = 2'b10, RRESPOND = 2'b11;

// FSM State Registers
reg [1:0] w_c_state, w_n_state;
reg [1:0] r_c_state, r_n_state;

// Address/Data Storage
reg [31:0] write_addr;
reg [DW-1:0] write_data;
reg [(DW/8)-1:0] write_strb;
reg [31:0] read_addr;

//    Write Address Channel Logic//
  always @(posedge ACLK, negedge ARESETN) begin
    if (!ARESETN) begin
        S_AXIL_AWREADY <= 0;
        aw_handshake <= 0;
        write_addr <= 0;            
    end else begin
        S_AXIL_AWREADY <= (!S_AXIL_AWREADY && S_AXIL_AWVALID)
                          && (!S_AXIL_BVALID || S_AXIL_BREADY);
        if (S_AXIL_AWREADY && S_AXIL_AWVALID) begin
            aw_handshake <= 1;
            write_addr <= S_AXIL_AWADDR;
        end else if (S_AXIL_BREADY && S_AXIL_BVALID) begin
            aw_handshake <= 0;
        end
    end
end
// Write Data Channel Logic//
  always @(posedge ACLK, negedge ARESETN) begin
    if (!ARESETN) begin
        S_AXIL_WREADY <= 0;
        w_handshake <= 0;
        write_data <= 0;
        write_strb <= 0;            
    end else begin
        S_AXIL_WREADY <= (!S_AXIL_WREADY && S_AXIL_WVALID)
                          && (!S_AXIL_BVALID || S_AXIL_BREADY);
        if (S_AXIL_WREADY && S_AXIL_WVALID) begin 
            w_handshake <= 1;
            write_data <= S_AXIL_WDATA;
            write_strb <= S_AXIL_WSTRB;
        end else if (S_AXIL_BREADY && S_AXIL_BVALID) begin
            w_handshake <= 0;
        end
    end
end
//write FSm:state transition logic
// State register
always @(posedge ACLK, negedge ARESETN) begin
    if (!ARESETN) begin
        w_c_state <= WIDLE;
        w_n_state <= WIDLE;
    end else begin
        w_c_state <= w_n_state;
    end
end

// Next state logic
always @(*) begin
    case (w_c_state)
        WIDLE:    w_n_state = (w_handshake && aw_handshake && !S_AXIL_BVALID) ? WRITE : WIDLE;
        WRITE:    w_n_state = WCOMPUTE;
        WCOMPUTE: w_n_state = WRESPOND;
        WRESPOND: w_n_state = (S_AXIL_BVALID && S_AXIL_BREADY) ? WIDLE : WRESPOND;
    endcase
end
//Write Operation and Memory Write//
always @(posedge ACLK) begin
    if (w_c_state == WRITE) begin
        check_data <= write_data;
        case (write_addr[7:6])
            2'b00: for (i = 0; i < 4; i++) if (write_strb[i]) block0[write_addr[5:0]][i*8 +: 8] <= write_data[i*8 +: 8];
            2'b01: for (i = 0; i < 4; i++) if (write_strb[i]) block1[write_addr[5:0]][i*8 +: 8] <= write_data[i*8 +: 8];
            2'b10: for (i = 0; i < 4; i++) if (write_strb[i]) block2[write_addr[5:0]][i*8 +: 8] <= write_data[i*8 +: 8];
            2'b11: for (i = 0; i < 4; i++) if (write_strb[i]) block3[write_addr[5:0]][i*8 +: 8] <= write_data[i*8 +: 8];
        endcase
    end
end
  //Write Response Logic (BRESP)//
  always @(posedge ACLK) begin
    if (w_c_state == WCOMPUTE) begin
        case (write_addr[7:6])
            2'b00: b_resp <= (check_data == block0[write_addr[5:0]]) ? 2'b00 : 2'b10;
            2'b01: b_resp <= (check_data == block1[write_addr[5:0]]) ? 2'b00 : 2'b10;
            2'b10: b_resp <= (check_data == block2[write_addr[5:0]]) ? 2'b00 : 2'b10;
            2'b11: b_resp <= (check_data == block3[write_addr[5:0]]) ? 2'b00 : 2'b10;
        endcase
    end
end

assign S_AXIL_BRESP = b_resp;

  //Write Response Valid Signal (BVALID)//
  always @(posedge ACLK, negedge ARESETN) begin
    if (!ARESETN) begin
        S_AXIL_BVALID <= 0;
        b_resp <= 2'b01;
    end else begin
        case (w_c_state)
            WIDLE:     begin S_AXIL_BVALID <= 0; b_resp <= 2'b01; end
            WCOMPUTE:  S_AXIL_BVALID <= 1;
            WRESPOND:  if (S_AXIL_BVALID && S_AXIL_BREADY) S_AXIL_BVALID <= 0;
        endcase
    end
end

  //Read Address Channel Logic//
  always @(posedge ACLK, negedge ARESETN) begin
    if (!ARESETN) begin
        S_AXIL_ARREADY <= 0;
        read_addr <= 0;
        ar_handshake <= 0;
    end else begin
        // Accept a new read address when not already processing a response
        S_AXIL_ARREADY <= (!S_AXIL_ARREADY && S_AXIL_ARVALID && !S_AXIL_RVALID);
        if (S_AXIL_ARREADY && S_AXIL_ARVALID) begin
            read_addr <= S_AXIL_ARADDR;
            ar_handshake <= 1;
        end else if (S_AXIL_RVALID && S_AXIL_RREADY) begin
            ar_handshake <= 0;
        end
    end
end
//. Read FSM: State Transition Logic//
  always @(posedge ACLK, negedge ARESETN) begin
    if (!ARESETN) begin
        r_c_state <= RIDLE;
        r_n_state <= RIDLE;
    end else begin
        r_c_state <= r_n_state;
    end
end
always @(*) begin
    case (r_c_state)
        RIDLE:     r_n_state = (ar_handshake && !S_AXIL_RVALID) ? READ : RIDLE;
        READ:      r_n_state = RCOMPUTE;
        RCOMPUTE:  r_n_state = RRESPOND;
        RRESPOND:  r_n_state = (S_AXIL_RVALID && S_AXIL_RREADY) ? RIDLE : RRESPOND;
    endcase
end
  // Read Memory and Prepare RDATA//
  
always @(posedge ACLK) begin
    if (r_c_state == READ) begin
        case (read_addr[7:6])
            2'b00: begin S_AXIL_RDATA <= block0[read_addr[5:0]]; check_data <= block0[read_addr[5:0]]; end
            2'b01: begin S_AXIL_RDATA <= block1[read_addr[5:0]]; check_data <= block1[read_addr[5:0]]; end
            2'b10: begin S_AXIL_RDATA <= block2[read_addr[5:0]]; check_data <= block2[read_addr[5:0]]; end
            2'b11: begin S_AXIL_RDATA <= block3[read_addr[5:0]]; check_data <= block3[read_addr[5:0]]; end
        endcase
    end
end

  // Generate RRESP Based on Data Match//
  always @(posedge ACLK) begin
    if (r_c_state == RCOMPUTE) begin
        case (read_addr[7:6])
            2'b00: r_resp <= (check_data == S_AXIL_RDATA) ? 2'b00 : 2'b10;
            2'b01: r_resp <= (check_data == S_AXIL_RDATA) ? 2'b00 : 2'b10;
            2'b10: r_resp <= (check_data == S_AXIL_RDATA) ? 2'b00 : 2'b10;
            2'b11: r_resp <= (check_data == S_AXIL_RDATA) ? 2'b00 : 2'b10;
        endcase
    end
end

assign S_AXIL_RRESP = r_resp;
//Set RVALID Signal//
  always @(posedge ACLK, negedge ARESETN) begin
    if (!ARESETN) begin
        S_AXIL_RVALID <= 0;
        S_AXIL_RDATA <= 0;
        r_resp <= 2'b01;
    end else begin
        case (r_c_state)
            RIDLE:     begin S_AXIL_RVALID <= 0; r_resp <= 2'b01; end
            RCOMPUTE:  S_AXIL_RVALID <= 1;
            RRESPOND:  if (S_AXIL_RVALID && S_AXIL_RREADY) S_AXIL_RVALID <= 0;
        endcase
    end
end
