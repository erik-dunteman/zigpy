- for any given zig type, we need
  - the equivalent type in python ctypes
  - the equivalent type in python primative
  - conversion function ctype to python primative


zig struct is exposed
users need to
- instanatiate it from python
- delete it from python
- access and write its attributes (effectively as getters/setters)
- run its methods

init is a special case where users must express as function (no self)
del is a pure method
attribute getters/setters are simple methods
methods are methods

in all cases, we're running some function/method with param types and return types
those types can be zig primative or complex

for every native zig primative arg, here's how we get there
- users call python class method with python native equivalent (1).
- that python native equivalent is optionally converted(*) to a c_type if that c_type isn't a 1:1 mapping.
- the c_type (2) is passed into libzigpy, which is configured to expect it

* conversion between src py type and dest c_type type can be a separate table

in zig native, we run method, then:
- return type returned as c_type (1) from libzigpy, which is configured to expect it as res type. we're now in python class method again.
- that c_type is optionally converted(*) to a py type if there isn't a 1:1 mapping.
- the python native equivalent(2) is returned to user

TLDR each zig type also has a:
- c_type: this is absolute: there's one correct c_type for each zig type
- py_type: this is subjective, for example if zig expects []const u8, does it want bytes or do we convert to string?

ideas:
- can we do literal type mappings (zig type to c_type) for all native zig types
- add special Zig types for things like Strings. These wrap the C callconv type to funnel via a known c_type, but are somehow tagged with extra data carrying c_type->py and py->c_type mappings


zigpy types are:
- structs, with a "value" that is a primative types that do clearly map to c_type
- follows interface:
  - toCType() is a stringified python func to be executed by python
  - fromCType() is a stringified python func to be executed by python

tried: type alias, but the type gets erased. annoying thing about struct approach is users can't return it outright since c callconv won't work. though export struct could maybe generate wrapper funcs to extract inner values. or make extern struct, generate python struct with _fields_ = ["value", value_ctype], argtype/restype is that generated type, pull value as conversion func. See MyStructProto.py

workflow would be like:
- scan types
- for args
  - switch type
  - if native zig type:
    - get equiv c_type
    - py_type = c_type
    - generate 
      - libzigpy.argtypes = [c_type]
      - function signature (arg_name: py_type)
      - no conversion func
      - pass arg_name into libzigpy
  - if special zigpy type
    - ...
- for response
  - switch type
  - if native zig type
    - ...
  - if special zigpy type:
    - it's an extern struct so callconv will work
    - get equiv c_type for .value
    - get equiv py_type for c_type
    - get conversion_func with .fromCType
    - generate
      - class _ZigPyType(Structure):\n\t_fields_ = [("value", c_type)] # for example class _PyString with value c_char_py
      - libzigpy.restype = _PyString
      - function signature returns py_type
      - get c_res_wrapped from libzigpy
      - c_res = c_res_wrapped.value # since is a _ZigPyType it will have a .value
      - res = exec(c_res_wrapped.fromCType()(res)) # kinda sketch but we execute stringified conversion func from zig to avoid templating it in. actually scratch that, do itt right. about to land so can;t fix now