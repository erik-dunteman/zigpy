from MyStruct import MyStruct


my_struct = MyStruct()
print("my_struct", my_struct)
print("Default values:")
print("a", my_struct.a)
print("b", my_struct.b)
my_struct.print()

print("\nSetting values:")
my_struct.a = 10
my_struct.b = 20
print("a", my_struct.a)
print("b", my_struct.b)
my_struct.print()
my_struct.print_pystring("testing func args")

sum = my_struct.sum()
print("sum", sum)

static_str = my_struct.get_static_str()
print("static_str", static_str)