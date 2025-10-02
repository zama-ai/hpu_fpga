echo "RX to TX board"
./app/build/ami_tool poke -d a1:00.0 -a 0x50010 -i 0x80000000
#  GT conf - near end pcs lane0
./app/build/ami_tool poke -d a1:00.0 -a 0x50010 -i 0x20000000

# Reset all ports
./app/build/ami_tool poke -d a1:00.0 -a 0x40004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d a1:00.0 -a 0x41004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d a1:00.0 -a 0x42004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d a1:00.0 -a 0x43004 -i 0xFFFFFFFF

# mode 25Ge port 0
# (Narrow mode - 40-bit GT interface, Independent 64b - 390.625 MHz, 25GE data rate)
./app/build/ami_tool poke -d a1:00.0 -a 0x41008 -i 0x40000221

# (Check preamble, Check start frame delimiter, FCS removal enabled, Enable RX)
./app/build/ami_tool poke -d a1:00.0 -a 0x40010 -i 0x00000003

# (IPG = 12 bytes,  FCS insertion enabled, No local fault, No remote fault, Enable TX)
./app/build/ami_tool poke -d a1:00.0 -a 0x4000C -i 0x00000c03

# (No FEC)
./app/build/ami_tool poke -d a1:00.0 -a 0x400D0 -i 0x00000000

# mode 25Ge port 1
./app/build/ami_tool poke -d a1:00.0 -a 0x41008 -i 0x40000221
./app/build/ami_tool poke -d a1:00.0 -a 0x41010 -i 0x00000033
./app/build/ami_tool poke -d a1:00.0 -a 0x4100C -i 0x00000C01
./app/build/ami_tool poke -d a1:00.0 -a 0x410D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d a1:00.0 -a 0x42008 -i 0x40000221
./app/build/ami_tool poke -d a1:00.0 -a 0x42010 -i 0x00000033
./app/build/ami_tool poke -d a1:00.0 -a 0x4200C -i 0x00000C03
./app/build/ami_tool poke -d a1:00.0 -a 0x420D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d a1:00.0 -a 0x43008 -i 0x40000221
./app/build/ami_tool poke -d a1:00.0 -a 0x43010 -i 0x00000033
./app/build/ami_tool poke -d a1:00.0 -a 0x4300C -i 0x00000C01
./app/build/ami_tool poke -d a1:00.0 -a 0x430D0 -i 0x0

# tick reg
./app/build/ami_tool poke -d a1:00.0 -a 0x4002c -i 0x1

# de-assert
./app/build/ami_tool poke -d a1:00.0 -a 0x40004 -i 0x0
./app/build/ami_tool poke -d a1:00.0 -a 0x41004 -i 0x0
./app/build/ami_tool poke -d a1:00.0 -a 0x42004 -i 0x0
./app/build/ami_tool poke -d a1:00.0 -a 0x43004 -i 0x0

# Reset from DMA rtl
./app/build/ami_tool poke -d a1:00.0 -a 0x50014 -i 0xFFF
./app/build/ami_tool poke -d a1:00.0 -a 0x50014 -i 0x0
./app/build/ami_tool peek -d a1:00.0 -a 0x50018 -l 1

sleep 1
# -----------------------------------------------------------------------------
