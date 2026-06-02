//! Test runner for module 04 acceptance tests.
//! Run with: zig test docs/04_test_runner.zig (from project root)
//! Or:       zig test 04_test_runner.zig (from docs/)
//!
//! This file exists at the docs/ level so that relative imports in the
//! acceptance test (e.g. ../03_element_store/types.zig) resolve within
//! the module path boundary.

comptime {
    _ = @import("specs/04.acceptance_test.zig");
}
