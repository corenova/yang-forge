# YangForge CLI Examples

The following guide provides walkthrough on various commands available
using the `yfc` command-line-interface utility. The example modules
and schema used can be all found within this directory.

## Using the `schema` command
```
$ yfc schema -h

  Usage: schema [options] [file]

  process a specific YANG schema file or string

  Options:

    -h, --help                                 output usage information
    -c, --compile                              perform compile operation on the input
    -e, --eval [textarea]                      pass a string from the command line as input
    -o, --output [string]                      set the output filename for generated result
    -f, --format [yaml|json|tree|yang|pretty]  specify output format (default: pretty)
    -s, --space [uint8]                        number of spaces to use for JSON output (default: 2)
    -x, --encoding [base64|utf8|gzip]          specify output data encoding (default: utf8)
    -I, --include [path]                       add directory to compiler search path
    -L, --link [path]                          add directory to linker search path
```

You can `--eval` a YANG schema **string** directly for dynamic parsing:
```
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
```
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

The `schema` command by default performs `preprocess` on the passed in
schema content (string or file).  The utility will retrieve any
`include/import` statements found within the schema and perform all
schema manipulations such as *grouping*, *uses*, *refine*, *augment*,
etc. Basically, it will flag any validation errors while producing an
output that should represent what the schema would look like just
before `compile`.

If you run the command with `--compile`, the utility will attempt to
construct an active instance for elements with `construct` handler. If
any errors occur during *construction* it will be flagged and when
successfully compiled, it will produce an output which will be ready
for direct instantiation without further compilation by `yfc`.

## Using the `run` command

The real power of `YangForge` is actualized when modules are run using
one or more **dynamic interface generators**.

```
$ yfc run -h

  Usage: run [options] [module...]

  runs one or more core(s) and module(s)

  Options:

    -h, --help          output usage information
    --express [uint16]  enables express web server on a specified port (default: 5000)
    --restjson          enables REST/JSON interface (default: true)
    --websocket         enables socket.io interface (default: false)
```

### Running a dynamically *compiled* schema instance

