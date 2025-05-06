# Parsing flags

HPU parameters are defined in **packages**.
In order to test different values for these parameters, we use different files each describing a value. The files describing the same definition package have the same name, and are in different directories. The parsing is in charge of retrieving the package/file that is needed.
The packages that are present in the project are the ones that are very likely needed for the top synthesis.
If exotic values are needed for a testbench, scripts are available to generate the corresponding definition packages.

The script in charge of file parsing is **run_edalize.py**. It uses flags. A flag is composed by a **family** identifier, and 1 or several flag **names**.
Package files defining the same parameter(s) are flagged with the same flag family, but with different flag names.

For example, the AXI4 bus data width can be of different sizes : 128, 256, or 512 bits. All the packages defining the AXI4 bus data width are named : ```axi_if_data_w_definition_pkg``` and are stored in a file named ```axi_if_data_w_definition_pkg.sv```. To avoid conflicts, they are stored in different directories. In their file_list.json, they are all flagged with the flag family ```AXI_DATA_W```. Each has respectively the flag name : ```AXI_DATA_W_128```, ```AXI_DATA_W_256```, ```AXI_DATA_W_512```.

## Directory organization:
```
axi_if/module/axi_if_common/rtl/AXI_DATA_W
|-- AXI_DATA_W_128
|   `-- axi_if_data_w_definition_pkg.sv
|-- AXI_DATA_W_256
|   `-- axi_if_data_w_definition_pkg.sv
`-- AXI_DATA_W_512
    `-- axi_if_data_w_definition_pkg.sv
```


## file_list.json
```
{
    "name": "hw/module/axi_if/module/axi_if_common/rtl/AXI_DATA_W/AXI_DATA_W_128/axi_if_data_w_definition_pkg.sv",
    "library": "work",
    "env": ["all"],
    "target": ["all"],
    "is_include_file": false,
    "AXI_DATA_W" : "AXI_DATA_W_128"
},
{
    "name": "hw/module/axi_if/module/axi_if_common/rtl/AXI_DATA_W/AXI_DATA_W_256/axi_if_data_w_definition_pkg.sv",
    "library": "work",
    "env": ["all"],
    "target": ["all"],
    "is_include_file": false,
    "AXI_DATA_W" : "AXI_DATA_W_256"
},
{
    "name": "hw/module/axi_if/module/axi_if_common/rtl/AXI_DATA_W/AXI_DATA_W_512/axi_if_data_w_definition_pkg.sv",
    "library": "work",
    "env": ["all"],
    "target": ["all"],
    "is_include_file": false,
    "AXI_DATA_W" : "AXI_DATA_W_512"
},
```

The option for run_edalize.py is
```
-F <flag_family> <value>
```

## Flags
In the HPU there are several flags available.

(\*) : default value


