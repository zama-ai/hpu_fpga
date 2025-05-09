<h1 style="text-align: center;">Debugging IOps</h1>

So, you've just found an excellent application for _TFHE_ and decided to use the _HPU_ to accelerate
it, however, using the high level _TFHE-rs_ API you don't get the performance you want. As with a
normal CPU, you can lower to the instruction set level (aka. assembly level) to try and speed up
your specific use case. The act of doing that is what we call writing a specialized IOp. To do that,
you need to know more about the _HPU_ architecture and its instruction set [here](./dop.md). This page
assumes that you've gone through it and/or are already aware of how to write an IOp.

Still, after writing your specialized IOps, you come to find that the result of your operation is
wrong and/or performance is not as good as you expected. If this resembles your story, read on.

# General debugging options

On the quest for the perfect IOp, you normally work on two main fronts: correctness and performance.
Debugging IOp correctness is usually done using the mockup - a software version of the _HPU_ that
gives you access to intermediate results without any _HPU_ hardware. It is much slower than the real
_HPU_ and even slower than running _TFHE_ for the CPU, but it provides observability at the
instruction set level, allowing you to figure out the exact point of discordance between the _HPU_
and you. The mockup also tries to be a faithful predictor of _HPU_ performance, so it can also be
used to optimize performance. However, the real _HPU_ has other factors that influence performance,
such as the software stack that runs to transport your ciphertexts to and from the _HPU_ and the
multiple memory and PCIe actors in the system that create uncertainty in IO and, consequently, in
the computation. If you find a big discrepancy between mockup performance prediction and real _HPU_
performance, there's still another tool in your belt: the instruction scheduler trace. We'll detail
all three options in the subsequent sections.

## The _HPU_ mockup

