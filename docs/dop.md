# Digit Operation (DOp)

Current version is **HIS v2.0** (HPU Instruction Syntax).

The Homomorphic processing unit (HPU) processes any operation on integers, using their radix representation. For this, the user only needs to provide a program to the HPU.

There are 2 levels of HPU programming.

* The high level one handles the *integers*.
* The second one is low level. This code is the equivalent of assembly code for traditional CPU, but processing on elementary ciphertexts encoding *digits*.

This document describes the low level code syntax. The targeted elements are digits. The instructions are named **Digit Operation** (DOp).

## Integer / Digit
See [IOp documentation](iop.md) for more details.

At this level, integers are already decomposed into digits. Each digit is a *b*-bit value.

The basic elements that are manipulated in DOp code are elementary ciphertexts. Each ciphertext can encode a payload up to *p*-bits, with *p* > *b*.

In current version, *p* = 4 bits and *b* = 2 bits.

## TFHE
The user has to keep in mind that he/she is manipulating TFHE ciphertexts. Therefore some rules have to be followed.

Each ciphertext can encode up to *p* bits. This corresponds to the computation range. One cannot overflow this range. The computation would be altered.

In FHE, noise is used to hide the message. The noise grows with the number of successive operations. Therefore, there is a limit number of operations that can be done on the ciphertext before the need of cleaning the noise with a bootstrap. If this bootstrap is not done, the message could be altered by the noise with an additional operation. In TFHE the bootstrap is affordable and can be done regularly. See [Zama's blogpost](https://www.zama.ai/post/tfhe-deep-dive-part-1) for more information.

> [!NOTE]
> In TFHE, Programmable BootStrap (or PBS) is used. This means that while cleaning the noise, a 2^*p*-input LUT can be applied to the message at the same time.


## Syntax
DOp program is very similar to traditional CPU assembly code.

HPU has a **register file** (regfile), where each register contains one elementary ciphertext.

The HPU has also access to a memory, where input and output ciphertexts are stored. This memory is also used for the heap.

General syntax
```
<DOp> <Dst> <Src> [<Src>] [<Cst>]
```

A DOp command contains:

* 1 name
* 1 destination ciphertext
* 1 or 2 source ciphertexts, depending on the DOp
* 0 or 1 constant, depending on the DOp

### Dst / Src
Depending on the DOp, the associated source (or destination) can be one of the following:

|Type|Syntax|Description|
|----|------|-----------|
|Register|R*x*|Register #*x* in the **register file**.|
|Heap|TH.*x*|Ciphertext in **heap** at location *x*.<br>The prefix 'T' stands for templated. This means that the physical memory address will be retrieved by the HPU micro-processor from *x* and the start address where the current IOp heap data is stored in memory.|
|IOp Destination|TD[*i*].*x*|Block #*x* of IOp destination integer #*i*.<br>The prefix 'T' stands for templated. This means that the physical memory address will be retrieved by the HPU micro-processor from *x* and the *i*th destination integer address given by the IOp code.|
|IOp Source|TS[*i*].*x*|Block #*x* of IOp source integer #*i*.<br>The prefix 'T' stands for templated. This means that the physical memory address will be retrieved by the HPU micro-processor from *x* and the *i*th source integer address given by the IOp code.|
|Offset|@<ofs\>|Offset value in memory in ciphertext unit.|


### Cst
The presence of the constant depends on the DOp.

|Type|Syntax|Description|
|----|------|-----------|
|Constant|*v*|*v* is the value of the constant.|
|Immediate|TI[*i*].*x*|Digit #*x* of IOp immediate #*i*.<br>The prefix 'T' stands for templated. This means that the value is retrieved by the HPU micro-processor from the IOp immediate #*i* value.|
|LUT|*alias*|Alias corresponding to a value used to identify the LUT used in PBS.|

### DOp
There are 4 categories of DOp:

* ALU: Process linear operation on ciphertexts stored in regfile's registers.
* MEM: Read or write ciphertexts from/into HPU memory.
* PBS: Process programmable bootstrap on ciphertexts stored in regfile's register.
* Control: DOp used to control the HPU.

#### ALU
|DOp|Syntax|Description|
|---|------|-----------|
|ADD|ADD <Dst\> <Src1\> <Src2\>|Dst = Src1 + Src2<br>Dst, Src1 and Src2 are regfile's registers|
|SUB|SUB <Dst\> <Src1\> <Src2\>|Dst = Src1 - Src2<br>Dst, Src1 and Src2 are regfile's registers|
|MAC|MAC <Dst\> <Src1\> <Src2\> <Cst\>|Dst = Src1 * Cst + Src2<br>Dst, Src1 and Src2 are regfile's registers.<br>Cst is a constant or immediate.|
|ADDS|ADDS <Dst\> <Src\> <Cst\>|Dst = Src + Cst<br>Dst, Src are regfile's registers.<br>Cst is a constant or immediate.|
|SUBS|SUBS <Dst\> <Src\> <Cst\>|Dst = Src - Cst<br>Dst, Src are regfile's registers.<br>Cst is a constant or immediate.|
|SSUB|SSUB <Dst\> <Src\> <Cst\>|Dst = Cst - Src<br>Dst, Src are regfile's registers.<br>Cst is a constant or immediate.|
|MULS|MULS <Dst\> <Src\> <Cst\>|Dst = Src * Cst<br>Dst, Src are regfile's registers.<br>Cst is a constant or immediate.|


#### MEM
|DOp|Syntax|Description|
|---|------|-----------|
|LD|LD <Dst\> <Src\>|Read a ciphertext from HPU memory, and store in regfile's register.<br>Dst is a regfile's register<br>Src is either a heap, an IOp destination, an IOp source or an offset.|
|ST|ST <Dst\> <Src\>|Read a ciphertext from a regfile's register, and store in HPU memory.<br>Dst is either a heap, an IOp destination, an IOp source or an offset.<br>Src is a regfile's register<br>|


#### PBS
|DOp|Syntax|Description|
|---|------|-----------|
|PBS|PBS <Dst\> <Src\> <Cst\>|Process a PBS on a regfile's register, and store the result in a regfile's register.<br>Apply the LUT identified by Cst.<br>Dst and Src are regfile's register.<br>Cst is an alias identifying the LUT.|
|PBS_ML2|PBS_ML2 <Dst\> <Src\> <Cst\>|Many-LUT 2 PBS<br>Process a PBS on a regfile's register, and store the 2 results in **2 consecutive** regfile's registers. Apply the LUT identified by Cst.<br>Dst and Src are regfile's register.<br>Dst register ID should be a **multiple of 2**.<br>Cst is an alias identifying the LUT.<br>Note that this LUT is of type Many-LUT|
|PBS_ML4|PBS_ML4 <Dst\> <Src\> <Cst\>|Many-LUT 4 PBS<br>Process a PBS on a regfile's register, and store the 4 results in **4 consecutive** regfile's registers. Apply the LUT identified by Cst.<br>Dst and Src are regfile's register.<br>Dst register ID should be a **multiple of 4**.<br>Cst is an alias identifying the LUT.<br>Note that this LUT is of type Many-LUT|
|PBS_ML8|PBS_ML8 <Dst\> <Src\> <Cst\>|Many-LUT 8 PBS<br>Process a PBS on a regfile's register, and store the 8 results in **8 consecutive** regfile's registers. Apply the LUT identified by Cst.<br>Dst and Src are regfile's register.<br>Dst register ID should be a **multiple of 8**.<br>Cst is an alias identifying the LUT.<br>Note that this LUT is of type Many-LUT|
|PBS_F|PBS_F <Dst\> <Src\> <Cst\>|Same definition as PBS<br>This PBS is accompanied by a flush trigger for the HPU.<br>This control forces the HPU to start the PBS batch, even if this latter is not full.<br>Is used for performance purpose.|
|PBS_ML2_F|PBS_ML2_F <Dst\> <Src\> <Cst\>|Same definition as PBS_ML2<br>This PBS is accompanied by a flush trigger for the HPU.<br>This control forces the HPU to start the PBS batch, even if this latter is not full.<br>Is used for performance purpose.|
|PBS_ML4_F|PBS_ML4_F <Dst\> <Src\> <Cst\>|Same definition as PBS_ML4<br>This PBS is accompanied by a flush trigger for the HPU.<br>This control forces the HPU to start the PBS batch, even if this latter is not full.<br>Is used for performance purpose.|
|PBS_ML8_F|PBS_ML8_F <Dst\> <Src\> <Cst\>|Same definition as PBS_ML8<br>This PBS is accompanied by a flush trigger for the HPU.<br>This control forces the HPU to start the PBS batch, even if this latter is not full.<br>Is used for performance purpose.|

### Many LUT
A LUT encodes any function with *p*-bit input, and *p*-bit output.

If the input range does not occupy all the 2^*p* possible values, but only 2^*k*, with *k* < *p*, the LUT has enough room to actually encode several functions for this input. More precisely, it can encode 2^(*p-k*) different functions. Running a Many-LUT PBS produces several elementary ciphertexts.

For example, with *p*=4. If we know that the input is in range [0..1], it uses 1-bit over the 4 available. We could define a LUT that is able to compute 8 (2^3) functions for this same input.

This is useful, since a single PBS is run for this Many-LUT, instead of 8 for our example. Remember that the PBS is, by far, the most time consuming operation.


### Padding bit
Actually, the ciphertexts used in the HPU encode *p*+1 bits. The additional bit is called **padding bit**. It is at the MSB position of the payload. Most of the time, we keep this bit constant equal to 0. The computation range is kept at *p* bits.

A constant padding bit equal to 0 is necessary for the LUT to properly operate, i.e. representing any function *f* with *p*-bit input, and *p*-bit output.

If the padding bit is used, and so can be 0 or 1, the LUT behavior is the following:

* if padding bit = 0, v[*p*-1:0] -> *f*({1'b0,v[*p*-1:0]}) = r[*p*:0]
* if padding bit = 1, v[*p*-1:0] -> *f*({1'b1,v[*p*-1:0]}) = -r[*p*:0] = not(r[*p*:0]) + 1

It could occur that it is necessary for the computation range to overflow in *p*+1 bit, and so to use the padding bit. The associated LUT should therefore be chosen carefully, with the behavior described above in mind.

The details of such usage is not described here. Please refer to the [TFHE-rs handbook](https://github.com/zama-ai/tfhe-rs-handbook/blob/main/tfhe-rs-handbook.pdf).

Below, a non-exhaustive list of LUT aliases.

Let's name the 2 parts of payload in the ciphertext:
```
v[*p*-1:0] = {v[*p-b*-1:*b*],v[*b*-1:0]}
           = {vc, vm}
```
These names come from the words message (vm) and carry (vc).

|LUT|Description|
|---|-----------|
|None|Identity LUT.|
|MsgOnly|Extract the LSB *b*-bits of the payload contained in the ciphertext. Set the MSB bits to 0.<br>{0,vm}|
|CarryOnly|Extract the MSB *p-b*-bits of the payload contained in the ciphertext. Set the LSB bits to 0.<br>{vc,0}|
|CarryInMsg|Extract the MSB *p-b*-bits of the payload contained in the ciphertext. Shift them in LSB position.<br>{0,vc}|
|MultCarryMsg|Multiply vm and vc|
|MultCarryMsgLsb|Multiply vm and vc, and keep LSB *b* bits.|
|MultCarryMsgMsb|Multiply vm and vc, and keep MSB *p-b* bits, and shift them in LSB position.|
|BwAnd|bitwise operation : vm & vc|
|BwOr|bitwise operation : vm \| vc|
|BwXor|bitwise operation : vm ^ vc|
|CmpSign|Use the padding bit.<br>if v[*p*-1:0] == 0 -> 0<br>else -> 1 (if padding bit equals 0) or -1 (if padding bit equals 1)<br>This LUT is usually followed by a +1 to obtain positive values, that are afterwards used as you can see in [Debugging IOps](./debug.md).|
|ManyCarryMsg|ManuLUT2<br>func1: Extract the vm in LSB.<br>func2: Extract vc[0] in LSB.|


#### Control
|Dop|Syntax|Description|
|---|------|-----------|
|SYNC|SYNC|This DOp is executed when all DOp preceding it are over. A synchronization signal is sent to the CPU host.|

## Examples
### Load from memory

```
LD R1 @0x400      # At given offset in hexa
LD R2 @386        # At given offset in decimal
LD R3 TS[8].4     # From templated IOp source 8 digit 4
LD R3 TD[6].2     # From templated IOp destination 6 digit 2
LD R4 TH.60       # From templated heap slot 60
```

### Store from memory

```
ST @0x400   R1   # At given offset in hexa
ST @386     R2   # At given offset in decimal
ST TS[8].4  R3   # To templated IOp source 8 digit 4
ST TD[4].0  R4   # To templated IOp destination 4 digit 0
ST TH.60    R4   # To templated heap slot 60
```

### Arithmetic operations

```
ADD  R2 R1 R3
SUB  R2 R1 R3
MUL  R2 R1 R3
MAC  R2 R1 R3 4
ADDS R2 R1 10
SUBS R2 R1 TI[4].0 # Used digit 0 of fourth IOp immediate
```

### PBS

```
PBS     R2 R1 PbsNone
PBS_F   R2 R1 PbsCarryInMsg
PBS_ML2 R4 R6 ManyCarryMsg    # Results in R4 and R5
```
