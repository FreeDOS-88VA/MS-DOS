; SPDX-License-Identifier: MIT
; BOOTMENU.DAT occupies one FAT12 cluster; first 4 KiB are in use.
; The first physical block is the sole mutable metadata block; the
; next three KiB hold saved IPLs for IDs 1..3. ID 0 means MS-DOS.
STATESEG EQU    3800H
ST_SIG1 EQU     0               ;'VB'
ST_SIG2 EQU     2               ;'M1'
ST_OWNER EQU    4
ST_LAST EQU     5
ST_PHASE EQU    6               ;0 clean, 1 switch, 2 prepared, 3 capture, 4 remove.
ST_NEXT EQU     7
ST_PREP EQU     8               ;Four word-sized placeholder root slots.
ST_ENT  EQU     16
ST_VER  EQU     118             ;0 original, 1 replayable, 2 startup pairs, 3 long labels.
ST_FLAGS EQU    119             ;Bit 0: keep the previous menu default.
ST_CAPPAIR EQU  120             ;1: park the standalone PC-Engine pair in capture.
ST_PAIR EQU     122             ;4 x (slot or FFFFh, metadata CRC), park then activate.
ST_LABELS EQU   138             ;Version 3: three 24-byte labels, in ID order.
PAIRVER EQU     2
STATEVER EQU    3
LABELLEN EQU    24
ST_CSUM EQU     254
ENTRYLEN EQU    34
OLDLABELLEN EQU 16             ;Version 0–2 label at the start of each entry.
EN_CSUM EQU     16              ;CRC of saved 1024-byte IPL.
EN_FILES EQU    18              ;4 x (root slot word, metadata CRC word).
DOSID   EQU     0
MAXID   EQU     3
