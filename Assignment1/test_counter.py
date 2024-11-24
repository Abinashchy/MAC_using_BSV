# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0

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

	a_bin=os.path.join(os.getcwd(),"counter_verif/test_cases/int8 MAC/A_binary.txt")
	with open(a_bin, "r") as file:
		a_list_bin = [line.strip() for line in file]
	
	b_bin=os.path.join(os.getcwd(),"counter_verif/test_cases/int8 MAC/B_binary.txt")
	with open(b_bin, "r") as file:
		b_list_bin = [line.strip() for line in file]

	c_bin=os.path.join(os.getcwd(),"counter_verif/test_cases/int8 MAC/C_binary.txt")
	with open(c_bin, "r") as file:
		c_list_bin = [line.strip() for line in file]


	mac_dec=os.path.join(os.getcwd(),"counter_verif/test_cases/int8 MAC/MAC_decimal.txt")
	with open(mac_dec, "r") as file:
		mac_list_dec = [line.strip() for line in file]
  
	#for int test cases
	for i in range(0, 1048): #1048
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
		await RisingEdge(dut.CLK)
		print("i = ", i)
		
		# print("Binary A values = ", a_list_bin[i])
		# print("Binary B values = ", b_list_bin[i])
		# print("Binary C values = ", c_list_bin[i])

		# print("Decimal A values = ", temp_a)
		# print("Decimal B values = ", temp_b)
		# print("Decimal C values = ", temp_c)
		# print("----Values from MAC---------------------------")
		# print(dut.get_A_input_A.value)
		# print(dut.get_B_input_B.value)
		# print(dut.get_C_input_C.value)
		dut.select_S1_or_S2_mode.value = 0
		
		#wait for inputs to stabilize
		await RisingEdge(dut.CLK)
		await RisingEdge(dut.CLK)

		u = dut.start_MAC.value
		# print("MAC binary output = ", u)
		v = int(dut.start_MAC.value)
		if v >= (1<<31):
			v -= (1<<32)

		dut._log.info(f'output {v}')

		# print("MAC decimal Ourput = ", v)
		# print("Expected Output = ", int(mac_list_dec[i]))

		if int(mac_list_dec[i]) == v :
			print("success")
		else :
			print("failure")
		
	coverage_db.export_to_yaml(filename="coverage_counter.yml")


def signed_binary_to_int(binary_str):
    bit_length = len(binary_str)
    value = int(binary_str, 2)  # Convert from binary to integer
    
    # Check if the sign bit is set (most significant bit)
    if binary_str[0] == '1':
        value -= (1 << bit_length)  # Convert to negative using two's complement
   
    return value
