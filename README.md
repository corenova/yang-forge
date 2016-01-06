# yangforge -- forge YANG modules to compose apps

[![Join the chat at https://gitter.im/saintkepha/yangforge](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/saintkepha/yangforge?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

`yfc` is the command shell for the YangForge framework, providing
schema-driven application lifecycle management.

`YangForge` provides runtime JavaScript execution based on YANG schema
modeling language as defined in IETF drafts and standards
([RFC 6020](http://tools.ietf.org/html/rfc6020)).

  [![NPM Version][npm-image]][npm-url]
  [![NPM Downloads][downloads-image]][downloads-url]
  
  [![NPM][history-image]][history-url]

Basically, the framework enables YANG schema language to *become* a
**programming** language.

It also utilizes YAML with custom tags to construct a portable module
with embedded code.

It is written primarily using [CoffeeScript](http://coffeescript.org)
and runs on [Node.js](http://nodejs.org) and the **web browser** (yes, it's isomorphic).

This software is **sponsored** by
[ClearPath Networks](http://www.clearpathnet.com) on behalf of the
[OPNFV](http://opnfv.org) (Open Platform for Network Functions
Virtualization) community. For a reference implementation created entirely utilizing `YangForge`, please take a look at [OPNFV Promise](http://github.com/opnfv/promise) which provides future resource/capacity management (reservations/allocations) for virtualized infrastructure.

Please note that this project is under **active development**. Be sure
to check back often as new updates are being pushed regularly.

## Installation
```bash
$ npm install -g yangforge
```

You must have `node >= 0.10.28` as a minimum requirement to run
`yangforge`.

## Usage
```
  Usage: yfc [options] [command]


  Commands:

    build [options] [file]      package the application for deployment
    config                      manage yangforge service configuration (planned)
    deploy                      deploy application into yangforge endpoint (planned)
    info [options] [name]       shows info about a specific module
    publish [options]           publish package to upstream registry (planned)
    run [options] [modules...]  runs one or more modules and/or schemas
    schema [options] [file]     process a specific YANG schema file or string
    sign                        sign package to ensure authenticity (planned)

  YANG driven JS application builder

  Options:

    -h, --help     output usage information
    -V, --version  output the version number
    --no-color     disable color output
```

The `yfc` command-line interface is **runtime-generated** according to
[yangforge.yang](yangforge.yang) schema definitions.  Please refer to
the schema section covering various `rpc` extension statements and
sub-statement definitions for a reference regarding different types of
command-line arguments, descriptions, and options processing syntax.
The corresponding **actions** for each of the `rpc` extensions are
implemented inside the `YangForge` YAML module
[package.yaml](package.yaml).

For comprehensive **usage documentation** around various CLI commands,
please refer to the [YangForge Examples README](examples#readme).

## Troubleshooting

When you encounter errors or issues while utilizing the `yfc` command
line utility, you can set ENVIRONMENTAL variable `yfc_debug=1` to get
complete debug output of the `YangForge` execution log.

```bash
$ yfc_debug=1 yfc <some-command>
```

The output generated is very verbose and may or may not assist you in
determining the root cause. However, when reporting an issue into the
Github repository, it will be helpful to paste a snippet of the debug
output for quicker resolution by the project maintainer.

## Bundled YANG schema modules

There are a number of YANG schema modules commonly referenced and
utilized by other YANG modules during schema definition and they have
been *bundled* together into the `yangforge` package for convenience.
All you need to do is to `import <module name>` from your YANG schema
and they will be retrieved/resolved automatically.

name | description | reference
--- | --- | ---
[complex-types](core/complex-types.yang) | extensions to model complex types and typed instance identifiers | RFC-6095
[iana-crypt-hash](core/iana-crypt-hash.yang) | typedef for storing passwords using a hash function | RFC-7317
[ietf-inet-types](core/ietf-inet-types.yang) | collection of generally useful types for Internet addresses | RFC-6991
[ietf-yang-types](core/ietf-yang-types.yang) | collection of generally useful derived data types | RFC-6991

Additional YANG modules will be bundled into the `yangforge` package
over time. Since `yangforge` facilitate *forging* of new YANG modules
and easily using them in your own projects, only industry standards
based YANG schema modules will be considered for native bundling at
this time.

## Bundled YANG features

name | description | dependency
--- | --- | ---
[cli](features/cli.coffee) | generates command-line interface | none
[express](features/express.coffee) | generates HTTP/HTTPS web server instance | none
[restjson](features/restjson.coffee) | generates REST/JSON web services interface | express
[websocket](features/websocket.coffee) | generates socket.io interface | express

You can click on the *name* entry above for reference documentation on
each feature module.

## Using YangForge Programmatically

```coffeescript
forge = require 'yangforge'
forge.import 'my-cool-schema.yang'
.then (app) ->
  console.log app.info()
```

### Key Features

* **Parse** YAML/YANG/JSON schema files and generate runtime
  JavaScript semantic object tree hierarchy
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

[YangForge](src/forge.coffee) itself is also a YANG schema
([yangforge.yang](./yangforge.yang)) **compiled** module. It is
compiled by the [yang-compiler](src/compiler.litcoffee) and
natively includes
[yang-v1-extensions](core/yang-v1-extensions.yaml) submodule for
supporting the YANG version 1.0
([RFC 6020](http://tools.ietf.org/html/rfc6020)) specifications.
Please reference the
[yang-v1-extensions documentation](core/yang-v1-extensions.md) for
up-to-date info on YANG 1.0 language coverage status. It serves as a
good reference for writing new compilers, custom extensions, custom
typedefs, among other things.

### Primary interfaces

name | description
--- | ---
forge.import     | local/remote async loading of one or more modules using filenames
forge.load       | local async/sync loading of module(s), only one-at-a-time with sync
forge.compile    | local sync compilation of a module, generates class obj that can be instantiated
forge.preprocess | local sync preprocessing of a module, constraint validations, schema manipulations
forge.parse      | local sync parsing of a module, syntax validations, custom-tag resolutions

### Programmatic Usage Examples

The below examples can be executed using CoffeeScript REPL by running
`coffee` at the command-line from the top-directory of this repo.

Using the native YangForge module as a library:

```coffeescript
forge = require 'yangforge'

yang = """
  module hello-world {
    description "a test";
    leaf hello { type string; default "world"; }
  }
  """

# asynchronous load YANG schema
forge.load schema: yang
.then (app) ->
  console.log app.get 'hello-world.hello'
  app.set 'hello-world.hello', 'goodbye'
  console.log app.get()

# synchronous load YANG schema
app = forge.load schmea: yang, async: false
console.log app.info format: 'json'

# compile YANG schema model as class object
HelloWorld = forge.compile schema: yang
hello = new HelloWorld 'hello-world': hello: 'howdy there'
console.log hello.get()

yaml = """
  name: hello
  schema: !yang |
    module embedded-world { leaf wow { type number; default 0; } }
  config: !json |
    { "embedded-world": { "wow": 2 } }
  """

# it can do YAML quite well
forge.load yaml
.then (app) ->
  console.log app.get()

# sometimes you just want to preprocess to see what it becomes
console.log forge.preprocess yaml
```

Forging a new module/application for build/publish using YAML
(see also [complex-types](core/complex-types.yaml)):
```coffeescript
name: some-new-application
schema: !yang some-new-application.yang
rpc:
  something-useful: !coffee/function
    (input, output, done) ->
	  console.log input.get()
	  output.set 'important data'
	  done()
```

Forging a new interface generator using YAML (see also
[cli example](features/cli.yaml)):
```yaml
name: some-new-interface
description: Some new awesome interface
run: !coffee/function
  (model, options) ->
    # code logic to dynamically construct a new interface based on passed-in context
    console.log model
```

There are many other ways of interacting with the module's class
object as well as the instantiated class.

**More examples coming soon!**

## Literate CoffeeScript Documentation

The source code is documented in Markdown format. It's code combined
with documentation all-in-one.

* [YangForge](src/forge.coffee)
  * [Compiler](src/compiler.litcoffee)
  * [Features](features)
  * [Module](package.yaml)
  * [Schema](yangforge.yang)
* External Dependencies
  * [data-synth library](http://github.com/saintkepha/data-synth)
  * [js-yaml library](https://github.com/nodeca/js-yaml)
  * [yang-parser library](https://gitlab.labs.nic.cz/labs/yang-tools/wikis/coffee_parser)

## License
  [Apache 2.0](LICENSE)

[npm-image]: https://img.shields.io/npm/v/yangforge.svg
[npm-url]: https://npmjs.org/package/yangforge
[downloads-image]: https://img.shields.io/npm/dm/yangforge.svg
[downloads-url]: https://npmjs.org/package/yangforge
[history-image]: https://nodei.co/npm-dl/yangforge.png?height=3
[history-url]: https://nodei.co/npm/yangforge
