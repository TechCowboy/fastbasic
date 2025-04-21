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


' A text editor / IDE in FastBasic
' --------------------------------
'

'-------------------------------------
' Array definitions
dim ScrAdr(24)
' And an array with the current line being edited
''NOTE: Use page 6 ($600 to $6FF) to free memory instead of a dynamic array
'dim EditBuf(256) byte
EditBuf = $600

' Store original margin value
OldMargin = PEEK(@@LMARGN)

' We start with the help file.
FileName$ = "D:HELP.TXT"

' MemStart: the start of available memory, used as a buffer for the file data
' MemEnd: pointer to the end of the buffer.
dim MemStart(-1) byte

' NOTE: variables already are initialized to '0' in the runtime.
' topLine:      Line at the top of the screen
' column:       Logical cursor position (in the file)
' scrLine:      Cursor line in the acreen
' scrColumn:    Cursor column in the screen
' hDraw:        Column at left of screen, and last "updated" column
' lDraw:        Number of the line last drawn, and being edited.
' linLen:       Current line length.
' edited:       0 if not currently editing a line
' ScrAdr():     Address in the file of screen line

'-------------------------------------
' Main Program
'

' Loads initial file, and change the filename
exec InitScreen
exec LoadFile
exec DefaultFileName

' escape = 0  ' already initialized to 0
do
  ' Key reading loop
  exec ProcessKeys
loop

'-------------------------------------
' Sets FileName$ to the default drive
'
proc DefaultFileName
  FileName$="D:"
endproc


'-------------------------------------
' Starts the editor with an empty file
'
proc NewFile
  exec DefaultFileName
  MemEnd = Adr(MemStart)
  exec RedrawNewFile
endproc

'-------------------------------------
' Clears top line to show a message
'
PROC ClrTopLine
  exec SaveLine
  pos. 0,0
  ? ""$9C$9D"";
ENDPROC

'-------------------------------------
' Edit top line for input
'
PROC InputLine
  do
    get key
    ' Accept left/right arrows, backspace and standard characters
    if key >= 30 and key <= 124 or key = 126
      put key
    ' Process ENTER
    elif key = 155
      pos. 6, 0
      poke @CH, 12: ' Force ENTER
      key = 0
      exit
    else
    ' Otherwise simply exit
      exec ShowInfo
      exit
    endif
  loop
ENDPROC

'-------------------------------------
' Gets a filename with minimal line editing
'
PROC InputFilename
  ' Show current filename:
  ? "? "; FileName$;
  exec InputLine
  if not key
    input ; FileName$
    exec ShowInfo
  endif
ENDPROC

'-------------------------------------
' Compile and run
PROC CompileAndRun
  ' Pass the relocation offset, 0 means no
  ' relocation (compile and run at same address)
  dpoke @@RELOC_OFFSET, 0
  exec CompileFile
ENDPROC

'-------------------------------------
' Compile to a file
PROC CompileAndSave
  ' Pass the relocation offset, the compiled code
  ' is run at "BYTECODE_ADDR" instead of "MemEnd",
  ' the output buffer.
  dpoke @@RELOC_OFFSET, @BYTECODE_ADDR - MemEnd
  exec CompileFile
ENDPROC

'-------------------------------------
' Compile (and run) file
PROC CompileFile
  exec ClrTopLine
  ' Compile main file
  ? "Parsing: ";
  dpoke @@BUF_PTR, Adr(MemStart)
  if USR( @compile_buffer, MemEnd)
    ' Parse error, go to error line
    topLine = dpeek(@@linenum) - 11
    column = peek( @@bmax )
    scrLine = 10
    if topLine < 0
      scrLine = scrLine + topLine
      topLine = 0
    endif
    get key
  elif dpeek(@@RELOC_OFFSET)
    exec SaveCompiledFile
  else
    get key
    sound
    exec InitScreen
  endif
  exec CalcRedrawScreen
ENDPROC

'-------------------------------------
' Deletes the character over the cursor
'
PROC DeleteChar
  fileSaved = 0
  edited = 1
  linLen = linLen - 1
  move 1 + EditBuf + column, EditBuf + column, linLen - column
  exec ForceDrawCurrentLine
