; Scratch 2HD boot-sector probe: classify the documented keyboard callbacks
; before any DOS code loads. Inspect AX and DI at 3000:0100 in vaeg.
; DI=4B42h means KyBook returned the documented RAM location.
; AX bits 0/1 mean KbAddr/JFPAddr are nonzero; bit 2 means INT 8D is nonzero.
cpu 8086
org 0
    jmp short start
    nop
    times 62-($-$$) db 0
start:
    cli
    mov ax,3000h
    mov ss,ax
    mov sp,1000h
    sti
    mov ah,0eh
    int 82h                    ; KyBook: ES:DX
    mov bx,dx
    mov ax,es
    mov cl,4
    shl ax,cl
    add ax,bx
    xor di,di
    cmp ax,0ab0h
    jne result
    mov di,4b42h
    xor ax,ax
    mov ds,ax
    mov dx,[es:bx+01dah]
    or dx,[es:bx+01dch]
    jz .jfp
    or al,1
.jfp:
    mov dx,[es:bx+01deh]
    or dx,[es:bx+01e0h]
    jz .vector
    or al,2
.vector:
    mov dx,[8dh*4]
    or dx,[8dh*4+2]
    jz .done
    or al,4
.done:
    xor bx,bx                  ; No pointer values in the result.
    xor dx,dx
    jmp short result
    times 100h-($-$$) db 0
result:
    jmp short result
    times 510-($-$$) db 0
    dw 0aa55h
    times 1022-($-$$) db 0
    dw 0aa55h
