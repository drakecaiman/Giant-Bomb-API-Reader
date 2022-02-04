//
//  main.swift
//  Giant Bomb API Reader
//
//  Created by Duncan on 1/17/22.
//

import Foundation
import WebKit

let fillToken = "##ENTER##"
let typeToken = "##WRONG TYPE##"
let docURLString = "https://www.giantbomb.com/api/documentation/"
let urlDataDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
let pathParameterRegularExpression = try? NSRegularExpression(pattern: "(?<=\\{).*?(?=\\})", options: [])
let descriptionTableRowXPath = "tbody/tr/td[strong[starts-with(text(),'Description:')]]/p"
let excludeResponseSchemaArray = ["/video/current-live",
                                  "/video/get-saved-time",
                                  "/video/get-all-saved-times",
                                  "/video/save-time"]
let sortQueryRegEx = #"^\w+:((asc)|(desc))$"#
//!!!: named and numbered regex subroutines not working in apps
let filterQueryRegEx = #"^((\w+:((\w+)|(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\|\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}))),?)+$"#
let parameterSchemas :[ String : Reference<Schema> ] =
[
  "Format" : .actual(Schema(enumValues: [.string("xml"), .string("json"), .string("jsonp")], type: .string, description: fillToken)),
  "FieldList" : .actual(Schema(type: .array, description: fillToken, items: .item(.actual(Schema(type:.string, description: fillToken))))),
  "Limit": .actual(Schema(type: .integer, description: fillToken, minimum: 0, maximum: 100)),
  "Offset": .actual(Schema(type: .integer, description: fillToken)),
  "Sort": .actual(Schema(type: .string, description: fillToken, pattern: sortQueryRegEx)),
  "Filter": .actual(Schema(type: .string, description: fillToken, pattern: filterQueryRegEx)),
  "SubscriberOnly": .actual(Schema(type: .boolean, description: fillToken)),
  "Page": .actual(Schema(type: .integer, description: fillToken)),
  "VideoId": .actual(Schema(type: .integer, description: fillToken)),
  "TimeToSave": .actual(Schema(type: .integer, description: fillToken)),
  "GameId": .actual(Schema(type: .integer, description: fillToken)),
  "PlatformId": .actual(Schema(type: .integer, description: fillToken)),
  "Query": .actual(Schema(type: .string, description: fillToken)),
  "ResourceType": .actual(Schema(enumValues:
                                  [
                                    .string("game"),
                                    .string("franchise"),
                                    .string("character"),
                                    .string("concept"),
                                    .string("object"),
                                    .string("location"),
                                    .string("person"),
                                    .string("company"),
                                    .string("video")
                                  ],
                                type: .string,
                                description: fillToken))
]
let singular = [
  "/accessories" : "/accessory/{guid}",
  "/characters" : "/character/{guid}",
  "/chats" : "/chat/{guid}",
  "/companies" : "/company/{guid}",
  "/concepts" : "/concept/{guid}",
  "/dlcs" : "/dlc/{guid}",
  "/franchises" : "/franchise/{guid}",
  "/games" : "/game/{guid}",
  "/game_ratings" : "/game_rating/{guid}",
  "/genres" : "/genre/{guid}",
  "/locations" : "/location/{guid}",
  "/objects" : "/object/{guid}",
  "/people" : "/person/{guid}",
  "/platforms" : "/platform/{guid}",
  "/promos" : "/promo/{guid}",
  "/rating_boards" : "/rating_board/{guid}",
  "/regions" : "/region/{guid}",
  "/releases" : "/release/{guid}",
  "/reviews" : "/review/{guid}",
  "/themes" : "/theme/{guid}",
  "/user_reviews" : "/user_review/{guid}",
  "/videos" : "/video/{guid}",
  "/video_types" : "/video_type/{id}",
  "/video_categories/{id}" : "/video_category/{id}",
  "/video_shows" : "/video_show/{guid}"
]
let searchSchemaList = ["Game",
                  "Franchise",
                  "Character",
                  "Concept",
                  "Object",
                  "Location",
                  "Person",
                  "Company",
                  "Video"]

