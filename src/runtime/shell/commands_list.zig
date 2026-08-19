const std = @import("std");

pub const CommandTag = enum {
    exit,
    help,
    stats,
    doc,
    load,
    cmd_type,
    infer,
    qtt,
    dep,
    hole,
    prove,
    theorem,
    axiom,
    proof,
    theorems,
    skill,
    simplify,
    rewrite,
    explain,
    eval,
    quote,
    latex,
    let_var,
    derive,
    solve,
    expand,
    integrate,
    plot,
    fact,
    rule,
    ask,
    run_star,
    query,
    transpile,
    compile,
    c_out,
    memo,
    trace,
    optimize,
    hook,
    onto,
    isa,
    meta,
    subst,
    sexpr,
    spawn,
    threads,
    await,
    swarm,
    mlcpd_parse,
    mlcpd_convert,
    mlcpd_stats,
    mcp_serve,
    parse_file,
    dump_ast,
    translate_dump,
};

pub const CommandTarget = enum {
    both,
    native_only,
    wasm_only,
};

pub const Command = struct {
    name: []const u8,
    shortcut: ?[]const u8 = null,
    description: []const u8,
    method: []const u8,
    tag: CommandTag, // <--- On remplace le handler par un tag
    target: CommandTarget = .both,
};

pub const commands = [_]Command{
    // Système & Moteur
    .{ .name = "exit", .tag = .exit, .shortcut = "q", .description = "Quitter le shell", .method = "exit", .target = .native_only },
    .{ .name = "help", .tag = .help, .shortcut = "h", .description = "Cette aide", .method = "printHelp" },
    .{ .name = "stats", .tag = .stats, .shortcut = "s", .description = "Statistiques du moteur", .method = "cmdStats" },
    .{ .name = "doc", .tag = .doc, .description = "Documentation des primitives", .method = "cmdDoc" },
    .{ .name = "load", .tag = .load, .description = "Charger un fichier .hvn", .method = "cmdLoad" },

    // Logique & Types
    .{ .name = "type", .tag = .cmd_type, .shortcut = "t", .description = "Type d'une expression", .method = "cmdType" },
    .{ .name = "infer", .tag = .infer, .description = "Inférer le type d'une expression", .method = "cmdInfer" },
    .{ .name = "qtt", .tag = .qtt, .description = "Vérification Quantitative Type Theory", .method = "cmdQTT" },
    .{ .name = "dep", .tag = .dep, .shortcut = "dependent", .description = "Types dépendants", .method = "cmdDep" },
    .{ .name = "hole", .tag = .hole, .shortcut = "?", .description = "Résolution de trou de type", .method = "cmdHole" },

    // Théorèmes & Preuves
    .{ .name = "prove", .tag = .prove, .description = "Prouver une égalité", .method = "cmdProve" },
    .{ .name = "theorem", .tag = .theorem, .shortcut = "thm", .description = "Déclarer un théorème", .method = "cmdTheorem" },
    .{ .name = "axiom", .tag = .axiom, .shortcut = "ax", .description = "Assumer un axiome", .method = "cmdAxiom" },
    .{ .name = "proof", .tag = .proof, .shortcut = "pf", .description = "Lancer une preuve", .method = "cmdProof" },
    .{ .name = "theorems", .tag = .theorems, .shortcut = "thms", .description = "Liste les théorèmes et axiomes", .method = "cmdTheorems" },
    .{ .name = "skill", .tag = .skill, .description = "Appliquer un skill sur le goal courant", .method = "cmdSkill" },

    // Calcul Symbolique & Transformation
    .{ .name = "simplify", .tag = .simplify, .shortcut = "simp", .description = "Simplifier (rewrite)", .method = "exprSimplify" },
    .{ .name = "rewrite", .tag = .rewrite, .shortcut = "rw", .description = "Ajouter une règle de réécriture", .method = "exprRewrite" },
    .{ .name = "explain", .tag = .explain, .shortcut = "x", .description = "Détailler les étapes de calcul", .method = "cmdExplain" },
    .{ .name = "eval", .tag = .eval, .shortcut = "e", .description = "Évaluer une expression", .method = "exprEval" },
    .{ .name = "quote", .tag = .quote, .description = "Afficher l'AST", .method = "cmdQuote" },
    .{ .name = "latex", .tag = .latex, .shortcut = "l", .description = "Générer le rendu LaTeX", .method = "cmdLaTeX" },
    .{ .name = "let", .tag = .let_var, .description = "Assignation locale", .method = "cmdLet" },
    .{ .name = "derive", .tag = .derive, .shortcut = "d", .description = "Dérivation symbolique d/dx", .method = "cmdDerive" },
    .{ .name = "solve", .tag = .solve, .description = "Résoudre une équation", .method = "cmdSolve" },
    .{ .name = "expand", .tag = .expand, .description = "Développer une expression", .method = "cmdExpand" },
    .{ .name = "integrate", .tag = .integrate, .shortcut = "int", .description = "Intégration symbolique", .method = "cmdIntegrate" },
    .{ .name = "plot", .tag = .plot, .shortcut = "p", .description = "Tracer une fonction", .method = "cmdPlot" },

    // Programmation Logique & miniKanren
    .{ .name = "fact", .tag = .fact, .shortcut = "f", .description = "Asserter un fait Prolog", .method = "exprFact" },
    .{ .name = "rule", .tag = .rule, .shortcut = "r", .description = "Ajouter une règle Prolog", .method = "exprRule" },
    .{ .name = "ask", .tag = .ask, .description = "Query Prolog", .method = "cmdAsk" },
    .{ .name = "run*", .tag = .run_star, .description = "Query miniKanren", .method = "cmdRunStar" },
    .{ .name = "query", .tag = .query, .description = "Requête générique", .method = "exprQuery" },

    // Compilation & Transpilation
    .{ .name = "transpile", .tag = .transpile, .description = "Générer du code C", .method = "cmdTranspile" },
    .{ .name = "compile", .tag = .compile, .description = "Compiler vers un exécutable via C", .method = "cmdCompile" },
    .{ .name = "c", .tag = .c_out, .description = "Transpiler l'expression en C brut", .method = "cmdToC" },

    // Optimisation & Traçage
    .{ .name = "memo", .tag = .memo, .description = "Gérer la mémoïzation", .method = "cmdMemo" },
    .{ .name = "trace", .tag = .trace, .description = "Tracer l'exécution", .method = "cmdTrace" },
    .{ .name = "optimize", .tag = .optimize, .shortcut = "opt", .description = "Optimiser l'expression", .method = "cmdOptimize" },
    .{ .name = "hook", .tag = .hole, .description = "Enregistrer un hook événement => agent", .method = "cmdHook" },
    .{ .name = "green", .tag = .cmd_type, .description = "Profile une expression (Effets + Énergie)", .method = "cmdGreen" },

    // Ontologie & S-Expr
    .{ .name = "onto", .tag = .onto, .shortcut = "ontology", .description = "Gérer l'ontologie", .method = "cmdOnto" },
    .{ .name = "isa", .tag = .isa, .description = "Vérifier une relation d'héritage", .method = "cmdIsA" },
    .{ .name = "meta", .tag = .meta, .description = "Réflexion méta-système", .method = "cmdMeta" },
    .{ .name = "subst", .tag = .subst, .description = "Substitution explicite", .method = "cmdSubst" },
    .{ .name = "sexpr", .tag = .sexpr, .description = "Afficher le format S-Expression", .method = "cmdSExpr" },

    // Concurrence & Swarm (Bobiverse)
    .{ .name = "spawn", .tag = .spawn, .shortcut = "go", .description = "Instancier un green thread", .method = "cmdSpawn" },
    .{ .name = "threads", .tag = .threads, .shortcut = "gt", .description = "Lister les green threads actifs", .method = "cmdThreads" },
    .{ .name = "await", .tag = .await, .shortcut = "aw", .description = "Attendre la fin d'un thread", .method = "cmdAwait" },
    .{ .name = "swarm", .tag = .swarm, .shortcut = "sw", .description = "Piloter le Swarm de calcul", .method = "cmdSwarm" },
    // ─── MLCPD (MultiLang Code Parser Dataset) ───
    .{ .name = "mlcpd", .tag = .mlcpd_parse, .description = "Parser code via MLCPD universal AST schema", .method = "cmdMlcpdParse", .target = .native_only },
    .{ .name = "mlcpd-convert", .tag = .mlcpd_convert, .description = "Convert MLCPD AST → Heaven Expr IR", .method = "cmdMlcpdConvert", .target = .native_only },
    .{ .name = "mlcpd-stats", .tag = .mlcpd_stats, .description = "Show MLCPD dataset statistics", .method = "cmdMlcpdStats", .target = .native_only },
    // ─── MCP (Model Context Protocol) ───
    .{ .name = "mcp", .tag = .mcp_serve, .description = "Start MCP server for AI assistant integration", .method = "cmdMcpServe", .target = .native_only },
    .{ .name = "mlcpd-equiv", .tag = .mlcpd_parse, .description = "Check structural equivalence of two MLCPD files via EGraph", .method = "cmdMlcpdEquiv", .target = .native_only },
    //
    .{ .name = "parseFileWithLanguage", .tag = .parse_file, .description = "Parse un fichier selon son extension", .method = "cmdParseFile", .target = .native_only },
    .{ .name = "dumpAstFile", .tag = .dump_ast, .description = "Affiche l'AST brut d'un fichier parsé", .method = "cmdDumpAstFile", .target = .native_only },
    .{ .name = "translateAndDump", .tag = .translate_dump, .description = "Traduit et affiche l'AST Heaven", .method = "cmdTranslateAndDump", .target = .native_only },
};
