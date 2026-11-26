        TITLE   Optional second stage for the PC-88VA SASI IPL
; SPDX-License-Identifier: MIT
CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE,DS:CODE
        ORG     0
        INCLUDE VAMENUCO.INC
CODE    ENDS
        END     MAIN
