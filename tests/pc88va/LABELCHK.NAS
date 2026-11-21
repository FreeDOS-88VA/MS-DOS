; nasm -f bin LABELCHK.NAS -o LABELCHK.COM
; N: 30 lines and exit. H/L: hide/show via DOS write, B/C: same bytewise.
; P: pause before hiding, after hiding, after scrolling, after showing.
; U/V: direct VA Putstr / Chuput (bypass CON), pause after each escape.
; F: unsupported/incomplete escape sequences must print as before.
        bits 16
        org 100h
        cld
        mov al,[82h]            ; First argument (one leading space).
        and al,0dfh
        cmp al,'N'
        je lines
        cmp al,'P'
        je probe
        cmp al,'F'
        je fallback
        mov si,hide
        cmp al,'U'
        je native
        cmp al,'V'
        je native
        cmp al,'B'
        je bytes
        cmp al,'H'
        je string
        mov si,show
        cmp al,'C'
        je bytes
string: mov dx,si
        mov cx,5
        call write
quit:   mov ax,4c00h
        int 21h
bytes:  mov cx,5
.next:  lodsb
        mov dl,al
        mov ah,02h
        int 21h
        loop .next
        jmp quit
lines:  call scroll
        jmp quit
probe:  call pause
        mov dx,hide
        mov cx,5
        call write
        call pause
        call scroll
        call pause
        mov dx,show
        mov cx,5
        call write
        call pause
        jmp quit
fallback:
        mov dx,unknown
        mov cx,unknown_end-unknown
        call write
        jmp quit
native: mov [method],al
        call rom
        mov si,show
        call rom
        mov si,clear
        call rom
        mov si,home
        call rom
        jmp quit
rom:    push cs
        pop ds
        cmp byte [method],'V'
        je .char
        mov dx,8000h
        mov ah,02h
        int 83h
        jmp pause
.char:  cld
        lodsb
        or al,al
        jz pause
        push si
        xor dh,dh
        mov dl,al
        xor ah,ah
        int 83h
        pop si
        jmp .char
pause:  push cs
        pop ds
        mov ah,07h
        int 21h
        ret
scroll: mov bp,30
.next:  mov dx,line
        mov cx,line_end-line
        call write
        inc byte [line+7]
        cmp byte [line+7],':'
        jne .again
        mov byte [line+7],'0'
        inc byte [line+6]
.again: dec bp
        jnz .next
        ret
write:  mov bx,1
        mov ah,40h
        int 21h
        ret
hide    db 27,'[>1h',0
show    db 27,'[>1l',0
clear   db 27,'[2J',0
home    db 27,'[H',0
line    db 'LINE #01',13,10
line_end:
unknown db 27,'[2X|',27,'[>2h|',27,'Z|',27,'[>',13,10
unknown_end:
method  db 0
