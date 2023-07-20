const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const Tuple = @import("../raytracer/tuple.zig").Tuple;
const Shape = @import("../raytracer/shapes/shape.zig").Shape;
const Material = @import("../raytracer/material.zig").Material;

pub fn ObjParser(comptime T: type) type {
    return struct {
        const Self = @This();
        const Error = error {
            LineEmpty,
            UnknownFirstToken,
            IncompleteVertex,
            IncompleteFace,
            IncompleteNamedGroup
        };

        shape_allocator: Allocator,
        default_group: *Shape(T),
        active_group: *Shape(T),
        named_groups: StringHashMap(*Shape(T)),
        vertices: ArrayList(Tuple(T)),
        lines_ignored: usize,

        pub fn new(list_allocator: Allocator, shape_allocator: Allocator) !Self {
            var default_group = try shape_allocator.create(Shape(T));
            default_group.* = Shape(T).group(shape_allocator);

            return .{
                .shape_allocator = shape_allocator,
                .default_group = default_group,
                .active_group = default_group,
                .named_groups = StringHashMap(*Shape(T)).init(shape_allocator),
                .lines_ignored = 0,
                .vertices = ArrayList(Tuple(T)).init(list_allocator),
            };
        }

        pub fn destroy(self: Self) void {
            self.vertices.deinit();
        }

        fn handleVertex(self: *Self, tokens: *std.mem.TokenIterator(u8, .scalar)) !void {
            const x = try std.fmt.parseFloat(
                T, tokens.next() orelse { return Self.Error.IncompleteVertex; }
            );
            const y = try std.fmt.parseFloat(
                T, tokens.next() orelse { return Self.Error.IncompleteVertex; }
            );
            const z = try std.fmt.parseFloat(
                T, tokens.next() orelse { return Self.Error.IncompleteVertex; }
            );

            // Ignore any trailing items

            try self.vertices.append(Tuple(T).point(x, y, z));
        }

        fn handleFace(
            self: *Self, tokens: *std.mem.TokenIterator(u8, .scalar), material: ?Material(T)
        ) !void {
            const first = try std.fmt.parseInt(
                usize, tokens.next() orelse { return Self.Error.IncompleteFace; }, 10
            );

            var last = try std.fmt.parseInt(
                usize, tokens.next() orelse { return Self.Error.IncompleteFace; }, 10
            );

            _ = tokens.peek() orelse { return Self.Error.IncompleteFace; };

            var str = tokens.next();
            while (str) |next| : (str = tokens.next()) {
                var current = try std.fmt.parseInt(usize, next, 10);
            
                // Vertices are 1-indexed
                const p1 = self.vertices.items[first - 1];
                const p2 = self.vertices.items[last - 1];
                const p3 = self.vertices.items[current - 1];

                var triangle = try self.shape_allocator.create(Shape(T));
                triangle.* = Shape(T).triangle(p1, p2, p3);
                triangle.material = material orelse Material(T).new();

                try self.active_group.addChild(triangle);

                last = current;
            }
        }

        fn handleNamedGroup(self: *Self, tokens: *std.mem.TokenIterator(u8, .scalar)) !void {
            const str = tokens.next() orelse { return Self.Error.IncompleteNamedGroup; };

            // Ignore trailing items.

            // Copy the name string so that we own the memory.
            var name = try self.shape_allocator.alloc(u8, str.len);
            @memcpy(name, str);

            var new_group = try self.shape_allocator.create(Shape(T));
            new_group.* = Shape(T).group(self.shape_allocator);

            try self.default_group.addChild(new_group);
            try self.named_groups.put(name, new_group);
            self.active_group = new_group;
        }

        fn handleLine(self: *Self, line: []const u8, material: ?Material(T)) !void {
            var tokens = std.mem.tokenizeScalar(u8, line, ' ');
            if (tokens.next()) |first| {
                if (std.mem.eql(u8, first, "v")) {
                    try self.handleVertex(&tokens);
                } else if (std.mem.eql(u8, first, "f")) {
                    try self.handleFace(&tokens, material);
                } else if (std.mem.eql(u8, first, "g")) {
                    try self.handleNamedGroup(&tokens);
                } else {
                    return Self.Error.UnknownFirstToken;
                }
            } else {
                return Self.Error.LineEmpty;
            }
        }

        pub fn loadObj(self: *Self, obj: []const u8, material: ?Material(T)) void {
            var lines = std.mem.tokenizeScalar(u8, obj, '\n');
            var l = lines.next();

            while (l) |line| : (l = lines.next()) {
                self.handleLine(line, material) catch { self.lines_ignored += 1; };
            }
        }

        pub fn toGroup(self: Self) *Shape(T) {
            return self.default_group;
        }

    };
}

test "Ignoring unrecognized lines" {
    const list_allocator = testing.allocator;
    var shape_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer shape_arena.deinit();
    const shape_allocator = shape_arena.allocator();

    const gibberish =
        \\There was a young lady named Bright
        \\who traveled much faster than light.
        \\She set out one day
        \\in a relative way,
        \\and came back the previous night.
    ;

    var parser = try ObjParser(f32).new(list_allocator, shape_allocator);
    defer parser.destroy();

    parser.loadObj(gibberish, null);

    try testing.expectEqual(parser.lines_ignored, 5);
}

