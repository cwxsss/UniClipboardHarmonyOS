@echo off
if "%OHOS_NATIVE_HOME%"=="" (
  echo OHOS_NATIVE_HOME is required. 1>&2
  exit /b 2
)
"%OHOS_NATIVE_HOME%\llvm\bin\clang++.exe" -target aarch64-linux-ohos --sysroot="%OHOS_NATIVE_HOME%\sysroot" -D__MUSL__ %*
