'
' FastBasic - Fast basic interpreter for the Atari 8-bit computers
' Copyright (C) 2017-2025 Daniel Serpell
'
' This program is free software; you can redistribute it and/or modify
' it under the terms of the GNU General Public License as published by
' the Free Software Foundation, either version 2 of the License, or
' (at your option) any later version.
'
' This program is distributed in the hope that it will be useful,
' but WITHOUT ANY WARRANTY; without even the implied warranty of
' MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
' GNU General Public License for more details.
'
' You should have received a copy of the GNU General Public License along
' with this program.  If not, see <http://www.gnu.org/licenses/>
'
' In addition to the permissions in the GNU General Public License, the
' authors give you unlimited permission to link the compiled version of
' this file into combinations with other programs, and to distribute those
' combinations without any restriction coming from the use of this file.
' (The General Public License restrictions do apply in other respects; for
' example, they cover modification of the file, and distribution when not
' linked into a combine executable.)

' Command line compiler in FastBasic
' ----------------------------------

' Init filename, allocates space for one string
FileName$ = ""

' MemStart: the start of available memory, used as a buffer for the file data
dim MemStart(-1) byte
' MemEnd: the end of the current file, initialized to MemStart.
MemEnd = Adr(MemStart)
DIM NewPtr

'-------------------------------------
' Shows file error
'
PROC FileError
  i = err()
  ? "FILE ERROR: "; i
  put $FD
  ? "Press any key to exit."
  close #1
  get i
  end
ENDPROC

'-------------------------------------
' Gets a file name from command line or input
'
PROC InputFileName
  ' Clear file name
  poke &FileName$, 0
  ? " File Name ";
  ' Detect Sparta compatible DOS
  if peek($700) = $53
    ' Try to get file name from command line
    i = usr(dpeek(10)+3)
    for i=0 to 27
      if peek(dpeek(10)+33+i) = $9B then Exit
    next
    if i >= 4
      move dpeek(10)+33, &FileName$ + 1, 28
      poke &FileName$,i
      ? FileName$
    endif
  endif
  ' No file name, input from console
  if not Len(FileName$) then input FileName$
  ' Adds "D:" and extension to file name if not there
  if Len(FileName$) < 3 OR (Asc(FileName$[2]) <> $3A AND Asc(FileName$[3]) <> $3A)
    ' Don't use string operations to avoid allocations!!!
    -move Adr(FileName$) + 1, Adr(FileName$) + 3, Len(FileName$)
    poke Adr(FileName$), peek(Adr(FileName$)) + 2
    poke Adr(FileName$) + 1, $44
    poke Adr(FileName$) + 2, $3A
  endif
ENDPROC

'-------------------------------------
' Save compiled file
'
PROC SaveCompiledFile

  ? "Output";
  exec InputFileName

  if not Len(FileName$) then exit

  open #1, 8, 0, FileName$
  if err() < 128
    ' Open ok, write header
    bput #1, @COMP_HEAD_1, 12
    bput #1, @@ZP_INTERP_LOAD, @@ZP_INTERP_SIZE
    bput #1, @__PREHEAD_RUN__, @COMP_RT_SIZE
    ' Note, the compiler writes to "NewPtr" the end of program code
    bput #1, MemEnd, NewPtr - MemEnd + 1
    if err() < 128
      ' Save ok, close
      close #1
    endif
  endif

  if err() > 127
    exec FileError
  endif

ENDPROC

'-------------------------------------
' Load file into editor
'
PROC LoadFile

  ? "BASIC";
  exec InputFileName

  open #1, 4, 0, FileName$
  if err() < 128
    bget #1, Adr(MemStart), dpeek(@MEMTOP) - Adr(MemStart)
  endif

  ' Load ok only if error = 136 (EOF found)
  if err() = 136
    MemEnd = dpeek($358) + Adr(MemStart)
  else
    exec FileError
  endif
  close #1

ENDPROC

'-------------------------------------
' Compile file
PROC CompileFile
  ' Compile main file
  ? "Compiling..."
  dpoke @@RELOC_OFFSET, @BYTECODE_ADDR - MemEnd
  dpoke @@BUF_PTR, Adr(MemStart)
  if USR( @compile_buffer, MemEnd)
    ' Parse error, show
    ? " at line "; dpeek(@@linenum); " column "; peek( @@bmax )
  else
    exec SaveCompiledFile
  endif
ENDPROC

'-------------------------------------
' Main Program
'

? "FastBasic Compiler %VERSION%"
exec LoadFile

exec CompileFile


' vi:syntax=tbxl
