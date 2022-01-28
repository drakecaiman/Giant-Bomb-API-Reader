//
//  main.swift
//  Giant Bomb API Reader
//
//  Created by Duncan on 1/17/22.
//

import Foundation
import WebKit

let urlDataDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
let pathParameterRegularExpression = try? NSRegularExpression(pattern: "(?<=\\{).*?(?=\\})", options: [])
let descriptionTableRowXPath = "tbody/tr/td[strong[starts-with(text(),'Description:')]]/p"

guard let apiURL = URL(string: "https://www.giantbomb.com/api/documentation/") else
{
  print("Failed to get URL")
  exit(EXIT_FAILURE)
}
do
{
  let documentationXMLDocument = try XMLDocument(contentsOf: apiURL, options: [.documentTidyHTML])
//  let components
  
  // Grab the "Response" format to create the encapsulation structure
  guard let responseNode = try? documentationXMLDocument.nodes(forXPath: "//*[@id='default-content']/div/table[1]").first
  else
  {
    print("Unable to find response definition table.")
    exit(EXIT_FAILURE)
  }
  
  let securityScheme = SecurityScheme(type: .apiKey, name: "api_key", location: .query)
  guard let responseTableRowNodes = try? responseNode.nodes(forXPath: "tbody/tr") else { exit(EXIT_FAILURE) }
  let components = Components(schemas: ["Response": getSchema(fromTableRowNodes: responseTableRowNodes)],
                              securitySchemes: ["api_key" : securityScheme])
  
  guard let pathNodes = try? documentationXMLDocument.nodes(forXPath: "//*[@id='default-content']/div/table[position()>1]")
  else
  {
    print("Unable to find path definition tables.")
    exit(EXIT_FAILURE)
  }
  var paths = [String : PathItem]()
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
    let apiPath = getAPIPath(fromURL: url)
    var nextOperation = getOperation(fromTableNode: nextPathNode)
    nextOperation.deprecated = (nextSummary?.contains("DEPRECATED") ?? false) ? true : nil
    for nextParameter in getParameters(fromPath: apiPath)
    {
      nextOperation.parameters?.append(Parameter(name: nextParameter, location: .path, isRequired: true))
    }
    let nextPathItem = PathItem(summary: nextSummary, get: nextOperation)
    paths[apiPath] = nextPathItem
  }
  
  var openAPI = OpenAPI(openapi: "3.0.2",
                        info: Info(title: "Giant Bomb API",
                                   version: "1.0.0"),
                        paths: paths,
                        components: components)
  openAPI.servers = [Server(url: URL(string: "http://www.giantbomb.com/api/")!)]
  let jsonEncoder = JSONEncoder()
  jsonEncoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
  guard let json = try? jsonEncoder.encode(openAPI)
  else {
    print("Unable to encode JSON")
    exit(EXIT_FAILURE)
  }
  print(String(data: json, encoding: .utf8)!)
}
catch
{
  print(error)
}

func getOperation(fromTableNode tableNode: XMLNode) -> Operation
{
  var operation = Operation(parameters: [], responses: Responses(responses: [String:Response]()))
  let filterTableRowXPath = "tbody/tr[td[strong[text() = 'Filters']]]//following-sibling::tr[not(preceding-sibling::tr/td/strong[text() = 'Fields'])]"
  let fieldTableRowXPath = "tbody/tr[td[strong[text() = 'Fields']]]//following-sibling::tr"
  guard let filterTableRowNodes = try? tableNode.nodes(forXPath: filterTableRowXPath),
        let fieldTableRowNodes = try? tableNode.nodes(forXPath: fieldTableRowXPath)
  else { return operation }
  
  for nextFilter in filterTableRowNodes
  {
    guard let nextParameterName = try? nextFilter.nodes(forXPath: "td[1]").first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    else {
//      print("Unable to get property name")
      continue
    }
    guard let nextParameterDescription = try? nextFilter.nodes(forXPath: "td[2]").first?.giantBombDescriptionString
    else {
//      print("Unable to get property description")
      continue
    }
    let nextParameter = Parameter(name: nextParameterName, description: nextParameterDescription, location: .query, isRequired: false)
    operation.parameters?.append(nextParameter)
  }
  let pathSchema = getSchema(fromTableRowNodes: fieldTableRowNodes)
  let nextMediaType = MediaType(schema: pathSchema)
  let nextResponse = Response(description: "", content: ["application/json": nextMediaType])
  operation.responses.responses!["200"] = nextResponse
  operation.security = [["api_key": []]]
  
  return operation
}

func getSchema(fromTableRowNodes tableRowNodes: [XMLNode]) -> Schema
{
  var propertiesDictionary = [String : Property]()
  for nextRow in tableRowNodes
  {
    guard let nextPropertyName = try? nextRow.nodes(forXPath: "td[1]").first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    else {
//      print("Unable to get property name")
      continue
    }
    guard let nextPropertyDescription = try? nextRow.nodes(forXPath: "td[2]").first?.giantBombDescriptionString
    else {
//      print("Unable to get property description")
      continue
    }
    propertiesDictionary[nextPropertyName] = Property(type: "string", description: nextPropertyDescription)
  }
  return Schema(type: "object", properties: propertiesDictionary)
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
  }
}