ENDPROC

'-------------------------------------
' Draws current line from edit buffer
' and move cursor to current position
'
PROC ForceDrawCurrentLine
  hDraw = 1
  exec DrawCurrentLine
ENDPROC

'-------------------------------------
' Draws current line from edit buffer
' and move cursor to current position
'
PROC DrawCurrentLine

  hColumn = 0
  scrColumn = column

  while scrColumn >= peek(@@RMARGN)
    hColumn = hColumn + 8
    scrColumn = 1 + column - hColumn
  wend

  if hDraw <> hColumn

    hDraw = hColumn
    y = scrLine
    ptr = EditBuf
    lLen = linLen
    exec DrawLinePtr

  endif
  lDraw = scrLine

  pos. scrColumn, scrLine
  put 29
ENDPROC

'-------------------------------------
' Insert a character over the cursor
'
PROC InsertChar
  fileSaved = 0
  edited = 1
  ptr = EditBuf + column
  -move ptr, ptr+1, linLen - column
  poke ptr, key
  inc linLen
ENDPROC

'-------------------------------------
' Undo editing current line
PROC UndoEditLine
  edited = 0
  put @@ATBEL
  exec CopyToEdit
  exec ForceDrawCurrentLine
ENDPROC

'-------------------------------------
' Save line being edited
'
PROC SaveLine
  if edited
    ' Move file memory to make room for new line
    nptr = ScrAdr(lDraw) + linLen
    ptr = ScrAdr(lDraw+1) - 1
    newPtr = nptr - ptr

    ' Check if we have enough space in the buffer for the new file
    ' TODO: This check will fail if the buffer is bigger than 32kB,
    '       because the right side will be negative.
    if newPtr > dpeek(@MEMTOP) - MemEnd
      exec UndoEditLine
      exit
    endif

    MemEnd = MemEnd + newPtr
    if newPtr < 0
      move  ptr, nptr, MemEnd - nptr
    elif newPtr <> 0
      -move ptr, nptr, MemEnd - nptr
    endif

    ' Copy new line
    move EditBuf, ScrAdr(lDraw), linLen
    ' Adjust all pointers
    y = lDraw
    repeat
      inc y
      ScrAdr(y) = ScrAdr(y) + newPtr
    until y > 22
    ' End
    edited = 0
  endif
ENDPROC

'-------------------------------------
' Copy current line to edit buffer
'
PROC CopyToEdit
  ptr = ScrAdr(scrLine)
  linLen = ScrAdr(scrLine+1) - ptr - 1

  ' Get column in range
  if column > linLen
    column = linLen
  endif

  ' Copy line to 'Edit' buffer, if not too long
  if linLen > 255
    linLen = 255
  endif
  move ptr, EditBuf, linLen
  poke EditBuf + linLen, $9b
ENDPROC

'-------------------------------------
' Save edited file
'
PROC AskSaveFile
  exec ClrTopLine
  ? "Save";
  exec InputFileName
  if key
    ' Don't save
    exit
  endif

  open #1, 8, 0, FileName$
  if err() = 1
    ' Open ok, write dile
    bput #1, Adr(MemStart), MemEnd - Adr(MemStart)
    if err() = 1
      ' Save ok, close
      close #1
      if err() = 1
        fileSaved = 1
        Exit
      endif
    endif
  endif

  exec FileError
ENDPROC

'-------------------------------------
' Shows file error
'
PROC FileError
  pos. 0,0
  ? err(); " I/O ERROR!"$FD;
  close #1
  get key
  exec ShowInfo
ENDPROC

'-------------------------------------
' Prints line info and changes line
'
PROC ShowInfo
  ' Print two "-", then filename, then complete with '-' until right margin
  pos. 0, 0 : ? ""$92$92;
  ? color(128) FileName$;
  repeat : put $92 : until peek(@@RMARGN) = peek(@@COLCRS)
  ' Fill last character
  poke @@OLDCHR, $D2
  ' Go to cursor position
  pos. scrColumn, scrLine
  put 29
ENDPROC

