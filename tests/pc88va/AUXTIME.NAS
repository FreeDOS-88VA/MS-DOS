; Read 4096 'x' bytes through DOS binary AUX, after SPEED sets the baud.
; On vaeg, wait for AUX_READ and then CISTAT to measure guest frames.
        cpu 8086
        org 100h

        mov ax,3d00h
        mov dx,device
        int 21h
        jc fail
        mov bx,ax
        mov ax,4400h
        int 21h
        jc fail
        and dl,7fh              ; Keep only writable device-info bits.
        or dl,20h              ; Binary device mode.
        xor dh,dh
        mov ax,4401h
        int 21h
        jc fail
        mov ah,3fh
        mov cx,4096
        mov dx,buffer
        int 21h
        jc fail
        cmp ax,4096
        jne fail
        mov si,buffer
        mov cx,4096
check:  lodsb
        cmp al,'x'
        jne fail
        loop check
        mov dx,ok
        jmp short print
fail:   mov dx,bad
print:  mov ah,9
        int 21h
        mov ax,4c00h
        int 21h

device: db 'AUX',0
ok:     db 'RX4096 PASS',13,10,'$'
bad:    db 'RX4096 FAIL',13,10,'$'
buffer: times 4096 db 0
