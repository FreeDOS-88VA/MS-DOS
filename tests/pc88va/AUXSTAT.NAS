; Exercise DOS IOCTL input status without consuming AUX input.
        cpu 8086
        org 100h

        mov ax,3d00h
        mov dx,device
        int 21h
        jc error
        mov bx,ax
        mov ax,4406h
        int 21h
        jc error
        mov dx,ready
        cmp al,0ffh
        je print
        mov dx,empty
        test al,al
        jz print
error:  mov dx,bad
print:  mov ah,9
        int 21h
        mov ax,4c00h
        int 21h

device: db 'AUX',0
ready:  db 'AUX READY',13,10,'$'
empty:  db 'AUX EMPTY',13,10,'$'
bad:    db 'AUX STATUS ERROR',13,10,'$'
