# HPU_REGIF_CORE documentation
**Date**: 2025-07-17
**Tool Version**: bb0db737792da6b81e69a039028c971af1627fe2

## RegisterMap Overview

**Module Name**: hpu_regif_core
**Description**: HPU top-level register interface. Used by the host to retrieve design information, and to configure it.

HPU top-level register interface. Used by the host to retrieve design information, and to configure it.

HPU top-level register interface. Used by the host to retrieve design information, and to configure it.

HPU top-level register interface. Used by the host to retrieve design information, and to configure it.
**Offset**: 0x0
**Range**: 0x40000
**Word Size (b)**: 32
**External Packages**: "axi_if_common_param_pkg.sv","axi_if_shell_axil_pkg.sv"


---

## Section Overview

Below is a summary of all the registers in the current register map:

| Section Name | Offset | Range | Description |
|-------------:|:------:|:-----:|:------------|
| [entry_cfg_1in3](#section-entry-cfg-1in3) | 0x0 | 0x10 | entry_cfg_1in3 section with known value used for debug. |
| [info](#section-info) | 0x10 | 0x4c | RTL architecture parameters |
| [hbm_axi4_addr_1in3](#section-hbm-axi4-addr-1in3) | 0x1000 | 0xa0 | HBM AXI4 connection address offset |
| [bpip](#section-bpip) | 0x2000 | 0x8 | BPIP configuration |
| [keyswitch](#section-keyswitch) | 0x3000 | 0x4 | Keyswitch Configuration |
| [entry_prc_1in3](#section-entry-prc-1in3) | 0x10000 | 0x10 | entry_prc_1in3 section with known value used for debug. |
| [status_1in3](#section-status-1in3) | 0x10010 | 0x4 | HPU status of part 1in3 |
| [ksk_avail](#section-ksk-avail) | 0x11000 | 0x8 | KSK availability configuration |
| [runtime_1in3](#section-runtime-1in3) | 0x12000 | 0x13c | Runtime information |
| [entry_cfg_3in3](#section-entry-cfg-3in3) | 0x20000 | 0x10 | entry_cfg_3in3 section with known value used for debug. |
| [hbm_axi4_addr_3in3](#section-hbm-axi4-addr-3in3) | 0x20010 | 0x80 | HBM AXI4 connection address offset |
| [hpu_reset](#section-hpu-reset) | 0x20100 | 0x4 | Used to control the HPU soft reset |
| [entry_prc_3in3](#section-entry-prc-3in3) | 0x30000 | 0x10 | entry_prc_3in3 section with known value used for debug. |
| [status_3in3](#section-status-3in3) | 0x30010 | 0x4 | HPU status of parts 2in3 and 3in3 |
| [bsk_avail](#section-bsk-avail) | 0x31000 | 0x8 | BSK availability configuration |
| [runtime_3in3](#section-runtime-3in3) | 0x32000 | 0x48 | Runtime information |


---


## Section entry-cfg-1in3

### Register Overview

Below is a summary of all the registers in the current section entry_cfg_1in3:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [dummy_val0](#register-entry-cfg-1in3dummy-val0) | 0x0 | R. |  RTL version |
| [dummy_val1](#register-entry-cfg-1in3dummy-val1) | 0x4 | R. |  RTL version |
| [dummy_val2](#register-entry-cfg-1in3dummy-val2) | 0x8 | R. |  RTL version |
| [dummy_val3](#register-entry-cfg-1in3dummy-val3) | 0xc | R. |  RTL version |


---


### Register entry-cfg-1in3.dummy-val0

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x0
- **Default**: 16843009




---


### Register entry-cfg-1in3.dummy-val1

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x4
- **Default**: 286331153




---


### Register entry-cfg-1in3.dummy-val2

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x8
- **Default**: 555819297




---


### Register entry-cfg-1in3.dummy-val3

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0xc
- **Default**: 825307441




---




## Section info

### Register Overview

Below is a summary of all the registers in the current section info:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [version](#register-infoversion) | 0x10 | R. |  RTL version |
| [ntt_architecture](#register-infontt-architecture) | 0x14 | R. |  NTT architecture |
| [ntt_structure](#register-infontt-structure) | 0x18 | R. |  NTT structure parameters |
| [ntt_rdx_cut](#register-infontt-rdx-cut) | 0x1c | R. |  NTT radix cuts, in log2 unit (for gf64 arch) |
| [ntt_pbs](#register-infontt-pbs) | 0x20 | R. |  Maximum number of PBS in the NTT pipeline |
| [ntt_modulo](#register-infontt-modulo) | 0x24 | R. |  Code associated to the NTT prime |
| [application](#register-infoapplication) | 0x28 | R. |  Code associated with the application |
| [ks_structure](#register-infoks-structure) | 0x2c | R. |  Key-switch structure parameters |
| [ks_crypto_param](#register-infoks-crypto-param) | 0x30 | R. |  Key-switch crypto parameters |
| [regf_structure](#register-inforegf-structure) | 0x34 | R. |  Register file structure parameters |
| [isc_structure](#register-infoisc-structure) | 0x38 | R. |  Instruction scheduler structure parameters |
| [pe_properties](#register-infope-properties) | 0x3c | R. |  Processing elements parameters |
| [bsk_structure](#register-infobsk-structure) | 0x40 | R. |  BSK manager structure parameters |
| [ksk_structure](#register-infoksk-structure) | 0x44 | R. |  KSK manager structure parameters |
| [hbm_axi4_nb](#register-infohbm-axi4-nb) | 0x48 | R. |  Number of AXI4 connections to HBM |
| [hbm_axi4_dataw_pem](#register-infohbm-axi4-dataw-pem) | 0x4c | R. |  Ciphertext HBM AXI4 connection data width |
| [hbm_axi4_dataw_glwe](#register-infohbm-axi4-dataw-glwe) | 0x50 | R. |  GLWE HBM AXI4 connection data width |
| [hbm_axi4_dataw_bsk](#register-infohbm-axi4-dataw-bsk) | 0x54 | R. |  BSK HBM AXI4 connection data width |
| [hbm_axi4_dataw_ksk](#register-infohbm-axi4-dataw-ksk) | 0x58 | R. |  KSK HBM AXI4 connection data width |


---


### Register info.version

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x10
- **Default**: C.f. fields


#### Field Details

Register version contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| major      | 0 | 4 |VERSION_MAJOR| RTL major version |
| minor      | 4 | 4 |VERSION_MINOR| RTL minor version |



---


### Register info.ntt-architecture

- **Description**: NTT architecture
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x14
- **Default**: NTT_CORE_ARCH




---


### Register info.ntt-structure

- **Description**: NTT structure parameters
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x18
- **Default**: C.f. fields


#### Field Details

Register ntt_structure contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| radix      | 0 | 8 |R| NTT radix |
| psi      | 8 | 8 |PSI| NTT psi |
| div      | 16 | 8 |BWD_PSI_DIV| NTT backward div |
| delta      | 24 | 8 |DELTA| NTT network delta (for wmm arch) |



---


### Register info.ntt-rdx-cut

- **Description**: NTT radix cuts, in log2 unit (for gf64 arch)
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x1c
- **Default**: C.f. fields


#### Field Details

Register ntt_rdx_cut contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| radix_cut0      | 0 | 4 |NTT_RDX_CUT_S_0| NTT radix cut #0 |
| radix_cut1      | 4 | 4 |NTT_RDX_CUT_S_1| NTT radix cut #1 |
| radix_cut2      | 8 | 4 |NTT_RDX_CUT_S_2| NTT radix cut #2 |
| radix_cut3      | 12 | 4 |NTT_RDX_CUT_S_3| NTT radix cut #3 |
| radix_cut4      | 16 | 4 |NTT_RDX_CUT_S_4| NTT radix cut #4 |
| radix_cut5      | 20 | 4 |NTT_RDX_CUT_S_5| NTT radix cut #5 |
| radix_cut6      | 24 | 4 |NTT_RDX_CUT_S_6| NTT radix cut #6 |
| radix_cut7      | 28 | 4 |NTT_RDX_CUT_S_7| NTT radix cut #7 |



---


### Register info.ntt-pbs

- **Description**: Maximum number of PBS in the NTT pipeline
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x20
- **Default**: C.f. fields


#### Field Details

Register ntt_pbs contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| batch_pbs_nb      | 0 | 8 |BATCH_PBS_NB| Maximum number of PBS in the NTT pipe |
| total_pbs_nb      | 8 | 8 |TOTAL_PBS_NB| Maximum number of PBS stored in PEP buffer |



---


### Register info.ntt-modulo

- **Description**: Code associated to the NTT prime
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x24
- **Default**: MOD_NTT_NAME




---


### Register info.application

- **Description**: Code associated with the application
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x28
- **Default**: APPLICATION_NAME




---


### Register info.ks-structure

- **Description**: Key-switch structure parameters
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x2c
- **Default**: C.f. fields


#### Field Details

Register ks_structure contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| x      | 0 | 8 |LBX| Number of coefficients on X dimension |
| y      | 8 | 8 |LBY| Number of coefficients on Y dimension |
| z      | 16 | 8 |LBZ| Number of coefficients on Z dimension |



---


### Register info.ks-crypto-param

- **Description**: Key-switch crypto parameters
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x30
- **Default**: C.f. fields


#### Field Details

Register ks_crypto_param contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| mod_ksk_w      | 0 | 8 |MOD_KSK_W| Width of KSK modulo |
| ks_l      | 8 | 8 |KS_L| Number of KS decomposition level |
| ks_b      | 16 | 8 |KS_B_W| Width of KS decomposition base |



---


### Register info.regf-structure

- **Description**: Register file structure parameters
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x34
- **Default**: C.f. fields


#### Field Details

Register regf_structure contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| reg_nb      | 0 | 8 |REGF_REG_NB| Number of registers in regfile |
| coef_nb      | 8 | 8 |REGF_COEF_NB| Number of coefficients at regfile interface |



---


### Register info.isc-structure

- **Description**: Instruction scheduler structure parameters
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x38
- **Default**: C.f. fields


#### Field Details

Register isc_structure contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| depth      | 0 | 8 |ISC_DEPTH| Number of slots in ISC lookahead buffer. |
| min_iop_size      | 8 | 8 |MIN_IOP_SIZE| Minimum number of DOp per IOp to prevent sync_id overflow. |



---


### Register info.pe-properties

- **Description**: Processing elements parameters
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x3c
- **Default**: C.f. fields


#### Field Details

Register pe_properties contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| pea_regf_period      | 0 | 8 |PEA_REGF_PERIOD| Number of cycles between 2 consecutive data transfer between PEA and regfile |
| pem_regf_period      | 8 | 8 |PEM_REGF_PERIOD| Number of cycles between 2 consecutive data transfer between PEM and regfile |
| pep_regf_period      | 16 | 8 |PEP_REGF_PERIOD| Number of cycles between 2 consecutive data transfer between PEP and regfile |
| alu_nb      | 24 | 8 |PEA_ALU_NB| Number of coefficients processed in parallel in pe_alu |



---


### Register info.bsk-structure

- **Description**: BSK manager structure parameters
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x40
- **Default**: C.f. fields


#### Field Details

Register bsk_structure contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| bsk_cut_nb      | 8 | 8 |BSK_CUT_NB| BSK cut nb |



---


### Register info.ksk-structure

- **Description**: KSK manager structure parameters
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x44
- **Default**: C.f. fields


#### Field Details

Register ksk_structure contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| ksk_cut_nb      | 8 | 8 |KSK_CUT_NB| KSK cut nb |



---


### Register info.hbm-axi4-nb

- **Description**: Number of AXI4 connections to HBM
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x48
- **Default**: C.f. fields


#### Field Details

Register hbm_axi4_nb contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| bsk_pc      | 0 | 8 |BSK_PC| Number of HBM connections for BSK |
| ksk_pc      | 8 | 8 |KSK_PC| Number of HBM connections for KSK |
| pem_pc      | 16 | 8 |PEM_PC| Number of HBM connections for ciphertexts (PEM) |
| glwe_pc      | 24 | 8 |GLWE_PC| Number of HBM connections for GLWE |



---


### Register info.hbm-axi4-dataw-pem

- **Description**: Ciphertext HBM AXI4 connection data width
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x4c
- **Default**: AXI4_PEM_DATA_W




---


### Register info.hbm-axi4-dataw-glwe

- **Description**: GLWE HBM AXI4 connection data width
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x50
- **Default**: AXI4_GLWE_DATA_W




---


### Register info.hbm-axi4-dataw-bsk

- **Description**: BSK HBM AXI4 connection data width
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x54
- **Default**: AXI4_BSK_DATA_W




---


### Register info.hbm-axi4-dataw-ksk

- **Description**: KSK HBM AXI4 connection data width
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x58
- **Default**: AXI4_KSK_DATA_W




---




## Section hbm-axi4-addr-1in3

### Register Overview

Below is a summary of all the registers in the current section hbm_axi4_addr_1in3:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [ct_pc0_lsb](#register-hbm-axi4-addr-1in3ct-pc0-lsb) | 0x1000 | RW |  Address offset for each ciphertext HBM AXI4 connection |
| [ct_pc0_msb](#register-hbm-axi4-addr-1in3ct-pc0-msb) | 0x1004 | RW |  Address offset for each ciphertext HBM AXI4 connection |
| [ct_pc1_lsb](#register-hbm-axi4-addr-1in3ct-pc1-lsb) | 0x1008 | RW |  Address offset for each ciphertext HBM AXI4 connection |
| [ct_pc1_msb](#register-hbm-axi4-addr-1in3ct-pc1-msb) | 0x100c | RW |  Address offset for each ciphertext HBM AXI4 connection |
| [glwe_pc0_lsb](#register-hbm-axi4-addr-1in3glwe-pc0-lsb) | 0x1010 | RW |  Address offset for each GLWE HBM AXI4 connection |
| [glwe_pc0_msb](#register-hbm-axi4-addr-1in3glwe-pc0-msb) | 0x1014 | RW |  Address offset for each GLWE HBM AXI4 connection |
| [ksk_pc0_lsb](#register-hbm-axi4-addr-1in3ksk-pc0-lsb) | 0x1018 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc0_msb](#register-hbm-axi4-addr-1in3ksk-pc0-msb) | 0x101c | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc1_lsb](#register-hbm-axi4-addr-1in3ksk-pc1-lsb) | 0x1020 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc1_msb](#register-hbm-axi4-addr-1in3ksk-pc1-msb) | 0x1024 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc2_lsb](#register-hbm-axi4-addr-1in3ksk-pc2-lsb) | 0x1028 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc2_msb](#register-hbm-axi4-addr-1in3ksk-pc2-msb) | 0x102c | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc3_lsb](#register-hbm-axi4-addr-1in3ksk-pc3-lsb) | 0x1030 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc3_msb](#register-hbm-axi4-addr-1in3ksk-pc3-msb) | 0x1034 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc4_lsb](#register-hbm-axi4-addr-1in3ksk-pc4-lsb) | 0x1038 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc4_msb](#register-hbm-axi4-addr-1in3ksk-pc4-msb) | 0x103c | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc5_lsb](#register-hbm-axi4-addr-1in3ksk-pc5-lsb) | 0x1040 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc5_msb](#register-hbm-axi4-addr-1in3ksk-pc5-msb) | 0x1044 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc6_lsb](#register-hbm-axi4-addr-1in3ksk-pc6-lsb) | 0x1048 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc6_msb](#register-hbm-axi4-addr-1in3ksk-pc6-msb) | 0x104c | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc7_lsb](#register-hbm-axi4-addr-1in3ksk-pc7-lsb) | 0x1050 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc7_msb](#register-hbm-axi4-addr-1in3ksk-pc7-msb) | 0x1054 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc8_lsb](#register-hbm-axi4-addr-1in3ksk-pc8-lsb) | 0x1058 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc8_msb](#register-hbm-axi4-addr-1in3ksk-pc8-msb) | 0x105c | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc9_lsb](#register-hbm-axi4-addr-1in3ksk-pc9-lsb) | 0x1060 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc9_msb](#register-hbm-axi4-addr-1in3ksk-pc9-msb) | 0x1064 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc10_lsb](#register-hbm-axi4-addr-1in3ksk-pc10-lsb) | 0x1068 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc10_msb](#register-hbm-axi4-addr-1in3ksk-pc10-msb) | 0x106c | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc11_lsb](#register-hbm-axi4-addr-1in3ksk-pc11-lsb) | 0x1070 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc11_msb](#register-hbm-axi4-addr-1in3ksk-pc11-msb) | 0x1074 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc12_lsb](#register-hbm-axi4-addr-1in3ksk-pc12-lsb) | 0x1078 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc12_msb](#register-hbm-axi4-addr-1in3ksk-pc12-msb) | 0x107c | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc13_lsb](#register-hbm-axi4-addr-1in3ksk-pc13-lsb) | 0x1080 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc13_msb](#register-hbm-axi4-addr-1in3ksk-pc13-msb) | 0x1084 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc14_lsb](#register-hbm-axi4-addr-1in3ksk-pc14-lsb) | 0x1088 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc14_msb](#register-hbm-axi4-addr-1in3ksk-pc14-msb) | 0x108c | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc15_lsb](#register-hbm-axi4-addr-1in3ksk-pc15-lsb) | 0x1090 | RW |  Address offset for each KSK HBM AXI4 connection |
| [ksk_pc15_msb](#register-hbm-axi4-addr-1in3ksk-pc15-msb) | 0x1094 | RW |  Address offset for each KSK HBM AXI4 connection |
| [trc_pc0_lsb](#register-hbm-axi4-addr-1in3trc-pc0-lsb) | 0x1098 | RW |  Address offset for each trace HBM AXI4 connection |
| [trc_pc0_msb](#register-hbm-axi4-addr-1in3trc-pc0-msb) | 0x109c | RW |  Address offset for each trace HBM AXI4 connection |


---


### Register hbm-axi4-addr-1in3.ct-pc0-lsb

- **Description**: Address offset for each ciphertext HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1000
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ct-pc0-msb

- **Description**: Address offset for each ciphertext HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1004
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ct-pc1-lsb

- **Description**: Address offset for each ciphertext HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1008
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ct-pc1-msb

- **Description**: Address offset for each ciphertext HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x100c
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.glwe-pc0-lsb

- **Description**: Address offset for each GLWE HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1010
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.glwe-pc0-msb

- **Description**: Address offset for each GLWE HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1014
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc0-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1018
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc0-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x101c
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc1-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1020
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc1-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1024
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc2-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1028
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc2-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x102c
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc3-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1030
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc3-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1034
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc4-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1038
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc4-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x103c
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc5-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1040
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc5-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1044
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc6-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1048
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc6-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x104c
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc7-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1050
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc7-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1054
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc8-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1058
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc8-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x105c
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc9-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1060
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc9-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1064
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc10-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1068
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc10-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x106c
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc11-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1070
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc11-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1074
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc12-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1078
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc12-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x107c
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc13-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1080
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc13-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1084
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc14-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1088
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc14-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x108c
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc15-lsb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1090
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.ksk-pc15-msb

- **Description**: Address offset for each KSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1094
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.trc-pc0-lsb

- **Description**: Address offset for each trace HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x1098
- **Default**: 0




---


### Register hbm-axi4-addr-1in3.trc-pc0-msb

- **Description**: Address offset for each trace HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x109c
- **Default**: 0




---




## Section bpip

### Register Overview

Below is a summary of all the registers in the current section bpip:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [use](#register-bpipuse) | 0x2000 | RW |  (1) Use BPIP mode, (0) use IPIP mode (default) |
| [timeout](#register-bpiptimeout) | 0x2004 | RW |  Timeout for BPIP mode |


---


### Register bpip.use

- **Description**: (1) Use BPIP mode, (0) use IPIP mode (default)
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x2000
- **Default**: C.f. fields


#### Field Details

Register use contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| use_bpip      | 0 | 1 |1| use |
| use_opportunism      | 1 | 1 |0| use opportunistic PBS flush |



---


### Register bpip.timeout

- **Description**: Timeout for BPIP mode
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x2004
- **Default**: 4294967295




---




## Section keyswitch

### Register Overview

Below is a summary of all the registers in the current section keyswitch:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [config](#register-keyswitchconfig) | 0x3000 | RW |  (1) Use use modulus switching mean compensation. (default), (0) Don't use modulus switching mean compensation. |


---


### Register keyswitch.config

- **Description**: (1) Use use modulus switching mean compensation. (default), (0) Don't use modulus switching mean compensation.
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x3000
- **Default**: C.f. fields


#### Field Details

Register config contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| mod_switch_mean_comp      | 0 | 1 |1| Controls whether to use modulus switch mean compensation. |



---




## Section entry-prc-1in3

### Register Overview

Below is a summary of all the registers in the current section entry_prc_1in3:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [dummy_val0](#register-entry-prc-1in3dummy-val0) | 0x10000 | R. |  RTL version |
| [dummy_val1](#register-entry-prc-1in3dummy-val1) | 0x10004 | R. |  RTL version |
| [dummy_val2](#register-entry-prc-1in3dummy-val2) | 0x10008 | R. |  RTL version |
| [dummy_val3](#register-entry-prc-1in3dummy-val3) | 0x1000c | R. |  RTL version |


---


### Register entry-prc-1in3.dummy-val0

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x10000
- **Default**: 33686018




---


### Register entry-prc-1in3.dummy-val1

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x10004
- **Default**: 303174162




---


### Register entry-prc-1in3.dummy-val2

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x10008
- **Default**: 572662306




---


### Register entry-prc-1in3.dummy-val3

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x1000c
- **Default**: 842150450




---




## Section status-1in3

### Register Overview

Below is a summary of all the registers in the current section status_1in3:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [error](#register-status-1in3error) | 0x10010 | RW |  Error register (Could be reset by user) |


---


### Register status-1in3.error

- **Description**: Error register (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x10010
- **Default**: C.f. fields


#### Field Details

Register error contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| pbs      | 0 | 32 |0| HPU error part 1in3 |



---




## Section ksk-avail

### Register Overview

Below is a summary of all the registers in the current section ksk_avail:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [avail](#register-ksk-availavail) | 0x11000 | RW |  KSK available bit |
| [reset](#register-ksk-availreset) | 0x11004 | RW |  KSK reset sequence |


---


### Register ksk-avail.avail

- **Description**: KSK available bit
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x11000
- **Default**: C.f. fields


#### Field Details

Register avail contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| avail      | 0 | 1 |0| avail |



---


### Register ksk-avail.reset

- **Description**: KSK reset sequence
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x11004
- **Default**: C.f. fields


#### Field Details

Register reset contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| request      | 0 | 1 |0| request |
| done      | 31 | 1 |0| done |



---




## Section runtime-1in3

### Register Overview

Below is a summary of all the registers in the current section runtime_1in3:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [pep_cmux_loop](#register-runtime-1in3pep-cmux-loop) | 0x12000 | R. |  PEP: CMUX iteration loop number |
| [pep_pointer_0](#register-runtime-1in3pep-pointer-0) | 0x12004 | R. |  PEP: pointers (part 1) |
| [pep_pointer_1](#register-runtime-1in3pep-pointer-1) | 0x12008 | R. |  PEP: pointers (part 2) |
| [pep_pointer_2](#register-runtime-1in3pep-pointer-2) | 0x1200c | R. |  PEP: pointers (part 3) |
| [isc_latest_instruction_0](#register-runtime-1in3isc-latest-instruction-0) | 0x12010 | R. |  ISC: 4 latest instructions received ([0] is the most recent) |
| [isc_latest_instruction_1](#register-runtime-1in3isc-latest-instruction-1) | 0x12014 | R. |  ISC: 4 latest instructions received ([0] is the most recent) |
| [isc_latest_instruction_2](#register-runtime-1in3isc-latest-instruction-2) | 0x12018 | R. |  ISC: 4 latest instructions received ([0] is the most recent) |
| [isc_latest_instruction_3](#register-runtime-1in3isc-latest-instruction-3) | 0x1201c | R. |  ISC: 4 latest instructions received ([0] is the most recent) |
| [pep_seq_bpip_batch_cnt](#register-runtime-1in3pep-seq-bpip-batch-cnt) | 0x12020 | RW |  PEP: BPIP batch counter (Could be reset by user) |
| [pep_seq_bpip_batch_flush_cnt](#register-runtime-1in3pep-seq-bpip-batch-flush-cnt) | 0x12024 | RW |  PEP: BPIP batch triggered by a flush counter (Could be reset by user) |
| [pep_seq_bpip_batch_timeout_cnt](#register-runtime-1in3pep-seq-bpip-batch-timeout-cnt) | 0x12028 | RW |  PEP: BPIP batch triggered by a timeout counter (Could be reset by user) |
| [pep_seq_bpip_waiting_batch_cnt](#register-runtime-1in3pep-seq-bpip-waiting-batch-cnt) | 0x1202c | RW |  PEP: BPIP batch that waits the trigger counter (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_1](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-1) | 0x12030 | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_2](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-2) | 0x12034 | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_3](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-3) | 0x12038 | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_4](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-4) | 0x1203c | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_5](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-5) | 0x12040 | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_6](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-6) | 0x12044 | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_7](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-7) | 0x12048 | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_8](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-8) | 0x1204c | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_9](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-9) | 0x12050 | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_10](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-10) | 0x12054 | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_11](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-11) | 0x12058 | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_12](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-12) | 0x1205c | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_13](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-13) | 0x12060 | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_14](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-14) | 0x12064 | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_15](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-15) | 0x12068 | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_bpip_batch_filling_cnt_16](#register-runtime-1in3pep-seq-bpip-batch-filling-cnt-16) | 0x1206c | RW |  PEP: Count batch with filled with a given number of CT (Could be reset by user) |
| [pep_seq_ld_ack_cnt](#register-runtime-1in3pep-seq-ld-ack-cnt) | 0x12070 | RW |  PEP: load BLWE ack counter (Could be reset by user) |
| [pep_seq_cmux_not_full_batch_cnt](#register-runtime-1in3pep-seq-cmux-not-full-batch-cnt) | 0x12074 | RW |  PEP: not full batch CMUX counter (Could be reset by user) |
| [pep_seq_ipip_flush_cnt](#register-runtime-1in3pep-seq-ipip-flush-cnt) | 0x12078 | RW |  PEP: IPIP flush CMUX counter (Could be reset by user) |
| [pep_ldb_rcp_dur](#register-runtime-1in3pep-ldb-rcp-dur) | 0x1207c | RW |  PEP: load BLWE reception max duration (Could be reset by user) |
| [pep_ldg_req_dur](#register-runtime-1in3pep-ldg-req-dur) | 0x12080 | RW |  PEP: load GLWE request max duration (Could be reset by user) |
| [pep_ldg_rcp_dur](#register-runtime-1in3pep-ldg-rcp-dur) | 0x12084 | RW |  PEP: load GLWE reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc0](#register-runtime-1in3pep-load-ksk-rcp-dur-pc0) | 0x12088 | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc1](#register-runtime-1in3pep-load-ksk-rcp-dur-pc1) | 0x1208c | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc2](#register-runtime-1in3pep-load-ksk-rcp-dur-pc2) | 0x12090 | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc3](#register-runtime-1in3pep-load-ksk-rcp-dur-pc3) | 0x12094 | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc4](#register-runtime-1in3pep-load-ksk-rcp-dur-pc4) | 0x12098 | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc5](#register-runtime-1in3pep-load-ksk-rcp-dur-pc5) | 0x1209c | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc6](#register-runtime-1in3pep-load-ksk-rcp-dur-pc6) | 0x120a0 | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc7](#register-runtime-1in3pep-load-ksk-rcp-dur-pc7) | 0x120a4 | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc8](#register-runtime-1in3pep-load-ksk-rcp-dur-pc8) | 0x120a8 | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc9](#register-runtime-1in3pep-load-ksk-rcp-dur-pc9) | 0x120ac | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc10](#register-runtime-1in3pep-load-ksk-rcp-dur-pc10) | 0x120b0 | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc11](#register-runtime-1in3pep-load-ksk-rcp-dur-pc11) | 0x120b4 | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc12](#register-runtime-1in3pep-load-ksk-rcp-dur-pc12) | 0x120b8 | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc13](#register-runtime-1in3pep-load-ksk-rcp-dur-pc13) | 0x120bc | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc14](#register-runtime-1in3pep-load-ksk-rcp-dur-pc14) | 0x120c0 | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_load_ksk_rcp_dur_pc15](#register-runtime-1in3pep-load-ksk-rcp-dur-pc15) | 0x120c4 | RW |  PEP: load KSK slice reception max duration (Could be reset by user) |
| [pep_mmacc_sxt_rcp_dur](#register-runtime-1in3pep-mmacc-sxt-rcp-dur) | 0x120c8 | RW |  PEP: MMACC SXT reception duration (Could be reset by user) |
| [pep_mmacc_sxt_req_dur](#register-runtime-1in3pep-mmacc-sxt-req-dur) | 0x120cc | RW |  PEP: MMACC SXT request duration (Could be reset by user) |
| [pep_mmacc_sxt_cmd_wait_b_dur](#register-runtime-1in3pep-mmacc-sxt-cmd-wait-b-dur) | 0x120d0 | RW |  PEP: MMACC SXT command wait for b duration (Could be reset by user) |
| [pep_inst_cnt](#register-runtime-1in3pep-inst-cnt) | 0x120d4 | RW |  PEP: input instruction counter (Could be reset by user) |
| [pep_ack_cnt](#register-runtime-1in3pep-ack-cnt) | 0x120d8 | RW |  PEP: instruction acknowledge counter (Could be reset by user) |
| [pem_load_inst_cnt](#register-runtime-1in3pem-load-inst-cnt) | 0x120dc | RW |  PEM: load input instruction counter (Could be reset by user) |
| [pem_load_ack_cnt](#register-runtime-1in3pem-load-ack-cnt) | 0x120e0 | RW |  PEM: load instruction acknowledge counter (Could be reset by user) |
| [pem_store_inst_cnt](#register-runtime-1in3pem-store-inst-cnt) | 0x120e4 | RW |  PEM: store input instruction counter (Could be reset by user) |
| [pem_store_ack_cnt](#register-runtime-1in3pem-store-ack-cnt) | 0x120e8 | RW |  PEM: store instruction acknowledge counter (Could be reset by user) |
| [pea_inst_cnt](#register-runtime-1in3pea-inst-cnt) | 0x120ec | RW |  PEA: input instruction counter (Could be reset by user) |
| [pea_ack_cnt](#register-runtime-1in3pea-ack-cnt) | 0x120f0 | RW |  PEA: instruction acknowledge counter (Could be reset by user) |
| [isc_inst_cnt](#register-runtime-1in3isc-inst-cnt) | 0x120f4 | RW |  ISC: input instruction counter (Could be reset by user) |
| [isc_ack_cnt](#register-runtime-1in3isc-ack-cnt) | 0x120f8 | RW |  ISC: instruction acknowledge counter (Could be reset by user) |
| [pem_load_info_0_pc0_0](#register-runtime-1in3pem-load-info-0-pc0-0) | 0x120fc | R. |  PEM: load first data) |
| [pem_load_info_0_pc0_1](#register-runtime-1in3pem-load-info-0-pc0-1) | 0x12100 | R. |  PEM: load first data) |
| [pem_load_info_0_pc0_2](#register-runtime-1in3pem-load-info-0-pc0-2) | 0x12104 | R. |  PEM: load first data) |
| [pem_load_info_0_pc0_3](#register-runtime-1in3pem-load-info-0-pc0-3) | 0x12108 | R. |  PEM: load first data) |
| [pem_load_info_0_pc1_0](#register-runtime-1in3pem-load-info-0-pc1-0) | 0x1210c | R. |  PEM: load first data) |
| [pem_load_info_0_pc1_1](#register-runtime-1in3pem-load-info-0-pc1-1) | 0x12110 | R. |  PEM: load first data) |
| [pem_load_info_0_pc1_2](#register-runtime-1in3pem-load-info-0-pc1-2) | 0x12114 | R. |  PEM: load first data) |
| [pem_load_info_0_pc1_3](#register-runtime-1in3pem-load-info-0-pc1-3) | 0x12118 | R. |  PEM: load first data) |
| [pem_load_info_1_pc0_lsb](#register-runtime-1in3pem-load-info-1-pc0-lsb) | 0x1211c | R. |  PEM: load first address |
| [pem_load_info_1_pc0_msb](#register-runtime-1in3pem-load-info-1-pc0-msb) | 0x12120 | R. |  PEM: load first address |
| [pem_load_info_1_pc1_lsb](#register-runtime-1in3pem-load-info-1-pc1-lsb) | 0x12124 | R. |  PEM: load first address |
| [pem_load_info_1_pc1_msb](#register-runtime-1in3pem-load-info-1-pc1-msb) | 0x12128 | R. |  PEM: load first address |
| [pem_store_info_0](#register-runtime-1in3pem-store-info-0) | 0x1212c | R. |  PEM: store info 0) |
| [pem_store_info_1](#register-runtime-1in3pem-store-info-1) | 0x12130 | R. |  PEM: store info 1 |
| [pem_store_info_2](#register-runtime-1in3pem-store-info-2) | 0x12134 | R. |  PEM: store info 2 |
| [pem_store_info_3](#register-runtime-1in3pem-store-info-3) | 0x12138 | R. |  PEM: store info 3 |


---


### Register runtime-1in3.pep-cmux-loop

- **Description**: PEP: CMUX iteration loop number
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12000
- **Default**: C.f. fields


#### Field Details

Register pep_cmux_loop contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| br_loop      | 0 | 15 |0| PBS current BR-loop |
| br_loop_c      | 15 | 1 |0| PBS current BR-loop parity |
| ks_loop      | 16 | 15 |0| KS current KS-loop |
| ks_loop_c      | 31 | 1 |0| KS current KS-loop parity |



---


### Register runtime-1in3.pep-pointer-0

- **Description**: PEP: pointers (part 1)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12004
- **Default**: C.f. fields


#### Field Details

Register pep_pointer_0 contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| pool_rp      | 0 | 8 |0| PEP pool_rp |
| pool_wp      | 8 | 8 |0| PEP pool_wp |
| ldg_pt      | 16 | 8 |0| PEP ldg_pt |
| ldb_pt      | 24 | 8 |0| PEP ldb_pt |



---


### Register runtime-1in3.pep-pointer-1

- **Description**: PEP: pointers (part 2)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12008
- **Default**: C.f. fields


#### Field Details

Register pep_pointer_1 contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| ks_in_rp      | 0 | 8 |0| PEP ks_in_rp |
| ks_in_wp      | 8 | 8 |0| PEP ks_in_wp |
| ks_out_rp      | 16 | 8 |0| PEP ks_out_rp |
| ks_out_wp      | 24 | 8 |0| PEP ks_out_wp |



---


### Register runtime-1in3.pep-pointer-2

- **Description**: PEP: pointers (part 3)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x1200c
- **Default**: C.f. fields


#### Field Details

Register pep_pointer_2 contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| pbs_in_rp      | 0 | 8 |0| PEP pbs_in_rp |
| pbs_in_wp      | 8 | 8 |0| PEP pbs_in_wp |
| ipip_flush_last_pbs_in_loop      | 16 | 16 |0| PEP IPIP flush last pbs_in_loop |



---


### Register runtime-1in3.isc-latest-instruction-0

- **Description**: ISC: 4 latest instructions received ([0] is the most recent)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12010
- **Default**: 0




---


### Register runtime-1in3.isc-latest-instruction-1

- **Description**: ISC: 4 latest instructions received ([0] is the most recent)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12014
- **Default**: 0




---


### Register runtime-1in3.isc-latest-instruction-2

- **Description**: ISC: 4 latest instructions received ([0] is the most recent)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12018
- **Default**: 0




---


### Register runtime-1in3.isc-latest-instruction-3

- **Description**: ISC: 4 latest instructions received ([0] is the most recent)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x1201c
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-cnt

- **Description**: PEP: BPIP batch counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12020
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-flush-cnt

- **Description**: PEP: BPIP batch triggered by a flush counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12024
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-timeout-cnt

- **Description**: PEP: BPIP batch triggered by a timeout counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12028
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-waiting-batch-cnt

- **Description**: PEP: BPIP batch that waits the trigger counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x1202c
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-1

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12030
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-2

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12034
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-3

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12038
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-4

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x1203c
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-5

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12040
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-6

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12044
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-7

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12048
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-8

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x1204c
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-9

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12050
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-10

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12054
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-11

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12058
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-12

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x1205c
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-13

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12060
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-14

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12064
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-15

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12068
- **Default**: 0




---


### Register runtime-1in3.pep-seq-bpip-batch-filling-cnt-16

- **Description**: PEP: Count batch with filled with a given number of CT (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x1206c
- **Default**: 0




---


### Register runtime-1in3.pep-seq-ld-ack-cnt

- **Description**: PEP: load BLWE ack counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12070
- **Default**: 0




---


### Register runtime-1in3.pep-seq-cmux-not-full-batch-cnt

- **Description**: PEP: not full batch CMUX counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12074
- **Default**: 0




---


### Register runtime-1in3.pep-seq-ipip-flush-cnt

- **Description**: PEP: IPIP flush CMUX counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12078
- **Default**: 0




---


### Register runtime-1in3.pep-ldb-rcp-dur

- **Description**: PEP: load BLWE reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x1207c
- **Default**: 0




---


### Register runtime-1in3.pep-ldg-req-dur

- **Description**: PEP: load GLWE request max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12080
- **Default**: 0




---


### Register runtime-1in3.pep-ldg-rcp-dur

- **Description**: PEP: load GLWE reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12084
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc0

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12088
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc1

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x1208c
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc2

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12090
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc3

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12094
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc4

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x12098
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc5

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x1209c
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc6

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120a0
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc7

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120a4
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc8

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120a8
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc9

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120ac
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc10

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120b0
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc11

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120b4
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc12

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120b8
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc13

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120bc
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc14

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120c0
- **Default**: 0




---


### Register runtime-1in3.pep-load-ksk-rcp-dur-pc15

- **Description**: PEP: load KSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120c4
- **Default**: 0




---


### Register runtime-1in3.pep-mmacc-sxt-rcp-dur

- **Description**: PEP: MMACC SXT reception duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120c8
- **Default**: 0




---


### Register runtime-1in3.pep-mmacc-sxt-req-dur

- **Description**: PEP: MMACC SXT request duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120cc
- **Default**: 0




---


### Register runtime-1in3.pep-mmacc-sxt-cmd-wait-b-dur

- **Description**: PEP: MMACC SXT command wait for b duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120d0
- **Default**: 0




---


### Register runtime-1in3.pep-inst-cnt

- **Description**: PEP: input instruction counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120d4
- **Default**: 0




---


### Register runtime-1in3.pep-ack-cnt

- **Description**: PEP: instruction acknowledge counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120d8
- **Default**: 0




---


### Register runtime-1in3.pem-load-inst-cnt

- **Description**: PEM: load input instruction counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120dc
- **Default**: 0




---


### Register runtime-1in3.pem-load-ack-cnt

- **Description**: PEM: load instruction acknowledge counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120e0
- **Default**: 0




---


### Register runtime-1in3.pem-store-inst-cnt

- **Description**: PEM: store input instruction counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120e4
- **Default**: 0




---


### Register runtime-1in3.pem-store-ack-cnt

- **Description**: PEM: store instruction acknowledge counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120e8
- **Default**: 0




---


### Register runtime-1in3.pea-inst-cnt

- **Description**: PEA: input instruction counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120ec
- **Default**: 0




---


### Register runtime-1in3.pea-ack-cnt

- **Description**: PEA: instruction acknowledge counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120f0
- **Default**: 0




---


### Register runtime-1in3.isc-inst-cnt

- **Description**: ISC: input instruction counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120f4
- **Default**: 0




---


### Register runtime-1in3.isc-ack-cnt

- **Description**: ISC: instruction acknowledge counter (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x120f8
- **Default**: 0




---


### Register runtime-1in3.pem-load-info-0-pc0-0

- **Description**: PEM: load first data)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x120fc
- **Default**: 0




---


### Register runtime-1in3.pem-load-info-0-pc0-1

- **Description**: PEM: load first data)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12100
- **Default**: 0




---


### Register runtime-1in3.pem-load-info-0-pc0-2

- **Description**: PEM: load first data)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12104
- **Default**: 0




---


### Register runtime-1in3.pem-load-info-0-pc0-3

- **Description**: PEM: load first data)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12108
- **Default**: 0




---


### Register runtime-1in3.pem-load-info-0-pc1-0

- **Description**: PEM: load first data)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x1210c
- **Default**: 0




---


### Register runtime-1in3.pem-load-info-0-pc1-1

- **Description**: PEM: load first data)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12110
- **Default**: 0




---


### Register runtime-1in3.pem-load-info-0-pc1-2

- **Description**: PEM: load first data)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12114
- **Default**: 0




---


### Register runtime-1in3.pem-load-info-0-pc1-3

- **Description**: PEM: load first data)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12118
- **Default**: 0




---


### Register runtime-1in3.pem-load-info-1-pc0-lsb

- **Description**: PEM: load first address
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x1211c
- **Default**: 0




---


### Register runtime-1in3.pem-load-info-1-pc0-msb

- **Description**: PEM: load first address
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12120
- **Default**: 0




---


### Register runtime-1in3.pem-load-info-1-pc1-lsb

- **Description**: PEM: load first address
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12124
- **Default**: 0




---


### Register runtime-1in3.pem-load-info-1-pc1-msb

- **Description**: PEM: load first address
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12128
- **Default**: 0




---


### Register runtime-1in3.pem-store-info-0

- **Description**: PEM: store info 0)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x1212c
- **Default**: C.f. fields


#### Field Details

Register pem_store_info_0 contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| cmd_vld      | 0 | 1 |0| PEM_ST cmd vld |
| cmd_rdy      | 1 | 1 |0| PEM_ST cmd rdy |
| pem_regf_rd_req_vld      | 2 | 1 |0| PEM_ST pem_regf_rd_req_vld |
| pem_regf_rd_req_rdy      | 3 | 1 |0| PEM_ST pem_regf_rd_req_rdy |
| brsp_fifo_in_vld      | 4 | 4 |0| PEM_ST brsp_fifo_in_vld |
| brsp_fifo_in_rdy      | 8 | 4 |0| PEM_ST brsp_fifo_in_rdy |
| rcp_fifo_in_vld      | 12 | 4 |0| PEM_ST rcp_fifo_in_vld |
| rcp_fifo_in_rdy      | 16 | 4 |0| PEM_ST rcp_fifo_in_rdy |
| r2_axi_vld      | 20 | 4 |0| PEM_ST r2_axi_vld |
| r2_axi_rdy      | 24 | 4 |0| PEM_ST r2_axi_rdy |
| c0_enough_location      | 28 | 4 |0| PEM_ST c0_enough_location |



---


### Register runtime-1in3.pem-store-info-1

- **Description**: PEM: store info 1
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12130
- **Default**: C.f. fields


#### Field Details

Register pem_store_info_1 contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| s0_cmd_vld      | 0 | 4 |0| PEM_ST s0_cmd_vld |
| s0_cmd_rdy      | 4 | 4 |0| PEM_ST s0_cmd_rdy |
| m_axi_bvalid      | 8 | 4 |0| PEM_ST m_axi_bvalid |
| m_axi_bready      | 12 | 4 |0| PEM_ST m_axi_bready |
| m_axi_wvalid      | 16 | 4 |0| PEM_ST m_axi_wvalid |
| m_axi_wready      | 20 | 4 |0| PEM_ST m_axi_wready |
| m_axi_awvalid      | 24 | 4 |0| PEM_ST m_axi_awvalid |
| m_axi_awready      | 28 | 4 |0| PEM_ST m_axi_awready |



---


### Register runtime-1in3.pem-store-info-2

- **Description**: PEM: store info 2
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12134
- **Default**: C.f. fields


#### Field Details

Register pem_store_info_2 contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| c0_free_loc_cnt      | 0 | 16 |0| PEM_ST c0_free_loc_cnt |
| brsp_bresp_cnt      | 16 | 16 |0| PEM_ST brsp_bresp_cnt |



---


### Register runtime-1in3.pem-store-info-3

- **Description**: PEM: store info 3
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x12138
- **Default**: C.f. fields


#### Field Details

Register pem_store_info_3 contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| brsp_ack_seen      | 0 | 16 |0| PEM_ST brsp_ack_seen |
| c0_cmd_cnt      | 16 | 8 |0| PEM_ST c0_cmd_cnt |



---




## Section entry-cfg-3in3

### Register Overview

Below is a summary of all the registers in the current section entry_cfg_3in3:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [dummy_val0](#register-entry-cfg-3in3dummy-val0) | 0x20000 | R. |  RTL version |
| [dummy_val1](#register-entry-cfg-3in3dummy-val1) | 0x20004 | R. |  RTL version |
| [dummy_val2](#register-entry-cfg-3in3dummy-val2) | 0x20008 | R. |  RTL version |
| [dummy_val3](#register-entry-cfg-3in3dummy-val3) | 0x2000c | R. |  RTL version |


---


### Register entry-cfg-3in3.dummy-val0

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x20000
- **Default**: 50529027




---


### Register entry-cfg-3in3.dummy-val1

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x20004
- **Default**: 320017171




---


### Register entry-cfg-3in3.dummy-val2

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x20008
- **Default**: 589505315




---


### Register entry-cfg-3in3.dummy-val3

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x2000c
- **Default**: 858993459




---




## Section hbm-axi4-addr-3in3

### Register Overview

Below is a summary of all the registers in the current section hbm_axi4_addr_3in3:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [bsk_pc0_lsb](#register-hbm-axi4-addr-3in3bsk-pc0-lsb) | 0x20010 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc0_msb](#register-hbm-axi4-addr-3in3bsk-pc0-msb) | 0x20014 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc1_lsb](#register-hbm-axi4-addr-3in3bsk-pc1-lsb) | 0x20018 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc1_msb](#register-hbm-axi4-addr-3in3bsk-pc1-msb) | 0x2001c | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc2_lsb](#register-hbm-axi4-addr-3in3bsk-pc2-lsb) | 0x20020 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc2_msb](#register-hbm-axi4-addr-3in3bsk-pc2-msb) | 0x20024 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc3_lsb](#register-hbm-axi4-addr-3in3bsk-pc3-lsb) | 0x20028 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc3_msb](#register-hbm-axi4-addr-3in3bsk-pc3-msb) | 0x2002c | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc4_lsb](#register-hbm-axi4-addr-3in3bsk-pc4-lsb) | 0x20030 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc4_msb](#register-hbm-axi4-addr-3in3bsk-pc4-msb) | 0x20034 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc5_lsb](#register-hbm-axi4-addr-3in3bsk-pc5-lsb) | 0x20038 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc5_msb](#register-hbm-axi4-addr-3in3bsk-pc5-msb) | 0x2003c | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc6_lsb](#register-hbm-axi4-addr-3in3bsk-pc6-lsb) | 0x20040 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc6_msb](#register-hbm-axi4-addr-3in3bsk-pc6-msb) | 0x20044 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc7_lsb](#register-hbm-axi4-addr-3in3bsk-pc7-lsb) | 0x20048 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc7_msb](#register-hbm-axi4-addr-3in3bsk-pc7-msb) | 0x2004c | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc8_lsb](#register-hbm-axi4-addr-3in3bsk-pc8-lsb) | 0x20050 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc8_msb](#register-hbm-axi4-addr-3in3bsk-pc8-msb) | 0x20054 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc9_lsb](#register-hbm-axi4-addr-3in3bsk-pc9-lsb) | 0x20058 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc9_msb](#register-hbm-axi4-addr-3in3bsk-pc9-msb) | 0x2005c | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc10_lsb](#register-hbm-axi4-addr-3in3bsk-pc10-lsb) | 0x20060 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc10_msb](#register-hbm-axi4-addr-3in3bsk-pc10-msb) | 0x20064 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc11_lsb](#register-hbm-axi4-addr-3in3bsk-pc11-lsb) | 0x20068 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc11_msb](#register-hbm-axi4-addr-3in3bsk-pc11-msb) | 0x2006c | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc12_lsb](#register-hbm-axi4-addr-3in3bsk-pc12-lsb) | 0x20070 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc12_msb](#register-hbm-axi4-addr-3in3bsk-pc12-msb) | 0x20074 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc13_lsb](#register-hbm-axi4-addr-3in3bsk-pc13-lsb) | 0x20078 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc13_msb](#register-hbm-axi4-addr-3in3bsk-pc13-msb) | 0x2007c | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc14_lsb](#register-hbm-axi4-addr-3in3bsk-pc14-lsb) | 0x20080 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc14_msb](#register-hbm-axi4-addr-3in3bsk-pc14-msb) | 0x20084 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc15_lsb](#register-hbm-axi4-addr-3in3bsk-pc15-lsb) | 0x20088 | RW |  Address offset for each BSK HBM AXI4 connection |
| [bsk_pc15_msb](#register-hbm-axi4-addr-3in3bsk-pc15-msb) | 0x2008c | RW |  Address offset for each BSK HBM AXI4 connection |


---


### Register hbm-axi4-addr-3in3.bsk-pc0-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20010
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc0-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20014
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc1-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20018
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc1-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x2001c
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc2-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20020
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc2-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20024
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc3-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20028
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc3-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x2002c
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc4-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20030
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc4-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20034
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc5-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20038
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc5-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x2003c
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc6-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20040
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc6-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20044
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc7-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20048
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc7-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x2004c
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc8-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20050
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc8-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20054
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc9-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20058
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc9-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x2005c
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc10-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20060
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc10-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20064
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc11-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20068
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc11-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x2006c
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc12-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20070
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc12-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20074
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc13-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20078
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc13-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x2007c
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc14-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20080
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc14-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20084
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc15-lsb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x20088
- **Default**: 0




---


### Register hbm-axi4-addr-3in3.bsk-pc15-msb

- **Description**: Address offset for each BSK HBM AXI4 connection
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x2008c
- **Default**: 0




---




## Section hpu-reset

### Register Overview

Below is a summary of all the registers in the current section hpu_reset:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [trigger](#register-hpu-resettrigger) | 0x20100 | RW |  A soft reset for the whole HPU reconfigurable logic |


---


### Register hpu-reset.trigger

- **Description**: A soft reset for the whole HPU reconfigurable logic
- **Owner**: Kernel
- **Read Access**: ReadNotify
- **Write Access**: WriteNotify
- **Offset**: 0x20100
- **Default**: C.f. fields


#### Field Details

Register trigger contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| request      | 0 | 1 |0| request |
| done      | 31 | 1 |0| done |



---




## Section entry-prc-3in3

### Register Overview

Below is a summary of all the registers in the current section entry_prc_3in3:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [dummy_val0](#register-entry-prc-3in3dummy-val0) | 0x30000 | R. |  RTL version |
| [dummy_val1](#register-entry-prc-3in3dummy-val1) | 0x30004 | R. |  RTL version |
| [dummy_val2](#register-entry-prc-3in3dummy-val2) | 0x30008 | R. |  RTL version |
| [dummy_val3](#register-entry-prc-3in3dummy-val3) | 0x3000c | R. |  RTL version |


---


### Register entry-prc-3in3.dummy-val0

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x30000
- **Default**: 67372036




---


### Register entry-prc-3in3.dummy-val1

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x30004
- **Default**: 336860180




---


### Register entry-prc-3in3.dummy-val2

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x30008
- **Default**: 606348324




---


### Register entry-prc-3in3.dummy-val3

- **Description**: RTL version
- **Owner**: Parameter
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x3000c
- **Default**: 875836468




---




## Section status-3in3

### Register Overview

Below is a summary of all the registers in the current section status_3in3:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [error](#register-status-3in3error) | 0x30010 | RW |  Error register (Could be reset by user) |


---


### Register status-3in3.error

- **Description**: Error register (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x30010
- **Default**: C.f. fields


#### Field Details

Register error contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| pbs      | 0 | 32 |0| HPU error part 3in3 |



---




## Section bsk-avail

### Register Overview

Below is a summary of all the registers in the current section bsk_avail:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [avail](#register-bsk-availavail) | 0x31000 | RW |  BSK available bit |
| [reset](#register-bsk-availreset) | 0x31004 | RW |  BSK reset sequence |


---


### Register bsk-avail.avail

- **Description**: BSK available bit
- **Owner**: User
- **Read Access**: Read
- **Write Access**: Write
- **Offset**: 0x31000
- **Default**: C.f. fields


#### Field Details

Register avail contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| avail      | 0 | 1 |0| avail |



---


### Register bsk-avail.reset

- **Description**: BSK reset sequence
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x31004
- **Default**: C.f. fields


#### Field Details

Register reset contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| request      | 0 | 1 |0| request |
| done      | 31 | 1 |0| done |



---




## Section runtime-3in3

### Register Overview

Below is a summary of all the registers in the current section runtime_3in3:

| Name             | Offset | Access | Description |
|-----------------:|:------:|:------:|:------------|
| [pep_load_bsk_rcp_dur_pc0](#register-runtime-3in3pep-load-bsk-rcp-dur-pc0) | 0x32000 | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc1](#register-runtime-3in3pep-load-bsk-rcp-dur-pc1) | 0x32004 | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc2](#register-runtime-3in3pep-load-bsk-rcp-dur-pc2) | 0x32008 | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc3](#register-runtime-3in3pep-load-bsk-rcp-dur-pc3) | 0x3200c | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc4](#register-runtime-3in3pep-load-bsk-rcp-dur-pc4) | 0x32010 | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc5](#register-runtime-3in3pep-load-bsk-rcp-dur-pc5) | 0x32014 | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc6](#register-runtime-3in3pep-load-bsk-rcp-dur-pc6) | 0x32018 | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc7](#register-runtime-3in3pep-load-bsk-rcp-dur-pc7) | 0x3201c | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc8](#register-runtime-3in3pep-load-bsk-rcp-dur-pc8) | 0x32020 | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc9](#register-runtime-3in3pep-load-bsk-rcp-dur-pc9) | 0x32024 | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc10](#register-runtime-3in3pep-load-bsk-rcp-dur-pc10) | 0x32028 | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc11](#register-runtime-3in3pep-load-bsk-rcp-dur-pc11) | 0x3202c | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc12](#register-runtime-3in3pep-load-bsk-rcp-dur-pc12) | 0x32030 | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc13](#register-runtime-3in3pep-load-bsk-rcp-dur-pc13) | 0x32034 | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc14](#register-runtime-3in3pep-load-bsk-rcp-dur-pc14) | 0x32038 | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_load_bsk_rcp_dur_pc15](#register-runtime-3in3pep-load-bsk-rcp-dur-pc15) | 0x3203c | RW |  PEP: load BSK slice reception max duration (Could be reset by user) |
| [pep_bskif_req_info_0](#register-runtime-3in3pep-bskif-req-info-0) | 0x32040 | R. |  PEP: BSK_IF: requester info 0 |
| [pep_bskif_req_info_1](#register-runtime-3in3pep-bskif-req-info-1) | 0x32044 | R. |  PEP: BSK_IF: requester info 0 |


---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc0

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x32000
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc1

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x32004
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc2

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x32008
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc3

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x3200c
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc4

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x32010
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc5

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x32014
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc6

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x32018
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc7

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x3201c
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc8

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x32020
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc9

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x32024
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc10

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x32028
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc11

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x3202c
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc12

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x32030
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc13

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x32034
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc14

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x32038
- **Default**: 0




---


### Register runtime-3in3.pep-load-bsk-rcp-dur-pc15

- **Description**: PEP: load BSK slice reception max duration (Could be reset by user)
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: WriteNotify
- **Offset**: 0x3203c
- **Default**: 0




---


### Register runtime-3in3.pep-bskif-req-info-0

- **Description**: PEP: BSK_IF: requester info 0
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x32040
- **Default**: C.f. fields


#### Field Details

Register pep_bskif_req_info_0 contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| req_br_loop_rp      | 0 | 16 |0| PEP BSK_IF requester BSK read pointer |
| req_br_loop_wp      | 16 | 16 |0| PEP BSK_IF requester BSK write pointer |



---


### Register runtime-3in3.pep-bskif-req-info-1

- **Description**: PEP: BSK_IF: requester info 0
- **Owner**: Kernel
- **Read Access**: Read
- **Write Access**: None
- **Offset**: 0x32044
- **Default**: C.f. fields


#### Field Details

Register pep_bskif_req_info_1 contains following Sub-fields:

| Field Name | Offset_b | Size_b | Default      | Description   |
|-----------:|:--------:|:------:|:------------:|:--------------|
| req_prf_br_loop      | 0 | 16 |0| PEP BSK_IF requester BSK prefetch pointer |
| req_parity      | 16 | 1 |0| PEP BSK_IF requester BSK pointer parity |
| req_assigned      | 31 | 1 |0| PEP BSK_IF requester assignment |



---