You can `run` a YANG schema **file** and instantiate it immediately:
```bash
$ yfc run example/jukebox.yang
running in development mode
express: listening on 5000
generating REST/JSON interface...
restjson generation complete
restjson: binding to /restjson
running with: synthesizer,yang-forge-core,example-jukebox
```
Once it's running, you can issue HTTP calls:
```bash
$ curl localhost:5000/restjson/example-jukebox
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

The `restjson` interface dynamically routes nested module/container hierarchy:
```bash
$ curl localhost:5000/restjson/example-jukebox/jukebox/library
```
```json
{
  "artist": []
}
```

### Running a *forged* module

You can run a *forged* module (packaged with code behaviors) as follows:
```bash
$ yfc run examples/ping
express: listening on 5000
restjson: binding forgery to /restjson
```

The example `ping` module for this section is available
[here](ping.yaml). It is based on
[ping.yang](ping.yang) YANG schema.

Once it's running, you can issue HTTP REPORT call to discover
capabilities of the [ping](ping.yaml) module:
```bash
$ curl -X REPORT localhost:5000/restjson/ping
```
```json
{
  "name": "ping",
  "description": "An example ping module from ODL",
  "license": "MIT",
  "keywords": [
    "yangforge",
    "ping",
    "example"
  ],
  "schema": {
    "prefix": "ping",
    "namespace": "urn:opendaylight:ping",
    "revision": {
      "2013-09-11": {
        "description": "TCP ping module"
      }
    },
    "import": {
      "ietf-inet-types": {
        "prefix": "inet"
      }
    }
  },
  "operations": {
    "send-echo": "Send TCP ECHO request"
  }
}
```
You can get usage info on an available RPC call with OPTIONS:
```bash
$ curl -X OPTIONS localhost:5000/restjson/ping/send-echo
```
The below output provides details on the expected
`input/output` schema for invoking the RPC call.
```json
{
  "POST": {
    "description": "Send TCP ECHO request",
    "input": {
      "leaf": {
        "destination": {
          "type": "inet:ipv4-address"
        }
      }
    },
    "output": {
      "leaf": {
        "echo-result": {
          "type": {
            "enumeration": {
              "enum": {
                "reachable": {
                  "value": 0,
                  "description": "Received reply"
                },
                "unreachable": {
                  "value": 1,
                  "description": "No reply during timeout"
                },
                "error": {
                  "value": 2,
                  "description": "Error happened"
                }
              }
            }
          },
          "description": "Result types"
        }
      }
    }
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
As you would expect, it will also perform *validations* for the input based on `inet:ipv4-address` definition:

```bash
$ curl -X POST localhost:5000/restjson/ping/send-echo -H 'Content-Type: application/json' -d '{ "destination": "abcdefg" }'
```
```json
{
  "error": "AssertionError: unable to validate passed-in 'abcdefg' as 'inet:ipv4-address'"
}
```

### Running `YangForge` natively as a stand-alone instance

When you issue `run` without any target module(s) as argument, it runs
the internal `yang-forge-core` module using defaults:

```bash
$ yfc run
express: listening on 5000
restjson: binding forgery to /restjson
```

Once it's running, you can inquire about its capabilities by issuing
HTTP REPORT call (similar output available via CLI using `yfc info`):

```bash
$ curl -X REPORT localhost:5000/restjson/yang-forge-core
```
```json
{
  "name": "yang-forge-core",
  "description": "YANG driven JS application builder",
  "license": "Apache-2.0",
  "keywords": [
    "build",
    "config",
    "datastore",
    "datamodel",
    "forge",
    "model",
    "yang",
    "opnfv",
    "parse",
    "restjson",
    "restconf",
    "rpc",
    "translate",
    "yang-json",
    "yang-yaml",
    "yfc"
  ],
  "schema": {
    "prefix": "yf",
    "description": "This module provides YANG v1 language based schema compilations.",
    "revision": {
      "2015-09-23": {
        "description": "Enhanced with 0.10.x functionality"
      },
      "2015-05-04": {
        "description": "Initial revision",
        "reference": "RFC-6020"
      }
    },
    "organization": "ClearPath Networks NFV R&D Group",
    "contact": "Web:  <http://www.clearpathnet.com>\nCode: <http://github.com/clearpath-networks/yangforge>\n\nAuthor: Peter K. Lee <mailto:plee@clearpathnet.com>",
    "include": "yang-v1-extensions"
  },
  "features": {
    "cli": "When enabled, generates command-line interface for the module",
    "express": "When enabled, generates HTTP/HTTPS web server instance for the module",
    "restjson": "When enabled, generates REST/JSON web services interface for the module"
  },
  "operations": {
    "build": "package the application for deployment",
    "deploy": "deploy application into yangforge endpoint",
    "info": "shows info about a specific module",
    "publish": "publish package to upstream registry",
    "run": "runs one or more modules and/or schemas",
    "schema": "process a specific YANG schema file",
    "sign": "sign package to ensure authenticity",
    "enable": "enables passed-in set of feature(s) for the current runtime",
    "disable": "disables passed-in set of feature(s) for the current runtime",
    "infuse": "absorb requested target module(s) into current runtime",
  }
}
```

There are now a handful of *new operations* available in the context
of the `express/restjson` interface that was previously hidden in the
`cli` interface.

The `enable/disable` operations allow runtime control of various
features to be toggled on/off. Additionally, by utilizing
`infuse/defuse` operations, you can **dynamically** load/unload
modules into the runtime context. This capability allows the
`yangforge` instance to operate as an agent which can run any
*arbitrary* schema/module instance on-demand. 

Now with the `0.10.x` remote import features, you can dynamically
`infuse` any YAML/YANG into a running `yangforge` instance without any
package download/install into filesystem nor any restart of the
running process.

The `run` command internally utilizes the `infuse` operation to
instantiate the initial running process.

