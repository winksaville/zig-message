// Create a Message that supports arbitrary data
// and can be passed between entities via a Queue.

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Queue = std.atomic.Queue;

/// Message with a header and body. Header
/// has information common to all Messages
/// and body is a comptime type with information
/// unique to each Message.
///
/// Using packed struct guarantees field ordering
/// and no padding. I'd also like to guarantee
/// endianness so messages can have a consistent
/// external representation.
fn Message(comptime BodyType: type) type {
    return packed struct {
        const Self = @This();

        pub header: MessageHeader,
        pub body: BodyType,

        pub fn init(cmd: u64) Self {
            var self: Self = undefined;
            self.header.init(cmd, &self);
            BodyType.init(&self.body);
            return self;
        }
    };
}

/// MessageHeader is the common information for
/// all Messages and is the type that is used
/// to place a message on a Queue.
const MessageHeader = packed struct {
    const Self = @This();

    pub message_offset: usize,
    pub cmd: u64,

    /// Initialize the header
    pub fn init(self: *Self, cmd: u64, message_ptr: var) void {
        self.cmd = cmd;
        self.message_offset = @ptrToInt(&self.message_offset) - @ptrToInt(message_ptr);
    }

    /// Get the address of the message associated with the header
    pub fn getMessagePtrAs(self: *const Self, comptime T: type) T {
        var message_ptr = @intToPtr(T, @ptrToInt(&self.message_offset) - self.message_offset);
        return @ptrCast(T, message_ptr);
    }
};

const MyMsgBody = packed struct {
    const Self = @This();
    data: [3]u8,

    fn init(self: *Self) void {
        mem.set(u8, self.data[0..], 'Z');
    }
};

test "Message" {
    // Create a message
    const MyMsg = Message(MyMsgBody);
    var myMsg = MyMsg.init(123);

    assert(myMsg.header.message_offset == @ptrToInt(&myMsg.header.message_offset) - @ptrToInt(&myMsg)); 
    assert(myMsg.header.message_offset == 0);
    assert(myMsg.header.cmd == 123);
    assert(mem.eql(u8, myMsg.body.data[0..], "ZZZ"));

    // Modify message body data
    myMsg.body.data[0] = 'a';
    assert(mem.eql(u8, myMsg.body.data[0..], "aZZ"));

    // Create a queue of MessageHeader pointers
    const MyQueue = Queue(*MessageHeader);
    var q = MyQueue.init();

    // Create a node with a pointer to a message header
    var node_0 = MyQueue.Node {
        .data = &myMsg.header,
        .next = undefined,
        .prev = undefined,
    };

    // Add and remove it from the queue
    q.put(&node_0);
    var n = q.get() orelse { return error.QGetFailed; };

    // Get the Message and validate
    var pMsg = n.data.getMessagePtrAs(*MyMsg);
    assert(pMsg.header.cmd == 123);
    assert(mem.eql(u8, pMsg.body.data[0..], "aZZ"));
}
