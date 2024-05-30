# frozen_string_literal: true

# spec/fixtures/setup_sample_package.rb
require "fileutils"
require "json"

base_dir = "spec/fixtures/sample_package"
content_dir = File.join(base_dir, "content")
data_dir = File.join(base_dir, "data")

FileUtils.mkdir_p(content_dir)
FileUtils.mkdir_p(data_dir)

# Create content files
File.write(File.join(content_dir, "index.html"), "<html><body>Hello</body></html>")
File.write(File.join(content_dir, "example.css"), "body { color: red; }")
File.write(File.join(content_dir, "example.js"), "function test() { return true; }")

# Create data file
animals_yaml = <<~YAML
  animals:
    - name: "Lion"
      type: "Mammal"
      habitat: "Savannah"
    - name: "Eagle"
      type: "Bird"
      habitat: "Mountains"
    - name: "Shark"
      type: "Fish"
      habitat: "Ocean"
YAML

File.write(File.join(data_dir, "animals.yaml"), animals_yaml)

# Create schema file
animals_schema_yaml = <<~YAML
  type: object
  properties:
    animals:
      type: array
      items:
        type: object
        properties:
          name:
            type: string
          type:
            type: string
          habitat:
            type: string
        required:
          - name
          - type
          - habitat
  required:
    - animals
YAML

File.write(File.join(data_dir, "animals_schema.yaml"), animals_schema_yaml)

# Create manifest.json
manifest_data = {
  content: {
    "index.html" => "text/html",
    "example.css" => "text/css",
    "example.js" => "application/javascript"
  }
}
File.write(File.join(base_dir, "manifest.json"), JSON.pretty_generate(manifest_data))

# Create metadata.json
metadata_data = {
  "name": "sample_package",
  "version": "0.1.0",
  "dependencies": {}
}
File.write(File.join(base_dir, "metadata.json"), JSON.pretty_generate(metadata_data))

# Create routes.json
routes_data = {
  "routes": {
    "/": "index.html",
    "/index": "index.html",
    "/index.html": "index.html",
    "/example.css": "example.css",
    "/example.js": "example.js",
    "/api/v1/data/animals": { "type": "dataset", "name": "animals" }
  }
}
File.write(File.join(base_dir, "routes.json"), JSON.pretty_generate(routes_data))

# Create storage.json
storage_data = {
  "datasets": [
    {
      "name": "animals",
      "source": "data/animals.yaml",
      "format": "yaml",
      "schema": "data/animals_schema.yaml"
    }
  ]
}
File.write(File.join(base_dir, "storage.json"), JSON.pretty_generate(storage_data))
