./app/build/ami_tool poke -d e1:00.0 -a 0x50e10 -i 0x80000000
./app/build/ami_tool poke -d e1:00.0 -a 0x50e10 -i 0x0
sleep 1

# Reset all ports
./app/build/ami_tool poke -d e1:00.0 -a 0x40004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d e1:00.0 -a 0x41004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d e1:00.0 -a 0x42004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d e1:00.0 -a 0x43004 -i 0xFFFFFFFF

# mode 25Ge for ports 0 1 2 3
# (Narrow mode - 40-bit GT interface, Independent 64b - 390.625 MHz, 25GE data rate)
# (Check preamble, Check start frame delimiter, FCS removal enabled, Enable RX)
# (IPG = 12 bytes,  FCS insertion enabled, No local fault, No remote fault, Enable TX)
# (No FEC)
./app/build/ami_tool poke -d e1:00.0 -a 0x41008 -i 0x40000221
./app/build/ami_tool poke -d e1:00.0 -a 0x40010 -i 0x00000003
./app/build/ami_tool poke -d e1:00.0 -a 0x4000C -i 0x00000c03
./app/build/ami_tool poke -d e1:00.0 -a 0x400D0 -i 0x00000000

# mode 25Ge port 1
./app/build/ami_tool poke -d e1:00.0 -a 0x41008 -i 0x40000221
./app/build/ami_tool poke -d e1:00.0 -a 0x41010 -i 0x00000033
./app/build/ami_tool poke -d e1:00.0 -a 0x4100C -i 0x00000C01
./app/build/ami_tool poke -d e1:00.0 -a 0x410D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d e1:00.0 -a 0x42008 -i 0x40000221
./app/build/ami_tool poke -d e1:00.0 -a 0x42010 -i 0x00000033
./app/build/ami_tool poke -d e1:00.0 -a 0x4200C -i 0x00000C03
./app/build/ami_tool poke -d e1:00.0 -a 0x420D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d e1:00.0 -a 0x43008 -i 0x40000221
./app/build/ami_tool poke -d e1:00.0 -a 0x43010 -i 0x00000033
./app/build/ami_tool poke -d e1:00.0 -a 0x4300C -i 0x00000C01
./app/build/ami_tool poke -d e1:00.0 -a 0x430D0 -i 0x0

# tick reg
./app/build/ami_tool poke -d e1:00.0 -a 0x4002c -i 0x1

# de-assert
./app/build/ami_tool poke -d e1:00.0 -a 0x40004 -i 0x0
./app/build/ami_tool poke -d e1:00.0 -a 0x41004 -i 0x0
./app/build/ami_tool poke -d e1:00.0 -a 0x42004 -i 0x0
./app/build/ami_tool poke -d e1:00.0 -a 0x43004 -i 0x0

# Reset from DMA rtl
./app/build/ami_tool poke -d e1:00.0 -a 0x50014 -i 0xFFF
./app/build/ami_tool poke -d e1:00.0 -a 0x50014 -i 0x0
./app/build/ami_tool peek -d e1:00.0 -a 0x50018 -l 1
# -----------------------------------------------------------------------------
sleep 1

# -----------------------------------------------------------------------------
# Push ethernet frame

# 16 words
./app/build/ami_tool peek -d e1:00.0 -a 0x5001c -l 1
./app/build/ami_tool poke -d e1:00.0 -a 0x5001c -i 0x10
./app/build/ami_tool peek -d e1:00.0 -a 0x5001c -l 1

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0x10101010
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0x11111111

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0x2020202
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0x2222222

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0x3030303
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0x3333333

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0x40404040
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0x44444444

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0x50505050
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0x55555555

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0x50606060
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0x56666666

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0x70707070
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0x77777777

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0x80808080
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0x88888888

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0x90909090
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0x99999999

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0xa0a0a0a0
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0xaaaaaaaa

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0xb0b0bb0b
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0xbbbbbbbb

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0xc0c0cc0c
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0xcccccccc

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0xd0d0d0d0
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0xdddddddd

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0xe0e0e0e0
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0xeeeeeeee

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0xf0f0f0f0
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0xffffffff

./app/build/ami_tool poke -d e1:00.0 -a 0x50020 -i 0xafafafaf
./app/build/ami_tool poke -d e1:00.0 -a 0x50024 -i 0x00decode

sleep 10
# -----------------------------------------------------------------------------

./app/build/ami_tool peek -d e1:00.0 -a 0x50030 -l 1

for i in {1..16}
do
    ./app/build/ami_tool peek -d e1:00.0 -a 0x5002C -l 2
done

echo "counter of start of packet from tx to rx"
./app/build/ami_tool peek -d e1:00.0 -a 0x50060 -l 2