| Family | Description | Values | Parameters | Comment |
| ----------- | ----------- | ----------- |----------- |----------- |
| APPLICATION | Crypto parameter set |APPLI_msg2_carry2_pfail64_132b_tuniform_7e47d8co (\*)<br>APPLI_msg2_carry2_pfail64_132b_gaussian_1f72dba<br>APPLI_msg2_carry2_gaussian<br>APPLI_msg2_carry2_tuniform|N, GLWE_K, PBS_L, PBS_B_W, LWE_K, MOD_Q_W, MOD_Q, MOD_P_W, MOD_P, KS_L, KS_B_W, MOD_KSK_W, MOD_KSK, PAYLOAD_BIT, PADDING_BIT||
|TOP_TOP |Top name|TOP_TOP_hpu (\*)|TOP| Support only HPU.|
|HPU_PART|HPU placement|HPU_PART_delta (\*)<br>HPU_PART_gf64|\*_S_NB,\*_USE_PP, \*_S_INIT||
|HPU_TWDFILE |Path to twiddle files (used for top synthesis)|HPU_TWDFILE_default (\*)|TWD_IFNL_FILE_PREFIX, TWD_PHRU_FILE_PREFIX, TWD_GF64_FILE_PREFIX| Default memory content path: to directory "memory_file"|
|NTT_MOD|NTT prime|NTT_MOD_goldilocks (\*)<br>NTT_MOD_solinas2_44_14<br>NTT_MOD_solinas3_32_17_13|MOD_NTT_NAME, MOD_NTT_NAME_S, MOD_NTT_W, MOD_NTT, MOD_NTT_TYPE, MOD_NTT_INV_TYPE||
|NTT_CORE_ARCH|NTT core architecture|NTT_CORE_ARCH_gf64 (\*)<br>NTT_CORE_ARCH_wmm_unfold_pcg|NTT_CORE_ARCH| gf64 : Optimized NTT architecture used for 64b goldilocks prime.<br>wmm: NTT architecture used for any prime size. Supports Solinas 2 and 3 type prime for now.|
|NTT_CORE_R|NTT elementary radix size| NTT_CORE_R_2 (\*)|R| Support only R=2. Some modules may support 2^r. This is checked in associated local testbenches.|
|NTT_CORE_PSI|NTT radix number |NTT_CORE_PSI_4<br>NTT_CORE_PSI_8<br>NTT_CORE_PSI_16 (\*)<br>NTT_CORE_PSI_32<br>NTT_CORE_PSI_64<br>NTT_CORE_PSI_128|PSI||
|NTT_CORE_DIV|INTT processed coefficient divider (Not supported in gf64 archi yet)|NTT_CORE_DIV_1 (\*)<br>NTT_CORE_DIV_2|BWD_PSI_DIV|NTT_CORE_ARCH_gf64 supports only DIV_1.|
|NTT_CORE_RDX_CUT|NTT radix cuts|NTT_CORE_RDX_CUT_n5c6 (\*)<br>NTT_CORE_RDX_CUT_n5c5c1<br>NTT_CORE_RDX_CUT_n6c5<br>NTT_CORE_RDX_CUT_n4c4c3|NTT_RDX_CUT_NB, NTT_RDX_CUT_S||
|KSLB|Key switch form factor|KSLB_x2y32z3<br>KSLB_x3y32z3 (\*)<br>KSLB_x3y64z3<br>KSLB_x4y16z3<br>KSLB_x6y128z3<br>KSLB_x6y64z3|LBX, LBY, LBZ||
|KSK_CUT|Number of input cuts for ksk_manager|KSK_CUT_1<br>KSK_CUT_2<br>KSK_CUT_4<br>KSK_CUT_8<br>KSK_CUT_16 (\*)|KSK_CUT_NB||
|KSK_SLOT |KSK cache number of slots|KSK_SLOT_8 (\*)|KSK_SLOT_NB||
|BSK_CUT|Number of input cuts for bsk_manager|BSK_CUT_1<br>BSK_CUT_2<br>BSK_CUT_4<br>BSK_CUT_8 (\*)<br>BSK_CUT_16|BSK_CUT_NB||
|BSK_SLOT |BSK cache number of slots|BSK_SLOT_8 (\*)|BSK_SLOT_NB||
|AXI_DATA_W |AXI4 bus data width|AXI_DATA_W_128<br>AXI_DATA_W_256 (\*)<br>AXI_DATA_W_512|AXI4_DATA_W||
|TOP_PCMAX|System maximum number of AXI connections to HBM|TOP_PCMAX_pem2_glwe1_bsk8_ksk8 (\*)<br>TOP_PCMAX_pem1_glwe1_bsk4_ksk4<br>TOP_PCMAX_pem2_glwe1_bsk16_ksk16|PEM_PC_MAX,GLWE_PC_MAX,BSK_PC_MAX,KSK_PC_MAX||
|TOP_PC|Number of AXI connexions to HBM|TOP_PC_pem2_glwe1_bsk4_ksk4<br>TOP_PC_pem1_glwe1_bsk4_ksk4<br>TOP_PC_pem2_glwe1_bsk8_ksk8<br>TOP_PC_pem2_glwe1_bsk8_ksk16<br>TOP_PC_pem1_glwe1_bsk2_ksk3<br>TOP_PC_pem1_glwe1_bsk1_ksk1<br>TOP_PC_pem1_glwe1_bsk2_ksk2 (\*)<br>TOP_PC_bsk2_ksk4_pem1<br>TOP_PC_pem2_glwe1_bsk16_ksk16|PEM_PC,GLWE_PC,BSK_PC,KSK_PC||
|<br>PEP_BATCH|PEP batch info : number of CT per batch, and total number of ct stored in PEP|PEP_BATCH_bpbs16_tpbs32<br>PEP_BATCH_bpbs8_tpbs32 (\*)<br>PEP_BATCH_bpbs12_tpbs32<br>PEP_BATCH_bpbs8_tpbs16|BATCH_NB, TOTAL_BATCH_NB, BATCH_PBS_NB, TOTAL_PBS_NB||
|PEP_MSPLIT|PEP monomult acc split type|PEP_MSPLIT_main2_subs2 (\*)<br>PEP_MSPLIT_main1_subs3<br>PEP_MSPLIT_main3_subs1|MSPLIT_TYPE, MSPLIT_DIV, MSPLIT_MAIN_FACTOR, MSPLIT_SUBS_FACTOR||
|REGF_STRUCT |Regfile structure|REGF_STRUCT_reg64_coef32_seq4<br>REGF_STRUCT_reg16_coef8_seq4|REGF_REG_NB, REGF_COEF_NB, REGF_SEQ||
