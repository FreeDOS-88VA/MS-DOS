; SPDX-License-Identifier: MIT
; CRC-16/IBM (initial zero), DS:SI / CX bytes -> DX; clobbers AX,CX,SI.
CRC16:  XOR     DX,DX
CRC16B: LODSB
        XOR     DL,AL
        MOV     AH,8
CRC16L: SHR     DX,1
        JNC     CRC16N
        XOR     DX,0A001H
CRC16N: DEC     AH
        JNZ     CRC16L
        LOOP    CRC16B
        RET
