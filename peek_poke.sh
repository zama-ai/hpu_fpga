#  GT conf - near end pcs lane0
./app/build/ami_tool poke -d 24:00.0 -a 0x60010 -i 0x10

# Reset all ports
./app/build/ami_tool poke -d 24:00.0 -a 0x40004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d 24:00.0 -a 0x41004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d 24:00.0 -a 0x42004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d 24:00.0 -a 0x43004 -i 0xFFFFFFFF

# mode 25Ge port 0
./app/build/ami_tool poke -d 24:00.0 -a 0x40008 -i 0x40000240
#  ctl tx igp - FCS - Port tx enable
./app/build/ami_tool poke -d 24:00.0 -a 0x4000C -i 0x00000C03
# FCS no check
./app/build/ami_tool poke -d 24:00.0 -a 0x40010 -i 0x00000033
# no fec
./app/build/ami_tool poke -d 24:00.0 -a 0x400D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d 24:00.0 -a 0x41008 -i 0x40000240
./app/build/ami_tool poke -d 24:00.0 -a 0x4100C -i 0x00000C03
./app/build/ami_tool poke -d 24:00.0 -a 0x41010 -i 0x00000033
./app/build/ami_tool poke -d 24:00.0 -a 0x410D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d 24:00.0 -a 0x42008 -i 0x40000240
./app/build/ami_tool poke -d 24:00.0 -a 0x4200C -i 0x00000C03
./app/build/ami_tool poke -d 24:00.0 -a 0x42010 -i 0x00000033
./app/build/ami_tool poke -d 24:00.0 -a 0x420D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d 24:00.0 -a 0x43008 -i 0x40000240
./app/build/ami_tool poke -d 24:00.0 -a 0x4300C -i 0x00000C03
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

# -----------------------------------------------------------------------------
# Push ethernet frame
# init IP
./app/build/ami_tool poke -d 24:00.0 -a 0x50000 -i 0xFFFFFFFFF
./app/build/ami_tool poke -d 24:00.0 -a 0x50008 -i 0x000000A5
./app/build/ami_tool peek -d 24:00.0 -a 0x50000 -l 1
./app/build/ami_tool poke -d 24:00.0 -a 0x50004 -i 0x0C000000
./app/build/ami_tool poke -d 24:00.0 -a 0x5002C -i 0x2
./app/build/ami_tool peek -d 24:00.0 -a 0x5000C -l 1
# Write frame 64-bytes
./app/build/ami_tool poke -d 24:00.0 -a 0x70000 -i 0x01234567
./app/build/ami_tool poke -d 24:00.0 -a 0x70000 -i 0x01234567
./app/build/ami_tool poke -d 24:00.0 -a 0x70000 -i 0x01234567
./app/build/ami_tool poke -d 24:00.0 -a 0x70000 -i 0x01234567
./app/build/ami_tool poke -d 24:00.0 -a 0x70000 -i 0x01234567
./app/build/ami_tool poke -d 24:00.0 -a 0x70000 -i 0x01234567
./app/build/ami_tool poke -d 24:00.0 -a 0x70000 -i 0x01234567
./app/build/ami_tool poke -d 24:00.0 -a 0x70000 -i 0x01234567
./app/build/ami_tool peek -d 24:00.0 -a 0x5000C -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x50000 -l 1
# trigger 4x nb_word
./app/build/ami_tool poke -d 24:00.0 -a 0x50014 -i 0x40
./app/build/ami_tool peek -d 24:00.0 -a 0x5000C -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x50000 -l 1

# TX status
./app/build/ami_tool peek -d 24:00.0 -a 0x40740 -l 1

# -----------------------------------------------------------------------------
# READ ethernet frame
./app/build/ami_tool peek -d 24:00.0 -a 0x5001C -l 1
./app/build/ami_tool peek -d 24:00.0 -a 0x71000 -l 1

# -----------------------------------------------------------------------------
# debug
# RX status
./app/build/ami_tool peek -d 24:00.0 -a 0x40744 -l 1







