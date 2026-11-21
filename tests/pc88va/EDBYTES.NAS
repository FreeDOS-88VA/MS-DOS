; SPDX-License-Identifier: MIT
; nasm -f bin EDBYTES.NAS -o EDBYTES.COM
; Read one DOS 0Ah line, print its byte count and bytes (including CR).
        bits 16
        org 100h
        mov dx, prompt
        mov ah, 09h
        int 21h
        mov dx, buffer
        mov ah, 0ah
        int 21h
        mov dx, result
        mov ah, 09h
        int 21h
        xor cx, cx
        mov cl, [buffer+1]
        mov al, cl
        call hexbyte
        inc cx                   ; include the terminating CR
        mov si, buffer+2
.next:
        mov dl, ' '
        call putc
        lodsb
        call hexbyte
        loop .next
        mov dx, newline
        mov ah, 09h
        int 21h
        mov ax, 4c00h
        int 21h
hexbyte:
        push ax
        shr al, 4
        call nibble
        pop ax
        and al, 0fh
nibble:
        add al, '0'
        cmp al, '9'
        jbe .digit
        add al, 'A'-'9'-1
.digit:
        mov dl, al
putc:
        mov ah, 02h
        int 21h
        ret
prompt: db 'EDIT>','$'
result: db 13,10,'BYTES: ','$'
newline: db 13,10,'$'
buffer: db 32,0
        times 32 db 0
