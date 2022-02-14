//
//  OpenAPI.swift
//  Giant Bomb API Reader
//
//  Created by Duncan on 1/19/22.
//

import Foundation

enum JSONType : String, Codable
{
  case boolean
  case integer
  case number
  case string
  case object
  case array
}

protocol OpenAPIObject : Codable {}

struct OpenAPI : OpenAPIObject
{
  var openapi : String
  var info : Info
  var servers : [Server]?
  var paths : [String : PathItem]
  var components : Components
  var tags : [Tag]? = nil
  var externalDocs : ExternalDocumentation? = nil
}

struct ExternalDocumentation : Codable
{
  var description : String? = nil
  var url : URL
}

struct Info : Codable
{
  var title : String
  var description : String? = nil
  var version : String
}

struct Server : Codable
{
  var url : URL
  var description : String? = nil
//  var variables : [String : ServerVariable]
}

struct PathItem : Codable
{
  var summary : String? = nil
  var description : String? = nil
  var get : Operation? = nil
}

struct Operation : Codable
{
  var deprecated : Bool? = nil
  var description : String? = nil
  var externalDocs : ExternalDocumentation? = nil
  var parameters : [Reference<Parameter>]? = nil
  var responses : Responses
  var security : [[String : [String]]]? = nil
  var summary : String? = nil
  var tags : [String]? = nil
}

struct Components : Codable
{
  var schemas : [ String : Reference<Schema> ]? = nil
  var parameters : [ String : Reference<Parameter> ]? = nil
  var responses : [ String : Reference<Response> ]? = nil
  var securitySchemes : [ String : SecurityScheme]? = nil
}

struct Responses
{
  
  var defaultResponse : Response? = nil
  var responses : [ String : Reference<Response> ]? = nil
}

extension Responses : Codable
{
  struct CodingKeys : CodingKey
  {
    static let DEFAULT_KEY = "default"
    static let defaultResponseCodingKey = CodingKeys(stringValue: DEFAULT_KEY)!
    
    var stringValue : String
    var intValue: Int? { nil }

    init?(stringValue: String) {
      self.stringValue = stringValue
    }
    
    init?(intValue: Int) {
      return nil
    }
  }
  
  init(from decoder: Decoder) throws
  {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.defaultResponse = try container.decode(Response.self, forKey: CodingKeys(stringValue: CodingKeys.DEFAULT_KEY)!)
    self.responses = [String:Reference<Response>]()
    for nextKey in container.allKeys.filter({ $0.stringValue != CodingKeys.DEFAULT_KEY })
    {
      self.responses![nextKey.stringValue] = try container.decode(Reference<Response>.self, forKey: nextKey)
    }
  }
  
  func encode(to encoder: Encoder) throws
  {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if self.defaultResponse != nil { try container.encode(defaultResponse, forKey: .defaultResponseCodingKey) }
    for (nextStatusCode, nextResponse) in self.responses ?? [:]
    {
      try container.encode(nextResponse, forKey: CodingKeys(stringValue: nextStatusCode)!)
    }
  }
}

struct Response : Codable
{
  var description : String
  var content : [String : MediaType]? = nil
}

struct MediaType : Codable
{
  var schema : Reference<Schema>? = nil
}

struct Schema : Codable
{
  enum CodingKeys : String, CodingKey
  {
    case enumValues = "enum"
    case type
    case description
    case example
    case minimum
    case maximum
    case pattern
    case nullable
    case properties
    case title
    case items
    case allOf
    case anyOf
    case oneOf
    case not
    case xml
  }
  enum ItemsValue : Codable
  {
    indirect case item(Reference<Schema>)
    
    func encode(to encoder: Encoder) throws
    {
      switch self
      {
      case let .item(reference):
        try reference.encode(to: encoder)
      }
    }
    
    init(from decoder: Decoder) throws {
      let item = try Reference<Schema>(from: decoder)
      self = .item(item)
    }
  }
  
//  TODO: `init()` for straight `struct` instead of `ItemsValue` `enum` for `items`
//  TODO: Find requirements from JSONSchema
  enum EnumType : Codable
  {
    case string(String)
    case integer(Int)
    case array([String])
    
