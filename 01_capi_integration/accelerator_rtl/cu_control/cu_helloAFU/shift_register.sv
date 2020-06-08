module shift_register #(parameter width = 1) (
  input logic clock,
  input logic [0:width-1] in,
  output logic [0:width-1] out);

  always_ff @ (posedge clock) begin
    out <= in;
  end
endmodule
