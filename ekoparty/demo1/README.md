This is the same basic code as demo0, but shows how long it takes for the
iTLB contents to switch over from the old to the new page.

(Note that this is exactly the _opposite_ condition we want for triggering
the bug!)

This applies to (most) vulnerable CPUs.

In a VM, this will typically be until the next VM exit.
On bare metal, this will be forever or until the next SMI.
(Sometimes, this can be triggered by hitting various Fn+Key combinations
on laptops, or unplugging the USB stick).

This can be used as a base for experimentation with the longevity of various
'abnormal' TLB conditions.
