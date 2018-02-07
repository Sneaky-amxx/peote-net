haxe cli.hxml

if not exist bin mkdir bin

copy build\neko\peote-net-test.n bin\peote-net-test.n
@echo off
REM creates (clickable;) batch files to start servers and clients
(
  echo neko peote-net-test.n -s 1
  echo pause
) > bin\neko_server.bat
(
  echo neko peote-net-test.n -c 1
  echo pause
) > bin\neko_client.bat
@echo on

copy build\cpp\MainCli.exe bin\peote-net-test.exe
@echo off
REM creates (clickable;) batch files to start servers and clients
(
  echo peote-net-test.exe -s 1
  echo pause
) > bin\server.bat
(
  echo peote-net-test.exe -c 1
  echo pause
) > bin\client.bat
@echo on

pause