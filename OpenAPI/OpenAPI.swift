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
  var parameters : [Parameter]? = nil
  var responses : Responses
  var security : [[String : [String]]]? = nil
  var summary : String? = nil
  var tags : [String]? = nil
}

struct Components : Codable
{
  var schemas : [ String : Schema ]? = nil
  var securitySchemes : [ String : SecurityScheme]? = nil
}

struct Responses
{
  
  var defaultResponse : Response? = nil
  var responses : [ String : Response ]? = nil
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
    self.responses = [String:Response]()
    for nextKey in container.allKeys.filter({ $0.stringValue != CodingKeys.DEFAULT_KEY })
    {
      self.responses![nextKey.stringValue] = try container.decode(Response.self, forKey: nextKey)
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
  enum CodingKeys : String, CodingKey
  {
    case ref = "$ref"
    case description
    case content
  }
  
  var ref : String? = nil
  var description : String
  var content : [String : MediaType]? = nil
}

struct MediaType : Codable
{
  var schema : Schema?
}

struct Schema : Codable
{
  enum CodingKeys : String, CodingKey
  {
    case ref = "$ref"
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
    case xml
  }
  enum ItemsValue : Codable
  {
    indirect case item(Schema)
    
    func encode(to encoder: Encoder) throws
    {
      switch self
      {
      case let .item(schema):
        try schema.encode(to: encoder)
      }
    }
    
    init(from decoder: Decoder) throws {
      let item = try Schema(from: decoder)
      self = .item(item)
    }
  }
  
//  TODO: `init()` for straight `struct` instead of `ItemsValue` `enum` for `items`
//  TODO: Find requirements from JSONSchema
//  TODO: Properly do refs ("ref" property on objects? Protocols)
  var enumValues : [String]? = nil
  var ref : String? = nil
  var type : JSONType? = nil
  var description : String? = nil
//  TODO: Should be Any, find way to define any codable
  var example : String? = nil
  var minimum : Int? = nil
  var maximum : Int? = nil
  var pattern : String? = nil
  var nullable : Bool? = nil
  var properties : [String : Schema]? = nil
  var title : String? = nil
  var items : ItemsValue? = nil
  var anyOf : [Schema]? = nil
  var allOf : [Schema]? = nil
  var oneOf : [Schema]? = nil
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
  var schema : Schema? = nil
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