The _HPU_ mockup is included in the _TFHE-rs_ _HPU_ backend. It is basically a standalone rust
program that connects to the _HPU_ backend via Unix sockets and responds to register reads, IOp
requests, etc. instead of the real _HPU_ in the most faithful way we could find, effectively
emulating a _HPU_. It is also useful to test other _HPU_ parameter sets and/or architectural what-if
scenarios without actually having to write RTL (which you run away from probably as fast we do).
With that said, we'll leave that to the next episodes and focus only on debugging. In the event you
feel the rare urge to learn more, read the mockup's readme
[file](https://github.com/zama-ai/tfhe-rs/blob/main/mockups/tfhe-hpu-mockup/Readme.md). If that
doesn't satisfy your knowledge thirst, you can always read the code. To start the mockup, you clone
the _TFHE-rs_ repository, compile the mockup and launch it using:

```bash
cargo build --release --bin hpu_mockup --features isc-order-check
source setup_hpu.sh -c sim
target/release/hpu_mockup                                                   \
    --dump-out mockup.dump                                                  \
    --dump-reg                                                              \
    --log-out mockup.log                                                    \
    --report-out mockup.rpt                                                 \
    --report-trace                                                          \
    --params mockups/tfhe-hpu-mockup/params/gaussian_64b_pfail64_psi64.toml \
    --freq-mhz 350
```

> [!NOTE]
> The mockup will run as an independent process and the above command will launch it for
> you. It will just stay there waiting for connections from the _HPU_ backend and for the most part
> won't give you any output, even when connections are made.

The above commands will compile and start the mockup while dumping as much debugging information
as possible when the backend tells it to do something. The `--params` argument specifies the
emulated _HPU_ parameter set and architecture. The provided one is simply an example. The frequency
is only needed to convert cycles to time and is only used while reporting instruction latency
statistics, so don't obsess too much over it.

Now, any _TFHE-rs_ code needs to be compiled with the feature _hpu_ and by sourcing `setup_hpu.sh`
with the sim configuration flavor:

```
cd tfhe-rs
source setup_hpu.sh -c sim
```

If you do this right, all your _HPU_ _TFHE-rs_ code will now use the mockup instead of the real
_HPU_. Just keep it running on a different terminal and forget about it.

## Debugging correctness

Once you write an IOp, you'll want to test it standalone, before actually creating hooks to
_TFHE-rs_. To that effect, we provide a simple program called `hpu_bench`, that you can use to
benchmark and verify whether your IOp runs correctly. This bench also works with the mockup,
although the latency report will be wrong, as it will measure _CPU_ time, not _HPU_ time. For
example, the following will benchmark multiplying, homomorphically, clear text 64 bit values _1_ and
_0_ using the mockup:

```bash
cargo run --profile devo --features hpu --example hpu_bench -- \
    --integer-w 64 \
    --iop MUL \
    --trivial \
    --src 1  \
    --src 0 \
    --iter 1
```

> [!NOTE]
> Here's a description of the options used in this example:
> - `--integer-w`, selects the bit-width of the clear-text inputs used in the integer operations.
> - `--iop`, selects the IOp to benchmark. This example selected the _MUL_ IOp. If you're testing a
>   new one of your own making, you need to specify it here. If you don't specify this option, all
>   IOps will be benchmarked.
> - `--trivial`, Runs the benchmark by encrypting your clear-text trivially. This is mostly useful
>   to debug your IOp correctness.
> - `--src`, Used to force the clear-text of one of the inputs of the IOp. You can specify this many
>   times to force multiple inputs. If you don't force an input, it will be randomized.
> - `--iter`, The benchmark will be done by calling the specified IOps recursively, by re-cycling
>   the output to the first input, the provided amount of times. Defaults to one.
>
> You can always call `hpu_bench --help` to know more about the accepted options.

As an output, you'll get a latency report (ignore it for now) and the result of the multiplication
in clear-text. The result can be used to check if your IOp works correctly. You can test many
combinations of inputs, even omit `--src` to try random values and write a program around this to
make sure that your IOp works as expected. We all know that you are reading this because it doesn't,
so the next step is to read the mockup output to help you deal with the problem.

The mockup provides two main pieces of information that are very useful to debug an IOp:
- DOp execution order traces;
- intermediate DOp results.

The reason you need to know the DOp execution order is two-fold - to understand performance and to
be able to follow the intermediate DOp results. As it stands, the mockup writes DOp results as it
executes them to whatever folder provided using the `--dump-out` argument, so knowing the execution
order is an absolute must to be able to match results to DOps. We plan on making this step easier in
the future depending on how often we realize users have to debug their IOps.

Under `mockup.dump/blwe/run` you'll find one or more hex files for each output of a DOp. This
depends on how the LWE ciphertext is packed onto memory and might change in the future. However,
we're running trivial encrypted versions to debug (as you've probably noticed by the `--trivial`
argument while calling the benchmark program). The very last bits of the ciphertext contain the
message, and the whole ciphertext is output in little endian, _LSB_ first order.

The only thing missing to be able to debug an IOp is to be able to link an intermediate output to a
specific DOp. Under `mockup.dump/dop`, you'll find a list of assembly files of both the IOp stream
as it was received along with an assembly listing of the DOps as they were executed. By opening the
assembly file containing the IOp you're trying to debug, you can now make sense of the intermediate
result files, which hopefully will get you closer to debugging your IOp.

## Debugging performance with the mockup

Now that your IOp works as expected, you are puzzled by its performance. Before throwing down the
towel and blaming the _HPU_ team, you have other options. One of them is to look at other
information produced by the mockup to learn what is wrong.

As you've learned from the other documentation pages on the _HPU_[^1], the main bottleneck to _TFHE_
and _HPU_ processing time is the programmable bootstrapping (PBS). On the _HPU_, PBSs take almost
100 times more to process than linear/leveled or IO operations. This all means that performance will
be mostly given by the number of PBS batches your IOp has to execute. With this in mind, the mockup
produces an execution report giving you great insight into how many DOps have been executed and
their latency. You can find this report under `mockup.rpt/`, if you follow the example above. One
report for every different IOp executed will be produced, although only one per IOp type. Here's an
example for the multiplication:

