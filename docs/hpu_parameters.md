# HPU Parameters

SystemVerilog parameters are used to configure the HPU. This document describes these parameters and their effects.

Some supported and verified values of these parameters are available in **definition** packages.

Parsing flags are used to select them. See the [parsing flags documentation](parsing_flag.md).

Some parameters have special types. They can be found in **common_definition_pkg.sv**.

If exotic values are needed (for simulation for example), a script named **gen_<definition_package_name>.py** can be used to generate the corresponding sv definition package.


## Crypto parameters
Crypto parameters are defined in the definition package: **param_tfhe_definition_pkg.sv**.
They are identified by an application. Several real applications are available in the code.

* ```APPLI_msg2_carry2_pfail64_132b_tuniform_7e47d8c```
    * The default application.
    * Defines a parameter set dedicated for HPU with:
        * 4-bit payload ciphertext
        * pfail = 2^-64
        * 132-bit security
        * tuniform noise distribution
* ```APPLI_msg2_carry2_pfail64_132b_gaussian_1f72dba```
    * Defines a parameter set dedicated for HPU with:
        * 4-bit payload ciphertext
        * pfail = 2^-64
        * 132-bit security
        * gaussian noise distribution
* ```APPLI_msg2_carry2_gaussian```
    * Today's CPU parameter set for:
        * 4-bit payload ciphertext
        * pfail = 2^-64
        * 132-bit security
        * gaussian noise distribution
* ```APPLI_msg2_carry2_tuniform```
    * Today's CPU parameter set for:
        * 4-bit payload ciphertext
        * pfail = 2^-64
        * 132-bit security
        * tuniform noise distribution

Exotic parameter sets are tested in the testbench. (This is especially useful to have manageable simulation duration.) They are generated using the script: **gen_param_tfhe_definition_pkg.py**.

The concerned parameters are:

* ```N```: Polynomial size.
    * Is a power of 2.
    * In top simulation, minimal N is 2^7.
* ```GLWE_K```: Number of polynomials in the mask part of the GLWE.
* ```PBS_L```: Number of levels in PBS decomposition.
    * When PBS_L > 1, with ntt_wmm architecture, it is possible to reduce the INTT size, since it has less polynomials to process. This is done with BWD_PSI_DIV parameter.
* ```PBS_B_W```: Number of bits in the PBS decomposition base.
* ```LWE_K```: Number of elements in the LWE mask.
* ```MOD_Q_W```: Number of bits in ciphertext coefficient.
* ```MOD_Q```: Ciphertext coefficient modulo.
    * Is a power of 2.
    * Is equal to 2^MOD_Q_W.
* ```KS_L```: Number of levels in key-switch (KS) decomposition.
* ```KS_B_W```: Number of bits in KS decomposition base.
* ```MOD_KSK_W```: Number of bits in key-switching (KS) key coefficient.
* ```MOD_KSK```: KSK coefficient modulo.
* ```PAYLOAD_BIT```: Number of payload bits in the body coefficient.
* ```PADDING_BIT```: Presence of the padding bit in the body coefficient.

HPU uses the NTT. Therefore a prime is used for the computation. Note that HPU supports only 1 prime at a time.

Parameters are used to define this prime.

* ```MOD_NTT_NAME```: NTT prime name (used as identifier)
* ```MOD_NTT_NAME_S```: Internal prime name expressed as a string (for debug purpose)
* ```MOD_NTT_W```: Number of bits in the NTT prime.
* ```MOD_NTT```: NTT prime value.
* ```MOD_NTT_TYPE```: NTT prime type.
  * Special prime type could ease the computation. For example Solinas2 primes, with the form 2^q - 2^k + 1.
* ```MOD_NTT_INV_TYPE```: NTT prime inverse type.
  * Special type could ease the computation.
  * This is used in the modulo switch done at the output of the INTT.


## HPU architecture parameters
### Top
* Top module.
    * ```TOP_TOP```: defines current top. Only HPU is supported for now.

* Practical
    * Define the path to retrieve ROM content files.
    * ```HPU_TWDFILE```: Path to twiddle ROM memory files.

