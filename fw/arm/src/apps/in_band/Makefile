CC = gcc
CFLAGS = -Wall -O0 -Wno-packed-bitfield-compat -Wno-format-extra-args
TARGET = mhdma_fw
INCLUDES = -I ../../profiles/v80/ -I ../../device_drivers/eeprom/ -I ../../common/include/ -I ../../../amc_bsp/psv_cortexr5_0/freertos10_xilinx_domain/bsp/psv_cortexr5_0/include/

all: $(TARGET)

$(TARGET): ./mhdma_driver/main.c ucore.c
	$(CC) $(CFLAGS) -o $(TARGET) $(INCLUDES) ./mhdma_driver/main.c ucore.c

clean:
	rm -f $(TARGET)
