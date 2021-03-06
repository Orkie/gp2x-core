/*--------------------------------------------------------------------------------
	This Source Code Form is subject to the terms of the Mozilla Public License,
	v. 2.0. If a copy of the MPL was not distributed with this file, You can
	obtain one at https://mozilla.org/MPL/2.0/.
--------------------------------------------------------------------------------*/

    .section	".crt0","ax"
	.code 32
	.align
	.global _start, _undefined_instruction, _software_interrupt, _prefetch_abort, _data_abort, _not_used, _irq, _fiq

        .set  Mode_USR, 0x10
        .set  Mode_FIQ, 0x11
        .set  Mode_IRQ, 0x12
        .set  Mode_SVC, 0x13
        .set  Mode_ABT, 0x17
        .set  Mode_UND, 0x1B
        .set  Mode_SYS, 0x1F

        .equ  I_Bit, 0x80
        .equ  F_Bit, 0x40	

@---------------------------------------------------------------------------------
_start:
@---------------------------------------------------------------------------------
	b       _start2
        ldr     pc, _undefined_instruction
        ldr     pc, _software_interrupt
        ldr     pc, _prefetch_abort
        ldr     pc, _data_abort
        ldr     pc, _not_used
        ldr     pc, _irq
        ldr     pc, _fiq

_undefined_instruction: .word undefined_instruction
_software_interrupt:    .word software_interrupt
_prefetch_abort:        .word prefetch_abort
_data_abort:            .word data_abort
_not_used:              .word not_used
_irq:                   .word irq
_fiq:                   .word fiq
	.balignl 16,0xdeadbeef
	.long __params_addr
	.long __params_length
	
@---------------------------------------------------------------------------------
@ AXF addresses
@---------------------------------------------------------------------------------

_text_start:
	.word   __text_start
_ro_end:
	.word   __ro_end
_data_start:
	.word   __data_start
	.word   __bss_end
_bss_start:
	.word   __bss_start
_bss_end:
	.word   __bss_end

undefined_instruction:
	subs pc,lr,#4
	
software_interrupt:
	subs pc,lr,#4
	
prefetch_abort:
	subs pc,lr,#4
	
data_abort:
	subs pc,lr,#4
	
not_used:
	subs pc,lr,#4
	
irq:
	subs pc,lr,#4
	
fiq:
	subs pc,lr,#4
	
@---------------------------------------------------------------------------------
_start2:
@---------------------------------------------------------------------------------
	ldr		R0,=__stack_base
	ldr             R1,=__int_stack_size
	
	msr		CPSR_c, #Mode_FIQ|I_Bit|F_Bit
	mov		sp, R0
	sub		R0, R0, R1

	msr		CPSR_c, #Mode_IRQ|I_Bit|F_Bit
	mov		sp, R0
	sub		R0, R0, R1

	msr		CPSR_c, #Mode_SVC|I_Bit|F_Bit
	mov		sp, R0

	ldr 		R0,=__bss_start
	ldr 		R1,=__bss_end
	mov		R2, #0
clear_bss_loop:
	cmp 		r0, r1
	strlt 		r2, [r0], #4
	blt		clear_bss_loop
	
@---------------------------------------------------------------------------------
@ global constructors
@---------------------------------------------------------------------------------
	ldr		r3,=_call_main
	mov		lr,r3
	ldr		r3,=__libc_init_array
	bx		r3
@---------------------------------------------------------------------------------
@ Jump to user code
@---------------------------------------------------------------------------------
_call_main:
@---------------------------------------------------------------------------------
	ldr		r1,=__params_addr
	ldr             r0, [r1]
	add             r1, r1, #4
	bl		main
	bl 		disable_caches_mmu
	b		run_bootloader

@---------------------------------------------------------------------------------
@ Load and execute bootloader from NAND
@ We load the first block to 0x0 and run it. This simulates what happens on boot
@ so it should work for any bootloader
@---------------------------------------------------------------------------------
.balign 512
run_bootloader:
@---------------------------------------------------------------------------------
	// registers we use
	#define NFDATA          0x9c000000
	#define NFCMD           0x9C000010
	#define NFADDR          0x9C000018
	#define MEMNANDCTRLW    0xC0003A3A
	#define MEMNANDTIMEW    0xC0003A3C

	// load parameters
	#define BLOCK_SIZE	512
	#define LOAD_ADDRESS	0x0
	#define LOAD_LENGTH	512

	ldr		r1, =MEMNANDCTRLW
	ldr		r0, =0x8080
	strh		r0, [r1]
	
	// set NAND timing
	ldr		r1, =MEMNANDTIMEW
	ldr		r0, =0x7F8
	strh		r0, [r1]

	// prepare load parameters
	ldr		r3, =LOAD_LENGTH // next NAND address to read from, and number of bytes remaining
	ldr		r4, =(LOAD_ADDRESS+LOAD_LENGTH) // current write-to address

nand_read:
	sub		r3, r3, #BLOCK_SIZE

	// read one block
	ldr		r1, =NFCMD
	ldr		r0, =0x0
	strb		r0, [r1]

	// write address out one byte at a time
	// K9F1208 databook page 8 says the addresses are sent a0-a7,a9-a16,a17-a24,a25 with a8 determined by cmd0 (0), or cmd1 (1) - meaning you have to explicitly read half pages
	ldr		r1, =NFADDR

	strb		r3, [r1]
	mov		r0, r3, lsr #9
	strb		r0, [r1]
	mov		r0, r3, lsr #17
	strb		r0, [r1]
	mov		r0, r3, lsr #25
	strb		r0, [r1]

nand_read_wait:
	ldr		r1, =MEMNANDCTRLW
        ldrh		r0, [r1]
	tst		r0, #0x8000
	beq		nand_read_wait
	ldr		r0, =0x8080
	strh		r0, [r1]
	
	ldr		r1, =NFDATA
	sub		r5, r4, #BLOCK_SIZE
nand_copy_data:
	ldrh		r0, [r1]
	strh		r0, [r5]
	add		r5, r5, #2
	cmp		r5, r4
	bne		nand_copy_data

	sub		r4, r4, #BLOCK_SIZE
	cmp		r3, #0
	bne		nand_read

	b launch_bootloader
		
launch_bootloader:	
	// we are done, jump to bootloader
	ldr		lr, =LOAD_ADDRESS
	mov		pc, lr

// http://infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.ddi0151c/I66051.html	
disable_caches_mmu:
	// mmu off
	mrc p15, 0, r0, c1, c0, 0
	bic r0, r0, #0x1
	mcr p15, 0, r0, c1, c0, 0

	// caches off
	mrc p15, 0, r0, c1, c0, 0
	bic r1, r1, #(0x1 << 12) // icache off
	bic r1, r1, #(0x1 << 2) // dcache off
	mcr p15, 0, r0, c1, c0, 0
	
	bx lr
	
@---------------------------------------------------------------------------------
	
	.pool
	.end

	
