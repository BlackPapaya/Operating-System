org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

;
; FAT 12 HEADER
;
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1' 
bdb_bytes_per_sector:       dw 512              ; 8 bytes      
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1                ; GEFIXT: bdb statt dbd
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880             ; 2880 * 512 = 1.44MB     
bdb_media_descriptor_type:  db 0F0h             ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9                ; 9 sectors/fat
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; extended boot record
ebr_drive_number:           db 0                ; 0x00 floppy, 0x80 hdd
                            db 0                ; reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h ; serial number
ebr_volume_label:           db 'NANOBYTE  OS'
ebr_system_id:              db 'FAT12   '

start:
    jmp main

; prints a String to the screen
; params: ds:si points to string
puts:
    push si
    push ax
    push bx

.loop:
    lodsb       ; loads next character in al
    or al, al   ; check for null terminator
    jz .done

    mov ah, 0x0e
    mov bh, 0
    int 0x10

    jmp .loop

.done:
    pop bx
    pop ax
    pop si
    ret

main:
    ; setup data segments
    mov ax, 0
    mov ds, ax
    mov es, ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00

    ; save drive number from BIOS (in DL)
    mov [ebr_drive_number], dl

    ; read something from floppy disk
    mov ax, 1               ; LBA = 1 (second sector)
    mov cl, 1               ; 1 sector to read
    mov bx, 0x7E00          ; load address after bootloader
    mov dl, [ebr_drive_number]
    call disk_read

    ; print hello world message
    mov si, msg_hello
    call puts
	cli			;disable interrupts, CPU cant get out of halt state
    hlt

floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h                 ; wait for keypress
    jmp 0FFFFh:0            ; reboot

.halt:
    cli
    hlt

;
; Disk routines
;

; Converts an LBA address to a CHS address
; Parameters: ax = LBA Address
; Returns: cx [0-5]=sector, cx [6-15]=cylinder, dh = head
lba_to_chs:
    push ax
    push dx

    xor dx, dx                              ; dx = 0
    div word [bdb_sectors_per_track]        ; ax = LBA / SectorsPerTrack
                                            ; dx = LBA % SectorsPerTrack
    inc dx                                  ; sector
    mov cx, dx                              ; cx = sector

    xor dx, dx                              ; dx = 0
    div word [bdb_heads]                    ; ax = cylinder, dx = head
    mov dh, dl                              ; dh = head
    mov ch, al                              ; ch = cylinder (lower 8 bits)
    shl ah, 6
    or cl, ah                               ; put upper 2 bits of cylinder in CL

    pop ax                                  ; GEFIXT: ax (alter DX Wert) holen
    mov dl, al                              ; GEFIXT: Laufwerksnummer sauber in DL restaurieren
    pop ax                                  ; GEFIXT: ursprüngliches AX wiederherstellen
    ret

; Reads sectors from a disk
; Parameters: ax = LBA, cl = count, dl = drive, es:bx = buffer
disk_read:
    push ax
    push bx
    push cx
    push dx
    push di
    
    push cx                                 ; save CL (sector count)
    call lba_to_chs
    pop ax                                  ; AL = sector count for int 13h
    
    mov ah, 02h
    mov di, 3                               ; retry count

retry:
    pusha
    stc
    int 13h
    jnc .done

    ; read failed
    popa
    call disk_reset

    dec di
    test di, di
    jnz retry                               ; GEFIXT: ohne Punkt (war: jnz .retry)

.fail:
    jmp floppy_error    

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret

msg_hello:          db 'Hello World!', ENDL, 0
msg_read_failed:     db 'Read from disk failed!', ENDL, 0

times 510-($-$$) db 0
dw 0AA55h