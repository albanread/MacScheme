const std = @import("std");
const types = @import("types.zig");
const parser = @import("parser.zig");
const midi = @import("midi.zig");
const writer = @import("writer.zig");

pub const ABCTuneHandle = *types.ABCTune;

const CompiledProgram = struct {
    channel: u8,
    program: u8,
};

const CompiledNote = struct {
    start_beats: f64,
    duration_beats: f64,
    midi_note: u8,
    velocity: u8,
    channel: u8,
};

const PendingNote = struct {
    start_beats: f64,
    velocity: u8,
};

const kCompiledMusicMagic: u32 = 0x434D4246;
const kCompiledMusicVersion: u32 = 1;

fn writeU32LE(bytes: *std.array_list.Managed(u8), value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try bytes.appendSlice(&buf);
}

fn writeF64LE(bytes: *std.array_list.Managed(u8), value: f64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, @bitCast(value), .little);
    try bytes.appendSlice(&buf);
}

fn pendingKey(channel: u8, midi_note: u8) u16 {
    return (@as(u16, channel) << 8) | @as(u16, midi_note);
}

fn collectCompiledMusicData(
    allocator: std.mem.Allocator,
    abc_string: [*:0]const u8,
    programs: *std.array_list.Managed(CompiledProgram),
    notes: *std.array_list.Managed(CompiledNote),
    tempo_out: *f64,
) !bool {
    var abc_parser = parser.ABCParser.init(allocator);
    defer abc_parser.deinit();

    var tune = types.ABCTune.init(allocator);
    defer tune.deinit();

    if (!(try abc_parser.parseABC(std.mem.span(abc_string), &tune))) {
        return false;
    }

    var midi_generator = midi.MIDIGenerator.init(allocator);
    defer midi_generator.deinit();

    var tracks = std.array_list.Managed(midi.MIDITrack).init(allocator);
    defer {
        for (tracks.items) |*track| {
            track.deinit();
        }
        tracks.deinit();
    }

    if (!(try midi_generator.generateMIDI(&tune, &tracks))) {
        return false;
    }

    tempo_out.* = @floatFromInt(tune.default_tempo.bpm);

    var seen_programs = std.AutoHashMap(u16, void).init(allocator);
    defer seen_programs.deinit();

    var pending_notes = std.AutoHashMap(u16, std.array_list.Managed(PendingNote)).init(allocator);
    defer {
        var it = pending_notes.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        pending_notes.deinit();
    }

    for (tracks.items) |*track| {
        for (track.events.items) |event| {
            switch (event.ty) {
                .program_change => {
                    if (event.channel < 0) continue;
                    const channel: u8 = @intCast(event.channel + 1);
                    const program_key: u16 = (@as(u16, channel) << 8) | @as(u16, event.data1);
                    if (!seen_programs.contains(program_key)) {
                        try seen_programs.put(program_key, {});
                        try programs.append(.{
                            .channel = channel,
                            .program = event.data1,
                        });
                    }
                },
                .note_on => {
                    if (event.channel < 0) continue;
                    const channel: u8 = @intCast(event.channel + 1);
                    const key = pendingKey(channel, event.data1);
                    if (pending_notes.getPtr(key)) |pending_list| {
                        try pending_list.append(.{
                            .start_beats = event.timestamp,
                            .velocity = event.data2,
                        });
                    } else {
                        var pending_list = std.array_list.Managed(PendingNote).init(allocator);
                        try pending_list.append(.{
                            .start_beats = event.timestamp,
                            .velocity = event.data2,
                        });
                        try pending_notes.put(key, pending_list);
                    }
                },
                .note_off => {
                    if (event.channel < 0) continue;
                    const channel: u8 = @intCast(event.channel + 1);
                    const key = pendingKey(channel, event.data1);
                    if (pending_notes.getPtr(key)) |pending_list| {
                        if (pending_list.items.len == 0) continue;
                        const pending = pending_list.pop() orelse continue;
                        const duration = event.timestamp - pending.start_beats;
                        if (duration > 0.0) {
                            try notes.append(.{
                                .start_beats = pending.start_beats,
                                .duration_beats = duration,
                                .midi_note = event.data1,
                                .velocity = pending.velocity,
                                .channel = channel,
                            });
                        }
                    }
                },
                else => {},
            }
        }
    }

    std.mem.sort(CompiledNote, notes.items, {}, struct {
        fn lessThan(_: void, a: CompiledNote, b: CompiledNote) bool {
            if (a.start_beats != b.start_beats) return a.start_beats < b.start_beats;
            if (a.channel != b.channel) return a.channel < b.channel;
            return a.midi_note < b.midi_note;
        }
    }.lessThan);

    return true;
}

