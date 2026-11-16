import Foundation
import AppKit
import WacomdShared

// Record output; no input events are sent to the desktop during these tests.
final class EventInjector {
    var events: [String] = []
    var dragging = false
    func setTouchDragging(_ value: Bool) -> Bool {
        if value != dragging { events.append(value ? "down" : "up"); dragging = value }
        return true
    }
    func moveCursorBy(dx: Double, dy: Double) { events.append(dragging ? "drag" : "move") }
    func tapClick(button: CGMouseButton = .left) { events.append(button == .right ? "right-tap" : "tap") }
    func middleClick() { events.append("middle") }
    func scroll(dx: Double, dy: Double) { events.append("scroll") }
    func postKeyCombo(keyCode: CGKeyCode, modifiers: CGEventFlags) { events.append("key:\(keyCode):\(modifiers.rawValue)") }
}
var settings = WacomdConfig()
settings.threeFingerDrag = true
settings.fourFingerAction = .desktops
let sink = EventInjector(), gate = PenTouchGate()
let tracker = TouchTracker(injector: sink, penTouchGate: gate, configuration: { settings })
gate.cancelTouchDrag = { tracker.cancelGesture() }
func frame(_ count: Int, _ x: Int = 100, _ y: Int = 100) {
    tracker.handleFrame(contacts: (0..<count).map { TouchContact(slotID: $0+2, inContact: true, x:x+$0*40, y:y) })
}
frame(3); precondition(sink.events.isEmpty) // landing three fingers must not click
frame(3,150); precondition(sink.events == ["down"])
frame(3,200); precondition(sink.events == ["down","drag"])
frame(2); frame(1); frame(0)
precondition(sink.events == ["down","drag","up"]) // staggered release cannot click or scroll
sink.events=[]
frame(4); frame(4,800); frame(4,1200); frame(3); frame(2); frame(1); frame(0)
precondition(sink.events == ["key:124:262144"])
sink.events=[]
settings.fourFingerAction = .applications
frame(4); frame(4,800); frame(0)
precondition(sink.events == ["key:48:1048576"])
sink.events=[]
frame(4,100,800); frame(4,100,100); frame(0)
precondition(sink.events == ["key:126:262144"])
sink.events=[]
settings.fourFingerAction = .off
frame(4); frame(4,800); frame(3); frame(0)
precondition(sink.events.isEmpty)
frame(3); frame(3,150); precondition(sink.dragging)
settings.touchEnabled=false
frame(3,200); precondition(!sink.dragging && sink.events.last == "up")
settings.touchEnabled=true; frame(0)
frame(3); frame(3,150); precondition(sink.dragging)
gate.observe(reportID: 2, bytes: [2,0xa0,0,0,0,0,0,0,0,0], now: ProcessInfo.processInfo.systemUptime)
precondition(!sink.dragging && sink.events.last == "up")
print("Touch integration passed: drag events, landing guard, staggered lift, four-finger routing, one action per swipe, disabled gestures, palm takeover")

var packetParser = IntuosProTouchParser()
func packet(_ messages: [[UInt8]], statusFlags: UInt8 = 0) -> [TouchContact]? {
    var data: [UInt8] = [2, UInt8(messages.count) | statusFlags] + messages.flatMap { $0 }
    data += Array(repeating: 0, count: max(0, 64-data.count))
    return data.withUnsafeMutableBufferPointer { packetParser.decode(data: $0.baseAddress!, length: $0.count) }
}
// Actual PTH-451 packets from the previous USB capture: low bits live together in byte 4.
let recorded: [UInt8] = [2,0xc0,0xde,0x9a,0xa6,3,3,0]
precondition(packet([recorded]) == [TouchContact(slotID:2,inContact:true,x:3562,y:2470)])
precondition(packet([[2,0x88,0xde,0x9a,0xa6,3,4,0]]) == [TouchContact(slotID:2,inContact:true,x:3562,y:2470)]) // flag changes cannot move a stationary finger
precondition(packet([[0x81,3,0,0,0,0,0,0]]) == nil) // status between motion packets
precondition(packet([[3,0xc0,0xff,0xf8,0x79,2,3,0]])?.count == 2) // omitted slot 2 is still down
precondition(packet([[4,0x80,30,40,0x12,0,0,0]], statusFlags:0x80)?.count == 3) // flags are not finger count
precondition(packet([[5,0x80,31,41,0x34,0,0,0]])?.count == 4) // zero width is not release
precondition(packet([[2,0,0xde,0x9a,0xa6,3,3,0]])?.count == 3) // release flag wins over nonzero width
precondition(packet([[3,0,0,0,0,0,0,0],[4,0,0,0,0,0,0,0],[5,0,0,0,0,0,0,0]]) == [])
var short: [UInt8] = [2,2,2,0x80]
precondition(short.withUnsafeMutableBufferPointer { packetParser.decode(data:$0.baseAddress!,length:$0.count) } == nil)

