; Scratch boot-sector probe for the INT DCh vector before DOS loads.
; Assemble with NASM -f bin and replace sector 0 (not its D88 header)
; on a disposable VA 2HD image. Capture registers at 3000:0100:
; AL bit 0 = same as DBh and DDh, bit 1 = immediate IRET, bit 2 = null.
; No vector pointers are output; the sector does not call DCh.
cpu 8086
org 0
    jmp short start
    nop
    times 62-($-$$) db 0       ; Space for a scratch disk's BPB.
start:
    cli
    xor ax,ax
    mov ds,ax
    mov bx,[0dch*4]
    mov dx,[0dch*4+2]
    cmp bx,[0dbh*4]
    jne .target
    cmp dx,[0dbh*4+2]
    jne .target
    cmp bx,[0ddh*4]
    jne .target
    cmp dx,[0ddh*4+2]
    jne .target
    or al,1
.target:
    mov cx,bx
    or cx,dx
    jz .null
    mov es,dx
    cmp byte [es:bx],0cfh
    jne .done
    or al,2
    jmp short .done
.null:
    or al,4
.done:
    xor bx,bx
    xor cx,cx
    xor dx,dx
    mov ds,bx
    mov es,bx
    jmp near result
    times 100h-($-$$) db 0
result:
    jmp short result
    times 510-($-$$) db 0
    dw 0aa55h
    times 1022-($-$$) db 0
    dw 0aa55h
