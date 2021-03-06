/*
 *  Startup Code for MIPS64 CPU-core
 *
 *  Copyright (c) 2003	Wolfgang Denk <wd@denx.de>
 *
 * See file CREDITS for list of people who contributed to this
 * project.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any dlater version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICUdlaR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Pdlace, Suite 330, Boston,
 * MA 02111-1307 USA
 */

#include <asm-offsets.h>
#include <config.h>
#include <asm/regdef.h>
#include <asm/mipsregs.h>

#ifndef CONFIG_SYS_MIPS_CACHE_MODE
#define CONFIG_SYS_MIPS_CACHE_MODE CONF_CM_CACHABLE_NONCOHERENT
#endif

	/*
	 * For the moment disable interrupts, mark the kernel mode and
	 * set ST0_KX so that the CPU does not spit fire when using
	 * 64-bit addresses.
	 */
	.macro	setup_c0_status set clr
	.set	push
	mfc0	t0, CP0_STATUS
	or	t0, ST0_CU0 | \set | 0x1f | \clr
	xor	t0, 0x1f | \clr
	mtc0	t0, CP0_STATUS
	.set	noreorder
	sll	zero, 3				# ehb
	.set	pop
	.endm

	.set noreorder

	.globl _start
	.text
_start:
	.org 0x000
	b	reset
	 nop
	.org 0x080
	b	romReserved
	 nop
	.org 0x100
	b	romReserved
	 nop
	.org 0x180
	b	romReserved
	 nop
	.org 0x200
	b	romReserved
	 nop
	.org 0x280
	b	romReserved
	 nop
	.org 0x300
	b	romReserved
	 nop
	.org 0x380
	b	romReserved
	 nop
	.org 0x480
	b	romReserved
	 nop

	/*
	 * We hope there are no more reserved vectors!
	 * 128 * 8 == 1024 == 0x400
	 * so this is address R_VEC+0x400 == 0xbfc00400
	 */
	.org 0x500
	.align 4
reset:

	/* Clear watch registers */
	dmtc0	zero, CP0_WATCHLO
	dmtc0	zero, CP0_WATCHHI

	/* WP(Watch Pending), SW0/1 should be cleared */
	mtc0	zero, CP0_CAUSE

	setup_c0_status ST0_KX 0

	/* Init Timer */
	mtc0	zero, CP0_COUNT
	mtc0	zero, CP0_COMPARE

#ifndef CONFIG_SKIP_LOWLEVEL_INIT
	/* CONFIG0 register */
	dli	t0, CONF_CM_UNCACHED
	mtc0	t0, CP0_CONFIG
#endif

	/* Initialize $gp */
	bal	1f
	 nop
	.dword	_gp
1:
	ld	gp, 0(ra)

#ifndef CONFIG_SKIP_LOWLEVEL_INIT
	/* Initialize any external memory */
	dla	t9, lowlevel_init
	jalr	t9
	 nop

	/* Initialize caches... */
	dla	t9, mips_cache_reset
	jalr	t9
	 nop

	/* ... and enable them */
	dli	t0, CONFIG_SYS_MIPS_CACHE_MODE
	mtc0	t0, CP0_CONFIG
#endif

	/* Set up temporary stack */
	dli	t0, CONFIG_SYS_SDRAM_BASE + CONFIG_SYS_INIT_SP_OFFSET
	dla	sp, 0(t0)

	dla	t9, board_init_f
	jr	t9
	 nop

/*
 * void relocate_code (addr_sp, gd, addr_moni)
 *
 * This "function" does not return, instead it continues in RAM
 * after relocating the monitor code.
 *
 * a0 = addr_sp
 * a1 = gd
 * a2 = destination address
 */
	.globl	relocate_code
	.ent	relocate_code
relocate_code:
	move	sp, a0			# set new stack pointer

	dli	t0, CONFIG_SYS_MONITOR_BASE
	dla	t3, in_ram
	ld	t2, -24(t3)		# t2 <-- uboot_end_data
	move	t1, a2
	move	s2, a2			# s2 <-- destination address

	/*
	 * Fix $gp:
	 *
	 * New $gp = (Old $gp - CONFIG_SYS_MONITOR_BASE) + Destination Address
	 */
	move	t8, gp
	dsub	gp, CONFIG_SYS_MONITOR_BASE
	dadd	gp, a2			# gp now adjusted
	dsub	s1, gp, t8		# s1 <-- relocation offset

	/*
	 * t0 = source address
	 * t1 = target address
	 * t2 = source end address
	 */

	/*
	 * Save destination address and size for dlater usage in flush_cache()
	 */
	move	s0, a1			# save gd in s0
	move	a0, t1			# a0 <-- destination addr
	dsub	a1, t2, t0		# a1 <-- size

1:
	lw	t3, 0(t0)
	sw	t3, 0(t1)
	daddu	t0, 4
	ble	t0, t2, 1b
	 daddu	t1, 4

	/* If caches were enabled, we would have to flush them here. */

	/* a0 & a1 are already set up for flush_cache(start, size) */
	dla	t9, flush_cache
	jalr	t9
	 nop

	/* Jump to where we've relocated ourselves */
	daddi	t0, s2, in_ram - _start
	jr	t0
	 nop

	.dword	_gp
	.dword	_GLOBAL_OFFSET_TABLE_
	.dword	uboot_end_data
	.dword	uboot_end
	.dword	num_got_entries

in_ram:
	/*
	 * Now we want to update GOT.
	 *
	 * GOT[0] is reserved. GOT[1] is also reserved for the dynamic object
	 * generated by GNU ld. Skip these reserved entries from relocation.
	 */
	ld	t3, -8(t0)		# t3 <-- num_got_entries
	ld	t8, -32(t0)		# t8 <-- _GLOBAL_OFFSET_TABLE_
	ld	t9, -40(t0)		# t9 <-- _gp
	dsub	t8, t9			# compute offset
	dadd	t8, t8, gp		# t8 now holds relocated _G_O_T_
	daddi	t8, t8, 16		# skipping first two entries
	dli	t2, 2
1:
	ld	t1, 0(t8)
	beqz	t1, 2f
	 dadd	t1, s1
	sd	t1, 0(t8)
2:
	daddi	t2, 1
	blt	t2, t3, 1b
	 daddi	t8, 8

	/* Clear BSS */
	ld	t1, -24(t0)		# t1 <-- uboot_end_data
	ld	t2, -16(t0)		# t2 <-- uboot_end
	dadd	t1, s1			# adjust pointers
	dadd	t2, s1

	dsub	t1, 8
1:
	daddi	t1, 8
	bltl	t1, t2, 1b
	 sd	zero, 0(t1)

	move	a0, s0			# a0 <-- gd
	dla	t9, board_init_r
	jr	t9
	 move	a1, s2

	.end	relocate_code

	/* Exception handlers */
romReserved:
	b	romReserved
