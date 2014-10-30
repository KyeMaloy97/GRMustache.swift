//
//  TemplateCompiler.swift
//  GRMustache
//
//  Created by Gwendal Roué on 25/10/2014.
//  Copyright (c) 2014 Gwendal Roué. All rights reserved.
//

import Foundation

class TemplateCompiler: TemplateTokenConsumer {
    private var state: CompilerState
    let templateRepository: TemplateRepository
    let templateID: TemplateID?
    
    init(contentType: ContentType, templateRepository: TemplateRepository, templateID: TemplateID?) {
        self.state = .Compiling(CompilationState(contentType: contentType))
        self.templateRepository = templateRepository
        self.templateID = templateID
    }
    
    func templateAST(error outError: NSErrorPointer) -> TemplateAST? {
        switch(state) {
        case .Compiling(let compilationState):
            switch compilationState.currentScope.type {
            case .Root:
                return TemplateAST(nodes: compilationState.currentScope.templateASTNodes, contentType: compilationState.contentType)
            case .Section(openingToken: let openingToken, expression: _):
                if outError != nil {
                    outError.memory = parseErrorAtToken(openingToken, description: "Unclosed Mustache tag")
                }
                return nil
            case .InvertedSection(openingToken: let openingToken, expression: _):
                if outError != nil {
                    outError.memory = parseErrorAtToken(openingToken, description: "Unclosed Mustache tag")
                }
                return nil
            case .InheritablePartial(openingToken: let openingToken, partialName: _):
                if outError != nil {
                    outError.memory = parseErrorAtToken(openingToken, description: "Unclosed Mustache tag")
                }
                return nil
            case .InheritableSection(openingToken: let openingToken, inheritableSectionName: _):
                if outError != nil {
                    outError.memory = parseErrorAtToken(openingToken, description: "Unclosed Mustache tag")
                }
                return nil
            }
        case .Error(let error):
            if outError != nil {
                outError.memory = error
            }
            return nil
        }
    }
    
    
    // MARK: - TemplateTokenConsumer
    
    func parser(parser: TemplateParser, didFailWithError error: NSError) {
        state = .Error(error)
    }
    
