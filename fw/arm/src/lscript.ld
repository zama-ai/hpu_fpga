/**
 * SPDX-License-Identifier: MIT
 * Copyright (C) 2023 Xilinx, Inc. All rights reserved.
 */

_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0xA00000;
_HEAP_SIZE = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0xA00000;

_ABORT_STACK_SIZE = DEFINED(_ABORT_STACK_SIZE) ? _ABORT_STACK_SIZE : 1024;
_SUPERVISOR_STACK_SIZE = DEFINED(_SUPERVISOR_STACK_SIZE) ? _SUPERVISOR_STACK_SIZE : 2048;
_IRQ_STACK_SIZE = DEFINED(_IRQ_STACK_SIZE) ? _IRQ_STACK_SIZE : 1024;
_FIQ_STACK_SIZE = DEFINED(_FIQ_STACK_SIZE) ? _FIQ_STACK_SIZE : 1024;
_UNDEF_STACK_SIZE = DEFINED(_UNDEF_STACK_SIZE) ? _UNDEF_STACK_SIZE : 1024;

/* Define Memories in the system */

MEMORY
{
   blp_cips_pspmc_0_psv_r5_tcm_ram_0_psv_r5_tcm_ram_0 : ORIGIN = 0x0, LENGTH = 0x10000
   blp_cips_pspmc_0_psv_r5_0_btcm_psv_r5_0_btcm : ORIGIN = 0x20000, LENGTH = 0x10000
   blp_shell_utils_remap_0_mem2 : ORIGIN = 0x20108000000, LENGTH = 0x8000000
   ulp_plram_ctrl_Mem0 : ORIGIN = 0x20204000000, LENGTH = 0x20000
   blp_shell_utils_remap_1_mem0 : ORIGIN = 0x20206000000, LENGTH = 0x1000000
   blp_axi_noc_mc_C0_DDR_LOW0x4 : ORIGIN = 0x40000000, LENGTH = 0x3E800000
   blp_axi_noc_mc_C0_DDR_LOW2x4 : ORIGIN = 0xC080000000, LENGTH = 0x380000000
   blp_cips_pspmc_0_psv_pmc_ram_psv_pmc_ram : ORIGIN = 0xF2000000, LENGTH = 0x20000
   blp_cips_pspmc_0_psv_r5_0_instruction_cache_psv_r5_0_instruction_cache : ORIGIN = 0xFFE40000, LENGTH = 0x10000
   blp_cips_pspmc_0_psv_r5_0_data_cache_psv_r5_0_data_cache : ORIGIN = 0xFFE50000, LENGTH = 0x10000
   blp_cips_pspmc_0_psv_r5_1_instruction_cache_psv_r5_1_instruction_cache : ORIGIN = 0xFFEC0000, LENGTH = 0x10000
   blp_cips_pspmc_0_psv_r5_1_data_cache_psv_r5_1_data_cache : ORIGIN = 0xFFED0000, LENGTH = 0x10000
   blp_cips_pspmc_0_psv_ocm_ram_0_psv_ocm_ram_0 : ORIGIN = 0xFFFC0000, LENGTH = 0x40000
}

/* Specify the default entry point to the program */

ENTRY(_boot)

/* Define the sections, and where they are mapped in memory */

