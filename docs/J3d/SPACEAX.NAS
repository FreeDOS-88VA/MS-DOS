; Foreground DOS probe. Print PrmGetK AX and PrmSfts AL until Return.
bits 16
org 100h
    mov dx, ready
    mov ah, 9
    int 21h
.poll:
    mov ah, 0ah                 ; PrmSnsK
    int 82h
    jc .poll
    mov ah, 09h                 ; PrmGetK
    int 82h
    cmp al, 0dh
    je .done
    push ax
    mov ah, 0bh                 ; PrmSfts
    int 82h
    mov [shift], al
    pop bx
    mov cx, 4
    call hex
    mov bx, [shift]
    mov cx, 2
    ror bx, 8
    call hex
    mov dl, ' '
    mov ah, 02h
    int 21h
    jmp .poll
.done:
    mov ax, 4c00h
    int 21h
hex:
.hex:
    rol bx, 4
    mov dl, bl
    and dl, 0fh
    add dl, '0'
    cmp dl, '9'
    jbe .print
    add dl, 'A'-'9'-1
.print:
    mov ah, 02h
    int 21h
    loop .hex
    ret
ready db 'AX: $'
shift dw 0
