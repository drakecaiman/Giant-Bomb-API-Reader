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
let parameterSchemas = ["Format" : Schema(enumValues: ["xml", "json", "jsonp"], type: .string, description: fillToken),
                        "FieldList" : Schema(type: .array, description: fillToken, items: .item(Schema(type:.string, description: fillToken))),
                        "Limit": Schema(type: .integer, description: fillToken, minimum: 0, maximum: 100),
                        "Offset": Schema(type: .integer, description: fillToken),
                        "Sort": Schema(type: .string, description: fillToken, pattern: sortQueryRegEx),
                        "Filter": Schema(type: .string, description: fillToken, pattern: filterQueryRegEx),
                        "ResourceType": Schema(enumValues: [
                          "game",
                          "franchise",
                          "character",
                          "concept",
                          "object",
                          "location",
                          "person",
                          "company",
                          "video"
                        ],
                                               type: .string,
                                               description: fillToken)]
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

//let invalidAPIKeySchemas = [Schema(ref: "#/components/schemas/Response"),
//                            Schema(properties: ["results": ]]

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
  responseSchema.properties?["version"] = Schema(type:.string, description: fillToken, example: typeToken)
  let responseSchemaDictionary = ["Response" : responseSchema]
  var components = Components(schemas: parameterSchemas.merging(responseSchemaDictionary, uniquingKeysWith: { (first,second) in first }),
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
    let nextSchema = nextOperation.responses.responses!["200"]!.content!["application/json"]!.schema
    if [String](singular.keys).contains(apiPath)
    {
      schemaName = singular[apiPath]!.components(separatedBy: "/")[1].capitalized.replacingOccurrences(of: "_", with: "")
      components.schemas?[schemaName] = nextSchema
    }
    else if [String](singular.values).contains(apiPath)
    {
      schemaName = "\(apiPath.components(separatedBy: "/")[1].capitalized.replacingOccurrences(of: "_", with: "")).Detail"
      extraSchema[schemaName] = nextSchema
    }
    else
    {
      let pathName = apiPath.components(separatedBy: "/")[1].capitalized.replacingOccurrences(of: "_", with: "")
      schemaName = pathName.hasSuffix("s") ? String(pathName.dropLast()) : pathName
      components.schemas?[schemaName] = nextSchema
    }
    
    let envelope : Schema
    if !excludeResponseSchemaArray.contains(apiPath)
    {
      envelope = getResponseSchema(withChild: Schema(ref: "#/components/schemas/\(schemaName)"), isSingular: [String](singular.values).contains(apiPath))
    }
    else
    {
      envelope = Schema(ref: "#/components/schemas/\(schemaName)")
    }
    
    nextOperation.responses.responses?["200"]?.content?["application/json"]?.schema = envelope
    let content = nextOperation.responses.responses?["200"]?.content?["application/json"]
    nextOperation.responses.responses?["200"]?.content?["application/xml"] = content
    nextOperation.responses.responses?["200"]?.content?["application/jsonp"] = content
    // Response(ref: "#/components/responses/InvalidAPIKey")
    let response = nextOperation.responses.responses?["200"]
    nextOperation.responses.responses?["401"] = response
    
    nextOperation.deprecated = (nextSummary?.contains("DEPRECATED") ?? false) ? true : nil
    if apiPath == "/video_categories/{id}" { apiPath = "/video_categories" }
    if apiPath == "/types"
    {
      let formatSchema = Schema(ref: "#/components/schemas/Format")
      nextOperation.parameters?.append(Parameter(name: "format", description: "The data format of the response takes either xml, json, or jsonp.", location: .query, schema: formatSchema, isRequired: false))
    }
    for nextParameter in getParameters(fromPath: apiPath)
    {
      let pathParameterSchema = Schema(type: .string, description: fillToken)
      nextOperation.parameters?.append(Parameter(name: nextParameter, location: .path, schema: pathParameterSchema, isRequired: true))
    }
    let nextPathItem = PathItem(summary: fillToken, description: fillToken, get: nextOperation)
    paths[apiPath] = nextPathItem
  }
  
  //Build detailed schema
  for (nextSchemaName, nextSchema) in extraSchema
  {
    let baseSchemaName = nextSchemaName.components(separatedBy: ".")[0]
    
    let baseSchema = components.schemas![baseSchemaName]!
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
    components.schemas?[nextSchemaName] = Schema(allOf:[Schema(ref: "#/components/schemas/\(baseSchemaName)"), Schema(properties: extraProperties)])
  }
  //Build search field_list
  let searchFieldList = [String](Set<String>(searchSchemaList.map { components.schemas![$0]! }
                                              .flatMap { $0.properties!.keys })).sorted()
  let fieldListParameterIndex = paths["/search"]!.get!.parameters!.firstIndex{ $0.name == "field_list" }!
  if case var .item(item) = paths["/search"]!.get!.parameters![fieldListParameterIndex].schema?.allOf?[1].items
  {
    item.enumValues?.append(contentsOf: searchFieldList)
    item.enumValues?.sort()
    paths["/search"]!.get!.parameters![fieldListParameterIndex].schema?.allOf?[1].items = .item(item)
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
  var operation = Operation(description: fillToken, parameters: [], responses: Responses(responses: [String:Response]()), summary: fillToken)
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
      nextParameter.schema = Schema(ref: "#/components/schemas/\(schemaName)")
    }
    else if nextParameterName == "subscriber_only"
    {
      nextParameter.schema = Schema(type: .boolean, description: fillToken)
    }
    else if nextParameterName == "page" ||
              nextParameterName == "platforms" ||
              nextParameterName == "game" ||
              nextParameterName == "video_id" ||
              nextParameterName == "time_to_save"
    {
      nextParameter.schema = Schema(type: .integer, description: fillToken)
    }
    else if nextParameterName == "query"
    {
      nextParameter.schema = Schema(type: .string, description: fillToken)
    }
    else if nextParameterName == "resources"
    {
      nextParameter.style = .form
      nextParameter.explode = false
      let resourceSchema = Schema(type: .array, description: fillToken, items: .item(Schema(ref: "#/components/schemas/ResourceType")))
      nextParameter.schema = resourceSchema
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
                                             Schema(maximum: 10)])
      nextParameter.schema = searchLimitSchema
    }
    operation.parameters?.append(nextParameter)
  }
  var schema = getSchema(fromTableRowNodes: fieldTableRowNodes)
  if var fieldListParameter = operation.parameters?.first(where: {$0.name == "field_list"})
  {
    let fieldListSchema = Schema(enumValues: [String](schema.properties!.keys.sorted()), type: .string)
    let overrideSchema = Schema(items: .item(fieldListSchema))
    fieldListParameter.schema = Schema(allOf: [fieldListParameter.schema!, overrideSchema])
    fieldListParameter.style = .form
    fieldListParameter.explode = false
    if let fieldListIndex = operation.parameters?.firstIndex(where: {$0.name == "field_list"})
    {
      operation.parameters?[fieldListIndex] = fieldListParameter
    }
  }
  // Correct schema
  if path == "/video/current-live" { schema.properties?["success"] = Schema(type: .integer, description: fillToken) }
  else if path == "/video/get-saved-time"
  {
    schema.properties?.removeValue(forKey: "message")
    schema.properties?["success"] = Schema(type: .integer, description: fillToken)
  }
  else if path == "/video/get-all-saved-times"
  {
    let innerSchema = schema
    let savedTimesSchema = Schema(type:.array, description: fillToken, items: .item(innerSchema))
    var parentSchema = Schema(type: .object, properties: ["savedTimes" : savedTimesSchema])
    parentSchema.properties?["success"] = Schema(type: .integer, description: fillToken)
    schema = parentSchema
  }
  else if path == "/video/save-time"
  {
    let properties = ["success": Schema(type: .boolean, description: fillToken),
                      "message": Schema(type: .string, description: fillToken)]
    schema = Schema(type: .object, description: fillToken, properties: properties)
  }
  else if path == "/search"
  {
    let innerSchema = schema
    let schemaRefList = searchSchemaList.map { "#/components/schemas/\($0)" }.map { Schema(ref: $0 ) }
    let parentSchema = Schema(allOf: [Schema(oneOf: schemaRefList), innerSchema])
    schema = parentSchema
  }
  let nextMediaType = MediaType(schema: schema)
  let descriptionTableViewStringValue = (try? tableNode.nodes(forXPath: descriptionTableRowXPath).first?.stringValue?.apiPageFormattedString) ?? fillToken
  let descriptionComponents = descriptionTableViewStringValue.components(separatedBy: "<br />")
  operation.summary = descriptionComponents[0]
  if descriptionComponents.count > 1
  {
    operation.description = ([fillToken] + descriptionComponents[1...]).joined(separator: "<br />")
  }
  let nextResponse = Response(description: fillToken,
                              content: ["application/json": nextMediaType])
  operation.responses.responses!["200"] = nextResponse
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
  var propertiesDictionary = [String : Schema]()
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
        propertiesDictionary[parentName]?.properties?[propertySegments[1]] = childProperty
      }
      else
      {
        let parentSchema = Schema(type: .object, description: fillToken, nullable: true, properties: [propertySegments[1] : childProperty])
        propertiesDictionary[propertySegments[0]] = parentSchema
      }
    }
    else if nextPropertyName == "resource_type"
    {
      let resourceTypeSchema = Schema(allOf: [Schema(ref: "#/components/schemas/ResourceType"),
                                              Schema(description: nextPropertyDescription)])
      propertiesDictionary[nextPropertyName] = resourceTypeSchema
    }
    else
    {
      propertiesDictionary[nextPropertyName] = Schema(type: .string, description: nextPropertyDescription, example: typeToken)
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

func getResponseSchema(withChild pathSchema: Schema, isSingular: Bool = false) -> Schema
{
  let resultSchema = isSingular ?
  pathSchema :
  Schema(type: .array, items: Schema.ItemsValue.item(pathSchema))
  let extensionSchema = Schema(type: .object, properties: ["results" : resultSchema])
  
  return Schema(type: .object, allOf: [Schema(ref: "#/components/schemas/Response"), extensionSchema])
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
