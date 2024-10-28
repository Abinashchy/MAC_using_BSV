package mac;
// Import necessary Bluespec libraries
import Vector::*;
import FloatingPoint::*;
// import Float::*;


 // Interface with the predefined methods for A, B, C, S1_or_S2, and MAC
  interface MACInterface;
    method Action get_A(Bit#(16) input_A);
    method Action get_B(Bit#(16) input_B);
    method Action get_C(Bit#(32) input_C);
    method Action select_S1_or_S2(Bool mode); // mode: 0 for S1, 1 for S2
    method ActionValue #(Bit#(32)) start_MAC();
    method Bit#(32) get_MAC_result(); // Result output for both S1 and S2
  endinterface

// Version 1 of the counter

(* synthesize *)

module mkMAC(MACInterface);
   
  
  // Register to hold the mode (S1 or S2)
  Reg#(Bool) s1_or_s2_mode <- mkReg(False); // False = S1, True = S2

  // Registers for inputs A, B, C
  Reg#(Bit#(8)) reg_A_S1 <- mkReg(0);
  Reg#(Bit#(8)) reg_B_S1 <- mkReg(0);
  Reg#(Bit#(32)) reg_C_S1 <- mkReg(0);
  
  //Registers for floating point
  
  Reg#(Bit#(16)) reg_A_S2 <- mkReg(0);  //bf16
  Reg#(Bit#(16)) reg_B_S2 <- mkReg(0);  //bf16
  Reg#(Bit#(32)) reg_C_S2 <- mkReg(0);  //fp32

  // Registers for intermediate results
  Reg#(Bit#(32)) mac_result_S1 <- mkReg(0);
  Reg#(Bit#(32)) mac_result_S2 <- mkReg(0);

  // Ripple-carry adder for 32-bit addition
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

  // Shift-and-add multiplication for unsigned 8-bit numbers
  function Bit#(32) shift_and_add_mul(Bit#(8) a, Bit#(8) b);
    Bit#(32) product = 0;
    Bit#(32) temp_A = zeroExtend(a);
    for (Integer i = 0; i < 8; i = i + 1) begin
      if (b[i] == 1) begin
        product = ripple_add(product, temp_A); // Add shifted A if corresponding bit in B is set
      end
      temp_A = temp_A << 1; // Shift A to the left
    end
    return product;
  endfunction

//Functions for S2
  function Bit#(32) bf16_to_fp32(Bit#(16) bf16);
    Bit#(1) sign   = bf16[15];
    Bit#(8) exp    = bf16[14:7];
    Bit#(7) mant   = bf16[6:0];

    // fp32 format: sign(1), exp(8), mantissa(23)
    return {sign, exp, mant, 16'b0};  // Extend mantissa and return as fp32
  endfunction

function Bit#(32) multiply_bf16(Bit#(16) a_bf16, Bit#(16) b_bf16);
  Bit#(32) a_fp32 = bf16_to_fp32(a_bf16);
  Bit#(32) b_fp32 = bf16_to_fp32(b_bf16);

    // Determine sign and exponent
  Bit#(1)  sign   = a_fp32[31] ^ b_fp32[31];          // XOR the signs
  Bit#(8)  exp_a  = a_fp32[30:23];
  Bit#(8)  exp_b  = b_fp32[30:23];
  Bit#(8)  exp    = exp_a ^ exp_b ^ 8'd127;            // Approximate exponent addition with bias correction
  Bit#(24) mant_a = {1'b1, a_fp32[22:0]};          // Implicit leading 1 for normalized fp32 mantissa
  Bit#(24) mant_b = {1'b1, b_fp32[22:0]};
  Bit#(48) mant_product = 0;

  // Perform bitwise shift-and-add for mantissa multiplication
  for (Integer i = 0; i < 24; i = i + 1) begin
    if (mant_b[i] == 1) begin
      mant_product = mant_product ^ (zeroExtend(mant_a) << i);
    end
  end

  // Normalize result (if necessary)
  Bit#(8) final_exp;
  Bit#(23) final_mant;
  if (mant_product[47] == 1) begin
    final_mant = mant_product[46:24];
    final_exp = exp ^ 8'd1;  // Increment exponent by 1 without using +
  end else begin
    final_mant = mant_product[45:23];
    final_exp = exp;
  end

  // Assemble the final fp32 result
  return {sign, final_exp, final_mant};
endfunction

function Bit#(32) bitwise_add(Bit#(32) a, Bit#(32) b);
Bit#(32) result = 0;
Bit#(1) carry = 0;
for (Bit#(32) i = 0; i < 32; i = i + 1) begin
    result[i] = a[i] ^ b[i] ^ carry; // XOR for addition
    carry = (a[i] & b[i]) | (carry & (a[i] ^ b[i])); // Carry logic
end
return result;
endfunction

  // Get A method (demultiplex input based on mode)
  method Action get_A(Bit#(16) input_A);
    if (s1_or_s2_mode == False) begin // S1 mode (int8)
      reg_A_S1 <= input_A[7:0]; // Use lower 8 bits for A in S1
    end else begin // S2 mode (bf16)
      reg_A_S2 <= unpack(input_A); // Full 16 bits as bf16 for A in S2
    end
  endmethod

  // Get B method (demultiplex input based on mode)
  method Action get_B(Bit#(16) input_B);
    if (s1_or_s2_mode == False) begin // S1 mode (int8)
      reg_B_S1 <= input_B[7:0]; // Use lower 8 bits for B in S1
    end else begin // S2 mode (bf16)
      reg_B_S2 <= unpack(input_B); // Full 16 bits as bf16 for B in S2
    end
  endmethod

  // Get C method (demultiplex input based on mode)
  method Action get_C(Bit#(32) input_C);
    if (s1_or_s2_mode == False) begin // S1 mode (int32)
      reg_C_S1 <= input_C; // Full 32 bits for C in S1
    end else begin // S2 mode (fp32)
      reg_C_S2 <= unpack(input_C); // Full 32 bits for C in S2
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
      mac_result_S1 <= ripple_add(zeroExtend(product_S1), reg_C_S1); // Accumulate with C using ripple-carry adder
      return mac_result_S1;
    end else begin // S2 mode (bf16 * bf16 + fp32)

      Bit#(32) product_S2_fp32;
      Bit#(32) sum_result;

      product_S2_fp32 = multiply_bf16(reg_A_S2, reg_B_S2); // Multiply A and B
      sum_result = bitwise_add(product_S2_fp32, reg_C_S2);

      Bit#(1) round_bit = sum_result[22]; // The bit just beyond the mantissa (for rounding)
      Bit#(1) extra_bit = sum_result[23]; // The next bit used for deciding rounding
    // Rounding to nearest, round half to even
      if (round_bit == 1 && extra_bit == 1) begin
        // Increment the result if we need to round up
        sum_result[22:0] =  sum_result[22:0] + 1; // Round up
      end  
      mac_result_S2 <= sum_result;  // Store the result
      return mac_result_S2;

    end
  endmethod

  // Get MAC result method (multiplex result based on mode)
  method Bit#(32) get_MAC_result();
    // return mac_result_S1;
    if (s1_or_s2_mode == False) begin
      return mac_result_S1; // Return S1 result as 32-bit int
    end else begin
      return pack(mac_result_S2); // Return S2 result as 32-bit fp32
    end
  endmethod

endmodule

endpackage
