import Foundation
import Testing
@testable import XdeskAgent

@Suite struct SchemaValidationTests {
    private func schema(_ tool: String) -> JsonValue { ToolSchemas.all.first { $0.name == tool }?.inputSchema ?? .null }

    @Test func acceptsValidAndRejectsInvalidArguments() {
        let pointer = schema("xdesk_pointer")
        #expect(SchemaValidator.validate(["action": "click", "x": 10, "y": .double(20.5)], against: pointer) == nil)
        #expect(SchemaValidator.validate([:], against: pointer)?.contains("action") == true)
        #expect(SchemaValidator.validate(["action": "teleport"], against: pointer)?.contains("click") == true)
        #expect(SchemaValidator.validate(["action": "click", "x": "10"], against: pointer)?.contains("number") == true)
        #expect(SchemaValidator.validate(["action": "click", "evil": 1], against: pointer)?.contains("evil") == true)
    }

    @Test func stepsAreLimited() {
        let step: JsonValue = ["tool": "xdesk_scroll", "arguments": ["dy": 1]]
        let steps = Array(repeating: step, count: 21)
        #expect(SchemaValidator.validate(["steps": .array(steps)], against: schema("xdesk_run_steps"))?.contains("20") == true)
        #expect(SchemaValidator.validate(["steps": .array(Array(steps.prefix(20)))], against: schema("xdesk_run_steps")) == nil)
    }

    @Test func registryReturnsToolErrorBeforeCallingHandler() async {
        struct Boom: ToolHandler { func call(arguments: JsonValue) async -> ToolResult { .ok("không được tới đây") } }
        let registry = ToolRegistry(handlers: ["xdesk_type_text": Boom()])
        let result = await registry.call(name: "xdesk_type_text", arguments: [:])
        #expect(result?.isError == true)
        #expect(result?.text.contains("text") == true)
        #expect(await registry.call(name: "xdesk_type_text", arguments: ["text": "xin chào"])?.text == "không được tới đây")
    }
}

@Suite struct GeometryTests {
    @Test func screenshotLongEdgeIsCapped() {
        let big = AgentDisplayGeometry(width: 3840, height: 2160).screenshotSize
        #expect(max(big.width, big.height) == 1568)
        #expect(big.height == 882)
        let small = AgentDisplayGeometry(width: 1280, height: 800).screenshotSize
        #expect(small.width == 1280 && small.height == 800)
    }

    @Test func containsIsHalfOpenAndRejectsNonFinite() {
        let geometry = AgentDisplayGeometry(width: 100, height: 50)
        #expect(geometry.contains(x: 0, y: 0) && geometry.contains(x: 99.9, y: 49.9))
        #expect(!geometry.contains(x: 100, y: 10) && !geometry.contains(x: -1, y: 10) && !geometry.contains(x: .nan, y: 1))
    }

    @Test func refTableIsReplacedWholesale() {
        let table = UiRefTable()
        table.replace(with: [UiElement(ref: "e1", role: "AXButton", label: "Lưu", x: 10, y: 20, width: 40, height: 20)])
        #expect(table.element("e1")?.center.x == 30)
        table.replace(with: [UiElement(ref: "e2", role: "AXTextArea", label: "", x: 0, y: 0, width: 5, height: 5)])
        #expect(table.element("e1") == nil && table.count == 1)
        #expect(table.element("e2")?.line == "e2 AXTextArea [0,0,5,5]")
    }
}

@Suite struct KeyChordTests {
    @Test func parsesModifiersAndKey() throws {
        let chord = try KeyChord.parse(["Cmd", "shift", "s"])
        #expect(chord.keyCode == 1)
        #expect(chord.modifiers == [.command, .shift])
        #expect(try KeyChord.parse(["return"]).keyCode == 36)
        #expect(try KeyChord.parse(["f5"]).keyCode == 96)
    }

    @Test func rejectsBadChords() {
        #expect(throws: KeyChord.ParseError.empty) { _ = try KeyChord.parse([]) }
        #expect(throws: KeyChord.ParseError.noKey) { _ = try KeyChord.parse(["cmd"]) }
        #expect(throws: KeyChord.ParseError.manyKeys) { _ = try KeyChord.parse(["a", "b"]) }
        #expect(throws: KeyChord.ParseError.unknown("blah")) { _ = try KeyChord.parse(["blah"]) }
    }
}

@Suite struct ClipboardPolicyTests {
    @Test func concealedAndTransientTypesAreRefused() {
        #expect(ClipboardPolicy.refusalReason(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]) != nil)
        #expect(ClipboardPolicy.refusalReason(types: ["org.nspasteboard.TransientType"]) != nil)
        #expect(ClipboardPolicy.refusalReason(types: ["public.utf8-plain-text"]) == nil)
    }
}

@Suite struct RunStepsToolTests {
    private actor Recorder { var calls: [String] = []; func add(_ name: String) { calls.append(name) } }
    private struct Step: ToolHandler {
        let name: String, recorder: Recorder, fail: Bool
        func call(arguments: JsonValue) async -> ToolResult { await recorder.add(name); return fail ? .error("hỏng") : .ok("xong") }
    }

    private func steps(_ names: [String]) -> JsonValue {
        .array(names.map { ["tool": .string($0), "arguments": $0 == "xdesk_scroll" ? ["dy": 3] : ["text": "a"]] })
    }

    @Test func stopsAtFirstError() async {
        let recorder = Recorder()
        let tool = RunStepsTool(handlers: [
            "xdesk_scroll": Step(name: "scroll", recorder: recorder, fail: false),
            "xdesk_type_text": Step(name: "type", recorder: recorder, fail: true),
        ])
        let result = await tool.call(arguments: ["steps": steps(["xdesk_scroll", "xdesk_type_text", "xdesk_scroll"])])
        #expect(result.isError)
        #expect(await recorder.calls == ["scroll", "type"])
        #expect(result.audit == "steps=2/3")
    }

    @Test func rejectsTooManyAndForeignTools() async {
        let tool = RunStepsTool(handlers: [:])
        #expect(await tool.call(arguments: ["steps": steps(Array(repeating: "xdesk_scroll", count: 21))]).text.contains("20"))
        #expect(await tool.call(arguments: ["steps": steps(["xdesk_launch"])]).isError)
    }

    @Test func validatesEachStepAgainstItsSchema() async {
        let recorder = Recorder()
        let tool = RunStepsTool(handlers: ["xdesk_type_text": Step(name: "type", recorder: recorder, fail: false)])
        let bad: JsonValue = ["steps": [["tool": "xdesk_type_text", "arguments": ["text": 5]]]]
        #expect(await tool.call(arguments: bad).isError)
        #expect(await recorder.calls.isEmpty)
    }
}