    func parser(parser: TemplateParser, shouldContinueAfterParsingToken token: TemplateToken) -> Bool {
        switch(state) {
        case .Error:
            return false
        case .Compiling(let compilationState):
            switch(token.type) {
            case .SetDelimiters:
                // noop
                return true
                
            case .Comment:
                // noop
                return true
                
            case .Pragma(content: let content):
                // noop
                return true
                
            case .Text(text: let text):
                compilationState.currentScope.appendNode(TextNode(text: text))
                return true
                
            case .EscapedVariable(content: let content):
                var error: NSError?
                var empty = false
                if let expression = ExpressionParser().parse(content, empty: &empty, error: &error) {
                    compilationState.currentScope.appendNode(VariableTag(expression: expression, contentType: compilationState.contentType, escapesHTML: true))
                    return true
                } else {
                    self.state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                    return false
                }
                
            case .UnescapedVariable(content: let content):
                var error: NSError?
                var empty = false
                if let expression = ExpressionParser().parse(content, empty: &empty, error: &error) {
                    compilationState.currentScope.appendNode(VariableTag(expression: expression, contentType: compilationState.contentType, escapesHTML: false))
                    return true
                } else {
                    self.state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                    return false
                }
                
            case .Section(content: let content):
                var error: NSError?
                var empty = false
                let expression = ExpressionParser().parse(content, empty: &empty, error: &error)
                
                if expression == nil && !empty {
                    self.state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                    return false
                }
                
                var extendedExpression: Expression?
                switch compilationState.currentScope.type {
                case .InvertedSection(openingToken: _, expression: let openingExpression):
                    if (expression == nil && empty) || (openingExpression == expression) {
                        extendedExpression = openingExpression
                    }
                default:
                    break
                }

                if let extendedExpression = extendedExpression {
                    let templateASTNodes = compilationState.currentScope.templateASTNodes
                    let templateAST = TemplateAST(nodes: templateASTNodes, contentType: compilationState.contentType)
                    let sectionTag = SectionTag(expression: extendedExpression, inverted: true, templateAST: templateAST)
                    compilationState.popCurrentScope()
                    compilationState.currentScope.appendNode(sectionTag)
                    compilationState.pushScope(Scope(type: .Section(openingToken: token, expression: extendedExpression)))
                    return true
                } else if let expression = expression {
                    compilationState.pushScope(Scope(type: .Section(openingToken: token, expression: expression)))
                    return true
                } else {
                    self.state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                    return false
                }
                
            case .InvertedSection(content: let content):
                var error: NSError?
                var empty = false
                let expression = ExpressionParser().parse(content, empty: &empty, error: &error)
                
                if expression == nil && !empty {
                    self.state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                    return false
                }
                
                var extendedExpression: Expression?
                switch compilationState.currentScope.type {
                case .Section(openingToken: _, expression: let openingExpression):
                    if (expression == nil && empty) || (openingExpression == expression) {
                        extendedExpression = openingExpression
                    }
                default:
                    break
                }
                
                if let extendedExpression = extendedExpression {
                    let templateASTNodes = compilationState.currentScope.templateASTNodes
                    let templateAST = TemplateAST(nodes: templateASTNodes, contentType: compilationState.contentType)
                    let sectionTag = SectionTag(expression: extendedExpression, inverted: false, templateAST: templateAST)
                    compilationState.popCurrentScope()
                    compilationState.currentScope.appendNode(sectionTag)
                    compilationState.pushScope(Scope(type: .InvertedSection(openingToken: token, expression: extendedExpression)))
                    return true
                } else if let expression = expression {
                    compilationState.pushScope(Scope(type: .InvertedSection(openingToken: token, expression: expression)))
                    return true
                } else {
                    self.state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                    return false
                }
                
            case .InheritableSection(content: let content):
                var error: NSError?
                var empty: Bool = false
                if let inheritableSectionName = inheritableSectionNameFromString(content, inToken: token, empty: &empty, error: &error) {
                    compilationState.pushScope(Scope(type: .InheritableSection(openingToken: token, inheritableSectionName: inheritableSectionName)))
                    return true
                } else {
                    self.state = .Error(error!)
                    return false
                }
                
            case .InheritablePartial(content: let content):
                var error: NSError?
                var empty: Bool = false
                if let partialName = partialNameFromString(content, inToken: token, empty: &empty, error: &error) {
                    compilationState.pushScope(Scope(type: .InheritablePartial(openingToken: token, partialName: partialName)))
                    return true
                } else {
                    self.state = .Error(error!)
                    return false
                }
                
            case .Close(content: let content):
                switch compilationState.currentScope.type {
                case .Root:
                    self.state = .Error(parseErrorAtToken(token, description: "Unmatched closing tag"))
                    return false
                    
                case .Section(openingToken: let openingToken, expression: let closedExpression):
                    var error: NSError?
                    var empty: Bool = false
                    let expression = ExpressionParser().parse(content, empty: &empty, error: &error)
                    switch (expression, empty) {
                    case (nil, true):
                        break
                    case (nil, false):
                        self.state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                        return false
                    default:
                        if expression != closedExpression {
                            self.state = .Error(parseErrorAtToken(token, description: "Unmatched closing tag"))
                            return false
                        }
                    }
                    
                    let templateASTNodes = compilationState.currentScope.templateASTNodes
                    let templateAST = TemplateAST(nodes: templateASTNodes, contentType: compilationState.contentType)
                    let sectionTag = SectionTag(expression: closedExpression, inverted: false, templateAST: templateAST)
                    compilationState.popCurrentScope()
                    compilationState.currentScope.appendNode(sectionTag)
                    return true
                    
                case .InvertedSection(openingToken: let openingToken, expression: let closedExpression):
                    var error: NSError?
                    var empty: Bool = false
                    let expression = ExpressionParser().parse(content, empty: &empty, error: &error)
                    switch (expression, empty) {
                    case (nil, true):
                        break
                    case (nil, false):
                        self.state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                        return false
                    default:
                        if expression != closedExpression {
                            self.state = .Error(parseErrorAtToken(token, description: "Unmatched closing tag"))
                            return false
                        }
                    }
                    
                    let templateASTNodes = compilationState.currentScope.templateASTNodes
                    let templateAST = TemplateAST(nodes: templateASTNodes, contentType: compilationState.contentType)
                    let sectionTag = SectionTag(expression: closedExpression, inverted: true, templateAST: templateAST)
                    compilationState.popCurrentScope()
                    compilationState.currentScope.appendNode(sectionTag)
                    return true
                    
                case .InheritablePartial(openingToken: let openingToken, partialName: let closedPartialName):
                    var error: NSError?
                    var empty: Bool = false
                    let partialName = partialNameFromString(content, inToken: token, empty: &empty, error: &error)
                    switch (partialName, empty) {
                    case (nil, true):
                        break
                    case (nil, false):
                        self.state = .Error(error!)
                        return false
                    default:
                        if (partialName != closedPartialName) {
                            self.state = .Error(parseErrorAtToken(token, description: "Unmatched closing tag"))
                            return false
                        }
                    }
                    
                    if let partialTemplateAST = templateRepository.templateASTNamed(closedPartialName, relativeToTemplateID:templateID, error: &error) {
                        let partialNode = PartialNode(partialName: closedPartialName, templateAST: partialTemplateAST)
                        let templateASTNodes = compilationState.currentScope.templateASTNodes
                        let templateAST = TemplateAST(nodes: templateASTNodes, contentType: compilationState.contentType)
                        let inheritablePartialNode = InheritablePartialNode(partialNode: partialNode, templateAST: templateAST)
                        compilationState.popCurrentScope()
                        compilationState.currentScope.appendNode(inheritablePartialNode)
                        return true
                    } else {
                        self.state = .Error(error!)
                        return false
                    }
                    
                case .InheritableSection(openingToken: let openingToken, inheritableSectionName: let closedInheritableSectionName):
                    var error: NSError?
                    var empty: Bool = false
                    let inheritableSectionName = inheritableSectionNameFromString(content, inToken: token, empty: &empty, error: &error)
                    switch (inheritableSectionName, empty) {
                    case (nil, true):
                        break
                    case (nil, false):
                        self.state = .Error(parseErrorAtToken(token, description: error!.localizedDescription))
                        return false
                    default:
                        if inheritableSectionName != closedInheritableSectionName {
                            self.state = .Error(parseErrorAtToken(token, description: "Unmatched closing tag"))
                            return false
                        }
                    }
                    
                    let templateASTNodes = compilationState.currentScope.templateASTNodes
                    let templateAST = TemplateAST(nodes: templateASTNodes, contentType: compilationState.contentType)
                    let inheritableSectionTag = InheritableSectionNode(name: closedInheritableSectionName, templateAST: templateAST)
                    compilationState.popCurrentScope()
                    compilationState.currentScope.appendNode(inheritableSectionTag)
                    return true
                }
                
            case .Partial(content: let content):
                var error: NSError?
                var empty: Bool = false
                if let partialName = partialNameFromString(content, inToken: token, empty: &empty, error: &error) {
                    if let partialTemplateAST = templateRepository.templateASTNamed(partialName, relativeToTemplateID: templateID, error: &error) {
                        let partialNode = PartialNode(partialName: partialName, templateAST: partialTemplateAST)
                        compilationState.currentScope.appendNode(partialNode)
                        return true
                    } else {
                        self.state = .Error(error!)
                        return false
                    }
                } else {
                    self.state = .Error(error!)
                    return false
                }
            }
        }
    }
    
    
    // MARK: - Private
    
