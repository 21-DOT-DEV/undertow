import Testing
@testable import UndertowKit

@Suite("CodeChunker")
struct CodeChunkerTests {
    let chunker = CodeChunker()

    // MARK: - Swift Chunking

    @Suite("Swift files")
    struct SwiftChunking {
        let chunker = CodeChunker()

        @Test("extracts struct declaration")
        func structDeclaration() {
            let source = """
            struct Foo {
                var name: String
            }
            """
            let chunks = chunker.chunk(filePath: "Foo.swift", source: source)

            #expect(chunks.contains { $0.signature.contains("struct Foo") })
        }

        @Test("extracts class with inheritance")
        func classWithInheritance() {
            let source = """
            class MyView: UIView {
                func setup() {}
            }
            """
            let chunks = chunker.chunk(filePath: "MyView.swift", source: source)

            let classChunk = chunks.first { $0.signature.contains("class MyView") }
            #expect(classChunk != nil)
            #expect(classChunk?.signature.contains("UIView") == true)
        }

        @Test("extracts functions with correct line ranges")
        func functionLineRanges() {
            let source = """
            func hello() {
                print("hello")
            }

            func world() {
                print("world")
            }
            """
            let chunks = chunker.chunk(filePath: "test.swift", source: source)
            let funcChunks = chunks.filter { $0.signature.hasPrefix("func") }

            #expect(funcChunks.count == 2)

            let hello = funcChunks.first { $0.signature.contains("hello") }
            #expect(hello != nil)
            #expect(hello?.lineRange.lowerBound == 1)
            #expect(hello?.lineRange.upperBound == 3)

            let world = funcChunks.first { $0.signature.contains("world") }
            #expect(world != nil)
            #expect(world?.lineRange.lowerBound == 5)
        }

        @Test("extracts enum with cases")
        func enumDeclaration() {
            let source = """
            enum Direction {
                case north
                case south
                case east
                case west
            }
            """
            let chunks = chunker.chunk(filePath: "Direction.swift", source: source)

            #expect(chunks.contains { $0.signature.contains("enum Direction") })
        }

        @Test("extracts protocol")
        func protocolDeclaration() {
            let source = """
            protocol Drawable: Sendable {
                func draw()
            }
            """
            let chunks = chunker.chunk(filePath: "Drawable.swift", source: source)

            let proto = chunks.first { $0.signature.contains("protocol Drawable") }
            #expect(proto != nil)
            #expect(proto?.signature.contains("Sendable") == true)
        }

        @Test("extracts actor")
        func actorDeclaration() {
            let source = """
            actor Counter {
                var count = 0
                func increment() { count += 1 }
            }
            """
            let chunks = chunker.chunk(filePath: "Counter.swift", source: source)

            #expect(chunks.contains { $0.signature.contains("actor Counter") })
        }

        @Test("extracts extension")
        func extensionDeclaration() {
            let source = """
            extension String {
                func reversed() -> String {
                    String(self.reversed())
                }
            }
            """
            let chunks = chunker.chunk(filePath: "ext.swift", source: source)

            #expect(chunks.contains { $0.signature.contains("extension String") })
        }

        @Test("records containing type for methods")
        func containingType() {
            let source = """
            struct Foo {
                func bar() {}
            }
            """
            let chunks = chunker.chunk(filePath: "Foo.swift", source: source)
            let methodChunk = chunks.first { $0.signature.contains("func bar") }

            #expect(methodChunk?.containingType == "Foo")
        }

        @Test("extracts doc comments")
        func docComments() {
            let source = """
            /// This is a doc comment.
            /// It has multiple lines.
            func documented() {}
            """
            let chunks = chunker.chunk(filePath: "doc.swift", source: source)
            let funcChunk = chunks.first { $0.signature.contains("func documented") }

            #expect(funcChunk?.docComment != nil)
            #expect(funcChunk?.docComment?.contains("doc comment") == true)
        }

        @Test("extracts initializer")
        func initDeclaration() {
            let source = """
            struct Point {
                var x: Int
                var y: Int
                init(x: Int, y: Int) {
                    self.x = x
                    self.y = y
                }
            }
            """
            let chunks = chunker.chunk(filePath: "Point.swift", source: source)

            #expect(chunks.contains { $0.signature.contains("init") })
        }

        @Test("truncates large source bodies")
        func largeSourceTruncation() {
            let longBody = String(repeating: "    let x = 1\n", count: 300)
            let source = "func big() {\n\(longBody)}"
            let chunks = chunker.chunk(filePath: "big.swift", source: source)
            let funcChunk = chunks.first { $0.signature.contains("func big") }

            #expect(funcChunk != nil)
            #expect(funcChunk!.source.count <= 2020) // 2000 + "// ... truncated"
        }

        @Test("handles empty file")
        func emptyFile() {
            let chunks = chunker.chunk(filePath: "empty.swift", source: "")
            #expect(chunks.isEmpty)
        }

        @Test("handles file with only imports")
        func importsOnly() {
            let source = """
            import Foundation
            import SwiftUI
            """
            let chunks = chunker.chunk(filePath: "imports.swift", source: source)
            // Imports are not chunked as declarations
            #expect(chunks.isEmpty)
        }
    }

    // MARK: - Line-Based Chunking

    @Suite("Non-Swift files")
    struct LineBasedChunking {
        let chunker = CodeChunker(windowSize: 5, overlapSize: 2)

        @Test("chunks by lines with overlap")
        func linesWithOverlap() {
            let lines = (1...12).map { "line \($0)" }
            let source = lines.joined(separator: "\n")
            let chunks = chunker.chunk(filePath: "test.json", source: source)

            #expect(!chunks.isEmpty)
            // With windowSize=5 and overlapSize=2, step=3
            // Windows: 1-5, 4-8, 7-11, 10-12
            #expect(chunks.count == 4)
        }

        @Test("single window for small file")
        func smallFile() {
            let source = "a\nb\nc"
            let chunks = chunker.chunk(filePath: "small.md", source: source)

            #expect(chunks.count == 1)
            #expect(chunks[0].lineRange == 1...3)
        }

        @Test("handles empty non-Swift file")
        func emptyNonSwift() {
            let chunks = chunker.chunk(filePath: "empty.json", source: "")
            #expect(chunks.isEmpty)
        }

        @Test("file path preserved")
        func filePathPreserved() {
            let chunks = chunker.chunk(filePath: "config/settings.yaml", source: "key: value")
            #expect(chunks.first?.filePath == "config/settings.yaml")
        }
    }

    // MARK: - File Extension Routing

    @Suite("Extension routing")
    struct ExtensionRouting {
        let chunker = CodeChunker()

        @Test("routes .swift to syntax parser")
        func swiftRouting() {
            let source = "struct A {}"
            let chunks = chunker.chunk(filePath: "A.swift", source: source)
            // Swift chunker produces semantic chunks
            #expect(chunks.first?.signature.contains("struct A") == true)
        }

        @Test("routes .json to line-based chunker")
        func jsonRouting() {
            let source = "{\"key\": \"value\"}"
            let chunks = chunker.chunk(filePath: "data.json", source: source)
            // Line-based chunker produces window chunks
            #expect(chunks.first?.lineRange == 1...1)
        }
    }
}
