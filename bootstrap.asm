;;    SPDX-FileCopyrightText: 2022 TACITO SECURITY <staff@tacitosecurity.com>
;;    SPDX-License-Identifier: GPL-3.0-or-later
global _start
[bits 32]

[section .bss]
align 0x1000
pt: resb 0x1000      ; 1 PT (mirror)
pd: resb 0x1000      ; 1 PDs
pdpt: resb 0x1000    ; 1 PDPT
pml4: resb 0x1000    ; 1 PML

[section .data]
gdt:                  ; minimal 64-bit GDT
dq 0x0000000000000000
dq 0x00A09b000000ffff ; kernel CS
dq 0x00C093000000ffff ; kernel DS
gdt_end:              ; TODO: TSS
gdtr:
dw gdt_end - gdt - 1  ; GDT limit
dq gdt                ; GDT base

[section .text]
align 8, db 0
;; multiboot2 header
mb_header_size equ (mb_header_end - mb_header)
mb_header:
dd 0xE85250D6     ; magic field
dd 0              ; architecture field: i386 32-bit protected-mode
dd mb_header_size ; header length field
dd 0xffffffff & -(0xE85250D6 + mb_header_size) ; checksum field
;; termination tag
dw 0 ; tag type
dw 0 ; tag flags
dd 8 ; tag size
mb_header_end:
;; kernel code starts here
_start:
mov edi, pt
mov ecx, 512
mov eax, 0x01200003
init_pte:
mov dword [edi], eax
add eax, 0x1000
add edi, 8
dec ecx
jnz init_pte
mov edi, pd
mov ecx, 512
mov eax, 0x83; + 0x40;0x60
init_pde:
mov dword [edi], eax
add eax, 0x200000
add edi, 8
dec ecx
jnz init_pde
mov dword [pdpt], pd + 3
mov dword [pdpt+0x08], pd + 0x1003
mov dword [pdpt+0x10], pd + 0x2003
mov dword [pdpt+0x18], pd + 0x3003
mov dword [pml4], pdpt + 3
init_long_mode:
mov eax, pml4
cld
;; load page-tables
mov cr3, eax
mov ecx, 0xC0000080
rdmsr
or eax, 0x101       ; LME | SCE
wrmsr               ; set EFER
lgdt [gdtr]         ; load 64-bit GDT
mov eax, 0x1ba      ; PVI | DE | PSE | PAE | PGE | PCE
mov cr4, eax
mov eax, 0x8000003b ; PG | PE | MP | TS | ET | NE
mov cr0, eax
jmp 0x08:code64
[bits 64]
code64:
mov ax, 0x10
mov ds, ax
mov es, ax
mov ss, ax
mov rdi, 0x01100000
fill:
mov word [rdi], 0xE3FF ; jmp rbx
mov word [rdi+2], 0x0000
sfence
clflush [rdi]
add rdi, 0x1000
cmp rdi, 0x01200000
jnz fill
mov rsi, 0x01000000
mov rcx, 0x200000
rep movsb
mov rdi, 0x01100000
jnz fill
fill2:
clflush [rdi]
add rdi, 0x1000
cmp rdi, 0x01400000
jnz fill2
jmp call_ap

[section .ap_code]
call_ap:
reset:
mov rax, 0x01100000
next:
add rax, 0x1000
cmp rax, 0x01200000
jz reset
lea rbx, [rel return]
mov qword [pd + 64], 0x01000083
mfence
add ax, word [rax+2]
jmp rax
return:
sfence
mov qword [pd + 64], pt + 3
sfence
add [rax], al
jmp next

