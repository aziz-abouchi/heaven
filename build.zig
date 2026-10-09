const std = @import("std");
const builtin = @import("builtin");

fn isWindows(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows;
}
fn isMacOS(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .macos;
}
fn isLinux(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .linux;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const network_default = !isWindows(target);
    const network = b.option(bool, "network", "Enable native networking") orelse network_default;

    // 1. Options globales
    const options = b.addOptions();
    options.addOption(bool, "is_wasm", target.query.cpu_arch == .wasm32);
    options.addOption(bool, "network", network);
    options.addOption(i64, "build_timestamp", std.time.timestamp());
    // Chemin absolu vers QBE v1.2, injecte a la compilation pour les
    // tests qui doivent l'invoquer (test_mir_qbe). Evite le piege du
    // CWD : `zig build test` execute les binaires depuis .zig-cache/,
    // pas depuis la racine du repo.
    options.addOptionPath("qbe_path", .{ .cwd_relative = b.pathFromRoot("vendor/qbe-1.2/qbe") });

    // 2. Module platform
    // Note : plusieurs cibles partagent le meme fichier (voir docs/spec/_syntax_gaps.md).
    // Cibles routees :
    //   wasm32-*  -> wasm.zig          (freestanding ET wasi)
    //   aarch64-* -> x86_64_linux.zig  (macOS, POSIX)
    //   autres    -> <arch>_<os>.zig
    const platform_file = blk: {
        if (target.query.cpu_arch == .wasm32)
            break :blk "src/platform/wasm.zig";
        if (target.query.cpu_arch == .aarch64 and target.result.os.tag == .macos)
            break :blk "src/platform/x86_64_linux.zig";
        break :blk b.fmt("src/platform/{s}_{s}.zig", .{
            @tagName(target.result.cpu.arch),
            @tagName(target.result.os.tag),
        });
    };

    const platform_mod = b.createModule(.{
        .root_source_file = b.path(platform_file),
        .target = target,
        .optimize = optimize,
    });

    // Ajouter les include paths de tree-sitter
    if (target.query.cpu_arch != .wasm32) {
        platform_mod.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
        platform_mod.addIncludePath(b.path("vendor/tree-sitter/lib/src"));
        platform_mod.addIncludePath(b.path("vendor/tree-sitter/lib/src/unicode"));
        platform_mod.addIncludePath(b.path("vendor/tree-sitter-c/src"));
        platform_mod.addIncludePath(b.path("vendor/tree-sitter-heaven/src"));
        platform_mod.addIncludePath(b.path("vendor/tree-sitter-pie/src"));
        platform_mod.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    }

    // ─── TCC : bibliothèque statique (uniquement x86_64 non-Windows) ───
    // Note : le support arm64 de TCC (vendor/tcc/arm64-*.c) est
    // incomplet et ne compile pas (ARM64_STP_X_PRE, etc. non definis).
    // Voir docs/spec/_syntax_gaps.md.
    const tcc_supported = target.query.cpu_arch == .x86_64 and !isWindows(target);
    const tcc_lib = if (tcc_supported) blk: {
        const lib = b.addLibrary(.{
            .name = "tcc",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
            }),
        });

        const arch = target.result.cpu.arch;
        const cflags: []const []const u8 = if (arch == .x86_64)
            &.{ "-std=c99", "-DONE_SOURCE=0", "-DTCC_TARGET_X86_64", "-DTCC_TARGET_ELF" }
        else
            &.{ "-std=c99", "-DONE_SOURCE=0" };

        // Fichiers communs (toujours présents)
        lib.addCSourceFile(.{ .file = b.path("vendor/tcc/tcc.c"), .flags = cflags });
        lib.addCSourceFile(.{ .file = b.path("vendor/tcc/libtcc.c"), .flags = cflags });
        lib.addCSourceFile(.{ .file = b.path("vendor/tcc/tccpp.c"), .flags = cflags });
        lib.addCSourceFile(.{ .file = b.path("vendor/tcc/tccgen.c"), .flags = cflags });
        lib.addCSourceFile(.{ .file = b.path("vendor/tcc/tccelf.c"), .flags = cflags });
        lib.addCSourceFile(.{ .file = b.path("vendor/tcc/tccasm.c"), .flags = cflags });
        lib.addCSourceFile(.{ .file = b.path("vendor/tcc/tccrun.c"), .flags = cflags });
        lib.addCSourceFile(.{ .file = b.path("vendor/tcc/tccdbg.c"), .flags = cflags });

        // Architecture : x86_64 uniquement (tcc_supported garantit
        // deja arch == .x86_64, cf la condition plus haut).
        if (arch == .x86_64) {
            lib.addCSourceFile(.{ .file = b.path("vendor/tcc/x86_64-gen.c"), .flags = cflags });
            lib.addCSourceFile(.{ .file = b.path("vendor/tcc/x86_64-link.c"), .flags = cflags });
            lib.addCSourceFile(.{ .file = b.path("vendor/tcc/i386-asm.c"), .flags = cflags });
        }

        // Fichiers OS-spécifiques
        if (isWindows(target)) {
            lib.addCSourceFile(.{ .file = b.path("vendor/tcc/tccpe.c"), .flags = cflags });
        } else if (isMacOS(target)) {
            lib.addCSourceFile(.{ .file = b.path("vendor/tcc/tccmacho.c"), .flags = cflags });
        }
        // Linux/ELF : rien de plus à ajouter

        lib.addIncludePath(b.path("vendor/tcc"));
        lib.addIncludePath(b.path("vendor/tcc/include"));
        lib.root_module.link_libc = true;
        break :blk lib;
    } else null;

    // ─── Tree‑sitter : bibliothèque statique ───
    const tree_sitter_lib = if (target.query.cpu_arch != .wasm32) blk: {
        const lib = b.addLibrary(.{
            .name = "tree-sitter",
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
            }),
        });
        const cflags = &.{ "-std=c99", "-D_DEFAULT_SOURCE", "-D_GNU_SOURCE", "-D_POSIX_C_SOURCE=200809L" };
        lib.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
        lib.addIncludePath(b.path("vendor/tree-sitter/lib/src"));
        lib.addIncludePath(b.path("vendor/tree-sitter/lib/src/unicode"));
        lib.addIncludePath(b.path("vendor/tree-sitter-c/src"));
        lib.addIncludePath(b.path("vendor/tree-sitter-heaven/src"));
        lib.addIncludePath(b.path("vendor/tree-sitter-pie/src"));
        lib.addIncludePath(b.path("vendor/tree-sitter-zig/src"));

        lib.addCSourceFile(.{ .file = b.path("vendor/tree-sitter/lib/src/lib.c"), .flags = cflags });
        lib.addCSourceFile(.{ .file = b.path("vendor/tree-sitter-c/src/parser.c"), .flags = cflags });
        lib.addCSourceFile(.{ .file = b.path("vendor/tree-sitter-heaven/src/parser.c"), .flags = cflags });
        lib.addCSourceFile(.{ .file = b.path("vendor/tree-sitter-pie/src/parser.c"), .flags = cflags });
        lib.addCSourceFile(.{ .file = b.path("vendor/tree-sitter-zig/src/parser.c"), .flags = cflags });

        lib.root_module.link_libc = true;
        break :blk lib;
    } else null;

    // Ajouter les chemins pour tree-sitter (toutes cibles non-WASM)
    if (target.query.cpu_arch != .wasm32) {
        platform_mod.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
        platform_mod.addIncludePath(b.path("vendor/tree-sitter/lib/src"));
        platform_mod.addIncludePath(b.path("vendor/tree-sitter/lib/src/unicode"));
        platform_mod.addIncludePath(b.path("vendor/tree-sitter-c/src"));
        platform_mod.addIncludePath(b.path("vendor/tree-sitter-heaven/src"));
        platform_mod.addIncludePath(b.path("vendor/tree-sitter-pie/src"));
        platform_mod.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
    }

    const expr_mod = b.addModule("expr", .{
        .root_source_file = b.path("src/core/expr.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const knowledge_resource_mod = b.addModule("knowledge_resource", .{
        .root_source_file = b.path("src/knowledge/resource.zig"),
        .target = target,
        .optimize = optimize,
    });

    const knowledge_triple_mod = b.addModule("knowledge_triple", .{
        .root_source_file = b.path("src/knowledge/triple.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "resource", .module = knowledge_resource_mod },
        },
    });

    const knowledge_assertion_mod = b.addModule("knowledge_assertion", .{
        .root_source_file = b.path("src/knowledge/assertion.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "triple", .module = knowledge_triple_mod },
        },
    });

    const knowledge_store_mod = b.addModule("knowledge_store", .{
        .root_source_file = b.path("src/knowledge/store.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "assertion", .module = knowledge_assertion_mod },
        },
    });

    const knowledge_rdfs_mod = b.addModule("knowledge_rdfs", .{
        .root_source_file = b.path("src/knowledge/rdfs.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "assertion", .module = knowledge_assertion_mod },
            .{ .name = "knowledge_store", .module = knowledge_store_mod },
            .{ .name = "resource", .module = knowledge_resource_mod },
        },
    });

    const abi_mod = b.addModule("abi", .{
        .root_source_file = b.path("src/platform/abi/abi.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const hole_mod = b.addModule("hole", .{
        .root_source_file = b.path("src/core/hole.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
        },
    });

    const syntax_ast_mod = b.addModule("syntax_ast", .{
        .root_source_file = b.path("src/syntax/ast.zig"),
        .target = target,
        .optimize = optimize,
    });

    const syntax_core_lower_mod = b.addModule("syntax_core_lower", .{
        .root_source_file = b.path("src/syntax/core_lower.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "syntax_ast", .module = syntax_ast_mod },
        },
    });

    const syntax_lower_mod = b.addModule("syntax_lower", .{
        .root_source_file = b.path("src/syntax/lower.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "syntax_ast", .module = syntax_ast_mod },
            .{ .name = "core", .module = expr_mod },
            //.{ .name = "tree_sitter", .module = tree_sitter_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "syntax_ast", .module = syntax_ast_mod },
        },
    });

    const profiler_mod = b.addModule("profiler", .{
        .root_source_file = b.path("src/core/profiler.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const queue_mod = b.createModule(.{
        .root_source_file = b.path("src/core/network/queue.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const driver_mod = b.addModule("driver", .{
        .root_source_file = b.path("src/core/network/driver.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "queue", .module = queue_mod },
        },
    });

    platform_mod.addImport("driver", driver_mod);
    platform_mod.addImport("queue", queue_mod);

    const pattern_mod = b.createModule(.{
        .root_source_file = b.path("src/core/pattern.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const scheduler_task_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime/scheduler/task.zig"),
        .target = target,
        .optimize = optimize,
    });

    const scheduler_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime/scheduler/scheduler.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "scheduler_task", .module = scheduler_task_mod },
        },
    });

    const continuation_mod = b.createModule(.{
        .root_source_file = b.path("src/core/continuation.zig"),
        .target = target,
        .optimize = optimize,
    });

    const engine_expr_mod = b.createModule(.{
        .root_source_file = b.path("src/core/engine_expr.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "scheduler", .module = scheduler_mod },
            .{ .name = "continuation", .module = continuation_mod },
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "pattern", .module = pattern_mod },
            .{ .name = "syntax_lower", .module = syntax_lower_mod },
        },
    });

    const io_handler_mod = b.createModule(.{
        .root_source_file = b.path("src/core/io_handler.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
        },
    });

    const expr_parser_mod = b.createModule(.{
        .root_source_file = b.path("src/core/expr_parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "hole", .module = hole_mod },
        },
    });

    const mpst_mod = b.addModule("mpst", .{
        .root_source_file = b.path("src/core/mpst.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
        },
    });

    const elab_mod = b.createModule(.{
        .root_source_file = b.path("src/core/elab.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "syntax_lower", .module = syntax_lower_mod },
            .{ .name = "syntax_core_lower", .module = syntax_core_lower_mod },
            .{ .name = "mpst", .module = mpst_mod },
        },
    });

    const bridge_mod = b.createModule(.{
        .root_source_file = b.path("src/core/bridge.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const kanren_expr_mod = b.createModule(.{
        .root_source_file = b.path("src/logic/kanren_expr.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
        },
    });

    const canon_mod = b.createModule(.{
        .root_source_file = b.path("src/core/canon.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });
    const unify_proof_mod = b.addModule("unify_proof", .{
        .root_source_file = b.path("src/core/unify_proof.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "canon", .module = canon_mod },
        },
    });

    const types_mod = b.createModule(.{
        .root_source_file = b.path("src/core/types.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "elab", .module = elab_mod },
        },
    });

    const hole_runtime_mod = b.createModule(.{
        .root_source_file = b.path("src/core/hole_runtime.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "hole", .module = hole_mod },
            .{ .name = "types", .module = types_mod },
        },
    });

    const std_loader_mod = b.createModule(.{
        .root_source_file = b.path("src/core/std_loader.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const import_mod = b.createModule(.{
        .root_source_file = b.path("src/core/import.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const diff_mod = b.createModule(.{
        .root_source_file = b.path("src/core/diff.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
        },
    });

    const serialize_mod = b.createModule(.{
        .root_source_file = b.path("src/core/serialize.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
        },
    });

    const egraph_mod = b.createModule(.{
        .root_source_file = b.path("src/inference/eqsat/egraph.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "kanren_expr", .module = kanren_expr_mod },
            .{ .name = "canon", .module = canon_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "types", .module = types_mod },
        },
    });

    const transform_mod = b.createModule(.{
        .root_source_file = b.path("src/core/transform.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "canon", .module = canon_mod },
            .{ .name = "egraph", .module = egraph_mod },
            .{ .name = "pattern", .module = pattern_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const mir_mod = b.createModule(.{
        .root_source_file = b.path("src/core/mir.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
        },
    });

    const mir_qbe_mod = b.createModule(.{
        .root_source_file = b.path("src/backend/mir_qbe.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mir", .module = mir_mod },
        },
    });

    const mir_wat_mod = b.createModule(.{
        .root_source_file = b.path("src/backend/mir_wat.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mir", .module = mir_mod },
        },
    });

    const x86_64_mod = b.createModule(.{
        .root_source_file = b.path("src/core/x86_64.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mir", .module = mir_mod },
        },
    });

    const egraph_rewriter_mod = b.createModule(.{
        .root_source_file = b.path("src/core/egraph_rewriter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "egraph", .module = egraph_mod },
            .{ .name = "pattern", .module = pattern_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const headers_mod = b.addModule("headers", .{
        .root_source_file = b.path("src/codegen/headers.zig"),
        .target = target,
        .optimize = optimize,
    });
    const codegen_expr_c_mod = b.createModule(.{
        .root_source_file = b.path("src/codegen/expr_c.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "headers", .module = headers_mod },
        },
    });

    const codegen_expr_js_mod = b.createModule(.{ .root_source_file = b.path("src/codegen/expr_js.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "expr", .module = expr_mod }} });

    const codegen_expr_latex_mod = b.createModule(.{
        .root_source_file = b.path("src/codegen/expr_latex.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
        },
    });

    const matrix_mod = b.addModule("matrix_lib", .{
        .root_source_file = b.path("src/core/matrix.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const synthesis_mod = b.createModule(.{
        .root_source_file = b.path("src/inference/neural/synthesis.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "matrix_lib", .module = matrix_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const matrix_bridge_mod = b.createModule(.{
        .root_source_file = b.path("src/core/matrix_bridge.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "matrix_lib", .module = matrix_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const proof_mod = b.createModule(.{
        .root_source_file = b.path("src/core/proof.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "canon", .module = canon_mod },
        },
    });

    const skill_mod = b.createModule(.{
        .root_source_file = b.path("src/core/skill.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "proof", .module = proof_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const lowering_mod = b.createModule(.{
        .root_source_file = b.path("src/core/lowering.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "matrix_bridge", .module = matrix_bridge_mod },
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "matrix_lib", .module = matrix_mod },
        },
    });

    const algo_catalog_mod = b.createModule(.{
        .root_source_file = b.path("src/core/algo_catalog.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
        },
    });

    const kernel_mod = b.addModule("kernel", .{
        .root_source_file = b.path("src/kernel/kernel.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const kernel_bridge_mod = b.addModule("kernel_bridge", .{
        .root_source_file = b.path("src/core/kernel_bridge.zig"),
        // deps : expr + kernel — les deux dont bridge a besoin
    });
    kernel_bridge_mod.addImport("expr", expr_mod);
    kernel_bridge_mod.addImport("kernel", kernel_mod);

    const parse_mod = b.addModule("parse", .{
        .root_source_file = b.path("src/core/parse.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
        },
    });

    const math_mod = b.addModule("math", .{
        .root_source_file = b.path("src/core/math.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "matrix_bridge", .module = matrix_bridge_mod },
            .{ .name = "parse", .module = parse_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    // Module parzig pour lecture Parquet streaming
    const parzig_dep = b.dependency("parzig", .{
        .target = target,
        .optimize = optimize,
    });
    const parzig_mod = parzig_dep.module("parzig");

    const mlcpd_mod = b.addModule("mlcpd", .{
        .root_source_file = b.path("src/translator/mlcpd.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "parzig", .module = parzig_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const proof_core_mod = b.addModule("proof_core", .{
        .root_source_file = b.path("src/core/proof_core.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "canon", .module = canon_mod },
            .{ .name = "kernel", .module = kernel_mod },
            .{ .name = "kernel_bridge", .module = kernel_bridge_mod },
        },
    });

    const proof_state_mod = b.addModule("proof_state", .{
        .root_source_file = b.path("src/core/proof_state.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
        },
    });

    const type_registry_mod = b.addModule("type_registry", .{
        .root_source_file = b.path("src/core/type_registry.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
        },
    });

    const tactics_mod = b.addModule("tactics", .{
        .root_source_file = b.path("src/core/tactics.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "proof_state", .module = proof_state_mod },
            .{ .name = "unify_proof", .module = unify_proof_mod },
        },
    });

    const mlcpd_equiv_mod = b.addModule("mlcpd_equiv", .{
        .root_source_file = b.path("src/translator/mlcpd_equiv.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "elab", .module = elab_mod },
            .{ .name = "proof_core", .module = proof_core_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const universal_translator_mod = b.addModule("universal_translator", .{
        .root_source_file = b.path("src/translator/universal_translator.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "mlcpd", .module = mlcpd_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const codegen_wrapper_mod = b.addModule("codegen_wrapper", .{
        .root_source_file = b.path("src/core/codegen_wrapper.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "codegen_expr_c", .module = codegen_expr_c_mod },
            .{ .name = "codegen_expr_latex", .module = codegen_expr_latex_mod },
        },
    });

    const rules_mod = b.addModule("rules", .{
        .root_source_file = b.path("src/core/rules.zig"),
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "pattern", .module = pattern_mod },
        },
    });

    const simplify_engine_mod = b.addModule("simplify_engine", .{
        .root_source_file = b.path("src/core/simplify_engine.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "transform", .module = transform_mod },
            .{ .name = "pattern", .module = pattern_mod },
            .{ .name = "egraph", .module = egraph_mod },
            .{ .name = "egraph_rewriter", .module = egraph_rewriter_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "rules", .module = rules_mod },
        },
    });

    const proof_helpers_mod = b.addModule("proof_helpers", .{
        .root_source_file = b.path("src/core/proof_helpers.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "proof_core", .module = proof_core_mod },
        },
    });

    const turtle_parser_mod = b.createModule(.{
        .root_source_file = b.path("src/knowledge/turtle_parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    const triple_store_mod = b.createModule(.{
        .root_source_file = b.path("src/knowledge/triple_store.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "turtle_parser", .module = turtle_parser_mod },
        },
    });

    const agent_mod = b.addModule("agent", .{
        .root_source_file = b.path("src/runtime/agent/agent.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "triple_store", .module = triple_store_mod },
            .{ .name = "turtle_parser", .module = turtle_parser_mod },
        },
    });

    const shell_parser_types_mod = b.createModule(.{
        .root_source_file = b.path("src/platform/shell_parser_types.zig"),
        .target = target,
        .optimize = optimize,
    });
    platform_mod.addImport("shell_parser_types", shell_parser_types_mod);

    const shell_parser_mod = b.createModule(.{
        .root_source_file = b.path("src/parsing/shell_parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const dispatch_ops = b.createModule(.{
        .root_source_file = b.path("src/core/commands/dispatch.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "canon", .module = canon_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const runtime_ops = b.createModule(.{
        .root_source_file = b.path("src/core/commands/runtime.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "egraph", .module = egraph_mod },
            .{ .name = "mir", .module = mir_mod },
            .{ .name = "x86_64", .module = x86_64_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "codegen_expr_js", .module = codegen_expr_js_mod },
            .{ .name = "transform", .module = transform_mod },
        },
    });

    const meta_ops = b.createModule(.{
        .root_source_file = b.path("src/core/commands/meta.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "egraph", .module = egraph_mod },
            .{ .name = "canon", .module = canon_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const format_ops = b.createModule(.{
        .root_source_file = b.path("src/core/commands/format.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "codegen_expr_c", .module = codegen_expr_c_mod },
            .{ .name = "codegen_expr_latex", .module = codegen_expr_latex_mod },
        },
    });

    const defs_ops = b.createModule(.{
        .root_source_file = b.path("src/core/commands/defs.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "canon", .module = canon_mod },
            .{ .name = "egraph", .module = egraph_mod },
            .{ .name = "pattern", .module = pattern_mod },
            .{ .name = "math", .module = math_mod },
            .{ .name = "transform", .module = transform_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const cas_ops = b.createModule(.{
        .root_source_file = b.path("src/core/commands/cas.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "canon", .module = canon_mod },
            .{ .name = "egraph", .module = egraph_mod },
            .{ .name = "transform", .module = transform_mod },
            .{ .name = "pattern", .module = pattern_mod },
            .{ .name = "math", .module = math_mod },
            .{ .name = "rules", .module = rules_mod },
            .{ .name = "simplify_engine", .module = simplify_engine_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const parse_ops = b.createModule(.{
        .root_source_file = b.path("src/core/commands/parse.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "bridge_expr", .module = bridge_mod },
        },
    });

    const proofs_ops = b.createModule(.{
        .root_source_file = b.path("src/core/commands/proofs.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "canon", .module = canon_mod },
            .{ .name = "elab", .module = elab_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "proof_core", .module = proof_core_mod },
            .{ .name = "proof_helpers", .module = proof_helpers_mod },
        },
    });

    const commands_mod = b.addModule("commands", .{
        .root_source_file = b.path("src/core/commands.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "bridge_expr", .module = bridge_mod },
            .{ .name = "shell_parser", .module = shell_parser_mod },
            .{ .name = "triple_store", .module = triple_store_mod },
            .{ .name = "turtle_parser", .module = turtle_parser_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "codegen_expr_c", .module = codegen_expr_c_mod },
            .{ .name = "codegen_expr_js", .module = codegen_expr_js_mod },
            .{ .name = "codegen_expr_latex", .module = codegen_expr_latex_mod },
            .{ .name = "matrix_bridge", .module = matrix_bridge_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "egraph", .module = egraph_mod },
            .{ .name = "canon", .module = canon_mod },
            .{ .name = "proof", .module = proof_mod },
            .{ .name = "skill", .module = skill_mod },
            .{ .name = "mir", .module = mir_mod },
            .{ .name = "x86_64", .module = x86_64_mod },
            .{ .name = "proof_core", .module = proof_core_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "transform", .module = transform_mod },
            .{ .name = "pattern", .module = pattern_mod },
            .{ .name = "elab", .module = elab_mod },
            .{ .name = "agent", .module = agent_mod },
            .{ .name = "parse", .module = parse_mod },
            .{ .name = "math", .module = math_mod },
            .{ .name = "proof_helpers", .module = proof_helpers_mod },
            .{ .name = "simplify_engine", .module = simplify_engine_mod },
            .{ .name = "mlcpd", .module = mlcpd_mod },
            .{ .name = "mlcpd_equiv", .module = mlcpd_equiv_mod },
            .{ .name = "universal_translator", .module = universal_translator_mod },
            .{ .name = "rules", .module = rules_mod },
            .{ .name = "proofs_ops", .module = proofs_ops },
            .{ .name = "parse_ops", .module = parse_ops },
            .{ .name = "cas_ops", .module = cas_ops },
            .{ .name = "defs_ops", .module = defs_ops },
            .{ .name = "format_ops", .module = format_ops },
            .{ .name = "meta_ops", .module = meta_ops },
            .{ .name = "runtime_ops", .module = runtime_ops },
            .{ .name = "dispatch_ops", .module = dispatch_ops },
        },
    });
    commands_mod.addOptions("build_options", options);

    const heaven_expr_mod = b.createModule(.{
        .root_source_file = b.path("src/core/heaven_expr.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "hole", .module = hole_mod },
            .{ .name = "bridge_expr", .module = bridge_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "headers", .module = headers_mod },
            .{ .name = "codegen_expr_c", .module = codegen_expr_c_mod },
            .{ .name = "codegen_expr_latex", .module = codegen_expr_latex_mod },
            .{ .name = "matrix_bridge", .module = matrix_bridge_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "egraph", .module = egraph_mod },
            .{ .name = "lowering", .module = lowering_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "canon", .module = canon_mod },
            .{ .name = "proof", .module = proof_mod },
            .{ .name = "skill", .module = skill_mod },
            .{ .name = "mir", .module = mir_mod },
            .{ .name = "x86_64", .module = x86_64_mod },
            .{ .name = "elab", .module = elab_mod },
            .{ .name = "transform", .module = transform_mod },
            .{ .name = "pattern", .module = pattern_mod },
            .{ .name = "egraph_rewriter", .module = egraph_rewriter_mod },
            .{ .name = "codegen_expr_js", .module = codegen_expr_js_mod },
            .{ .name = "kernel", .module = kernel_mod },
            .{ .name = "parse", .module = parse_mod },
            .{ .name = "codegen_wrapper", .module = codegen_wrapper_mod },
            .{ .name = "proof_helpers", .module = proof_helpers_mod },
            .{ .name = "simplify_engine", .module = simplify_engine_mod },
            .{ .name = "math", .module = math_mod },
            .{ .name = "mlcpd", .module = mlcpd_mod },
            .{ .name = "mlcpd_equiv", .module = mlcpd_equiv_mod },
            .{ .name = "parzig", .module = parzig_mod },
            .{ .name = "shell_parser", .module = shell_parser_mod },
            .{ .name = "proof_core", .module = proof_core_mod },
            .{ .name = "proof_state", .module = proof_state_mod },
            .{ .name = "tactics", .module = tactics_mod },
            .{ .name = "type_registry", .module = type_registry_mod },
            .{ .name = "agent", .module = agent_mod },
            .{ .name = "commands", .module = commands_mod },
            .{ .name = "profiler", .module = profiler_mod },
            .{ .name = "io_handler", .module = io_handler_mod },
            .{ .name = "expr_parser", .module = expr_parser_mod },
            .{ .name = "hole_runtime", .module = hole_runtime_mod },
            .{ .name = "std_loader", .module = std_loader_mod },
            .{ .name = "kanren_expr", .module = kanren_expr_mod },
            .{ .name = "import", .module = import_mod },
            .{ .name = "diff", .module = diff_mod },
        },
    });
    heaven_expr_mod.addOptions("build_options", options);

    const mcp_server_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime/mcp_server.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "heaven_expr", .module = heaven_expr_mod },
            .{ .name = "mlcpd", .module = mlcpd_mod },
            .{ .name = "mlcpd_equiv", .module = mlcpd_equiv_mod },
            .{ .name = "parzig", .module = parzig_mod },
        },
    });

    const task_mod = b.addModule("task", .{
        .root_source_file = b.path("src/runtime/task.zig"),
        .target = target,
        .optimize = optimize,
    });

    const protocol_mod = b.addModule("protocol", .{
        .root_source_file = b.path("src/scut/protocol.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "task", .module = task_mod },
        },
    });

    const codec_mod = b.createModule(.{
        .root_source_file = b.path("src/core/network/codec.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "egraph", .module = egraph_mod },
            .{ .name = "protocol", .module = protocol_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const handlers_mod = b.createModule(.{
        .root_source_file = b.path("src/core/network/handlers.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "codec", .module = codec_mod },
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "egraph", .module = egraph_mod },
        },
    });

    const codegen_c_legacy_mod = b.createModule(.{
        .root_source_file = b.path("src/codegen/c.zig"),
        .target = target,
        .optimize = optimize,
    });

    const commands_list_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime/shell/commands_list.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "heaven_expr", .module = heaven_expr_mod },
        },
    });

    // ─── Exécutable principal ───
    const exe = b.addExecutable(.{
        .name = "heaven",
        .root_module = b.createModule(
            .{
                .root_source_file = b.path(if (target.query.cpu_arch == .wasm32)
                    "src/vessel/wasm_entry.zig"
                else
                    "src/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "expr", .module = expr_mod },
                    .{ .name = "bridge_expr", .module = bridge_mod },
                    .{ .name = "headers", .module = headers_mod },
                    .{ .name = "kanren_expr", .module = kanren_expr_mod },
                    .{ .name = "egraph", .module = egraph_mod },
                    .{ .name = "codegen_expr_c", .module = codegen_expr_c_mod },
                    .{ .name = "codegen_expr_latex", .module = codegen_expr_latex_mod },
                    .{ .name = "engine_expr", .module = engine_expr_mod },
                    .{ .name = "codegen_c", .module = codegen_c_legacy_mod },
                    .{ .name = "matrix_bridge", .module = matrix_bridge_mod },
                    .{ .name = "heaven_expr", .module = heaven_expr_mod },
                    .{ .name = "algo_catalog", .module = algo_catalog_mod },
                    .{ .name = "types", .module = types_mod },
                    .{ .name = "lowering", .module = lowering_mod },
                    .{ .name = "matrix_lib", .module = matrix_mod },
                    .{ .name = "platform", .module = platform_mod },
                    .{ .name = "triple_store", .module = triple_store_mod },
                    .{ .name = "turtle_parser", .module = turtle_parser_mod },
                    .{ .name = "proof", .module = proof_mod },
                    .{ .name = "skill", .module = skill_mod },
                    .{ .name = "synthesis", .module = synthesis_mod },
                    .{ .name = "elab", .module = elab_mod },
                    .{ .name = "codec", .module = codec_mod },
                    .{ .name = "handlers", .module = handlers_mod },
                    .{ .name = "queue", .module = queue_mod },
                    .{ .name = "protocol", .module = protocol_mod },
                    .{ .name = "task", .module = task_mod },
                    .{ .name = "mlcpd", .module = mlcpd_mod },
                    .{ .name = "mlcpd_equiv", .module = mlcpd_equiv_mod },
                    .{ .name = "parzig", .module = parzig_mod },
                    .{ .name = "mcp_server", .module = mcp_server_mod },
                    .{ .name = "simplify_engine", .module = simplify_engine_mod },
                    .{ .name = "egraph_rewriter", .module = egraph_rewriter_mod },
                    .{ .name = "shell_commands", .module = commands_list_mod },
                    .{ .name = "shell_parser", .module = shell_parser_mod },
                    .{ .name = "parse", .module = parse_mod },
                    .{ .name = "math", .module = math_mod },
                    .{ .name = "transform", .module = transform_mod },
                    .{ .name = "proof_core", .module = proof_core_mod },
                    .{ .name = "agent", .module = agent_mod },
                    .{ .name = "commands", .module = commands_mod },
                    .{ .name = "universal_translator", .module = universal_translator_mod },
                    .{ .name = "profiler", .module = profiler_mod },
                    .{ .name = "mir", .module = mir_mod },
                    .{ .name = "mir_qbe", .module = mir_qbe_mod },
                    .{ .name = "mir_wat", .module = mir_wat_mod },
                },
            },
        ),
    });

    exe.root_module.addOptions("build_options", options);

    // Lier les bibliothèques statiques
    if (tree_sitter_lib) |lib| exe.linkLibrary(lib);
    // TCC
    if (tcc_lib) |lib| exe.linkLibrary(lib) else {
        exe.addCSourceFile(.{ .file = b.path("src/platform/tcc_stub.c"), .flags = &.{"-std=c99"} });
    }

    // WebRTC (désactivé par défaut sur Windows, stub utilisé)
    if (target.query.cpu_arch != .wasm32) {
        exe.addIncludePath(b.path("src/platform"));
        // On utilise toujours le stub pour l'instant, même si network est true
        exe.addCSourceFile(.{ .file = b.path("src/platform/webrtc_stub.c"), .flags = &.{"-std=c99"} });
        exe.root_module.link_libc = true;
        exe.linkLibC();
    } else {
        // WASM
        exe.entry = .disabled;
        exe.rdynamic = true;
    }

    // Step: sync-tests — copie test_suite.hvn vers vessel/public/ pour WASM
    const sync_tests = b.addSystemCommand(&.{"cp"});
    sync_tests.addArgs(&.{ "core/test_suite.hvn", "src/vessel/public/test_suite.hvn" });
    const sync_step = b.step("sync-tests", "Copy test_suite.hvn to vessel/public/ for WASM");
    sync_step.dependOn(&sync_tests.step);

    // Rendre la synchronisation automatique lors de l'installation (y compris WASM)
    b.getInstallStep().dependOn(sync_step);

    // Steps : docgen — regenere les valeurs factuelles dans README.
    // Attention : 'doc' est deja pris (generate doc d'un .hvn), donc
    // on utilise 'docgen' et 'docgen-check'.
    // Voir PROMPT_CONTINUITE.md section "Convention doc".
    const docgen_cmd = b.addSystemCommand(&.{ "python3", "scripts/docgen.py" });
    const docgen_step = b.step("docgen", "Regenere les chiffres factuels du README (docgen.py)");
    docgen_step.dependOn(&docgen_cmd.step);

    const docgen_check_cmd = b.addSystemCommand(&.{ "python3", "scripts/docgen.py", "--check" });
    const docgen_check_step = b.step("docgen-check", "Verifie que la doc est a jour (CI)");
    docgen_check_step.dependOn(&docgen_check_cmd.step);

    b.installArtifact(exe);

    // ─── Tests ───
    // M2 : tests MIR→WAT (docs/BACKENDS.md, docs/MIR_CONTRACT.md)
    // M3 : tests MIR→QBE (docs/BACKENDS.md, docs/MIR_CONTRACT.md)
    const test_mir_qbe = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/backend/test_mir_qbe.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mir", .module = mir_mod },
            .{ .name = "expr", .module = expr_mod },
        },
    }) });
    test_mir_qbe.root_module.addOptions("build_options", options);

    const test_mir_wat = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/backend/test_mir_wat.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mir", .module = mir_mod },
            .{ .name = "expr", .module = expr_mod },
        },
    }) });
    const run_test_mir_wat = b.addRunArtifact(test_mir_wat);

    const test_expr = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/expr.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
        },
    }) });

    const test_bridge = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/bridge.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    }) });

    const test_kanren_expr = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/logic/kanren_expr.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "expr", .module = expr_mod }},
    }) });

    const test_continuation = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/continuation.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const test_abi_precision = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/abi/precision.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    const test_abi_error = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/abi/error.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    const test_abi_capability = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/abi/capability.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    const test_abi_metric = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/abi/metric.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    const test_abi_profile = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/abi/profile.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    const test_abi_profile_ser = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/abi/profile_ser.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    const test_abi_profile_tree = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/abi/profile_tree.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    const test_abi_profile_annotations = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/platform/abi/profile_annotations.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    const test_egraph = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/inference/eqsat/egraph.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "kanren_expr", .module = kanren_expr_mod },
            .{ .name = "canon", .module = canon_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "types", .module = types_mod },
        },
    }) });

    const egraph_viz_mod = b.createModule(.{
        .root_source_file = b.path("src/inference/eqsat/egraph_viz.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "egraph", .module = egraph_mod },
        },
    });

    const test_profile_egraph = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/inference/eqsat/profile_egraph_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "egraph", .module = egraph_mod },
            .{ .name = "egraph_viz", .module = egraph_viz_mod },
            .{ .name = "abi", .module = abi_mod },
        },
    }) });

    const test_codegen_c = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/codegen/expr_c.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "canon", .module = canon_mod },
            .{ .name = "headers", .module = headers_mod },
        },
    }) });

    const test_codegen_latex = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/codegen/expr_latex.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "expr", .module = expr_mod }},
    }) });

    const test_engine = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/engine_expr.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "pattern", .module = pattern_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "continuation", .module = continuation_mod },
            .{ .name = "scheduler", .module = scheduler_mod },
        },
    }) });

    // ─── FIX WASM: Imports dynamiques pour test_heaven_expr ───
    var test_he_imports: std.ArrayList(std.Build.Module.Import) = .empty;
    test_he_imports.append(b.allocator, .{ .name = "expr", .module = expr_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "engine_expr", .module = engine_expr_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "headers", .module = headers_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "codegen_expr_c", .module = codegen_expr_c_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "codegen_expr_latex", .module = codegen_expr_latex_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "types", .module = types_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "canon", .module = canon_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "egraph", .module = egraph_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "proof", .module = proof_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "skill", .module = skill_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "mir", .module = mir_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "x86_64", .module = x86_64_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "transform", .module = transform_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "pattern", .module = pattern_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "egraph_rewriter", .module = egraph_rewriter_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "codegen_expr_js", .module = codegen_expr_js_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "elab", .module = elab_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "kernel", .module = kernel_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "parse", .module = parse_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "platform", .module = platform_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "math", .module = math_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "mlcpd", .module = mlcpd_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "mlcpd_equiv", .module = mlcpd_equiv_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "simplify_engine", .module = simplify_engine_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "commands", .module = commands_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "proof_core", .module = proof_core_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "proof_state", .module = proof_state_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "tactics", .module = tactics_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "type_registry", .module = type_registry_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "agent", .module = agent_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "profiler", .module = profiler_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "io_handler", .module = io_handler_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "expr_parser", .module = expr_parser_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "hole_runtime", .module = hole_runtime_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "std_loader", .module = std_loader_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "import", .module = import_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "diff", .module = diff_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "serialize", .module = serialize_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "kanren_expr", .module = kanren_expr_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "unify_proof", .module = unify_proof_mod }) catch unreachable;
    test_he_imports.append(b.allocator, .{ .name = "hole", .module = hole_mod }) catch unreachable;

    if (target.query.cpu_arch != .wasm32) {
        test_he_imports.append(b.allocator, .{ .name = "matrix_bridge", .module = matrix_bridge_mod }) catch unreachable;
        test_he_imports.append(b.allocator, .{ .name = "lowering", .module = lowering_mod }) catch unreachable;
    }

    const test_heaven_expr = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/core/heaven_expr.zig"),
            .target = target,
            .optimize = optimize,
            .imports = test_he_imports.items,
        }),
    });

    const test_types = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/types.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "elab", .module = elab_mod },
        },
    }) });

    const test_proof = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/proof.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "canon", .module = canon_mod },
        },
    }) });

    const test_skill = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/skill.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "proof", .module = proof_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    }) });

    const test_canon = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/canon.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    }) });

    const test_elab = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/elab.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "syntax_lower", .module = syntax_lower_mod },
            .{ .name = "syntax_core_lower", .module = syntax_core_lower_mod },
            .{ .name = "mpst", .module = mpst_mod },
        },
    }) });

    const test_commands = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/shell/commands_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "matrix_bridge", .module = matrix_bridge_mod },
            .{ .name = "parse", .module = parse_mod },
            .{ .name = "transform", .module = transform_mod },
            .{ .name = "skill", .module = skill_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "proof_core", .module = proof_core_mod },
            .{ .name = "agent", .module = agent_mod },
            .{ .name = "math", .module = math_mod },
            .{ .name = "commands", .module = commands_mod },
        },
    }) });

    const test_commands_full = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/shell/commands_full_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "engine_expr", .module = engine_expr_mod },
            .{ .name = "matrix_bridge", .module = matrix_bridge_mod },
            .{ .name = "parse", .module = parse_mod },
            .{ .name = "transform", .module = transform_mod },
            .{ .name = "skill", .module = skill_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "proof_core", .module = proof_core_mod },
            .{ .name = "agent", .module = agent_mod },
            .{ .name = "math", .module = math_mod },
            .{ .name = "commands", .module = commands_mod },
        },
    }) });

    const test_mlcpd_equiv_integration = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/mlcpd_equiv_integration_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "mlcpd", .module = mlcpd_mod },
            .{ .name = "mlcpd_equiv", .module = mlcpd_equiv_mod },
            .{ .name = "elab", .module = elab_mod },
            .{ .name = "proof_core", .module = proof_core_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    }) });

    const test_mlcpd_equiv = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/translator/mlcpd_equiv.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "elab", .module = elab_mod },
            .{ .name = "proof_core", .module = proof_core_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    }) });

    // Protection des liens C pour les tests
    if (target.query.cpu_arch != .wasm32) {
        test_heaven_expr.root_module.addCSourceFile(.{
            .file = b.path("vendor/tree-sitter-heaven/src/parser.c"),
            .flags = &.{"-std=c99"},
        });
        test_heaven_expr.root_module.addIncludePath(b.path("vendor/tree-sitter-heaven/src"));
        test_heaven_expr.root_module.link_libc = true;
        //test_heaven_expr.linkSystemLibrary("tree-sitter");
        if (tree_sitter_lib) |lib| test_heaven_expr.linkLibrary(lib);

        test_elab.root_module.addCSourceFile(.{
            .file = b.path("vendor/tree-sitter-heaven/src/parser.c"),
            .flags = &.{"-std=c99"},
        });
        test_elab.root_module.addIncludePath(b.path("vendor/tree-sitter-heaven/src"));
        test_elab.root_module.link_libc = true;
        //test_elab.linkSystemLibrary("tree-sitter");
        if (tree_sitter_lib) |lib| test_elab.linkLibrary(lib);

        // Liens C pour test_commands (utilise MultiParser → 4 grammaires)
        const test_ts_flags = &.{"-std=c99"};
        test_commands.root_module.addCSourceFile(.{
            .file = b.path("vendor/tree-sitter-heaven/src/parser.c"),
            .flags = test_ts_flags,
        });
        test_commands.root_module.addCSourceFile(.{
            .file = b.path("vendor/tree-sitter-pie/src/parser.c"),
            .flags = test_ts_flags,
        });
        test_commands.root_module.addCSourceFile(.{
            .file = b.path("vendor/tree-sitter-c/src/parser.c"),
            .flags = test_ts_flags,
        });
        test_commands.root_module.addCSourceFile(.{
            .file = b.path("vendor/tree-sitter-zig/src/parser.c"),
            .flags = test_ts_flags,
        });
        test_commands.root_module.addIncludePath(b.path("vendor/tree-sitter-heaven/src"));
        test_commands.root_module.addIncludePath(b.path("vendor/tree-sitter-pie/src"));
        test_commands.root_module.addIncludePath(b.path("vendor/tree-sitter-c/src"));
        test_commands.root_module.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
        test_commands.root_module.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
        test_commands.root_module.link_libc = true;
        //test_commands.linkSystemLibrary("tree-sitter");
        if (tree_sitter_lib) |lib| test_commands.linkLibrary(lib);

        // Liens C pour test_commands_full
        test_commands_full.root_module.addCSourceFile(.{
            .file = b.path("vendor/tree-sitter-heaven/src/parser.c"),
            .flags = &.{"-std=c99"},
        });
        test_commands_full.root_module.addCSourceFile(.{
            .file = b.path("vendor/tree-sitter-pie/src/parser.c"),
            .flags = &.{"-std=c99"},
        });
        test_commands_full.root_module.addCSourceFile(.{
            .file = b.path("vendor/tree-sitter-c/src/parser.c"),
            .flags = &.{"-std=c99"},
        });
        test_commands_full.root_module.addCSourceFile(.{
            .file = b.path("vendor/tree-sitter-zig/src/parser.c"),
            .flags = &.{"-std=c99"},
        });
        test_commands_full.root_module.addIncludePath(b.path("vendor/tree-sitter-heaven/src"));
        test_commands_full.root_module.addIncludePath(b.path("vendor/tree-sitter-pie/src"));
        test_commands_full.root_module.addIncludePath(b.path("vendor/tree-sitter-c/src"));
        test_commands_full.root_module.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
        test_commands_full.root_module.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
        test_commands_full.root_module.link_libc = true;
        //test_commands_full.linkSystemLibrary("tree-sitter");
        if (tree_sitter_lib) |lib| test_commands_full.linkLibrary(lib);
    }

    const test_knowledge = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/knowledge/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "resource", .module = knowledge_resource_mod },
                .{ .name = "triple", .module = knowledge_triple_mod },
                .{ .name = "assertion", .module = knowledge_assertion_mod },
                .{ .name = "knowledge_store", .module = knowledge_store_mod },
                .{ .name = "knowledge_rdfs", .module = knowledge_rdfs_mod },
            },
        }),
    });

    const run_test_knowledge = b.addRunArtifact(test_knowledge);

    const test_step = b.step("test", "Run all tests");

    const test_serialize = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/serialize.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
        },
    }) });
    const run_test_serialize = b.addRunArtifact(test_serialize);
    test_step.dependOn(&run_test_serialize.step);

    const kernel_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/kernel/kernel.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "platform", .module = platform_mod },
            },
        }),
    });
    const run_kernel_tests = b.addRunArtifact(kernel_tests);
    test_step.dependOn(&run_kernel_tests.step);

    if (target.query.cpu_arch != .wasm32) {
        const syntax_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/syntax/core_lower_test.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "expr", .module = expr_mod },
                    .{ .name = "engine_expr", .module = engine_expr_mod },
                },
            }),
        });

        const run_syntax_tests = b.addRunArtifact(syntax_tests);
        test_step.dependOn(&run_syntax_tests.step);
    }

    if (target.query.cpu_arch != .wasm32 and tree_sitter_lib != null) {
        const test_syntax_lower = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/syntax/lower_test.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "syntax_lower", .module = syntax_lower_mod },
                    .{ .name = "platform", .module = platform_mod },
                },
            }),
        });
        if (tree_sitter_lib) |ts_lib| {
            test_syntax_lower.linkLibrary(ts_lib);
        }
        const run_test_syntax_lower = b.addRunArtifact(test_syntax_lower);
        test_step.dependOn(&run_test_syntax_lower.step);
    }

    test_step.dependOn(&run_test_knowledge.step);
    test_step.dependOn(&b.addRunArtifact(test_expr).step);
    test_step.dependOn(&run_test_mir_wat.step);
    test_step.dependOn(&b.addRunArtifact(test_mir_qbe).step);
    test_step.dependOn(&b.addRunArtifact(test_bridge).step);
    test_step.dependOn(&b.addRunArtifact(test_kanren_expr).step);
    test_step.dependOn(&b.addRunArtifact(test_continuation).step);
    test_step.dependOn(&b.addRunArtifact(test_abi_precision).step);
    test_step.dependOn(&b.addRunArtifact(test_abi_error).step);
    test_step.dependOn(&b.addRunArtifact(test_abi_capability).step);
    test_step.dependOn(&b.addRunArtifact(test_abi_metric).step);
    test_step.dependOn(&b.addRunArtifact(test_abi_profile).step);
    test_step.dependOn(&b.addRunArtifact(test_abi_profile_ser).step);
    test_step.dependOn(&b.addRunArtifact(test_abi_profile_tree).step);
    test_step.dependOn(&b.addRunArtifact(test_abi_profile_annotations).step);
    test_step.dependOn(&b.addRunArtifact(test_egraph).step);
    test_step.dependOn(&b.addRunArtifact(test_profile_egraph).step);
    test_step.dependOn(&b.addRunArtifact(test_codegen_c).step);
    test_step.dependOn(&b.addRunArtifact(test_codegen_latex).step);
    test_step.dependOn(&b.addRunArtifact(test_engine).step);
    test_step.dependOn(&b.addRunArtifact(test_heaven_expr).step);
    test_step.dependOn(&b.addRunArtifact(test_types).step);
    test_step.dependOn(&b.addRunArtifact(test_proof).step);
    test_step.dependOn(&b.addRunArtifact(test_skill).step);
    test_step.dependOn(&b.addRunArtifact(test_canon).step);
    test_step.dependOn(&b.addRunArtifact(test_elab).step);
    test_step.dependOn(&b.addRunArtifact(test_commands).step);
    test_step.dependOn(&b.addRunArtifact(test_mlcpd_equiv_integration).step);
    test_step.dependOn(&b.addRunArtifact(test_mlcpd_equiv).step);
    test_step.dependOn(&b.addRunArtifact(test_commands_full).step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |run_args| run_cmd.addArgs(run_args);

    const run_step = b.step("run", "Run heaven");
    run_step.dependOn(&run_cmd.step);

    const run_tests_cmd = b.addRunArtifact(exe);
    run_tests_cmd.addArgs(&.{ "--run-test", "core/test_suite.hvn" });
    const test_regress_step = b.step("test-regression", "Run Heaven internal regression tests");
    test_regress_step.dependOn(&run_tests_cmd.step);

    const tests_step = b.step("test-files", "Run tests/*.hvn");
    const run_tests = b.addRunArtifact(exe);
    run_tests.addArg("--run-tests");
    run_tests.addArg("tests");
    tests_step.dependOn(&run_tests.step);

    // Module C Tree-sitter (si applicable)
    //const tree_sitter_dep = b.dependency("tree_sitter", .{
    //    .target = target,
    //    .optimize = optimize,
    //});

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Si Tree-sitter nécessite le linkage C
    unit_tests.linkLibC();
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    const doc_step = b.step("doc", "Generate documentation");
    doc_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("docs"),
        .install_dir = .prefix,
        .install_subdir = "docs",
    }).step);

    const check_step = b.step("check", "Run all tests and regression suite");
    check_step.dependOn(test_step);
    check_step.dependOn(&run_tests_cmd.step);
}