    init(from decoder: Decoder) throws
    {
      if let container = try? decoder.singleValueContainer()
      {
        if let string = try? container.decode(String.self) { self = .string(string) }
        else
        {
          let integer = try container.decode(Int.self)
          self = .integer(integer)
        }
      }
      else
      {
        var container = try decoder.unkeyedContainer()
        var array = [String]()
        while !container.isAtEnd
        {
          array.append(try container.decode(String.self))
        }
        self = .array(array)
      }
    }
    
    func encode(to encoder: Encoder) throws
    {
      switch self
      {
      case let .string(string):
        var container = encoder.singleValueContainer()
        try container.encode(string)
      case let .integer(integer):
        var container = encoder.singleValueContainer()
        try container.encode(integer)
      case let .array(array):
        var container = encoder.unkeyedContainer()
        try container.encode(contentsOf: array)
      }
    }
  }
  
  var enumValues : [EnumType]? = nil
  var type : JSONType? = nil
  var description : String? = nil
//  TODO: Should be Any, find way to define any codable
  var example : String? = nil
  var minimum : Int? = nil
  var maximum : Int? = nil
  var pattern : String? = nil
  var nullable : Bool? = nil
  var properties : [String : Reference<Schema>]? = nil
  var title : String? = nil
  var items : ItemsValue? = nil
  var anyOf : [Reference<Schema>]? = nil
  var allOf : [Reference<Schema>]? = nil
  var oneOf : [Reference<Schema>]? = nil
  var not : Reference<Schema>? = nil
  var xml : XML? = nil
}

enum APILocation : String, Codable
{
  case query
  case header
  case path
  case cookie
}

struct SecurityScheme : Codable
{
  enum CodingKeys : String, CodingKey
  {
    case type
    case description
    case name
    case location = "in"
  }
  
  enum SecuritySchemeType : String, Codable
  {
    case apiKey
    case http
    case oauth2
    case openIdConnect
  }

  var type : SecuritySchemeType
  var description : String? = nil
  var name : String
  var location : APILocation
//  scheme  string  http  REQUIRED. The name of the HTTP Authorization scheme to be used in the Authorization header as defined in RFC7235. The values used SHOULD be registered in the IANA Authentication Scheme registry.
//  bearerFormat  string  http ("bearer")  A hint to the client to identify how the bearer token is formatted. Bearer tokens are usually generated by an authorization server, so this information is primarily for documentation purposes.
//  flows  OAuth Flows Object  oauth2  REQUIRED. An object containing configuration information for the flow types supported.
//  openIdConnectUrl  string  openIdConnect  REQUIRED. OpenId Connect URL to discover OAuth2 configuration values. This MUST be in the form of a URL.
}

enum Reference<T : Codable> : Codable
{
  case reference(String)
  indirect case actual(T)
  
  enum CodingKeys : String, CodingKey
  {
    case reference = "$ref"
  }
  
  init(from decoder: Decoder) throws
  {
    let container = try decoder.singleValueContainer()
    self = .reference(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    switch self
    {
    case let .reference(path):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(path, forKey: .reference)
    case let .actual(item):
      try item.encode(to: encoder)
    }
  }
}

struct Parameter : Codable
{
  enum ParameterStyle : String, Codable
  {
    case matrix
    case label
    case form
    case simple
    case spaceDelimited
    case pipeDelimited
    case deepObject
  }
  
  enum CodingKeys : String, CodingKey
  {
    case name
    case description
    case explode
    case location = "in"
    case schema
    case style
    case isRequired = "required"
    case allowReserved
  }
  
  var name : String
  var explode : Bool? = nil
  var description : String? = nil
  var location : APILocation
  var schema : Reference<Schema>? = nil
//  var schema : Schema? = nil
  var style : ParameterStyle? = nil
  var isRequired : Bool
  var allowReserved : Bool? = nil
}

struct SecurityRequirement
{
//  TODO: Use
}

struct XML : Codable
{
  var name : String? = nil
  var namespace : String? = nil
  var prefix : String? = nil
  var attribute : Bool? = nil
  var wrapped :  Bool? = nil
}

struct Tag : Codable
{
  var name : String
  var description : String? = nil
//  var externalDocs : String
}
