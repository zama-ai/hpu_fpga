# Core configurations

## ucore
Configuration for IOps to DOps translation.

The block design contains the following:
* ublaze_0 (Microcontroller preset)
    * 4 AXI STREAM
    * 1 AXI 4 lite
    * 1 interrupts
* ublaze_0_axi_intc (interrupt handler)
* ublaze_0_xlconcat
* ublaze_0_axi_periph
* rst_clock_100 Mhz (to trigger)
* memory units (infered)

Core clock is configured @250MHz