// Exercise the entire packet-to-gesture path; status and partial updates cannot cancel the drag.
settings.touchEnabled=true; settings.palmRejection=false; settings.threeFingerDrag=true
let rawSink=EventInjector()
let rawTracker=TouchTracker(injector:rawSink,penTouchGate:PenTouchGate(),configuration:{settings})
func msg(_ id: UInt8, _ x: Int, _ y: Int, down: Bool = true) -> [UInt8] {
    [id,down ? 0x80 : 0,UInt8(x>>4),UInt8(y>>4),UInt8((x&15)<<4 | (y&15)),3,3,0]
}
func feed(_ messages: [[UInt8]]) { if let contacts=packet(messages) { rawTracker.handleFrame(contacts:contacts) } }
feed([msg(2,100,100),msg(3,200,100),msg(4,300,100)])
feed([[0x81,3,0,0,0,0,0,0]])
feed([msg(2,200,100),msg(3,300,100),msg(4,400,100)])
precondition(rawSink.events == ["down"])
feed([[0x81,3,0,0,0,0,0,0]])
feed([msg(2,250,100)])
precondition(rawSink.events.last == "drag" && rawSink.dragging)
feed([msg(2,250,100,down:false)])
precondition(rawSink.events.last == "up" && !rawSink.dragging)
feed([msg(3,300,100,down:false),msg(4,400,100,down:false)])
precondition(!rawSink.events.contains("tap") && !rawSink.events.contains("middle"))
settings.fourFingerAction = .desktops
rawSink.events=[]
feed([msg(2,100,100),msg(3,200,100),msg(4,300,100),msg(5,400,100)])
feed([[0x81,3,0,0,0,0,0,0]])
feed([msg(2,800,100),msg(3,900,100),msg(4,1000,100),msg(5,1100,100)])
precondition(rawSink.events == ["key:124:262144"])
feed([msg(2,0,0,down:false),msg(3,0,0,down:false),msg(4,0,0,down:false),msg(5,0,0,down:false)])
precondition(rawSink.events == ["key:124:262144"])
print("Raw touch regression passed: captured coordinates, status interleaving, partial reports, true release bits, malformed packets, packet-to-drag path")

// Real hands land fingers sequentially: a fourth finger must promote an active drag.
settings = WacomdConfig(); settings.threeFingerDrag=true; settings.fourFingerAction = .desktops
let sequenceSink=EventInjector(), sequenceGate=PenTouchGate(releaseDelay:0)
let sequenceTracker=TouchTracker(injector:sequenceSink,penTouchGate:sequenceGate,configuration:{settings})
func seq(_ n: Int, _ x: Int = 100, _ y: Int = 800) {
    sequenceTracker.handleFrame(contacts:(0..<n).map { TouchContact(slotID:$0+2,inContact:true,x:x+$0*40,y:y) })
}
seq(1); seq(2); seq(3); seq(3,150); seq(4,150); seq(4,150,100)
precondition(sequenceSink.events == ["down","up","key:126:262144"])
seq(3);seq(2);seq(1);seq(0)
seq(3);seq(3,200);seq(3,250);seq(2);seq(1);seq(0)
precondition(Array(sequenceSink.events.suffix(3)) == ["down","drag","up"])
sequenceSink.events=[]
seq(1);Thread.sleep(forTimeInterval:0.15);seq(0)
precondition(sequenceSink.events == ["tap"])
sequenceSink.events=[]
seq(1);seq(2);seq(1);seq(0)
precondition(sequenceSink.events == ["right-tap"])
sequenceSink.events=[]
seq(2);seq(2,400);seq(1,400);seq(0)
precondition(!sequenceSink.events.contains("tap") && !sequenceSink.events.contains("right-tap"))
sequenceSink.events=[]
settings.twoFingerTapRightClick=false
seq(2);seq(1);seq(0);precondition(sequenceSink.events.isEmpty)
settings.twoFingerTapRightClick=true
sequenceGate.observe(reportID:2,bytes:[2,0xa0,0,0,0,0,0,0,0,0],now:0)
seq(4);sequenceGate.penRemoved(now:0);seq(0)
seq(3);seq(3,200);precondition(sequenceSink.dragging)
seq(0);precondition(!sequenceSink.dragging)
print("Repeated gestures passed: staggered four-finger promotion, next drag, relaxed left tap, staggered right tap, no click after scroll, palm recovery")
