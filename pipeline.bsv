package pipeline;

import FIFO::*;
import SpecialFIFOs::*;

typedef struct {
  Bit#(16) val1;
  Bit#(16) val2;
  Bit#(32) val3;
  Bit#(1 ) s1_or_s2;         // 0 for s1  and 1 for s2
} AdderInput
deriving(Bits, Eq);

// Struct for the intermediate pipe stage. We are implementin two stages pipeline so input is divided in two halves
typedef struct {
  Bit#(4 ) val1;
  Bit#(4 ) val2;
  Bit#(16) val3;
  Bit#(16) intermediateresult;
  Bit#(1 ) s1_or_s2;         // 0 for s1  and 1 for s2
} IntAdderPipeStage
deriving(Bits, Eq);

 typedef struct {
  Bit#(8 ) val1;
  Bit#(8 ) val2;
  Bit#(16) val3;
  Bit#(16) intermediateresult;
  Bit#(1 ) s1_or_s2;         // 0 for s1  and 1 for s2
} FloatAdderPipeStage
deriving(Bits, Eq);

typedef struct {
//  Bit#(1)  overflow;            //---> carry
  Bit#(32) result_s;
} AdderResult
deriving(Bits, Eq);

// Interface definition for the ripple carry adder<
interface RCA_ifc;
  method Action                    start(AdderInput inp);
  method ActionValue#(AdderResult) get_result();
endinterface : RCA_ifc

(* synthesize *)
module mkRippleCarryAdder(RCA_ifc);
  // Declare FIFO for the adder pipeline stages
  FIFO#(AdderInput)     adder_ififo <- mkPipelineFIFO();
  FIFO#(IntAdderPipeStage) adder_ipfifo <- mkPipelineFIFO();
  FIFO#(FloatAdderPipeStage) adder_fpfifo <- mkPipelineFIFO();
  FIFO#(AdderResult)    adder_ofifo <- mkPipelineFIFO();
  
  function Bit#(16) ripple_add(Bit#(16) x, Bit#(16) y);
    Bit#(16) sum   = 0;
    Bit#(1)  carry = 0;
    for (Integer i = 0; i < 16; i = i + 1) begin
      let a = x[i];
      let b = y[i];
      let temp_sum = a ^ b ^ carry; // sum = a ⊕ b ⊕ carry
      carry        = (a & b) | (carry & (a ^ b)); // carry = (a ∧ b) ∨ (carry ∧ (a ⊕ b))
      sum[i]       = temp_sum;
    end
    return sum;
  endfunction

