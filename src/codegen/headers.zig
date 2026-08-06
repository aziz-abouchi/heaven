// src/codegen/headers.zig
//const std = @import("std");

// Pour votre structure personnalisée Codegen
pub fn emitStandardHeaders(codegen: anytype) !void {
    try codegen.emit("#include <stdio.h>\n");
    try codegen.emit("#include <stdlib.h>\n");
    try codegen.emit("#include <stdint.h>\n");
    try codegen.emit("#include <stdbool.h>\n");
    try codegen.emit("#include <string.h>\n");
    try codegen.emit("#include <rtc/rtc.h>\n");
    try codegen.emit("\n");
}

// Pour les cas où vous utilisez un Writer standard (dans compile.zig ou transpile.zig)
pub fn writeStandardHeaders(writer: anytype) !void {
    try writer.writeAll("#include <stdio.h>\n");
    try writer.writeAll("#include <stdlib.h>\n");
    try writer.writeAll("#include <stdint.h>\n");
    try writer.writeAll("#include <string.h>\n");
    try writer.writeAll("#include <stdbool.h>\n\n");
    try writer.writeAll("#include <rtc/rtc.h>\n\n");
}
