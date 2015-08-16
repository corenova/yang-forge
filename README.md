# yfc -- YangForge Controller

`yfc` is the command shell for the YangForge framework, providing
schema-driven application lifecycle management.

`YangForge` provides runtime JavaScript execution based on YANG schema
modeling language as defined in IETF drafts and standards
([RFC 6020](http://tools.ietf.org/html/rfc6020)).

Basically, the framework enables YANG schema language to *become* a
**programming** language.

It is written primarily using [CoffeeScript](http://coffeescript.org)
and runs on [Node.js](http://nodejs.org).

This software is **sponsored** by
[ClearPath Networks](http://www.clearpathnet.com) on behalf of the
[OPNFV](http://opnfv.org) (Open Platform for Network Functions
Virtualization) community.

  [![NPM Version][npm-image]][npm-url]
  [![NPM Downloads][downloads-image]][downloads-url]

## Installation
```bash
$ npm install -g yangforge
```

You must have `node >= 0.10.3` and `npm >= 2.0` as minimum
requirements to run `yangforge`.

## Usage
```
  Usage: yfc [options] [command]


  Commands:

    build [options] [name...]       package the application for deployment (planned)
    config                          manage application configuration data (planned)
    deploy                          deploy application into yangforge endpoint (planned)
    info [options] [name...]        show info about one or more packages
    init                            initialize package configuration
    install [options] [package...]  install one or more packages
    list [options] [package...]     list installed packages
    publish [options]               publish package to upstream registry (planned)
    run [options] [module...]       runs one or more modules and/or schemas
    schema [options]                process YANG schema files
    sign                            sign package to ensure authenticity (planned)
    *                               specify a target module to run command-line interface

  YANG driven JS application builder

  Options:

    -h, --help     output usage information
    -V, --version  output the version number
    --no-color     disable color output
```

The `yfc` command-line interface is **runtime-generated** according to
[yangforge.yang](./yangforge.yang) schema definitions.  Please refer
to the schema section covering various `rpc` extension statements and
sub-statement definitions for a reference regarding different types of
command-line arguments, descriptions, and options processing syntax.
The corresponding **actions** for each of the `rpc` extensions are
implemented inside the `YangForge` module forging before-hook
[here](src/yangforge.coffee).

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
$ yfc schema -e 'module hello-world { description "a test"; leaf hello { type string; default "world"; } }'
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
$ yfc schema -e 'module hello-world { description "a test"; leaf hello { type string; default "world"; } }' -f json
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
modules are run using one or more **dynamic interface
generators**.

```bash
$ yfc run -h

  Usage: run [options] [module...]

  runs one or more modules and/or schemas

  Options:

    -h, --help          output usage information
    --cli               enables commmand-line-interface
    --express [number]  enables express web server on a specified port (default: 5000)
    --restjson          enables REST/JSON interface (default: true)
    --autodoc           enables auto-generated documentation interface (default: false)
```

#### Built-in interface generators

name | description | dependency
--- | --- | ---
[cli](src/features/cli.litcoffee) | generates command-line interface | none
[express](src/features/express.litcoffee) | generates HTTP/HTTPS web server instance | none
[restjson](src/features/restjson.litcoffee) | generates REST/JSON web services interface | express
[autodoc](src/features/autodoc.litcoffee) | generates self-documentation interface | express

You can click on the *name* entry above for reference
documentation on each interface feature.

#### Running `YangForge` natively

When you issue `run` without any target module(s) as argument, it runs
the internal `YangForge` module using defaults:
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
    "runtime": {
      "features": [
        {
          "cli": false
        },
        {
          "name": "express",
          "description": "Fast, unopionated, minimalist web framework (HTTP/HTTPS)"
        },
        {
          "name": "restjson",
          "description": "REST/JSON web services interface generator",
          "needs": [
            "express"
          ]
        }
      ],
      "modules": []
    }
  }
}
```

#### Running dynamically *compiled* schema instance

You can also dynamically `run` a YANG schema **file** and instantiate it immediately:
```bash
$ yfc run examples/jukebox.yang
express: listening on 5000
restjson: binding forgery to /restjson
```
Once it's running, you can issue HTTP calls:
```bash
$ curl localhost:5000/restjson/example-jukebox
```
```json
{
  "example-jukebox": {
    "jukebox": {
      "library": {
        "artist": []
      },
      "player": {},
      "playlist": []
    }
  }
}
```

The `restjson` interface dynamically routes nested module/container hierarchy:
```bash
$ curl localhost:5000/restjson/example-jukebox/jukebox
```
```json
{
  "library": {
    "artist": []
  },
  "player": {},
  "playlist": []
}
```

#### Running a *yangforged* module

You can also run a separate *forged* module as follows:
```bash
$ yfc run examples/ping
express: listening on 5000
restjson: binding forgery to /restjson
```
The example `ping` module for this section is available [here](examples/ping).

Once it's running, you can issue HTTP OPTIONS call to discover
capabilities of the [ping](examples/ping) module:
```bash
$ curl -X OPTIONS localhost:5000/restjson/ping
```
```json
{
  "metadata": {
    "name": "ping",
    "description": "an example ping yangforged module",
    "version": "1.0.0",
    "schema": {
      "name": "ping",
      "prefix": "ping",
      "namespace": "urn:opendaylight:ping",
      "revision": {
        "2013-09-11": {
          "description": "TCP ping module"
        }
      }
    },
    "license": "MIT",
    "author": "Peter Lee <peter@intercloud.net>",
    "keywords": [
      "yangforge",
      "ping"
    ],
    "dependencies": [
      "yangforge"
    ],
    "exports": {
      "extension": 63,
      "rpc": [
        "send-echo"
      ]
    }
  },
  "rpc": {
    "send-echo": "Send TCP ECHO request"
  }
}
```
You can also specifically get more info on an available RPC call:
```bash
$ curl -X OPTIONS localhost:5000/restjson/ping/send-echo
```
The below output provides additional information on what the expected
`input/output` schema for invoking the RPC call.
```json
{
  "metadata": {
    "name": "send-echo",
    "description": "Send TCP ECHO request"
  },
  "input": {
    "leaf": {
      "destination": {
        "type": "inet:ipv4-address"
      }
    },
    "yang": "input"
  },
  "output": {
    "leaf": {
      "echo-result": {
        "type": {
          "enumeration": {
            "enum": {
              "reachable": {
                "value": "0",
                "description": "Received reply"
              },
              "unreachable": {
                "value": "1",
                "description": "No reply during timeout"
              },
              "error": {
                "value": "2",
                "description": "Error happened"
              }
            }
          }
        },
        "description": "Result types"
      }
    },
    "yang": "output"
  }
}
```
You can then try out the available RPC call as follows:
```bash
$ curl -X POST localhost:5000/restjson/ping/send-echo -H 'Content-Type: application/json' -d '{ "destination": "8.8.8.8" }'
```
```json
{
  "echo-result": "reachable"
}
```

#### Running *arbitrary* mix of modules

The `run` command allows you to pass in as many modules you want to
instantiate. The following example will also *listen* on a different
port.
```bash
$ yfc run examples/jukebox.yang examples/ping
express: listening on 5000
restjson: binding forgery to /restjson
```

Once it's running, you can check out all of the capabilites of the
current runtime *yangforge* instance:
```bash
$ curl -X OPTIONS localhost:5000/restjson
```
```json
{
  "metadata": {
    "name": "yangforge",
    "description": "YANG driven JS application builder",
    "version": "0.9.11",
    "schema": {
      "name": "yangforge",
      "prefix": "yf",
      "description": "This module provides YANG v1 language based schema compilations.",
      "revision": {
        "2015-05-04": {
          "description": "Initial revision",
          "reference": "RFC-6020"
        }
      },
      "organization": "ClearPath Networks NFV R&D Group",
      "contact": "Web:  <http://www.clearpathnet.com>\nCode: <http://github.com/clearpath-networks/yangforge>\n\nAuthor: Peter K. Lee <mailto:plee@clearpathnet.com>"
    },
    "license": "Apache-2.0",
    "author": {
      "name": "Peter Lee",
      "email": "peter@intercloud.net"
    },
    "homepage": "https://github.com/opnfv/yangforge",
    "keywords": [
      "build",
      "config",
      "datastore",
      "datamodel",
      "forge",
      "model",
      "yang",
      "restjson",
      "restconf",
      "rpc",
      "parse",
      "translate",
      "yang-json",
      "yang-yaml",
      "yfc"
    ],
    "dependencies": [
      "body-parser",
      "clim",
      "colors",
      "commander",
      "data-synth",
      "errorhandler",
      "express",
      "passport",
      "prettyjson",
      "promise",
      "yang-parser",
      "yang-v1-extensions",
      "complex-types"
    ],
    "exports": {
      "extension": 63,
      "feature": [
        "cli",
        "express",
        "restjson"
      ],
      "grouping": [
        "compiler-rules",
        "meta-module",
        "cli-command",
        "unique-element"
      ],
      "rpc": [
        "build",
        "config",
        "deploy",
        "info",
        "init",
        "install",
        "list",
        "publish",
        "run",
        "schema",
        "sign",
        "enable",
        "import",
        "export"
      ]
    }
  },
  "modules": {
    "example-jukebox": {
      "metadata": {
        "name": "example-jukebox",
        "prefix": "jbox",
        "namespace": "http://example.com/ns/example-jukebox",
        "description": "Example Jukebox Data Model Module",
        "revision": {
          "2015-04-04": {
            "description": "Initial version.",
            "reference": "example.com document 1-4673"
          }
        },
        "organization": "Example, Inc.",
        "contact": "support at example.com"
      },
      "rpc": {
        "play": "Control function for the jukebox player"
      }
    },
    "ping": {
      "metadata": {
        "name": "ping",
        "description": "an example ping yangforged module",
        "version": "1.0.0",
        "schema": {
          "name": "ping",
          "prefix": "ping",
          "namespace": "urn:opendaylight:ping",
          "revision": {
            "2013-09-11": {
              "description": "TCP ping module"
            }
          }
        },
        "license": "MIT",
        "author": "Peter Lee <peter@intercloud.net>",
        "keywords": [
          "yangforge",
          "ping"
        ],
        "dependencies": [
          "yangforge"
        ],
        "exports": {
          "extension": 63,
          "rpc": [
            "send-echo"
          ]
        }
      },
      "rpc": {
        "send-echo": "Send TCP ECHO request"
      }
    }
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
[yang-v1-extensions](yang/yang-v1-extensions) submodule for
supporting the YANG version 1.0
([RFC 6020](http://tools.ietf.org/html/rfc6020)) specifications.
Please reference the
[yang-v1-extensions](yang/yang-v1-extensions) module for
up-to-date info on YANG 1.0 language coverage status. It serves as a
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

Forging a new module for build/publish (at a new package directory,
see also [complex-types](yang/complex-types)):
```coffeescript
Forge = require 'yangforge'
module.exports = Forge.new module,
  before: ->
    # series of before-compile operations
  after: ->
    # series of after-compile operations
```

Forging a new interface generator (see also
[cli example](src/features/cli.coffee)):
```coffeescript
Forge = require 'yangforge'
module.exports = Forge.Interface 
  name: 'some-new-interface'
  description: 'Some new awesome interface'
  generator: ->
    # code logic to dynamically construct a new interface based on passed-in context
    # this = an instance of Forge
    console.log this
```

There are many other ways of interacting with the module's class
object as well as the instantiated class.

**More examples coming soon!**

## Literate CoffeeScript Documentation

The source code is documented in Markdown format. It's code combined
with documentation all-in-one.

* [YangForge](src/yangforge.coffee)
  * [Compiler](src/compiler/compiler.litcoffee)
  * [Compiler Mixin](src/compiler/compiler-mixin.litcoffee)
  * [Features](src/features)
* [YangForge Schema](./yangforge.yang)
* [Yang v1.0 Extensions](yang/yang-v1-extensions)
* External Dependencies
  * [data-synth library](http://github.com/saintkepha/data-synth)

## License
  [Apache 2.0](LICENSE)

[npm-image]: https://img.shields.io/npm/v/yangforge.svg
[npm-url]: https://npmjs.org/package/yangforge
[downloads-image]: https://img.shields.io/npm/dm/yangforge.svg
[downloads-url]: https://npmjs.org/package/yangforge
