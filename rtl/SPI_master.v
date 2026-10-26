`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.10.2026 13:45:40
// Design Name: 
// Module Name: SPI_master
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
//parameter SPI_MODE=0;
//parameter CLKS_PER_HALF_BIT=2;

module SPI_master #(
parameter SPI_MODE=0,
parameter CLKS_PER_HALF_BIT=2
)(
    // control/data signals
    input i_Rst_L,
    input i_Clk,
    // TX(MOSI) signals
    input [7:0] i_TX_Byte,
    input       i_TX_DV,
    output reg  o_TX_Ready,
    // RX(MISO) signals
    output reg  o_RX_DV,
    output reg [7:0] o_RX_Byte,
    //SPI Interfaces
    output reg  o_SPI_Clk,
    input       i_SPI_MISO,
    output reg  o_SPI_MOSI
    );
wire w_CPOL;
wire w_CPHA;

reg [$clog2(CLKS_PER_HALF_BIT*2)-1:0] r_SPI_Clk_Count;// totsl numer of input clock count per spi cycle
reg r_SPI_Clk;//spi register for spi clock gets high and low based on r spi clock count
reg [4:0] r_SPI_Clk_Edges;//edge counter
reg r_Leading_Edge;//single cycle pulse which highs when leading edge
reg r_Trailing_Edge;//single cycle pulse which highs when trailing edge
reg r_TX_DV;//registered late by one cycle version of input data valid signal
reg [7:0] r_TX_Byte;//local 8 bit buffer

reg [2:0] r_RX_Bit_Count;//counts which bit being transferred 
reg [2:0] r_TX_Bit_Count;// counts which bit being recieved

assign w_CPOL = (SPI_MODE == 2) || (SPI_MODE == 3);
assign w_CPHA = (SPI_MODE == 1) || (SPI_MODE == 3);

//for all clock signals
always @(posedge i_Clk or negedge i_Rst_L)
begin
    if (~i_Rst_L)//its reset condn thats triggered
    begin
        o_TX_Ready      <= 1'b0;//set to 0
        r_SPI_Clk_Edges <= 0;//set to 0
        r_Leading_Edge  <= 1'b0;//set to 0
        r_Trailing_Edge <= 1'b0;//set to 0
        r_SPI_Clk       <= w_CPOL; // assign default state to idle state
        r_SPI_Clk_Count <= 0;
    end
    else//when not reset condn, means iclk 
    begin
        // Default assignments
        r_Leading_Edge  <= 1'b0;//leading edge set to 0
        r_Trailing_Edge <= 1'b0;//trailing edge set to 0
        if (i_TX_DV)//means that data is valid
        begin
            o_TX_Ready      <= 1'b0;// tx is busy
            r_SPI_Clk_Edges <= 16;  // Total # edges in one byte ALWAYS 16 two edges per bit
        end
        else if (r_SPI_Clk_Edges > 0)// means spi clk edges not 0 so byte not ended
        begin
            o_TX_Ready <= 1'b0;// tx is busy
            if (r_SPI_Clk_Count == CLKS_PER_HALF_BIT*2-1)//means count of iclk cycles in spi cycle is completed
            begin
                r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1'b1;// a edge is reduced from count as it occured
                r_Trailing_Edge <= 1'b1;//trailing edge triggered helps i mosi and miso
                r_SPI_Clk_Count <= 0;//since iclk cycles per spi cycle done it reset to 0
                r_SPI_Clk       <= ~r_SPI_Clk;//spi is negated 0 to 1 1 to 0 how clk works
            end
            
            else if (r_SPI_Clk_Count == CLKS_PER_HALF_BIT-1)// when half bit means half of all iclk cycles in one spi clk cycle done 
            begin
                r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1'b1;//an edge occured so count reduced
                r_Leading_Edge  <= 1'b1;//its leading edge so it triggered
                r_SPI_Clk_Count <= r_SPI_Clk_Count + 1'b1;//clk count not ended yet so incremented by 1
                r_SPI_Clk       <= ~r_SPI_Clk;// it negated. remember. cycle is 1 to 0 to 1 whole. at half of all iclk cycles it changed. spi freq not comprpmised
            end
            else
            begin
                r_SPI_Clk_Count <= r_SPI_Clk_Count + 1'b1;// none of the imp condns. spi clk count incremented by 1.
            end
        end
        else
        begin
            o_TX_Ready <= 1'b1;// if none of the condn means its idle so tx ready triggered
        end
    end    
end

//for buffer data storage
always @(posedge i_Clk or negedge i_Rst_L)
begin
    if (~i_Rst_L)// resetn condn 
    begin
        r_TX_Byte <= 8'h00;// stored data reset to 0.
        r_TX_DV   <= 1'b0;// data valid reset to 0.
    end
    else// iclk posedge triggered
    begin
        r_TX_DV <= i_TX_DV;// input data validity stored in register for data valid.
        if (i_TX_DV)// if data is valid
        begin
            r_TX_Byte <= i_TX_Byte;// store data byte to register. helps keep stored data if data gets changed
        end
    end
end

//for mosi operation
always @(posedge i_Clk or negedge i_Rst_L)
begin
    if (~i_Rst_L)//resetn condn
    begin
        o_SPI_MOSI <= 1'b0;// output mosi bit set to 0.
        r_TX_Bit_Count <= 3'b111;// sending msb first. this counter tells which bit to be transferred. it reset to point to msb.
    end
    else// iclk triggered
    begin
        if (o_TX_Ready)//tells that tx is ready and idle. means already done with the byte send new
        begin
            r_TX_Bit_Count <= 3'b111;//count reset to point to msb
        end
        else if (r_TX_DV & ~w_CPHA)//data is valid and cpha is 0. cpha 0 tells that even before spi count begins it sends msb. 
        begin
            o_SPI_MOSI     <= r_TX_Byte[3'b111];//output sent. set to 7th bit of register byte.
            r_TX_Bit_Count <= 3'b110;// bit count reduced
        end
        else if ((r_Leading_Edge & w_CPHA) | (r_Trailing_Edge & ~w_CPHA))// cpha 1 means sends at leading and cpha 0 means sends at trailing edge.
        begin
            r_TX_Bit_Count <= r_TX_Bit_Count - 1'b1;// bit count reduced.
            o_SPI_MOSI     <= r_TX_Byte[r_TX_Bit_Count];// it sent on output.note because non blocking statement used(<=) the opereations occur simultaneously no bit loss
        end
    end
end

// miso operation
always @(posedge i_Clk or negedge i_Rst_L)
begin
    if (~i_Rst_L)//reset condn
    begin
        o_RX_Byte      <= 8'h00;//rx byte is set to 0.
        o_RX_DV        <= 1'b0;//data valid set to 0
        r_RX_Bit_Count <= 3'b111;// bit count reset to point to msb.
    end
    else// posedge iclk condn
    begin
        // Default Assignments
        o_RX_DV   <= 1'b0;//acts as a check to tell new byte there. until 0 it means here being read

        if (o_TX_Ready) // Check if ready is high, if so reset bit count to default
        begin
            r_RX_Bit_Count <= 3'b111;
        end
        else if ((r_Leading_Edge & ~w_CPHA) | (r_Trailing_Edge & w_CPHA))//cpha 0 means reads on leading edge and cpha 1 means reads on trailing edge.
        begin
            o_RX_Byte[r_RX_Bit_Count] <= i_SPI_MISO;  // Sample data
            r_RX_Bit_Count            <= r_RX_Bit_Count - 1'b1;
            if (r_RX_Bit_Count == 3'b000)
            begin
                o_RX_DV   <= 1'b1;   // Byte done, pulse Data Valid
            end
        end
    end
end

// Purpose: Add clock delay to signals for alignment.
always @(posedge i_Clk or negedge i_Rst_L)
begin
    if (~i_Rst_L)
    begin
        o_SPI_Clk  <= w_CPOL;
    end
    else
    begin
        o_SPI_Clk <= r_SPI_Clk;
    end // else: !if(~i_Rst_L)
end // always @ (posedge i_Clk or negedge i_Rst_L)
endmodule