test "Vertex records" {
    const list_allocator = testing.allocator;
    var shape_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer shape_arena.deinit();
    const shape_allocator = shape_arena.allocator();

    const obj =
        \\v -1 1 0
        \\v -1.0000 0.5000 0.0000
        \\v 1 0 0
        \\v 1 1 0
    ;

    var parser = try ObjParser(f32).new(list_allocator, shape_allocator);
    defer parser.destroy();

    parser.loadObj(obj, null);

    try testing.expectEqual(parser.lines_ignored, 0);

    try testing.expectEqual(
        parser.vertices.items[0], Tuple(f32).point(-1.0, 1.0, 0.0)
    );
    try testing.expectEqual(
        parser.vertices.items[1], Tuple(f32).point(-1.0, 0.5, 0.0)
    );
    try testing.expectEqual(
        parser.vertices.items[2], Tuple(f32).point(1.0, 0.0, 0.0)
    );
    try testing.expectEqual(
        parser.vertices.items[3], Tuple(f32).point(1.0, 1.0, 0.0)
    );
}

test "Parsing triangle faces" {
    const list_allocator = testing.allocator;
    var shape_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer shape_arena.deinit();
    const shape_allocator = shape_arena.allocator();

    const obj =
        \\v -1 1 0
        \\v -1 0 0
        \\v 1 0 0
        \\v 1 1 0
        \\f 1 2 3
        \\f 1 3 4
    ;

    var parser = try ObjParser(f32).new(list_allocator, shape_allocator);
    defer parser.destroy();

    parser.loadObj(obj, null);

    try testing.expectEqual(parser.lines_ignored, 0);

    try testing.expectEqual(parser.default_group.variant.group.children.items.len, 2);

    const t1 = &parser.default_group.variant.group.children.items[0].variant.triangle;
    const t2 = &parser.default_group.variant.group.children.items[1].variant.triangle;

    try testing.expectEqual(t1.p1, parser.vertices.items[0]);
    try testing.expectEqual(t1.p2, parser.vertices.items[1]);
    try testing.expectEqual(t1.p3, parser.vertices.items[2]);
    try testing.expectEqual(t2.p1, parser.vertices.items[0]);
    try testing.expectEqual(t2.p2, parser.vertices.items[2]);
    try testing.expectEqual(t2.p3, parser.vertices.items[3]);
}

test "Triangulating polygons" {
    const list_allocator = testing.allocator;
    var shape_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer shape_arena.deinit();
    const shape_allocator = shape_arena.allocator();

    const obj =
        \\v -1 1 0
        \\v -1 0 0
        \\v 1 0 0
        \\v 1 1 0
        \\v 0 2 0
        \\f 1 2 3 4 5
    ;

    var parser = try ObjParser(f32).new(list_allocator, shape_allocator);
    defer parser.destroy();

    parser.loadObj(obj, null);

    try testing.expectEqual(parser.lines_ignored, 0);
    try testing.expectEqual(parser.default_group.variant.group.children.items.len, 3);

    const t1 = &parser.default_group.variant.group.children.items[0].variant.triangle;
    const t2 = &parser.default_group.variant.group.children.items[1].variant.triangle;
    const t3 = &parser.default_group.variant.group.children.items[2].variant.triangle;

    try testing.expectEqual(t1.p1, parser.vertices.items[0]);
    try testing.expectEqual(t1.p2, parser.vertices.items[1]);
    try testing.expectEqual(t1.p3, parser.vertices.items[2]);
    try testing.expectEqual(t2.p1, parser.vertices.items[0]);
    try testing.expectEqual(t2.p2, parser.vertices.items[2]);
    try testing.expectEqual(t2.p3, parser.vertices.items[3]);
    try testing.expectEqual(t3.p1, parser.vertices.items[0]);
    try testing.expectEqual(t3.p2, parser.vertices.items[3]);
    try testing.expectEqual(t3.p3, parser.vertices.items[4]);
}

test "Triangles in groups" {
    const list_allocator = testing.allocator;
    var shape_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer shape_arena.deinit();
    const shape_allocator = shape_arena.allocator();

    const obj =
        \\v -1 1 0
        \\v -1 0 0
        \\v 1 0 0
        \\v 1 1 0
        \\g FirstGroup
        \\f 1 2 3
        \\g SecondGroup
        \\f 1 3 4
    ;

    var parser = try ObjParser(f32).new(list_allocator, shape_allocator);
    defer parser.destroy();

    parser.loadObj(obj, null);

    try testing.expectEqual(parser.lines_ignored, 0);

    const g1 = &parser.named_groups.get("FirstGroup").?.variant.group;
    const g2 = &parser.named_groups.get("SecondGroup").?.variant.group;

    const t1 = &g1.children.items[0].variant.triangle;
    const t2 = &g2.children.items[0].variant.triangle;

    try testing.expectEqual(t1.p1, parser.vertices.items[0]);
    try testing.expectEqual(t1.p2, parser.vertices.items[1]);
    try testing.expectEqual(t1.p3, parser.vertices.items[2]);
    try testing.expectEqual(t2.p1, parser.vertices.items[0]);
    try testing.expectEqual(t2.p2, parser.vertices.items[2]);
    try testing.expectEqual(t2.p3, parser.vertices.items[3]);
}

test "Converting an OBJ file to a group" {
    const list_allocator = testing.allocator;
    var shape_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer shape_arena.deinit();
    const shape_allocator = shape_arena.allocator();

    const obj =
        \\v -1 1 0
        \\v -1 0 0
        \\v 1 0 0
        \\v 1 1 0
        \\g FirstGroup
        \\f 1 2 3
        \\g SecondGroup
        \\f 1 3 4
    ;

    var parser = try ObjParser(f32).new(list_allocator, shape_allocator);
    defer parser.destroy();

    parser.loadObj(obj, null);

    try testing.expectEqual(parser.lines_ignored, 0);

    const g = parser.toGroup();

    const g1 = parser.named_groups.get("FirstGroup").?;
    const g2 = parser.named_groups.get("SecondGroup").?;

    try testing.expectEqual(g.variant.group.children.items[0], g1);
    try testing.expectEqual(g.variant.group.children.items[1], g2);
}