// Shift-and-add multiplication for unsigned 8-bit numbers
  function Bit#(16) shift_and_add_mul(Bit#(4) a, Bit#(4) b);
    Bit#(16) product = 0;
    Bit#(16) temp_A  = zeroExtend(a);
    for (Integer i   = 0; i < 4; i = i + 1) begin
      if (b[i] == 1) begin
        product = ripple_add(product, temp_A); // Add shifted A if corresponding bit in B is set
      end
      temp_A    = temp_A << 1; // Shift A to the left
    end
    return product;                                           
  endfunction
  
  // Function for ripple carry addition
  function Bit#(16) mac_int(Bit#(4) a, Bit#(4) b, Bit#(16) c);
    Bit#(16) result;
    let product_S1 = shift_and_add_mul(a, b); // Multiply A and B using shift-and-add
    result         = ripple_add(zeroExtend(product_S1), c); // Accumulate with C using ripple-carry adder

    return result;
  endfunction : mac_int

  function Bit#(16) bf8_to_fp16(Bit#(8) bf8);
    Bit#(1) sign   = bf8[7];
    Bit#(4) exp    = bf8[6:3];
    Bit#(3) mant   = bf8[2:0];

    return {sign, exp, mant, 8'b0};  // Extend mantissa and return as fp32
  endfunction

  function Bit#(16) multiply_bf16(Bit#(8) a_bf8, Bit#(8) b_bf8);
    Bit#(16) a_fp16 = bf8_to_fp16(a_bf8);
    Bit#(16) b_fp16 = bf8_to_fp16(b_bf8);

    Bit#(1 ) sign    = a_fp16[15] ^ b_fp16[15];
    Bit#(8 ) exp     = a_fp16[14:7] ^ b_fp16[14:7] ^ 8'd127;   
    Bit#(8 ) mant_a  = {1'b1, a_fp16[6:0]}; // implicit leading 1 for normalization
    Bit#(8 ) mant_b  = {1'b1, b_fp16[6:0]}; // implicit leading 1
    Bit#(16) mant_product = 0;

    for (Integer i = 0; i < 8; i = i + 1) begin
      if (mant_b[i] == 1) begin
        mant_product = mant_product ^ (zeroExtend(mant_a) << i); // conditional add using XOR for demonstration
      end
    end
    // Normalize the mantissa if necessary
    Bit#(8) final_exp;
    Bit#(7) final_mant;
    if (mant_product[13] == 1) begin
      final_mant = mant_product[13:7];
      final_exp  = exp ^ 8'd1; // Increment exponent without +
    end else begin
       final_mant = mant_product[12:6];
       final_exp  = exp;
    end

    return {sign, final_exp, final_mant};
  endfunction
  
  function Bit#(16) bitwise_add(Bit#(16) a, Bit#(16) b);
    Bit#(16) result = 0;
    Bit#(1) carry   = 0;
    for (Bit#(16) i = 0; i < 16; i = i + 1) begin
        result[i] = a[i] ^ b[i] ^ carry; // XOR for addition
        carry     = (a[i] & b[i]) | (carry & (a[i] ^ b[i])); // Carry logic
    end
    return result;
  endfunction

  function Bit#(16) mac_float(Bit#(8) a, Bit#(8) b, Bit#(16) c);
    // Bit#(16) product_S2_fp32;
    Bit#(16) sum_result;

    let product_S2_fp16 = multiply_bf16(a, b); // Multiply A and B
    sum_result          = bitwise_add(product_S2_fp16, c);

    return sum_result;
  endfunction : mac_float

  // Rule for adder pipeline stage-1
  rule rl_pipe_stage1;
    AdderInput inp_stage1 = adder_ififo.first();
    if (inp_stage1.s1_or_s2 == 0) begin

      Bit#(4 )   inp_val1   = inp_stage1.val1[3:0 ];
      Bit#(4 )   inp_val2   = inp_stage1.val2[3:0 ];
      Bit#(16)   inp_val3   = inp_stage1.val3[15:0];
      Bit#(16)   psum       = mac_int(inp_val1, inp_val2, inp_val3);

      IntAdderPipeStage out_stage1;
      out_stage1.val1 = inp_stage1.val1[ 7:4 ];
      out_stage1.val2 = inp_stage1.val2[ 7:4 ];
      out_stage1.val3 = inp_stage1.val3[31:16];
      out_stage1.intermediateresult  = psum;
      out_stage1.s1_or_s2 = inp_stage1.s1_or_s2;

      // adder_ififo.deq();
      adder_ipfifo.enq(out_stage1);


    end else begin
      Bit#(8 )   inp_val1   = inp_stage1.val1[7:0 ];
      Bit#(8 )   inp_val2   = inp_stage1.val2[7:0 ];
      Bit#(16)   inp_val3   = inp_stage1.val3[15:0];
      Bit#(16)   psum       = mac_float(inp_val1, inp_val2, inp_val3);

      FloatAdderPipeStage out_stage1;
      out_stage1.val1 = inp_stage1.val1[15:8 ];
      out_stage1.val2 = inp_stage1.val2[15:8 ];
      out_stage1.val3 = inp_stage1.val3[31:16];
      out_stage1.intermediateresult  = psum;
      out_stage1.s1_or_s2 = inp_stage1.s1_or_s2;

      // adder_ififo.deq();
      adder_fpfifo.enq(out_stage1);
    end

  endrule : rl_pipe_stage1

  // Rule for adder pipeline stage-2
  rule rl_pipe_stage2;
    
    
    AdderInput inp = adder_ififo.first();
    if (inp.s1_or_s2 == 0) begin
      IntAdderPipeStage inp_stage2 = adder_ipfifo.first();
  
      Bit#(4 )       inp_val1   = inp_stage2.val1;
      Bit#(4 )       inp_val2   = inp_stage2.val2;
      Bit#(16)       inp_val3   = inp_stage2.val3;
      Bit#(16)       psum_lsbs  = inp_stage2.intermediateresult;
      Bit#(16)       psum_msbs  = mac_int(inp_val1, inp_val2, inp_val3);

      AdderResult out_stage2;
      out_stage2.result_s      = {psum_msbs[15:0], psum_lsbs[15:0]};
      adder_ipfifo.deq();
      adder_ofifo.enq(out_stage2);
    end else begin
      FloatAdderPipeStage inp_stage2 = adder_fpfifo.first(); 
      Bit#(8 )       inp_val1   = inp_stage2.val1;
      Bit#(8 )       inp_val2   = inp_stage2.val2;
      Bit#(16)       inp_val3   = inp_stage2.val3;
      Bit#(16)       psum_lsbs  = inp_stage2.intermediateresult;
      Bit#(16)       psum_msbs  = mac_float(inp_val1, inp_val2, inp_val3);

      AdderResult out_stage2;
      out_stage2.result_s      = {psum_msbs[15:0], psum_lsbs[15:0]};
      adder_fpfifo.deq();
      adder_ofifo.enq(out_stage2);

    end
    
    
  endrule : rl_pipe_stage2

  // Define the adder interface methods
  method Action start(AdderInput inp);
    adder_ififo.enq(inp);
  endmethod : start

  method ActionValue#(AdderResult) get_result();
    AdderResult out = adder_ofifo.first();
    adder_ofifo.deq();
    return out;
  endmethod : get_result
endmodule : mkRippleCarryAdder

endpackage : pipeline
