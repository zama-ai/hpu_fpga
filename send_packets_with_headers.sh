# reset register
./app/build/ami_tool poke -d 01:00.0 -a 0x51000 -i 0x80000000
# de toggle
./app/build/ami_tool poke -d 01:00.0 -a 0x51000 -i 0x0

#  GT conf - near end pcs lane0
sleep 1

# Reset all ports
./app/build/ami_tool poke -d 01:00.0 -a 0x40004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d 01:00.0 -a 0x41004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d 01:00.0 -a 0x42004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d 01:00.0 -a 0x43004 -i 0xFFFFFFFF

# mode 25Ge port 0
# (Narrow mode - 40-bit GT interface, Independent 64b - 390.625 MHz, 25GE data rate)
# (Check preamble, Check start frame delimiter, FCS removal enabled, Enable RX)
# (IPG = 12 bytes,  FCS insertion enabled, No local fault, No remote fault, Enable TX)
# (No FEC)
./app/build/ami_tool poke -d 01:00.0 -a 0x40008 -i 0x40000221
./app/build/ami_tool poke -d 01:00.0 -a 0x40010 -i 0x00000003
./app/build/ami_tool poke -d 01:00.0 -a 0x4000C -i 0x00000c03
./app/build/ami_tool poke -d 01:00.0 -a 0x400D0 -i 0x00000000

# mode 25Ge port 1
./app/build/ami_tool poke -d 01:00.0 -a 0x41008 -i 0x40000221
./app/build/ami_tool poke -d 01:00.0 -a 0x41010 -i 0x00000003
./app/build/ami_tool poke -d 01:00.0 -a 0x4100C -i 0x00000c03
./app/build/ami_tool poke -d 01:00.0 -a 0x410D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d 01:00.0 -a 0x42008 -i 0x40000221
./app/build/ami_tool poke -d 01:00.0 -a 0x42010 -i 0x00000003
./app/build/ami_tool poke -d 01:00.0 -a 0x4200C -i 0x00000C03
./app/build/ami_tool poke -d 01:00.0 -a 0x420D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d 01:00.0 -a 0x43008 -i 0x40000221
./app/build/ami_tool poke -d 01:00.0 -a 0x43010 -i 0x00000003
./app/build/ami_tool poke -d 01:00.0 -a 0x4300C -i 0x00000c03
./app/build/ami_tool poke -d 01:00.0 -a 0x430D0 -i 0x0

# de-assert
./app/build/ami_tool poke -d 01:00.0 -a 0x40004 -i 0x0
./app/build/ami_tool poke -d 01:00.0 -a 0x41004 -i 0x0
./app/build/ami_tool poke -d 01:00.0 -a 0x42004 -i 0x0
./app/build/ami_tool poke -d 01:00.0 -a 0x43004 -i 0x0

# Reset from DMA rtl
./app/build/ami_tool poke -d 01:00.0 -a 0x50014 -i 0xFFF
./app/build/ami_tool poke -d 01:00.0 -a 0x50014 -i 0x0
./app/build/ami_tool peek -d 01:00.0 -a 0x50018 -l 1
# -----------------------------------------------------------------------------
sleep 2

# tick reg
echo "tick register toggle"
./app/build/ami_tool poke -d 01:00.0 -a 0x4002c -i 0x1

# -----------------------------------------------------------------------------
# Push ethernet frame

# 16 words
./app/build/ami_tool peek -d 01:00.0 -a 0x5101c -l 1
./app/build/ami_tool poke -d 01:00.0 -a 0x5101c -i 0x8
./app/build/ami_tool peek -d 01:00.0 -a 0x5101c -l 1

# LSB: Destination MAC bytes 4-5 + Source MAC bytes 0-1
./app/build/ami_tool poke -d 01:00.0 -a 0x51020 -i 0xB240000A
# MSB: Destination MAC bytes 0-3
./app/build/ami_tool poke -d 01:00.0 -a 0x51024 -i 0x000A351F

# MSB: Source MAC bytes 2-5
./app/build/ami_tool poke -d 01:00.0 -a 0x51020 -i 0x0800aaaa
# LSB: EtherType (0x0800 for IPv4) + padding start
./app/build/ami_tool poke -d 01:00.0 -a 0x51024 -i 0x351FB240

# Payload
# Word 2
./app/build/ami_tool poke -d 01:00.0 -a 0x51020 -i 0x1111111a
./app/build/ami_tool poke -d 01:00.0 -a 0x51024 -i 0x1111111b
# Word 3
./app/build/ami_tool poke -d 01:00.0 -a 0x51020 -i 0x2222222a
./app/build/ami_tool poke -d 01:00.0 -a 0x51024 -i 0x2222222b
# Word 4
./app/build/ami_tool poke -d 01:00.0 -a 0x51020 -i 0x3333333a
./app/build/ami_tool poke -d 01:00.0 -a 0x51024 -i 0x3333333b
# Word 5
./app/build/ami_tool poke -d 01:00.0 -a 0x51020 -i 0x4444444a
./app/build/ami_tool poke -d 01:00.0 -a 0x51024 -i 0x4444444b
# Word 6
./app/build/ami_tool poke -d 01:00.0 -a 0x51020 -i 0x5555555a
./app/build/ami_tool poke -d 01:00.0 -a 0x51024 -i 0x5555555b
# Word 7 (final - may need special signaling for frame end)
./app/build/ami_tool poke -d 01:00.0 -a 0x51020 -i 0x6666666a
./app/build/ami_tool poke -d 01:00.0 -a 0x51024 -i 0x6666666b

# -----------------------------------------------------------------------------
sleep 1
for i in {0..8}
do
    ./app/build/ami_tool peek -d 01:00.0 -a 0x5102C -l 2
done

# tick reg
echo "tick register toggle"
./app/build/ami_tool poke -d 01:00.0 -a 0x4002c -i 0x1

echo "total tx packet"
echo "total tx good packets"
./app/build/ami_tool peek -d 01:00.0 -a 0x40818 -l 2
./app/build/ami_tool peek -d 01:00.0 -a 0x40820 -l 2
echo "total tx total bytes"
./app/build/ami_tool peek -d 01:00.0 -a 0x40828 -l 2
echo "total tx total good bytes"
./app/build/ami_tool peek -d 01:00.0 -a 0x40830 -l 2


./app/build/ami_tool peek -d 01:00.0 -a 0x5103C -l 3

./app/build/ami_tool peek -d 01:00.0 -a 0x40e40 -l 2
./app/build/ami_tool peek -d 01:00.0 -a 0x40e48 -l 2
