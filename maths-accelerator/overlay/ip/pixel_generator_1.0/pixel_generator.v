
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.05.2024 22:03:08
// Design Name: 
// Module Name: test_block_v
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module pixel_generator(
input           out_stream_aclk,
input           s_axi_lite_aclk,
input           axi_resetn,
input           periph_resetn,

//Stream output
output [31:0]   out_stream_tdata,
output [3:0]    out_stream_tkeep,
output          out_stream_tlast,
input           out_stream_tready,
output          out_stream_tvalid,
output [0:0]    out_stream_tuser, 

//AXI-Lite S
input [AXI_LITE_ADDR_WIDTH-1:0]     s_axi_lite_araddr,
output          s_axi_lite_arready,
input           s_axi_lite_arvalid,

input [AXI_LITE_ADDR_WIDTH-1:0]     s_axi_lite_awaddr,
output          s_axi_lite_awready,
input           s_axi_lite_awvalid,

input           s_axi_lite_bready,
output [1:0]    s_axi_lite_bresp,
output          s_axi_lite_bvalid,

output [31:0]   s_axi_lite_rdata,
input           s_axi_lite_rready,
output [1:0]    s_axi_lite_rresp,
output          s_axi_lite_rvalid,

input  [31:0]   s_axi_lite_wdata,
output          s_axi_lite_wready,
input           s_axi_lite_wvalid

);

localparam X_SIZE = 640;
localparam Y_SIZE = 480;
localparam REG_FILE_SIZE = 8;
parameter AXI_LITE_ADDR_WIDTH = 8;

localparam AWAIT_WADD_AND_DATA = 3'b000;
localparam AWAIT_WDATA = 3'b001;
localparam AWAIT_WADD = 3'b010;
localparam AWAIT_WRITE = 3'b100;
localparam AWAIT_RESP = 3'b101;

localparam AWAIT_RADD = 2'b00;
localparam AWAIT_FETCH = 2'b01;
localparam AWAIT_READ = 2'b10;

localparam AXI_OK = 2'b00;
localparam AXI_ERR = 2'b10;

localparam RELATIVE_ZOOM = 1;
localparam ABSOLUTE_X_OFFSET = 0;
localparam ABSOLUTE_Y_OFFSET = 0;
localparam BASELINE_ITERATIONS_MAX = 50;
localparam STEP_SIZE = 1;

localparam scale_factor = 16777216; // 2^24
localparam signed x_min = (-(0.5 * (X_SIZE)) + ABSOLUTE_X_OFFSET) * scale_factor / (RELATIVE_ZOOM * 100);
localparam signed x_max = ((0.5 * (X_SIZE)) + ABSOLUTE_X_OFFSET) * scale_factor / (RELATIVE_ZOOM * 100);
localparam signed y_min = (-(0.5 * (Y_SIZE)) + ABSOLUTE_Y_OFFSET) * scale_factor / (RELATIVE_ZOOM * 100);
localparam signed y_max = ((0.5 * (Y_SIZE)) + ABSOLUTE_Y_OFFSET) * scale_factor / (RELATIVE_ZOOM * 100);

localparam relative_iterations_max = BASELINE_ITERATIONS_MAX * scale_factor;
localparam signed relative_step_size = (STEP_SIZE * scale_factor) / (100 * RELATIVE_ZOOM);

reg [31:0] iterations;

reg [31:0]                          regfile [REG_FILE_SIZE-1:0];
reg [AXI_LITE_ADDR_WIDTH-3:0]       writeAddr, readAddr;
reg [31:0]                          readData, writeData;
reg [1:0]                           readState = AWAIT_RADD;
reg [2:0]                           writeState = AWAIT_WADD_AND_DATA;

//Read from the register file
always @(posedge s_axi_lite_aclk) begin
    
    readData <= regfile[readAddr];

    if (!axi_resetn) begin
    readState <= AWAIT_RADD;
    end

    else case (readState)

        AWAIT_RADD: begin
            if (s_axi_lite_arvalid) begin
                readAddr <= s_axi_lite_araddr[7:2];
                readState <= AWAIT_FETCH;
            end
        end

        AWAIT_FETCH: begin
            readState <= AWAIT_READ;
        end

        AWAIT_READ: begin
            if (s_axi_lite_rready) begin
                readState <= AWAIT_RADD;
            end
        end

        default: begin
            readState <= AWAIT_RADD;
        end

    endcase
end

assign s_axi_lite_arready = (readState == AWAIT_RADD);
assign s_axi_lite_rresp = (readAddr < REG_FILE_SIZE) ? AXI_OK : AXI_ERR;
assign s_axi_lite_rvalid = (readState == AWAIT_READ);
assign s_axi_lite_rdata = readData;