'-------------------------------------
' Ask to save a file if it is changed
' from last save.
PROC AskSaveFileChanged
  key = 0
  while not fileSaved
   exec AskSaveFile
   ' ESC means "don't save, cancel operation"
   if key = 27
     exit
   endif
   ' CONTROL-C means "don't save, lose changes"
   if key = 3
     key = 0
     exit
   endif
  wend
ENDPROC

'-------------------------------------
' Moves the cursor down 1 line
PROC CursorDown
  exec SaveLine
  if scrLine = 22
    exec ScrollUp
  else
    inc scrLine
  endif
ENDPROC

'-------------------------------------
' Moves the cursor up 1 line
PROC CursorUp
  exec SaveLine
  if scrLine
    dec scrLine
  else
    exec ScrollDown
  endif
ENDPROC

'-------------------------------------
' Scrolls screen Down (like page-up)
PROC ScrollDown
  ' Don't scroll if already at beginning of file
  if not topLine then Exit

  ' Scroll screen image inserting a line
  ' poke @CRSINH, 1   ' Not needed, as the cursor is already in this position
  pos. 0, 1
  put 157
  ' Move screen pointers
  -move adr(ScrAdr), adr(ScrAdr)+2, 46
  ' Get first screen line by searching last '$9B'
  ptr = ScrAdr(0) - 1
  while ptr <> Adr(MemStart) and peek(ptr-1) <> $9B
    dec ptr
  wend
  ScrAdr(0) = ptr

  ' Adjust top line
  dec topLine

  ' Draw first line
  y = 0
  exec DrawLineOrig

ENDPROC

'-------------------------------------
' Draws line 'Y' from file buffer
'
PROC DrawLineOrig
  ptr = ScrAdr(y)
  lLen = ScrAdr(y+1) - ptr - 1
  hDraw = 0
  exec DrawLinePtr
ENDPROC

'-------------------------------------
' Draws line 'Y' scrolled by hDraw
' with data from ptr and lLen.
'
PROC DrawLinePtr

  poke @DSPFLG, 1
  poke @CRSINH, 1

  pos. 0, y+1
  max = peek(@@RMARGN)
  ' If scrolled, print arrow and adjust pointers
  if hDraw
    ptr = ptr + hDraw
    lLen = lLen - hDraw
    put $9E
    dec max
  endif

  if lLen > max
    ' If length overflows, print one less and an arrow
    bput #0, ptr, max
    poke @@OLDCHR, $DF
  else
    if lLen < 0
      ' If line is outside the file, print an EOL symbol.
      put $FD
    elif lLen <> 0
      ' We can't call "BPUT" with a zero len, as that will
      ' print the character in the accumulator.
      bput #0, ptr, lLen
    endif
    ' And if the line is shorter than the max, fill up with
    ' spaces up to the end.
    if lLen <> max
      ? tab(peek(@@RMARGN));
    endif
    ' Fixup last character of line, as the OS don't let us
    ' print the last column
    poke @@OLDCHR, $00
  endif

  ' Restore cursor flags
  poke @DSPFLG, 0
  poke @CRSINH, 0
endproc


'-------------------------------------
' Calls 'CountLines
PROC CountLines
' This code is too slow in FastBasic, so we use machine code
'  ptr = nptr
'  while nptr <> MemEnd
'    inc nptr
'    if peek(nptr-1) = $9b then exit
'  wend
  ptr = nptr
  nptr = USR(@Count_Lines, ptr, MemEnd)
ENDPROC

'-------------------------------------
' Scrolls screen Up (like page-down)
PROC ScrollUp
  ' Don't scroll if already in last position
  if MemEnd = ScrAdr(1) then Exit

  ' Scroll screen image deleting the first line
  poke @CRSINH, 1
  pos. 0, 1
  put 156
  ' Move screen pointers
  move adr(ScrAdr)+2, adr(ScrAdr), 46

  ' Increment top-line
  inc topLine

  ' Get last screen line length by searching next EOL
  nptr = ScrAdr(23)
  exec CountLines
  ScrAdr(23) = nptr

  ' Draw last line
  y = 22
  exec DrawLineOrig
ENDPROC

