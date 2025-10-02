./app/build/ami_tool poke -d 01:00.0 -a 0x50010 -i 0x80000000
#  GT conf - near end pcs lane0
./app/build/ami_tool poke -d 01:00.0 -a 0x50010 -i 0x00000001
./app/build/ami_tool poke -d 01:00.0 -a 0x50010 -i 0x40000001
sleep 2

# Reset all ports
./app/build/ami_tool poke -d 01:00.0 -a 0x40004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d 01:00.0 -a 0x41004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d 01:00.0 -a 0x42004 -i 0xFFFFFFFF
./app/build/ami_tool poke -d 01:00.0 -a 0x43004 -i 0xFFFFFFFF

# mode 25Ge port 0
# (Narrow mode - 40-bit GT interface, Independent 64b - 390.625 MHz, 25GE data rate)
./app/build/ami_tool poke -d 01:00.0 -a 0x41008 -i 0x40000221

# (Check preamble, Check start frame delimiter, FCS removal enabled, Enable RX)
./app/build/ami_tool poke -d 01:00.0 -a 0x40010 -i 0x00000003

# (IPG = 12 bytes,  FCS insertion enabled, No local fault, No remote fault, Enable TX)
./app/build/ami_tool poke -d 01:00.0 -a 0x4000C -i 0x00000c03

# (No FEC)
./app/build/ami_tool poke -d 01:00.0 -a 0x400D0 -i 0x00000000

# mode 25Ge port 1
./app/build/ami_tool poke -d 01:00.0 -a 0x41008 -i 0x40000221
./app/build/ami_tool poke -d 01:00.0 -a 0x41010 -i 0x00000033
./app/build/ami_tool poke -d 01:00.0 -a 0x4100C -i 0x00000C01
./app/build/ami_tool poke -d 01:00.0 -a 0x410D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d 01:00.0 -a 0x42008 -i 0x40000221
./app/build/ami_tool poke -d 01:00.0 -a 0x42010 -i 0x00000033
./app/build/ami_tool poke -d 01:00.0 -a 0x4200C -i 0x00000C03
./app/build/ami_tool poke -d 01:00.0 -a 0x420D0 -i 0x0

# mode 25Ge port 1
./app/build/ami_tool poke -d 01:00.0 -a 0x43008 -i 0x40000221
./app/build/ami_tool poke -d 01:00.0 -a 0x43010 -i 0x00000033
./app/build/ami_tool poke -d 01:00.0 -a 0x4300C -i 0x00000C01
./app/build/ami_tool poke -d 01:00.0 -a 0x430D0 -i 0x0

# tick reg
./app/build/ami_tool poke -d 01:00.0 -a 0x4002c -i 0x1

# de-assert
./app/build/ami_tool poke -d 01:00.0 -a 0x40004 -i 0x0
./app/build/ami_tool poke -d 01:00.0 -a 0x41004 -i 0x0
./app/build/ami_tool poke -d 01:00.0 -a 0x42004 -i 0x0
./app/build/ami_tool poke -d 01:00.0 -a 0x43004 -i 0x0

# Reset from DMA rtl
./app/build/ami_tool poke -d 01:00.0 -a 0x50014 -i 0xFFF
./app/build/ami_tool poke -d 01:00.0 -a 0x50014 -i 0x0
./app/build/ami_tool peek -d 01:00.0 -a 0x50018 -l 1

sleep 1
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Push ethernet frame

# 64 words
./app/build/ami_tool peek -d 01:00.0 -a 0x5001c -l 1
./app/build/ami_tool poke -d 01:00.0 -a 0x5001c -i 0x40
./app/build/ami_tool peek -d 01:00.0 -a 0x5001c -l 1

./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x3af95fbb
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x509b1a0f
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x7feac6e6
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x5fee3038
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x5d1f3be5
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xf8416527
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x01f6df8c
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x2ee0b7ce
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x9de81ad2
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x914967b2
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xcc34b8cb
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x5fc39d73
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xba29c04c
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x5203e753
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x07a803fe
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xb9cb1d07
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x4b3e5ab8
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xa1f11148
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xee45b184
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x54ec1dc7
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xb8e30220
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xdaece3a4
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x8e5f98ec
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xa7a8a986
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x029b7d8e
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x5acfc984
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x9f8cc44d
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xeb6934db
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xa5eb0c96
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xa2ec87f5
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xb589829a
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x25afee7b
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x0701fcb2
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x4a725f5b
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x7d983d01
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xfe796e32
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xda6a700c
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x07ccfc91
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x99894205
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xedb9442f
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xf6a244c7
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x45fd3f8c
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x1cc597fc
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x5d15ca79
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x054e8f0b
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x13af022d
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xda3ab15a
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x5cbe31d6
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x339d0608
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xdb6c846a
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x8aae5f33
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x49035eca
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x0b94247a
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x7a06e3ff
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xc99b3bf7
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xca3ff7d8
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xb7d9964d
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xba9dff48
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xd096efb2
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x96849a5f
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xcc322054
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x49035eca
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x0b94247a

./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x3af95fbb
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x509b1a0f
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x7feac6e6
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x5fee3038
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x5d1f3be5
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xf8416527
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x01f6df8c
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x2ee0b7ce
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x9de81ad2
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x914967b2
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xcc34b8cb
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x5fc39d73
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xba29c04c
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x5203e753
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x07a803fe
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xb9cb1d07
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x4b3e5ab8
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xa1f11148
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xee45b184
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x54ec1dc7
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xb8e30220
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xdaece3a4
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x8e5f98ec
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xa7a8a986
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x029b7d8e
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x5acfc984
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x9f8cc44d
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xeb6934db
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xa5eb0c96
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xa2ec87f5
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xb589829a
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x25afee7b
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x0701fcb2
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x4a725f5b
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x7d983d01
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xfe796e32
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xda6a700c
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x07ccfc91
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x99894205
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xedb9442f
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xf6a244c7
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x45fd3f8c
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x1cc597fc
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x5d15ca79
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x054e8f0b
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x13af022d
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xda3ab15a
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x5cbe31d6
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x339d0608
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xdb6c846a
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x8aae5f33
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x49035eca
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x0b94247a
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x7a06e3ff
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xc99b3bf7
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xca3ff7d8
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xb7d9964d
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0xba9dff48
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xd096efb2
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x96849a5f
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0xcc322054
./app/build/ami_tool poke -d 01:00.0 -a 0x50024 -i 0x49035eca
./app/build/ami_tool poke -d 01:00.0 -a 0x50020 -i 0x0b94247a


sleep 3
echo "stop"
./app/build/ami_tool poke -d 01:00.0 -a 0x50010 -i 0x0

# -----------------------------------------------------------------------------

./app/build/ami_tool peek -d 01:00.0 -a 0x50030 -l 1
for i in {1..64}
do
    ./app/build/ami_tool peek -d 01:00.0 -a 0x5002C -l 2
done



echo "how many clock cycles passed by ?"
./app/build/ami_tool peek -d 01:00.0 -a 0x50050 -l 2

echo "how many valid values had been returned ?"
./app/build/ami_tool peek -d 01:00.0 -a 0x50058 -l 2


# # empting fifo
for i in {1..512}
do
    ./app/build/ami_tool peek -d 01:00.0 -a 0x5002C -l 2
done

