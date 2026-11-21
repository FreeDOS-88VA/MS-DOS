; nasm -f bin WRAPTEST.NAS -o WRAPTEST.COM
; WRAPTEST uses AH=40h, WRAPTEST B uses AH=02h.
; Capture all six pages, tapping Space between them and after the last.
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
%macro locate 2
    send 27,'[',%1,';',%2,'H'
%endmacro
; Show where X lands and log the position immediately before it.
%macro edge 4+
    locate %1,'5'
    send %3
    locate %1,'80'
    send 'T',%4
    call report
    send 'X'
    locate %2,'5'
    call show
%endmacro

start:
    cld
    cmp byte [82h],'B'
    jne .begin
    inc byte [split]
.begin:
    mov ax,0c00h
    int 21h
    send 27,'[>1l',27,'[m',27,'[2J','EDGE: reports before X on rows 15-23'
    locate '3','1'
    send 'Next printable'
    locate '3','80'
    send 'TX'
    edge '4','15','Report alone', ''
    edge '6','16','CR',13
    edge '7','17','LF',10
    edge '9','18','BS',8
    edge '10','19','CSI 1D',27,'[1D'
    edge '11','20','CSI 1C',27,'[1C'
    edge '12','21','CSI color',27,'[31m'
    send 27,'[m'
    edge '13','22','Hide',27,'[>1h'
    edge '14','23','Show',27,'[>1l'
    locate '24','1'
    send 'Kanji, empty/pending col 80 next page'
    call pause

    send 27,'[2J','EDGE: more controls (reports on rows 15-23)'
    edge '8','18','CSI 0J',27,'[J'
    edge '3','15','CSI 1B',27,'[1B'
    edge '5','16','CSI 1A',27,'[1A'
    edge '7','17','CSI 0K',27,'[K'
    edge '9','19','ESC D',27,'D'
    edge '10','20','ESC M',27,'M'
    edge '11','21','CSI same',27,'[11;80H'
    edge '12','22','Save/hop/restore',27,'[s',27,'[13;3H',27,'[u'
    edge '13','23','BEL',7
    call pause

    send 27,'[2J','EDGE KANJI: first at col 80 / after T at col 80 / ending at col 80'
    locate '3','80'
    send 95h,5ch,'X'
    locate '6','80'
    send 'T',95h,5ch,'X'
    locate '9','79'
    send 95h,5ch
    call report
    send 'X'
    locate '15','1'
    call show
    call pause

    ; No output after T until the capture, then a second capture after X.
    send 27,'[2J','KEEP TOP (labels on)'
    mov bp,21
    call fill
    locate '24','1'
    send 'BOTTOM'
    locate '24','80'
    send 'T'
    call pause
    send 'X'
    call pause

    send 27,'[>1h',27,'[2J','KEEP TOP (labels off)'
    mov bp,22
    call fill
    locate '25','1'
    send 'BOTTOM'
    locate '25','80'
    send 'T'
    call pause
    send 27,'[>1l',27,'[2J','WRAPTEST DONE',13,10
    mov ax,4c00h
    int 21h

fill:
    locate '2','1'
    send 'SECOND',13,10
.row:
    send 'FILL',13,10
    dec bp
    jnz .row
    ret

pause:
    mov ah,08h
    int 21h
    cmp al,' '
    jne pause
    ret

report:
    send 27,'[6n'
    mov di,pos
    mov cx,8
.next:
    push cx
    mov cx,2000
.poll:
    mov ah,06h
    mov dl,0ffh
    int 21h
    jnz .got
    loop .poll
    mov al,'?'
.got:
    stosb
    pop cx
    loop .next
    ret

show:
    mov dx,pos+2
    cmp word [pos],5b1bh
    jne .bad
    cmp byte [pos+7],'R'
    je .send
.bad:
    mov dx,badreport
.send:
    mov cx,5
    jmp write

write:
    cmp byte [split],0
    jne .split
    mov bx,1
    mov ah,40h
    int 21h
    ret
.split:
    mov si,dx
.next:
    lodsb
    mov dl,al
    mov ah,02h
    int 21h
    loop .next
    ret

split: db 0
pos: times 8 db 0
badreport: db '?????'
