import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb_coverage.coverage import coverage_db
@cocotb.test()
async def test_counter(dut):

    clock = Clock(dut.CLK, 10, units="us")  # Create a 10us period clock on port clk
    # Start the clock. Start it low to avoid issues on the first RisingEdge
    cocotb.start_soon(clock.start(start_high=False))

    ## test using model
    dut.RST_N.value = 0
    await RisingEdge(dut.CLK)
    dut.RST_N.value = 1

    a_bin=os.path.join(os.getcwd(),"counter_verif/test_cases/bf16 MAC/A_binary.txt")
    with open(a_bin, "r") as file:
        a_list_bin = [line.strip() for line in file]
   
    b_bin=os.path.join(os.getcwd(),"counter_verif/test_cases/bf16 MAC/B_binary.txt")
    with open(b_bin, "r") as file:
        b_list_bin = [line.strip() for line in file]

    c_bin=os.path.join(os.getcwd(),"counter_verif/test_cases/bf16 MAC/C_binary.txt")
    with open(c_bin, "r") as file:
        c_list_bin = [line.strip() for line in file]


    mac_dec=os.path.join(os.getcwd(),"counter_verif/test_cases/bf16 MAC/MAC_decimal.txt")
    with open(mac_dec, "r") as file:
        mac_list_dec = [line.strip() for line in file]
 
    #for int test cases
    for i in range(0, 10): #1048
        dut.EN_get_A.value = 1
        dut.EN_get_B.value = 1
        dut.EN_get_C.value = 1
        dut.EN_select_S1_or_S2.value = 1
        temp_a = signed_binary_to_int(a_list_bin[i])
        temp_b = signed_binary_to_int(b_list_bin[i])
        temp_c = signed_binary_to_int(c_list_bin[i])
        await RisingEdge(dut.CLK)
        dut.get_A_input_A.value = temp_a #signed_binary_to_int(a_list_bin[i])
        dut.get_B_input_B.value = temp_b #signed_binary_to_int(b_list_bin[i])
        dut.get_C_input_C.value = temp_c #signed_binary_to_int(c_list_bin[i])
        dut.select_S1_or_S2_mode.value = True
        await RisingEdge(dut.CLK)
        print("i = ", i)
       
        # print("Binary A values = ", a_list_bin[i])
        # print("Binary B values = ", b_list_bin[i])
        # print("Binary C values = ", c_list_bin[i])

        # print("Decimal A values = ", binary_to_float(a_list_bin[i]))
        # print("Decimal B values = ", binary_to_float(b_list_bin[i]))
        # print("Decimal C values = ", binary_to_float(c_list_bin[i]))
        # print("----Values from MAC---------------------------")
        # print(dut.get_A_input_A.value)
        # print(dut.get_B_input_B.value)
        # print(dut.get_C_input_C.value)
        dut.select_S1_or_S2_mode.value = 1
       
        #wait for inputs to stabilize
        await RisingEdge(dut.CLK)
        await RisingEdge(dut.CLK)

        code_output = binary_to_float(str(dut.start_MAC.value))
        print("Code Output = ", code_output)
        print("Expected Output = ", mac_list_dec[i])

        dut._log.info(f'output {code_output}')

        if mac_list_dec[i] == code_output :
            print("success")
        else :
            print("failure")
        #assert int(mac_out) == int(dut.result.value), f'Counter Output Mismatch, Expected = {mac_out} DUT = {int(dut.result.value)}'

    coverage_db.export_to_yaml(filename="coverage_counter.yml")


def signed_binary_to_int(binary_str):
    bit_length = len(binary_str)
    value = int(binary_str, 2)  # Convert from binary to integer
   
    # Check if the sign bit is set (most significant bit)
    if binary_str[0] == '1':
        value -= (1 << bit_length)  # Convert to negative using two's complement
   
    return value

def binary_to_float(binary_str):
    if len(binary_str) == 32:
        sign = int(binary_str[0], 2)
        exponent = int(binary_str[1:9], 2)
        mantissa = binary_str[9:]
   
        # Compute the actual exponent (subtract bias of 127)
        exp_value = exponent - 127
   
        # Reconstruct the floating-point number
        mantissa_value = 1  # Implicit leading 1 for normalized numbers
        for i, bit in enumerate(mantissa):
            if bit == '1':
                mantissa_value += 2 ** -(i + 1)
   
        # Final result
        result = (-1) ** sign * mantissa_value * (2 ** exp_value)
        return result
    else:
        sign = int(binary_str[0], 2)
        exponent = int(binary_str[1:9], 2)
        mantissa = binary_str[9:]
   
        # Handle special cases
        if exponent == 255:  # All 1s in exponent
            if mantissa == "0" * 7:
                return float("inf") if sign == 0 else float("-inf")
            else:
                return float("nan")
        elif exponent == 0:  # All 0s in exponent
            if mantissa == "0" * 7:
                return -0.0 if sign == 1 else 0.0  # Signed zero
            else:
                # Denormalized number
                mantissa_value = sum(int(bit) * (2 ** -(i + 1)) for i, bit in enumerate(mantissa))
                value = (-1) ** sign * mantissa_value * (2 ** -126)
                return value
   
        # Normalized number
        mantissa_value = 1 + sum(int(bit) * (2 ** -(i + 1)) for i, bit in enumerate(mantissa))
        value = (-1) ** sign * mantissa_value * (2 ** (exponent - 127))
        return value