let invalidAPIKeyResponseSchema = Schema(allOf: [Reference<Schema>.reference("#/components/schemas/Response"),
                                                 .actual(Schema(properties:
                                                                  [
                                                                    "error": .actual(Schema(enumValues: [.string("Invalid API Key")])),
                                                                    "status_code": .actual(Schema(enumValues: [.integer(100)])),
                                                                    "results": .actual(Schema(enumValues: [.array([])])),
//                                                                    "error": .actual(Schema(enumValues: ["Invalid API Key"]))
                                                                  ]
                                                               ))])
let invalidAPIKeyResponse = Response(description: fillToken, content: ["application/json": MediaType(schema: .actual(invalidAPIKeyResponseSchema)),
                                                                       "application/xml": MediaType(schema: .actual(invalidAPIKeyResponseSchema)),
                                                                       "application/jsonp": MediaType(schema: .actual(invalidAPIKeyResponseSchema))])
let responses : [String : Reference<Response>]  = ["InvalidAPIKey": .actual(invalidAPIKeyResponse)]

guard let apiURL = URL(string: "https://www.giantbomb.com/api/documentation/") else
{
  print("Failed to get URL")
  exit(EXIT_FAILURE)
}
do
{
  let documentationXMLDocument = try XMLDocument(contentsOf: apiURL, options: [.documentTidyHTML])
  
  // Grab the "Response" format to create the encapsulation structure
  guard let responseNode = try? documentationXMLDocument.nodes(forXPath: "//*[@id='default-content']/div/table[1]").first
  else
  {
    print("Unable to find response definition table.")
    exit(EXIT_FAILURE)
  }
  
  let securityScheme = SecurityScheme(type: .apiKey, name: "api_key", location: .query)
  guard let responseTableRowNodes = try? responseNode.nodes(forXPath: "tbody/tr") else { exit(EXIT_FAILURE) }
  var responseSchema = getSchema(fromTableRowNodes: responseTableRowNodes)
  responseSchema.xml = XML(name: "response", wrapped: true)
  //Populate types for response schema
  for nextProperty in ["error", "results"]
  {
    if case var .actual(schema) = responseSchema.properties?[nextProperty]
    {
      schema.example = nil
      responseSchema.properties?[nextProperty] = .actual(schema)
    }
  }
  for nextProperty in ["limit", "number_of_page_results", "number_of_total_results", "offset", "status_code"]
  {
    if case var .actual(schema) = responseSchema.properties?[nextProperty]
    {
      schema.type = .integer
      schema.example = nil
      responseSchema.properties?[nextProperty] = .actual(schema)
    }
  }
  let responseSchemaDictionary = ["Response" : Reference.actual(responseSchema)]
  var components = Components(schemas: parameterSchemas.merging(responseSchemaDictionary, uniquingKeysWith: { (first,second) in first }),
                              responses:responses,
                              securitySchemes: ["api_key" : securityScheme])

  
  guard let pathNodes = try? documentationXMLDocument.nodes(forXPath: "//*[@id='default-content']/div/table[position()>1]")
  else
  {
    print("Unable to find path definition tables.")
    exit(EXIT_FAILURE)
  }
  var paths = [String : PathItem]()
  var extraSchema = [ String : Schema ]()
  for nextPathNode in pathNodes
  {
    guard let urlRowString = try? nextPathNode.nodes(forXPath: "tbody/tr[1]").first?.stringValue,
          let url = getPathURL(fromString: urlRowString)
    else
    {
      print("Unable to get URL for path")
      exit(EXIT_FAILURE)
    }
    let nextSummary = try? nextPathNode.nodes(forXPath: descriptionTableRowXPath).first?.stringValue?.apiPageFormattedString
    var apiPath = getAPIPath(fromURL: url)
    var nextOperation = getOperation(fromTableNode: nextPathNode, forPath: apiPath)
    let schemaName : String
    guard case var .actual(nextResponse) = nextOperation.responses.responses!["200"]!  else { exit(EXIT_FAILURE) }
    let nextSchema = nextResponse.content!["application/json"]!.schema
    if [String](singular.keys).contains(apiPath)
    {
      schemaName = singular[apiPath]!.components(separatedBy: "/")[1].capitalized.replacingOccurrences(of: "_", with: "")
      components.schemas?[schemaName] = nextSchema
    }
    else if [String](singular.values).contains(apiPath)
    {
      schemaName = "\(apiPath.components(separatedBy: "/")[1].capitalized.replacingOccurrences(of: "_", with: "")).Detail"
      guard case let .actual(pluralSchema) = nextSchema else { exit(EXIT_FAILURE) }
      extraSchema[schemaName] = pluralSchema
    }
    else
    {
      let pathName = apiPath.components(separatedBy: "/").last{ !$0.contains("id}") }!.capitalized.replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "-", with: "")
      schemaName = pathName.hasSuffix("s") ? String(pathName.dropLast()) : pathName
      components.schemas?[schemaName] = nextSchema
    }
    
    let envelope : Reference<Schema>
    if !excludeResponseSchemaArray.contains(apiPath)
    {
      envelope = .actual(getResponseSchema(withChild: .reference("#/components/schemas/\(schemaName)"), isSingular: [String](singular.values).contains(apiPath)))
    }
    else
    {
      envelope = .reference("#/components/schemas/\(schemaName)")
    }
    
    nextResponse.content?["application/json"]?.schema = envelope
    let content = nextResponse.content?["application/json"]
    nextResponse.content?["application/xml"] = content
    nextResponse.content?["application/jsonp"] = content
    nextOperation.responses.responses?["200"] = .actual(nextResponse)
    nextOperation.responses.responses?["401"] = .reference("#/components/responses/InvalidAPIKey")
    
    nextOperation.deprecated = (nextSummary?.contains("DEPRECATED") ?? false) ? true : nil
    if apiPath == "/video_categories/{id}" { apiPath = "/video_categories" }
    if apiPath == "/types"
    {
      nextOperation.parameters?.append(Parameter(name: "format", description: "The data format of the response takes either xml, json, or jsonp.", location: .query, schema: .reference("#/components/schemas/Format"), isRequired: false))
    }
    for nextParameter in getParameters(fromPath: apiPath)
    {
      let pathParameterSchema = Schema(type: .string, description: fillToken)
      nextOperation.parameters?.append(Parameter(name: nextParameter, location: .path, schema: .actual(pathParameterSchema), isRequired: true))
    }
    let nextPathItem = PathItem(summary: fillToken, description: fillToken, get: nextOperation)
    paths[apiPath] = nextPathItem
  }
  
  //Build detailed schema
  for (nextSchemaName, nextSchema) in extraSchema
  {
    let baseSchemaName = nextSchemaName.components(separatedBy: ".")[0]
    
    guard case let .actual(baseSchema) = components.schemas![baseSchemaName]! else { exit(EXIT_FAILURE) }
    let baseSchemaProperties = [String](baseSchema.properties!.keys).sorted()
    let differenceProperties = [String](nextSchema.properties!.keys).sorted().difference(from: baseSchemaProperties)
    let diffKeys : [String] = differenceProperties.compactMap({
      change in
      switch change
      {
      case let .insert(_, key, _):
        return key
      default:
        return nil
      }
    })
    let extraProperties = nextSchema.properties!.filter { diffKeys.contains($0.key) }
    components.schemas?[nextSchemaName] = .actual(Schema(allOf:[.reference("#/components/schemas/\(baseSchemaName)"), .actual(Schema(properties: extraProperties))]))
  }
  //Build search field_list
  var searchFieldList = [String](Set<String>(searchSchemaList.map { components.schemas![$0]! }
    .map {(reference) -> Schema in if case let .actual(schema) = reference { return schema } else { exit(EXIT_FAILURE) }}
    .flatMap { $0.properties!.keys })).sorted()
  let fieldListParameterIndex = paths["/search"]!.get!.parameters!.firstIndex{ $0.name == "field_list" }!
  if case var .actual(parameterSchema) = paths["/search"]!.get!.parameters![fieldListParameterIndex].schema,
     case var .actual(fieldListSchema) = parameterSchema.allOf?[1],
     case let .item(reference) = fieldListSchema.items,
     case var .actual(item) = reference
  {
    searchFieldList.append(contentsOf: item.enumValues?.compactMap { guard case let .string(string) = $0 else { return nil } ; return string } ?? [])
    searchFieldList.sort()
    item.enumValues = searchFieldList.map { .string($0) }
    fieldListSchema.items = .item(.actual(item))
    parameterSchema.allOf?[1] = .actual(fieldListSchema)
    paths["/search"]!.get!.parameters![fieldListParameterIndex].schema = .actual(parameterSchema)
  }
  var openAPI = OpenAPI(openapi: "3.0.2",
                        info: Info(title: "Giant Bomb API",
                                   description: fillToken,
                                   version: "0.7"),
                        paths: paths,
                        components: components,
                        externalDocs: ExternalDocumentation(description: fillToken, url: URL(string: docURLString)!))
  openAPI.tags = [
    Tag(name: "General", description: fillToken),
    Tag(name: "Wiki", description: fillToken),
    Tag(name: "Search", description: fillToken),
    Tag(name: "Reviews", description: fillToken),
    Tag(name: "Videos", description: fillToken),
    Tag(name: "Live", description: fillToken),
    Tag(name: "Bookmarks", description: fillToken)
  ]
  openAPI.servers = [Server(url: URL(string: "http://www.giantbomb.com/api/")!, description: fillToken)]
  let jsonEncoder = JSONEncoder()
  jsonEncoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
  guard let json = try? jsonEncoder.encode(openAPI)
  else {
    print("Unable to encode JSON")
    exit(EXIT_FAILURE)
  }
  guard let jsonString = String(data: json, encoding: .utf8) else { exit(EXIT_FAILURE) }
  try? jsonString.write(toFile: "Giant Bomb API OpenAPI Specification.json", atomically: true, encoding: .utf8)
}
catch
{
  print(error)
}

