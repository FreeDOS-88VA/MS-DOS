; nasm -f bin ESCPROBE.NAS -o ESCPROBE.COM
; Run ESCPROBE (AH=40h), or ESCPROBE B (same stream, AH=02h).
; Capture each page before pressing Space. A printed marker identifies the
; affected cell; a marker advances the cursor unless it wraps/scrolls.
org 100h
cpu 8086
bits 16

%macro send 1+
    mov dx, %%data
    mov cx, %%end-%%data
    call write
    jmp short %%end
%%data: db %1
%%end:
%endmacro
%macro csi 1+
    send 27,'[',%1
%endmacro
%define at locate
%macro locate 2
    csi %1,';',%2,'H'
%endmacro
%macro page 1
    csi 'm',27,'[2J',27,'[H',%1
%endmacro
%macro ktest 2
    at %1,'1'
    send %2, '  ABCDEFGHIJ'
    at %1,'13'
%endmacro
%macro jfill 1
    page %1
    at '4','1'
    send 'ABOVE',13,10,'0123456789',13,10,'BELOW'
    at '5','5'
%endmacro
%macro rows 1
    page %1
    at '4','1'
    send 'R04',13,10,'R05',13,10,'R06',13,10,'R07',13,10,'R08'
    at '5','2'
%endmacro
%macro attr 2
    csi 'm',27,'[',%1,'m',%2,27,'[m','|'
%endmacro

start:
    cmp byte [82h],'B'
    jne .pages
    inc byte [split]
.pages:
    page '01: position (A=H, B=f, C=H default, D=partial, E=zero, F/G=range, X=direct)'
    at '3','10'
    send 'A'
    csi '4;12f','B'
    at '6','20'
    csi 'H','C'
    at '6','20'
    csi '5H','D'
    at '6','20'
    csi '0;0H','E'
    at '7','20'
    csi '99;11H','F'
    at '8','20'
    csi '9;99f','G'
    at '13','1'
    send 27,'=',32+14,32+21,'X'
    at '16','1'
    csi ';74H','Y'
    at '16','1'
    send 27,'=',32+90,32+34,'Z',27,'=',32+10,32+90,'T'
    call pause

    page '02: relative (A up, B down, C right, D left, Z zero, X/Y edge)'
    at '7','20'
    csi 'A','A'
    at '7','22'
    csi '2B','B'
    at '7','24'
    csi '4C','C'
    at '7','20'
    csi '3D','D'
    at '7','24'
    csi '0B','Z'
    at '11','4'
    csi '99D','X'
    at '11','4'
    csi '99C','Y'
    at '11','25'
    csi '99A','U'
    at '11','27'
    csi '99B','V'
    at '20','40'
    csi '25A','W'
    at '20','42'
    csi '99B','Q'
    at '15','28'
    csi '0A','N'
    at '15','30'
    csi 'C','P'
    at '15','34'
    csi 'D','R'
    call pause

    page '03: save/restore and report'
    at '3','7'
    csi 's'
    at '6','9'
    csi 'u','S'
    ; Flush keystrokes before positioning and requesting reports.
    mov ax,0c00h
    int 21h
    at '12','34'
    call readpos
    at '9','1'
    send 'Report at (12,34): '
    call hexpos
    at '2','7'
    call readpos
    at '11','1'
    send 'Report at (2,7):   '
    call hexpos
    call pause

    page '04: erase in line; | marks unchanged cursor'
    ktest '3','K  '
    csi 'K','|'
    ktest '5','0K '
    csi '0K','|'
    ktest '7','1K '
    csi '1K','|'
    ktest '9','2K '
    csi '2K','|'
    ktest '11','3K '
    csi '3K','|'
    call pause

    jfill '05: J'
    csi 'J','|'
    call pause
    jfill '06: 0J'
    csi '0J','|'
    call pause
    jfill '07: 1J'
    csi '1J','|'
    call pause
    jfill '08: 2J'
    csi '2J','|'
    call pause
    jfill '09: ESC *'
    send 27,'*','|'
    call pause

    page '10: attributes (later text; reset delimiters)'
    at '3','1'
    attr '0','00 TEST'
    attr '1','01 TEST'
    attr '4','04 TEST'
    attr '5','05 TEST'
    attr '7','07 TEST'
    attr '8','08 TEST'
    attr '16','16 TEST'
    attr '17','17 TEST'
    at '5','1'
%assign v 30
%rep 8
    attr %str(v),%str(v)
%assign v v+1
%endrep
    at '7','1'
%assign v 40
%rep 8
    attr %str(v),%str(v)
