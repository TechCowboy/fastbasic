;
; FastBasic - Fast basic interpreter for the Atari 8-bit computers
; Copyright (C) 2017-2025 Daniel Serpell
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


; Floating Point SGN
; ------------------

        .importzp       next_instruction

        .include "atari.inc"

        .segment        "RUNTIME"

.proc   EXE_FP_SGN
        asl     FR0
        beq     zero
        ldy     #$80
        sty     FR0
        ror     FR0
        ldy     #$01
        sty     FR0+1
        ldy     #0
        sty     FR0+2
        sty     FR0+3
        sty     FR0+4
        sty     FR0+5
zero:   jmp     next_instruction
.endproc

        .include "deftok.inc"
        deftoken "FP_SGN"

; vi:syntax=asm_ca65
