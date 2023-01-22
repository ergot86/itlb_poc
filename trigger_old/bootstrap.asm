;;    SPDX-FileCopyrightText: 2022 TACITO SECURITY <staff@tacitosecurity.com>
;;    SPDX-License-Identifier: GPL-3.0-or-later
extern kmain
global _start, booted_cpus, go_aps, pt, pd
[bits 32]

[section .bss]
align 0x1000
resb 0x2000 * 16     ; 16x 8k stacks
stack_top:
pt: resb 0x1000     ; 1 PT (mirror)
pd: resb 0x1000 * 4 ; 4 PDs = maps 4GB
pdpt: resb 0x1000   ; 1 PDPT
pml4: resb 0x1000   ; 1 PML

[section .data]
gdt:                  ; minimal 64-bit GDT
dq 0x0000000000000000
dq 0x00A09b000000ffff ; kernel CS
dq 0x00C093000000ffff ; kernel DS
gdt_end:              ; TODO: TSS
gdtr:
dw gdt_end - gdt - 1  ; GDT limit
dq gdt                ; GDT base
booted_cpus: dd 0
go_aps: dd 0

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
mov eax, 0x03
init_pte:
mov dword [edi], eax
add eax, 0x1000
add edi, 8
dec ecx
jnz init_pte
mov edi, pd
mov ecx, 512*4
mov eax, 0x83
init_pde:
mov dword [edi], eax
add eax, 0x200000
add edi, 8
dec ecx
jnz init_pde
mov dword [pdpt], pd + 7
mov dword [pdpt+0x08], pd + 0x1007
mov dword [pdpt+0x10], pd + 0x2007
mov dword [pdpt+0x18], pd + 0x3007
mov dword [pml4], pdpt + 7
init_long_mode:
mov eax, pml4
cld
mov edi, 1
lock xadd dword [booted_cpus], edi
mov esi, edi
shl esi, 13
mov esp, stack_top
sub esp, esi
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
	or	edi,edi
	jnz	ap_ready_to_go

	mov	word [rdi + 0xb80a0],0x0742

	call	kmain
	int3

ap_ready_to_go:
	mov	word [rdi * 2 + 0xb80a0],0x0741

wait_for_go_aps_loop:
	cmp	dword [go_aps],0
	je	wait_for_go_aps_loop

goto_zero:
	xor	rax,rax
	jmp	rax

align 0x1000, int3

[global ap_code]
ap_code:
cli
mov rbx, 0x005b9000
mov cr3, rbx
mov rax,rbx
mov rsi,rbx
mov rdx,rbx
mov rbp, 0x1337
jmp eop
align 0x800, nop
times 0x7e0 nop
times 4 nop
[global eop]
eop:
inc rbp
add rdx,rbp
and edx,0x000ffF00
add edx,0x00100000
lea eax,[edx + 0x1000]
call rdx
;times 2 nop
db 0x00
[global ap_code_next]
ap_code_next:
;; next page
db 0x00
db 0xeb, 0xe1
times 0x700 db 0xeb, 0xfc
align 0x1000, int3
[global ap_code_end]
ap_code_end:

[global fiddle]
fiddle:
	cli


                    mov rcx, 0x00000001
                    mov rdi, 0x005b0000
                    mov r9, 0x005bb003
                    call write_pml4

                    mov rcx, 1
                    mov rdi, 0x005b9000
                    mov r9, 0x005bb003
                    call write_pml4

                    mov rcx, 1
                    mov rdi, 0x005bb000
                    mov r9, 0x005bd003
                    call write_pdpt

                    mov rcx, 1
                    mov rdi, 0x005bf000

                    mov r9, 0x90003
                    call write_pdpt

                    mov rcx, 0x00000032
                    mov rdi, 0x005bd000
                    mov r9, 0x00000083
                    call write_pde_big

                    mov qword [0x005bf000],0x00003003
                    mov qword [0x005bf008],0x00004003

		ret

[global twiddle]
twiddle:

                    cli


                    mov rax, 0deadf007deadf007h

                    here:
                    mfence
                    mov rcx, 2
                    mov rdi, 0x005bd000
                    mov r9, 0x00000083
                    call write_pde_big
                    mfence
                    mov qword [0x005bd000], 0x005bf003
                    mov qword [0x005bd008], 0x005bf003
                    jmp here
                    times 0x400 db 0xeb,0xfc

    write_pml4:
    write_pdpt:
    write_pde:
    write_pte:
        mov rsi, 0x1000
        jmp write_common
    write_pde_big:
        mov rsi, 0x200000
        jmp write_common
    write_common:
        mov rbx, 512
    write_common_:
        mov rdx, rcx ; count
        mov r8, r9  ; original entry
    write_common__:
        mov qword [rdi], r8
        add rdi, 8
        add r8, rsi
        dec rbx
        jz end
        dec rdx
        jnz write_common__
        jmp write_common_
    end:
        ret


;; AP Bootstrap code (@0x8000)
[section .bootstrap]
[bits 16]
cli
lgdt [ap_gdtr]
mov edx, 0x3b   ; PE | MP | TS | ET | NE
mov cr0, edx
mov eax, 0x10
mov ds, ax
mov es, ax
mov ss, ax
jmp 0x08:protected_mode
[bits 32]
protected_mode:
jmp init_long_mode

ap_gdt:
dq 0x0000000000000000
dq 0x00CF9A000000FFFF
dq 0x00CF92000000FFFF
ap_gdt_end:
ap_gdtr:
dw ap_gdt_end - ap_gdt - 1
dd ap_gdt