```
Report for IOp: MUL      <I64 I64> <I64@0x40> <I64@0x00 I64@0x20>
TimeRpt { cycle: 44061792, duration: 146.872ms }
InstructionKind {MemLd: 1703, MemSt: 1691, Arith: 1840, Pbs: 1685, Sync: 1}
Processing element statistics:
	 "KsPbs_0" => issued: 1685, batches: 142, by_timeout: 0, usage: 0.9891165172855315
	 "LdSt_0" => issued: 3394, batches: 3394, by_timeout: 0, usage: 1
	 "Lin_0" => issued: 1840, batches: 1840, by_timeout: 0, usage: 1
```

The most important piece of information you can take from this report, besides the actual latency,
is the number of PBS batches, 142 in this case, and the PBS unit usage ratio. This will indicate the
percentage of time that the batches were full, indicating how efficiently your IOp is using the PBS
unit. The **by_timeout** variable is also important because it indicates how many batches were
scheduled not completely full and started because no more PBSs could be scheduled, by timeout. This
timeout feature is mostly a security feature and set to a very large value comparable to the batch
latency. Your IOps should always indicate whether to flush a batch if that batch is a dependency to
subsequent batches.

If you don't understand why your PBS unit usage rate is low, you'll have to inspect an instruction
scheduler trace. In the same directory (`mockup.rpt` in the example), you'll find a **json**
file per IOp type executed. This contains a trace of instruction scheduler events, which give you
access to almost all details of the scheduling process. This trace was made to emulate a real
hardware trace, so the techniques that follow will also be helpful to debugging using the real
hardware.

## Debugging performance with the _HPU_

Before we delve into the details of how to debug your IOp using the trace, you need to know a bit
more about the instruction scheduler.

### The instruction scheduler

The instruction scheduler in the _HPU_ is responsible for scheduling instructions to the multiple
processing units composing an _HPU_. They are currently only three: a load store unit, a linear FHE
operation unit and a PBS unit. All three can run in parallel, and the PBS unit can actually run many
bootstraps in parallel. To maximize efficiency, the instruction scheduler looks into the DOp stream
and reorders operations, while respecting their dependencies, to keep all three as busy as they can.
While doing that, it keeps a record of all events it uses to make its decisions, such as DOps being
queued, DOps being scheduled to processing elements, executed, DOp's dependencies being cleared,
etc. This stream of events is sent to a buffer in HBM memory, which can later be retrieved through
PCIe.

The main difference between traces captured by the mockup versus the hardware is that, in hardware,
the instruction scheduler doesn't really know which IOp is executing. So all events are simply
queued to the same memory in the order they are seen while the mockup actually separates events by
IOp. This means that before debugging a hardware trace, you'll have to find out where your IOp is in
the event stream. This is not so hard because all DOp streams come tagged with a synchronization ID,
which can be used to separate events from multiple IOps, so you'll only have to search your IOp
among many DOp groups. Still, it is a nuisance and if the mockup reproduces _HPU_ performance,
you're better off using it, as it records more information than the hardware. Again, all this is a
moving target, and we'll probably add that information to the trace in future iterations.

### Retrieving a hardware trace

Anyway, after you've used your _HPU_, you can retrieve the trace by compiling and executing a little
rust program - the _hputil_:

```bash
cargo build --release --features hpu,utils,hw-v80 --bin hputil
./target/release/hputil trace-dump -f trace.json
```

This will save all events to a **json** file. The HBM trace buffer is small, roughly 32MBs at
the time of writing, but the result of unpacking all that information to **json** results in
files sized over GBs. We're planning on changing the output format or allowing for multiple output
formats, but that is not supported as of now.

Once you have your trace file, save it dearly as it might be key to figuring out what is going on
with your IOp.

> [!NOTE]
> This program is useful to extract more information from the _HPU_, such as dumping debug
> registers. It is for internal use and the rest of its functionality would only be useful if you
> have a clear understanding of what each register contains. Still, most registers have a suggestive
> name, so you could read the `--help` output to learn more.

## Debugging using instruction scheduler traces

