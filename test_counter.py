import cocotb
from cocotb.triggers import RisingEdge, Timer
import os
import random
from model_counter import *

async def apply_inputs(dut, a, b, c):
    # Apply inputs to the DUT
    dut.a.value = a
    dut.b.value = b
    dut.c.value = c
    await RisingEdge(dut.clk)

@cocotb.test()
async def mac_random_test(dut):
    """Randomized test for the MAC design with inputs and expected outputs from files."""
    # Paths to input and output files
    input_a_path = os.path.join(os.getcwd(), "test_cases/bf16MAC/A_binary.txt")
    input_b_path = os.path.join(os.getcwd(), "test_cases/bf16MAC/B_binary.txt")
    input_c_path = os.path.join(os.getcwd(), "test_cases/bf16MAC/C_binary.txt")
    output_path = os.path.join(os.getcwd(), "test_cases/bf16MAC/MAC_binary.txt")

    # Load input and output data
    with open(input_a_path, 'r') as f:
        inputs_a = [int(line.strip()) for line in f.readlines()]
    
    with open(input_b_path, 'r') as f:
        inputs_b = [int(line.strip()) for line in f.readlines()]
    
    with open(input_c_path, 'r') as f:
        inputs_c = [int(line.strip()) for line in f.readlines()]
    
    with open(output_path, 'r') as f:
        expected_outputs = [int(line.strip()) for line in f.readlines()]

    # Ensure all files have the same number of lines
    assert len(inputs_a) == len(inputs_b) == len(inputs_c) == len(expected_outputs), \
        "Mismatch in number of test vectors across input/output files."

    # Reset the design
    dut.reset.value = 1
    await Timer(10, units='ns')
    dut.reset.value = 0
    await Timer(10, units='ns')

    # Number of random tests to perform
    num_tests = 10  # Adjust this as needed for more or fewer tests

    for _ in range(num_tests):
        # Randomly select an index
        index = random.randint(0, len(inputs_a) - 1)
        
        # Retrieve random inputs and expected output
        a = inputs_a[index]
        b = inputs_b[index]
        c = inputs_c[index]
        expected_output = expected_outputs[index]

        # Apply inputs and wait for a clock cycle
        await apply_inputs(dut, a, b, c)
        await Timer(10, units='ns')  # Wait for any processing delay

        # Capture the output
        result = dut.output.value.integer

        # Check the result
        assert result == expected_output, f"Test failed for inputs a={a}, b={b}, c={c}: expected {expected_output}, got {result}"
        cocotb.log.info(f"Test passed for inputs a={a}, b={b}, c={c}: output {result}")
