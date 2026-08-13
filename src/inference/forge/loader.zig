const std = @import("std");
const platform = @import("platform");
const matrix_lib = @import("../../core/matrix.zig");
const heaven_lib = @import("../heaven.zig");

pub const ScriptLoader = struct {
    allocator: std.mem.Allocator,
    matrix: *matrix_lib.Matrix,
    engine: *heaven_lib.Engine,

    pub fn loadFile(self: *ScriptLoader, path: []const u8) !void {
        // platform.debug.print("[DEBUG] loadFile: reading '{s}'\n", .{path});
        // Lecture brute du fichier en mémoire
        const content = try platform.fs.cwd().readFileAlloc(self.allocator, path, 1024 * 1024);
        defer self.allocator.free(content);

        // Itération sur les lignes
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \r\t");

            // On ignore les lignes vides et les commentaires
            if (line.len == 0 or std.mem.startsWith(u8, line, "//") or line[0] == '#') continue;

            // --- NOUVEAU : CAS DES SPÉCIFICATIONS (spec lang key = pattern) ---
            if (std.mem.startsWith(u8, line, "spec ")) {
                var it = std.mem.tokenizeAny(u8, line[5..], " =");
                const lang = it.next() orelse continue;
                const key = it.next() orelse continue;

                const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
                const pattern = std.mem.trim(u8, line[eq_idx + 1 ..], " \"");

                const spec_key = try std.fmt.allocPrint(self.allocator, "SPEC_{s}_{s}", .{ lang, key });
                defer self.allocator.free(spec_key);

                const kid = try self.matrix.addUniqueSymbol(spec_key);
                const vid = try self.matrix.addUniqueSymbol(pattern);
                try self.matrix.addEdge(kid, vid, "PATTERN");
                continue;
            }

            // --- CAS 1 : LES ASSIGNATIONS (ex: Core_Node_Type = "Vessel_Alpha") ---
            if (std.mem.indexOfScalar(u8, line, '=')) |eq_idx| {
                const key = std.mem.trim(u8, line[0..eq_idx], " ");
                const value = std.mem.trim(u8, line[eq_idx + 1 ..], " \"");

                const kid = try self.matrix.addUniqueSymbol(key);
                try self.matrix.initGeometry(kid, key);
                const vid = try self.matrix.addUniqueSymbol(value);
                try self.matrix.initGeometry(vid, value);

                try self.matrix.addEdge(kid, vid, "IS");
                continue;
            }

            // --- CAS 2 : LES COMMANDES SPÉCIFIQUES (type, effect, hole) ---
            var it = std.mem.tokenizeAny(u8, line, " : ");
            const cmd = it.next() orelse continue;

            if (std.mem.eql(u8, cmd, "type")) {
                const name = it.next() orelse continue;
                _ = try self.matrix.addUniqueSymbol(name);
            } else if (std.mem.eql(u8, cmd, "effect")) {
                const name = it.next() orelse continue;
                const type_name = it.next() orelse continue;
                const type_id = try self.matrix.addUniqueSymbol(type_name);

                _ = try self.matrix.addNode(.{ .Effect = .{ .name = try self.allocator.dupe(u8, name), .signature = type_id } });
            } else if (std.mem.eql(u8, cmd, "hole")) {
                const name = it.next() orelse continue;
                const type_name = it.next() orelse continue;
                const type_id = try self.matrix.addUniqueSymbol(type_name);
                const hole_id = try self.matrix.addHole(name, type_id);

                try self.engine.atoms.put(@intCast(hole_id), .{
                    .id = hole_id,
                    .hash = std.hash.Wyhash.hash(0, name),
                    .valence = 0.5,
                    .state = .Dormant,
                    .last_pulse = std.time.timestamp(),
                    .type_id = type_id,
                    .is_hole = true,
                });
            }
        }
    }

    pub fn loadJsonGrammar(self: *ScriptLoader, lang: []const u8, json_path: []const u8) !void {
        const data = try platform.fs.cwd().readFileAlloc(self.allocator, json_path, 10 * 1024 * 1024);
        defer self.allocator.free(data);

        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, data, .{});
        defer parsed.deinit();

        if (parsed.value != .array) return error.InvalidGrammarFormat;

        for (parsed.value.array.items) |node_type| {
            if (node_type.object.get("type")) |name_val| {
                const type_name = name_val.string;
                const spec_key = try std.fmt.allocPrint(self.allocator, "SPEC_{s}_{s}", .{ lang, type_name });
                defer self.allocator.free(spec_key);

                _ = try self.matrix.addUniqueSymbol(spec_key);
                // Ici, on pourrait itérer sur "fields" pour créer des Edges structurels
            }
        }
    }
};
