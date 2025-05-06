# User IOp with immediat used for debug
# Hooked in opcode 16
# IOP_16 <I2 I2>     <I2@0x10> <I2@0x08> <0x4>
LD       R0    TS[0].0
PBS_F    R0    R0      PbsNone
ST       TD[0].0       R0
