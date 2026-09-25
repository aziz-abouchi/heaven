//! import.zig -- chargement de modules Heaven (RFC-0001 5/5).
//!
//! Extrait de heaven_expr.zig :
//!   - ImportState : etat import (exports, pre-scan, isExported)
//!   - resolveImportPath : cwd + HEAVEN_PATH
//!   - evalImport : point d'entree import "path" [as Name] / import Name
//!
//! `heaven` est `anytype` pour eviter un cycle d'import avec
//! heaven_expr.zig (Heaven y est defini).

const std = @import("std");
const platform = @import("platform");

/// ImportError : seul OutOfMemory remonte. Les erreurs metier (syntaxe,
/// cycle, introuvable) sont renvoyees comme strings allouees.
pub const ImportError = error{OutOfMemory};

/// État d'un import en cours (v2a : filtrage `export`).
/// v0.5 = tout est exporté ; v2a = si le fichier contient au moins un
/// `export`, seuls les noms listés sont aliasés sous `M.x`.
/// (Les noms non-exportés restent accessibles sans qualification —
/// « enforcement faible », cohérent avec le REPL en namespace plat.)
pub const ImportState = struct {
    exports: std.StringHashMapUnmanaged(void) = .{},
    saw_export: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ImportState {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ImportState) void {
        var it = self.exports.iterator();
        while (it.next()) |e| self.allocator.free(e.key_ptr.*);
        self.exports.deinit(self.allocator);
    }

    pub fn isExported(self: *const ImportState, name: []const u8) bool {
        return !self.saw_export or self.exports.contains(name);
    }
};


    /// Résout un chemin d'import :
    ///   1. absolu → tel quel (si existe)
    ///   2. cwd + path
    ///   3. chaque dossier de HEAVEN_PATH (séparé par ':')
pub fn resolveImportPath(allocator: std.mem.Allocator, path: []const u8) error{NotFound, OutOfMemory}![]u8 {
        if (platform.fs.path.isAbsolute(path)) {
            const f = platform.fs.cwd().openFile(path, .{}) catch return error.NotFound;
            f.close();
            return allocator.dupe(u8, path);
        }

        // 1. cwd
        if (platform.fs.cwd().openFile(path, .{})) |f| {
            f.close();
            return allocator.dupe(u8, path);
        } else |_| {}

        // 2. HEAVEN_PATH
        const env_val = platform.getenv("HEAVEN_PATH") orelse return error.NotFound;
        var it = std.mem.splitScalar(u8, env_val, ':');
        while (it.next()) |dir| {
            if (dir.len == 0) continue;
            const candidate = try platform.fs.path.join(allocator, &.{ dir, path });
            if (platform.fs.cwd().openFile(candidate, .{})) |f| {
                f.close();
                return candidate;
            } else |_| {
                allocator.free(candidate);
            }
        }
        return error.NotFound;
    }


