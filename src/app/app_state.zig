//! AppState(T) — top-level signal tree for application-wide state (R81 / M8-02).
//!
//! INV-3.3: AppState signals follow the same dirty-bitset mechanism as all other signals.
//! No new change-propagation path is introduced.
//! INV-1.1: No plugin system, no configurable slots. Hardcoded generic struct pattern.

const std = @import("std");

/// A comptime-generic container wrapping a user-defined struct `T` whose fields
/// are Signal instances (or any type with a `deinit` method).
///
/// Owned by the application entry point and shared across screens via the `ctx`
/// argument to `Navigator.push`. Provides `get()` returning `*T` for direct
/// signal access. Optionally exposed as a thread-local singleton via
/// `setGlobal` / `getGlobal`.
pub fn AppState(comptime T: type) type {
    return struct {
        gpa: std.mem.Allocator,
        inner: T,

        const Self = @This();

        /// Initialise from a value-initialised T.
        /// Signal fields in `initial` must already be initialised by the caller
        /// using the real 3-arg Signal.init(gpa, value, dirty_ptr).
        pub fn init(gpa: std.mem.Allocator, initial: T) !Self {
            return Self{ .gpa = gpa, .inner = initial };
        }

        /// Deinit all fields in T that have a deinit method (comptime field walk).
        /// Fields without a deinit method are left alone.
        pub fn deinit(self: *Self) void {
            inline for (std.meta.fields(T)) |f| {
                const FieldType = f.type;
                // @hasDecl only works on struct/enum/union/opaque types.
                // Skip primitives and pointer types that cannot have declarations.
                const type_info = @typeInfo(FieldType);
                const can_have_decl = switch (type_info) {
                    .@"struct", .@"enum", .@"union", .@"opaque" => true,
                    else => false,
                };
                if (can_have_decl and @hasDecl(FieldType, "deinit")) {
                    @field(self.inner, f.name).deinit();
                }
            }
        }

        /// Return a mutable pointer to the inner state struct.
        pub fn get(self: *Self) *T {
            return &self.inner;
        }

        /// Optional global singleton (thread-local; single-threaded per INV-2.1).
        /// NOT thread-safe. Call only from the main thread.
        /// pub so that tests can reset the global between test cases.
        pub var _global: ?*Self = null;

        /// Register this AppState instance as the process-level global.
        /// A second call silently overwrites the first.
        pub fn setGlobal(self: *Self) void {
            _global = self;
        }

        /// Return the global AppState instance, or null if setGlobal has not yet been called.
        pub fn getGlobal() ?*Self {
            return _global;
        }
    };
}
