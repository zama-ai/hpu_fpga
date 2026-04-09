CC = gcc
CFLAGS = -Wall -O0 -Wno-packed-bitfield-compat -Wno-format-extra-args -DUCORE_MHDMA_SIMU
TARGET = mhdma_fw
INCLUDES = -I ../../profiles/v80/ -I ../../device_drivers/eeprom/ -I ../../common/include/ -I ../../../amc_bsp/psv_cortexr5_0/freertos10_xilinx_domain/bsp/psv_cortexr5_0/include/ -I mhdma_driver/

all: $(TARGET)

$(TARGET): ./mhdma_driver/main.c ./mhdma_driver/mhdma_driver.c ucore.c
	$(CC) $(CFLAGS) -o $(TARGET) $(INCLUDES) ./mhdma_driver/main.c ./mhdma_driver/mhdma_driver.c ucore.c

test33: $(TARGET)
	./mhdma_fw tests/iop33.hex tests/iop33_dop0.hex 0 &
	./mhdma_fw tests/iop33.hex tests/iop33_dop1.hex 1 &
	. ./tests/start.bash

test32: $(TARGET)
	./mhdma_fw tests/iop32.hex tests/iop32_dop0.hex 0 &
	./mhdma_fw tests/iop32.hex tests/iop32_dop1.hex 1 &
	. ./tests/start.bash


clean:
	rm -f $(TARGET)
