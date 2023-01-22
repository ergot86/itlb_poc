/*
    SPDX-FileCopyrightText: 2022 TACITO SECURITY <staff@tacitosecurity.com>
    SPDX-License-Identifier: GPL-3.0-or-later
*/
#include <stdint.h>
#include <x86intrin.h>

extern volatile uint32_t booted_cpus;
extern volatile uint32_t go_aps;
extern volatile uint64_t pt[512];
extern volatile uint64_t pd[512];

static void outb(uint16_t port, uint8_t val)
{
    __asm__ __volatile__("outb %0, %1" ::"a"(val), "Nd"(port));
}

static uint8_t inb(uint16_t port)
{
    uint8_t ret;
    __asm__ __volatile__("inb %1, %0"
                         : "=a"(ret)
                         : "Nd"(port));
    return ret;
}

static uint32_t inl(uint16_t port)
{
    uint32_t ret;
    __asm__ __volatile__("inl %1, %0"
                         : "=a"(ret)
                         : "Nd"(port));
    return ret;
}

void acpi_sleep(uint64_t ms)
{
    static uint16_t TimerPort = 1032; // hyperv
///    static uint16_t TimerPort = 0x4008; //vbox
///    static uint16_t TimerPort = 0x1008; //vmware
#define ACPI_TIMER_FREQ 3579545
    uint64_t total_ticks = (ACPI_TIMER_FREQ * ms) / 1000;
    uint64_t cur_ticks = 0;
    uint64_t cur_value = 0;
    uint64_t prev_value = 0;
    uint32_t timer_max = 0xffFFffFF;

    prev_value = inl(TimerPort);
    while (cur_ticks < total_ticks)
    {
        cur_value = inl(TimerPort);
        if (cur_value < prev_value)
            cur_ticks += cur_value + timer_max + 1 - prev_value;
        else
            cur_ticks += cur_value - prev_value;
        prev_value = cur_value;
    }
}

volatile uint64_t busy_sleep;

void sleep(uint64_t ms)
{
    // acpi_sleep(ms);
    __asm__("1: loop 1b"
            :
            : "c"(ms * 1000000));
}

uint64_t rdmsr(uint64_t msr)
{
    uint64_t msr_value;
    __asm__("rdmsr"
            : "=A"(msr_value)
            : "c"(msr));
    return msr_value;
}

static void *get_apic_base()
{
    return (void *)(rdmsr(0x1b) & 0xfffff000);
}

static uint32_t *apic_reg(unsigned int num)
{
    return (uint32_t *)((char *)get_apic_base() + 0x10 * num);
}

static void lapic_ack()
{
    *(uint32_t volatile *)apic_reg(0xb) = 0;
}

void enable_lapic()
{
    uint32_t volatile *sivr = apic_reg(0xf);
    uint32_t volatile *icr_lo = apic_reg(0x30);
    uint32_t volatile *icr_hi = apic_reg(0x31);
    uint32_t volatile *esr = apic_reg(0x28);

    *sivr |= 0x1ff;
    *esr = 0;
    *esr = 0;
    lapic_ack();
    *icr_hi = 0;
    *icr_lo = 0x80000 | 0x500 | 0x8000;
}

void init_cpu(uint8_t apic_id, uint64_t bootstrap_address)
{
    uint32_t volatile *icr_lo = apic_reg(0x30);
    uint32_t volatile *icr_hi = apic_reg(0x31);

    *icr_hi = apic_id << 24;
    *icr_lo = 0x4500; /* INIT IPI */
    sleep(10);
    *icr_hi = apic_id << 24;
    *icr_lo = 0x4600 | (bootstrap_address >> 12); /* SIPI */
    sleep(2);
}

static inline void *memcpy(void *dest, const void *src, size_t count)
{
    char *tmp = dest;
    const char *s = src;

    while (count--)
        *tmp++ = *s++;
    return dest;
}

extern unsigned char ap_code[1], ap_code_next[1];
void fiddle(void);
void twiddle(void);

void kmain()
{
    uint32_t asd;
    volatile unsigned char *p = (volatile unsigned char *)0;
    uint32_t i;

    // asm("int3");

    for (i = 0; i < 0x7000; i += 1)
        p[i] = 0;

    p = (unsigned char *)0x005b0000;
    for (i = 0; i < 0x10000; i += 1)
        p[i] = 0;

    memcpy((void *)0x3000, ap_code, 0x1000);
    memcpy((void *)0x1000, ap_code_next, 0x1000);
    memcpy((void *)0x4000, ap_code_next, 0x1000);
    memcpy((void *)0x0, ap_code, 0x1000);
#if 1
    p = (void *)0x100000;
    for (i = 0; i < 0x100000; i += 1)
        p[i] = 0x90; /* NOP */
    for (i = 0; i < 0x100000; i += 0x2000)
        p[i] = 0xc3;        /* RET */
    p[0x100000 - 1] = 0xc3; /* RET */
#endif

    fiddle();

    enable_lapic();

#if 1
    for (i = 1; i < 4; i += 1)
    {
        init_cpu(i, 0x8000);
    }
#endif
#if 1
    for (i = 5; i < 8; i += 1)
    {
        init_cpu(i, 0x8000);
    }
#endif

    go_aps = 1;

    twiddle();

    while (1)
        ;
}
