# Autogenerated Python bindings for MyStruct
# Do not edit this file directly

from ctypes import CDLL, Structure, POINTER, c_int

libzigpy = CDLL("./zig-out/lib/libzigpy.dylib")

# Public class
class MyStruct(Structure):
    _fields_ = [("a", c_int), ("b", c_int), ]

# Shared Library Function interfaces
libzigpy.codegenstruct_sum.argtypes = [c_int, c_int, ]

