<p align="center">
<!-- product name logo -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./docs/img/hpu-header-d.png">
  <source media="(prefers-color-scheme: light)" srcset="./docs/img/hpu-header-l.png">

  <img width=600 alt="Zama HPU FPGA">
</picture>
</p>

<hr/>

<p align="center">
<a href="https://docs.zama.ai/tfhe-rs/hardware-acceleration/run-on-hpu"> 📒 Documentation</a> | <a href="https://zama.ai/community"> 💛 Community support</a> | <a href="https://github.com/zama-ai/awesome-zama"> 📚 FHE resources by Zama</a>
</p>


<p align="center">
  <a href="https://github.com/zama-ai/tfhe-rs/releases"><img src="https://img.shields.io/github/v/release/zama-ai/tfhe-rs?style=flat-square"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-BSD--3--Clause--Clear-%23ffb243?style=flat-square"></a>
</p>


## About

### What is Zama's HPU on FPGA

Zama's Homomorphic Processing Unit (HPU) is a SystemVerilog-based hardware implementation targeting [AMD Alveo V80](https://www.amd.com/en/products/accelerators/alveo/v80.html) FPGA board. It is the first open-source processor capable of executing homomorphic operations directly on encrypted data, designed specifically to accelerate [TFHE-rs](https://github.com/zama-ai/tfhe-rs) workloads.

