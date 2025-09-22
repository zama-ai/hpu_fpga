#  GT conf - near end pcs lane0
./app/build/ami_tool poke -d 24:00.0 -a 0x60010 -i 0x10

# Reset all ports
./app/build/ami_tool poke -d 24:00.0 -a 0x40004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d 24:00.0 -a 0x41004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d 24:00.0 -a 0x42004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d 24:00.0 -a 0x43004 -i 0xFFFFFFFF

# mode 25Ge port 0
./app/build/ami_tool poke -d 24:00.0 -a 0x40008 -i 0x40000221
#  ctl tx igp - FCS - Port tx enable
./app/build/ami_tool poke -d 24:00.0 -a 0x40010 -i 0x00000033
./app/build/ami_tool poke -d 24:00.0 -a 0x4000C -i 0x00000C03
# no fec
./app/build/ami_tool poke -d 24:00.0 -a 0x400D0 -i 0x00000000

# mode 25Ge port 1
./app/build/ami_tool poke -d 24:00.0 -a 0x41008 -i 0x40000240
./app/build/ami_tool poke -d 24:00.0 -a 0x4100C -i 0x00000C01
./app/build/ami_tool poke -d 24:00.0 -a 0x41010 -i 0x00000033
./app/build/ami_tool poke -d 24:00.0 -a 0x410D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d 24:00.0 -a 0x42008 -i 0x40000240
./app/build/ami_tool poke -d 24:00.0 -a 0x4200C -i 0x00000C03
./app/build/ami_tool poke -d 24:00.0 -a 0x42010 -i 0x00000033
./app/build/ami_tool poke -d 24:00.0 -a 0x420D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d 24:00.0 -a 0x43008 -i 0x40000240
./app/build/ami_tool poke -d 24:00.0 -a 0x4300C -i 0x00000C01
./app/build/ami_tool poke -d 24:00.0 -a 0x43010 -i 0x00000033
./app/build/ami_tool poke -d 24:00.0 -a 0x430D0 -i 0x0

# de-assert
./app/build/ami_tool poke -d 24:00.0 -a 0x40004 -i 0x0
./app/build/ami_tool poke -d 24:00.0 -a 0x41004 -i 0x0
./app/build/ami_tool poke -d 24:00.0 -a 0x42004 -i 0x0
./app/build/ami_tool poke -d 24:00.0 -a 0x43004 -i 0x0

# Reset from DMA rtl
./app/build/ami_tool poke -d 24:00.0 -a 0x60014 -i 0xFFF
./app/build/ami_tool poke -d 24:00.0 -a 0x60014 -i 0x0
./app/build/ami_tool peek -d 24:00.0 -a 0x60018 -l 1

# -----------------------------------------------------------------------------
# lane 0
./app/build/ami_tool peek -d 24:00.0 -a 0x40740 -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x40744 -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x40754 -l 1 # block lock
./app/build/ami_tool peek -d 24:00.0 -a 0x40758 -l 1 # lane sync

# # lane 1
# ./app/build/ami_tool peek -d 24:00.0 -a 0x41740 -l 1
# ./app/build/ami_tool peek -d 24:00.0 -a 0x41744 -l 1
# # lane 2
# ./app/build/ami_tool peek -d 24:00.0 -a 0x42740 -l 1
# ./app/build/ami_tool peek -d 24:00.0 -a 0x42744 -l 1
# # lane 3
# ./app/build/ami_tool peek -d 24:00.0 -a 0x43740 -l 1
# ./app/build/ami_tool peek -d 24:00.0 -a 0x43744 -l 1

./app/build/ami_tool peek -d 24:00.0 -a 0x40744 -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x41744 -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x42744 -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x43744 -l 1
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Push ethernet frame

# 16 words
./app/build/ami_tool peek -d 24:00.0 -a 0x6001c -l 1
./app/build/ami_tool poke -d 24:00.0 -a 0x6001c -i 0x10
./app/build/ami_tool peek -d 24:00.0 -a 0x6001c -l 1

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0x0101010
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0x1111111

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0x2020202
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0x2222222

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0x3030303
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0x3333333

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0x40404040
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0x44444444

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0x50505050
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0x55555555

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0x60606060
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0x66666666

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0x70707070
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0x77777777

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0x80808080
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0x88888888

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0x90909090
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0x99999999

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0xa0a0a0a0
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0xaaaaaaaa

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0xb0b0bb0b
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0xbbbbbbbb

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0xc0c0cc0c
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0xcccccccc

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0xd0d0d0d0
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0xdddddddd

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0xe0e0e0e0
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0xeeeeeeee

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0xf0f0f0f0
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0xffffffff

# FIFO_WRITE_FIFO_WRITE_DATA_COUNT_OFS
./app/build/ami_tool peek -d 24:00.0 -a 0x60028 -l 1

./app/build/ami_tool poke -d 24:00.0 -a 0x60020 -i 0xafafafaf
./app/build/ami_tool poke -d 24:00.0 -a 0x60024 -i 0x00decode

# FIFO_WRITE_FIFO_WRITE_DATA_COUNT_OFS
./app/build/ami_tool peek -d 24:00.0 -a 0x60028 -l 1

# -----------------------------------------------------------------------------
# debug
# lane 0
./app/build/ami_tool peek -d 24:00.0 -a 0x40740 -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x40744 -l 1
# lane 1
./app/build/ami_tool peek -d 24:00.0 -a 0x41740 -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x41744 -l 1
# lane 2
./app/build/ami_tool peek -d 24:00.0 -a 0x42740 -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x42744 -l 1
# lane 3
./app/build/ami_tool peek -d 24:00.0 -a 0x43740 -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x43744 -l 1

# cycle count lsb & msb
./app/build/ami_tool peek -d 24:00.0 -a 0x40800 -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x40804 -l 1

# CNT_CLK_OFS
./app/build/ami_tool peek -d 24:00.0 -a 0x6003c -l 1
# CNT_TRIG_RD_OFS
./app/build/ami_tool peek -d 24:00.0 -a 0x60040 -l 1
# CNT_TX_WR_OFS
./app/build/ami_tool peek -d 24:00.0 -a 0x60044 -l 1
# CNT_WORDS_OFS
./app/build/ami_tool peek -d 24:00.0 -a 0x60048 -l 1
# STAT_STATUS_OFS
./app/build/ami_tool peek -d 24:00.0 -a 0x6004c -l 1

# -----------------------------------------------------------------------------

./app/build/ami_tool peek -d 24:00.0 -a 0x60030 -l 1

./app/build/ami_tool peek -d 24:00.0 -a 0x6002c -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x60030 -l 1


