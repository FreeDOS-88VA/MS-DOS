; SPDX-License-Identifier: MIT
; NASM -f bin. Synthetic INT 89h replies; no ROM or printer data captured.
org 100h
bits 16
cpu 186

    mov ax,3589h
    int 21h
    mov [old],bx
    mov [old+2],es
    mov dx,mock
    mov ax,2589h
    int 21h

%ifdef STARTDEV
    mov ax,cs
    add ax,(ioimage-$$+100h)/16
    mov es,ax
    mov bx,STARTDEV
%else
    mov ah,52h
    int 21h
    les bx,[es:bx+12]             ; SYSI_CON
%endif
.find:
    cmp word [es:bx+10],'PR'
    je .found
%ifdef STARTDEV
    mov bx,[es:bx]
%else
    les bx,[es:bx]
%endif
    cmp bx,-1
    jne .find
    jmp done
.found:
    mov ax,[es:bx+6]
    mov [strategy],ax
    mov ax,[es:bx+8]
    mov [driver],ax
    mov [strategy+2],es
    mov [driver+2],es

    inc byte [stage]
%ifdef STARTDEV
    mov byte [cmd],8
    mov word [count],1
    mov word [xfer],ascii
    call request
%else
    mov dl,'A'
    mov ah,5
    int 21h
    mov byte [cmd],8
%endif
    cmp word [last],0041h
    jne done
    cmp byte [function],1        ; ANK uses the ROM's text mode
    jne done

    inc byte [stage]
%ifdef STARTDEV
    mov es,[driver+2]
    mov bx,[es:STARTDEV]         ; CON -> AUX (AUX -> COM1 on M3).
    mov bx,[es:bx]
    cmp word [es:bx+10],'CO'
    jne .prn
    mov bx,[es:bx]
.prn:
    mov bx,[es:bx]              ; PRN -> LPT1.
    cmp word [es:bx+10],'LP'
    jne done
    mov ax,[es:bx+8]
    mov [driver],ax
    mov word [xfer],bytes
    mov word [count],1
    call request
    cmp word [last],0041h
    jne done
    inc word [xfer]
    mov word [count],1
    call request
    cmp word [last],955ch
    jne done
    cmp byte [function],1
    jne done
%else
    mov dx,lpt
    mov ax,3d01h
    int 21h
    jc done
    mov bx,ax
    mov ax,4400h                  ; binary handle, no DOS cooked processing
    int 21h
    or dl,20h
    xor dh,dh
    mov ax,4401h
    int 21h
    jc done
    mov dx,bytes
    mov cx,1
    mov ah,40h
    int 21h
    jc done
    cmp word [last],0041h         ; lead is buffered, not emitted
    jne done
    inc dx
    mov ah,40h
    int 21h
    jc done
    cmp word [last],955ch
    jne done
    cmp byte [function],1
    jne done
    mov ah,3eh
    int 21h
%endif

    inc byte [stage]
    mov byte [cmd],16
    mov word [xfer],controls
    mov word [count],3
    mov byte [busy_after],1       ; first byte works; then BUSY
    call request
    cmp word [status],0100h
    jne done
    cmp word [count],1
    jne done
    cmp word [last],000dh
    jne done
    mov byte [cmd],10
    call request
    cmp word [status],0300h
    jne done

    inc byte [stage]
    mov byte [cmd],8              ; raw TAB failure while busy => not ready
    mov word [xfer],controls+2
    mov word [count],1
    mov byte [fail],1
    call request
    cmp word [status],8102h
    jne done
    cmp word [count],0
    jne done
    mov byte [busy],0             ; raw failure without busy => write fault
    mov word [count],1
    call request
    cmp word [status],810ah
    jne done
    cmp word [count],0
    jne done
    mov byte [stage],'P'
done:
    push ds
    lds dx,[old]
    mov ax,2589h
    int 21h
    pop ds
    mov dx,msg
    mov ah,9
    int 21h
    mov ax,4c00h
    cmp byte [stage],'P'
    je .exit
    inc ax
.exit:
    int 21h

request:
    push cs
    pop es
    mov [xfer+2],es
    mov bx,packet
    call far [strategy]
    call far [driver]
    ret

mock:
    push bp
    mov bp,sp
    and word [ss:bp+6],0fffeh
    test ah,ah
    jnz .write
    mov al,[cs:busy]
    jmp short .exit
.write:
    cmp byte [cs:fail],0
    je .sent
    or word [ss:bp+6],1
    jmp short .exit
.sent:
    cmp ah,1
    je .store
    xor dh,dh
.store:
    mov [cs:last],dx
    mov [cs:function],ah
    mov al,[cs:busy_after]
    mov [cs:busy],al
.exit:
    pop bp
    iret

old dd 0
strategy dd 0
driver dd 0
last dw 0
function db 0
busy db 0
busy_after db 0
fail db 0
bytes db 95h,5ch
ascii db 'A'
controls db 13,10,9
lpt db 'LPT1',0
msg db 'PRNMCK: '
stage db '0',13,10,'$'
packet db 22,0
cmd db 0
status dw 0
    times 9 db 0
xfer dw controls,0
count dw 0
    dw 0

%ifdef STARTDEV
    align 16
ioimage: incbin 'IO.SYS'
%endif
