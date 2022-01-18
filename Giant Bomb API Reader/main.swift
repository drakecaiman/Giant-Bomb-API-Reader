//
//  main.swift
//  Giant Bomb API Reader
//
//  Created by Duncan on 1/17/22.
//

import Foundation
import WebKit

guard let apiURL = URL(string: "https://www.giantbomb.com/api/documentation/") else
{
  print("Failed to get URL")
  exit(EXIT_FAILURE)
}
do
{
  let documentationXMLDocument = try XMLDocument(contentsOf: apiURL, options: [.documentTidyHTML])
  
  // Grab the "Response" format to create the encapsulation structure
  if let responseNode = try? documentationXMLDocument.nodes(forXPath: "//*[@id='default-content']/div/table[1]").first
  {
    print(getPath(forTableNode: responseNode))
  }
  else
  {
    print("Unable to find response definition table.")
  }
  
}
catch
{
  print(error)
}

func getPath(forTableNode tableNode: XMLNode) -> Dictionary<String, Any>
{
  var responseDictionary = [String : Any]()
  for nextRow in (try? tableNode.nodes(forXPath: "tbody/tr")) ?? []
  {
    guard let nextPropertyName = try? nextRow.nodes(forXPath: "td[1]").first?.stringValue else { exit(EXIT_FAILURE) }
    guard let nextPropertyDescription = try? nextRow.nodes(forXPath: "td[2]").first?.stringValue else { exit(EXIT_FAILURE) }
    responseDictionary[nextPropertyName] = ["description": nextPropertyDescription]
  }
  return responseDictionary
}
