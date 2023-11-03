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

msg_old_pd:
	db 'Old PDE:    ',0
msg_new_pd:
	db 'New PDE:    ',0
msg_mem_before:
	db 'Code before:',0
msg_mem_after:
	db 'Code after: ',0
msg_mem_during:
	db 'Counter:    ',0
msg_mem_later:
	db 'Code later: ',0


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

;physical address of large page
BIG_ADDR	equ	0x02000000

;address corresponding to page we'll be flipping
CODE_ADDR	equ	0x01000000

;offset of code in 4k page (preceeded by NOPs)
CODE_OFFSET	equ	0xf00

;clear screen
	mov 	rdi,0xb8000
	xor 	rax,rax
	mov 	rcx,(2*80*24)/8
	rep 	stosq

;flip CODE_ADDR to large page
	mov 	qword [pd + 64], BIG_ADDR | 0x83
	mov 	rax,cr3
	mov 	cr3,rax

;fill mem where large page points with 0xc3 (ret), so it instantly returns
	mov 	rdi,CODE_ADDR
	mov 	rcx,0x1000
	mov 	al,0xc3 ;ret
	rep 	stosb


;flip CODE_ADDR to small page
	mov 	qword [pd + 64],pt+3
	mov 	rax,cr3
	mov 	cr3,rax

;build code where small page points 
;small page does inc r12, and xor rax,rax to mark that it was executed
	mov 	rdi,CODE_ADDR

;first a RET that's called to load the page into iTLB
	mov 	al,0xc3
	stosb

;then bump counter
	mov 	eax,0x90c4ff49 ; inc r12
	stosd

;then flush cache
	mov 	eax,0x3fae0f41
	stosd

;then NOPs
	mov 	rcx,CODE_OFFSET
	mov 	al,0x90
	rep 	stosb


;then xor rax,rax ; ret
	mov 	eax,0xc3c03148 ; xor rax,rax ; ret
	stosd



	mov 	r15,CODE_ADDR

;point PDE to PT with small pages
	mov	qword [pd + 64],pt + 3
	mov 	rax,cr3
	mov 	cr3,rax

;load 4k page into iTLB + sTLB from page tables
	call 	r15 

;flip to large page in page table
	mov 	qword [pd + 64],BIG_ADDR | 0x83 

;save rsp
	mov 	r8,rsp

;point stack into a 4k page covered by the large page
	lea 	rsp,[r15 + 0x2000]

;bump past initial RET
	add 	r15,1

;read old contents of PDE for large page
	mov 	r9,[pd + 64]

;reset counter
	xor 	r12,r12

;read old contents
	mov 	r13,[r15 + CODE_OFFSET]

;flush cache for the code
;note that this also loads it into dTLB
	clflush [r15]

;write back and invalidate cache
	wbinvd

;call into the 4k page

call_until_code_switches_over:
	mov 	eax,1
	call 	r15 

;can be uncommented to demonstrate that even writes to the VA of the
;code doesn't affect the instructions actually executed
;	mov 	[r15],dword 0xc3c3c3c3


	or 	eax,eax ;did xor rax,rax (from 4k page) execute?
	jz 	call_until_code_switches_over

;read new contents of PDE for large page
	mov 	r10,[pd + 64]

;read new contents of where we just called
	mov 	r11,[r15 + CODE_OFFSET]

;restore stack
	mov 	rsp,r8

;display results

	mov 	edi,0xb8000 + 160*0
	mov 	rbx,msg_old_pd
	mov 	rsi,r9
	call 	tohex

	mov 	edi,0xb8000 + 160*1
	mov 	rbx,msg_new_pd
	mov 	rsi,r10
	call 	tohex

	mov 	edi,0xb8000 + 160*2
	mov 	rbx,msg_mem_before
	mov 	rsi,r13
	call 	tohex

	mov 	edi,0xb8000 + 160*3
	mov 	rbx,msg_mem_during
	mov 	rsi,r12
	call 	tohex

	mov 	edi,0xb8000 + 160*4
	mov 	rbx,msg_mem_after
	mov 	rsi,r11
	call 	tohex

	mov 	edi,0xb8000 + 160*5
	mov 	rbx,msg_mem_later
	mov 	rsi,qword [r15 + CODE_OFFSET]
	call 	tohex



infinite:
	jmp infinite


;helper function to print a value as hex
tohex:
	mov 	ecx,4
	mov 	ax,0x0700

print_loop:
	mov 	al,[rbx]
	or 	al,al
	jz 	end_print_loop
	stosw
	inc 	rbx
	jmp 	print_loop

end_print_loop:

	mov 	bx,ax

tohex_loop:
	mov 	al,sil
	shr 	esi,8

	mov 	bl,al
	shr 	al,4
	and 	bl,0xf

	cmp 	al,0x9
	seta 	dl
	mov 	dh,dl
	shl 	dl,3
	sub 	dl,dh
	add 	al,dl
	add 	al,0x30

	cmp 	bl,0x9
	seta 	dl
	mov 	dh,dl
	shl 	dl,3
	sub 	dl,dh
	add 	bl,dl
	add 	bl,0x30

	stosw
	mov 	ax,bx
	stosw


	dec 	ecx
	jnz 	tohex_loop

	ret