'-------------------------------------
' Load file into editor
'
PROC LoadFile

  open #1, 4, 0, FileName$
  if err() = 1
    bget #1, Adr(MemStart), dpeek(@MEMTOP) - Adr(MemStart)
  endif

  ' Load ok only if error = 136 (EOF found)
  if err() = 136
    MemEnd = dpeek($358) + adr(MemStart)
  else
    ' Load error, we show the error to the user
    ' and restart with an empty file
    exec FileError
    exec NewFile
    exit
  endif

  exec RedrawNewFile
ENDPROC

'-------------------------------------
' Redraw screen after new file
'
PROC RedrawNewFile
  close #1
  fileSaved = 1
  column = 0
  topLine = 0
  scrLine = 0
  exec CalcRedrawScreen
ENDPROC

'-------------------------------------
' Calculate screen start and redraws entire screen
'
PROC CalcRedrawScreen

  exec CheckEmptyBuf

  ' Search given line
  nptr = Adr(MemStart)
  y = 0
  while y < topLine
   exec CountLines
   if nptr = MemEnd
     '  Line is outside of current file, go to last line
     topLine = y
     nptr = ptr
     exit
   endif
   inc y
  wend

  ScrAdr(0) = nptr
  exec RedrawScreen
ENDPROC

'-------------------------------------
' Redraws entire screen
'
PROC RedrawScreen
  ' Draw all screen lines
  cls
  exec ShowInfo
  hdraw = 0
  y = 0
  nptr = ScrAdr(0)
  while y < 23
    exec CountLines
    lLen = nptr - ptr - 1
    exec DrawLinePtr
    inc y
    ScrAdr(y) = nptr
  wend

  exec ChgLine
ENDPROC

'-------------------------------------
' Change current line.
'
PROC ChgLine

  exec SaveLine

  ' Restore last line, if needed
  if hDraw <> 0
    y = lDraw
    exec DrawLineOrig
  endif

  ' Keep new line in range
  while scrLine and ScrAdr(scrLine) = MemEnd
    scrLine = scrLine - 1
  wend

  exec CopyToEdit

  ' Print status
  pos. 32, 0 : ? color(128) 1 + topLine + scrLine;
  put $92

  ' Redraw line
  hDraw = 0
  exec DrawCurrentLine

ENDPROC

'-------------------------------------
' Fix empty buffer
PROC CheckEmptyBuf
  if peek(MemEnd-1) <> $9B
    poke MemEnd, $9b
    MemEnd = MemEnd + 1
  endif
ENDPROC

'-------------------------------------
' Initializes editor device
PROC InitScreen
  graphics 0
  poke @@LMARGN, $00
  poke @KEYREP, 3
ENDPROC

'-------------------------------------
' RETURN key, splits line at position
'
PROC ReturnKey
  ' Ads an CR char and terminate current line editing.
  exec InsertChar
  exec SaveLine
  ' Scroll screen if we are in the last line
  if scrLine > 21
    exec ScrollUp
    dec scrLine
  endif
  ' Split current line at this point
  newPtr = ScrAdr(scrLine) + column + 1

  ' Go to next line
  inc scrLine

  ' Move screen pointers
  ptr = adr(ScrAdr) + scrLine * 2
  -move ptr, ptr + 2, (23 - scrLine) * 2
  ' Save new line position
  dpoke ptr, newPtr

  ' Go to column 0
  column = 0

  ' Move screen down!
  ' poke @CRSINH, 1  ' Not needed, as cursor is already in this line
  pos. 0, scrLine + 1
  put 157

  ' And redraw old and new line to be edited
  lDraw = scrLine - 1
  hDraw = 1
  exec ChgLine
  exec ForceDrawCurrentLine
ENDPROC

'-------------------------------------
' Inserts a normal key to the file
'
PROC InsertNormalKey
    ' Process normal keys
    escape = 0
    if linLen > 254
      put @@ATBEL : ' ERROR, line too long
    else
      exec InsertChar
      inc column
      inc scrColumn
      if linLen = column and scrColumn < peek(@@RMARGN)
        poke @DSPFLG, 1
        put key
        poke @DSPFLG, 0
      else
        exec ForceDrawCurrentLine
      endif
    endif
ENDPROC

'-------------------------------------
' Moves the cursor one page up
'
proc CursorPageUp
    key = 20
    repeat
      exec CursorUp
      dec key
    until not key
    exec ChgLine
