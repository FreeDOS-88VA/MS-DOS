; Test-only: pump CON until Ctrl, then leave the firmware queue alone
; until KANA. Ctrl and KANA themselves do not enqueue keys.
bits 16
org 100h
    mov dx, msg
    mov ah, 9
    int 21h
.pumping:
    mov ah, 0bh
    int 21h
    mov ah, 0bh
    int 82h
    test al, 20h
    jz .pumping
.wait_kana:
    mov ah, 0bh
    int 82h
    test al, 08h
    jz .wait_kana
    mov ah, 0bh
    int 21h
    mov ax, 4c00h
    int 21h
msg db 'Polling until Ctrl, then use KANA to resume.',13,10,'$'
