; ROWSMODE 2 or 5: test DOS CON in 20 or 25 rows, leaving the mode set.
org 100h
bits 16
cpu 8086
%macro send 1+
    jmp short %%send
%%data: db %1
%%send:
    mov dx,%%data
    mov cx,%%send-%%data
    call write
%endmacro
    cmp byte [82h],'2'
    je .mode20
    send 27,'[>3l'
    jmp short .start
.mode20:
    mov byte [last],19
    send 27,'[>3h'
.start:
    send 'TOP',27,'[2;1HSECOND',27,'[31m'
    mov al,[last]
    call bottom
    send 'T',27,'[6n'
    mov al,[last]
    mov bl,'1'               ; Logical column 81.
    call report
    call pause               ; TOP still present; T at right edge.
    send 'X',27,'[m',27,'[>1h'
    mov al,[last]
    inc al
    call bottom
    send 'U',27,'[6n'
    mov al,[last]
    inc al
    mov bl,'1'
    call report
    call pause               ; SECOND scrolled to top; full height with labels off.
    send 27,'[>1l',27,')3',27,'[>5h',27,'[2J','ROWS OK'
    call pause               ; Clear+home, labels and g visible, cursor disabled.
    send 27,')0',27,'[>5l'
    mov ax,4c00h
    int 21h
bottom:
    aam
    add ax,3030h
    xchg al,ah
    mov [position+2],ax
    mov dx,position
    mov cx,position_end-position
write:
    mov bx,1
    mov ah,40h
    int 21h
    ret
report:
    aam
    add ax,3030h
    xchg al,ah
    mov [response+2],ax
    mov [response+6],bl
    mov si,response
    mov cx,8
.next:
    mov ax,0600h
    mov dl,0ffh
    int 21h
    jz fail
    cmp al,[si]
    jne fail
    inc si
    loop .next
    ret
fail:
    send 27,'[H','BAD DSR'
    mov ax,4c01h
    int 21h
pause:
    mov ah,08h
    int 21h
    cmp al,' '
    jne pause
    ret
last db 24
position db 27,'[00;80H'
position_end:
response db 27,'[00;80R'
