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

idtr:
dw 0			; IDT limit
dq 0			; IDT base

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
cli

mov edi, pt
mov ecx, 512
mov eax, 0x01000003
init_pte:
mov dword [edi], eax
add eax, 0x1000
add edi, 8
dec ecx
jnz init_pte

mov edi, pd
mov ecx, 512
mov eax, 0x83
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
lidt [idtr]
mov eax, 0x1ba      ; PVI | DE | PSE | PAE | PGE | PCE
mov cr4, eax
;mov eax, 0x8000003b ; PG | PE | MP | TS | ET | NE
mov eax, 0xc000003b ; PG | PE | MP | TS | ET | NE | CD
mov cr0, eax
jmp 0x08:code64
[bits 64]
code64:
wbinvd
mov ax, 0x10
mov ds, ax
mov es, ax
mov ss, ax


BIG_ADDR	equ	0x02000000

;address corresponding to page we'll be flipping
CODE_ADDR	equ	0x01000000

;clear screen
	mov	rdi,0xb8000
	xor 	rax,rax
	mov 	rcx,(2*80*24)/8
	rep 	stosq

;point CODE_ADDR to small page followed by address of big page
	mov	qword [pt + 2 * 8],BIG_ADDR | 0x3
	mov	qword [pt + 3 * 8],(BIG_ADDR + 0x1000) | 0x3

	mov 	qword [pd + 64],pt+3

	mov 	rax,cr3
	mov 	cr3,rax

	mov	rdi,CODE_ADDR

;ret at beginning for iTLB fill
	mov	al,0xc3 ;ret
	stosb

;NOPs until 1 byte before end of page
	mov	rcx,0xfff-1
	mov 	al,0x90 ;nop
	rep 	stosb

;followed by
	;CALL lbl [straddling page boundary]
	;lbl: JMP RBX

	mov	al,0xe8 ;call immediate
	stosb
	mov	al,0x00
	stosb
	mov	al,0x00
	stosb
	stosb
	stosb

	mov	al,0xff ;jmp rbx
	stosb
	mov	al,0xe3
	stosb

;copy code to adress large page will be pointing to so they are identical
	mov	rsi,CODE_ADDR
	mov	rdi,CODE_ADDR + 2 * 0x1000 ; address of large page
	mov	rcx,0x2000/8
	rep	movsq

gogo:
	lea	rbx,[retloc]

	mov 	r15,CODE_ADDR


;point PDE to PT with small pages
	mov 	qword [pd + 64],pt + 3

	mov 	rax,cr3
	mov 	cr3,rax

;load 4k page into iTLB + sTLB from page tables
	call 	r15 

;flip to large page in page table
	mov 	qword [pd + 64], BIG_ADDR | 0x83 

;save rsp
	mov 	r8,rsp

;point stack into a 4k page covered by the large page
	lea 	rsp,[r15 + 0x1800]

;bump past initial RET
	add 	r15,1


;jump into the 4k page
	jmp	r15

retloc:
;we come back here in case trigger fails, so restore stack and try again
	mov 	rsp,r8


	jmp	gogo

infinite:
	jmp infinite



