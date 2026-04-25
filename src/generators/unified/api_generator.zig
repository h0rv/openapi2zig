const std = @import("std");
const cli = @import("../../cli.zig");
const UnifiedDocument = @import("../../models/common/document.zig").UnifiedDocument;
const Operation = @import("../../models/common/document.zig").Operation;
const Schema = @import("../../models/common/document.zig").Schema;
const SchemaType = @import("../../models/common/document.zig").SchemaType;

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn isReservedIdent(name: []const u8) bool {
    const reserved = [_][]const u8{
        "addrspace", "align",    "allowzero", "and",       "anyerror", "anyframe",    "anyopaque", "anytype",
        "asm",       "async",    "await",     "bool",      "break",    "callconv",    "catch",     "comptime",
        "const",     "continue", "defer",     "else",      "enum",     "errdefer",    "error",     "export",
        "extern",    "false",    "fn",        "for",       "if",       "inline",      "isize",     "linksection",
        "noalias",   "noreturn", "nosuspend", "null",      "opaque",   "or",          "orelse",    "packed",
        "pub",       "resume",   "return",    "struct",    "suspend",  "switch",      "test",      "threadlocal",
        "true",      "try",      "type",      "undefined", "union",    "unreachable", "usize",     "usingnamespace",
        "var",       "void",     "volatile",  "while",
    };
    for (reserved) |word| {
        if (std.mem.eql(u8, name, word)) return true;
    }
    return false;
}

fn isBareIdentifier(name: []const u8) bool {
    if (name.len == 0 or !isIdentStart(name[0]) or isReservedIdent(name)) return false;
    for (name[1..]) |c| {
        if (!isIdentContinue(c)) return false;
    }
    return true;
}

