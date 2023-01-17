# itlb_poc
iTLB multihit PoC


## How to use
- For most hypervisors (and Gen1 on hyper-v): create a VM with a bootable disk pointing to `poc_bios.iso`.
- For Gen2 hyper-v: create a VM with *secure boot* disabled, and a bootable disk poiting to `poc_efi.iso`.

Launching the VM should crash the host in less than a minute.

Btw, to avoid some extra fun disable automatic start for VMs.


