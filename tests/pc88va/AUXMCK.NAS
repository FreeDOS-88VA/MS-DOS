; SPDX-License-Identifier: MIT
; NASM -f bin. Exercises the assembled AUX/COM1 driver with a BIOS mock.
org 100h
bits 16
cpu 186

    mov ax,358ah
    int 21h
    mov [old],bx
    mov [old+2],es
    mov dx,mock
    mov ax,258ah
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
    cmp word [es:bx+10],'CO'
    jne .next
    cmp word [es:bx+12],'M1'
    je .found
.next:
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
    mov byte [cmd],6
    call request
    cmp word [status],0300h
    jne done
    mov byte [queued],1
    mov byte [cmd],5
    call request
    cmp word [status],0100h
    jne done
    cmp byte [peek],95h
    jne done
    cmp byte [queued],1
    jne done

    inc byte [stage]
    mov byte [cmd],4
    mov word [count],1
    call request
    cmp word [status],0100h
    jne done
    cmp byte [bytebuf],95h
    jne done
    cmp byte [queued],0
    jne done
    mov byte [queued],1
    mov byte [cmd],7
    call request
    cmp byte [queued],0
    jne done

    inc byte [stage]
    mov byte [cmd],8
    mov word [count],1
    call request
    cmp word [status],0100h
    jne done
    cmp word [last],0095h
    jne done
    mov byte [modem],40h         ; CTS inactive
    mov byte [cmd],10
    call request
    cmp word [status],0300h
    jne done
    mov byte [cmd],8
    mov word [count],1
    call request
    cmp word [status],8102h
    jne done
    cmp word [count],0
    jne done
%ifndef STARTDEV
    inc byte [stage]
    mov byte [modem],0
    mov dl,'U'
    mov ah,4
    int 21h
    cmp word [last],'U'
    jne done
    mov byte [queued],1
    mov ah,3
    int 21h
    cmp al,95h
    jne done
    cmp byte [queued],0
    jne done
%endif
    mov byte [stage],'P'
done:
    push ds
    lds dx,[old]
    mov ax,258ah
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
    cmp ah,6
    je .status
    cmp ah,1
    je .send
    cmp ah,0ch
    je .flush
    cmp byte [cs:queued],0
    je .empty
    mov dx,95h
    xor al,al
    cmp ah,4
    je .return
.flush:
    mov byte [cs:queued],0
    jmp short .return
.empty:
    or word [ss:bp+6],1
    jmp short .return
.status:
    mov dl,1
    mov dh,[cs:modem]
    jmp short .return
.send:
    mov [cs:last],dx
.return:
    pop bp
    iret

old dd 0
strategy dd 0
driver dd 0
last dw 0
queued db 0
modem db 0
bytebuf db 0
msg db 'AUXMCK: '
stage db '0',13,10,'$'
packet db 22,0
cmd db 0
status dw 0
    times 8 db 0
peek db 0
xfer dw bytebuf,0
count dw 0
    dw 0

%ifdef STARTDEV
    align 16
ioimage: incbin 'IO.SYS'
%endif
