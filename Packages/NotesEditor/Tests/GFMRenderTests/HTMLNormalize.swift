//
//  HTMLNormalize.swift
//  GFMRenderTests
//
//  Compares rendered HTML to the spec's expected HTML. The GFM corpus'
//  expected output is produced by cmark-gfm, which GFMRenderer also uses, so
//  the outputs match exactly — comparison is byte-for-byte.
//

import Foundation

enum HTMLNormalize {
    static func equal(_ a: String, _ b: String) -> Bool {
        a == b
    }
}