export fn abc_parse(abc_string: [*:0]const u8) ?ABCTuneHandle {
    const allocator = std.heap.c_allocator;
    var p = parser.ABCParser.init(allocator);
    defer p.deinit();

    const tune = p.parse(std.mem.span(abc_string)) catch return null;

    // We need to allocate the tune on the heap so it outlives this function
    const tune_ptr = allocator.create(types.ABCTune) catch return null;
    tune_ptr.* = tune;
    return tune_ptr;
}

export fn abc_free_tune(tune: ?ABCTuneHandle) void {
    if (tune) |t| {
        const allocator = std.heap.c_allocator;
        t.deinit();
        allocator.destroy(t);
    }
}

export fn abc_generate_midi(tune: ?ABCTuneHandle, output_path: [*:0]const u8) bool {
    if (tune == null) return false;

    const allocator = std.heap.c_allocator;
    var generator = midi.MIDIGenerator.init(allocator);
    defer generator.deinit();

    var tracks = std.array_list.Managed(midi.MIDITrack).init(allocator);
    defer {
        for (tracks.items) |*track| {
            track.deinit();
        }
        tracks.deinit();
    }

    const ok = generator.generateMIDI(tune.?, &tracks) catch return false;
    if (!ok) {
        return false;
    }

    var file = std.fs.cwd().createFile(std.mem.span(output_path), .{}) catch return false;
    defer file.close();

    var w = writer.MIDIWriter.init(allocator, generator.ticks_per_quarter);
    var file_buf: [4096]u8 = undefined;
    var file_writer = file.writer(&file_buf);
    w.write(&tracks, &file_writer.interface) catch return false;
    file_writer.interface.flush() catch return false;

    return true;
}

export fn abc_compile_music_blob(abc_string: [*:0]const u8, out_size: *usize) ?[*]u8 {
    out_size.* = 0;

    const allocator = std.heap.c_allocator;
    var programs = std.array_list.Managed(CompiledProgram).init(allocator);
    defer programs.deinit();
    var notes = std.array_list.Managed(CompiledNote).init(allocator);
    defer notes.deinit();

    var tempo: f64 = 120.0;
    const ok = collectCompiledMusicData(allocator, abc_string, &programs, &notes, &tempo) catch return null;
    if (!ok) return null;

    var bytes = std.array_list.Managed(u8).init(allocator);
    defer bytes.deinit();

    writeU32LE(&bytes, kCompiledMusicMagic) catch return null;
    writeU32LE(&bytes, kCompiledMusicVersion) catch return null;
    writeF64LE(&bytes, tempo) catch return null;
    writeU32LE(&bytes, @intCast(programs.items.len)) catch return null;
    writeU32LE(&bytes, @intCast(notes.items.len)) catch return null;

    for (programs.items) |program| {
        bytes.append(program.channel) catch return null;
        bytes.append(program.program) catch return null;
        bytes.append(0) catch return null;
        bytes.append(0) catch return null;
    }

    for (notes.items) |note| {
        writeF64LE(&bytes, note.start_beats) catch return null;
        writeF64LE(&bytes, note.duration_beats) catch return null;
        bytes.append(note.midi_note) catch return null;
        bytes.append(note.velocity) catch return null;
        bytes.append(note.channel) catch return null;
        bytes.append(0) catch return null;
    }

    const owned = allocator.alloc(u8, bytes.items.len) catch return null;
    @memcpy(owned, bytes.items);
    out_size.* = owned.len;
    return owned.ptr;
}

export fn abc_free_music_blob(blob_ptr: ?[*]u8, blob_size: usize) void {
    if (blob_ptr) |ptr| {
        std.heap.c_allocator.free(ptr[0..blob_size]);
    }
}
