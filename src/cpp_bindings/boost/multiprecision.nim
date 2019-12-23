import os

##! Compile time instructions
when defined(windows):
    {.passL: "-L" & os.getEnv("VCPKG_ROOT") & "/installed/x64-windows-static/lib".}
    {.passC: "-std=c++17 -I" & os.getEnv("VCPKG_ROOT") & "/installed/x64-windows-static/include".}
  
when defined(macosx):
    {.passL: "-L" & os.getEnv("VCPKG_ROOT") & "/installed/x64-osx/lib".}
    {.passC: "-std=c++17 -I" & os.getEnv("VCPKG_ROOT") & "/installed/x64-osx/include".}
  
when defined(linux):
    {.passL: "-L" & os.getEnv("VCPKG_ROOT") & "/installed/x64-linux/lib -lfolly -pthread -ldouble-conversion -lglog -lgflags".}
    {.passC: "-std=c++17 -I" & os.getEnv("VCPKG_ROOT") & "/installed/x64-linux/include".}


##! C++ Bindings
const boostHeader = "<boost/multiprecision/cpp_dec_float.hpp>"

type
    TFloat50* {.importcpp"boost::multiprecision::cpp_dec_float_50", header: boostHeader, byref.} = object

proc constructTFloat50*(nb: cstring): TFloat50 {.importcpp: "boost::multiprecision::cpp_dec_float_50(@)", constructor.}
proc convertToStr*(instance: TFloat50): cstring {.importcpp: "#.convert_to<std::string>().data()"}

proc `-`*(lhs: TFloat50, rhs: TFloat50): TFloat50 {.importcpp: "# - #".}
