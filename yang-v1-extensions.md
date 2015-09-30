# YANG version 1.0 extensions module

This module provides YANG schema language extension support for
satisfying the [RFC 6020](http://tools.ietf.org/html/rfc6020)
specifications.

The [YANG schema](yang-v1-extensions.yang) file and the extended
language constraints and various *extension handler* routines inside
[YAML module](yang-v1-extensions.yaml) file are fused together to
construct an importable *yangforged* module.

## Current RFC 6020 Implementation Coverage

The below table provides up-to-date information about various YANG
schema language extensions and associated support within this module.
All extensions are syntactically and lexically processed already, but
the below table provides details on the status of extensions as it
pertains to how it is **processed** by the compiler for implementing
the intended behavior of each extension.

Basically, note that the *unsupported* status below indicates it is
not compliant with expected behavior although it is properly parsed
and processed by the compiler.

extension | behavior | status
--- | --- | ---
anyxml | TBD | unsupported
augment | schema merge | supported
base | TBD | supported
belongs-to | define prefix | supported
bit | TBD | unsupported
case | TBD | unsupported
choice | TBD | unsupported
config | property meta | supported
contact | meta data | supported
container | Forge.Object | supported
default | property meta | supported
description | meta data | supported
deviate | merge/alter | unsupported
deviation | merge/alter | unsupported
enum | property meta | supported
error-app-tag | TBD | unsupported
error-message | TBD | unsupported
feature | module meta | supported
fraction-digits | TBD | unsupported
grouping | define/export | supported
identity | module meta | supported
if-feature | conditional | supported
import | preprocess | supported
include | preprocess | supported
input | rpc schema | supported
key | property meta | supported
leaf | Forge.Property | supported
leaf-list | Forge.List | supported
length | property meta | supported
list | Forge.List | supported
mandatory | property meta | supported
max-elements | property meta | supported
min-elements | property meta | supported
module | Forge.Store | supported
must | conditional | unsupported
namespace | module meta | supported
notification | TBD | unsupported
ordered-by | property meta | unsupported
organization | module meta | supported
output | rpc schema | supported
path | TBD | unsupported
pattern | TBD | supported
position | TBD | unsupported
prefix | module meta | supported
presence | meta data | unsupported
range | property meta | supported
reference | meta data | supported
refine | merge | supported
require-instance | TBD | unsupported
revision | meta data | supported
revision-date | conditional | supported
rpc | Forge.Action | supported
status | meta data | supported
submodule | preprocess | supported
type | property meta | supported
typedef | TBD | supported
unique | property meta | supported
units | property meta | supported
uses | schema merge | supported
value | property meta | supported
when | conditional | unsupported
yang-version | module meta | supported
yin-element | TBD | unsupported
