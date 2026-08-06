const platform = @import("platform");

/// ShellParser — abstraction selon la plateforme.
/// - Native : parser tree-sitter réel (tree-sitter-heaven).
/// - WASM   : stub qui renvoie une erreur (tree-sitter indisponible en freestanding).
pub const ShellParser = platform.ShellParser;
pub const ParseError = platform.shell_parser_types.ParseError;
pub const Matrix = platform.shell_parser_types.Matrix;
pub const NodeKind = platform.shell_parser_types.NodeKind;
