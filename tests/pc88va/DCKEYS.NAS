; NASM -f bin DCKEYS.NAS -o DCKEYS.COM. Use a disposable disk.
; DCKEYS V: compare baseline DCh with neighboring unassigned vectors.
; DCKEYS U: unknown function only. DCKEYS L: use the default Shift+F9/10
; definitions for F9/10 to compare unlabelled display without Shift.
; DCKEYS P: read one byte from Shift+F1, redefine it, read one more byte.
; Otherwise sample reads/writes and leave F1 and Shift+F1 with visible
; labels and distinct input strings.
; DC.OUT: repeated records of input AX/CX, output AX/flags (words), followed
; by 800 bytes of buffer (initially CCh for reads); V prints classification.
cpu 8086
org 100h
    cld
    mov al,[82h]
    and al,0dfh
    cmp al,'V'
    je vector
    cmp al,'L'
    jne .not_label
    jmp labels
.not_label:
    cmp al,'P'
    jne .not_pending
    jmp pending
.not_pending:
    mov [mode],al
    mov dx,filename
    xor cx,cx
    mov ah,3ch
    int 21h
    jnc .opened
    jmp error
.opened:
    mov [handle],ax
    cmp byte [mode],'U'
    jne .normal
    mov ax,1234h
    mov cx,55ffh
    call read
    jmp finish
.normal:
    mov si,selectors
.next:
    lodsw
    cmp ax,0ffffh
    je .writes
    push si
    mov cx,550ch
    call read
    pop si
    jmp .next
.writes:
    mov si,longslot
    mov ax,1
    call write
    mov ax,0
    call readkey
    mov si,f1slot
    mov ax,1
    call write
    mov si,sf1slot
    mov ax,0bh
    call write
    mov ax,0
    call readkey
finish:
    mov bx,[handle]
    mov ah,3eh
    int 21h
    mov ah,0dh                  ;Flush DOS disk metadata for host extraction.
    int 21h
    mov ax,4c00h
    int 21h
error:
    mov ax,4c01h
    int 21h

labels:
    mov ax,13h
    mov bx,9
    call copykey
    mov ax,14h
    mov bx,10
    call copykey
    jmp finish_vector
copykey:
    push bx
    mov dx,buf
    mov cl,0ch
    int 0dch
    pop ax
    mov cl,0dh
    int 0dch
    ret

pending:
    mov ah,7
    int 21h
    cmp al,'d'
    jne error
    mov ax,0bh
    mov dx,sf1slot
    mov cl,0dh
    int 0dch
    mov ah,7
    int 21h
    cmp al,'z'
    jne error
    mov dx,pending_ok
    mov ah,9
    int 21h
    jmp finish_vector

vector:
    xor ax,ax
    mov es,ax
    mov bx,[es:0dch*4]
    mov dx,[es:0dch*4+2]
    mov si,shared
    cmp bx,[es:0dbh*4]
    jne .different
    cmp dx,[es:0dbh*4+2]
    jne .different
    cmp bx,[es:0ddh*4]
    jne .different
    cmp dx,[es:0ddh*4+2]
    je .classify
.different:
    mov si,distinct
.classify:
    mov ax,dx
    or ax,bx
    jz .null
    mov es,dx
    mov dx,iretmsg
    cmp byte [es:bx],0cfh
    je .show
    mov dx,other
    jmp .show
.null:
    mov dx,nullmsg
.show:
    mov ah,9
    int 21h
    mov dx,si
    mov ah,9
    int 21h
    jmp finish_vector

write:
    push ax
    call fill
    mov di,buf
    mov cx,20
    rep movsb
    pop ax
    mov cx,550dh
    jmp invoke
readkey:
    mov cx,550ch
read:
    push ax
    push cx
    call fill
    pop cx
    pop ax
invoke:
    mov [record],ax
    mov [record+2],cx
    mov dx,buf
    stc
    int 0dch
    pushf
    push cs
    pop ds
    mov [record+4],ax
    pop ax
    mov [record+6],ax
    cld
    mov bx,[handle]
    mov cx,808
    mov dx,record
    mov ah,40h
    int 21h
    jc error
    cmp ax,808
    jne error
    ret
fill:
    push cs
    pop es
    mov di,buf
    mov cx,800
    mov al,0cch
    cld
    rep stosb
    ret
finish_vector:
    mov ax,4c00h
    int 21h

shared db 'Matches DBh and DDh',13,10,'$'
distinct db 'Differs from DBh or DDh',13,10,'$'
nullmsg db 'DCh: null vector',13,10,'$'
iretmsg db 'DCh: immediate IRET',13,10,'$'
other db 'DCh: nontrivial vector',13,10,'$'
pending_ok db 'Pending input dropped, ordinary z received',13,10,'$'
filename db 'DC.OUT',0
selectors dw 0,1,2,0bh,14h,15h,17h,1fh,20h,2ah,39h,3ah,3bh,0ffh,100h,0ffffh
longslot db 'ABCDEFGHIJKLMNOPQRST'
f1slot db 0feh,'NEW  ','f-one',0,0,0,0,0,0,0,0,0
sf1slot db 0feh,'SHIFT','s-one',0,0,0,0,0,0,0,0,0
handle dw 0
mode db 0
record times 8 db 0
buf times 800 db 0
