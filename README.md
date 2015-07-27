# yfc -- YangForge Controller

`yfc` is the command shell for the YangForge framework, providing
schema-driven application lifecycle management.

`YangForge` provides runtime JavaScript execution based on YANG schema
modeling language as defined in IETF drafts and standards
([RFC 6020](http://tools.ietf.org/html/rfc6020)).

It is written primarily using CoffeeScript and runs on
[Node.js](http://nodejs.org).

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

The `yfc` command-line interface is **dynamically auto-generated** according to [yangforge.yang](./yangforge.yang) schema definitions.  Please refer to the schema section covering various `rpc` extension statements and sub-statement definitions for a reference regarding different types of command-line arguments, descriptions, and options processing syntax.  The corresponding **actions** for each of the `rpc` extensions are implemented inside the `YangForge` module forging before hook (here)[src/yangforge.coffee]

## Common Usage Examples

### Using the `schema` command
```bash
$ yfc schema -h

  Usage: schema [options]

  process YANG schema files

  Options:

    -h, --help              output usage information
    -c, --compile [string]  compile input file into specified output format
    -e, --eval [string]     pass a string from the command line as input
    -f, --format [string]   specify output format (yaml, json) (default: yaml)
    -o, --output [string]   set the output directory for compiled schemas
```

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
You can specify explicit output `--format` (default is YAML as above):
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
$ yfc schema -c examples/jukebox.yang
```

### Using the `run` command

The real power of `YangForge` is actualized when **yangforged**
modules are run using via one or more **dynamic interface
generators**.

```bash
$ yfc run -h

  Usage: run [options] [name...]

  runs one or more modules

  Options:

    -h, --help              output usage information
    -p, --port [number]     specify listening port (default: 5000)
    -c, --compile <file>  dynamically compile/run a YANG schema file
    --restjson [boolean]    enables REST/JSON interface (default: true)
    --autodoc [boolean]     enables auto-generated documentation interface
```

#### Built-in interface generators

name | description | dependency
--- | --- | ---
cli | generates command-line interface | none
express | generates HTTP/HTTPS web server instance | none
restjson | generates REST/JSON web services interface | express
autodoc | generates self-documentation interface | express

When you issue `run` without any target module(s) as argument, it runs the internal `YangForge` module using defaults:
```bash
$ yfc run
express: listening on 5000
restjson: binding forgery to /restjson
```
Once it's running, you can issue HTTP calls:
```bash
$ curl localhost:5000/restjson
```
```json
{
  "yangforge": {
    "modules": {},
    "features": {
      "express": {
        "name": "express",
        "description": "Fast, unopionated, minimalist web framework (HTTP/HTTPS)"
      },
      "restjson": {
        "name": "restjson",
        "description": "REST/JSON web services interface generator",
        "needs": [
          "express"
        ]
      }
    }
  }
}
```
The `restjson` interface dynamically routes nested module/container hierarchy:
```bash
$ curl localhost:5000/restjson/yangforge/features/restjson
```
```json
{
  "name": "restjson",
  "description": "REST/JSON web services interface generator",
  "needs": [
    "express"
  ]
}
```
You can also dynamically `--compile` a YANG schema **file** and `run` it immediately:
```bash
$ yfc run -p 5050 -c examples/jukebox.yang
express: listening on 5050
restjson: binding forgery to /restjson
```
Once it's running, you can issue HTTP calls:
```bash
$ curl localhost:5050/restjson/example-jukebox
```
```json
{
  "jukebox": {
    "library": {
      "artist": []
    },
    "player": {},
    "playlist": []
  }
}
```

## Using YangForge Programmatically (Advanced)

```coffeescript
Forge = require 'yangforge'
module.exports = Forge.new module
```

### Key Features

* **Parse** YANG schema files and generate runtime JavaScript semantic object tree hierarchy
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
([yangforge.yang](./yangforge.yang)) **compiled** module. It is
compiled by the [yang-compiler](src/compiler/compiler.litcoffee) and
natively includes
[yang-v1-extensions](yang_modulesyang-v1-extensions) submodule for
supporting the version 1.0 YANG RFC specifications. It serves as a
good reference for writing new compilers, custom extensions, custom
importers, among other things.

### Programmatic Usage Examples

The below examples can be executed using CoffeeScript REPL by running
`coffee` at the command-line from the top-directory of this repo.

Using the native YangForge instance:
```coffeescript
Forge = require 'yangforge'

schema = """
  module hello-world {
    description "a test";
    leaf hello { type string; default "world"; }
  }
  """
  
forgery = new Forge
HelloWorld = forgery.compile schema
test = new HelloWorld
console.log test.get 'hello'
test.set 'hello', 'there'
console.log test.get 'works'
```

Forging a new module for build/publish (at a new package directory, see also [complex-types](yang_modules/complex-types)):
```coffeescript
Forge = require 'yangforge'
module.exports = Forge.new module,
  before: ->
    // series of before-compile operations
  after: ->
    // series of after-compile operations
```

Forging a new interface generator (see also [cli example](src/features/cli.coffee)):
```coffeescript
Forge = require 'yangforge'
module.exports = Forge.Interface 
  name: 'some-new-interface'
  description: 'Some new awesome interface'
  generator: ->
    // code logic to dynamically construct a new interface based on passed-in context
    // this = an instance of Forge
    console.log this
```

There are many other ways of interacting with the module's class
object as well as the instantiated class.  More examples coming soon.

## Literate CoffeeScript Documentation

The source code is documented in Markdown format. It's code combined
with documentation all-in-one.

* [YangForge](src/yangforge.coffee)
  * [Compiler](src/compiler/compiler.litcoffee)
  * [Compiler Mixin](src/compiler/compiler-mixin.litcoffee)
  * [Features](src/features)
* [YangForge Schema](./yangforge.yang)
* [Yang v1.0 Extensions](yang_modules/yang-v1-extensions)
* External Dependencies
  * [data-synth library](http://github.com/saintkepha/data-synth)

## License
  [MIT](LICENSE)

[npm-image]: https://img.shields.io/npm/v/yangforge.svg
[npm-url]: https://npmjs.org/package/yangforge
[downloads-image]: https://img.shields.io/npm/dm/yangforge.svg
[downloads-url]: https://npmjs.org/package/yangforge
