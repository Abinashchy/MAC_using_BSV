# model for increment alone

import cocotb
from cocotb_coverage.coverage import *

counter_coverage = coverage_section(
    CoverPoint('top.increment_di', vname='increment_di', bins = list(range(0,16))),
    CoverPoint('top.EN_increment', vname='EN_increment', bins = list(range(0,2))),
    CoverCross('top.cross_cover', items = ['top.increment_di', 'top.EN_increment'])
)
@counter_coverage
def model_counter(current_state, EN_increment: int, increment_di: int) -> int:
    if(EN_increment):
        return current_state + increment_di
    return 0