This repository provides everything needed to deploy and experiment with the HPU, including:
* SystemVerilog RTL source code
* Block design for AMD Versal FPGAs, partially derived from AVED – see [block design code](versal/scripts/bd).
* Bitstream generation flow for the Alveo V80
* Simulation flow and testbenches
* Firmware for the Real-Time Processing Unit (RPU), derived from [Xilinx's AVED](https://github.com/Xilinx/AVED) – see [firmware docs](fw/arm/README.md).

> [!Note]
> HPU also needs the following software:
>
> * The [QDMA driver](https://github.com/zama-ai/dma_ip_drivers)
> * The [AMI driver](https://github.com/zama-ai/AVED)
> * The [high-level API](https://github.com/zama-ai/tfhe-rs)
> * The HPU register interface generator [hw_regmap](https://github.com/zama-ai/hw_regmap), loaded in HPU FPGA project as a git submodule

</br>

### Directory structure
The directories of this repository are organized in the following way:
#### Root
* `docs/`
    * Markdown documentations.
* `fw/`
    * Firmware code for the RPU or microblaze.
    * Flow necessary for the ublaze generation.
* `hw/`
    * RTL code and the simulation flow.
* `sw/`
    * Python models for some algorithms.
    * SW binaries for testbench stimuli and reference generation.
    * Register map generator: hw_regmap.
* `versal/`
    * Flow for block design and bitstream generation.

#### `hw/`

* `common_lib/`
    * Shared RTL library, organized in <RTL module\> hierarchy.
* `memory_file/`
    * ROM content files.
* `module/`
    * HPU RTL, organized in <RTL module\> hierarchy.
* `syn/`
    * Scripts for synthesis.
* `scripts/`
    * Miscellaneous scripts.
* `simu_lib/`
    * Shared RTL library for simulation.
* `output/`
    * Generated directory.
    * Simulation and out-of-context (ooc) synthesis results.

#### <RTL module\>
>[!Note]
> If any directory is not needed, it won't be present.
* <module_name\>
    * `info/`
        * Mainly contains ***file_list.json***, which lists the RTL files of this directory, the RTL dependencies and synthesis constraints of this module.
    * `rtl/`
        * RTL files. The file name corresponds to the module name.
    * `constraints/`
        * Synthesis files for local ooc synthesis (with ***_local*** suffix), and hierarchical synthesis if needed (with ***_hier*** suffix).
    * `simu/`
        * Simulation files. Is organized as a regular <RTL module\> structure. See [below](#simulation).
    * `module/`
        * If the module's submodules need to be placed in a <RTL module\> structure, it is done under the *module* directory.
    * `scripts/`
        * Scripts necessary to generate the module.
</br>

## Table of Contents
- [About](#about)
  - [What is Zama's HPU on FPGA](#what-is-zamas-hpu-on-fpga)
  - [Directory structure](#directory-structure)
- [Getting Started](#getting-started)
  - [Installation](#installation)
  - [Setup](#setup)
  - [Build bitstream](#build-bitstream)
  - [Simulation](#simulation)
- [Bring-up](#bring-up)
  - [AMI driver](#ami-driver)
  - [QDMA](#qdma)
  - [FPGA loading](#fpga-loading)
- [Resources](#resources)
  - [High-level API](#high-level-api)
  - [Low-level implementations](#low-level-implementations)
- [Working with HPU FPGA](#working-with-hpu-fpga)
  - [Citations](#citations)
  - [Contributing](#contributing)
  - [License](#license)
  - [FAQ](#faq)
- [Support](#support)
</br>

## Getting started

### Installation

To use the HPU FPGA project, ensure the following tools and dependencies are installed:

- **bash** : All the commands are run in a bash terminal. If not it would be specified.
- [**tfhe-rs**](https://github.com/zama-ai/tfhe-rs/) >= 1.2.0.
- **Host linux driver**: [AVED fork](https://github.com/zama-ai/AVED).
- **DMA linux driver**: [QDMA fork](https://github.com/zama-ai/dma_ip_drivers).
- [**Vivado/Vitis**](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools/2025-1.html) = **2025.1**.
- [**just**](https://github.com/casey/just) >= 1.37.0.
- *(simulation only)* [**Sage**](https://sagemanifolds.obspm.fr/install_ubuntu.html) = 10.4.
- *(firmware compilation)* [**CMake**](https://cmake.org/download/) >= 3.3.0.
- **Python** = 3.12 with:
    - `edalize` from the [ZAMA fork] used as a submodule (https://github.com/zama-ai/edalize).
    - `jinja2`
    - *(simulation only)* `constrainedrandom`

> [!CAUTION]
> **Ubuntu with kernel 5.15.0-139-generic** or **Almalinux kernel 5.14-*.** is required to compile the host software. (See [Ami driver](https://github.com/zama-ai/AVED)). \
> We found issues concerning FPGA programmation with some of Ubuntu's patches. The last patch, dated May 5 2025, is fully stable. \
> If ever you are open to change your distribution, we recommend using Almalinux.

#### Python dependencies
> [!TIP]
> With newer Linux versions, it is recommended to use a virtual environment.

```
# create a virtual environment "my_env"
python -m venv my_venv

# activate it
source my_venv/bin/activate

# install dependencies

# jinja2 is used for file templates
pip install jinja2

# constrainedrandom is used to generate random parameters in simulation
pip install constrainedrandom

# To exit this environment
deactivate

# Next time, you just need to activate this environment, with:
source my_venv/bin/activate
```

### Setup
To prepare your environment, set the bash variables **XILINX_PATH** with your xilinx installation path.


Clone the HPU repository:
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
> A useful variable `$PROJECT_DIR` will be set to direct to the root of the current project.


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
> * sometimes Vivado 2025.1 will report routing failures like "Router failed to deposit pin-assignments on site...". In these case you need to wait for top_hpu_routed_error.dcp to be generated and run the script you can find in versal/script/reroute.tcl which unroutes this slice and reroutes the whole design (Ex: vivado -mode batch -source scripts/reroute.tcl -tclargs SLICE_X286Y585 output_psi64).

The documentation about [HPU parameters](./docs/hpu_parameters.md) and [parsing flags](./docs/parsing_flags.md) can help you understand the content of these 3 scripts and change some of these parameters to adapt the HPU to your needs.

A tested bitstream of the HPU compiled using run_syn_hpu_3parts_psi64.sh is available in tfhe-rs repo.

### Simulation

The flow supports 2 simulation tools :
- ```xsim``` from AMD
- ```vcs``` from Synopsys.

Set the variable ```$PROJECT_SIMU_TOOL``` in ```setup.sh``` to "xsim" or "vcs" according to the tool you want to use.

> [!NOTE]
> `vcs` is set by default.

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

Note that if `run_simu.sh` is not present, the corresponding testbench is not fully supported.


Example: Run `pe_alu` testbench. `pe_alu` is the ALU processing element
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
The V80 FPGA has on-board a dual-core Arm Cortex-R5F (RPU) that executes the firmware code. To accelerate the simulation, we use a microblaze model to run a similar version of this firmware.

In some simulations, like the top level one, the generation of the microblaze model is needed. So before these simulations, do the following:
```
${PROJECT_DIR}/fw/ublaze/script/generate_core.sh
```
<p align="right">
  <a href="#table-of-contents" > ↑ Back to top </a>
</p>

## Bring-up

> [!WARNING]
>
> We assume that the user has already used a V80 board and knows its basic usage.<br>
> We assume that the [flash](https://xilinx.github.io/AVED/latest/AVED%2BUpdating%2BFPT%2BImage%2Bin%2BFlash.html) has already been correctly programmed and the example design [is in partition 0](https://xilinx.github.io/AVED/latest/AVED%2BUpdating%2BDesign%2BPDI%2Bin%2BFlash.html)<br>
> We recommend not to update the V80 board flash content as tfhe-hpu-backend can dynamically load your bitstream via PCIe. \
> If you really need to put your bitstream in flash, we recommend to use partition 1 for your freshly generated pdi. This will enable you to fallback on partition 0 after a reboot.*

> [!WARNING]
>
> Note that we witnessed the following behavior: server reboot after loading of the V80 FPGA from OSPI. The PCIe device disappeared during the boot.<br>
> If your machine **doesn't allow hot plug, your machine will reboot**.<br>
> In this specific scenario, we suggest to program partition 0 in order to reboot your machine with the new pdi or program using tandem PCIe.<br>
>
> In the case you corrupt the flash inadvertently, plug USB/JTAG and reprogram it.<br>
> Use script ```cd versal && just rewrite_flash ``` or follow [AMD tutorial](https://xilinx.github.io/AVED/latest/AVED%2BUpdating%2BFPT%2BImage%2Bin%2BFlash.html).

To control the board and use ```TFHE-rs' tfhe-hpu-backend```, install both AMI (AVED Management Interface - driver and tool) and QDMA driver.


### AMI driver
The AMI software, adapted for HPU, is available in a [git fork](https://github.com/zama-ai/AVED) from XILINX AVED example design.

> [!WARNING]
> If you insert ami module of the original AVED branche with one of our bitstream loaded and your machine doesn't support hot plug, you will crash.\
> We tweaked the design and removed a block that is mandatory for original AVED driver.\
> Without this module, AVED is issuing a PCIE read to a missing module. This is not the case in our fork.

AMI driver compilation requires usage of a specific Linux kernel version (ubuntu 5.15.0-* ) (Almalinux 5.14.0-* ), Linux kernel sources and DKMS.


#### Driver installation
```
git clone git@github.com:zama-ai/AVED.git zama_aved

./zama_aved/sw/AMI/scripts/gen_package.py
cd zama_aved/sw/AMI/scripts/output/<timestamp>/
sudo apt install ./ami_xxx.deb
```
Now ```ami_tool``` is available.



#### How to use ami_tool

Through a few examples:
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
git clone https://github.com/zama-ai/dma_ip_drivers.git zama_qdma

# before adding kernel module, let's define correctly its rights on the host machine
sudo cp zama_qdma/QDMA/linux-kernel/scripts/42-qdma.rules /etc/udev/rules.d/
udevadm control --reload-rules && udevadm trigger

cd zama_qdma/QDMA/linux-kernel/
TANDEM_BOOT_SUPPORTED=1 make

# install kernel module in your machine
sudo make install-mods
```

### FPGA loading

#### Loading through OSPI flash

There are two file types resulting from `run_syn_hpu_3parts_psi64.sh` bitstream generation, in directory `${PROJECT_DIR}/versal/output_psi64`: bitstream `*.pdi` and shell archive `hpu_plug.xsa`.\
Note that if you use another given script (for another HPU size), the output directory will be `${PROJECT_DIR}/versal/output_psi<size\>`.

You might have noticed that two pdi are created after fpga compilation. In order to program them directly into OSPI, the first step is to merge the two pdi together.

```
# We assume that hpu_fpga project has already been set-up.
# Return to hpu_fpga directory.
cd ${PROJECT_DIR}/versal
just merge_pdi top_hpu
```

Then you can associate a pre-compiled elf for the ARM processor into the pdi.
```
# Compile elf
just --set OUTDIR $PWD/output_psi64 compile_fw

# Merge elf and pdi
just --set OUTDIR $PWD/output_psi64 merge_elf top_hpu
# /!\ At this point top_hpu.pdi has been modified and now contains the firmware. The original pdi has been moved into top_hpu.pdi.noelf.
```

Then program the FPGA.
```
# Find your pcie device number
PCIE_CARD=$(lspci -d 10ee:50b4)
DEVICE="${PCIE_CARD%% *}"

# The following task will take a couple of minutes ...
sudo -E ami_tool cfgmem_program -d $DEVICE -t primary -i ${PROJECT_DIR}/versal/output_psi64/top_hpu.pdi -p 1
```

### Programmation through PCIE
In certain systems, the PCIe device is required to boot within 120 ms. To achieve this, we are employing tandem configuration done in 2 stages. Stage 1 programming allows immediate PCIe enumeration. Stage 2 includes FPGA logic and ARM firmware.

Stage 1 requires the V80 board to be connected through JTAG, while Stage 2 requires connection via PCIe. By default we suppose JTAG and PCIe are connected to the same machine.
If ever it's not the case, optional arguments to the "program" justfile recipe are available to program only a given stage: `program top_hpu stage1` or `program top_hpu stage2`.

Same as for OSPI programmation, an elf must be associated with the pdi. Here, merge elf to ```*_tandem2```.

```
just merge_elf top_hpu_tandem2
```

Once merged you will be able to program the two pdis.

```
just program top_hpu XFL1MND5BQYG
```

> [!TIP]
> XFL1MND5BQYG is a fake serial number. To get your serial number you can either:
> * read it on the box you received
> * when AMI driver is loaded and AMC is in the expected version you can run a command like ```cat /sys/module/ami/drivers/pci\:ami/0000\:24\:00.0/board_serial``` (replacing 24 by the PCIe slot id of your board)
> * with xsdb you can run ```xsdb -eval "connect;puts [lsort -unique [regex -all -inline {( XFL[A-Z0-9]*)} [targets -target-properties]]]"```. This gives you all the serial numbers available on your machine with a character 'A' added at the end.

> [!WARNING]
> Note: if booting from OSPI is required after programming with Tandem, please run ```xsdb versal/scripts/jtag/write_ospi_mode.tcl``` beforehand.

*Now, you can run TFHE-rs code with the HPU you just loaded! In order to do so, have a look at [this document](https://docs.zama.ai/tfhe-rs/hardware-acceleration/run-on-hpu) in order to find the next commands!*

<p align="right">
  <a href="#table-of-contents" > ↑ Back to top </a>
</p>

## Resources

### High-level API
Use the HPU with the TFHE-rs high-level API:
- [HPU configuration documentation](https://docs.zama.ai/tfhe-rs/hardware-acceleration/run-on-hpu)
- [Video tutorial] Introducing HPU HFPA](Coming soon)
- [HPU benchmarks](https://docs.zama.ai/tfhe-rs/get-started/benchmarks/hpu)
### Low-level implementations
Understand the HPU architecture in depth and make your own implementation:
- [HPU components](docs/hpu.md)
- [HPU parameters](docs/hpu_parameters.md)
- [Integer Operation (IOp)](docs/iop.md)
- [Digit Operation (DOp)](docs/dop.md)
- [Parsing flags](docs/parsing_flags.md)
- [Debugging IOps](docs/debug.md)
- [HPU FAQ](docs/faq.md)

</br>

## Working with HPU FPGA

### Citations
To cite HPU FPGA in academic papers, please use the following entry:

```text
@Misc{HPU FPGA,
  title={{A systemVerilog implementation of the Homomorphic Processing Unit (HPU) targeting AMD Alveo V80 FPGA board}},
  author={Zama},
  year={2025},
  note={\url{https://github.com/zama-ai/hpu_fpga}},
}
```

### Contributing

There are two ways to contribute to HPU FPGA:

- [Open issues](https://github.com/zama-ai/hpu_fpga/issues/new) to report bugs and typos, or to suggest new ideas
- Request to become an official contributor by emailing [hello@zama.ai](mailto:hello@zama.ai).

Becoming an approved contributor involves signing our Contributor License Agreement (CLA). Only approved contributors can send pull requests, so please make sure to get in touch before you do!
<br></br>

### License
This software is distributed under the **BSD-3-Clause-Clear** license. Read [this](LICENSE) for more details.

#### FAQ
**Is Zama’s technology free to use?**
>Zama’s libraries are free to use under the BSD 3-Clause Clear license only for development, research, prototyping, and experimentation purposes. However, for any commercial use of Zama's open source code, companies must purchase Zama’s commercial patent license.
>
>Everything we do is open source and we are very transparent on what it means for our users, you can read more about how we monetize our open source products at Zama in [this blogpost](https://www.zama.ai/post/open-source).

**What do I need to do if I want to use Zama’s technology for commercial purposes?**
>To commercially use Zama’s technology you need to be granted Zama’s patent license. Please contact us hello@zama.ai for more information.

**Do you file IP on your technology?**
>Yes, all Zama’s technologies are patented.

**Can you customize a solution for my specific use case?**
>We are open to collaborating and advancing the FHE space with our partners. If you have specific needs, please email us at hello@zama.ai.

<p align="right">
  <a href="#table-of-contents" > ↑ Back to top </a>
</p>

## Support

<a target="_blank" href="https://community.zama.ai">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://github.com/zama-ai/tfhe-rs/assets/157474013/08656d0a-3f44-4126-b8b6-8c601dff5380">
  <source media="(prefers-color-scheme: light)" srcset="https://github.com/zama-ai/tfhe-rs/assets/157474013/1c9c9308-50ac-4aab-a4b9-469bb8c536a4">
  <img alt="Support">
</picture>
</a>

🌟 If you find this project helpful or interesting, please consider giving it a star on GitHub! Your support helps to grow the community and motivates further development.
