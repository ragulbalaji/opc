module opc5lscpu( input[15:0] din, output[15:0] dout, output[15:0] address, output rnw, input clk, input reset_b, input int_b );
   parameter MOV=4'h0,AND=4'h1,OR=4'h2,XOR=4'h3,ADD=4'h4,ADC=4'h5,STO=4'h6,LD=4'h7,ROR=4'h8,NOT=4'h9,SUB=4'hA,SBC=4'hB,CMP=4'hC,CMPC=4'hD,BSWP=4'hE,PSR=4'hF,RTI=17'h100FF;
   parameter FETCH0=3'h0, FETCH1=3'h1, EA_ED=3'h2, RDMEM=3'h3, EXEC=3'h4, WRMEM=3'h5, INT=3'h6 ;
   parameter P0=15, P1=14, P2=13, IRLEN=12, IRLD=16, IRSTO=17, IRGETPSR=18, IRPUTPSR=19, IRCMP=20, INT_VECTOR=16'h0002;
   reg [15:0] OR_q, PC_q, PCI_q, result;
   reg [20:0] IR_q;
   reg [15:0] GRF_q[15:0];
   reg [2:0]  FSM_q;
   reg [3:0]  grf_radr_q, PSRI_q;
   reg        SWI_q, I_q, C_q, Z_q, S_q, zero, carry, sign, swi, isrv_q, enable_int;
   wire predicate = IR_q[P2] ^ (IR_q[P1] ? (IR_q[P0] ? S_q : Z_q) : (IR_q[P0] ? C_q : 1));
   wire predicate_din = din[P2] ^ (din[P1] ? (din[P0] ? S_q : Z_q) : (din[P0] ? C_q : 1));
   wire [15:0] grf_dout= (grf_radr_q==4'hF) ? PC_q: (GRF_q[grf_radr_q] & { 16{(grf_radr_q!=4'h0)}});
   wire        skip_eaed = !((grf_radr_q!=0) || (IR_q[IRLD]) || IR_q[IRSTO]);
   assign      { rnw, dout, address } = { !(FSM_q==WRMEM), grf_dout, ( FSM_q==WRMEM || FSM_q == RDMEM)? OR_q : PC_q };
   always @( * )
     begin
        case (IR_q[11:8])     // no real need for STO entry but include it so all instructions are covered, no need for default
          LD, MOV, PSR, STO   : {carry, result} = {C_q, (IR_q[IRGETPSR])? {13'b0, S_q, C_q, Z_q}: OR_q} ;
          AND, OR             : {carry, result} = {C_q, (IR_q[8])? (grf_dout & OR_q) : (grf_dout | OR_q)};
          ADD, ADC            : {carry, result} = grf_dout + OR_q + (IR_q[8] & C_q);
          SUB, SBC, CMP, CMPC : {carry, result} = grf_dout + (OR_q ^ 16'hFFFF) + ((IR_q[8])? C_q: 1);
          XOR, BSWP           : {carry, result} = {C_q, (!IR_q[11])? (grf_dout ^ OR_q): { OR_q[7:0], OR_q[15:8] }};
          NOT, ROR            : {result, carry} = (IR_q[8]) ? {~OR_q, C_q} : {C_q, OR_q} ;
        endcase // case ( IR_q )
        {swi,enable_int,sign, carry, zero} = (IR_q[IRPUTPSR])? OR_q[4:0]: (IR_q[3:0]!=4'hF)? {SWI_q,I_q, result[15], carry,!(|result)}: {SWI_q,I_q,S_q,C_q,Z_q} ; // don't update flags PC dest operations
     end
   always @(posedge clk or negedge reset_b )
     if (!reset_b)
       FSM_q <= FETCH0;
     else
       case (FSM_q)
         FETCH0 : FSM_q <= (din[IRLEN])? FETCH1 : (!predicate_din )? FETCH0: EA_ED;
         FETCH1 : FSM_q <= (!predicate )? FETCH0: (skip_eaed) ? EXEC : EA_ED;        // Allow FETCH1 to skip through to EXEC
         EA_ED  : FSM_q <= (!predicate )? FETCH0: (IR_q[IRLD]) ? RDMEM : (IR_q[IRSTO]) ? WRMEM : EXEC;
         RDMEM  : FSM_q <= EXEC;
         EXEC   : FSM_q <= ((!int_b || SWI_q) & I_q & !isrv_q ) ? INT :  (IR_q[3:0]==4'hF)? FETCH0: (din[IRLEN]) ? FETCH1 : EA_ED; // Cant interrupt an interrupt ...
         default: FSM_q <= ((!int_b || SWI_q) & I_q & !isrv_q ) ? INT :  FETCH0;
       endcase // case (FSM_q)
   always @(posedge clk)
     case(FSM_q)
       FETCH0, EXEC  : {grf_radr_q, OR_q } <= {din[7:4], 16'b0};
       FETCH1        : {grf_radr_q, OR_q } <= {((skip_eaed)? IR_q[3:0] : IR_q[7:4]), din};
       RDMEM         : {grf_radr_q, OR_q } <= {IR_q[3:0], din};
       EA_ED         : {grf_radr_q, OR_q } <= {IR_q[3:0], grf_dout + OR_q};
       default       : {grf_radr_q, OR_q } <= {4'bx, 16'bx};
     endcase
   always @(posedge clk or negedge reset_b)
     if ( !reset_b)
       { PC_q, PCI_q, isrv_q, PSRI_q, I_q, SWI_q} <= 39'b0;
     else if ( FSM_q == INT )
       { PC_q, PCI_q, isrv_q, PSRI_q } <= { INT_VECTOR, PC_q, 1'b1,  I_q, S_q, C_q, Z_q} ;
     else if ( FSM_q == FETCH0 || FSM_q == FETCH1 )
       PC_q <= PC_q + 1;
     else if ( FSM_q == EXEC )
        begin
            PC_q <= ( {isrv_q,IR_q[15:0]}==RTI)? PCI_q : (IR_q[3:0]==4'hF) ? result : ((!int_b || SWI_q) & I_q & !isrv_q )? PC_q: PC_q + 1 ; //Dont incr PC if taking interrupt
            {isrv_q, SWI_q, I_q} <= { (( {isrv_q,IR_q[15:0]} ==RTI)? 2'b0: {isrv_q, swi}), enable_int};
        end
   always @ (posedge clk)
     if ( FSM_q == EXEC )
        { S_q, C_q, Z_q, GRF_q[(IR_q[IRCMP])?4'b0:IR_q[3:0]] } <= ({isrv_q,IR_q[15:0]}==RTI) ? {PSRI_q[2:0], result} : { sign, carry, zero, result};
   always @ (posedge clk)
     if ( FSM_q == FETCH0 || FSM_q == EXEC)
        IR_q <= { ((din[11:8]==CMP)||(din[11:8]==CMPC)), {2{(din[11:8]==PSR)}} & {(din[3:0]==4'h0),(din[7:4]==4'b0)}, (din[11:8]==STO),(din[11:8]==LD), din};
endmodule