* Placement partition.
    * Parameters are used to define the placement partition of the HPU, especially the NTT / INTT.
    * Xilinx FPGA with 3 SLRs are used: v80 for example. Therefore the HPU is split into 3 parts.
    * These parameters define the number of NTT/INTT stages that are present in each part.
    * ```*_S_NB```: Number of stages in the corresponding part.
    * ```*_USE_PP```: Presence of the post-process (PP) in the corresponding part. The PP is the multiplication with the BSK.
    * ```*_S_INIT```: First stage ID of the corresponding part.
        * In NTT, the stages are numbered from S-1 to 0.
        * In INTT, the stages are numbered from 2N-1 to S.
        * S = log2(N)

* AXI
    * HPU is connected to the HBM with AXI4 buses.
    * ```AXI_DATA_W```: Defines the AXI4 data bus size in bit unit.
        * Is a power of 2.
        * Tested values: 128, 256 and 512.
        * Use the flag **AXI_DATA_W** to choose one of these values.
* TOP_PCMAX: This flag defines the maximum number of AXI4 buses available in the top design.
    * The parameters are defined for each entry.
    * ```PEM_PC_MAX,GLWE_PC_MAX,BSK_PC_MAX,KSK_PC_MAX```
    * The concerned package is **top_common_pcmax_definition_pkg.sv**
    * For exotic values, use the script **gen_top_common_pcmax_definition_pkg.py**


* TOP_PC: This flag defines the number of AXI4 buses actually used in HPU.
    * The parameters are defined for each entry.
    * ```PEM_PC,GLWE_PC,BSK_PC,KSK_PC```
    * The concerned package is **top_common_pc_definition_pkg.sv**
    * For exotic values, use the script **gen_top_common_pc_definition_pkg.py**


### NTT
2 different NTT architectures are available in HPU: **ntt_wmm** and **ntt_gf64**.

**ntt_wmm** is the historical NTT version. It supports any prime value. Modular reduction optimizations are available for solinas2 and solinas3 primes.
    * Note that the SW used to generate the stimuli does not support any prime.

**ntt_gf64** is an optimized NTT version for a particular prime, **goldilocks-64 = 2^64 - 2^32 + 1**.


The following parameter chooses between the 2:

* ```NTT_CORE_ARCH```: Parameter to describe the NTT flavor. Available values: **NTT_CORE_ARCH_GF64** and **NTT_CORE_ARCH_WMM_UNFOLD_PCG**.
  * Use the flag **NTT_CORE_ARCH** to choose among these possibilities.

The NTT is configured with the following parameters.

* ```R```: Radix size
    * NTT computation unit (butterfly) size, in number of entries.
    * Is a power of 2
    * Only 2 is supported now.
* ```PSI```: Number of NTT computation units working in parallel.
    * The processing path computes RxPSI coefficients in parallel.
    * In simulation, use **gen_ntt_core_common_psi_definition_pkg.py** to generate the definition package with exotic values.
* ```BWD_PSI_DIV```: When PBS_L > 1, the INTT has less coefficients to process. Therefore the INTT processing path size could be reduced.
    * This parameter describes the reduction of the INTT.
    * RxPSI/BWD_PSI_DIV coefficients are processed in parallel in the INTT.
    * Note that in ntt_gf64 architecture this feature has not been implemented yet. Therefore for ntt_gf64, only BWD_PSI_DIV=1 is supported.
    * In simulation, use **gen_ntt_core_common_div_definition_pkg.py** to generate the definition package with exotic values.


The NTT process contains log2(N) stages. (In the RTL log2(N) is named S). Some stages are gathered together to ease the implementation. A group of stages is called a NTT radix cut. Within a group, the same size of NTT is used (the radix cut size). A network and a barrier of multiplication with phi are used between groups. For more information, see NTT documentation.

* ```NTT_RDX_CUT_NB```: Number of NTT radix cuts.
    * In ntt_wmm, only NTT_RDX_CUT_NB=2 is supported.
* ```NTT_RDX_CUT_S```: Is an array, describing each NTT radix cuts. Number of stages inside the corresponding NTT radix cut.
    * In ntt_wmm the first NTT radix cut size should be less or equal to the second.
    * In ntt_gf64
        * The first NTT radix cut is a negacyclic one. It has been optimized for a maximum size of 5 stages.
        * The other stages are cyclic ones. They have been optimized for a maximum size of 6 stages.

In simulation, use **gen_ntt_core_common_cut_definition_pkg.py** to generate the definition package with exotic values.


