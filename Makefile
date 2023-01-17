MKRESCUE = /usr/bin/grub-mkrescue
GRUB_EFI_FLAGS = -d /usr/lib/grub/x86_64-efi/
GRUB_BIOS_FLAGS = -d /usr/lib/grub/i386-pc/
OBJECTS = bootstrap.o

all: poc_efi.iso poc_bios.iso

bootstrap.o : bootstrap.asm
	nasm -felf64 $< -o $@

poc_efi.iso: iso/boot/kernel
	$(MKRESCUE) $(GRUB_EFI_FLAGS) -o $@ iso

poc_bios.iso: iso/boot/kernel
	$(MKRESCUE) $(GRUB_BIOS_FLAGS) -o $@ iso

iso/boot/kernel: $(OBJECTS)
	$(LD) -melf_x86_64 --section-start=".ap_code"=0x01000000 $^ -o $@

clean:
	rm -f *.o iso/boot/kernel *.iso

