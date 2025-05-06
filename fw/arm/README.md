Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
SPDX-License-Identifier: MIT

# AVED Management Control (AMC)

## Overview

The AVED Management Controller (AMC) provides management and control of the AVED RPU. Its basic features include, but are not limited to:

- In-Band Telemetry
- Built in Monitoring
- Host (AMI) communication
- Sensor Control
- QSFP Control
- Download and Programming to Flash

In addition, the AMC is fully abstracted from:

- The OS (Operating System Abstraction Layer (OSAL))
- The Firmware Driver (Firmware Interface Abstraction Layer (FAL))

Event driven architecture is provided by the Event Library (EVL).

---
### ZAMA changes

Changes from original AMC repository have been made to enable :
- Communication between host to FPGA regfile
- IOp to DOp translation
- Sending DOp through axi-stream to FPGA

## Building

You are supposed to compile this firmware using with the justfile in versal directory :

```
cd versal
just compile_fw
```

A minimum CMake version of 3.3.0 is required therefore you must ensure that this is installed and used in the place where you are building AMC i.e. server, VM or your local machine.
