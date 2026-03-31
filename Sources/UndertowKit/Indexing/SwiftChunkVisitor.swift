import Foundation
import SwiftParser
import SwiftSyntax

/// A `SyntaxVisitor` that walks a Swift AST and extracts `CodeChunk`s
/// at the function, type, extension, and property level.
public final class SwiftChunkVisitor: SyntaxVisitor {
    private let filePath: String
    private let locationConverter: SourceLocationConverter
    private var chunks: [CodeChunk] = []
    private var containingTypeStack: [String] = []

    /// Create a visitor for a given file.
    ///
    /// - Parameters:
    ///   - filePath: Relative path to the source file.
    ///   - tree: The parsed syntax tree.
    public init(filePath: String, tree: SourceFileSyntax) {
        self.filePath = filePath
        self.locationConverter = SourceLocationConverter(
            fileName: filePath,
            tree: tree
        )
        super.init(viewMode: .sourceAccurate)
    }

    /// Walk the tree and return all extracted chunks.
    public func extractChunks(from tree: SourceFileSyntax) -> [CodeChunk] {
        chunks = []
        walk(tree)
        return chunks
    }

    // MARK: - Type Declarations

    override public func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        addChunk(for: node, signature: "struct \(name)\(inheritanceText(node.inheritanceClause))", name: name)
        containingTypeStack.append(name)
        return .visitChildren
    }

    override public func visitPost(_ node: StructDeclSyntax) {
        containingTypeStack.removeLast()
    }

    override public func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        addChunk(for: node, signature: "class \(name)\(inheritanceText(node.inheritanceClause))", name: name)
        containingTypeStack.append(name)
        return .visitChildren
    }

    override public func visitPost(_ node: ClassDeclSyntax) {
        containingTypeStack.removeLast()
    }

    override public func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        addChunk(for: node, signature: "enum \(name)\(inheritanceText(node.inheritanceClause))", name: name)
        containingTypeStack.append(name)
        return .visitChildren
    }

    override public func visitPost(_ node: EnumDeclSyntax) {
        containingTypeStack.removeLast()
    }

    override public func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        addChunk(for: node, signature: "protocol \(name)\(inheritanceText(node.inheritanceClause))", name: name)
        containingTypeStack.append(name)
        return .visitChildren
    }

    override public func visitPost(_ node: ProtocolDeclSyntax) {
        containingTypeStack.removeLast()
    }

    override public func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        addChunk(for: node, signature: "actor \(name)\(inheritanceText(node.inheritanceClause))", name: name)
        containingTypeStack.append(name)
        return .visitChildren
    }

    override public func visitPost(_ node: ActorDeclSyntax) {
        containingTypeStack.removeLast()
    }

    // MARK: - Extensions

    override public func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.extendedType.trimmedDescription
        addChunk(for: node, signature: "extension \(name)\(inheritanceText(node.inheritanceClause))", name: name)
        containingTypeStack.append(name)
        return .visitChildren
    }

    override public func visitPost(_ node: ExtensionDeclSyntax) {
        containingTypeStack.removeLast()
    }

    // MARK: - Functions

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let sig = node.signature.trimmedDescription
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
        addChunk(for: node, signature: "func \(name)\(sig)", name: name)
        return .skipChildren
    }

    override public func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let sig = node.signature.trimmedDescription
        addChunk(for: node, signature: "init\(sig)", name: "init")
        return .skipChildren
    }

    // MARK: - Properties (only computed/observed)

    override public func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let binding = node.bindings.first else { return .skipChildren }
        let name = binding.pattern.trimmedDescription
        let typeAnnotation = binding.typeAnnotation?.trimmedDescription ?? ""
        let keyword = node.bindingSpecifier.trimmedDescription

        // Only chunk properties with accessor blocks (computed/observed) or that are significant
        if binding.accessorBlock != nil || containingTypeStack.isEmpty {
            addChunk(for: node, signature: "\(keyword) \(name)\(typeAnnotation)", name: name)
        }

        return .skipChildren
    }

    // MARK: - Helpers

    private func addChunk(for node: some SyntaxProtocol, signature: String, name: String) {
        let range = node.sourceRange(converter: locationConverter)
        let startLine = range.start.line
        let endLine = range.end.line

        // Extract leading doc comment if present
        let docComment = extractDocComment(from: node)

        // Source text — truncate very large declarations to avoid bloating index
        let source = node.trimmedDescription
        let truncatedSource = source.count > 2000 ? String(source.prefix(2000)) + "\n// ... truncated" : source

        let chunk = CodeChunk(
            filePath: filePath,
            lineRange: startLine...endLine,
            signature: signature,
            docComment: docComment,
            containingType: containingTypeStack.last,
            source: truncatedSource
        )

        chunks.append(chunk)
    }

    private func extractDocComment(from node: some SyntaxProtocol) -> String? {
        let trivia: Trivia? = {
            if let t = node.as(StructDeclSyntax.self)?.leadingTrivia { return t }
            if let t = node.as(ClassDeclSyntax.self)?.leadingTrivia { return t }
            if let t = node.as(EnumDeclSyntax.self)?.leadingTrivia { return t }
            if let t = node.as(FunctionDeclSyntax.self)?.leadingTrivia { return t }
            if let t = node.as(ProtocolDeclSyntax.self)?.leadingTrivia { return t }
            if let t = node.as(ExtensionDeclSyntax.self)?.leadingTrivia { return t }
            if let t = node.as(VariableDeclSyntax.self)?.leadingTrivia { return t }
            if let t = node.as(InitializerDeclSyntax.self)?.leadingTrivia { return t }
            if let t = node.as(ActorDeclSyntax.self)?.leadingTrivia { return t }
            return nil
        }()
        guard let decl = trivia else { return nil }

        let docLines = decl.compactMap { piece -> String? in
            switch piece {
            case .docLineComment(let text):
                return text
            case .docBlockComment(let text):
                return text
            default:
                return nil
            }
        }

        return docLines.isEmpty ? nil : docLines.joined(separator: "\n")
    }

    private func inheritanceText(_ clause: InheritanceClauseSyntax?) -> String {
        guard let clause else { return "" }
        let types = clause.inheritedTypes.map { $0.trimmedDescription.trimmingCharacters(in: [","]) }
        return ": \(types.joined(separator: ", "))"
    }
}
