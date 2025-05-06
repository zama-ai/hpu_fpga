# HPU FPGA

## Introduction

SystemVerilog implementation of the [Homomorphic Processing Unit (HPU)](/docs/hpu.md) targeting [AMD Alveo V80](https://www.amd.com/en/products/accelerators/alveo/v80.html) FPGA board.

This repository includes:

* the RTL sources in SystemVerilog
* the block design necessary for AMD FPGA designs.
    * The block design, defining the CIPS and the card management configuration, is partly derived from AVED. See [block design code](versal/scripts/bd)).
* the flow for the FPGA V80 bitstream generation
* the flow for the simulation
* the firmware code for the Real-Time Processing Unit (RPU)
    * The firmware is derived from [Xilinx's AVED](https://github.com/Xilinx/AVED). See [firmware documentation](fw/arm/README.md).

> [!Tip]
> HPU also needs the following piece of software:
>
> * AMI driver can be found [here](https://github.com/zama-ai/AVED).
> * The high level API can be found [here](https://github.com/zama-ai/tfhe-rs)
> * The HPU register interface is generated using the tool [regmap](https://github.com/zama-ai/hw_regmap). It is loaded in HPU FPGA project as a git submodule.



## Directory structure
At the root of HPU FPGA project, you will find the following directories:

* docs
    * Markdown documentation.
* fw
    * Firmware code for the RPU or microblaze.
    * Flow necessary for the ublaze generation.
* hw
    * RTL code and the simulation flow.
* sw
    * Python models for some algorithms.
    * register map generator: regmap.
* versal
    * Flow for block design and bitstream generation.

<br>
In **hw** the general directory hierarchy is the following:

* common_lib
    * Shared RTL library, organized in <RTL module\> hierarchy.
* memory_file
    * ROM content files.
* module
    * HPU RTL, organized in <RTL module\> hierarchy.
* syn
    * Scripts for synthesis.
* scripts
    * Miscellaneous scripts.
* simu_lib
    * Shared RTL library for simulation.
* output
    * Generated directory.
    * Simulation and out-of-context (ooc) synthesis results.


<br>
An **RTL module** directory has the following general hierarchy.<br>
Note that if any directory is not needed, it won't be present.

* <module_name\>
    * info
        * Mainly contains ***file_list.json***, which lists the RTL files of this directory, the RTL dependencies and synthesis constraints of this module.
    * rtl
        * RTL files. The file name corresponds to the module name.
    * constraints
        * Synthesis files for local ooc synthesis (with ***_local*** suffix), and hierarchical synthesis if needed (with ***_hier*** suffix).
    * simu
        * Simulation files. Is organized as a regular "RTL module" structure. See [below](#simulation).
    * module
        * If the module's submodules need to be placed in a "RTL module" structure, it is done under the *module* directory.
    * scripts
        * Scripts necessary to generate the module.


## Getting started

### Installation

HPU FPGA project needs the following:

- bash : All the commands are run in a **bash** terminal. If not it would be specified.
- [tfhe-rs](https://github.com/zama-ai/tfhe-rs/) >= 1.2.0.
- host linux driver: [AVED fork](https://github.com/zama-ai/AVED).
- DMA linux driver: [QDMA fork](https://github.com/zama-ai/dma_ip_drivers).
- [Vivado/Vitis](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools/2024-2.html) = **2024.2**.
- [just](https://github.com/casey/just) >= 1.37.0.
- *(simulation only)* [Sage](https://sagemanifolds.obspm.fr/install_ubuntu.html) = 10.4.
- Python = 3.12.
    - edalize = [ZAMA fork] used as a submodule (https://github.com/zama-ai/edalize).
    - jinja2.
    - *(simulation only)* constrainedrandom.

> [!CAUTION]
> Linux with kernel version 5.15.0-* is required to compile the host software. ([ami driver](https://github.com/zama-ai/AVED)).


#### Python dependencies
> [!TIP]
> With newer Linux versions, it is recommended to use a virtual environment.

```
# create a virtual environment "my_env"
python -m venv my_venv

# activate it
source my_venv/bin/activate

# install dependencies

# jinja2 is used to use file templates
pip install jinja2

# constrainedrandom is used to generate random parameters in simulation
pip install constrainedrandom

# To exit this environment
deactivate

# Next time, you just need to activate this environment, with:
source my_venv/bin/activate
```

### Setup
Prepare your environment.


Set the bash variables **XILINX_VIVADO_PATH** and **XILINX_VITIS_PATH** with your vivado and vitis installation path.


Clone the HPU repository
```
git clone git@github.com:zama-ai/hpu_fpga

```

Do the following before running any simulation or synthesis. It will set all the variables needed by the project, all the aliases and links.

```
cd hpu_fpga
git submodule update --init
source setup.sh
```

> [!Tip]
> A useful variable that is created: **$PROJECT_DIR**. Its value is the path to the root directory of the current project.


### Build bitstream
Once your environment is [set-up](#setup), run the following commands to get an FPGA bitstream.

```
cd ${PROJECT_DIR}/versal

# /!\ This next task will take hours
./run_syn_hpu_3parts_psi64.sh
```

> [!TIP]
>
> * run_syn_hpu_3parts_psi64.sh
>     * Compile the biggest HPU in which blind rotation processes 128 polynomial coefficients per cycle.
>     * This compilation is likely to take more than 10 hours.
> * run_syn_hpu_3parts_psi32.sh
>     * HPU in which blind rotation processes 64 polynomial coefficients per cycle.
> * run_syn_hpu_3parts_psi16.sh
>     * HPU in which blind rotation processes 32 polynomial coefficients per cycle.
>     * Fastest to compile.


### Simulation

The flow supports 2 simulation tools : ```xsim``` from AMD and ```vcs``` from Synopsys.

Set the variable ```$PROJECT_SIMU_TOOL``` in ```setup.sh``` to "xsim" or "vcs" according to the tool you want to use.

> [!NOTE]
> "vcs" is set by default.

A design under test (DUT) simulation material is in ```simu``` directory. If several testbenches exist, they are stored in separate directories. If a single testbench is present, this directory level does not exist.

Simulation directory minimal content:

simu<br>
|-- info<br>
|-- rtl<br>
'-- scripts<br>

* info : directory containing file_list.json script, used to list the project files at this level.
* rtl : directory containing the testbench RTL.
* scripts : directory containing the scripts necessary to run the simulation.


Each testbench has a ```run_simu.sh``` script inside the directory ```scripts```. This script sets randomly the HDL parameters supported by the DUT. This command is run in our continuous integration (CI).

It is recommended to use run_simu.sh when the testbench is run for the very first time.

The output gives the details of the advanced command to launch, if ever you want to play with the parameters.

Note that if run_simu.sh is not present, the corresponding testbench is not fully supported.


Example: Run pe_alu testbench, pe_alu is the ALU processing element
```
${PROJECT_DIR}/hw/module/pe_alu/simu/scripts/run_simu.sh
```

This command outputs lines similar to the following ones:

```
===========================================================
INFO> Running : ${PROJECT_DIR}/hw/module/pe_alu/simu/scripts/run.sh           -g 2           -R 2           -S 8           -W 64           -q 2**64           -i 48           -j 4           -k 1           -a 4           -Q 4           -D 1           --            -P PEA_PERIOD int 2           -P PEM_PERIOD int 2           -P PEP_PERIOD int 1
===========================================================
${PROJECT_DIR}/hw/module/regfile/constraint/regfile_timing_constraints_hier.xdc has unknown file type 'xdc'
SUCCEED> ${PROJECT_DIR}/hw/module/pe_alu/simu/scripts/run.sh           -g 2           -R 2           -S 8           -W 64           -q 2**64           -i 48           -j 4           -k 1           -a 4           -Q 4           -D 1           --            -P PEA_PERIOD int 2           -P PEM_PERIOD int 2           -P PEP_PERIOD int 1
```

The first line starting with "INFO> Running" gives you the details of the command that is actually launched. This command can be run on its own. All the options are different values of the HDL parameters.

The second line is an edalize output, indicating that an "xdc" files has been given to the simulator, which does not need it.

The third line, created by run_simu.sh, indicates the status of the test : SUCCEED or FAILURE.


#### Simulation with firmware
The V80 FPGA has on-board a dual-core Arm Cortex-R5F (RPU) that executes the firmware code. To accelerate the simulation, we use a microblaze model to run a similar verson of this firmware.

In some simulations, like the top level one, the generation of the microblaze model is needed. So before these simulations, do the following:
```
${PROJECT_DIR}/fw/ublaze/script/generate_core.sh
```



## Bring-up

> [!WARNING]
>
> We assume that the user has already used a V80 board and knows its basic usage.<br>
> We assume that the [flash](https://xilinx.github.io/AVED/latest/AVED%2BUpdating%2BFPT%2BImage%2Bin%2BFlash.html) has already been correctly programmed and the example design [is in partition 0](https://xilinx.github.io/AVED/latest/AVED%2BUpdating%2BDesign%2BPDI%2Bin%2BFlash.html)<br>
> We recommend to use partition 1 for your freshly generated pdi. This will enable you to fallback on partition 0 after a reboot.

> [!WARNING]
>
> Note that we witnessed the following behavior: server reboot after loading of the V80 FPGA from OSPI. The PCIe device disappeared during the boot.<br>
> If your machine **doesn't allow hot plug, your machine will reboot**.<br>
> In this specific scenario, we suggest to program partition 0 in order to reboot your machine with the new pdi.<br>
>
> In the case you corrupt the flash inadvertently, plug USB/JTAG and reprogram it.<br>
> Use script ```cd versal && just rewrite_flash ``` or follow [AMD tutorial](https://xilinx.github.io/AVED/latest/AVED%2BUpdating%2BFPT%2BImage%2Bin%2BFlash.html).

To control the board and use ```TFHE-rs' tfhe-hpu-backend```, install both AMI (AVED Management Interface - driver and tool) and QDMA driver.


### AMI driver
The AMI software, adapted for HPU, is available in a [git fork](https://github.com/zama-ai/AVED) from XILINX AVED example design.

AMI driver compilation requires usage of a specific Linux kernel version (5.15.0-*), Linux kernel sources and DKMS.


#### Driver installation
```
git clone git@github.com:zama-ai/AVED.git zama_aved

./zama_aved/sw/AMI/scripts/gen_package.py
cd zama_aved/sw/AMI/scripts/output/<timestamp>/
sudo apt install ./ami_xxx.deb
```
Now ```ami_tool``` is available.



#### How to use ami_tool

Through few examples:
```
# Get pcie device number
PCIE_CARD=$(lspci -d 10ee:50b4)
DEVICE="${PCIE_CARD%% *}"


# Check that the device is visible with a "READY" state
sudo ami_tool overview

# Read 8 first registers from HPU at address 0
ami_tool peek -d $DEVICE -a 0x0 -l 8

# Reset the board and reload fpga (triggers a hot plug)
sudo ami_tool reload -d $DEVICE -t sbr
```

It is recommended to use app and API from the Zama modified AVED repository.

With this version, on reset, the rescan on the two PCIe physical functions is launched. You will also have access to new commands and guardrails to avoid accidental mistakes.

### QDMA
We are using AMD [QDMA](https://github.com/Xilinx/dma_ip_drivers) linux driver for host-to-board communication using DMA in physical function 1 (PF1).

```
# from this repo
git clone git@github.com:zama-ai/QDMA.git zama_qdma

# before adding kernel module, let's define correctly its rights on the host machine
sudo cp zama_qdma/scripts/42-qdma.rules /etc/udev/rules.d/
udevadm control --reload-rules && udevadm trigger

cd zama_qdma/QDMA/linux-kernel/
make

# install kernel module in your machine
make install-mods
```

### FPGA loading

#### Loading through OSPI flash
Here we use 2 files resulting from the bitstream generation, in directory ${PROJECT_DIR}/versal/output_psi64 for example: **top_hpu.pdi** and **hpu_plug.xsa**.

First associate a pre-compiled elf for the ARM processor into the pdi.
```
# Compile elf
just --set OUTDIR $PWD/output_psi64 compile_fw
# Merge elf and pdi
just --set OUTDIR $PWD/output_psi64 merge_elf top_hpu
```

Then program the FPGA.
```
# Find your pcie device number
PCIE_CARD=$(lspci -d 10ee:50b4)
DEVICE="${PCIE_CARD%% *}"

# The following task will take a couple of minutes ...
sudo -E ami_tool cfgmem_program -d $DEVICE -t primary -i ${PROJECT_DIR}/versal/output_psi64/top_hpu.pdi -p 1
```

### Card diagnostics
In order to run card diagnostics, you must install [xbtest](https://xilinx.github.io/AVED/amd_v80_gen5x8_exdes_2_20240408/xbtest/user-guide/source/docs/introduction/installation.html) and have an example AVED bitstream loaded into FPGA.

> [!TIP]
> Depending on your hardware's AMC version, you should checkout original AVED repository, git tag ```7497599``` for version 2.3 and ```b580f84``` for 2.2.

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

### License

All the Zama code in this repository is distributed under the **BSD-3-Clause-Clear** license. Read [this](LICENSE) for more details.
