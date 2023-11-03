This was one of the key experiments behind understanding the multihit bug
and producing the final trigger.

Apart from producing an interesting i/dTLB desync condition, it also serves
to illustrate:
- D bit update
- TLB entry replacement triggered by it
- Several other concepts of x86 paging
and is a good base for many experiments.

Suggested experiment:
Try varying the number of NOPs and you can see exactly where the dTLB entry
switches over. The exact number will differ quite a lot between different
CPUs - numbers between 0x10 and 0x100 have been observed.
If testing on bare metal, it helps to enable cache: change
mov eax, 0xc000003b
to
mov eax, 0x8000003b