func getOperation(fromTableNode tableNode: XMLNode, forPath path: String) -> Operation
{
  var operation = Operation(description: fillToken, parameters: [], responses: Responses(responses: [String:Reference<Response>]()), summary: fillToken)
  let fieldsHeaderTableRowXPath = "td/strong[text() = 'Fields']"
  let filterTableRowXPath = "tbody/tr[td[strong[text() = 'Filters']]]//following-sibling::tr[not(preceding-sibling::tr/\(fieldsHeaderTableRowXPath)) and not(\(fieldsHeaderTableRowXPath))]"
  let fieldTableRowXPath = "tbody/tr[td[strong[text() = 'Fields']]]//following-sibling::tr"
  guard let filterTableRowNodes = try? tableNode.nodes(forXPath: filterTableRowXPath),
        let fieldTableRowNodes = try? tableNode.nodes(forXPath: fieldTableRowXPath)
  else { return operation }
  
  for nextFilter in filterTableRowNodes
  {
    guard let nextParameterName = try? nextFilter.nodes(forXPath: "td[1]").first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    else {
      continue
    }
    guard let nextParameterDescription = try? nextFilter.nodes(forXPath: "td[2]").first?.giantBombDescriptionString
    else {
      continue
    }
    var nextParameter = Parameter(name: nextParameterName, description: nextParameterDescription, location: .query, isRequired: false)
    let schemaName = nextParameterName.capitalized.replacingOccurrences(of: "_", with: "")
    if parameterSchemas.keys.contains(schemaName)
    {
      nextParameter.schema = .reference("#/components/schemas/\(schemaName)")
    }
    else if schemaName == "Platforms"
    {
      nextParameter.schema = .reference("#/components/schemas/\(schemaName.dropLast())Id")
    }
    else if schemaName == "Game"
    {
      nextParameter.schema = .reference("#/components/schemas/\(schemaName)Id")
    }
    else if nextParameterName == "resources"
    {
      nextParameter.style = .form
      nextParameter.explode = false
      let resourceSchema = Schema(type: .array, description: fillToken, items: .item(.reference("#/components/schemas/ResourceType")))
      nextParameter.schema = .actual(resourceSchema)
    }
    else if nextParameterName == "sort" ||
              nextParameterName == "filter"
    {
      nextParameter.allowReserved = true
    }
    
    if path == "/search",
       nextParameterName == "limit"
    {
      let searchLimitSchema = Schema(allOf: [nextParameter.schema!,
                                             .actual(Schema(maximum: 10))])
      nextParameter.schema = .actual(searchLimitSchema)
    }
    operation.parameters?.append(nextParameter)
  }
  var schema = getSchema(fromTableRowNodes: fieldTableRowNodes)
  if var fieldListParameter = operation.parameters?.first(where: {$0.name == "field_list"})
  {
    let fieldListSchema = Schema(enumValues: [String](schema.properties!.keys.sorted()).map { .string($0)}, type: .string)
    let overrideSchema = Schema(items: .item(.actual(fieldListSchema)))
    fieldListParameter.schema = .actual(Schema(allOf: [fieldListParameter.schema!, .actual(overrideSchema)]))
    fieldListParameter.style = .form
    fieldListParameter.explode = false
    if let fieldListIndex = operation.parameters?.firstIndex(where: {$0.name == "field_list"})
    {
      operation.parameters?[fieldListIndex] = fieldListParameter
    }
  }
  // Correct schema
  if path == "/video/current-live" { schema.properties?["success"] = .actual(Schema(type: .integer, description: fillToken)) }
  else if path == "/video/get-saved-time"
  {
    schema.properties?.removeValue(forKey: "message")
    schema.properties?["success"] = .actual(Schema(type: .integer, description: fillToken))
  }
  else if path == "/video/get-all-saved-times"
  {
    let innerSchema = schema
    let savedTimesSchema = Schema(type:.array, description: fillToken, items: .item(.actual(innerSchema)))
    var parentSchema = Schema(type: .object, properties: ["savedTimes" : .actual(savedTimesSchema)])
    parentSchema.properties?["success"] = .actual(Schema(type: .integer, description: fillToken))
    schema = parentSchema
  }
  else if path == "/video/save-time"
  {
    let properties = ["success": Reference.actual(Schema(type: .boolean, description: fillToken)),
                      "message": Reference.actual(Schema(type: .string, description: fillToken))]
    schema = Schema(type: .object, description: fillToken, properties: properties)
  }
  else if path == "/search"
  {
    let innerSchema = schema
    let schemaRefList = searchSchemaList.map { "#/components/schemas/\($0)" }.map { Reference<Schema>.reference($0) }
    let parentSchema = Schema(allOf: [.actual(Schema(oneOf: schemaRefList)), .actual(innerSchema)])
    schema = parentSchema
  }
  let nextMediaType = MediaType(schema: .actual(schema))
  let descriptionTableViewStringValue = (try? tableNode.nodes(forXPath: descriptionTableRowXPath).first?.stringValue?.apiPageFormattedString) ?? fillToken
  let descriptionComponents = descriptionTableViewStringValue.components(separatedBy: "<br />")
  operation.summary = descriptionComponents[0]
  if descriptionComponents.count > 1
  {
    operation.description = ([fillToken] + descriptionComponents[1...]).joined(separator: "<br />")
  }
  let nextResponse = Response(description: fillToken,
                              content: ["application/json": nextMediaType])
  operation.responses.responses!["200"] = .actual(nextResponse)
  operation.security = [["api_key": []]]
  operation.externalDocs = ExternalDocumentation(description: fillToken, url: URL(string: "\(docURLString)#ADD")!)
  
  if path.starts(with: "/chat") ||
      path == "/video/current-live"
  {
    operation.tags = ["Live"]
  }
  else if path == "/video/get-saved-time" ||
            path == "/video/get-all-saved-times" ||
            path == "/video/save-time"
  {
    operation.tags = ["Bookmarks"]
  }
  else if path == "/types" ||
            path.starts(with: "/promo")
  {
    operation.tags = ["General"]
  }
  else if path.contains("search")
  {
    operation.tags = ["Search"]
  }
  else if path.contains("review")
  {
    operation.tags = ["Reviews"]
  }
  else if path.starts(with: "/video")
  {
    operation.tags = ["Videos"]
  }
  else
  {
    operation.tags = ["Wiki"]
  }
  
  return operation
}

