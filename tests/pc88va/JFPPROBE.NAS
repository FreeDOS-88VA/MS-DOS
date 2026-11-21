; Disposable cold-boot DOS probe. Do not run on a production system.
; Options run left-to-right: I=InitScr+AlcSysL, K=IntKb, R=ResJFP,
; S=SetJFP on (half-width alpha), J=SetJFP on (full-width kana),
; F=KbFlsh, H=hide the label row via DOS, T=Sug1st for the reading 'nihon',
; P=primitive key poll,
; G=main key poll even if callback is null, B=blocking GetChar (unguarded).
; Otherwise poll main only if the documented callback is non-null.
; Log lives in guest RAM; no BIOS display/output calls during key sampling.
; The INT 21h hook chains through, but is not uninstalled. End the run by
; stopping the emulator; use a fresh cold boot and disk copy for each case.
cpu 8086
org 100h
    jmp start

log_magic db 'J30PROBE-2026',0
phase db 0                     ; a call in progress, '.' when sampling
mode db 0
get_ax dw 0                    ; GetJFP result after setup, AX/DX
get_dx dw 0
nkeys dw 0
n21 dw 0
stages times 16 db 0           ; each successfully returned option
int21_log times 128 db 0       ; AH seen, up to 128 calls
keys times 192 dw 0            ; 48 sets: sense AX/BX, get AX/BX
candidate times 128 db 0
old21 dd 0
options times 16 db 0
reading db 82h,0c9h,82h,0d9h,82h,0f1h,0  ; ni-ho-n, Shift-JIS
hide db 1bh,'[>1h'
hide_len equ $-hide

start:
    push cs
    pop ds
    push cs
    pop es
    cld
    mov si,81h
    mov di,options
    xor cx,cx
    mov cl,[80h]
.copy:
    jcxz .hook
    lodsb
    cmp al,' '
    je .next
    and al,0dfh
    stosb
    cmp di,options+15
    je .hook
.next:
    loop .copy
.hook:
    xor ax,ax
    mov es,ax
    cli
    mov ax,[es:21h*4]
    mov [old21],ax
    mov ax,[es:21h*4+2]
    mov [old21+2],ax
    mov word [es:21h*4],int21_probe
    mov [es:21h*4+2],cs
    sti
    mov si,options
    mov di,stages
.step:
    lodsb
    or al,al
    jz sample
    mov [phase],al
    push ds
    push si
    push di
    cmp al,'I'
    je .editor
    cmp al,'K'
    je .kb
    cmp al,'R'
    je .reset
    cmp al,'S'
    je .set
    cmp al,'J'
    je .set_kana
    cmp al,'T'
    je .convert
    cmp al,'F'
    je .flush
    cmp al,'H'
    je .hide
    mov [mode],al
    jmp short .returned
.editor:
    mov ax,0004h
    int 94h
    mov ax,010ah
    int 94h
    jmp short .returned
.kb:
    mov ax,0500h
    int 82h
    jmp short .returned
.reset:
    mov cx,2
    int 8dh
    jmp short .returned
.set_kana:
    mov ax,0f03h               ; enabled, no screen switch/dictionary edit/gaiji
    jmp short .set_common
.set:
    mov ax,0f00h
.set_common:
    mov cx,1
    mov dx,3c1eh
    int 8dh
    jmp short .returned
.convert:
    mov cx,4
    mov si,reading
    mov di,candidate
    int 8dh
    jmp short .returned
.flush:
    mov ax,0400h
    int 82h
    jmp short .returned
.hide:
    mov ax,4000h
    mov bx,1
    mov cx,hide_len
    mov dx,hide
    int 21h
.returned:
    pop di
    pop si
    pop ds
    mov al,[phase]
    mov [di],al
    inc di
    jmp .step

sample:
    mov byte [phase],'E'
    mov ax,0201h                ; ExpCtrl, no ROM expansion
    int 82h
    mov byte [phase],'Q'
    xor cx,cx
    mov ax,0a55ah
    mov dx,0a55ah
    int 8dh                    ; GetJFP
    mov [get_ax],ax
    mov [get_dx],dx
    mov byte [phase],'.'
    cmp byte [mode],'B'
    je blocking
    cmp byte [mode],'P'
    je poll
    cmp byte [mode],'G'
    je poll
    mov ax,0abh
    mov es,ax
    mov ax,[es:01deh]
    or ax,[es:01e0h]
    jnz poll
    mov byte [phase],'N'       ; null callback: deliberately skip the main path
.idle:
    jmp short .idle
poll:
    cmp word [nkeys],48
    jae .done
    mov ah,1
    cmp byte [mode],'P'
    jne .sense
    mov ah,0ah
.sense:
    mov bx,0a55ah
    int 82h
    jc poll
    push ax
    push bx
    mov ah,0
    cmp byte [mode],'P'
    jne .get
    mov ah,9
.get:
    mov bx,0a55ah
    int 82h
    call record
    jmp short poll
.done:
    mov byte [phase],'F'
    jmp short .done
blocking:
    xor ax,ax
    push ax
    push ax
    mov bx,0a55ah
    int 82h
    call record
    jmp short blocking

record:
    ; Pull saved sense AX/BX from the caller's stack, then restore depth.
    pop cx
    pop dx
    pop si
    push cx
    mov di,[nkeys]
    shl di,1
    shl di,1
    shl di,1
    mov [keys+di],si
    mov [keys+di+2],dx
    mov [keys+di+4],ax
    mov [keys+di+6],bx
    inc word [nkeys]
    cmp word [nkeys],48
    je poll.done
    ret

int21_probe:
    pushf
    push bx
    mov bx,[cs:n21]
    cmp bx,128
    jae .chain
    mov [cs:int21_log+bx],ah
    inc word [cs:n21]
.chain:
    pop bx
    popf
    jmp far [cs:old21]
