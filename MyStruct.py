# Autogenerated Python bindings for MyStruct
# Do not edit this file directly

from ctypes import CDLL, Structure, POINTER, c_int, c_void_p, c_char_p

libzigpy = CDLL("./zig-out/lib/libzigpy.dylib")

# Public class
class MyStruct(Structure):
    _fields_ = [("a", c_int), ("b", c_int), ]

# Shared Library Function interfaces
libzigpy.codegenstruct___init__.restype = POINTER(MyStruct)
libzigpy.codegenstruct___del__.argtypes = [POINTER(MyStruct)]
libzigpy.codegenstruct_print.argtypes = [POINTER(MyStruct), ]
libzigpy.codegenstruct_print.restype = c_void_p

libzigpy.codegenstruct_print_pystring.argtypes = [POINTER(MyStruct), c_char_p, ]
libzigpy.codegenstruct_print_pystring.restype = c_void_p

libzigpy.codegenstruct_sum.argtypes = [POINTER(MyStruct), ]
libzigpy.codegenstruct_sum.restype = c_int

libzigpy.codegenstruct_get_static_str.argtypes = [POINTER(MyStruct), ]
libzigpy.codegenstruct_get_static_str.restype = c_char_p

class MyStruct():
  def __init__(self):
    self.ptr = libzigpy.codegenstruct___init__()
  def __del__(self):
    libzigpy.codegenstruct___del__(self.ptr)

  @property
  def a(self):
      return self.ptr.contents.a
  @a.setter
  def a(self, value: int):
      self.ptr.contents.a = value

  @property
  def b(self):
      return self.ptr.contents.b
  @b.setter
  def b(self, value: int):
      self.ptr.contents.b = value

  def print(self):
      return libzigpy.codegenstruct_print(self.ptr)

  def print_pystring(self, arg0: bytes):
      return libzigpy.codegenstruct_print_pystring(self.ptr, arg0)

  def sum(self):
      return libzigpy.codegenstruct_sum(self.ptr)

  def get_static_str(self):
      return libzigpy.codegenstruct_get_static_str(self.ptr)

