# FAQ

## Table of Contents

- [HPU usage with TFHE-rs](#hpu-usage)
  - [How can I run the TFHE-rs code example?](#run-hpu-example)
  - [How can I run regression tests?](#run-regression)
  - [How can I run benchmarks?](#run-benchmarks)
- [General card usage](#card-usage)
  - [How can I load a freshly compiled arm firmware?](#load-board)
  - [How do I run board diagnostics?](#diag)
- [Debug](#debug)
  - [How can I read internal HPU registers?](#hpu-register)
  - [How can I change the debug level of the firmware?](#debug-level)
  - [How do I reset the board?](#reset)
- [Common issues](#common-issues)
  - [My board seems inaccessible. What should I do?](#board-away)
    - [check if the device is correctly listed on the PCIe bus](#pcie-check)
    - [Use xsdb](#xsdb)
        - [Check SOC status](#soc-status)
        - [JTAG status](#jtag-status)
        - [Device status](#device-status)
  - [The board is in ```COMPAT``` mode, what to do?](#compat)
  - [When I do an ```ami_tool overview```, nothing is displayed. What should I do?](#overview)
  - [During boot, I see ```[AMC] iEEPROM_Initialised FAILED```. What should I do?](#eeprom)

<a id="hpu-usage"></a>
## HPU usage with TFHE-rs
<a id="run-hpu-example"></a>
### How can I run the TFHE-rs code example?

The HPU can be controlled directly by the rust library [TFHE-rs](https://github.com/zama-ai/tfhe-rs/configuration/run_on_hpu) starting from version v1.2.
One example is located  in ```tfhe/examples/hpu/matmul.rs```.

```
git clone https://github.com/zama-ai/tfhe-rs.git
cd  tfhe-rs
source setup_hpu.sh --config v80 --init-qdma
cargo run --profile devo --features=hpu-v80 --example hpu_matmul
```

For faster build time, when developing, it is recommended to use the profile ```devo```.

<a id="run-regression"></a>
### How can I run regression tests?
```
cargo test --release --features hpu-v80 --test hpu
```

<a id="run-benchmarks"></a>
### How can I run benchmarks?

```
make bench_integer_hpu
```
or
```
RUSTFLAGS="-C target-cpu=native" __TFHE_RS_BENCH_OP_FLAVOR=DEFAULT __TFHE_RS_FAST_BENCH=FALSE __TFHE_RS_BENCH_TYPE=latency \
cargo bench --bench integer-bench --features=integer,internal-keycache,pbs-stats,hpu,hpu-v80 -p tfhe-benchmark -- --quick
```

<a id="card-usage"></a>
## General card usage
<a id="load-arm"></a>
### How can I load a freshly compiled arm firmware?


> [!WARNING]
> [Vivado](https://www.xilinx.com/support/download.html) must be installed on the machine and JTAG connected from host to the board (USB cable).

Let's say you made modifications in the firmware ```fw/arm``` and want to use the compiled elf on board.

```
source setup.sh
cd versal
just compile_fw
# firmware will be located in versal/output/amc.elf
xsdb
connect
ta 3
dow versal/output/amc.elf
rst -proc
con
```
<a id="diag"></a>
### How do I run board diagnostics?

In order to run card diagnostics, you must install [xbtest](https://xilinx.github.io/AVED/amd_v80_gen5x8_exdes_2_20240408/xbtest/user-guide/source/docs/introduction/installation.html) and have an example AVED bitstream loaded into FPGA.

> [!TIP]
> Depending on your AVED bitstream version, you should checkout original AVED repository, git tag ```7497599``` for version 2.3 and ```b580f84``` for 2.2.

Once done, compile the driver and load the ami module.

```
git clone git@github.com:Xilinx/AVED.git
cd AVED
git checkout b580f84 #AMC version 2.2
cd sw/AMI/driver/
make clean && make
sudo modprobe -r ami && sudo insmod ami.ko
```

If you want to launch memory diagnostics you can do :
```
# Get pcie device number
PCIE_CARD=$(lspci -d 10ee:50b4)
DEVICE="${PCIE_CARD%% *}"

xbtest -d $DEVICE -c memory
```
<p align="right">
  <a href="#table-of-contents" > ↑ Back to top </a>
</p>

## Debug

The variable ```$DEVICE``` corresponds to your board *Bus Device Function*. You can easily find yours with ```lspci -d 10ee:50b4```.

<a id="hpu-register"></a>
### How can I read internal HPU registers?

You can read internal registers with HPUtils in TFHE-rs.\
In order to build it you can launch: ```cargo build --profile devo --features=hpu-v80,utils --bin hputil```

Then you can read registers with this tool.

```
source setup_hpu.sh --config v80 --init-qdma
./target/devo/hputil read --name info::version
```

You can as well dump sets of parameters read in the HPU:
```
./target/devo/hputil dump arch    // dumps crypto parameter set and HPU parameters
./target/devo/hputil dump isc     // dumps Instruction Scheduler registers
./target/devo/hputil dump pe-mem  // dumps Load/Store processing element registers
./target/devo/hputil dump pe-pbs  // dumps PBS processing element registers
./target/devo/hputil dump pe-alu  // dumps ALU processing element registers
```

<a id="debug-level"></a>
### How can I change the debug level of the firmware?

The same way as is instructed by Xlilinx: ```sudo ami_tool debug_verbosity -d $DEVICE -l debug```.

It will allow you to see more messages published by the firmware running on the ARM core (RPU). By default you will see only the errors.

<a id="reset"></a>
### How do I reset the board?

> [!WARNING]
> If you loaded the FPGA through JTAG, this solution will not work.

We currently don't have a general reset. To circumvent this you can do a "reload -sbr".

*This command will trigger the secondary bus reset, effectively resetting parts of the control of the FPGA and then will entirely reload the FPGA matrix with what is in the FLASH. This uses the current partition.*

```
sudo ami_tool reload -d $DEVICE -t sbr
```
<p align="right">
  <a href="#table-of-contents" > ↑ Back to top </a>
</p>

## Common issues
<a id="board-away"></a>
### My board seems inaccessible. What should I do?

<a id="pcie-check"></a>
#### 1. check if the device is correctly listed on the PCIe bus:

```
lspci -d 10ee:50b4
lspci -d 10ee:50b5
```

The Bus Device Function of Xilinx V80 board has this form ```0X:00.Y```.\
*X can be a different number, server to server. Y can only be (0;1): we only have two Physical Functions.*

You must find with previous command:
```
0X:00.0 Processing accelerators: Xilinx Corporation Device 50b4
0X:00.1 Processing accelerators: Xilinx Corporation Device 50b5
```

If ever this is not the case, you can try to **remove** and **rescan** the **two** physical functions.

```
sudo bash -c "echo 1 > /sys/bus/pci/devices/0000:{DEVICE}:00.0/remove"
sudo bash -c "echo 1 > /sys/bus/pci/devices/0000:{DEVICE}:00.1/remove"
sudo bash -c "echo 1 > /sys/bus/pci/rescan"
```

If after this you still cannot find the device, we would suggest you to do a **cold reboot**.

<a id="xsdb"></a>
#### 2: Use xsdb.

> [!WARNING]
> JTAG must be plugged.

*xsdb will allow you to have some information about the current status of the System On Chip (SOC). Including processors, FPGA and PMC.*

```
xsdb
connect
ta
```

You should see the processor RPU as ```3  Cortex-R5 #0 (Running)```.


If you cannot connect : check that ```Future Technology Devices International``` is present when doing ```lsusb```.\
This is not the case: JTAG is unplugged or has an issue.

<a id="soc-status"></a>
#### 2.1: Check SOC status.

<a id="jtag-status"></a>
#### 2.1.1: JTAG status
```
xsdb
connect
ta 1
device status jtag_status
```

If the Done bit is ‘0’: FPGA has not been properly programmed. You will certainly need to re-program.

If something is suspect you can have a look at [this documentation](https://docs.amd.com/r/2021.1-English/ug1388-acap-system-integration-validation-methodology/Debugging-the-PS/PMC).


> [!NOTE]
> boot mode should be ‘b1000 or ‘b0100\
> boot mode 1000 means boot mode is **OSPI**: you will be able to boot from flash\
> boot mode 0100 means boot mode is **JTAG**: you will be able to boot from JTAG\
>     - If ever you need to boot from the flash (OSPI), do `xsdb versal/jtag/write_ospi_mode.tcl`

<a id="device-status"></a>
#### 2.1.2: Device status
```
xsdb
connect
ta 1
device status -hex error_status
```

All output should be zeros, if something is up (this can happen with a functional bitstream), you can have a look there to get the bit signification in [this documentation](https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/2037088327/Versal+Platform+Loader+and+Manager#Debugging-Tips).


> [!NOTE]
> We noticed that ```GSW ERROR``` can be raised with a working bitstream.\
> ```NOC NCR``` already happened during development, this is likely a big issue you introduced in the block design.

<a id="compat"></a>
### The board is in ```COMPAT``` mode, what to do?

This means that there is an incompatibility between software/firmware versions.
This is likely due to the version of your [ami](https://github.com/zama-ai/AVED). Its major version number is probably not matching the AMC firmware major version. We modified the version of both pieces of software.

*simply compile and load the new ami module*
```
git clone https://github.com/zama-ai/AVED.git
cd sw/AMI/driver
make
sudo modprobe -r ami && sudo insmod ami.ko
```

<a id="overview"></a>
### When I do an ```ami_tool overview```, nothing is displayed. What should I do?

This is likely that your software is not properly synchronized between app/api and driver. This is common when having several users on a machine.

You can circumvent this by using the relative path of the application. Make sure to recompile and reload the driver beforehand.

<a id="eeprom"></a>
### During boot, I see ```[AMC] iEEPROM_Initialised FAILED```. What should I do?

We noticed that on V80, the board's communication with I2C bus can get stuck, leading to being unable to boot the system.\
The solution for now is simple: you need to turn off your machine and unplug it, wait enough for all the power to dissipate and only then replug/reboot your machine ;-)

<p align="right">
  <a href="#table-of-contents" > ↑ Back to top </a>
</p>