func getSchema(fromTableRowNodes tableRowNodes: [XMLNode]) -> Schema
{
  var propertiesDictionary = [String : Reference<Schema>]()
  for nextRow in tableRowNodes
  {
    guard let nextPropertyName = try? nextRow.nodes(forXPath: "td[1]").first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    else {
      continue
    }
    guard let nextPropertyDescription = try? nextRow.nodes(forXPath: "td[2]").first?.giantBombDescriptionString
    else {
      continue
    }
    if nextPropertyName.contains(".")
    {
      let propertySegments = nextPropertyName.components(separatedBy: ".")
      let parentName = propertySegments[0]
      let childProperty = Schema(type: .string, description: nextPropertyDescription, example: typeToken)
      if propertiesDictionary.keys.contains(parentName)
      {
        guard case var .actual(parentProperty) = propertiesDictionary[parentName] else { exit(EXIT_FAILURE) }
        parentProperty.properties?[propertySegments[1]] = .actual(childProperty)
        propertiesDictionary[parentName] = .actual(parentProperty)
      }
      else
      {
        let parentSchema = Schema(type: .object, description: fillToken, nullable: true, properties: [propertySegments[1] : .actual(childProperty)])
        propertiesDictionary[propertySegments[0]] = .actual(parentSchema)
      }
    }
    else if nextPropertyName == "resource_type"
    {
      let resourceTypeSchema = Schema(allOf: [.reference("#/components/schemas/ResourceType"),
                                              .actual(Schema(description: nextPropertyDescription))])
      propertiesDictionary[nextPropertyName] = .actual(resourceTypeSchema)
    }
    else
    {
      propertiesDictionary[nextPropertyName] = .actual(Schema(type: .string, description: nextPropertyDescription, example: typeToken))
    }
  }
  
  return Schema(type: .object, description: fillToken, properties: propertiesDictionary)
}


