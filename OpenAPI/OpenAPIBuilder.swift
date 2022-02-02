//
//  OpenAPIBuilder.swift
//  Giant Bomb API Reader
//
//  Created by Duncan on 2/1/22.
//

import Foundation

@resultBuilder
enum OpenAPIBuilder
{
  static func buildBlock(_ components: OpenAPIObject...) -> [OpenAPIObject] {
    components
  }
}