pub fn evalImport(heaven: anytype, src: []const u8) ImportError![]u8 {
        const trimmed = std.mem.trim(u8, src, " \t");
        if (trimmed.len < 1)
            return heaven.allocator.dupe(u8, "syntax: import \"path\" [as Name] | import Name");

        // Deux formes :
        //   import "chemin" [as Name]   → lecture explicite d'un fichier
        //   import Name                  → cherche core/std/<nom-min>.hvn,
        //                                  puis core/<nom-min>.hvn
        var path: []const u8 = undefined;
        var resolved_buf: ?[]u8 = null;
        defer if (resolved_buf) |b| heaven.allocator.free(b);

        var rest: []const u8 = "";
        var mod_name: []const u8 = "";

        if (trimmed[0] == '"') {
            // Forme 1 : chemin entre guillemets
            const close = std.mem.indexOfScalarPos(u8, trimmed, 1, '"') orelse
                return heaven.allocator.dupe(u8, "syntax: import \"path\" [as Name]");
            path = trimmed[1..close];
            rest = std.mem.trimLeft(u8, trimmed[close + 1 ..], " \t");

            if (std.mem.startsWith(u8, rest, "as ")) {
                mod_name = std.mem.trim(u8, rest[3..], " \t");
                if (mod_name.len == 0)
                    return heaven.allocator.dupe(u8, "syntax: nom de module vide après 'as'");
            } else {
                const base = platform.fs.path.basename(path);
                if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| {
                    mod_name = base[0..dot];
                } else {
                    mod_name = base;
                }
                if (mod_name.len == 0)
                    return heaven.allocator.dupe(u8, "syntax: nom de module indéterminable");
            }
        } else {
            // Forme 2 : identifiant simple → résout dans core/std/
            var it = std.mem.tokenizeAny(u8, trimmed, " \t");
            const name = it.next() orelse
                return heaven.allocator.dupe(u8, "syntax: import Name");
            mod_name = name;
            rest = it.rest();

            // Cherche core/std/<name-min>.hvn puis core/<name-min>.hvn
            const lower = try heaven.allocator.alloc(u8, name.len);
            defer heaven.allocator.free(lower);
            for (name, 0..) |ch, i| {
                lower[i] = std.ascii.toLower(ch);
            }
            const p1 = try std.fmt.allocPrint(heaven.allocator, "core/std/{s}.hvn", .{lower});
            defer heaven.allocator.free(p1);
            const p2 = try std.fmt.allocPrint(heaven.allocator, "core/{s}.hvn", .{lower});
            defer heaven.allocator.free(p2);

            if (platform.fs.cwd().openFile(p1, .{})) |f| {
                f.close();
                path = try heaven.allocator.dupe(u8, p1);
                resolved_buf = @constCast(path);
            } else |_| {
                if (platform.fs.cwd().openFile(p2, .{})) |f2| {
                    f2.close();
                    path = try heaven.allocator.dupe(u8, p2);
                    resolved_buf = @constCast(path);
                } else |_| {
                    return std.fmt.allocPrint(
                        heaven.allocator,
                        "✗ import {s} : ni core/std/{s}.hvn ni core/{s}.hvn",
                        .{ name, lower, lower },
                    );
                }
            }
        }

        // ─── Détection de cycle : mod_name déjà en cours de chargement ? ───
        for (heaven.loading_modules.items) |m| {
            if (std.mem.eql(u8, m, mod_name)) {
                return std.fmt.allocPrint(
                    heaven.allocator,
                    "✗ import {s} : cycle détecté (module {s} déjà en cours de chargement)",
                    .{ path, mod_name },
                );
            }
        }

        // ─── Résolution du chemin via cwd + HEAVEN_PATH ───
        const resolved = resolveImportPath(heaven.allocator, path) catch {
            return std.fmt.allocPrint(
                heaven.allocator,
                "✗ import {s} : fichier introuvable (essayé cwd + HEAVEN_PATH)",
                .{path},
            );
        };
        defer heaven.allocator.free(resolved);

        // ─── v2b : idempotence ───
        if (heaven.imported_files.get(resolved)) |existing_mod| {
            return std.fmt.allocPrint(
                heaven.allocator,
                "· import {s} : déjà importé (as {s}) — skip",
                .{ resolved, existing_mod },
            );
        }

        const source = platform.fs.cwd().readFileAlloc(
            heaven.allocator,
            resolved,
            1024 * 1024,
        ) catch {
            return std.fmt.allocPrint(
                heaven.allocator,
                "✗ import {s} (résolu → {s}) : lecture impossible",
                .{ path, resolved },
            );
        };
        defer heaven.allocator.free(source);

        // ─── v2a : pré-scan des `export` du fichier ───
        var import_state = ImportState.init(heaven.allocator);
        defer import_state.deinit();
        heaven.import_state = &import_state;
        defer heaven.import_state = null;

        {
            var prescan = std.mem.splitScalar(u8, source, '\n');
            while (prescan.next()) |line| {
                const t = std.mem.trim(u8, line, " \t\r");
                if (!std.mem.startsWith(u8, t, "export ")) continue;
                const names = std.mem.trim(u8, t["export ".len..], " \t");
                var nit = std.mem.tokenizeAny(u8, names, " \t,");
                while (nit.next()) |n| {
                    const owned = heaven.allocator.dupe(u8, n) catch continue;
                    const gop = import_state.exports.getOrPut(heaven.allocator, owned) catch {
                        heaven.allocator.free(owned);
                        continue;
                    };
                    if (gop.found_existing) heaven.allocator.free(owned);
                }
                import_state.saw_export = true;
            }
        }

        // ─── Push mod_name sur la pile de chargement ───
        const owned_mod = try heaven.allocator.dupe(u8, mod_name);
        try heaven.loading_modules.append(heaven.allocator, owned_mod);
        defer {
            const popped = heaven.loading_modules.pop();
            if (popped) |p| heaven.allocator.free(p);
        }

        // ─── Sauvegarde / restaure current_module ───
        const old_module = heaven.current_module;
        heaven.current_module = try heaven.allocator.dupe(u8, mod_name);
        defer {
            if (heaven.current_module) |m| heaven.allocator.free(m);
            heaven.current_module = old_module;
        }

        var lines = std.mem.splitScalar(u8, source, '\n');
        var count: usize = 0;
        while (lines.next()) |line| {
            const t = std.mem.trim(u8, line, " \t\r");
            if (t.len == 0) continue;
            if (t[0] == '#') continue;
            if (std.mem.startsWith(u8, t, "--")) continue;
            if (std.mem.startsWith(u8, t, "//")) continue;
            if (std.mem.startsWith(u8, t, ";;")) continue;

            const r = heaven.eval(t) catch |err| {
                return std.fmt.allocPrint(
                    heaven.allocator,
                    "✗ import {s} : ligne '{s}' → {}",
                    .{ path, t, err },
                );
            };
            defer heaven.allocator.free(r);

            // Propagation des erreurs retournées comme strings (✗ ...).
            // Sans ce check, un cycle détecté dans un sous-import serait
            // silencieusement avalé.
            if (std.mem.startsWith(u8, r, "✗")) {
                return std.fmt.allocPrint(
                    heaven.allocator,
                    "✗ import {s} : {s}",
                    .{ path, r },
                );
            }
            count += 1;
        }

        // ─── v2b : enregistrer dans le cache ───
        {
            const cache_path = try heaven.allocator.dupe(u8, resolved);
            const cache_mod = try heaven.allocator.dupe(u8, mod_name);
            const gop = heaven.imported_files.getOrPut(heaven.allocator, cache_path) catch {
                heaven.allocator.free(cache_path);
                heaven.allocator.free(cache_mod);
                return std.fmt.allocPrint(
                    heaven.allocator,
                    "✓ import {s} as {s} ({d} line(s))",
                    .{ resolved, mod_name, count },
                );
            };
            if (gop.found_existing) {
                heaven.allocator.free(cache_path);
                heaven.allocator.free(cache_mod);
            } else {
                gop.value_ptr.* = cache_mod;
            }
        }

        return std.fmt.allocPrint(
            heaven.allocator,
            "✓ import {s} as {s} ({d} line(s))",
            .{ resolved, mod_name, count },
        );
    }



test "ImportState -- isExported respecte saw_export" {
    const allocator = std.testing.allocator;
    var st = ImportState.init(allocator);
    defer st.deinit();

    try std.testing.expect(st.isExported("anything"));
    try std.testing.expect(st.isExported("other"));

    st.saw_export = true;
    const k = try allocator.dupe(u8, "foo");
    try st.exports.put(allocator, k, {});
    try std.testing.expect(st.isExported("foo"));
    try std.testing.expect(!st.isExported("bar"));
}
