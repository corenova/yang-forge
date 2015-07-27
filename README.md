# yfc -- YangForge Controller

`yfc` is the command shell for the YangForge framework, providing
schema-driven application lifecycle management.

`YangForge` provides runtime JavaScript execution based on YANG schema
modeling language as defined in IETF drafts and standards
([RFC 6020](http://tools.ietf.org/html/rfc6020)).

It is written primarily using CoffeeScript and runs on
[node](http://nodejs.org).

  [![NPM Version][npm-image]][npm-url]
  [![NPM Downloads][downloads-image]][downloads-url]

## Installation
```bash
$ npm install -g yangforge
```

## Usage
```
  Usage: yfc [options] [command]
  
  
  Commands:
    
    build [options] [name...]    package the application for deployment (planned)
    config                       manage application configuration data (planned)
    deploy                       deploy application into yangforge endpoint (planned)
    info [options] [name...]     show info about one or more packages
    init                         initialize package configuration
    install [options] [name...]  install one or more packages
    list [options]               list installed packages
    publish [options]            publish package to upstream registry (planned)
    run [options] [name...]      runs one or more modules
    schema [options]             process YANG schema files
    sign                         sign package to ensure authenticity (planned)
  
  YANG driven JS application builder
  
  Options:
    
    -h, --help     output usage information
    -V, --version  output the version number
    --no-color     disable color output
```

## Common Usage Examples

### Working with `schema`

You can `--eval` a YANG schema **string** directly for dynamic parsing:
```bash
$ yfc schema -e 'module hello-world { description "a test"; leaf hello
{ type string; default "world"; } }'
```
```yaml
module:
  hello-world:
    description: a test
    leaf:
      hello:
        type: string
        default: world
```
You can specify output `--format` (default is YAML as above):
```bash
$ yfc schema -e 'module hello-world { description "a test"; leaf hello
{ type string; default "world"; } }' -f json
```
```json
{
 "module": {
   "hello-world": {
     "description": "a test",
     "leaf": {
       "hello": {
         "type": "string",
         "default": "world"
       }
     }
   }
 }
}
```
You can `--compile` a YANG schema **file** for processing:
```bash
$ yfc schema -c examples/example-jukebox.yang
```

## Key Features

* **Parse** YANG schema files and generate runtime JavaScript
  [meta-class](http://github.com/stormstack/meta-class) semantic tree
  hierarchy
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

[YangForge](src/yangforge.litcoffee) itself is also a YANG schema
([yang-compiler.yang](./yangforge.yang)) **compiled** module. It is
compiled by the [yang-compiler](src/compiler/compiler.litcoffee) and
natively `include`
[yang-v1-extensions](yang_modulesyang-v1-extensions) submodule for
supporting the version 1.0 YANG RFC specifications. It serves as a
good reference for writing new compilers, custom extensions, custom
importers, among other things.

## Using YangForge Programmatically

```coffeescript
Forge = require 'yangforge'

forgey = new Forge

yang = new Yang

schema = """
  module test {
    description 'hello';
	leaf works { type string; }
  }
  """
Test = yang.compile schema
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

* [YANG Compiler](src/yang-compiler.litcoffee)
  * [Compiler Mixin](src/yang-compiler-mixin.litcoffee)
  * [Compiler Schema](./yang-compiler.yang)
  * [YANG v1.0 Extensions](./yang-v1-extensions.yang)
* [YANG Meta Compiler](src/yang-meta-compiler.litcoffee)
* [Meta Class](src/meta-class.litcoffee)

## License
  [MIT](LICENSE)

[npm-image]: https://img.shields.io/npm/v/yangforge.svg
[npm-url]: https://npmjs.org/package/yangforge
[downloads-image]: https://img.shields.io/npm/dm/yangforge.svg
[downloads-url]: https://npmjs.org/package/yangforge