    class CompilationState {
        var contentType: ContentType
        var currentScope: Scope {
            return scopeStack[scopeStack.endIndex - 1]
        }
        
        init(contentType: ContentType) {
            self.contentType = contentType
            self.scopeStack = [Scope(type: .Root)]
        }
        
        func popCurrentScope() {
            scopeStack.removeLast()
        }
        
        func pushScope(scope: Scope) {
            scopeStack.append(scope)
        }
        
        private var scopeStack: [Scope]
    }
    
    enum CompilerState {
        case Compiling(CompilationState)
        case Error(NSError)
    }
    
    class Scope {
        let type: Type
        var templateASTNodes: [TemplateASTNode]
        
        init(type:Type) {
            self.type = type
            self.templateASTNodes = []
        }
        
        func appendNode(node: TemplateASTNode) {
            templateASTNodes.append(node)
        }
        
        enum Type {
            case Root
            case Section(openingToken: TemplateToken, expression: Expression)
            case InvertedSection(openingToken: TemplateToken, expression: Expression)
            case InheritablePartial(openingToken: TemplateToken, partialName: String)
            case InheritableSection(openingToken: TemplateToken, inheritableSectionName: String)
        }
    }
    
    func inheritableSectionNameFromString(string: String, inToken token: TemplateToken, inout empty outEmpty: Bool, error outError: NSErrorPointer) -> String? {
        let whiteSpace = NSCharacterSet.whitespaceAndNewlineCharacterSet()
        let inheritableSectionName = string.stringByTrimmingCharactersInSet(whiteSpace)
        if countElements(inheritableSectionName) == 0 {
            if outError != nil {
                outError.memory = parseErrorAtToken(token, description: "Missing inheritable section name")
            }
            outEmpty = true
            return nil
        } else if (inheritableSectionName.rangeOfCharacterFromSet(whiteSpace) != nil) {
            if outError != nil {
                outError.memory = parseErrorAtToken(token, description: "Invalid inheritable section name")
            }
            outEmpty = false
            return nil
        }
        return inheritableSectionName
    }
    
    func partialNameFromString(string: String, inToken token: TemplateToken, inout empty outEmpty: Bool, error outError: NSErrorPointer) -> String? {
        let whiteSpace = NSCharacterSet.whitespaceAndNewlineCharacterSet()
        let partialName = string.stringByTrimmingCharactersInSet(whiteSpace)
        if countElements(partialName) == 0 {
            if outError != nil {
                outError.memory = parseErrorAtToken(token, description: "Missing template name")
            }
            outEmpty = true
            return nil
        } else if (partialName.rangeOfCharacterFromSet(whiteSpace) != nil) {
            if outError != nil {
                outError.memory = parseErrorAtToken(token, description: "Invalid template name")
            }
            outEmpty = false
            return nil
        }
        return partialName
    }
    
    func parseErrorAtToken(token: TemplateToken, description: String) -> NSError {
        let userInfo = [NSLocalizedDescriptionKey: "Parse error at line \(token.lineNumber): \(description)"]
        return NSError(domain: GRMustacheErrorDomain, code: GRMustacheErrorCodeParseError, userInfo: userInfo)
    }
}