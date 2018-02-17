;
; FastBasic - Fast basic interpreter for the Atari 8-bit computers
; Copyright (C) 2017,2018 Daniel Serpell
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 2 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License along
; with this program.  If not, see <http://www.gnu.org/licenses/>
;
; In addition to the permissions in the GNU General Public License, the
; authors give you unlimited permission to link the compiled version of
; this file into combinations with other programs, and to distribute those
; combinations without any restriction coming from the use of this file.
; (The General Public License restrictions do apply in other respects; for
; example, they cover modification of the file, and distribution when not
; linked into a combine executable.)


; Clear Memory
; ------------

        .export         clear_data, clear_memory, alloc_array

        .importzp       prog_ptr, mem_end, var_buf, var_ptr

        ; From runtime.asm
        .import         move_dwn_src, move_dwn_dst, move_dwn, putc, EXE_END
        .importzp       tmp1, tmp2, array_ptr

        ; From interpreter.asm
        .importzp       var_count

        ; Top of available memory
MEMTOP=         $2E5
        ; Allocation size
alloc_size=     tmp1

;----------------------------------------------------------
; Following routines are part of the runtime
        .segment        "RUNTIME"

        ; Clears data pointers before starting the interpreter
.proc   clear_data
        ; Init all pointers to end of program data
        lda     prog_ptr
        ldy     prog_ptr+1
        ldx     #(mem_end-prog_ptr)
loop:
        sta     prog_ptr, x
        sty     prog_ptr+1, x
        dex
        dex
        bpl     loop
        ; Adds 2 bytes for each variable
        ldx     #0
        lda     var_count
        asl
        sta     alloc_size
        bcc     :+
        inx
:       stx     alloc_size+1
.endproc        ; Fall through

        ; Allocate space for a new array AX = SIZE
        ; Returns pointer to allocated memory in TMP2
        ; Returns size of allocated memory in ALLOC_SIZE
.proc alloc_array

        ldy     array_ptr
        sty     tmp2
        ldy     array_ptr+1
        sty     tmp2+1

        sta     alloc_size
        stx     alloc_size + 1

        clc
        adc     array_ptr
        tay
        txa
        adc     array_ptr+1
        tax
        cpy     MEMTOP
        sbc     MEMTOP+1
        bcs     err_nomem

        sty     array_ptr
        stx     array_ptr+1
.endproc        ; Fall through

        ; Clears memory from (tmp2) of (alloc_size) size
.proc   clear_memory
        lda     alloc_size+1
        tax
        clc
        adc     tmp2+1
        sta     tmp2+1
        lda     #0
        inx
        ldy     alloc_size
        beq     nxt
        .byte   $2C   ; Skip 2 bytes over next "DEC"

pgloop: dec     tmp2+1
loop:   dey
        sta     (tmp2), y
        bne     loop

nxt:    dex
        bne     pgloop

        rts
.endproc

err_nomem:
        ; Show message and end program
        ldy     #memory_error_len-1
loop:   lda     memory_error_msg, y
        jsr     putc
        dey
        bpl     loop
        jmp     EXE_END
memory_error_msg:
        .byte $9b, "rorrE yromeM", $9b
memory_error_len=    * - memory_error_msg

; vi:syntax=asm_ca65
