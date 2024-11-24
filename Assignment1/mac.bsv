package mac;
import Vector::*;
import FloatingPoint::*;

interface MACInterface;
  method Action get_A(Bit#(16) input_A);
  method Action get_B(Bit#(16) input_B);
  method Action get_C(Bit#(32) input_C);
 
  method Action select_S1_or_S2(Bool mode); // mode: 0 for S1, 1 for S2
  method ActionValue #(Bit#(32)) start_MAC();
  method Bit#(32) get_MAC_result(); // Result output for both S1 and S2
endinterface

(* synthesize *)
module mkMAC(MACInterface);
  Reg#(Bool) s1_or_s2_mode <- mkWire; // False = S1, True = S2
  Reg#(Bit#(8)) reg_A_S1 <- mkWire;
  Reg#(Bit#(8)) reg_B_S1 <- mkWire;
  Reg#(Bit#(32)) reg_C_S1 <- mkWire;

  Reg#(Bit#(16)) reg_A_S2 <- mkWire;  // bf16
  Reg#(Bit#(16)) reg_B_S2 <- mkWire;  // bf16
  Reg#(Bit#(32)) reg_C_S2 <- mkWire;  // fp32

  Reg#(Bit#(32)) mac_result_S1 <- mkReg(0);
  Reg#(Bit#(32)) mac_result_S2 <- mkReg(0);

  function Bit#(32) ripple_add(Bit#(32) x, Bit#(32) y);
    Bit#(32) sum = 0;
    Bit#(1) carry = 0;
    for (Integer i = 0; i < 32; i = i + 1) begin
      let a = x[i];
      let b = y[i];
      let temp_sum = a ^ b ^ carry; // sum = a ⊕ b ⊕ carry
      carry = (a & b) | (carry & (a ^ b)); // carry = (a ∧ b) ∨ (carry ∧ (a ⊕ b))
      sum[i] = temp_sum;
    end
    return sum;
  endfunction

  function Bit#(32) shift_and_add_mul(Bit#(8) a, Bit#(8) b);
    Bool a_negative = a[7] == 1;
    Bool b_negative = b[7] == 1;

    Bit#(8) abs_a = a_negative ? (~a + 1) : a;
    Bit#(8) abs_b = b_negative ? (~b + 1) : b;

    Bit#(32) product = 0;
    Bit#(32) temp_A = zeroExtend(abs_a);
    for (Integer i = 0; i < 8; i = i + 1) begin
      if (abs_b[i] == 1) begin
        product = ripple_add(product, (temp_A << i));
      end
    end

    Bool result_negative = (a_negative && !b_negative) || (!a_negative && b_negative);

    if(result_negative == True) begin
      product = (~product + 1); // Two's complement for negative result
    end

    return signExtend(product);
  endfunction


  function Bit#(32) multiply_bf16(Bit#(16) a_bf16, Bit#(16) b_bf16);
    // Extract components
    Bit#(1)  sign_a = a_bf16[15];
    Bit#(8)  exp_a  = a_bf16[14:7];
    Bit#(7)  mant_a = a_bf16[6:0];
   
    Bit#(1)  sign_b = b_bf16[15];
    Bit#(8)  exp_b  = b_bf16[14:7];
    Bit#(7)  mant_b = b_bf16[6:0];

    // Handle result sign
    Bit#(1) result_sign = sign_a ^ sign_b;
   
    // Add implicit 1 for normalized numbers
    Bit#(8) full_mant_a = {1'b1, mant_a};
    Bit#(8) full_mant_b = {1'b1, mant_b};

    // Multiply mantissas (8-bit * 8-bit = 16-bit result)
    Bit#(16) mant_product = 0;
    for (Integer i = 0; i < 8; i = i + 1) begin
        if (full_mant_b[i] == 1) begin
            mant_product = mant_product + (zeroExtend(full_mant_a) << i);
        end
    end

    // Handle exponents
    // Remove bias from inputs, add exponents, add back single bias
    Bit#(16) exp_sum = signExtend(exp_a) + signExtend(exp_b) - 127;

    // Normalize result if needed
    Bit#(8) final_exp;
    Bit#(23) final_mant;
   
    if (mant_product[15] == 1) begin  // Need to shift right
        final_mant = {mant_product[14:0], 8'b0};  // Shift and pad with zeros
        exp_sum = exp_sum + 1;
    end else begin
        final_mant = {mant_product[13:0], 9'b0};  // Pad with zeros
    end

    // Check for overflow/underflow
    if (exp_sum > 255) begin
        final_exp = 8'hFF;  // Overflow to infinity
        final_mant = 0;
    end else begin
        final_exp = exp_sum[7:0];
    end

    // Assemble final FP32 result
    return {result_sign, final_exp, final_mant};
  endfunction

  // Get A method (demultiplex input based on mode)
  method Action get_A(Bit#(16) input_A);
    if (s1_or_s2_mode == False) begin // S1 mode (int8)
      reg_A_S1 <= input_A[7:0]; // Use lower 8 bits for A in S1
    end else begin // S2 mode (bf16)
      reg_A_S2 <= input_A;
    end
  endmethod

  // Get B method (demultiplex input based on mode)
  method Action get_B(Bit#(16) input_B);
    if (s1_or_s2_mode == False) begin // S1 mode (int8)
      reg_B_S1 <= input_B[7:0]; // Use lower 8 bits for B in S1
    end else begin // S2 mode (bf16)
      reg_B_S2 <= input_B;
    end
  endmethod

  // Get C method (demultiplex input based on mode)
  method Action get_C(Bit#(32) input_C);
    if (s1_or_s2_mode == False) begin // S1 mode (int32)
      reg_C_S1 <= input_C; // Full 32 bits for C in S1
    end else begin // S2 mode (fp32)
      reg_C_S2 <= input_C; // Full 32 bits for C in S2
    end
  endmethod

  // Select mode method
  method Action select_S1_or_S2(Bool mode);
    s1_or_s2_mode <= mode;
  endmethod

  // Start MAC operation (performs MAC operation depending on mode)
  method ActionValue #(Bit#(32)) start_MAC();
    if (s1_or_s2_mode == False) begin // S1 mode (int8 * int8 + int32)
        let product_S1 = shift_and_add_mul(reg_A_S1, reg_B_S1); // Multiply A and B using shift-and-add
        let _mac_result_S1 = ripple_add(zeroExtend(product_S1), reg_C_S1); // Add C to result
        mac_result_S1 <= _mac_result_S1;
        return _mac_result_S1;  // Return the result for S1 mode
    end else begin // S2 mode (bf16 * bf16 + fp32)
        let product_S2 = multiply_bf16(reg_A_S2, reg_B_S2); // Multiply bf16 A and B
        let _mac_result_S2 = ripple_add(product_S2, reg_C_S2); // Add C to result
        mac_result_S2 <= _mac_result_S2;
        return _mac_result_S2;  // Return the result for S2 mode
    end
  endmethod

  // Get MAC result method (returns current result based on mode)
  method Bit#(32) get_MAC_result();
    if (s1_or_s2_mode == False) begin // S1 mode
      return mac_result_S1;
    end else begin // S2 mode
      return mac_result_S2;
    end
  endmethod
endmodule
endpackage