//Write to the register file, use a state machine to track address write, data write and response read events
always @(posedge s_axi_lite_aclk) begin

    if (!axi_resetn) begin
        writeState <= AWAIT_WADD_AND_DATA;
    end

    else case (writeState)

        AWAIT_WADD_AND_DATA: begin  //Idle, awaiting a write address or data
            case ({s_axi_lite_awvalid, s_axi_lite_wvalid})
                2'b10: begin
                    writeAddr <= s_axi_lite_awaddr[7:2];
                    writeState <= AWAIT_WDATA;
                end
                2'b01: begin
                    writeData <= s_axi_lite_wdata;
                    writeState <= AWAIT_WADD;
                end
                2'b11: begin
                    writeData <= s_axi_lite_wdata;
                    writeAddr <= s_axi_lite_awaddr[7:2];
                    writeState <= AWAIT_WRITE;
                end
                default: begin
                    writeState <= AWAIT_WADD_AND_DATA;
                end
            endcase        
        end

        AWAIT_WDATA: begin //Received address, waiting for data
            if (s_axi_lite_wvalid) begin
                writeData <= s_axi_lite_wdata;
                writeState <= AWAIT_WRITE;
            end
        end

        AWAIT_WADD: begin //Received data, waiting for address
            if (s_axi_lite_awvalid) begin
                writeData <= s_axi_lite_wdata;
                writeState <= AWAIT_WRITE;
            end
        end

        AWAIT_WRITE: begin //Perform the write
            regfile[writeAddr] <= writeData;
            writeState <= AWAIT_RESP;
        end

        AWAIT_RESP: begin //Wait to send response
            if (s_axi_lite_bready) begin
                writeState <= AWAIT_WADD_AND_DATA;
            end
        end

        default: begin
            writeState <= AWAIT_WADD_AND_DATA;
        end
    endcase
end

assign s_axi_lite_awready = (writeState == AWAIT_WADD_AND_DATA || writeState == AWAIT_WADD);
assign s_axi_lite_wready = (writeState == AWAIT_WADD_AND_DATA || writeState == AWAIT_WDATA);
assign s_axi_lite_bvalid = (writeState == AWAIT_RESP);
assign s_axi_lite_bresp = (writeAddr < REG_FILE_SIZE) ? AXI_OK : AXI_ERR;



reg signed [31:0] x = x_min;
reg signed [31:0] y = y_min;

reg first = 1'b1;



reg lastx = 1'b0;
reg lasty = 1'b0;

always @(posedge out_stream_aclk) begin
    if (periph_resetn) begin
        if (ready) begin
            if (lastx) begin
                x <= x_min;
                if (lasty) begin
                    y <= y_min;
                end
                else begin
                    y <= y + relative_step_size;
                end
            end
            else x <= x + relative_step_size;
        end
    end
    else begin
        x <= x_min;
        y <= y_min;
    end
end

wire valid_int;
wire ready;
reg reset_engine = 1'b0;


reg [7:0] r, g, b;

single_engine engine (
    .clk(out_stream_aclk),
    .reset(reset_engine),
    .iterations_max(relative_iterations_max),
    .x0(x),
    .y0(y),
    .finished(valid_int),
    .iterations(iterations)
);

always @(*) begin
    if (x == x_min && y == y_min) begin
        first = 1'b1;
    end
    else begin
        first = 1'b0;
    end
    if (x == x_max - relative_step_size) begin
        lastx = 1'b1;
    end
    else begin
        lastx = 1'b0;
    end
    if (y == y_max - relative_step_size) begin
        lasty = 1'b1;
    end
    else begin
        lasty = 1'b0;
    end
    
        
    
    
    if (valid_int) begin
        if (iterations < relative_iterations_max) begin
            r = 8'd255;
            g = 8'd255;
            b = 8'd255;
        end
        else begin
            r = 8'd0;
            g = 8'd0;
            b = 8'd0;
        end
        reset_engine = 1'b1;
    end
    else begin
        reset_engine = 1'b0;
    end
end

packer pixel_packer(    .aclk(out_stream_aclk),
                        .aresetn(periph_resetn),
                        .r(r), .g(g), .b(b),
                        .eol(lastx), .in_stream_ready(ready), .valid(valid_int), .sof(first),
                        .out_stream_tdata(out_stream_tdata), .out_stream_tkeep(out_stream_tkeep),
                        .out_stream_tlast(out_stream_tlast), .out_stream_tready(out_stream_tready),
                        .out_stream_tvalid(out_stream_tvalid), .out_stream_tuser(out_stream_tuser) );

 
endmodule
