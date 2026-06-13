//! Unit tests for regex module (M18-01 RH1)

const std = @import("std");
const regex = @import("regex.zig");
const testing = std.testing;

test "literal match" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const pattern = try regex.compilePattern(arena.allocator(), "abc");
    defer pattern.deinit();

    try testing.expect(regex.matches(pattern, "abc"));
    try testing.expect(!regex.matches(pattern, "abd"));
    try testing.expect(!regex.matches(pattern, "ab"));
    try testing.expect(!regex.matches(pattern, "abcd"));
}

test "anchor start" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const pattern = try regex.compilePattern(arena.allocator(), "^abc");
    defer pattern.deinit();

    try testing.expect(regex.matches(pattern, "abc"));
    try testing.expect(!regex.matches(pattern, "xabc"));
}

test "anchor end" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const pattern = try regex.compilePattern(arena.allocator(), "abc$");
    defer pattern.deinit();

    try testing.expect(regex.matches(pattern, "abc"));
    try testing.expect(!regex.matches(pattern, "abcx"));
}

test "email validation" {
    try testing.expect(regex.isValidEmail("user@example.com"));
    try testing.expect(regex.isValidEmail("test.user@domain.co.uk"));
    try testing.expect(regex.isValidEmail("a@b.co"));

    try testing.expect(!regex.isValidEmail("noatsign.com"));
    try testing.expect(!regex.isValidEmail("@example.com"));
    try testing.expect(!regex.isValidEmail("user@"));
    try testing.expect(!regex.isValidEmail("user@.com"));
}

test "url validation" {
    try testing.expect(regex.isValidUrl("http://example.com"));
    try testing.expect(regex.isValidUrl("https://example.com"));
    try testing.expect(!regex.isValidUrl("example.com"));
}
