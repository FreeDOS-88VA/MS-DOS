; SPDX-License-Identifier: MIT
; K1BYTES: trace keyboard BIOS results during DOS 0Ah. R uses DOS 08h.
; G/N only switch CON to graph/kanji mode. Test program, not resident.
        cpu 8086
        bits 16
        org 100h
        cmp byte [80h], 2
        jne probe
        mov dx, graph_on
        cmp byte [82h], 'G'
        je mode
        mov dx, graph_off
        cmp byte [82h], 'N'
        jne probe
mode:   call puts
        jmp done
probe:  mov dx, prompt
        call puts
        mov ax, 3582h
        int 21h
        mov [old], bx
        mov [old+2], es
        mov dx, hook
        mov ax, 2582h
        int 21h
        cmp byte [80h], 2
        jne cooked
        cmp byte [82h], 'R'
        jne cooked
        mov si, buffer+2
.raw:   mov ah, 08h
        int 21h
        mov [si], al
        inc si
        cmp al, 0dh
        je got
        inc byte [buffer+1]
        cmp byte [buffer+1], 31
        jb .raw
        mov byte [si], 0dh
        jmp short got
cooked: mov dx, buffer
        mov ah, 0ah
        int 21h
got:    push ds
        lds dx, [old]
        mov ax, 2582h
        int 21h
        pop ds
        mov dx, result
        call puts
        xor cx, cx
        mov cl, [buffer+1]
        mov al, cl
        call hexbyte
        inc cx
        mov si, buffer+2
.bytes: mov dl, ' '
        call putc
        lodsb
        call hexbyte
        loop .bytes
        mov dx, trace
        call puts
        mov si, log
.entry: cmp si, [next]
        je done
        mov cx, 6
.field: lodsb
        call hexbyte
        loop .field
        mov dl, ' '
        call putc
        jmp short .entry
done:   mov dx, newline
        call puts
        mov ax, 4c00h
        int 21h
hexbyte:
        push ax
        shr al, 1
        shr al, 1
        shr al, 1
        shr al, 1
        call nibble
        pop ax
        and al, 0fh
nibble: add al, '0'
        cmp al, '9'
        jbe .digit
        add al, 'A'-'9'-1
.digit: mov dl, al
putc:   mov ah, 02h
        int 21h
        ret
puts:   mov ah, 09h
        int 21h
        ret

; Chain the original handler. For the four read/sense interfaces, copy CF
; to the caller's frame and record ready returns only. No DOS calls here.
hook:   pushf
        cmp ah, 0ah
        je .read
        cmp ah, 09h
        je .read
        cmp ah, 01h
        je .read
        cmp ah, 00h
        je .read
        popf
        jmp far [cs:old]
.read:  mov [cs:fn], ah
        popf
        pushf
        call far [cs:old]
        push bp
        mov bp, sp
        jnc .ready
        or word [bp+6], 1
        jmp short .exit
.ready: and word [bp+6], 0fffeh
        push ax
        push di
        push es
        mov di, [cs:next]
        cmp di, log_end
        jae .skip
        mov [cs:di+1], ax
        mov al, [cs:fn]
        mov [cs:di], al
        cmp al, 2
        jae .primitive
        mov [cs:di+3], bx
.primitive:
        mov ax, 40h
        mov es, ax
        mov al, [es:6b0h]       ; BIOS work RAM: shift/lock status, not a ROM address.
        mov [cs:di+5], al
        add di, 6
        mov [cs:next], di
.skip:  pop es
        pop di
        pop ax
.exit:  pop bp
        iret

prompt: db 'EDIT>','$'
result: db 13,10,'BYTES: ','$'
trace:  db 13,10,'TRACE: ','$'
newline: db 13,10,'$'
graph_on: db 27,')3','$'
graph_off: db 27,')0','$'
buffer: db 32,0
        times 32 db 0
old:    dd 0
fn:     db 0
next:   dw log
log:    times 6*48 db 0          ; Function, AX, BX (main only), shift byte.
log_end:
