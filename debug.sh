
# FIFO_WRITE_FIFO_WRITE_DATA_COUNT_OFS
./app/build/ami_tool peek -d 01:00.0 -a 0x50028 -l 1

# -----------------------------------------------------------------------------
# debug
# lane 0
./app/build/ami_tool peek -d 01:00.0 -a 0x40740 -l 1
./app/build/ami_tool peek -d 01:00.0 -a 0x40744 -l 1
# lane 1
./app/build/ami_tool peek -d 01:00.0 -a 0x41740 -l 1
./app/build/ami_tool peek -d 01:00.0 -a 0x41744 -l 1
# lane 2
./app/build/ami_tool peek -d 01:00.0 -a 0x42740 -l 1
./app/build/ami_tool peek -d 01:00.0 -a 0x42744 -l 1
# lane 3
./app/build/ami_tool peek -d 01:00.0 -a 0x43740 -l 1
./app/build/ami_tool peek -d 01:00.0 -a 0x43744 -l 1

# cycle count lsb & msb
./app/build/ami_tool peek -d 01:00.0 -a 0x40800 -l 1
./app/build/ami_tool peek -d 01:00.0 -a 0x40804 -l 1

# CNT_CLK_OFS
./app/build/ami_tool peek -d 01:00.0 -a 0x5003c -l 1
# CNT_TRIG_RD_OFS
./app/build/ami_tool peek -d 01:00.0 -a 0x50040 -l 1
# CNT_TX_WR_OFS
./app/build/ami_tool peek -d 01:00.0 -a 0x50044 -l 1
# CNT_WORDS_OFS
./app/build/ami_tool peek -d 01:00.0 -a 0x50048 -l 1
# STAT_STATUS_OFS
./app/build/ami_tool peek -d 01:00.0 -a 0x5004c -l 1

# total tx packet
./app/build/ami_tool peek -d 01:00.0 -a 0x40818 -l 2
# total tx good packets
./app/build/ami_tool peek -d 01:00.0 -a 0x40820 -l 2
# total tx total bytes
./app/build/ami_tool peek -d 01:00.0 -a 0x40828 -l 2
# total tx total good bytes
./app/build/ami_tool peek -d 01:00.0 -a 0x40830 -l 2

# -----------------------------------------------------------------------------
# lane 0
./app/build/ami_tool peek -d 01:00.0 -a 0x40740 -l 1
./app/build/ami_tool peek -d 01:00.0 -a 0x40744 -l 1
./app/build/ami_tool peek -d 01:00.0 -a 0x40754 -l 1 # block lock
./app/build/ami_tool peek -d 01:00.0 -a 0x40758 -l 1 # lane sync


./app/build/ami_tool peek -d 01:00.0 -a 0x40740 -l 1
./app/build/ami_tool peek -d 01:00.0 -a 0x40744 -l 1
./app/build/ami_tool peek -d 01:00.0 -a 0x40748 -l 1 # RT TX
./app/build/ami_tool peek -d 01:00.0 -a 0x4074C -l 1 # RT RX

./app/build/ami_tool peek -d 01:00.0 -a 0x40744 -l 1
./app/build/ami_tool peek -d 01:00.0 -a 0x41744 -l 1
./app/build/ami_tool peek -d 01:00.0 -a 0x42744 -l 1
./app/build/ami_tool peek -d 01:00.0 -a 0x43744 -l 1
