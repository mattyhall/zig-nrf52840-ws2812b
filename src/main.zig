usingnamespace @import("nrf52840.zig");
const std = @import("std");

const CPU_FREQ_MHZ = 64;

const N_LEDS = 3;
const N_RESET_BITS = 7;

const SCK_PIN = 31;
const LRCK_PIN = 30;
const MCK_PIN = 4294967295;
const SDOUT_PIN = 27;
const SDIN_PIN = 26;

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

export fn SystemInit() void {
    clock.events_done.write_raw(0);
    clock.events_ctto.write_raw(0);
    clock.ctiv.write_raw(0);
    if (power.resetreas.read().resetpin == .detected) {
        power.resetreas.modify(.{ .resetpin = .not_detected });
    }

    // FPU
    var ptr = @intToPtr(*volatile u32, 0xE000E000 + 0x0D00 + 0x088);
    const val = ptr.*;
    ptr.* = val | (3 << 20) | (3 << 22);
    asm volatile ("dsb 0xf");
    asm volatile ("isb 0xf");
}

fn calc_level(level: u8) u32 {
    if (level == 0) {
        return 0x88888888;
    } else if (level == 255) {
        return 0xeeeeeeee;
    }
    var val: u32 = 0x88888888;
    var i: u5 = 0;
    // Set 1 bits to be 0xe in val
    while (i < 8) : (i += 1) {
        if (((@as(u32, 1) << i) & level) != 0) {
            const mask = ~(@as(u32, 0x0f) << (4 * i));
            const patt = @as(u32, 0x0e) << (4 * i);
            val = (val & mask) | patt;
        }
    }

    // Swap first two bytes with last two bytes
    val = (val >> 16) | (val << 16);
    return val;
}

fn generate_led_data(_: usize) []u32 {
    const len = 3 * N_LEDS + N_RESET_BITS;
    var data: [len]u32 = [1]u32{0} ** len;
    var i: usize = 0;
    while (i < N_LEDS * 3) : (i += 3) {
        data[i] = calc_level(0);
        data[i + 1] = calc_level(128);
        data[i + 2] = calc_level(0);
    }
    return data[0..];
}

fn make_output(pin: u32) void {
    p0.pin_cnf[pin].write(.{
        .dir = .output,
        .input = .disconnect,
    });
}

fn make_input(pin: u32) void {
    p0.pin_cnf[pin].write(.{
        .dir = .input,
        .input = .connect,
    });
}

//fn NVIC_EnableIRQ(IRQn: u5) void {
//    // Get pointer to NVIC ISER register
//    const ISER = @intToPtr(*u32, 0xE000E000 + 0x0100 + 0x0);
//    ISER.* = @as(u32, 1) << IRQn;
//}

export fn configure_i2s() void {
    i2s.config.mode.write(.{ .mode = .master });
    i2s.config.format.write(.{ .format = .i2s });
    i2s.config.align_.write(.{ .align_ = .left });
    i2s.config.swidth.write(.{ .swidth = .bit_16 });
    i2s.config.channels.write(.{ .channels = .stereo });
    i2s.config.ratio.write(.{ .ratio = .x32 });

    i2s.config.mckfreq.write(.{ .mckfreq = .freq_32m_div_10 });
    i2s.config.mcken.write(.{ .mcken = .enabled });
    //i2s.config.txen.write(.{ .txen = .enabled });

    make_output(SCK_PIN);
    make_output(LRCK_PIN);
    make_output(SDOUT_PIN);
    make_input(SDIN_PIN);

    i2s.psel.sck.write(.{ .pin = SCK_PIN });
    i2s.psel.lrck.write(.{ .pin = LRCK_PIN });
    i2s.psel.mck.write_raw(MCK_PIN);
    i2s.psel.sdout.write(.{ .pin = SDOUT_PIN });
    i2s.psel.sdin.write(.{ .pin = SDIN_PIN });

    // IRQ stuff
    // SetPriority

    //NVIC_EnableIRQ(37);
    asm volatile("":::"memory");
    const irqn = 37;
    const isr_addr = 0xE000E000 + 0x0100 + @sizeOf(u32) * (irqn >> 5);
    var ptr = @intToPtr(*volatile u32, isr_addr);
    ptr.* = 1 << (irqn & 0x1f);
    asm volatile("":::"memory");
}

fn start_i2s(buffer: []u32) void {
    i2s.rxtxd.write_raw(@intCast(u32, buffer.len));
    i2s.txd.write_raw(@ptrToInt(buffer.ptr));
    i2s.config.txen.write(.{ .txen = .enabled });

    i2s.enable.write(.{ .enable = .enabled });

    i2s.events_rxptrupd.write(.{ .events_rxptrupd = .not_generated });
    _ = i2s.events_rxptrupd.read();
    i2s.events_txptrupd.write(.{ .events_txptrupd = .not_generated });
    _ = i2s.events_txptrupd.read();
    i2s.events_stopped.write(.{ .events_stopped = .not_generated });
    _ = i2s.events_stopped.read();

    i2s.intenset.write_raw(36);

    i2s.tasks_start.write(.{ .tasks_start = .trigger });
}

fn stop_i2s() void {
    i2s.tasks_stop.write(.{ .tasks_stop = .trigger });
}

export fn I2S_IRQHandler() void {
//   i2s.events_rxptrupd.write(.{ .events_rxptrupd = .not_generated });
//   _ = i2s.events_rxptrupd.read();
//   i2s.events_txptrupd.write(.{ .events_txptrupd = .not_generated });
//   _ = i2s.events_txptrupd.read();
//   if (i2s.events_stopped.read().events_stopped == .generated) {
//       i2s.events_stopped.write(.{ .events_stopped = .not_generated });
//       _ = i2s.events_stopped.read();
//       i2s.intenclr.write_raw(36);
//       i2s.enable.write(.{ .enable = .disabled });
////       const irqn = 37;
//       const isr_addr = 0xE000E000 + 0x0100 + @sizeOf(u32) * (irqn >> 5);
//       var ptr = @intToPtr(*volatile u32, isr_addr);
//       ptr.* = 1 << (irqn & 0x1f);
////       stop_i2s();
//   }
}

export fn _start() void {
    configure_i2s();
    var LED_DATA: []u32 = generate_led_data(0);

    p0.pin_cnf[13].write(.{
      .dir = .output,
      .input = .disconnect,
    });
    p0.outclr.write(.{ .pin13 = .clear });

    // var n_led: usize = 1;
    start_i2s(LED_DATA);

    while (true) {
        delay_ms(1000);
        stop_i2s();
    }

    while (true) {
        delay_ms(10000);
    }

    unreachable;
}
