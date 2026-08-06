const mir = @import("mir");

pub fn emitFromFunction(func: *const mir.MirFunction, writer: anytype) !void {
    try writer.writeAll(".intel_syntax noprefix\n.globl _start\n_start:\n");
    for (func.blocks.items, 0..) |block, block_id| {
        try writer.print("  block_{d}:\n", .{block_id});
        for (block.instrs.items) |inst| {
            switch (inst) {
                .const_int => |c| {
                    try writer.print("    mov rax, {d}\n", .{c.value});
                },
                .add => |_| try writer.writeAll("    add rax, rbx\n"),
                .sub => |_| try writer.writeAll("    sub rax, rbx\n"),
                .mul => |_| try writer.writeAll("    mul rbx\n"),
                .div => |_| try writer.writeAll("    div rbx\n"),
                .cmp_lt => |_| try writer.writeAll("    cmp rax, rbx\n    setl al\n    movzx rax, al\n"),
                .cmp_eq => |_| try writer.writeAll("    cmp rax, rbx\n    sete al\n    movzx rax, al\n"),
                .ret => |_| {
                    try writer.writeAll("    mov rax, 60\n    xor rdi, rdi\n    syscall\n");
                },
                else => {},
            }
        }
        switch (block.terminator) {
            .jump => |target| try writer.print("    jmp block_{d}\n", .{target}),
            .branch => |b| {
                try writer.writeAll("    cmp rax, 0\n");
                try writer.print("    je block_{d}\n", .{b.else_block});
                try writer.print("    jmp block_{d}\n", .{b.then_block});
            },
            .ret => |_| {
                try writer.writeAll("    mov rax, 60\n    xor rdi, rdi\n    syscall\n");
            },
            .fallthrough => {},
        }
    }
}
