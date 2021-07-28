usingnamespace @import("nrf52840.zig");

export fn SystemInit() void {}

export fn _start() void {
    comptime var i = 13;
    // The LEDs are active low, so set and clr are reversed
    p0.outset.write_raw(0xFFFFFFFF);
    inline while (i <= 16) : (i += 1) {
        p0.pin_cnf[i].modify(.{
            .dir = .output,
            .input = .disconnect,
        });

        p0.outclr.write_raw(1 << i);
    }

    while (true) {
        asm volatile ("nop");
    }
}
