# YANG Compiler

YANG Compiler provides necessary tooling to enable runtime JavaScript
execution based on YANG schema modeling language as defined in IETF
drafts and standards ([RFC 6020](http://tools.ietf.org/html/rfc6020)).

It is written primarily using CoffeeScript and runs on
[node](http://nodejs.org).

  [![NPM Version][npm-image]][npm-url]
  [![NPM Downloads][downloads-image]][downloads-url]

## Key Features

* **Parse** YANG schema files and generate runtime JavaScript
  [meta-class](http://github.com/stormstack/meta-class) semantic tree
  hierarchy
* **Map/Reduce** traversal of the parser output to dynamically resolve
  YANG statement extensions and transform nodes in the tree as well as
  collapsing them into a final output module
* **Import/Export** capabilities to load modules using customizable
  importers based on regular expressions and custom import
  routines. Ability to serialize module meta data into JSON format
  that is portable across systems. Also exports serialized JS
  functions as part of export meta data.
* **Runtime Generation** allows compiler to directly create a live JS
  class object definition so that it can be instantiated via `new`
  keyword and used immediately
* **Dynamic Extensions** enable compiler to be configured with
  alternative `resolver` functions to change the behavior of produced
  output

The [yang-compiler](src/yang-compiler.litcoffee) itself is also a YANG
schema ([yang-compiler.yang](./yang-compiler.yang)) **compiled**
module. It is compiled by the
[yang-meta-compiler](src/yang-meta-compiler.litcoffee) and dynamically
`include` [yang-v1-extensions.yang](./yang-v1-extensions.yang) schema
for supporting the version 1.0 YANG RFC specifications. It serves as a
good reference for writing new compilers, custom extensions, custom
importers, among other things.

## Installation
```bash
$ npm install yang-compiler
```

## Quick Example

```coffeescript
YangCompiler = require 'yang-compiler'
compiler = new YangCompiler

schema = """
  module test {
    description 'hello';
	leaf works { type string; }
  }
  """
Test = compiler.compile schema
test = new Test
test.set 'works', 'very well'
test.get 'works'
```

## Common Usage Examples

The below examples can be executed using CoffeeScript REPL by running
`coffee` at the command-line from the top-directory of this repo.

* Importing a local YANG schema file (such as importing itself...)
```coffeescript
yc = compiler.import source: 'schema:./yang-compiler.yang'
```
* Exporting a known YANG module into JSON
```coffeescript
json = compiler.export name: 'yang-compiler'
```
* Importing from serialized JSON export
```coffeescript
A = compiler.import json
```
* Instantiating a newly imported module with configurations
```coffeescript
hello = new A map: 'foo': 'schema:./yang-compiler.yang'
```
* Invoking a YANG RPC extension to import by name (like foo)
```coffeescript
B = hello.invoke 'import', name: 'foo'
```
* Various operations to get/set different configurations
```coffeescript
hello.get()
hello.get 'map'
hello.set 'map', bar: 'whatever'
hello.get 'map.bar'
hello.set 'map.bar', 'good bye'
hello.get 'map'
```

There are many other ways of interacting with the module's class
object as well as the instantiated class. Please refer to the
`meta-class` for additional information.

## Literate CoffeeScript Documentation

The source code is documented in Markdown format. It's code combined
with documentation all-in-one.

* [YANG Compiler Source](src/yang-compiler.litcoffee)
* [YANG Compiler Schema](./yang-compiler.yang)
* [YANG v1.0 Extensions](./yang-v1-extensions.yang)
* [YANG Meta Compiler](src/yang-meta-compiler.litcoffee)

### External Dependencies

* [Meta Class](http://github.com/stormstack/meta-class)

## License
  [MIT](LICENSE)

[npm-image]: https://img.shields.io/npm/v/yang-compiler.svg
[npm-url]: https://npmjs.org/package/yang-compiler
[downloads-image]: https://img.shields.io/npm/dm/yang-compiler.svg
[downloads-url]: https://npmjs.org/package/yang-compiler