func getPathURL(fromString string: String) -> URL?
{
  let formatted = string
    .replacingOccurrences(of: "[YOUR API KEY]", with: "YOURAPIKEY")
    .replacingOccurrences(of: "[", with: "{")
    .replacingOccurrences(of: "]", with: "}")
  let range = NSRange(formatted.startIndex..<formatted.endIndex, in: formatted)
  if let urlMatch = urlDataDetector?.firstMatch(in: formatted, options: [], range: range)
  {
    return urlMatch.url
  }
  return nil
}

func getAPIPath(fromURL url: URL) -> String
{
  let pathComponents = url.pathComponents
  return "/\(pathComponents[2...].joined(separator: "/"))"
}

func getParameters(fromPath pathString: String) -> [String]
{
  var parameters = [String]()
  let range = NSRange(pathString.startIndex..<pathString.endIndex, in: pathString)
  let matches = pathParameterRegularExpression?.matches(in: pathString, options: [], range: range) ?? []
  for nextMatch in matches
  {
    let matchRange = Range(nextMatch.range, in: pathString)!
    parameters.append(String(pathString[matchRange]))
  }
  return parameters
}

func getResponseSchema(withChild pathSchema: Reference<Schema>, isSingular: Bool = false) -> Schema
{
  let resultSchema = isSingular ?
  pathSchema :
    .actual(Schema(type: .array, items: Schema.ItemsValue.item(pathSchema)))
  let extensionSchema = Schema(type: .object, properties: ["version": .actual(Schema(type:.string, description: fillToken, example: "1.0")),
                                                           "results" : resultSchema])
  return Schema(type: .object, allOf: [.reference("#/components/schemas/Response"), .actual(extensionSchema)])
}

extension XMLNode
{
  var giantBombDescriptionString : String
  {
    let htmlString = self.xmlString(options: .documentTidyHTML)
    let htmlData = htmlString.data(using: .utf8)!
    let attributedString = NSAttributedString(html: htmlData, documentAttributes: nil)
    
    return attributedString!.string.apiPageFormattedString
  }
}

extension String
{
  var apiPageFormattedString : String
  {
    self
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\n", with: "<br />")
      .replacingOccurrences(of: "\t", with: "")
      .replacingOccurrences(of: "•", with: "")
      .replacingOccurrences(of: "NEED DESCRIPTION", with: fillToken)
  }
}
