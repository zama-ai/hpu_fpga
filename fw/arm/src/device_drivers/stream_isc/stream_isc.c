// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
//
// libraries ---------------------------------------------------------------------------------- //

#include <stdio.h>
#include <stdlib.h>
#include "util.h"
#include "osal.h"
// print and log library
#include "pll.h"
// paramaters from bsp
#include "xparameters.h"

#include "profile_hal.h"

/* Writing to ISC ---------------------------------------------------------------------------------
 *
 * this function is meant to write to Xilinx's IP "AXI STREAM FIFO" in order to send Nxwords to the
 * instruction scheduler via axi stream
 *
 * we can as well send an unique word
 *
 * In order to send a transaction properly, we need to write to some predefined registers in the IP.
 *      1 - clear Interrupt Status Register (ISR)
 *      2 - write to Transmit Destination Register (TDR)
 *      3 - check if there is enough space in FIFO by reading Transmit data FIFO Vacancy (TDFV)
 *      4 - exit with iStatus RETRY if not
 *      5 - send payload to Transmit Data Fifo (TDFD)
 *      6 - trigger a write
 *
 * https://docs.amd.com/v/u/en-US/ds806_axi_fifo_mm_s
 *
 */
int write_isc(uint32_t *pucData, uint32_t writeSize) {
    int iStatus = OK;
    int nb_words = writeSize/4;
    uint32_t tdfv_val = 0;

    //PLL_LOG("AMC:write_isc", "nb_words  %d, writeSize %d", nb_words, writeSize);

    *( ( volatile uint32_t * )(XPAR_AXI_FIFO_0_BASEADDR + 0x0) ) = 0xFFFFFFFF;
    *( ( volatile uint32_t * )(XPAR_AXI_FIFO_0_BASEADDR + 0x2C) ) = 0x2;
    // read available words
    tdfv_val = * (volatile uint32_t *) (XPAR_AXI_FIFO_0_BASEADDR + 0xC);
    //PLL_LOG("AMC:write_isc", "tdfv %d", tdfv_val);
    if (tdfv_val < nb_words) {
        //PLL_WRN("AMC:write_isc", "cannot write %d words, only %d available in axis fifo", nb_words, tdfv_val);
        iStatus = RETRY;
        return iStatus;
    }

    if (nb_words == 1) {
        PLL_LOG("AMC:write_isc", "writing only one word : %x", *pucData);
        *( ( volatile uint32_t * )(XPAR_AXI_FIFO_0_BASEADDR + 0x10) ) = *pucData;
    } else {
        for (int i=0; i < nb_words; i++) {
            //if (i%128==0)
            //    PLL_LOG("AMC:write_isc", "i=%d writing %x", i, *(pucData+i));
            *( ( volatile uint32_t * )(XPAR_AXI_FIFO_0_BASEADDR + 0x10) ) = *(pucData+i);
        }
    }

    // trigger a write stating how much data must be sent
    *( ( volatile uint32_t * )(XPAR_AXI_FIFO_0_BASEADDR + 0x14) ) = 4*nb_words;

    return iStatus;
}

void flush_dop_buffer_to_isc(uint32_t *dop_buffer, int number_of_dop) {
    uint32_t write_isc_rv = OK;
    //PLL_DBG("UCORE", "trying to flush %d dop to isc", number_of_dop);
    //PLL_ERR("UCORE", "dop_buffer %08x %08x %08x ... %08x %08x %08x",dop_buffer[0], dop_buffer[1], dop_buffer[2], dop_buffer[number_of_dop-2], dop_buffer[number_of_dop-1], dop_buffer[number_of_dop]);
    write_isc_rv = write_isc(dop_buffer, (uint32_t) (number_of_dop * sizeof(uint32_t)));
    while (write_isc_rv == RETRY) {
        //PLL_DBG("UCORE", "retry flush %d value to isc", number_of_dop);
        iOSAL_Task_SleepTicks(20);
        write_isc_rv = write_isc(dop_buffer, (uint32_t) (number_of_dop * sizeof(uint32_t)));
    }
}

/* Checking if acknowledge AXIS is not empty ------------------------------------------------------
 *
 * this function is meant to get the number of available words in the ack stream FIFO
 * to do this it reads Receive data FIFO Occupancy (RDFO) register
 * it returns the number of available words (0 if none)
 *
 */
int read_isc_ack_cnt(void) {
    uint32_t isc_ack_cnt = * (volatile uint32_t *) (XPAR_AXI_FIFO_0_BASEADDR + 0x1c);
    return isc_ack_cnt;
}

/* Pop an Ack from AXIs ---------------------------------------------------------------------------
 *
 * This function returns an IOpAck from AxisStream, or 0 in case of empty stream
 */
uint32_t pop_isc_ack() {
    uint32_t iop_ack = 0;
    int available_word = read_isc_ack_cnt();

    if (available_word > 0) {
        iop_ack = * (volatile uint32_t *) (XPAR_AXI_FIFO_0_BASEADDR + 0x20);
    }
    // available_word is here only for debug and has no fct consequences
    // the LSB of the SYNC DOp are used so it is ok to use the lower 8b for debug
    return (iop_ack | (available_word & 0xFF));
}
