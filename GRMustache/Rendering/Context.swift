//
//  Context.swift
//  GRMustache
//
//  Created by Gwendal Roué on 25/10/2014.
//  Copyright (c) 2014 Gwendal Roué. All rights reserved.
//

import Foundation

class Context {
    enum Type {
        case Root
        case Value(value: MustacheValue, parent: Context)
        case InheritablePartial(inheritablePartialNode: InheritablePartialNode, parent: Context)
    }
    
    let type: Type
    
    var topMustacheValue: MustacheValue {
        switch type {
        case .Root:
            return .None
        case .Value(value: let value, parent: _):
            return value
        case .InheritablePartial(inheritablePartialNode: _, parent: let parent):
            return parent.topMustacheValue
        }
    }
    
    init(type: Type) {
        self.type = type
    }
    
    convenience init() {
        self.init(type: .Root)
    }
    
    func contextByAddingValue(value: MustacheValue) -> Context {
        switch value {
        case .None:
            return self
        default:
            return Context(type: .Value(value: value, parent: self))
        }
    }
    
    func contextByAddingInheritablePartialNode(inheritablePartialNode: InheritablePartialNode) -> Context {
        return Context(type: .InheritablePartial(inheritablePartialNode: inheritablePartialNode, parent: self))
    }
    
    func resolveTemplateASTNode(var node: TemplateASTNode) -> TemplateASTNode {
        var usedTemplateASTs: [TemplateAST] = []
        var context = self
        while true {
            switch context.type {
            case .Root:
                return node
            case .Value(value: _, parent: let parent):
                context = parent
            case .InheritablePartial(inheritablePartialNode: let inheritablePartialNode, parent: let parent):
                let templateAST = inheritablePartialNode.partialNode.templateAST
                var used = false
                for usedTemplateAST in usedTemplateASTs {
                    if usedTemplateAST === templateAST {
                        used = true
                        break
                    }
                }
                if !used {
                    let resolvedNode = inheritablePartialNode.resolveTemplateASTNode(node)
                    if resolvedNode !== node {
                        usedTemplateASTs.append(templateAST)
                    }
                    node = resolvedNode
                }
                context = parent
            }
        }
    }
    
    func valueForMustacheIdentifier(identifier: String) -> MustacheValue {
        switch type {
        case .Root:
            return .None
        case .Value(value: let value, parent: let parent):
            let innerValue = value.valueForMustacheIdentifier(identifier)
            switch innerValue {
            case .None:
                return parent.valueForMustacheIdentifier(identifier)
            default:
                return innerValue
            }
        case .InheritablePartial(inheritablePartialNode: _, parent: let parent):
            return parent.valueForMustacheIdentifier(identifier)
        }
    }
}