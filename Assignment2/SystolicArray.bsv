package SystolicArray;

import Vector::*;
import FIFO::*;
import FIFOF::*;

// Processing Element (PE) interface
interface PE_ifc;
    method Action putA(Int#(32) a);
    method Action putB(Int#(32) b);
    method Int#(32) getA();
    method Int#(32) getB();
    method Int#(32) getC();
    method Action clear();
endinterface

// Processing Element module
(* synthesize *)
module mkPE(PE_ifc);
    Reg#(Int#(32)) a <- mkReg(0);
    Reg#(Int#(32)) b <- mkReg(0);
    Reg#(Int#(32)) c <- mkReg(0);
    
    // Multiply-accumulate operation
    rule mac;
        c <= c + (a * b);
    endrule
    
    method Action putA(Int#(32) new_a);
        a <= new_a;
    endmethod
    
    method Action putB(Int#(32) new_b);
        b <= new_b;
    endmethod
    
    method Int#(32) getA();
        return a;
    endmethod
    
    method Int#(32) getB();
        return b;
    endmethod
    
    method Int#(32) getC();
        return c;
    endmethod
    
    method Action clear();
        c <= 0;
    endmethod
endmodule

// Systolic Array interface
interface SystolicArray_ifc;
    method Action loadA(Vector#(4, Int#(32)) row);
    method Action loadB(Vector#(4, Int#(32)) col);
    method Vector#(4, Vector#(4, Int#(32))) getResult();
    method Action start();
    method Action clear();
endinterface

// Main Systolic Array module
(* synthesize *)
module mkSystolicArray(SystolicArray_ifc);
    // 4x4 array of PEs
    Vector#(4, Vector#(4, PE_ifc)) pes <- replicateM(replicateM(mkPE));
    
    // Input FIFOs for matrix A (rows) - using FIFOF for notEmpty method
    Vector#(4, FIFOF#(Int#(32))) fifo_a <- replicateM(mkFIFOF);
    
    // Input FIFOs for matrix B (columns) - using FIFOF for notEmpty method
    Vector#(4, FIFOF#(Int#(32))) fifo_b <- replicateM(mkFIFOF);
    
    // Control registers
    Reg#(Bool) active <- mkReg(False);
    Reg#(UInt#(8)) cycle_count <- mkReg(0);

    function Bool checkNotFull(FIFOF#(Int#(32)) fifo);
        return fifo.notFull;
    endfunction
    
    // Main computation rule
    rule compute(active);
        cycle_count <= cycle_count + 1;
        
        // Data propagation through the array
        for(Integer i = 0; i < 4; i = i + 1) begin
            for(Integer j = 0; j < 4; j = j + 1) begin
                if(i == 0 && fifo_a[j].notEmpty) begin
                    pes[i][j].putA(fifo_a[j].first);
                end
                if(j == 0 && fifo_b[i].notEmpty) begin
                    pes[i][j].putB(fifo_b[i].first);
                end
                if(i > 0) begin
                    pes[i][j].putA(pes[i-1][j].getA());
                end
                if(j > 0) begin
                    pes[i][j].putB(pes[i][j-1].getB());
                end
            end
        end
        
        // Dequeue input FIFOs
        if(pack(cycle_count)[2:0] == 0) begin
            for(Integer i = 0; i < 4; i = i + 1) begin
                if (fifo_a[i].notEmpty) begin
                    fifo_a[i].deq;
                end
                if (fifo_b[i].notEmpty) begin
                    fifo_b[i].deq;
                end
            end
        end
    endrule
    
    method Action loadA(Vector#(4, Int#(32)) row) if (all(checkNotFull, fifo_a));
        for(Integer i = 0; i < 4; i = i + 1) begin
            fifo_a[i].enq(row[i]);
        end
    endmethod
    
    method Action loadB(Vector#(4, Int#(32)) col) if (all(checkNotFull, fifo_a));
        for(Integer i = 0; i < 4; i = i + 1) begin
            fifo_b[i].enq(col[i]);
        end
    endmethod
    
    method Vector#(4, Vector#(4, Int#(32))) getResult();
        Vector#(4, Vector#(4, Int#(32))) result = newVector;
        for(Integer i = 0; i < 4; i = i + 1) begin
            result[i] = newVector;
            for(Integer j = 0; j < 4; j = j + 1) begin
                result[i][j] = pes[i][j].getC();
            end
        end
        return result;
    endmethod
    
    method Action start();
        active <= True;
        cycle_count <= 0;
    endmethod
    
    method Action clear();
        active <= False;
        cycle_count <= 0;
        for(Integer i = 0; i < 4; i = i + 1) begin
            for(Integer j = 0; j < 4; j = j + 1) begin
                pes[i][j].clear();
            end
        end
    endmethod
endmodule

typedef enum {
    Load,
    Wait,
    Start,
    Done
} State deriving(Bits, Eq);

// Test bench module
(* synthesize *)
module mkTestBench(Empty);
    SystolicArray_ifc sa <- mkSystolicArray();
    Reg#(Bool) initialized <- mkReg(False);

    Reg#(State) state <- mkReg(Load);
    
    rule init (!initialized && state == Load);
        Vector#(4, Int#(32)) test_row = replicate(0);
        Vector#(4, Int#(32)) test_col = replicate(0);
        
        // Load test data
        test_row[0] = 1; test_row[1] = 2; test_row[2] = 3; test_row[3] = 4;
        test_col[0] = 5; test_col[1] = 6; test_col[2] = 7; test_col[3] = 8;
        
        sa.loadA(test_row);
        sa.loadB(test_col);
        state <= Wait;
    endrule
    
    rule wait_state (state == Wait);
        state <= Start;
    endrule
    
    rule start_array (state == Start);
        sa.start();
        state <= Done;
        initialized <= True;
    endrule
    
    rule display (initialized);
        Vector#(4, Vector#(4, Int#(32))) result = sa.getResult();
        $display("Result Matrix:");
        for(Integer i = 0; i < 4; i = i + 1) begin
            for(Integer j = 0; j < 4; j = j + 1) begin
                $display("%d ", result[i][j]);
            end
            $display("");
        end
        
        $finish;
    endrule
endmodule

endpackage
