package mac;
// Import necessary Bluespec libraries
import Vector::*;
import FloatingPoint::*;
// import Float::*;

interface MAC_Interface;
  method Action setInputs(Bit#(16) a_bf16, Bit#(16) b_bf16, Bit#(32) c_fp32);
  method Bit#(32) getResult();
endinterface


// (* synthesize *)

module mkMAC(MAC_Interface);
  // Declare registers to hold inputs
  Reg#(Bit#(16)) reg_A <- mkReg(0);  // bfloat16 A
  Reg#(Bit#(16)) reg_B <- mkReg(0);  // bfloat16 B
  Reg#(Bit#(32)) reg_C <- mkReg(0);  // fp32 C

  // Declare register to hold the result
  Reg#(Bit#(32)) result <- mkReg(0);

  // Convert bfloat16 to fp32
  function Bit#(32) bf16_to_fp32(Bit#(16) bf16);
      Bit#(1) sign   = bf16[15];
      Bit#(8) exp    = bf16[14:7];
      Bit#(7) mant   = bf16[6:0];

      // fp32 format: sign(1), exp(8), mantissa(23)
      return {sign, exp, mant, 16'b0};  // Extend mantissa and return as fp32
  endfunction

  // Perform bit manipulation for multiplication
  function Bit#(32) multiply_bf16(Bit#(16) a_bf16, Bit#(16) b_bf16);
      Bit#(32) a_fp32 = bf16_to_fp32(a_bf16);
      Bit#(32) b_fp32 = bf16_to_fp32(b_bf16);

      // Multiply the two fp32 values (done manually without the * operator)
      Bit#(1) sign = a_fp32[31] ^ b_fp32[31];  // XOR the signs
      Bit#(8) exp = a_fp32[30:23] + b_fp32[30:23] - 8'd127;  // Add exponents and adjust bias
      // Bit#(23) mant = (a_fp32[22:0] * b_fp32[22:0]) >> 23;  // Multiply mantissas and normalize

      // Bit#(14) mant_product = 0;
      // for (Bit#(7) i = 0; i < 8; i = i + 1) begin
      //     mant_product[i + 7] = mant_A[i] & mant_B[0];
      //     for (Bit#(7) j = 1; j < 8; j = j + 1) begin
      //         mant_product[i + j] = mant_product[i + j] ^ (mant_A[i] & mant_B[j]);
      //     end
      // end
      Bit#(23) mant_A = a_fp32[22:0];
      Bit#(23) mant_B = b_fp32[22:0];
      Bit#(23) mant_product = 0; // 23-bit mantissa for fp32
      for (Bit#(7) i = 0; i < 8; i = i + 1) begin
        for (Bit#(7) j = 0; j < 8; j = j + 1) begin
          mant_product[i + j] = mant_product[i + j] ^ (mant_A[i] & mant_B[j]);
        end
      end

      // if (mant_product[23]) begin
      //   mant_product = mant_product >> 1; // Right shift to normalize
      //   exp_product = exp_product + 1; // Increment exponent for normalization
      // end

      return {sign, exp, mant_product};  // Return the fp32 result
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

  // Set inputs method
  method Action setInputs(Bit#(16) a_bf16, Bit#(16) b_bf16, Bit#(32) c_fp32);
      reg_A <= a_bf16;
      reg_B <= b_bf16;
      reg_C <= c_fp32;

      // Multiply A and B (bf16)
      Bit#(32) product_fp32 = multiply_bf16(a_bf16, b_bf16);

      // Add product to C using bit manipulation (manual fp32 addition)
      // Bit#(32) sum = product_fp32 + reg_C;  // Replace this with custom fp32 addition
      Bit#(32) sum_result;
      sum_result = bitwise_add(product_fp32, c_fp32);

      // Rounding logic
      Bit#(1) round_bit = result[22]; // The bit just beyond the mantissa (for rounding)
      Bit#(1) extra_bit = result[23]; // The next bit used for deciding rounding

    // Rounding to nearest, round half to even
      if (round_bit == 1 && extra_bit == 1) begin
        // Increment the result if we need to round up
        sum_result[22:0] =  sum_result[22:0] + 1; // Round up
      end      

      result <= sum_result;  // Store the result
  endmethod

  // Get the result method
  method Bit#(32) getResult();
      return result;
  endmethod
endmodule

module topModule();
  // Instantiate the MAC module
  MAC_Interface mac_inst <- mkMAC;

  // Declare input values
  Bit#(16) a_bf16 = 16'h3f80;  // Example bfloat16 value (1.0)
  Bit#(16) b_bf16 = 16'h3f80;  // Example bfloat16 value (1.0)
  Bit#(32) c_fp32 = 32'h3f800000;  // Example fp32 value (1.0)

  // Set inputs and get result
  rule setInputsAndCompute;
      mac_inst.setInputs(a_bf16, b_bf16, c_fp32);
  endrule

  // Display the result
  rule displayResult;
      Bit#(32) mac_result = mac_inst.getResult();
      $display("MAC Result: %h", mac_result);
  endrule
endmodule


endpackage
