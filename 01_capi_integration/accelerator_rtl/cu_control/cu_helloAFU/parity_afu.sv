import CAPI::*;

module parity_afu (
  input clock,
  output timebase_request,
  output parity_enabled,
  input JobInterfaceInput job_in,
  output JobInterfaceOutput job_out,
  input CommandInterfaceInput command_in,
  output CommandInterfaceOutput command_out,
  input BufferInterfaceInput buffer_in,
  output BufferInterfaceOutput buffer_out,
  input ResponseInterface response,
  input MMIOInterfaceInput mmio_in,
  output MMIOInterfaceOutput mmio_out);

  logic jdone;

  shift_register jdone_shift(
    .clock(clock),
    .in(jdone),
    .out(job_out.done));

  mmio mmio_handler(
    .clock(clock),
    .mmio_in(mmio_in),
    .mmio_out(mmio_out));

  parity_workelement workelement(
    .clock(clock),
    .enabled(job_out.running),
    .reset(jdone),
    .wed(job_in.address),
    .buffer_in(buffer_in),
    .response(response),
    .command_out(command_out),
    .buffer_out(buffer_out));

  assign job_out.cack = 0,
         job_out.error = 0,
         job_out.yield = 0,
         timebase_request = 0,
         parity_enabled = 0;

  always_ff @(posedge clock) begin
    if(job_in.valid) begin
      case(job_in.command)
        RESET: begin
          jdone <= 1;
          job_out.running <= 0;
        end
        START: begin
          jdone <= 0;
          job_out.running <= 1;
        end
      endcase
    end else begin
      jdone <= 0;
    end
  end

endmodule