### Keys
A data cache is used for KSK and BSK. Parameters are used to configure these caches.

* ```KSK_SLOT_NB```: KSK cache size.
    * The purpose of this cache is to hide the HBM reading latency.
    * A slot is used to store an entire GGSW. This parameter defines the number of slots in advance that are necessary to hide the HBM reading latency.
    * In simulation, use **gen_ksk_mgr_common_slot_definition_pkg.py** to generate the definition package with exotic values.
* ```KSK_CUT_NB```: Number of entry cuts seen by the module reading from HBM.
    * This parameter is an implementation parameter.
    * It is used to ease the writing of the key in the local cache memory.
    * Should be a multiple of KSK_PC.
    * Usually set to KSK_PC
    * In simulation, use **gen_ksk_mgr_common_cut_definition_pkg.py** to generate the definition package with exotic values.

The same parameters are defined for the BSK.

* ```BSK_SLOT_NB```: BSK cache size.
    * The purpose of this cache is to hide the HBM reading latency.
    * A slot is used to store an entire GGSW. This parameter defines the number of slots in advance that are necessary to hide the HBM reading latency.
    * In simulation, use **gen_bsk_mgr_common_slot_definition.py** to generate the definition package with exotic values.
* ```BSK_CUT_NB```: Number of entry cuts seen by the module reading from HBM.
    * This parameter is an implementation parameter.
    * It is used to ease the writing of the key in the local cache memory.
    * Should be a multiple of BSK_PC.
    * Usually set to BSK_PC.
    * In simulation, use **gen_bsk_mgr_common_cut_definition_pkg.py** to generate the definition package with exotic values.


### KS
The key-switch consists in a sum of matrix-vector multiplications. Because of the sizes of this matrix and vector, the computation is done piece by piece. LBX x LBY x LBZ is the number of multiplications computed in parallel.
* ```LBX```: Number of LWE coefficients that are processed in parallel.
* ```LBY```: Number of big-LWE coefficients that are processed in parallel.
* ```LBZ```: Number of resulting decomposition levels that are processed in parallel.
    * For an implementation reason, several KSK words are stored together in a BRAM word. Therefore, LBZ x KSK_W should not be bigger than 64bits.
* In simulation, use **gen_pep_ks_common_definition_pkg.py** to generate the definition package with exotic values.

### Regfile
The register file is the module that handles the registers used in the DOp code. URAMs are used to store them.

For exotic values use **gen_regf_common_definition_pkg.py** to generate the definition package.

* ```REGF_REG_NB```: Number of computation registers available for the user through the DOp code.
    * Today, HPU uses 64 registers.
* ```REGF_COEF_NB```: Implementation parameter.
    * Defines the number of coefficients at the regfile interface.
    * Is a power of 2.
* ```REGF_SEQ```: Implementation parameter.
    * To ease the distribution of the command through all the URAMs, the REGF_COEF_NB coefficients are not processed in parallel, but sequentially, in REGF_SEQ times.
    * Note that a pipeline is used, so the regfile is still able to process REGF_COEF_NB per cycle. It is the latency that is impacted.
    * Divides REGF_COEF_NB.

### Monomial multiplier-accumulator
The monomial multiplier-accumulator (MMACC) deals with the GLWEs that are currently being bootstrapped. It contains mainly BRAMs to store the GLWE between each CMUX. The MACC is split into parts to ease the implementation, especially split placement in different SLRs. Today 4 parts are used: 2 belong to the main, and 2 to the subsidiary submodule. In case the MMACC is spread into 2 SLRs, the main submodule is connected to the HPU entry part, and the subsidiary to the NTT processing part.

The following parameters define the size of each part.

* PEP_MSPLIT: Parsing flag used to select between the different possibilities:
    * PEP_MSPLIT_MSPLIT_main2_sub2, PEP_MSPLIT_main1_subs3, PEP_MSPLIT_main3_subs1
    * The concerned parameters are:
        * ```MSPLIT_TYPE```: MMACC split type name. The other parameters could be deduced from this one.
        * ```MSPLIT_DIV```: Number of unit parts.
        * ```MSPLIT_MAIN_FACTOR```: Number of unit parts in the main submodule.
        * ```MSPLIT_SUBS_FACTOR```: Number of unit parts in the subsidiary submodule.
