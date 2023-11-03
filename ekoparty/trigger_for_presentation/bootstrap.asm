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

msg_r10:
	db 'R10: ',0
msg_r11:
	db 'R11: ',0
msg_r12:
	db 'R12: ',0
msg_r13:
	db 'R13: ',0
msg_r14:
	db 'R14: ',0

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
mov eax, 0x01200003 + 64 + 32 ; A/D bits set!!!
init_pte:
mov dword [edi], eax
add eax, 0x1000
add edi, 8
dec ecx
jnz init_pte
mov edi, pd

mov ecx, 16
mov eax, 0x83; + 0x40
init_pde:
mov dword [edi], eax
add eax, 0x200000
add edi, 8
dec ecx
jnz init_pde

mov ecx, 512 - 16
mov eax, 0x83; + 0x40;0x60
init_pde_upper:
mov dword [edi], eax
add edi, 8
dec ecx
jnz init_pde_upper


mov dword [pdpt], pd + 3
mov dword [pdpt+0x08], pd + 3 
mov dword [pdpt+0x10], pd + 3 
mov dword [pdpt+0x18], pd + 3 
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
mov eax, 0x8000003b + 0x10000; PG | PE | MP | TS | ET | NE

mov cr0, eax
jmp 0x08:code64
[bits 64]

code64:
mov ax, 0x10
mov ds, ax
mov es, ax
mov ss, ax


;build code for the trigger

;0x01000000 is where 2M page will point
;0x01200000 is where 4K page will point

;we set them to the same contents: a MOV [R8],R10 instruction crossing the 4K boundary

	mov	dword [0x01000ffe],0x9010894d	; mov [r8],r10 ; nop
	mov	word  [0x01001002],0xe3ff	; jmp rbx

	mov	dword [0x01200ffe],0x9010894d	; mov [r8],r10 ; nop
	mov	word  [0x01201002],0xE3FF	; jmp rbx

;you can change the contents at 0x01201000 to see that it's not loading
;the TLB with the actual 4K page but with a "4K page" split from the 2M page

;triggers as well! though not universally single-shot
	;mov	dword [0x01201000],0xccCCccCC	; will be mov r12,r9;int3 together with the code from previous page

;JMP RBX, used when loading the page into the iTLB
	mov	word [0x0120000b],0xe3ff 
 

try_trigger:
	mov	qword [pt],0x01200003 | 0x20 ; disable D for first page (0x01000000)
	mov	qword [pd + 64],pt + 3

	mov	rax,pml4
	mov	cr3,rax


;load the 4k page into iTLB (+sTLB)
	lea	rbx,[return]
	mov	rax,0x0100000b
	jmp	rax
return:


;evict the sTLB by spamming it with data accesses
	mov 	r8,0x01600000
evict_stlb:
	mov	r9,[r8]
	add	r8,0x200000
	cmp	r8,0x33400000
	jnz	evict_stlb

	mfence

	lea	rbx,[return2]

;set addr that will be written to (to trigger D bit update)
;you can play with the addr and with the actual instruction used to see that
;it can be triggered (but not always as reliably) under different
;conditions, such as A bit update
	mov	r8,0x01000ff0

;set address that will be jumped to (page-crossing instruction)
	mov	rax,0x01000ffe

;flip page to 2M in page tables
	mov	qword [pd + 64],0x01000083

;jump to page crossing instruction
	jmp	rax

return2:

;should never be reached!
;comment out next jmp to see if it's really single-shot
	jmp	try_trigger

infinite:
	jmp	infinite





