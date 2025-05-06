// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
//
// Writing to ISC ---------------------------------------------------------------------------------
//
//  this function is meant to write to Xilinx's IP "AXI STREAM FIFO" in order to send Nxwords to the
//  instruction scheduler via axi stream
//
//  we can as well send an unique word
//
//  In order to send a transaction properly, we need to write to some predefined registers in the IP.
//       1 - clear Interrupt Status Register (ISR)
//       2 - write to Transmit Destination Register (TDR)
//       3 - check if there is enough space in FIFO by reading Transmit data FIFO Vacancy (TDFV)
//       4 - exit with iStatus RETRY if not
//       5 - send payload to Transmit Data Fifo (TDFD)
//       6 - trigger a write
//
//  https://docs.amd.com/v/u/en-US/ds806_axi_fifo_mm_s

int write_isc(uint32_t *pucData, uint32_t Write_Size);

/* Pop an Ack from AXIs ---------------------------------------------------------------------------
 *
 * This function retur an IOpAck from AxisStream, return 0 in case of empty stream
 */
uint32_t pop_isc_ack();

/* Checking if acknowledge AXIS is not empty ------------------------------------------------------
 *
 * this function is meant to get the number of available words in the ack stream FIFO
 * to do this it reads Receive data FIFO Occupancy (RDFO) register
 * it returns the number of available words (0 if none)
 *
 */
int read_isc_ack_cnt(void);
