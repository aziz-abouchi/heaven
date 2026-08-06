pub const OpCode = enum(u8) {
    NOP,
    PUSH,
    ADD,
    MUL,
    CALL,
    HALT,
};

pub const Instr = struct {
    op: OpCode,
    arg: i64,
};