pub const UnifiedApiGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    args: cli.CliArgs,

    pub fn init(allocator: std.mem.Allocator, args: cli.CliArgs) UnifiedApiGenerator {
        return UnifiedApiGenerator{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).empty,
            .args = args,
        };
    }

    pub fn deinit(self: *UnifiedApiGenerator) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn generate(self: *UnifiedApiGenerator, document: UnifiedDocument) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        try self.generateHeader();
        try self.generateApiClient(document);
        return try self.allocator.dupe(u8, self.buffer.items);
    }

    fn appendIdentifier(self: *UnifiedApiGenerator, name: []const u8) !void {
        if (isBareIdentifier(name)) {
            try self.buffer.appendSlice(self.allocator, name);
            return;
        }

        try self.buffer.appendSlice(self.allocator, "@\"");
        for (name) |c| {
            switch (c) {
                '\\', '"' => {
                    try self.buffer.append(self.allocator, '\\');
                    try self.buffer.append(self.allocator, c);
                },
                '\n' => try self.buffer.appendSlice(self.allocator, "\\n"),
                '\r' => try self.buffer.appendSlice(self.allocator, "\\r"),
                '\t' => try self.buffer.appendSlice(self.allocator, "\\t"),
                else => try self.buffer.append(self.allocator, c),
            }
        }
        try self.buffer.appendSlice(self.allocator, "\"");
    }

    fn appendLineComment(self: *UnifiedApiGenerator, text: []const u8) !void {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            try self.buffer.appendSlice(self.allocator, "// ");
            try self.buffer.appendSlice(self.allocator, std.mem.trim(u8, line, "\r"));
            try self.buffer.appendSlice(self.allocator, "\n");
        }
    }

    fn generateHeader(self: *UnifiedApiGenerator) !void {
        try self.buffer.appendSlice(self.allocator, "///////////////////////////////////////////\n");
        try self.buffer.appendSlice(self.allocator, "// Generated Zig API client from OpenAPI\n");
        try self.buffer.appendSlice(self.allocator, "///////////////////////////////////////////\n\n");
    }

    fn generateApiClient(self: *UnifiedApiGenerator, document: UnifiedDocument) !void {
        var path_iterator = document.paths.iterator();
        while (path_iterator.next()) |entry| {
            const path = entry.key_ptr.*;
            const path_item = entry.value_ptr.*;
            try self.generateOperations(path, path_item);
        }
    }

    fn generateOperations(self: *UnifiedApiGenerator, path: []const u8, path_item: @import("../../models/common/document.zig").PathItem) !void {
        if (path_item.get) |op| try self.generateOperation("GET", path, op);
        if (path_item.post) |op| try self.generateOperation("POST", path, op);
        if (path_item.put) |op| try self.generateOperation("PUT", path, op);
        if (path_item.delete) |op| try self.generateOperation("DELETE", path, op);
        if (path_item.patch) |op| try self.generateOperation("PATCH", path, op);
        if (path_item.head) |op| try self.generateOperation("HEAD", path, op);
        if (path_item.options) |op| try self.generateOperation("OPTIONS", path, op);
    }

    fn generateOperation(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
        try self.generateComments(operation);
        try self.generateFunctionSignature(path, operation);
        try self.generateFunctionBody(method, path, operation);
    }

    fn generateComments(self: *UnifiedApiGenerator, operation: Operation) !void {
        if (operation.summary) |summary| {
            try self.buffer.appendSlice(self.allocator, "/////////////////\n");
            try self.buffer.appendSlice(self.allocator, "// Summary:\n");
            try self.appendLineComment(summary);
            try self.buffer.appendSlice(self.allocator, "//\n");
        }

        if (operation.description) |description| {
            try self.buffer.appendSlice(self.allocator, "// Description:\n");
            try self.appendLineComment(description);
            try self.buffer.appendSlice(self.allocator, "//\n");
        }
    }

    fn generateFunctionSignature(self: *UnifiedApiGenerator, path: []const u8, operation: Operation) !void {
        try self.buffer.appendSlice(self.allocator, "pub fn ");

        if (operation.operationId) |op_id| {
            try self.appendIdentifier(op_id);
        } else {
            try self.buffer.appendSlice(self.allocator, "@\"operation");
            try self.buffer.appendSlice(self.allocator, path[1..]);
            try self.buffer.appendSlice(self.allocator, "\"");
        }
        try self.buffer.appendSlice(self.allocator, "(allocator: std.mem.Allocator, io: std.Io");
        if (operation.parameters) |params| {
            for (params) |param| {
                try self.buffer.appendSlice(self.allocator, ", ");
                const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
                try self.appendIdentifier(name);
                try self.buffer.appendSlice(self.allocator, ": ");
                if (param.location == .body) {
                    if (param.schema) |schema| {
                        try self.appendZigTypeFromSchema(schema);
                    } else {
                        try self.buffer.appendSlice(self.allocator, "std.json.Value");
                    }
                } else if (param.type) |param_type| {
                    try self.appendZigTypeFromSchemaType(param_type);
                } else {
                    try self.buffer.appendSlice(self.allocator, "[]const u8");
                }
            }
        }

        try self.buffer.appendSlice(self.allocator, ") !void {\n");
    }

    fn generateFunctionBody(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
        if (operation.parameters) |parameters| {
            for (parameters) |parameter| {
                if (parameter.location != .path and parameter.location != .body) {
                    try self.buffer.appendSlice(self.allocator, "    _ = ");
                    try self.appendIdentifier(parameter.name);
                    try self.buffer.appendSlice(self.allocator, ";\n");
                }
            }
        }

        try self.buffer.appendSlice(self.allocator, "    var client: std.http.Client = .{ .allocator = allocator, .io = io };\n");
        try self.buffer.appendSlice(self.allocator, "    defer client.deinit();\n\n");

        try self.buffer.appendSlice(self.allocator, "    const headers = &[_]std.http.Header{\n");
        try self.buffer.appendSlice(self.allocator, "        .{ .name = \"Content-Type\", .value = \"application/json\" },\n");
        try self.buffer.appendSlice(self.allocator, "        .{ .name = \"Accept\", .value = \"application/json\" },\n");
        try self.buffer.appendSlice(self.allocator, "    };\n\n");

        if (operation.parameters) |parameters| {
            var new_path = path;
            var allocated_paths = std.ArrayList([]u8).empty;
            defer {
                for (allocated_paths.items) |allocated_path| self.allocator.free(allocated_path);
                allocated_paths.deinit(self.allocator);
            }

            for (parameters) |parameter| {
                if (parameter.location != .path) continue;
                const param = parameter.name;
                const param_type = switch (parameter.type orelse .string) {
                    .string => "s",
                    .integer => "d",
                    .number => "d",
                    else => "any",
                };
                const size = std.mem.replacementSize(u8, new_path, param, param_type);
                const output = try self.allocator.alloc(u8, size);
                try allocated_paths.append(self.allocator, output);
                _ = std.mem.replace(u8, new_path, param, param_type, output);
                new_path = output;
            }

            try self.buffer.appendSlice(self.allocator, "    const uri_str = try std.fmt.allocPrint(allocator, \"");
            if (self.args.base_url) |base_url| try self.buffer.appendSlice(self.allocator, base_url);
            try self.buffer.appendSlice(self.allocator, new_path);
            try self.buffer.appendSlice(self.allocator, "\", .{");

            var first_path_param = true;
            for (parameters) |parameter| {
                if (parameter.location != .path) continue;
                if (!first_path_param) try self.buffer.appendSlice(self.allocator, ", ");
                first_path_param = false;
                try self.appendIdentifier(parameter.name);
            }
            try self.buffer.appendSlice(self.allocator, "});\n");

            try self.buffer.appendSlice(self.allocator, "    defer allocator.free(uri_str);\n");
            try self.buffer.appendSlice(self.allocator, "    const uri = try std.Uri.parse(uri_str);\n");
        } else {
            try self.buffer.appendSlice(self.allocator, "    const uri = try std.Uri.parse(\"");
            if (self.args.base_url) |base_url| try self.buffer.appendSlice(self.allocator, base_url);
            try self.buffer.appendSlice(self.allocator, path);
            try self.buffer.appendSlice(self.allocator, "\");\n");
        }

        try self.buffer.appendSlice(self.allocator, "    var req = try client.request(std.http.Method.");
        try self.buffer.appendSlice(self.allocator, method);
        try self.buffer.appendSlice(self.allocator, ", uri, .{ .extra_headers = headers });\n");
        try self.buffer.appendSlice(self.allocator, "    defer req.deinit();\n\n");

        if (std.mem.eql(u8, method, "POST") or std.mem.eql(u8, method, "PUT") or std.mem.eql(u8, method, "PATCH")) {
            var sent_body = false;
            if (operation.parameters) |params| {
                for (params) |param| {
                    if (param.location == .body) {
                        try self.buffer.appendSlice(self.allocator, "    var str: std.Io.Writer.Allocating = .init(allocator);\n");
                        try self.buffer.appendSlice(self.allocator, "    defer str.deinit();\n\n");
                        try self.buffer.appendSlice(self.allocator, "    try std.json.Stringify.value(requestBody, .{}, &str.writer);\n");
                        try self.buffer.appendSlice(self.allocator, "    const payload = str.written();\n\n");
                        try self.buffer.appendSlice(self.allocator, "    req.transfer_encoding = .{ .content_length = payload.len };\n");
                        try self.buffer.appendSlice(self.allocator, "    try req.sendBodyComplete(payload);\n");
                        sent_body = true;
                        break;
                    }
                }
            }
            if (!sent_body) try self.buffer.appendSlice(self.allocator, "    try req.sendBodiless();\n");
        } else {
            try self.buffer.appendSlice(self.allocator, "    try req.sendBodiless();\n");
        }

        try self.buffer.appendSlice(self.allocator, "}\n\n");
    }

    fn appendZigTypeFromSchema(self: *UnifiedApiGenerator, schema: Schema) !void {
        if (schema.ref) |ref| {
            if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| {
                try self.appendIdentifier(ref[last_slash + 1 ..]);
                return;
            }
        }
        if (schema.type) |schema_type| {
            try self.appendZigTypeFromSchemaType(schema_type);
            return;
        }
        try self.buffer.appendSlice(self.allocator, "std.json.Value");
    }

    fn appendZigTypeFromSchemaType(self: *UnifiedApiGenerator, schema_type: SchemaType) !void {
        try self.buffer.appendSlice(self.allocator, switch (schema_type) {
            .string => "[]const u8",
            .integer => "i64",
            .number => "f64",
            .boolean => "bool",
            .array => "[]const std.json.Value",
            .object, .reference => "std.json.Value",
        });
    }
};