Once you have a trace file you want to look into, independently of it being a hardware or mockup
trace, you can use a python library specifically written for this purpose. You can find it in the
[_TFHE-rs_](https://github.com/zama-ai/tfhe-rs/tree/main/backends/tfhe-hpu-backend/python) code
base. The library's main purpose is mainly to separate the trace into independent traces from
different IOps and help you analyze a trace by filtering for events of different types while
collecting statistics regarding those. First, you import the library:

```python
from isctrace.analysis import Trace, Refilled, Retired
```

Those three classes mainly abstract three types of events, refilling, retirement and trace events
(all events). A retirement event is seen when an operation has finished by one of the processing
elements. By collecting only events of that type, you can look at a stream of operations in the
order they were executed. You can read a trace and filter for those events as follows:

```python
iops = Trace.from_hw("trace.json") # Or Trace.from_mockup, for mockup traces
retired = Retired(iops[x])          # x is the IOp index you want to look into
```

You can look at them as a pandas **DataFrame**:

```python
retired.to_df()
```

The **Retired** class does more than just collecting retirement events. It actually pairs issuing
events to the retirement events to get the DOp latency.

Another very important piece of information you can get from the **Retired** class is what we call a
PBS latency table, which is also a **DataFrame**:

```python
retired.pbs_latency_table(freq_mhz=freq_mhz)
```

This will give you a batch size vs batch latency information table. This will be useful for you to
find non-full batches executed in your stream, if any, and the actual latency of each batch size.
Latencies here are measured from batch to batch, so they will include latency of any kind of
linear/IO operations that were executed as dependencies to batches. However, those latencies are
often very small and the instruction scheduler can usually interleave linear operations that share
no dependency to the current executing batch, so they make no impact to the final batch latency.
Still, you can catch some bugs or improve your IOp, if that is not the case.

Obviously, if this information isn't enough to figure out what is going on, you could do anything
you would like with the information recorded in the _Trace_ class.

We've now gone through all the tools and tricks we actually use ourselves to debug and improve our
own IOps. Still, most of the magic here is to know how to write properly for the _HPU_, so we'll
finish with a single performance improvement example.

# An example

Let's say you want to write a IOp that compares two ciphertexts homomorphically[^2]. Naively, and
assuming you already know the _HPU_ instruction set, you could try to do the following:

<p align="center">
<!-- Comparison diagram -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./img/recursive_comparison_dark.png">
  <source media="(prefers-color-scheme: light)" srcset="./img/recursive_comparison.png">
  <img width=500 alt="Comparison FHE recursive computation">
</picture>
</p>

Where the gray diamond depicts a PBS that outputs 1 if the input is not zero, zero otherwise, unless
it is negative, in which case it will actually output -1 because PBSs are nega-cyclic. We'll refer
to this PBS as the "**sign PBS**" from now on. If you add one to this result, you'll get an
order value: 0 for less-than, 1 for equal, 2 for greater-than.

The yellow diamond is an "**order merge PBS**" and we'll call it that from now on. It looks at
two order messages packed into one ciphertext. If the most significant order value amounts to equal,
the PBS chooses the least significant order, if not chooses the most significant order. The packing
operation is implicit, but it maps to a*4 + b, which can be made by the _HPU_ using a single _MAC_
operation, which is very cheap.

The pink diamond is the final comparison PBS, or "**comparison PBS**" from now on, converting an
order value to a boolean and this depends on the type of comparison you're trying to do. If you want
a less-than comparison, you'll only output 0 if the input is the greater-than value (2).

All operations in the diagram map directly to a DOp in the instruction set. We can then try to do a
comparison by simply subtracting every digit of every pair of ciphertexts, running the **sign
PBS** on the result, adding one to get the order value of each digit and merging the order values
recursively, using the **order merge PBS**, from most significant to least significant digit.
The end result would be the result of converting the final order value to a boolean by the
**comparison PBS** (pink). Note that _TFHE-rs_ and our own IOps make some further
simplifications and use more FHE tricks to try to reduce the number of PBSs used, but we'll not use
them here for the sake of simplicity. Also, note that the end result of this example will end up by
being comparable to the actual implementation, but I'll leave understanding that as an exercise to
the reader.

The direct translation from the above diagram to rust firmware code is actually very simple. Even
though it is not the purpose of this document to explain how to write firmware for the HPU, I'll
paste it here for the sake of completeness:

```rust
pub fn cmp_gt(prog: &mut Program) {
    // Create Input/Output template entry points to be linked at execution time.
    let mut dst = prog.iop_template_var(OperandKind::Dst, 0);
    let src_a = prog.iop_template_var(OperandKind::Src, 0);
    let src_b = prog.iop_template_var(OperandKind::Src, 1);

    // Get the index of the required PBSs
    let sgn_pbs = new_pbs!(prog, "CmpSign");   // gray   diamond
    let red_pbs = new_pbs!(prog, "CmpReduce"); // yellow diamond
    let gt_pbs = new_pbs!(prog, "CmpGt");      // pink   diamond

    dst[0] <<= std::iter::zip(src_a, src_b)
        .rev()
        .fold(prog.new_imm(pbs_macro::CMP_EQUAL), |acc, (a, b)| {
            (&(&a - &b).pbs(&sgn_pbs, false) + &prog.new_imm(1))
                .pack_carry(&acc)
                .pbs(&red_pbs, false)
        })
        .pbs(&gt_pbs, false);
}
```

> [!NOTE]
> Note that all code used in this example is available
> [here](https://github.com/zama-ai/tfhe-rs/tree/main/backends/tfhe-hpu-backend/src/fw/fw_impl/demo.rs).
> This is an extra firmware implementation made just for demonstration purposes.

Now, as we've gone through, the first part of understanding the performance of this IOp is to
benchmark it. Here's the latency report of the above operation as given by the mockup for 64 bits:

```
> cargo run --profile devo --features hpu --example hpu_bench -- \
    --fw Demo --integer-w 64 --iop CMP_GT --src 1 --src 0
> cat mockup.rpt/CMP_GT*.rpt
Report for IOp: CMP_GT   <I2 I64> <I2@0x40> <I64@0x00 I64@0x20>
TimeRpt { cycle: 13166040, duration: 43.886ms }
InstructionKind {MemLd: 64, MemSt: 1, Arith: 96, Pbs: 65, Sync: 1}
Processing element statistics:
	 "KsPbs_0" => issued: 65, batches: 34, by_timeout: 34, usage: 0.17379679144385018
	 "LdSt_0" => issued: 65, batches: 65, by_timeout: 0, usage: 1
	 "Lin_0" => issued: 96, batches: 96, by_timeout: 0, usage: 1
 >
```

In this example a batch takes roughly 1ms and the timeout is set to 300us. The first thing that pops
up is that the usage ratio, or PBS unit efficiency, is at 17%. Also, the number of PBSs needed by
the IOp are 65. We know that the _HPU_ can run many PBSs in parallel, in this example 10.
That means that those 65 PBSs could potentially run on 65/10 * 1ms=6.5ms and we are at 43ms! You
knew you couldn't trust the _HPU_ team, but before you make some noise let's gather some more
information.

To be able to investigate that, you can read the mockup trace and print the retired instructions and
batch latency reports, as demonstrated in the previous sections. Here's the result of an 8 bit
comparison, to keep things simple:

```
           latency   delta  reltime opcode             args
timestamp
503482162      422     422      422     LD          R0 @0x3
503482447      681     285      707     LD          R1 @0x7
503482729      807     282      989     LD          R7 @0x2
503483160     1212     431     1420     LD          R8 @0x6
503483458     1354     298     1718     LD         R14 @0x1
503483742     1612     284     2002     LD         R15 @0x5
503484040     1722     298     2300     LD         R21 @0x0
503484485     2141     445     2745     LD         R22 @0x4
503484622     2149     137     2882    SUB         R2 R0 R1
503486697     3530    2075     4957    SUB         R9 R7 R8
503488779     5030    2082     7039    SUB      R16 R14 R15
503490861     6369    2082     9121    SUB      R23 R21 R22
503872701   388072  381840   390961    PBS        R3 R2 @10
503872776   386072      75   391036    PBS       R10 R9 @10
503872858   384072      82   391118    PBS      R17 R16 @10
503872940   382072      82   391200    PBS      R24 R23 @10
503874855     2147    1915   393115   ADDS          R4 R3 1
503876931     4148    2076   395191   ADDS        R11 R10 1
503879014     6149    2083   397274   ADDS        R18 R17 1
503881097     8150    2083   399357   ADDS        R25 R24 1
503883173     8311    2076   401433   ADDS          R5 R4 4
504270837   387657  387664   789097    PBS        R6 R5 @11
504272990     2146    2153   791250    MAC   R12 R6 R11 X4
504660668   387671  387678  1178928    PBS      R13 R12 @11
504662821     2146    2153  1181081    MAC  R19 R13 R18 X4
505050499   387671  387678  1568759    PBS      R20 R19 @11
505052652     2146    2153  1570912    MAC  R26 R20 R25 X4
505440337   387678  387685  1958597    PBS      R27 R26 @11
505828029   387685  387692  2346289    PBS      R28 R27 @12
505828481      445     452  2346741     ST         @0x8 R28

                    min          avg          max          sum  count
batch size
1           1292.306667  1303.392667  1326.323333  6516.963333      5
4           1304.000000  1304.000000  1304.000000  1304.000000      1
```

The first thing you might note is that we mainly have two different batch sizes, one batch of four,
and five with one PBS. Although we didn't describe the IOp in any parallel fashion, the
instruction scheduler correctly identified that the **sign PBSs** (gray) could all run in parallel,
as they share no dependency. For eight bits, we use four ciphertexts and four **sign PBSs**, and so
the scheduler created a single batch of four PBSs. For sixty four bits, it could actually launch
three batches of twelve [^3]. So, why couldn't it also pack the **order merge PBSs** onto batches?
The reason is simply because this algorithm is recursive - one **order merge PBS** depends on the
previous merge. In other words, one **order merge PBS** cannot start before the previous one has
finished. Recursiveness has plagued hardware engineers trying to parallelize operations for many
decades and more recently software engineers too with the advent of multiple core _CPUs_ and the
massively parallel _GPUs_. This is common for many algorithms including fundamental ones such as
addition, division and others more specific such as, ECC codes, sorting, IIR filters and a whole
myriad of other algorithms.

One usual way to parallelize recursive algorithms is to find out a different formulation of the
problem which you can break into two parallel computations that you can merge. If that is possible,
you can then follow the same process recursively for the two parallel computations to get four
parallel computations and so on until you cannot reduce it any further. This is called recursive
doubling, and used extensively in the derivation of the now famous, incredibly prolific and mostly
forgotten kogge-stone adder[^4]. Breaking recursiveness for almost all recursive algorithms use
recursive doubling in some way or another and it can be used too in our simple comparison. The way
we've formulated the comparison can already be broken into two parallel problems using exactly the
same operations, if you realize that you can divide your integer into two parts, compute the order
of all digits of the most significant part and the order of all the digits of the least significant
part and merge the resulting two orders by a single merge. If you keep dividing the parts
recursively, you'll end up with a tree of merges, instead of a recursive stream of merges. If you
have enough "threads" or computing elements, the final latency of the tree will be proportional to
**log(N)** times the merge latency, instead of proportional to **N**. Some say that a
picture is worth a thousand words:

<p align="center">
<!-- Parallel Comparison diagram -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./img/parallel_comparison_dark.png">
  <source media="(prefers-color-scheme: light)" srcset="./img/parallel_comparison.png">
  <img width=500 alt="Comparison FHE parallel computation">
</picture>
</p>

Note that the computation is now done in stages of parallel elements, each stage with half the
parallel work of the previous one. It is not fully parallel all the way to the end, but still much
better than the original recursive formulation.

Let's benchmark this new formulation (**cmp_gte()** in **demo.rs**):

```
Report for IOp: CMP_GTE  <I2 I64> <I2@0x40> <I64@0x00 I64@0x20>
TimeRpt { cycle: 3699192, duration: 12.33ms }
InstructionKind {MemLd: 64, MemSt: 1, Arith: 95, Pbs: 64, Sync: 1}
Processing element statistics:
	 "KsPbs_0" => issued: 64, batches: 10, by_timeout: 7, usage: 0.5636363636363636
	 "LdSt_0" => issued: 65, batches: 65, by_timeout: 0, usage: 1
	 "Lin_0" => issued: 95, batches: 95, by_timeout: 0, usage: 1
```

We've improved the latency dramatically. Note that we only do now ten batches instead of thirty
four. The PBS unit usage, while not perfect, went up dramatically. Note that we still have batches
that are not full, specially for the last stages of the tree. If you give no information to the
scheduler that these should be flushed, it will only launch the batch after a timeout. By properly
flushing batches at the end of each stage, we get this (**cmp_lt()** in **demo.rs**):

```
Report for IOp: CMP_LT   <I2 I64> <I2@0x40> <I64@0x00 I64@0x20>
TimeRpt { cycle: 3176268, duration: 10.587ms }
InstructionKind {MemLd: 64, MemSt: 1, Arith: 95, Pbs: 63, Sync: 1}
Processing element statistics:
	 "KsPbs_0" => issued: 63, batches: 10, by_timeout: 2, usage: 0.5545454545454545
	 "LdSt_0" => issued: 65, batches: 65, by_timeout: 0, usage: 1
	 "Lin_0" => issued: 95, batches: 95, by_timeout: 0, usage: 1
```

That's almost a twenty percent improvement. Now, there's still two batches timing out. You can read
the trace and read the batch latency report to know where those batches are. In this particular
case, what happened was that the linear operations between two batches took more than 300us to
complete. It is still possible to hide that latency but that requires re-ordering the IOp as to
avoid this. We're working on a new firmware framework that works those details out for you by
running a simulation on an operation dependency graph and trying to schedule operations the best it
can. Your only job would only be to figure out how to parallelize an operation and write those
operation dependencies as a graph. You can read the current
[llt](https://github.com/zama-ai/tfhe-rs/blob/main/backends/tfhe-hpu-backend/src/fw/fw_impl/llt/mod.rs)
IOp implementation to learn how to do that but it is not considered stable yet for widespread use.

# Finishing remarks

Hopefully, this document has enlightened you on the tools at your disposal to debugging _HPU_ IOps.
Make sure you also read the other documents pertaining to writing firmware to the _HPU_ before
trying to write or even debug IOps.

Besides that, happy homomorphic encryption!

[^1]: If you haven't, go read them now, this one can wait.
[^2]: We already have IOps that do that, but they are actually a very good example of how to
    improve IOp performance dramatically, or looking from another angle, how to make the _HPU_ look
    bad.
[^3]: Although the typical minimum batch size is of ten PBSs in this example, the _HPU_ can run
    twelve PBSs much more efficiently than running two batches of ten and two respectively. The
    latency of a batch of twelve is of 12/10 the latency of a single batch of ten, while two batches
    of ten and two take twice the latency. This is because the amount of work to do as part of a PBS
    can be broken up in many smaller parts and the effective latency becomes the sum of the
    latencies of those smaller work chunks. This suggests that we could probably fill all ten slots
    with work coming from a single PBS and have the PBS latency be ten times lower. We cannot do
    that, however, because the bandwidth for getting the bootstrapping key is limited, forcing us to
    share the key for a single rotation throughout multiple PBSs, instead, to keep maximum PBS
    throughput.
[^4]: We all stand on the shoulder of giants, and giants should be acknowledged even if a bit old.
    Kogge, Peter M., and Harold S. Stone. "A parallel algorithm for the efficient solution of a
    general class of recurrence equations." IEEE transactions on computers 100.8 (1973): 786-793.