endproc

'-------------------------------------
' Moves the cursor one page down
'
proc CursorPageDown
    key = 20
    repeat
      exec CursorDown
      dec key
    until not key
    exec ChgLine
endproc

'-------------------------------------
' Deletes current line
'
PROC DeleteLine
  ' Go to beginning of line
  column = 0
  ' Delete from entire file!
  ptr = ScrAdr(scrLine)
  nptr = ScrAdr(scrLine+1)
  move nptr, ptr, MemEnd - nptr
  MemEnd = MemEnd - nptr + ptr
  ' Scroll screen if we are in the first line
  if scrLine = 0 and ptr = MemEnd
    exec ScrollDown
  endif
  exec MoveLineUp
ENDPROC

'-------------------------------------
' Move screen up after deleting current
' or joining two lines together
'
PROC MoveLineUp
  exec CheckEmptyBuf
  ' Mark file as changed
  fileSaved = 0
  ' Delete line from screen
  ' poke @CRSINH, 1 ' Not needed, as cursor is already in this line
  pos. 0, scrLine+1
  put 156
  nptr = ScrAdr(scrLine)
  for y = scrLine to 22
    exec CountLines
    ScrAdr(y+1) = nptr
  next y
  y = scrLine
  exec DrawLineOrig
  edited = 0
  lDraw = 22
  hDraw = 1
  exec ChgLine
ENDPROC

'-------------------------------------
' Deletes char to the left of current
'
PROC DoBackspace
    if column <> 0
      column = column - 1
      exec DoDeleteKey
    endif
ENDPROC

'-------------------------------------
' Process DELETE key
'
PROC DoDeleteKey
  if column < linLen
    exec DeleteChar
  else
    exec SaveLine
    ' Manually delete the EOL
    ptr = ScrAdr(scrLine+1)
    if ptr <> MemEnd
      move ptr, ptr - 1, MemEnd - ptr
      MemEnd = MemEnd - 1
    endif
    ' Redraw
    exec MoveLineUp
  endif
ENDPROC

'-------------------------------------
' Sets mark position to current line
'
PROC SetMarkPosition
  markPos = topLine + scrLine
ENDPROC

'-------------------------------------
' Copies a line from the mark position
'
PROC CopyFromMark

    ' If we are copying to a position before the mark
    if markPos > topLine + scrLine
      ' we need to increment the mark position
      inc markPos
    endif

    ' Insert a line after current one, to paste there:
    key = 155
    column = linLen
    exec ReturnKey

    ' Search mark line address. We can't store the address of
    ' the line, as any edit could invalidate that.
    nptr = Adr(MemStart)
    y = 0
    while y <= markPos and nptr <> MemEnd
      exec CountLines
      inc y
    wend

    ' Increment the mark position by one
    inc markPos

    ' Copy our source line to the edit buffer, simulating an edit
    linLen = nptr - ptr - 1
    if linLen > 255
      linLen = 255
    endif
    move ptr, EditBuf, linLen
    edited = 1
    exec SaveLine
    exec ForceDrawCurrentLine

ENDPROC

