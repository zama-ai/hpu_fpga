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

    PLL_LOG("AMC:write_isc", "nb_words  %d, writeSize %d", nb_words, writeSize);

    *( ( volatile uint32_t * )(XPAR_AXI_FIFO_0_BASEADDR + 0x0) ) = 0xFFFFFFFF;
    *( ( volatile uint32_t * )(XPAR_AXI_FIFO_0_BASEADDR + 0x2C) ) = 0x2;
    // read available words
    tdfv_val = * (volatile uint32_t *) (XPAR_AXI_FIFO_0_BASEADDR + 0xC);
    PLL_LOG("AMC:write_isc", "tdfv %d", tdfv_val);
    if (tdfv_val < nb_words) {
        PLL_WRN("AMC:write_isc", "cannot write %d words, only %d available in axis fifo", nb_words, tdfv_val);
        iStatus = RETRY;
        return iStatus;
    }

    if (nb_words == 1) {
        PLL_LOG("AMC:write_isc", "writing only one word : %x", *pucData);
        *( ( volatile uint32_t * )(XPAR_AXI_FIFO_0_BASEADDR + 0x10) ) = *pucData;
    } else {
        for (int i=0; i < nb_words; i++) {
            if (i%128==0)
                PLL_LOG("AMC:write_isc", "i=%d writing %x", i, *(pucData+i));
            *( ( volatile uint32_t * )(XPAR_AXI_FIFO_0_BASEADDR + 0x10) ) = *(pucData+i);
        }
    }

    // trigger a write stating how much data must be sent
    *( ( volatile uint32_t * )(XPAR_AXI_FIFO_0_BASEADDR + 0x14) ) = 4*nb_words;

    return iStatus;
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
 * This function retur an IOpAck from AxisStream, return 0 in case of empty stream
 */
uint32_t pop_isc_ack() {
    uint32_t  iop_ack = 0;

    if (read_isc_ack_cnt() == 0) {
        PLL_ERR("AMC:read_isc", "cannot read fifo data right now RDFO is 0");
    } else {
        iop_ack = * (volatile uint32_t *) (XPAR_AXI_FIFO_0_BASEADDR + 0x20);
        PLL_INF("AMC:isc", "Read IOpAck %d from the isc axis.", iop_ack);
    }
    return iop_ack;
}
