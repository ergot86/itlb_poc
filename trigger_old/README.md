This is a direct derivative of the original fuzzcase that found the bug, and is thus very messy.
However, it works across more CPU models than our newer PoC.

**Requires to set up the VMs with SMP (works with 2 CPUs but uses up to 8 for faster triggering).**

Usually it takes from 10 seconds to 10 minutes to trigger, with a few systems taking up to 6 hours.

Works in
- Hyperv (gen2 only)
- VirtualBox (BIOS boot)
- VMware Workstation and ESXi (BIOS boot)

Does not work in KVM, or Hyper-V gen1. Due MMIO areas of virtual hardware, they have 4k EPT mappings in low memory preventing large pages
from being used here, and the trigger uses hardcoded addresses in this range. This can be observed by dumping the EPT mappings of Hyper-V (use https://github.com/ergot86/crap/blob/main/hyperv_stuff.js).