'-------------------------------------
' Reads a key and process
PROC ProcessKeys
  get key
  ' Special characters:
  '   27 ESC            ok
  '   28 UP             ok
  '   29 DOWN           ok
  '   30 LEFT           ok
  '   31 RIGHT          ok
  '  125 CLR SCREEN (shift-<) or (ctrl-<)
  '  126 BS CHAR        ok
  '  127 TAB
  '  155 CR             ok
  '  156 DEL LINE (shift-bs)   ok
  '  157 INS LINE (shift->)
  '  158 CTRL-TAB
  '  159 SHIFT-TAB
  '  253 BELL (ctrl-2)
  '  254 DEL CHAR (ctrl-bs)    ok
  '  255 INS CHAR (ctrl->)

  '--------- Return Key - can't be escaped
  if key = $9B
    exec ReturnKey

  elif (escape or ( ((key & 127) >= $20) and ((key & 127) < 125)) )
    exec InsertNormalKey
  '--------------------------------
  ' Command keys handling
  '
  '
  '--------- Delete Line ----------
  elif key = 156
    exec DeleteLine
  '
  '--------- Backspace ------------
  elif key = 126
    exec DoBackspace
  '
  '--------- Del Char -------------
  elif key = 254
    exec DoDeleteKey
  '
  '--------- Control-E (END) ------
  elif key = $05
    column = linLen
    exec DrawCurrentLine
  '
  '--------- Control-A (HOME) -----
  elif key = $01
    column = 0
    exec DrawCurrentLine
  '
  '--------- Left -----------------
  elif key = $1F
    if column < linLen
      inc column
      inc scrColumn
      if scrColumn < peek(@@RMARGN)
        put key
      else
        exec DrawCurrentLine
      endif
    endif
  '
  '--------- Right ----------------
  elif key = $1E
    if column <> 0
      dec column
      dec scrColumn
      if scrColumn <> 0
        put key
      else
        exec DrawCurrentLine
      endif
    endif
  '
  '--------- Control-U (page up)---
  elif key = $15
    exec CursorPageUp
  '
  '--------- Control-I (page down)-
  elif key = $09
    exec CursorPageDown
  '
  '--------- Down -----------------
  '--------- Page Down ------------
  elif key = $1D
    if peek(@SUPERF)
      exec CursorPageDown
    else
      exec CursorDown
      exec ChgLine
    endif
  '
  '--------- Up -------------------
  '--------- Page Up --------------
  elif key = $1C
    if peek(@SUPERF)
      exec CursorPageUp
    else
      exec CursorUp
      exec ChgLine
    endif
  '
  '--------- Control-Q (exit) -----
  elif key = $11
    exec AskSaveFileChanged
    if not key
      cls
      poke @@LMARGN, OldMargin
      end
    endif
  '
  '--------- Control-S (save) -----
  elif key = $13
    exec AskSaveFile
  '
  '--------- Control-R (run) -----
  elif key = $12
    exec CompileAndRun
  '
  '--------- Control-W (write compiled file) -----
  elif key = $17
    exec CompileAndSave
  '
  '--------- Control-N (new) -----
  elif key = $0E
    exec AskSaveFileChanged
    if not key
      exec NewFile
    endif
  '
  '--------- Control-L (load) -----
  elif key = $0C
    exec AskSaveFileChanged
    if not key
      exec ClrTopLine
      ? "Load";
      exec InputFileName
      if not key
        exec LoadFile
      endif
    endif
  '
  '--------- Control-G (go to line) -----
  elif key = $07
    exec ClrTopLine
    ? "Line? ";
    exec InputLine
    if not key
      input ; topLine
      topLine = abs(topLine - 1)
      scrLine = 0
      exec CalcRedrawScreen
    endif
  '
  '--------- Control-Z (undo) -----
  elif key = $1A
    exec UndoEditLine
  '
  '--------- Control-C (set mark) -----
  elif key = $03
    exec SetMarkPosition
  '--------- Control-V (copy from mark) -----
  elif key = $16
    exec CopyFromMark
  '
  '--------- Escape ---------------
  elif key = $1B
    escape = 1
 'else
    ' Unknown Control Key
  endif
ENDPROC

'-------------------------------------
' Save compiled file
'
PROC SaveCompiledFile
  exec ClrTopLine

  ' Save original filename
  move Adr(FileName$), EditBuf, 128
  exec DefaultFileName

  ? "Name";
  exec InputFileName
  if key
    ' Don't save
    exit
  endif

  open #1, 8, 0, FileName$
  if err() = 1
    ' Open ok, write header
    bput #1, @COMP_HEAD_1, 12
    bput #1, @@ZP_INTERP_LOAD, @@ZP_INTERP_SIZE
    bput #1, @__PREHEAD_RUN__, @COMP_RT_SIZE
    ' Note, the compiler writes to "NewPtr" the end of program code
    bput #1, MemEnd, NewPtr - MemEnd + 1
    if err() = 1
      ' Save ok, close
      close #1
    endif
  endif

  ' Restore original filename
  move EditBuf, Adr(FileName$), 128

  if err() <> 1
    exec FileError
  endif

ENDPROC

' vi:syntax=fastbasic
