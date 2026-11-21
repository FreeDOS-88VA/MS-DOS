; J1 kernel probe. Build: nasm -f bin J1DBCS.NAS -o J1DBCS.COM
; Run in a clean root. Writes J1API.OUT (format decoded by docs/J1/check.py).
; J1DBCS L reads one redirected 0Ah line and writes it to J1LINE.OUT.
bits 16
cpu 8086
org 100h

    cld
    mov al,[82h]
    and al,0dfh
    cmp al,'L'
    jne api
    mov dx,line
    mov ah,0ah
    int 21h
    xor cx,cx
    mov cl,[line+1]
    add cx,2                   ; count byte, contents and CR
    mov si,line+1
    mov dx,line_out
    jmp save
api:
    mov si,0ffffh
    mov ax,6300h
    push ds
    int 21h
    push cs
    pop es
    mov di,table
    cmp si,0ffffh             ; an unsupported service may leave SI alone
    je .no_table
    mov cx,6
    rep movsb
.no_table:
    pop ds
    mov dx,country_buf
    mov ax,3800h
    int 21h
    mov [country],bx

    mov dx,dta
    mov ah,1ah
    int 21h
    mov si,pairs
    mov di,results
.next:
    lodsw
    push si
    mov [sub],ax
    mov [path],ax
    mov [want_cwd],ax
    mov [old],ax
    mov [new],ax
    mov [fcbname],ax
    mov [fcbnew],ax

    call mkdir
    stosb
    mov dx,path
    call create
    stosb
    call cd_sub
    stosb
    mov dl,0
    mov si,cwd
    mov ah,47h
    int 21h
    jc .cwd_done
    mov ax,[cwd]
    cmp ax,[want_cwd]
    jne .cwd_bad
    mov ax,[cwd+2]
    cmp ax,'D'
    je .cwd_done
.cwd_bad:
    mov al,0ffh
    jmp short .cwd_store
.cwd_done:
    call status
.cwd_store:
    stosb
    mov dx,old
    mov ax,3d00h
    int 21h
    call close_status
    stosb
    mov [out_pos],di
    mov dx,old
    mov di,new
    mov ah,56h
    int 21h
    mov di,[out_pos]
    call status
    stosb
    mov dx,old
    mov ah,41h
    int 21h
    call status
    stosb                       ; old name must no longer exist
    mov dx,new
    mov ax,3d00h
    int 21h
    call close_status
    stosb                       ; leave renamed file for raw disk check
    mov dx,old
    call create
    stosb
    mov dx,old
    mov ah,41h
    int 21h
    call status
    stosb                       ; this time the existing file must be deleted

    ; Parse a name into an FCB, then create, close, open, close, rename, delete.
    mov [out_pos],di
    mov si,fcbname
    mov di,fcb
    xor ax,ax
    mov ah,29h
    int 21h
    mov di,[out_pos]
    stosb
    mov dx,fcb
    mov ah,16h
    int 21h
    stosb
    mov ah,10h
    int 21h
    stosb
    mov ah,0fh
    int 21h
    stosb
    mov ah,10h
    int 21h
    stosb
    mov [out_pos],di
    mov si,fcbnew
    mov di,fcb+16
    mov ax,2900h
    int 21h
    mov di,[out_pos]
    stosb
    mov dx,fcb
    mov ah,17h
    int 21h
    stosb
    mov dx,fcb+16
    mov ah,0fh
    int 21h
    stosb
    mov ah,10h
    int 21h
    stosb
    mov dx,fcbnew              ; independent ASCIIZ check of the FCB name
    mov ax,3d00h
    int 21h
    call close_status
    stosb
    mov dx,fcb+16
    mov ah,13h
    int 21h
    stosb
    mov ah,0fh
    int 21h
    stosb
    mov dx,root
    mov ah,3bh
    int 21h
    call status
    stosb

    ; Root directory with the pair at the END of the component: DOS must
    ; distinguish the trail from the following real path separator.
    mov ax,[sub]
    mov [temp+1],ax
    mov [temp_new+1],ax
    mov dx,temp
    mov ah,39h
    int 21h
    call status
    stosb
    mov [out_pos],di
    mov di,temp_new
    mov ah,56h
    int 21h
    mov di,[out_pos]
    call status
    stosb
    mov dx,temp_new
    test al,al
    jz .check_dir
    mov dx,temp                ; still exercise CD/RD when rename unsupported
