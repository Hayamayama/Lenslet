//
//  LensletResult.swift
//  Lenslet
//
//  Created by Kris on 2026/6/23.
//

import Foundation


struct LensletResult: Codable {
    
    let status: String
    
    let ocr: String?
    
    let summary: String?
    
    let memory_path: String?
    
    let related: [RelatedMemory]?
} 


struct RelatedMemory: Codable {
    
    let id: String
    
    let path: String
    
    let distance: Double
    
    let text: String
}