SECTIONS
{
.vectors : {
   KEEP (*(.vectors))
   *(.boot)
} > blp_cips_pspmc_0_psv_r5_tcm_ram_0_psv_r5_tcm_ram_0

.bootdata : {
   *(.bootdata)
} > blp_cips_pspmc_0_psv_r5_tcm_ram_0_psv_r5_tcm_ram_0

.text : {
   *(.text)
   *(.text.*)
   *(.gnu.linkonce.t.*)
   *(.plt)
   *(.gnu_warning)
   *(.gcc_execpt_table)
   *(.glue_7)
   *(.glue_7t)
   *(.vfp11_veneer)
   *(.ARM.extab)
   *(.gnu.linkonce.armextab.*)
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.init : {
   KEEP (*(.init))
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.fini : {
   KEEP (*(.fini))
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.interp : {
   KEEP (*(.interp))
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.note-ABI-tag : {
   KEEP (*(.note-ABI-tag))
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.note.gnu.build-id : {
   KEEP (*(.note.gnu.build-id))
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.rodata : {
   __rodata_start = .;
   *(.rodata)
   *(.rodata.*)
   *(.gnu.linkonce.r.*)
   __rodata_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.rodata1 : {
   __rodata1_start = .;
   *(.rodata1)
   *(.rodata1.*)
   __rodata1_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.sdata2 : {
   __sdata2_start = .;
   *(.sdata2)
   *(.sdata2.*)
   *(.gnu.linkonce.s2.*)
   __sdata2_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.sbss2 : {
   __sbss2_start = .;
   *(.sbss2)
   *(.sbss2.*)
   *(.gnu.linkonce.sb2.*)
   __sbss2_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.data : {
   __data_start = .;
   *(.data)
   *(.data.*)
   *(.gnu.linkonce.d.*)
   *(.jcr)
   *(.got)
   *(.got.plt)
   __data_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.data1 : {
   __data1_start = .;
   *(.data1)
   *(.data1.*)
   __data1_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.got : {
   *(.got)
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.ctors : {
   __CTOR_LIST__ = .;
   ___CTORS_LIST___ = .;
   KEEP (*crtbegin.o(.ctors))
   KEEP (*(EXCLUDE_FILE(*crtend.o) .ctors))
   KEEP (*(SORT(.ctors.*)))
   KEEP (*(.ctors))
   __CTOR_END__ = .;
   ___CTORS_END___ = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.dtors : {
   __DTOR_LIST__ = .;
   ___DTORS_LIST___ = .;
   KEEP (*crtbegin.o(.dtors))
   KEEP (*(EXCLUDE_FILE(*crtend.o) .dtors))
   KEEP (*(SORT(.dtors.*)))
   KEEP (*(.dtors))
   __DTOR_END__ = .;
   ___DTORS_END___ = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.fixup : {
   __fixup_start = .;
   *(.fixup)
   __fixup_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.eh_frame : {
   *(.eh_frame)
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.eh_framehdr : {
   __eh_framehdr_start = .;
   *(.eh_framehdr)
   __eh_framehdr_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.gcc_except_table : {
   *(.gcc_except_table)
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.mmu_tbl (ALIGN(16384)) : {
   __mmu_tbl_start = .;
   *(.mmu_tbl)
   __mmu_tbl_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.ARM.exidx : {
   __exidx_start = .;
   *(.ARM.exidx*)
   *(.gnu.linkonce.armexidix.*.*)
   __exidx_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.preinit_array : {
   __preinit_array_start = .;
   KEEP (*(SORT(.preinit_array.*)))
   KEEP (*(.preinit_array))
   __preinit_array_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.init_array : {
   __init_array_start = .;
   KEEP (*(SORT(.init_array.*)))
   KEEP (*(.init_array))
   __init_array_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.fini_array : {
   __fini_array_start = .;
   KEEP (*(SORT(.fini_array.*)))
   KEEP (*(.fini_array))
   __fini_array_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.ARM.attributes : {
   __ARM.attributes_start = .;
   *(.ARM.attributes)
   __ARM.attributes_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.sdata : {
   __sdata_start = .;
   *(.sdata)
   *(.sdata.*)
   *(.gnu.linkonce.s.*)
   __sdata_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.sbss (NOLOAD) : {
   __sbss_start = .;
   *(.sbss)
   *(.sbss.*)
   *(.gnu.linkonce.sb.*)
   __sbss_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.tdata : {
   __tdata_start = .;
   *(.tdata)
   *(.tdata.*)
   *(.gnu.linkonce.td.*)
   __tdata_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.tbss : {
   __tbss_start = .;
   *(.tbss)
   *(.tbss.*)
   *(.gnu.linkonce.tb.*)
   __tbss_end = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.bss (NOLOAD) : {
   . = ALIGN(4);
   __bss_start__ = .;
   *(.bss)
   *(.bss.*)
   *(.gnu.linkonce.b.*)
   *(COMMON)
   . = ALIGN(4);
   __bss_end__ = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

_SDA_BASE_ = __sdata_start + ((__sbss_end - __sdata_start) / 2 );

_SDA2_BASE_ = __sdata2_start + ((__sbss2_end - __sdata2_start) / 2 );

/* Generate Stack and Heap definitions */

.heap (NOLOAD) : {
   . = ALIGN(16);
   _heap = .;
   HeapBase = .;
   _heap_start = .;
   . += _HEAP_SIZE;
   _heap_end = .;
   HeapLimit = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

.stack (NOLOAD) : {
   . = ALIGN(16);
   _stack_end = .;
   . += _STACK_SIZE;
   _stack = .;
   __stack = _stack;
   . = ALIGN(16);
   _irq_stack_end = .;
   . += _IRQ_STACK_SIZE;
   __irq_stack = .;
   _supervisor_stack_end = .;
   . += _SUPERVISOR_STACK_SIZE;
   . = ALIGN(16);
   __supervisor_stack = .;
   _abort_stack_end = .;
   . += _ABORT_STACK_SIZE;
   . = ALIGN(16);
   __abort_stack = .;
   _fiq_stack_end = .;
   . += _FIQ_STACK_SIZE;
   . = ALIGN(16);
   __fiq_stack = .;
   _undef_stack_end = .;
   . += _UNDEF_STACK_SIZE;
   . = ALIGN(16);
   __undef_stack = .;
} > blp_axi_noc_mc_C0_DDR_LOW0x4

_end = .;
}


