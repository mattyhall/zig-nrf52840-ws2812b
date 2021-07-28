usingnamespace @import("nrf52840.zig");

const CPU_FREQ_MHZ = 64;

fn delay_us(us: u32) void {
    // Largely copied from the nrf52 SDK
    const delay_loop_cycles = 3;
    const cycles = us * CPU_FREQ_MHZ;

    // zig fmt: off
    const delay_machine_code = [3]u16 {
        0x3800 + delay_loop_cycles, // subs r0, delay_loop_cycles
        0xd8fd,                     // BHI .-2
        0x4770,                     // BX LR
    };
    // zig fmt: on

    const code = @intToPtr(fn (u32) void, @ptrToInt(delay_machine_code[0..]) | 1);
    code(cycles);
}

fn delay_ms(ms: u32) void {
    var loops = ms;

    while (loops > 0) {
        delay_us(1000);
        loops -= 1;
    }
}

export fn SystemInit() void {}

export fn _start() void {
    const leds = [_]u5{ 13, 14, 15, 16 };
    for (leds) |led| {
        p0.pin_cnf[led].modify(.{
            .dir = .output,
            .input = .disconnect,
        });
    }

    // The LEDs are active low, so set and clr are reversed
    p0.outset.write_raw(0xFFFFFFFF);

    var on = true;
    while (true) {
        for (leds) |led| {
            if (on) {
                p0.outclr.write_raw(@intCast(u32, 1) << led);
            } else {
                p0.outset.write_raw(@intCast(u32, 1) << led);
            }
            delay_ms(500);
        }
        on = !on;
    }

    unreachable;
}