.check_dir:
    push dx
    mov ah,3bh
    int 21h
    call status
    stosb
    mov dx,root
    mov ah,3bh
    int 21h
    pop dx
    mov ah,3ah
    int 21h
    call status
    stosb

    pop si
    cmp si,pairs_end
    je .wild
    mov [out_pos],di
    jmp .next
.wild:
    mov dx,wilddir
    mov ah,39h
    int 21h
    mov ah,3bh
    int 21h
    mov dx,kanji
    call create
    mov dx,ascii
    call create
    mov dx,kanjix
    call create
    mov dx,asciix
    call create
    mov si,patterns
    mov di,wild_results
.pat:
    lodsw
    mov dx,ax
    xor cx,cx
    mov ah,4eh
    int 21h
    xor bx,bx
.match:
    jc .pattern_done
    mov ax,[dta+30]
    cmp ax,[kanji]
    jne .is_ascii
    cmp byte [dta+32],'X'
    je .kanjix
    or bl,1
    jmp short .next_match
.kanjix:
    or bl,4
    jmp short .next_match
.is_ascii:
    cmp al,'A'
    jne .unknown
    cmp ah,'X'
    je .ax
    or bl,2
    jmp short .next_match
.ax:
    or bl,8
    jmp short .next_match
.unknown:
    or bl,80h
.next_match:
    push bx
    mov ah,4fh
    int 21h
    pop bx
    jmp .match
.pattern_done:
    mov al,bl
    stosb
    cmp si,patterns_end
    jb .pat
    mov dx,root
    mov ah,3bh
    int 21h
    mov dx,api_out
    mov si,table
    mov cx,report_end-table
save:
    push cx
    xor cx,cx
    mov ah,3ch
    int 21h
    pop cx
    jc exit_fail
    mov bx,ax
    mov dx,si
    mov ah,40h
    int 21h
    jc exit_fail
    cmp ax,cx
    jne exit_fail
    mov ah,3eh
    int 21h
    jc exit_fail
    mov ax,4c00h
    int 21h
exit_fail:
    mov ax,4c01h
    int 21h

mkdir:
    mov dx,sub
    mov ah,39h
    int 21h
    jmp short status
cd_sub:
    mov dx,sub
    mov ah,3bh
    int 21h
    jmp short status
create:
    xor cx,cx
    mov ah,3ch
    int 21h
close_status:
    jc status
    mov bx,ax
    mov ah,3eh
    int 21h
status:
    jc .bad
    xor al,al
.bad:
    ret

pairs: db 95h,5ch,83h,5ch,94h,5ch,90h,5ch,97h,5ch,81h,7ch,82h,61h
pairs_end:
sub: db 0,0,'d',0
path: db 0,0,'d',5ch
old: db 0,0,'a.txt',0
new: db 0,0,'b.txt',0
fcbname: db 0,0,'c.txt',0
fcbnew: db 0,0,'f.txt',0
temp: db 'T',0,0,0
temp_new: db 'U',0,0,0
want_cwd: db 0,0,'D',0
root: db 5ch,0
wilddir: db 'J1WILD',0
kanji: db 95h,5ch,'.TXT',0
ascii: db 'A.TXT',0
kanjix: db 95h,5ch,'X.TXT',0
asciix: db 'AX.TXT',0
patterns: dw star,q,qq,qx,qqx
patterns_end:
star: db '*.TXT',0
q: db '?.TXT',0
qq: db '??.TXT',0
qx: db '?X.TXT',0
qqx: db '??X.TXT',0
api_out: db 'J1API.OUT',0
line_out: db 'J1LINE.OUT',0
line: db 32,0
      times 33 db 0
out_pos: dw results
fcb: times 64 db 0
cwd: times 64 db 0
country_buf: times 40 db 0
dta: times 48 db 0
table: times 6 db 0
country: dw 0
results: times (pairs_end-pairs)/2*27 db 0
wild_results: times 5 db 0
report_end:
