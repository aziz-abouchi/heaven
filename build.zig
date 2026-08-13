const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const network = b.option(bool, "network", "Enable native networking (WebRTC/SCUT)") orelse true;

    // 1. Options globales
    const options = b.addOptions();
    options.addOption(bool, "is_wasm", target.query.cpu_arch == .wasm32);
    options.addOption(bool, "network", network);
    options.addOption(i64, "build_timestamp", std.time.timestamp());

    // 2. Création dynamique des modules
    const expr_mod = b.addModule("expr", .{
        .root_source_file = b.path("src/core/expr.zig"),
        .target = target,
        .optimize = optimize,
    });

    const platform_mod = b.addModule("platform", .{
        .root_source_file = b.path(if (target.query.cpu_arch == .wasm32)
            "src/platform/wasm.zig"
        else
            "src/platform/native.zig"),
        .target = target,
        .optimize = optimize,
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

    // Mettre à jour platform_mod pour qu'il puisse utiliser driver/queue si besoin
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

    const engine_expr_mod = b.createModule(.{
        .root_source_file = b.path("src/core/engine_expr.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "platform", .module = platform_mod },
            .{ .name = "pattern", .module = pattern_mod },
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
        .root_source_file = b.path("src/core/kanren_expr.zig"),
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

    const egraph_mod = b.createModule(.{
        .root_source_file = b.path("src/inference/eqsat/egraph.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "expr", .module = expr_mod }, .{ .name = "kanren", .module = kanren_expr_mod }, .{ .name = "canon", .module = canon_mod } },
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

    const types_mod = b.createModule(.{
        .root_source_file = b.path("src/core/types.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
        },
    });

    const ontology_mod = b.createModule(.{
        .root_source_file = b.path("src/core/ontology.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
        },
    });

    const kernel_mod = b.addModule("kernel", .{
        .root_source_file = b.path("src/core/kernel.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
        },
    });
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
        },
    });

    // Module parzig pour lecture Parquet streaming
    const parzig_dep = b.dependency("parzig", .{
        .target = target,
        .optimize = optimize,
    });
    const parzig_mod = parzig_dep.module("parzig");

    const mlcpd_mod = b.addModule("mlcpd", .{
        .root_source_file = b.path("src/core/mlcpd.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "parzig", .module = parzig_mod },
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
        },
    });

    const mlcpd_equiv_mod = b.addModule("mlcpd_equiv", .{
        .root_source_file = b.path("src/core/mlcpd_equiv.zig"),
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
        .root_source_file = b.path("src/core/universal_translator.zig"),
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

    const agent_mod = b.addModule("agent", .{
        .root_source_file = b.path("src/core/agent.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
        },
    });

    const shell_parser_types_mod = b.createModule(.{
        .root_source_file = b.path("src/platform/shell_parser_types.zig"),
        .target = target,
        .optimize = optimize,
    });
    platform_mod.addImport("shell_parser_types", shell_parser_types_mod);

    const shell_parser_mod = b.createModule(.{
        .root_source_file = b.path("src/core/shell_parser.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = platform_mod },
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
        },
    });
    commands_mod.addOptions("build_options", options);

    const heaven_expr_mod = b.createModule(.{
        .root_source_file = b.path("src/core/heaven_expr.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
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
            .{ .name = "agent", .module = agent_mod },
            .{ .name = "commands", .module = commands_mod },
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

    const kanren_legacy_mod = b.createModule(.{
        .root_source_file = b.path("src/logic/kanren.zig"),
        .target = target,
        .optimize = optimize,
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
                    .{ .name = "kanren", .module = kanren_legacy_mod },
                    .{ .name = "codegen_c", .module = codegen_c_legacy_mod },
                    .{ .name = "matrix_bridge", .module = matrix_bridge_mod },
                    .{ .name = "heaven_expr", .module = heaven_expr_mod },
                    .{ .name = "ontology", .module = ontology_mod },
                    .{ .name = "types", .module = types_mod },
                    .{ .name = "lowering", .module = lowering_mod },
                    .{ .name = "matrix_lib", .module = matrix_mod },
                    .{ .name = "platform", .module = platform_mod },
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
                    .{ .name = "egraph_rewriter", .module = egraph_rewriter_mod },
                    .{ .name = "shell_commands", .module = commands_list_mod },
                    .{ .name = "shell_parser", .module = shell_parser_mod },
                    .{ .name = "parse", .module = parse_mod },
                    .{ .name = "math", .module = math_mod },
                    .{ .name = "transform", .module = transform_mod },
                    .{ .name = "proof_core", .module = proof_core_mod },
                    .{ .name = "agent", .module = agent_mod },
                    .{ .name = "commands", .module = commands_mod },
                },
            },
        ),
    });

    exe.root_module.addOptions("build_options", options);

    // ═══════════════════════════════════════════════════
    // Tree-sitter : grammaires compilées pour NATIF et WASM
    // ═══════════════════════════════════════════════════

    if (target.query.cpu_arch != .wasm32) {
        // ─── NATIF : tree-sitter (runtime système + grammaires) ───
        const ts_grammar_flags = &.{"-std=c99"};
        exe.root_module.addCSourceFile(.{ .file = b.path("vendor/tree-sitter-c/src/parser.c"), .flags = ts_grammar_flags });
        exe.root_module.addCSourceFile(.{ .file = b.path("vendor/tree-sitter-heaven/src/parser.c"), .flags = ts_grammar_flags });
        exe.root_module.addCSourceFile(.{ .file = b.path("vendor/tree-sitter-pie/src/parser.c"), .flags = ts_grammar_flags });
        exe.root_module.addCSourceFile(.{ .file = b.path("vendor/tree-sitter-zig/src/parser.c"), .flags = ts_grammar_flags });
        exe.root_module.addIncludePath(b.path("vendor/tree-sitter-c/src"));
        exe.root_module.addIncludePath(b.path("vendor/tree-sitter-heaven/src"));
        exe.root_module.addIncludePath(b.path("vendor/tree-sitter-pie/src"));
        exe.root_module.addIncludePath(b.path("vendor/tree-sitter-zig/src"));
        exe.root_module.addIncludePath(b.path("vendor/tree-sitter/lib/include"));

        // WebRTC + TCC + libc
        if (network) {
            exe.addIncludePath(b.path("vendor/libdatachannel/include"));
            exe.addCSourceFile(.{
                .file = b.path("src/platform/webrtc_impl.cpp"),
                .flags = &.{ "-std=c++17", "-Drtc_EXPORTS", "-fno-sanitize=undefined" },
            });
            exe.addIncludePath(b.path("src/platform"));
            exe.linkSystemLibrary("datachannel");
            exe.linkLibCpp();
        } else {
            exe.root_module.addAnonymousImport("network_stub", .{
                .root_source_file = b.path("src/platform/network_stub.zig"),
            });
        }

        exe.root_module.link_libc = true;
        exe.linkSystemLibrary("tree-sitter");
        exe.linkSystemLibrary("tcc");
        exe.linkLibC();
    } else {
        // ─── WASM : pas de tree-sitter C (freestanding = pas de libc) ───
        // Le ShellParser WASM retourne NotSupported, et commands.zig
        // bascule sur bridge.importExpr (fallback).
        exe.entry = .disabled;
        exe.rdynamic = true;
    }

    b.installArtifact(exe);

    // ═══════════════════════════════════════════════════
    //  Tests (nouveau noyau — pas besoin de tree-sitter)
    // ═══════════════════════════════════════════════════

    const test_expr = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/expr.zig"),
        .target = target,
        .optimize = optimize,
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

    const test_kanren = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/kanren_expr.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "expr", .module = expr_mod }},
    }) });

    const test_egraph = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/inference/eqsat/egraph.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "expr", .module = expr_mod },
            .{ .name = "kanren", .module = kanren_expr_mod },
            .{ .name = "canon", .module = canon_mod },
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
        .imports = &.{.{ .name = "expr", .module = expr_mod }},
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
        },
    }) });

    const test_commands = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/commands_test.zig"),
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
        .root_source_file = b.path("src/core/mlcpd_equiv.zig"),
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
        test_heaven_expr.linkSystemLibrary("tree-sitter");

        test_elab.root_module.addCSourceFile(.{
            .file = b.path("vendor/tree-sitter-heaven/src/parser.c"),
            .flags = &.{"-std=c99"},
        });
        test_elab.root_module.addIncludePath(b.path("vendor/tree-sitter-heaven/src"));
        test_elab.root_module.link_libc = true;
        test_elab.linkSystemLibrary("tree-sitter");

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
        test_commands.linkSystemLibrary("tree-sitter");
    }

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&b.addRunArtifact(test_expr).step);
    test_step.dependOn(&b.addRunArtifact(test_bridge).step);
    test_step.dependOn(&b.addRunArtifact(test_kanren).step);
    test_step.dependOn(&b.addRunArtifact(test_egraph).step);
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

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |run_args| run_cmd.addArgs(run_args);

    const run_step = b.step("run", "Run heaven");
    run_step.dependOn(&run_cmd.step);

    const run_tests_cmd = b.addRunArtifact(exe);
    run_tests_cmd.addArgs(&.{ "--run-test", "core/test_suite.hvn" });
    const test_regress_step = b.step("test-regression", "Run Heaven internal regression tests");
    test_regress_step.dependOn(&run_tests_cmd.step);
}