%assign v v+1
%endrep
    at '9','1'
    attr '7;31;4','7;31;4 TEST'
    attr '4;31;7','4;31;7 TEST'
    csi '7m','REVERSE',27,'[m',' RESET'
    at '12','1'
    send 'Erase with 7m: '
    csi '7m',27,'[K',27,'[m'
    at '13','1'
    csi '41m',27,'[K','AFTER',27,'[m'
    at '14','1'
    csi '31m','RED',27,'[1m',' THEN 1',27,'[m',' RESET'
    at '16','1'
    csi '31m',27,'[4m','RED then 4',27,'[m','|',27,'[31;4m','31;4',27,'[m','|'
    at '18','1'
    csi '41;32m','41;32',27,'[m','|',27,'[16;31m','16;31',27,'[m','|'
    call pause

    page '11: >3h (H printed immediately, R addressed to 4;60)'
    at '4','1'
    csi '>3h','H'
    at '4','60'
    send 'R'
    call pause
    csi '>3l','L'
    at '4','60'
    send 'R'
    call pause

    page '12: )0/)3, ? forms and >5l then >5h'
    at '6','1'
    send 27,')0','C',0a6h,95h,5ch,27,')3','D',0a6h,95h,5ch
    at '8','1'
    csi '?25l','E',27,'[?25h','F',27,'[?3h','G',27,'[?3l','H'
    at '10','1'
    csi '>5l'
    call pause
    at '10','1'
    csi '>5h'
    call pause
    send 27,')0'             ; Restore kanji interpretation before later pages.
    csi '>5l'                ; Restore cursor display.

    rows '13: L, then 2L'
    csi 'L','A'
    at '7','2'
    csi '2L','B'
    call pause
    rows '14: M, then 2M'
    csi 'M','A'
    at '6','2'
    csi '2M','B'
    call pause
    rows '15: ESC D/M/E from inside screen'
    send 27,'D','D',27,'M','M',27,'E','E'
    call pause
    rows '16: ESC D/E at bottom, M at top'
    at '24','20'
    send 'bottom',27,'D','D',27,'E','E'
    at '1','2'
    send 27,'M','M'
    call pause

    page '17: controls; each A<byte>B starts at column 10'
    at '3','1'
    send '07       A',7,'B'
    at '5','1'
    send '09       A',9,'B'
    at '7','1'
    send '0B       A',11,'B'
    at '10','1'
    send '1A       A',26,'B'
    at '12','1'
    send '1E       A',30,'B'
    call pause
    page '17b: 0C'
    at '14','1'
    send '0C       A',12,'B'
    call pause

    page '18: other C0 and DEL (hex labels)'
%assign n 0
%rep 32
%if n != 7 && n != 9 && n != 11 && n != 12 && n != 26 && n != 27 && n != 30
%assign row 3+(n/8)*4
%assign col 1+(n&7)*10
    at %str(row),%str(col)
%assign hex n&15
%if hex < 10
    send '0'+(n>>4),'0'+hex,':A',n,'B'
%else
    send '0'+(n>>4),'A'+hex-10,':A',n,'B'
%endif
%endif
%assign n n+1
%endrep
    at '20','1'
    send '7F:A',127,'B'
    call pause

    page '19: half-kanji overwrite (left/right) and erase (right/left)'
    at '4','1'
    send '[',95h,5ch,'] [',95h,5ch,']'
    at '4','2'
    send 'L'
    at '4','8'
    send 'R'
    at '6','1'
    send '[',95h,5ch,']'
    at '6','3'
    csi 'K'
    at '8','1'
    send '[',95h,5ch,']'
    at '8','2'
    csi '1K'
    call pause

    page '20: recovery and malformed parameters'
    at '3','1'
    csi '12;34z','Z OK'
    at '5','1'
    csi '12;?K','? OK'
    at '7','1'
    csi '1234567890123456789012345678901234567890z','LONG OK'
    at '9','1'
    csi '>X','X OK'
    at '11','1'
    csi '12;',27,'[11;20H','ESC OK'
    at '13','1'
    csi '1234567890123456789012345678901234567890','1234567890123456789012345678901234567890z','OVER OK'
    at '15','1'
    csi '1234567890123456789012345678901234567890','1234567890123456789012345678901234567890'
    send '1234567890123456789012345678901234567890z','HARD OK'
    call pause

    page '21: hidden labels, L/M and scroll on row 25'
    csi '>1h'
    at '23','1'
    send '23',13,10,'24',13,10,'25'
    at '24','2'
    csi 'L','L',27,'[M','M'
    at '25','10'
    send 'BOTTOM',27,'D','D'
    call pause
    at '25','1'
    send 'ROW25',27,'[25;3H',27,'[K','|'
    call pause
    csi '>1l',27,'[m',27,'[2J',27,'[H'
    send 'ESCPROBE DONE',13,10
    mov ax,4c00h
    int 21h

pause:
    mov ax,0c08h             ; discard type-ahead, wait without echo
    int 21h
    ret

readpos:
    xor di,di
    csi '6n'
.next:
    mov ah,06h
    mov dl,0ffh
    int 21h
    jz .done
    mov [report+di],al
    inc di
    cmp di,16
    jb .next
.done:
    ret

hexpos:
    xor si,si
.next:
    cmp si,di
    jae .done
    mov al,[report+si]
    inc si
    push ax
    mov cl,4
    shr al,cl
    call digit
    pop ax
    and al,15
    call digit
    mov dl,' '
    call put02
    jmp short .next
.done:
    ret

digit:
    cmp al,10
    jb .numeric
    add al,'A'-'0'-10
.numeric:
    add al,'0'
    mov dl,al
put02:
    push si
    push di
    mov ah,02h
    int 21h
    pop di
    pop si
    ret

write:
    cmp byte [split],0
    jne .bytewise
    mov bx,1
    mov ah,40h
    int 21h
    ret
.bytewise:
    push si
    mov si,dx
.next:
    lodsb
    mov dl,al
    push cx
    call put02
    pop cx
    loop .next
    pop si
    ret

split db 0
report times 16 db 0
